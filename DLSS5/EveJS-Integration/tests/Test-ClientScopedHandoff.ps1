[CmdletBinding()]
param(
    [string]$IntegrationRoot = '',
    [string]$StockClientRoot = '',
    [string]$StockCodeCcpPath = '',
    [string]$PythonRuntimePath = '',
    [string]$RenoDxZip = '',
    [string]$DlssNrZip = '',
    [string]$StreamlineZip = '',
    [switch]$KeepFixtures,
    [switch]$Worker,
    [string]$FixtureRoot = '',
    [ValidateSet('RootA', 'RootB')][string]$SelectedRoot = 'RootA',
    [ValidateSet('Ensure', 'Restore')][string]$Action = 'Ensure'
)

# Destructive operations are restricted to a marked disposable temp fixture.
# Source arguments are read-only. No EVE process or GUI is launched.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:TestScriptPath = $PSCommandPath
$script:TempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Assert-FixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $resolved.StartsWith($script:TempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^evejs-dlss5-handoff-fixture-[0-9a-f]{32}$') {
        throw "Refusing non-fixture root: $resolved"
    }
    $marker = Join-Path $resolved '.fixture-owner'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        [IO.File]::ReadAllText($marker) -cne 'Test-ClientScopedHandoff.ps1') {
        throw "Missing fixture identity marker: $resolved"
    }
    $item = Get-Item -LiteralPath $resolved -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture root must not be a reparse point.' }
    return $resolved
}

function Assert-FixtureDestination {
    param([Parameter(Mandatory = $true)][string]$Path)
    $fixture = Assert-FixtureRoot $script:FixtureRoot
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($fixture + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing a write outside the disposable fixture: $full"
    }
    return $full
}

function Write-FixtureText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $destination = Assert-FixtureDestination $Path
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    [IO.File]::WriteAllText($destination, $Text, $script:Utf8NoBom)
}

function Copy-FixtureFile {
    param([string]$Source, [string]$Destination)
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if ($sourceItem.PSIsContainer -or ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Source must be a regular file: $Source"
    }
    $target = Assert-FixtureDestination $Destination
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $sourceItem.FullName -Destination $target -Force
    if ((Get-FileHash -LiteralPath $sourceItem.FullName -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw "Fixture copy mismatch: $Source"
    }
}

function Remove-FixturePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Assert-FixtureDestination $Path
    if (-not (Test-Path -LiteralPath $full)) { return }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse cleanup: $full" }
    Remove-Item -LiteralPath $full -Recurse -Force
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $records = foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName)) {
        [ordered]@{
            path = $file.FullName.Substring($prefix.Length)
            bytes = [Int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return (@($records) | ConvertTo-Json -Compress)
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory = $true)][string]$Label)
    if ($Expected -cne $Actual) { throw "$Label mismatch. Expected '$Expected', got '$Actual'." }
}

if ($Worker) {
    $script:FixtureRoot = Assert-FixtureRoot $FixtureRoot
    $workspace = Join-Path $script:FixtureRoot 'workspace'
    $evejs = Join-Path $workspace $SelectedRoot
    $client = Join-Path $workspace 'client\tq'
    $state = Join-Path (Split-Path -Parent $client) '_evejs\dlss5\install'
    $manager = Join-Path $evejs 'mods\DLSS5\EveJS-Integration\Manage-EveJSDLSS5.ps1'
    foreach ($path in @($workspace, $evejs, $client, $state, $manager)) { Assert-FixtureDestination $path | Out-Null }
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile, [int]$TimeoutSec, [hashtable]$Headers)
        Write-FixtureText (Join-Path $script:FixtureRoot 'unexpected-network.txt') $Uri
        throw 'Fixture prohibits network downloads; expected the seeded cache or an offline action.'
    }
    & $manager -Action $Action -Profile DLSS5 -WorkspaceRoot $workspace -EveJSRootPath $evejs -ClientRoot $client -StateRootPath $state
    if (-not $?) { exit 1 }
    exit 0
}

if (-not $IntegrationRoot) { $IntegrationRoot = Split-Path -Parent $PSScriptRoot }
foreach ($requiredName in @('IntegrationRoot', 'StockClientRoot', 'StockCodeCcpPath', 'PythonRuntimePath', 'RenoDxZip', 'DlssNrZip', 'StreamlineZip')) {
    $value = Get-Variable -Name $requiredName -ValueOnly
    if (-not $value -or -not [IO.Path]::IsPathRooted($value) -or -not (Test-Path -LiteralPath $value)) {
        throw "Supply an existing absolute read-only source path with -$requiredName."
    }
}

$sourceIntegration = [IO.Path]::GetFullPath($IntegrationRoot).TrimEnd('\')
$payload = [IO.File]::ReadAllText((Join-Path $sourceIntegration 'payload-manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$codeRecord = @($payload.files | Where-Object { ([string]$_.destination).Equals('code.ccp', [StringComparison]::OrdinalIgnoreCase) })[0]
Assert-Equal ([string]$codeRecord.requiredOriginalSha256) ((Get-FileHash -LiteralPath $StockCodeCcpPath -Algorithm SHA256).Hash) 'Stock code.ccp hash'
Assert-Equal ([Int64]$codeRecord.requiredOriginalBytes) ([Int64](Get-Item -LiteralPath $StockCodeCcpPath).Length) 'Stock code.ccp bytes'

$sourceArchives = @{
    'renodx-dlss5-4.70' = $RenoDxZip
    'nvidia-dlssnr-310.8.0' = $DlssNrZip
    'nvidia-streamline-2.13.0.0' = $StreamlineZip
}
foreach ($artifact in @($payload.artifacts)) {
    $archive = [string]$sourceArchives[[string]$artifact.id]
    Assert-Equal ([Int64]$artifact.bytes) ([Int64](Get-Item -LiteralPath $archive).Length) ("Archive bytes $($artifact.id)")
    Assert-Equal ([string]$artifact.sha256) ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash) ("Archive hash $($artifact.id)")
}

$script:FixtureRoot = Join-Path $script:TempParent ('evejs-dlss5-handoff-fixture-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:FixtureRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $script:FixtureRoot '.fixture-owner'), 'Test-ClientScopedHandoff.ps1', $script:Utf8NoBom)
$workspace = Join-Path $script:FixtureRoot 'workspace'
$rootA = Join-Path $workspace 'RootA'
$rootB = Join-Path $workspace 'RootB'
$client = Join-Path $workspace 'client\tq'
$state = Join-Path (Split-Path -Parent $client) '_evejs\dlss5\install'
$activeManifest = Join-Path $state 'active-install.json'
$configA = Join-Path $rootA 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
$configB = Join-Path $rootB 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
$sourceManager = Join-Path $sourceIntegration 'Manage-EveJSDLSS5.ps1'
$managerA = Join-Path $rootA 'mods\DLSS5\EveJS-Integration\Manage-EveJSDLSS5.ps1'

function Install-FixturePackage {
    param([Parameter(Mandatory = $true)][string]$Root)
    $destinationIntegration = Join-Path $Root 'mods\DLSS5\EveJS-Integration'
    $prefix = $sourceIntegration + '\'
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceIntegration -File -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Package source contains a reparse point: $($item.FullName)" }
        Copy-FixtureFile $item.FullName (Join-Path $destinationIntegration $item.FullName.Substring($prefix.Length))
    }
}

function Seed-ArtifactCache {
    foreach ($artifact in @($payload.artifacts)) {
        $destination = Join-Path (Join-Path (Join-Path $state 'cache\artifacts') ([string]$artifact.sha256)) ([string]$artifact.fileName)
        Copy-FixtureFile -Source ([string]$sourceArchives[[string]$artifact.id]) -Destination $destination
    }
}

function Invoke-FixtureManager {
    param(
        [ValidateSet('RootA', 'RootB')][string]$Root,
        [ValidateSet('Ensure', 'Restore')][string]$SelectedAction,
        [int]$ExpectedExit = 0,
        [string]$ExpectedMessage = ''
    )
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:TestScriptPath,
        '-Worker', '-FixtureRoot', $script:FixtureRoot, '-SelectedRoot', $Root, '-Action', $SelectedAction)
    $quoted = @($arguments | ForEach-Object {
        if ($_ -match '["\r\n]' -or $_.EndsWith('\')) { throw 'Unsupported child-process argument.' }
        '"' + $_ + '"'
    }) -join ' '
    $start = New-Object Diagnostics.ProcessStartInfo
    $windowsPowerShell = Join-Path $PSHOME 'powershell.exe'
    $start.FileName = if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
        $windowsPowerShell
    } else {
        (Get-Process -Id $PID).Path
    }
    $start.Arguments = $quoted
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Fixture worker did not start.' }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(360000)) {
            $process.Kill()
            [void]$process.WaitForExit(5000)
            throw 'Fixture worker exceeded six minutes and was stopped.'
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        Write-Host $output
        Assert-Equal $ExpectedExit $process.ExitCode "$Root $SelectedAction exit"
        if ($ExpectedMessage -and $output.IndexOf($ExpectedMessage, [StringComparison]::Ordinal) -lt 0) {
            throw "Manager output did not contain '$ExpectedMessage'."
        }
    } finally { $process.Dispose() }
    if (Test-Path -LiteralPath (Join-Path $script:FixtureRoot 'unexpected-network.txt')) {
        throw 'An offline fixture operation attempted a network download.'
    }
}

try {
    foreach ($relative in @('bin64\exefile.exe', 'bin64\blue.dll', 'bin64\_trinity_dx12.dll')) {
        Copy-FixtureFile (Join-Path $StockClientRoot $relative) (Join-Path $client $relative)
    }
    Copy-FixtureFile $StockCodeCcpPath (Join-Path $client 'code.ccp')
    Copy-FixtureFile $PythonRuntimePath (Join-Path $client 'bin64\python27.dll')
    Write-FixtureText (Join-Path $client 'start.ini') "build=3396210`r`nserver=127.0.0.1`r`n"
    Write-FixtureText (Join-Path $rootA 'package.json') '{"name":"eve.js","version":"0.12.7"}'
    Write-FixtureText (Join-Path $rootB 'package.json') '{"name":"eve.js","version":"0.12.7.1"}'
    $configTemplate = '@echo off' + "`r`n" +
        'set EVEJS_DLSS5=off' + "`r`n" +
        'set TRINITYPLATFORM=dx11' + "`r`n" +
        'set "EVEJS_CLIENT_PATH=' + $client + '"' + "`r`n" +
        'set "EVEJS_CLIENT_EXE="' + "`r`n"
    Write-FixtureText $configA $configTemplate
    Write-FixtureText $configB $configTemplate
    Install-FixturePackage $rootA
    Install-FixturePackage $rootB
    Seed-ArtifactCache

    $stockClient = Get-TreeSnapshot $client
    $stockConfigA = (Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash
    $stockConfigB = (Get-FileHash -LiteralPath $configB -Algorithm SHA256).Hash

    $standalone = Join-Path $rootB 'mods\DLSS5\EveJS-Integration\Invoke-Standalone.ps1'
    $resolvedTarget = & $standalone -ResolveOnly -NonInteractive -EveJSRootPath $rootB -ClientRoot $client
    Assert-Equal $rootB ([string]$resolvedTarget.EveJSRootPath) 'Standalone arbitrary-version EveJS root'
    Assert-Equal $client ([string]$resolvedTarget.ClientRoot) 'Standalone physical client root'
    Assert-Equal $state ([string]$resolvedTarget.StateRootPath) 'Standalone client-scoped state root'
    Write-Host 'PASS standalone resolver accepts 0.12.7.1 and derives state beside the physical tq client' -ForegroundColor Green

    $stateContainer = Join-Path (Split-Path -Parent $client) '_evejs'
    $plainStateContainer = Join-Path (Split-Path -Parent $client) '_evejs-fixture-plain'
    Move-Item -LiteralPath $stateContainer -Destination $plainStateContainer
    try {
        New-Item -ItemType Junction -Path $stateContainer -Target $plainStateContainer | Out-Null
        Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'reparse point in the client-scoped state path'
        Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Reparse rejection client bytes'
        if (Test-Path -LiteralPath $activeManifest -PathType Leaf) { throw 'Reparse rejection created an install receipt.' }
    } finally {
        $junction = Get-Item -LiteralPath $stateContainer -Force -ErrorAction SilentlyContinue
        if ($null -ne $junction) {
            if (-not ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected fixture state junction was replaced.' }
            [IO.Directory]::Delete($junction.FullName)
        }
        Move-Item -LiteralPath $plainStateContainer -Destination $stateContainer
    }
    Write-Host 'PASS a state-path junction is rejected before receipt, cache or client mutation' -ForegroundColor Green

    foreach ($ownedChild in @('backups', 'history')) {
        $junctionPath = Join-Path $state $ownedChild
        $junctionTarget = Join-Path $script:FixtureRoot ('state-junction-target-' + $ownedChild)
        New-Item -ItemType Directory -Path $junctionTarget -Force | Out-Null
        try {
            New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
            Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'reparse point in the client-scoped state path'
            Assert-Equal $stockClient (Get-TreeSnapshot $client) "$ownedChild junction rejection client bytes"
            if (Test-Path -LiteralPath $activeManifest -PathType Leaf) { throw "$ownedChild junction rejection created an install receipt." }
        } finally {
            $junction = Get-Item -LiteralPath $junctionPath -Force -ErrorAction SilentlyContinue
            if ($null -ne $junction) {
                if (-not ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Expected $ownedChild junction was replaced." }
                [IO.Directory]::Delete($junction.FullName)
            }
        }
    }
    Write-Host 'PASS backups and history child junctions are rejected before receipt or client mutation' -ForegroundColor Green

    $configScripts = Split-Path -Parent $configA
    $configJunctionTarget = Join-Path $script:FixtureRoot 'config-junction-target'
    Move-Item -LiteralPath $configScripts -Destination $configJunctionTarget
    try {
        New-Item -ItemType Junction -Path $configScripts -Target $configJunctionTarget | Out-Null
        Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'reparse point in the owned EveJS path'
        Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Config-parent junction rejection client bytes'
        Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Config-parent junction config bytes'
        if (Test-Path -LiteralPath $activeManifest -PathType Leaf) { throw 'Config-parent junction rejection created an install receipt.' }
    } finally {
        $junction = Get-Item -LiteralPath $configScripts -Force -ErrorAction SilentlyContinue
        if ($null -ne $junction) {
            if (-not ($junction.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected config-parent junction was replaced.' }
            [IO.Directory]::Delete($junction.FullName)
        }
        Move-Item -LiteralPath $configJunctionTarget -Destination $configScripts
    }
    Write-Host 'PASS a config-parent junction is rejected before config, receipt, or client mutation' -ForegroundColor Green

    $originalConfigAText = [IO.File]::ReadAllText($configA)
    $duplicateClientPathConfig = 'set EVEJS_CLIENT_PATH=C:\wrong\tq' + "`r`n" + $originalConfigAText
    Write-FixtureText $configA $duplicateClientPathConfig
    Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'exactly one unambiguous literal EVEJS_CLIENT_PATH assignment'
    Assert-Equal $duplicateClientPathConfig ([IO.File]::ReadAllText($configA)) 'Ambiguous config remains unmodified'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Ambiguous config rejection client bytes'
    if (Test-Path -LiteralPath $activeManifest -PathType Leaf) { throw 'Ambiguous config rejection created an install receipt.' }
    Write-FixtureText $configA $originalConfigAText
    Write-Host 'PASS duplicate quoted/unquoted client paths fail before receipt or client mutation' -ForegroundColor Green

    $managerText = [IO.File]::ReadAllText($managerA)
    $dispatchMarker = '$managerMutex = $null'
    Assert-Equal 1 ([Regex]::Matches($managerText, [Regex]::Escape($dispatchMarker)).Count) 'Manager dispatch marker count'
    $processInjection = @'
function Get-Process {
    param([string]$Name, [object]$ErrorAction)
    if ($Name -eq "exefile") {
        return [pscustomobject]@{ Id = 424242 }
    }
    throw "Unexpected fixture Get-Process call."
}
'@
    Write-FixtureText $managerA ($managerText.Replace($dispatchMarker, $processInjection + "`r`n" + $dispatchMarker))
    Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'Close every EVE client'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Unavailable-process-path rejection client bytes'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Unavailable-process-path rejection config'
    if (Test-Path -LiteralPath $activeManifest -PathType Leaf) { throw 'Process gate created an install receipt.' }
    Copy-FixtureFile $sourceManager $managerA
    Write-Host 'PASS an exefile process with no readable path blocks every mutating action' -ForegroundColor Green

    $managerText = [IO.File]::ReadAllText($managerA)
    $verifyInjection = @'
$script:FixtureOriginalInvokeVerify = ${function:Invoke-Verify}
$script:FixtureFinalVerifyInjected = $false
function Invoke-Verify {
    param($PayloadManifest = $null)
    if (-not $script:FixtureFinalVerifyInjected -and $null -ne $PayloadManifest) {
        $script:FixtureFinalVerifyInjected = $true
        throw "Injected final verification failure."
    }
    & $script:FixtureOriginalInvokeVerify -PayloadManifest $PayloadManifest
}
'@
    $uncertifiedRollbackInjection = $verifyInjection + @'

function Invoke-RecoveryRollback {
    param($Manifest)
    Write-WarningLine "Injected no-op recovery rollback."
}
'@
    Assert-Equal 1 ([Regex]::Matches($managerText, [Regex]::Escape($dispatchMarker)).Count) 'Uncertified-rollback manager dispatch marker count'
    Write-FixtureText $managerA ($managerText.Replace($dispatchMarker, $uncertifiedRollbackInjection + "`r`n" + $dispatchMarker))
    Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'Automatic rollback also failed: Rollback verification found'
    $uncertified = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal 'rollbackPending' ([string]$uncertified.status) 'Unverified rollback receipt status'
    Copy-FixtureFile $sourceManager $managerA
    Invoke-FixtureManager RootA Restore -ExpectedMessage 'Original client files and EveJS config restored'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Recovery after uncertified rollback client bytes'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Recovery after uncertified rollback config'
    Write-Host 'PASS a no-op rollback is never certified terminal and remains recoverable by explicit Restore' -ForegroundColor Green

    $managerText = [IO.File]::ReadAllText($managerA)
    Assert-Equal 1 ([Regex]::Matches($managerText, [Regex]::Escape($dispatchMarker)).Count) 'Final-verify manager dispatch marker count'
    Write-FixtureText $managerA ($managerText.Replace($dispatchMarker, $verifyInjection + "`r`n" + $dispatchMarker))
    Invoke-FixtureManager RootA Ensure -ExpectedExit 1 -ExpectedMessage 'Install failed and was rolled back: Injected final verification failure.'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Final-verify failure restored client bytes'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Final-verify failure restored config'
    $rolledBack = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal 'rolledBack' ([string]$rolledBack.status) 'Final-verify failure terminal receipt'
    Copy-FixtureFile $sourceManager $managerA
    Write-Host 'PASS a final installed-state verification failure performs a complete verified rollback' -ForegroundColor Green

    Invoke-FixtureManager RootA Ensure -ExpectedMessage 'DLSS5 integration installed'
    $installedA = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal 5 ([int]$installedA.schemaVersion) 'RootA receipt schema'
    Assert-Equal 'client' ([string]$installedA.stateScope) 'RootA receipt state scope'
    Assert-Equal $rootA ([string]$installedA.evejsRoot) 'RootA receipt owner'
    Assert-Equal $state ([string]$installedA.stateRoot) 'RootA receipt state path'
    $installedConfigA = [IO.File]::ReadAllText($configA)
    foreach ($setting in @('EVEJS_CLIENT_PATH', 'EVEJS_CLIENT_EXE', 'TRINITYPLATFORM', 'EVEJS_DLSS5')) {
        Assert-Equal 1 ([Regex]::Matches($installedConfigA, '(?im)^\s*@?set\s+"?' + [Regex]::Escape($setting) + '=').Count) "Installed $setting assignment count"
    }
    if ($installedConfigA -notmatch '(?im)^\s*@?set\s+"EVEJS_CLIENT_EXE=bin64\\exefile\.exe"\s*$') {
        throw 'The installed config did not normalize the stock blank EVEJS_CLIENT_EXE value.'
    }
    if ($installedConfigA -match '(?im)^\s*@?set\s+(?:"?TRINITYPLATFORM=dx11|"?EVEJS_DLSS5=off)') {
        throw 'The installed config retained an earlier conflicting unquoted DLSS assignment.'
    }
    $installedClient = Get-TreeSnapshot $client
    Write-Host 'PASS arbitrary EveJS version installs with a fresh client-scoped schema-5 receipt and normalized config' -ForegroundColor Green

    $legacyB = Join-Path $rootB '_local\dlss5\install\active-install.json'
    Write-FixtureText $legacyB '{"schemaVersion":4,"status":"installed"}'
    Invoke-FixtureManager RootB Ensure -ExpectedExit 1 -ExpectedMessage 'shared client is verified stock'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Failed-handoff stock client'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Failed-handoff restored RootA config'
    Assert-Equal $stockConfigB ((Get-FileHash -LiteralPath $configB -Algorithm SHA256).Hash) 'Failed-handoff untouched RootB config'
    if (Test-Path -LiteralPath $activeManifest) { throw 'Failed target install left an active client-scoped receipt.' }

    $archivedReceipts = @(Get-ChildItem -LiteralPath (Join-Path $state 'history') -Filter 'active-install-before-root-handoff-*.json' -File)
    Assert-Equal 1 $archivedReceipts.Count 'Archived restored old-root receipt count'
    $archivedText = [IO.File]::ReadAllText($archivedReceipts[0].FullName)
    $archived = $archivedText | ConvertFrom-Json
    Assert-Equal 'restored' ([string]$archived.status) 'Archived old-root receipt status'
    Assert-Equal $rootA ([string]$archived.evejsRoot) 'Archived old-root receipt owner'
    if ($archivedText.IndexOf($rootB, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'Archived old-root receipt was copied or relabelled as the target root.'
    }
    Write-Host 'PASS failed target install leaves stock bytes and preserves the restored old-root receipt without relabelling' -ForegroundColor Green

    Remove-FixturePath (Join-Path $rootB '_local\dlss5')
    Invoke-FixtureManager RootB Ensure -ExpectedMessage 'DLSS5 integration installed'
    $installedB = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal 5 ([int]$installedB.schemaVersion) 'RootB receipt schema'
    Assert-Equal 'client' ([string]$installedB.stateScope) 'RootB receipt state scope'
    Assert-Equal $rootB ([string]$installedB.evejsRoot) 'Fresh RootB receipt owner'
    Assert-Equal $state ([string]$installedB.stateRoot) 'Fresh RootB receipt state path'
    Assert-Equal $installedClient (Get-TreeSnapshot $client) 'RootB installed client bytes'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'RootA remains restored'
    Write-Host 'PASS retry after a safely failed handoff installs a fresh target-root receipt' -ForegroundColor Green

    Invoke-FixtureManager RootA Ensure -ExpectedMessage 'root handoff completed'
    $handedToA = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal $rootA ([string]$handedToA.evejsRoot) 'Successful handoff RootA owner'
    Assert-Equal $stockConfigB ((Get-FileHash -LiteralPath $configB -Algorithm SHA256).Hash) 'Successful handoff restored RootB config'
    Assert-Equal $installedClient (Get-TreeSnapshot $client) 'Successful handoff RootA client bytes'

    Invoke-FixtureManager RootB Ensure -ExpectedMessage 'root handoff completed'
    $handedToB = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal 5 ([int]$handedToB.schemaVersion) 'Successful handoff RootB schema'
    Assert-Equal 'client' ([string]$handedToB.stateScope) 'Successful handoff RootB state scope'
    Assert-Equal $rootB ([string]$handedToB.evejsRoot) 'Successful handoff RootB owner'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Successful handoff restored RootA config'
    Assert-Equal $installedClient (Get-TreeSnapshot $client) 'Successful handoff RootB client bytes'
    Write-Host 'PASS completed sibling handoffs restore the old root and create a fresh target-root receipt' -ForegroundColor Green

    $reshadeIni = Join-Path $client 'bin64\ReShade.ini'
    $reshadeText = [IO.File]::ReadAllText($reshadeIni)
    Assert-Equal 1 ([Regex]::Matches($reshadeText, '(?m)^NeuralUplift=1\r?$').Count) 'Installed NeuralUplift default count'
    Write-FixtureText $reshadeIni ([Regex]::Replace($reshadeText, '(?m)^NeuralUplift=1\r?$', 'NeuralUplift=0'))
    $activeHash = (Get-FileHash -LiteralPath $activeManifest -Algorithm SHA256).Hash
    $runtimePreferenceClient = Get-TreeSnapshot $client
    Invoke-FixtureManager RootB Ensure -ExpectedMessage 'read-only verification'
    Assert-Equal $activeHash ((Get-FileHash -LiteralPath $activeManifest -Algorithm SHA256).Hash) 'Same-root Ensure receipt hash'
    Assert-Equal $runtimePreferenceClient (Get-TreeSnapshot $client) 'Same-root Ensure client bytes after NeuralUplift runtime change'
    Write-Host 'PASS same-root Ensure accepts persisted NeuralUplift off and remains byte-for-byte read-only' -ForegroundColor Green

    Write-FixtureText $reshadeIni ([Regex]::Replace([IO.File]::ReadAllText($reshadeIni), '(?m)^NeuralUplift=0\r?$', 'NeuralUplift=2'))
    $invalidPreferenceClient = Get-TreeSnapshot $client
    Invoke-FixtureManager RootB Ensure -ExpectedExit 1 -ExpectedMessage 'ReShade.ini mismatch: [RenoDX.DLSS5] NeuralUplift'
    Assert-Equal $activeHash ((Get-FileHash -LiteralPath $activeManifest -Algorithm SHA256).Hash) 'Invalid NeuralUplift receipt hash'
    Assert-Equal $invalidPreferenceClient (Get-TreeSnapshot $client) 'Invalid NeuralUplift rejection client bytes'
    Write-FixtureText $reshadeIni ([Regex]::Replace([IO.File]::ReadAllText($reshadeIni), '(?m)^NeuralUplift=2\r?$', 'NeuralUplift=0'))
    Write-Host 'PASS same-root Ensure still rejects NeuralUplift outside its runtime Boolean domain' -ForegroundColor Green

    Invoke-FixtureManager RootB Restore -ExpectedMessage 'Original client files and EveJS config restored'
    Invoke-FixtureManager RootA Ensure -ExpectedMessage 'root handoff completed'
    $afterExplicitRestore = [IO.File]::ReadAllText($activeManifest) | ConvertFrom-Json
    Assert-Equal $rootA ([string]$afterExplicitRestore.evejsRoot) 'Explicit-restore handoff owner'
    Assert-Equal $installedClient (Get-TreeSnapshot $client) 'Explicit-restore handoff client bytes'
    Assert-Equal $stockConfigB ((Get-FileHash -LiteralPath $configB -Algorithm SHA256).Hash) 'Explicit-restore handoff RootB config'
    Write-Host 'PASS Restore on one root followed by Ensure on its sibling installs a fresh receipt' -ForegroundColor Green

    Invoke-FixtureManager RootA Restore -ExpectedMessage 'Original client files and EveJS config restored'
    Assert-Equal $stockClient (Get-TreeSnapshot $client) 'Final restored client'
    Assert-Equal $stockConfigA ((Get-FileHash -LiteralPath $configA -Algorithm SHA256).Hash) 'Final RootA config'
    Assert-Equal $stockConfigB ((Get-FileHash -LiteralPath $configB -Algorithm SHA256).Hash) 'Final RootB config'
    Write-Host 'PASS final rollback restores client plus both sibling EveJS configurations' -ForegroundColor Green
    Write-Host 'Client-scoped handoff fixture: 18 passed; no live client, GUI, or network touched.'
} finally {
    if ($KeepFixtures) {
        Write-Host "Disposable fixture retained for inspection: $script:FixtureRoot"
    } else {
        $safeRoot = Assert-FixtureRoot $script:FixtureRoot
        Remove-Item -LiteralPath $safeRoot -Recurse -Force
    }
}
