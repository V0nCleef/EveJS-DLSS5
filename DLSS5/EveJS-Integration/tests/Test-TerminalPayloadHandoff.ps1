# Control-flow contract only; real restored-file proof is covered by copied-client acceptance.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'Manage-EveJSDLSS5.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$definition=@($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Invoke-ClientScopedRootHandoff' })
if ($definition.Count -ne 1) { throw 'Missing handoff function' }
. ([scriptblock]::Create($definition[0].Extent.Text))
function Assert-NoTargetClientProcess {}
function Assert-WorkspaceLayout {}
function Assert-EveJSRootContract($Root) { return @{configPath=(Join-Path $Root 'tools\ClientSETUP\scripts\EvEJSConfig.bat')} }
function Read-PayloadManifest { return @{integrationVersion='new-payload'} }
function Get-NormalizedPath($Path) { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
function Set-EveJSRootContext($Root) { $script:EveJSRoot=$Root }
function Write-Step($Message) {}
function Write-Okay($Message) {}
function Read-ActiveManifest { return $script:Active }
function Read-ActiveManifestRaw { return $script:Active }
function Test-ManifestMatchesPayloadMetadata { param($Manifest,$PayloadManifest) return $false }
function Invoke-Verify { param($PayloadManifest) throw 'Installed payload verification should not run for restored bytes' }
function Assert-RestoreBackups { param($Manifest) $script:BackupChecks++ }
function Assert-RecoveryRollbackComplete {
    param($Manifest)
    $script:RollbackChecks++
    if ($script:Corrupt) { throw 'controlled original-byte mismatch' }
}
function Move-TerminalRootStateToHistory { param($TerminalManifest) $script:Archived=$TerminalManifest }
function Invoke-Install { $script:Installs++; $script:Active=[pscustomobject]@{status='installed';evejsRoot=$script:EveJSRoot} }
foreach ($case in @('restored','rolledBack','installed','corrupt')) {
    $script:WorkspaceRoot='C:\fixture'
    $script:EveJSRoot='C:\fixture\new'
    $script:ClientRoot='C:\fixture\client'
    $script:StateRoot='C:\fixture\state'
    $script:BackupChecks=0; $script:RollbackChecks=0; $script:Installs=0
    $script:Archived=$null; $script:Corrupt=$case -eq 'corrupt'
    $status=if ($case -eq 'corrupt') {'restored'} else {$case}
    $script:Active=[pscustomobject]@{schemaVersion=5;stateScope='client';status=$status;workspaceRoot='C:\fixture';evejsRoot='C:\fixture\old';clientRoot=$script:ClientRoot;stateRoot=$script:StateRoot;config=[pscustomobject]@{path='C:\fixture\old\tools\ClientSETUP\scripts\EvEJSConfig.bat'}}
    $failure=''
    try { Invoke-ClientScopedRootHandoff $script:Active } catch { $failure=$_.Exception.Message }
    if ($case -in @('restored','rolledBack')) {
        if ($failure -or $script:RollbackChecks -ne 1 -or $script:BackupChecks -ne 1 -or $script:Installs -ne 1 -or $script:Archived.evejsRoot -ne 'C:\fixture\old') { throw "Terminal handoff failed: $failure" }
    } else {
        $expected=if ($case -eq 'corrupt') {'controlled original-byte mismatch'} else {'exact client-scoped payload metadata'}
        if ($failure -notlike "*$expected*" -or $script:Installs -ne 0 -or $null -ne $script:Archived) { throw "Unsafe or unexpected rejection: $failure" }
    }
    if ($script:EveJSRoot -ne 'C:\fixture\new') { throw 'Target context was not restored' }
    Write-Host "PASS $case changed-payload handoff"
}
