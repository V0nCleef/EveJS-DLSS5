[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$integration = Split-Path -Parent $PSScriptRoot
. (Join-Path $integration 'ReShade-Lists.ps1')
. (Join-Path $integration 'Client-Attachments.ps1')
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture = Join-Path $tempRoot ('dlss5-recovery-' + [Guid]::NewGuid().ToString('N'))
if (-not ([IO.Path]::GetFullPath($fixture)).StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped temp.' }
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $integration 'Manage-EveJSDLSS5.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load definitions only. Main dispatch, helper imports and path detection never run.
foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert-True { param([bool]$Value,[string]$Message) if (-not $Value) { throw $Message } }
function Assert-Fails { param([scriptblock]$Body,[string]$Pattern) try { & $Body } catch { if ($_.Exception.Message -match $Pattern) { return }; throw }; throw "Expected failure: $Pattern" }
function Assert-NoTargetClientProcess { }
$script:WorkspaceRoot = $fixture
$script:EveJSRoot = Join-Path $fixture 'EveJS'
$script:ClientRoot = Join-Path $fixture 'physical\tq'
$script:BinRoot = Join-Path $script:ClientRoot 'bin64'
$script:ExePath = Join-Path $script:BinRoot 'exefile.exe'
$script:IntegrationRoot = $integration
$script:StateRoot = Join-Path $fixture 'physical\_evejs\dlss5\install'
$script:ActiveManifestPath = Join-Path $script:StateRoot 'active-install.json'
$script:PendingTransactionPath = Join-Path $script:StateRoot 'pending-profile-transaction.json'
$script:ConfigPath = Join-Path $script:EveJSRoot 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
$script:ReShadeConfigPath = Join-Path $script:BinRoot 'ReShade.ini'
$script:ProfileTransaction = $null
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)
$before = 'profile A file'
$after = 'profile B file'
try {
    New-Item -ItemType Directory -Path $script:BinRoot,$script:StateRoot,(Split-Path -Parent $script:ConfigPath) -Force | Out-Null
    [IO.File]::WriteAllText($script:ExePath,'disposable executable identity fixture')
    $script:ExpectedExeSha256=Get-Sha256 $script:ExePath
    $first = Join-Path $script:BinRoot 'first.dll'
    $second = Join-Path $script:BinRoot 'second.dll'
    [IO.File]::WriteAllText($first,$before)
    [IO.File]::WriteAllText($script:ConfigPath,"set OTHER=original`r`n")
    $manifest = [pscustomobject]@{ operations=@([pscustomobject]@{ destination='bin64\first.dll' },[pscustomobject]@{ destination='bin64\second.dll' }) }
    [IO.File]::WriteAllText($script:ActiveManifestPath,'{"profile":"A"}')
    Start-ProfileTransaction $manifest
    Write-TextAtomic -Text $after -Path $first
    Write-TextAtomic -Text 'new addition' -Path $second
    Write-JsonAtomic -Value @{profile='B'} -Path $script:ActiveManifestPath
    $script:ProfileTransaction = $null # Simulate a process dying before commit.
    Invoke-RecoverProfileTransaction
    Assert-True ([IO.File]::ReadAllText($first) -ceq $before) 'Pre-operation file not restored.'
    Assert-True (-not (Test-Path -LiteralPath $second)) 'New operation file not removed.'
    Assert-True ([IO.File]::ReadAllText($script:ActiveManifestPath) -ceq '{"profile":"A"}') 'Pre-operation receipt not restored.'
    Assert-True (-not (Test-Path -LiteralPath $script:PendingTransactionPath)) 'Recovered operation still pending.'

    # Detect drift in the last entry before touching the first rollback target.
    Start-ProfileTransaction $manifest
    Write-TextAtomic -Text $after -Path $first
    Write-TextAtomic -Text 'new addition' -Path $second
    [IO.File]::WriteAllText($second,'another mod changed this')
    $script:ProfileTransaction = $null
    Assert-Fails { Invoke-RecoverProfileTransaction } 'changed outside the transaction'
    Assert-True ([IO.File]::ReadAllText($first) -ceq $after) 'Recovery wrote before validating all targets.'
    Assert-True ([IO.File]::ReadAllText($second) -ceq 'another mod changed this') 'Recovery overwrote external changes.'
    [IO.File]::WriteAllText($second,'new addition')
    Invoke-RecoverProfileTransaction

    # Original-absence is a valid postimage when a profile removes an addition.
    Start-ProfileTransaction $manifest
    Register-ProfileTransactionMutation -Path $first
    Remove-Item -LiteralPath $first
    $script:ProfileTransaction = $null
    Invoke-RecoverProfileTransaction
    Assert-True ([IO.File]::ReadAllText($first) -ceq $before) 'Interrupted removal was not restored.'

    # Restore exactly the three owned INI keys; retain another mod and user data.
    $reshade = [pscustomobject]@{ originalExists=$false; restoredAtUtc=$null; managedKeys=@(
        [pscustomobject]@{section='ADDON';key='LoadFromDllMain';installedValue='renodx-dlss5.addon64';originalPresent=$false},
        [pscustomobject]@{section='RenoDX.DLSS5';key='EnableHooks';installedValue='2';originalPresent=$false},
        [pscustomobject]@{section='RenoDX.DLSS5';key='NeuralUplift';installedValue='1';originalPresent=$false}) }
    $owner = [pscustomobject]@{reshadeConfig=$reshade}
    [IO.File]::WriteAllText($script:ReShadeConfigPath,"[ADDON]`r`nLoadFromDllMain=renodx-dlss5.addon64`r`n[RenoDX.DLSS5]`r`nEnableHooks=2`r`nNeuralUplift=0`r`nMyPreference=7`r`n[OtherMod]`r`nCustom=keep`r`n")
    Restore-ReShadeConfig $owner
    $text=[IO.File]::ReadAllText($script:ReShadeConfigPath)
    Assert-True ($text.Contains('Custom=keep') -and $text.Contains('MyPreference=7')) 'Unrelated shared INI data was removed.'
    Assert-True (-not $text.Contains('EnableHooks=')) 'Owned key was not removed.'
    [IO.File]::WriteAllText($script:ReShadeConfigPath,'new file after removal')
    Restore-ReShadeConfig $owner
    Assert-True ([IO.File]::ReadAllText($script:ReShadeConfigPath) -ceq 'new file after removal') 'Repeated cleanup acquired later data.'
    $reshade.restoredAtUtc=$null
    [IO.File]::WriteAllText($script:ReShadeConfigPath,"[RenoDX.DLSS5]`r`nEnableHooks=2`r`nNeuralUplift=1`r`n")
    Restore-ReShadeConfig $owner
    Assert-True (-not (Test-Path -LiteralPath $script:ReShadeConfigPath)) 'Empty originally absent INI was retained.'

    # Only managed batch assignments are restored, without old whole-file copy.
    $backupRoot=Join-Path $script:StateRoot 'backups\fixture'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $originalConfig=Join-Path $backupRoot 'config.bat'
    [IO.File]::WriteAllText($originalConfig,"set EVEJS_CLIENT_PATH=old-client`r`nset EVEJS_CLIENT_EXE=`r`nset OTHER=old`r`n")
    [IO.File]::WriteAllText($script:ConfigPath,('set "EVEJS_CLIENT_PATH='+$script:ClientRoot+'"'+"`r`nset EVEJS_CLIENT_EXE=bin64\exefile.exe`r`nset TRINITYPLATFORM=dx12`r`nset EVEJS_DLSS5=on`r`nset OTHER=new`r`n"))
    $batchOwner=[pscustomobject]@{stateRoot=$script:StateRoot;backupDirectory='backups\fixture';config=[pscustomobject]@{backup='config.bat';originalSha256=(Get-Sha256 $originalConfig);installedSha256=$null}}
    Restore-OwnedBatchSettings $batchOwner
    $restored=[IO.File]::ReadAllText($script:ConfigPath)
    Assert-True ($restored.Contains('set OTHER=new') -and $restored.Contains('EVEJS_CLIENT_PATH=old-client')) 'Batch restoration clobbered an unrelated setting or missed the owned setting.'
    Assert-True (-not $restored.Contains('EVEJS_DLSS5=on')) 'Added batch flag remains.'
    Add-Member -InputObject $batchOwner -MemberType NoteProperty -Name reshadeConfig -Value $reshade
    Assert-OwnedConfigRestoration $batchOwner
    # Current Verify intentionally checks the retained receipt's installed bytes,
    # not the current package hash. Prove that prior-version recovery remains
    # verifiable, while a changed retained binary still fails.
    function Assert-WorkspaceLayout { }
    function Read-ActiveManifest { return $script:RetainedFixture }
    function Test-ReShadeConfigForProfile { param($Manifest,$ProfileName) }
    $script:ProfileComponents=@{DLSS5=@('runtime')}
    [IO.File]::WriteAllText($first,'retained 0.5.7 payload')
    $script:RetainedFixture=[pscustomobject]@{status='installed';profile='DLSS5';integrationVersion='0.5.7';executable=[pscustomobject]@{sha256=$script:ExpectedExeSha256};operations=@([pscustomobject]@{destination='bin64\first.dll';kind='replace';component='runtime';installedSha256=(Get-Sha256 $first)})}
    $currentPayload=[pscustomobject]@{integrationVersion='0.5.8';files=@([pscustomobject]@{destination='bin64\first.dll';component='runtime';sha256=('F'*64)})}
    [IO.File]::WriteAllText($script:ConfigPath,('set "EVEJS_CLIENT_PATH='+$script:ClientRoot+'"'+"`r`nset EVEJS_CLIENT_EXE=bin64\exefile.exe`r`nset TRINITYPLATFORM=dx12`r`nset EVEJS_DLSS5=on`r`n"))
    Invoke-Verify -PayloadManifest $currentPayload
    $movedServer=Join-Path $fixture 'server-temporarily-unavailable'
    Move-Item -LiteralPath $script:EveJSRoot -Destination $movedServer
    try {
        Invoke-Verify -PayloadManifest $currentPayload -ClientOnly
    } finally { Move-Item -LiteralPath $movedServer -Destination $script:EveJSRoot }
    Assert-True ($script:RetainedFixture.integrationVersion -ceq '0.5.7') 'Verification relabelled the prior installation.'
    [IO.File]::WriteAllText($first,'changed outside recovery')
    Assert-Fails { Invoke-Verify -PayloadManifest $currentPayload } 'Enabled profile hash mismatch'
    Write-Host 'PASS: operation rollback, prevalidated external drift, interrupted deletion, shared INI preservation, repeated cleanup, empty INI deletion, scoped batch restoration (9 cases, including retained-version verification and byte drift). Disposable mocked client only.'
} finally {
    $script:ProfileTransaction = $null
    if (Test-Path -LiteralPath $fixture) {
        $item=Get-Item -LiteralPath $fixture -Force
        if (-not $item.FullName.StartsWith($tempRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $item.Name -notmatch '^dlss5-recovery-[0-9a-f]{32}$' -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe fixture cleanup.' }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}
