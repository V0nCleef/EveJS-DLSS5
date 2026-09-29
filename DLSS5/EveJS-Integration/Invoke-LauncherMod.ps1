[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AdapterVersion = '0.5.11'
. (Join-Path $PSScriptRoot 'ReShade-Lists.ps1')
$script:Utf8 = New-Object Text.UTF8Encoding($false)
$script:PackageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$script:OperationClock = [Diagnostics.Stopwatch]::StartNew()
$script:ManagerBudgetMilliseconds = 120000

function Get-PlainPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -match '["\x00-\x1f]') { throw 'A plain absolute path is required.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $volume = [IO.Path]::GetPathRoot($full)
    $cursor = $volume
    foreach ($part in @($full.Substring($volume.Length) -split '[\\/]' | Where-Object { $_ })) {
        $cursor = Join-Path $cursor $part
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Linked path is not a valid private/physical boundary: $cursor" }
    }
    return $full
}

function Read-JsonFile {
    param([string]$Path)
    $path = Get-PlainPath $Path
    $item = Get-Item -LiteralPath $path
    if ($item.PSIsContainer -or $item.Length -gt 1048576) { throw 'JSON input is not a bounded file.' }
    return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $path = Get-PlainPath $Path
    $text = ($Value | ConvertTo-Json -Depth 16) + "`n"
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and [IO.File]::ReadAllText($path) -ceq $text) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    $staged = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($staged,$text,$script:Utf8)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backup=$staged+'.previous'
            try { [IO.File]::Replace($staged,$path,$backup) }
            finally { if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force } }
        } else { [IO.File]::Move($staged,$path) }
    } finally { if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force } }
}

function Read-ClientJournal {
    param([string]$Client)
    $path = Get-PlainPath (Join-Path (Split-Path -Parent $Client) '_evejs\dlss5\install\active-install.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $journal=Read-JsonFile $path
    if ([int]$journal.schemaVersion -ne 5 -or [string]$journal.stateScope -cne 'client' -or
        -not (Get-PlainPath ([string]$journal.clientRoot)).Equals($Client,[StringComparison]::OrdinalIgnoreCase)) { throw 'The DLSS5 journal does not belong to this physical client.' }
    return $journal
}

function Invoke-BinaryManager {
    param([string]$Action,[string]$Client,[string]$EveJS)
    $manager=Get-PlainPath (Join-Path $PSScriptRoot 'Manage-EveJSDLSS5.ps1')
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$manager,
        '-Action',$Action,'-Profile','DLSS5','-ClientRoot',$Client,'-EveJSRootPath',$EveJS,
        '-WorkspaceRoot',(Split-Path -Parent $EveJS))
    # Each argument is bounded plain text without embedded quotes; no shell
    # expression, interpolation, profile script or client executable is used.
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $PSHOME 'powershell.exe'
    $start.Arguments=($arguments | ForEach-Object { '"'+([string]$_).Replace('"','\"')+'"' }) -join ' '
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.WorkingDirectory=$script:PackageRoot
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try {
        # The launcher bounds the whole helper process tree. Leave ten seconds
        # for its correlated reply and use the remaining budget across every
        # manager call; a pinned download alone may take up to 900 seconds.
        $remaining=[int][Math]::Floor($script:ManagerBudgetMilliseconds - $script:OperationClock.Elapsed.TotalMilliseconds - 10000)
        if ($remaining -le 0) { throw "DLSS5 $Action has no time left in the launcher operation." }
        if (-not $process.Start()) { throw 'Could not start the DLSS5 binary manager.' }
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($remaining)) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
            $tail=@($stdout,$stderr) | ForEach-Object {
                if ($_.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion) { [string]$_.Result }
            }
            $tail=$tail -join "`n"
            $tail=($tail -replace '[\x00-\x1f]+',' ').Trim()
            if ($tail.Length -gt 1200) { $tail=$tail.Substring($tail.Length-1200) }
            $detail=if ($tail) { " Last manager output: $tail" } else { '' }
            throw "DLSS5 $Action timed out within the launcher operation budget. Inspect the helper diagnostics; use Recover if an install journal was created.$detail"
        }
        $output=$stdout.GetAwaiter().GetResult()
        $errorText=$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            $details=($output+"`n"+$errorText).Trim()
            if ($details.Length -gt 3000) { $details=$details.Substring($details.Length-3000) }
            throw ("DLSS5 binary manager failed: "+$details)
        }
    } finally { $process.Dispose() }
}

function Read-IniValues {
    param([string]$Path)
    $values=[ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return ,$values }
    $plain=Get-PlainPath $Path
    if ((Get-Item -LiteralPath $plain).Length -gt 1048576) { throw 'ReShade configuration exceeds the import limit.' }
    $section=''
    $sections=@{}
    foreach ($line in [IO.File]::ReadAllLines($plain)) {
        $text=$line.Trim()
        if (-not $text -or $text.StartsWith(';') -or $text.StartsWith('#')) { continue }
        if ($text -match '^\[([^\]]+)\]\s*(?:[;#].*)?$') {
            $section=$Matches[1].Trim()
            if ($sections.ContainsKey($section.ToLowerInvariant())) { throw "Duplicate ReShade section: $section" }
            $sections[$section.ToLowerInvariant()]=$true
            continue
        }
        if ($text -notmatch '^([^=]+)=(.*)$') { throw 'Unsupported ReShade INI line; the original file was preserved.' }
        $key=$Matches[1].Trim()
        $value=$Matches[2].Trim()
        if ($key -match '[\[\]=:;]' -or $section -match '[\[\]=:;]') { throw 'Unsupported ReShade INI key.' }
        $identity=$section.ToLowerInvariant()+"`0"+$key.ToLowerInvariant()
        if ($values.Contains($identity)) { throw "Duplicate ReShade key: [$section] $key" }
        if ($values.Count -ge 480) { throw 'ReShade configuration has too many keys for a safe import.' }
        $parts=if ($section) { @($section,$key) } else { @($key) }
        $values[$identity]=[pscustomobject]@{key=$parts;value=$value}
    }
    return ,$values
}

function Set-PrivateIniValue {
    param($Values,[string]$Section,[string]$Key,[string]$Value,[switch]$Preserve)
    $identity=$Section.ToLowerInvariant()+"`0"+$Key.ToLowerInvariant()
    if ($Preserve -and $Values.Contains($identity)) { return }
    $Values[$identity]=[pscustomobject]@{key=@($Section,$Key);value=$Value}
}

function Get-ProfilePreparation {
    param($Request,[string]$Client)
    if ($null -eq $Request.profile) { throw 'A selected profile is required for private ReShade settings.' }
    $private=Get-PlainPath ([string]$Request.profile.modDataRoot)
    $profileRoot=Get-PlainPath ([string]$Request.profile.root)
    if (-not $private.StartsWith($profileRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Private mod data must stay inside the selected profile.' }
    $shared=Join-Path $Client 'bin64\ReShade.ini'
    $sharedValues=Read-IniValues $shared
    $baseKey="install`0basepath"
    if ($sharedValues.Contains($baseKey) -and $sharedValues[$baseKey].value) { throw 'Shared [INSTALL] BasePath overrides profile isolation; retain that file and resolve this configuration conflict first.' }
    $destination=Join-Path $private 'ReShade.ini'
    $legacy=Get-PlainPath (Join-Path $profileRoot 'DLSS5\ReShade.ini')
    $privateValues=Read-IniValues $destination
    # The settings form can save one field before the first preparation. Merge
    # that draft over legacy values instead of treating a partial file as a
    # completed migration and discarding the remaining preferences.
    $source=if ($privateValues.Contains("addon`0addonpath")) { $destination }
        elseif (Test-Path -LiteralPath $legacy -PathType Leaf) { $legacy } else { $shared }
    $values=Read-IniValues $source
    if (-not $source.Equals($destination,[StringComparison]::OrdinalIgnoreCase)) {
        foreach ($key in @($privateValues.Keys)) { $values[$key]=$privateValues[$key] }
    }
    if ($values.Contains($baseKey) -and $values[$baseKey].value) { throw 'Profile [INSTALL] BasePath conflicts with the private mod directory.' }
    Set-PrivateIniValue $values 'ADDON' 'AddonPath' (Join-Path $Client 'bin64')
    $earlyLoadKey="addon`0loadfromdllmain"
    $earlyLoad=if ($values.Contains($earlyLoadKey)) { [string]$values[$earlyLoadKey].value } else { '' }
    Set-PrivateIniValue $values 'ADDON' 'LoadFromDllMain' (Add-ReShadeListItem $earlyLoad 'renodx-dlss5.addon64')
    Set-PrivateIniValue $values 'RenoDX.DLSS5' 'EnableHooks' '2'
    # Existing/F6-persisted values win over form defaults during first import.
    # An explicit settings Save already writes the new private destination.
    Set-PrivateIniValue $values 'RenoDX.DLSS5' 'NeuralUplift' '1' -Preserve
    $nr=$values["renodx.dlss5`0neuraluplift"].value
    if ($nr -notin @('0','1')) { throw 'NeuralUplift must be 0 or 1; its existing value was preserved.' }
    $presetContributions=@()
    if (-not $source.Equals($destination,[StringComparison]::OrdinalIgnoreCase)) {
        $sourceDirectory=Split-Path -Parent $source
        # Keep relative shader/texture locations meaningful when the INI moves
        # to the generic private directory. Absolute user locations stay exact.
        foreach ($name in @('EffectSearchPaths','TextureSearchPaths')) {
            $identity="general`0"+$name.ToLowerInvariant()
            if ($values.Contains($identity) -and -not $privateValues.Contains($identity)) {
                $paths=@(Split-ReShadeList ([string]$values[$identity].value) | ForEach-Object {
                    $entry=$_.Trim()
                    if ($entry -and -not [IO.Path]::IsPathRooted($entry)) { Join-Path $sourceDirectory $entry } else { $entry }
                })
                $values[$identity].value=(@($paths | ForEach-Object { $_.Replace(',',',,') }) -join ',')
            }
        }
        $presetKey="general`0presetpath"
        if ($values.Contains($presetKey) -and -not $privateValues.Contains($presetKey) -and $values[$presetKey].value) {
            $presetSource=[string]$values[$presetKey].value
            if (-not [IO.Path]::IsPathRooted($presetSource)) { $presetSource=Join-Path $sourceDirectory $presetSource }
            $presetValues=Read-IniValues $presetSource
            $presetContributions=@($presetValues.Values | ForEach-Object { [ordered]@{base='profile';path='ReShadePreset.ini';format='ini';key=@($_.key);value=$_.value} })
            $values[$presetKey].value=Join-Path $private 'ReShadePreset.ini'
        }
    }
    $contributions=@($values.Values | ForEach-Object { [ordered]@{base='profile';path='ReShade.ini';format='ini';key=@($_.key);value=$_.value} })
    $contributions+=@($presetContributions)
    if ($contributions.Count -gt 512) { throw 'Combined ReShade configuration/preset exceeds the private import limit.' }
    return [pscustomobject]@{
        contributions=$contributions
        environment=@{RESHADE_BASE_PATH_OVERRIDE=$private;TRINITYPLATFORM='dx12'}
    }
}

function Get-JournalHash {
    param([string]$Path)
    $stream=[IO.File]::OpenRead((Get-PlainPath $Path))
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','') }
    finally { $hasher.Dispose(); $stream.Dispose() }
}

function Write-BoundReceipt {
    param($Request,[string]$Client,$Journal,[string]$State)
    $serverRoot=Get-PlainPath ([string]$Request.runtime.evejsRoot)
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { $serverKey=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($serverRoot.ToUpperInvariant())))).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    $relative='_local/mod-receipts/dlss5/'+$serverKey+'.json'
    $journalPath=Get-PlainPath (Join-Path (Split-Path -Parent $Client) '_evejs\dlss5\install\active-install.json')
    $receipt=[ordered]@{
        schemaVersion=1;modIdentity=[string]$Request.mod.identity;clientRoot=$Client;state=$State;
        evejsRoot=$serverRoot;
        adapterVersion=$script:AdapterVersion;
        packageVersion=if ($null -ne $Journal -and $Journal.PSObject.Properties.Name -contains 'integrationVersion') { [string]$Journal.integrationVersion } else { $null };
        managerJournal=$journalPath;
        managerJournalSha256=if ($null -ne $Journal) { (Get-JournalHash $journalPath) } else { $null }
    }
    Write-JsonFile -Path (Join-Path $Client $relative) -Value $receipt
    return [ordered]@{base='client';path=$relative;state=$State;schemaVersion=1}
}

$reply=[ordered]@{protocol='evejs_launcher_mod_v1';requestId='';success=$false;state='failed';message='';restartRequired=@();contributions=@();environment=@{};arguments=@()}
$recoveryStarted=$false
$requestFile=Get-PlainPath $RequestPath
$resultFile=Get-PlainPath $ResultPath
if (-not (Split-Path -Parent $requestFile).Equals((Split-Path -Parent $resultFile),[StringComparison]::OrdinalIgnoreCase) -or $requestFile.Equals($resultFile,[StringComparison]::OrdinalIgnoreCase)) { throw 'Request and result must be distinct files in the same operation directory.' }
try {
    $request=Read-JsonFile $requestFile
    $reply.requestId=[string]$request.requestId
    $requestGuid=[Guid]::Empty
    if ([string]$request.protocol -cne 'evejs_launcher_mod_v1' -or -not [Guid]::TryParse($reply.requestId,[ref]$requestGuid)) { throw 'Unsupported launcher request protocol or identity.' }
    if ([string]$request.mod.id -cne 'evejs-dlss5' -or [string]$request.mod.version -cne $script:AdapterVersion -or
        -not (Get-PlainPath ([string]$request.mod.path)).Equals($script:PackageRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Launcher request does not identify this package.' }
    $script:ManagerBudgetMilliseconds=switch ([string]$request.action) {
        'install' { 3600000 }
        'recover' { 3600000 }
        'prepare_disable' { 600000 }
        'prepare_remove' { 600000 }
        default { 120000 }
    }
    $client=Get-PlainPath ([string]$request.runtime.clientRoot)
    $evejs=Get-PlainPath ([string]$request.runtime.evejsRoot)
    $journal=Read-ClientJournal $client
    if ([string]$request.action -eq 'prepare_profile') {
        if ($null -eq $journal -or [string]$journal.status -ne 'installed') { throw 'Install and verify the global DLSS5 package before preparing a profile.' }
        if ($journal.PSObject.Properties.Name -contains 'serverAttachments') {
            $attached=@($journal.serverAttachments | Where-Object { ([string]$_.root).Equals($evejs,[StringComparison]::OrdinalIgnoreCase) -and $_.status -eq 'attached' })
            if ($attached.Count -ne 1) { throw 'This server is not attached to the shared DLSS5 installation.' }
        }
        $prepared=Get-ProfilePreparation -Request $request -Client $client
        $reply.contributions=@($prepared.contributions)
        $reply.environment=$prepared.environment
        $reply.message='Private ReShade settings are proposed for the launcher to apply.'
    } else {
        switch ([string]$request.action) {
            'install' { Invoke-BinaryManager -Action Ensure -Client $client -EveJS $evejs }
            'verify' { Invoke-BinaryManager -Action Verify -Client $client -EveJS $evejs }
            {$_ -in @('prepare_disable','prepare_remove')} {
                if ($null -ne $request.profile) { throw 'DLSS5 removal is global to the physical client, not one profile.' }
                $removalRoot=if ($null -ne $journal -and $journal.PSObject.Properties.Name -contains 'serverAttachments') { $evejs } elseif ($null -ne $journal) { [string]$journal.evejsRoot } else { $evejs }
                if ($null -ne $journal) { Invoke-BinaryManager -Action Restore -Client $client -EveJS $removalRoot }
            }
            'recover' {
                $ownerRoot=if ($null -ne $journal) { Get-PlainPath ([string]$journal.evejsRoot) } else { $evejs }
                $recoveryStarted=$true
                Invoke-BinaryManager -Action Recover -Client $client -EveJS $ownerRoot
                $journal=Read-ClientJournal $client
                # Recovery remains possible after the former server is gone.
                # Restore client originals from its retained receipt/backups.
                if ($null -ne $journal -and $journal.PSObject.Properties.Name -contains 'serverAttachments' -and [string]$journal.status -eq 'installed') {
                    Invoke-BinaryManager -Action VerifyClient -Client $client -EveJS $ownerRoot
                } elseif ($null -ne $journal -and (-not (Test-Path -LiteralPath $ownerRoot -PathType Container) -or [string]$journal.status -notin @('installed','restored','rolledBack'))) {
                    Invoke-BinaryManager -Action Restore -Client $client -EveJS $ownerRoot
                } elseif ($null -ne $journal -and [string]$journal.status -in @('installed','restored','rolledBack')) {
                    Invoke-BinaryManager -Action Verify -Client $client -EveJS $ownerRoot
                }
            }
            default { throw 'Unsupported launcher action.' }
        }
        $journal=Read-ClientJournal $client
        $state=if ($null -eq $journal -or [string]$journal.status -in @('restored','rolledBack')) { 'restored' }
            elseif ([string]$journal.status -eq 'installed') { 'active' } else { 'recoverable' }
        if ($null -ne $journal -and $journal.PSObject.Properties.Name -contains 'serverAttachments') {
            $selected=@($journal.serverAttachments | Where-Object { ([string]$_.root).Equals($evejs,[StringComparison]::OrdinalIgnoreCase) })
            if ($selected.Count -eq 1 -and $selected[0].status -eq 'detached') { $state='restored' }
        }
        $reply.receipt=Write-BoundReceipt -Request $request -Client $client -Journal $journal -State $state
        if ($state -eq 'recoverable') { throw 'The retained binary transaction still needs recovery.' }
        if ([string]$request.action -eq 'recover' -and $state -eq 'active') {
            $reply.message='Recovery verified the retained installed payload against its recorded hashes. This does not upgrade the physical payload.'
        } else {
            $reply.message='The global client package operation was verified; private profile settings remain separate.'
        }
        if ([string]$request.action -ne 'verify') { $reply.restartRequired=@('client') }
    }
    $reply.success=$true
    $reply.state='ready'
} catch {
    # A failed recovery must not leave a stale active receipt suggesting success.
    # Keep the original failure even if the journal itself cannot be read safely.
    $failure=$_
    if ($recoveryStarted) {
        try {
            $journal=Read-ClientJournal $client
            $reply.receipt=Write-BoundReceipt -Request $request -Client $client -Journal $journal -State 'recoverable'
        } catch { }
    }
    $reply.message=($failure.Exception.Message -replace '[\x00-\x1f]+',' ').Trim()
    # Keep a bounded message in the public result.
    if ($reply.message.Length -gt 4000) { $reply.message=$reply.message.Substring(0,4000) }
}
Write-JsonFile -Path $ResultPath -Value $reply
if (-not $reply.success) { exit 1 }
