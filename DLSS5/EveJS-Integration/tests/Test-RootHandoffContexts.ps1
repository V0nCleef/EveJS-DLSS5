[CmdletBinding()]
param()

# Execute the authored handoff with controlled providers. No client files,
# processes, certificates, network requests or installations are touched.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path -Parent $PSScriptRoot) 'Manage-EveJSDLSS5.ps1'
$tokens = $null; $errors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-NormalizedPath', 'Set-EveJSRootContext', 'Invoke-ClientScopedRootHandoff')) {
    $selected = @($tree.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($selected.Count -ne 1) { throw "Expected exactly one $name function" }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}

function Assert-Equal($Actual, $Expected) { if ($Actual -cne $Expected) { throw "Expected $Expected; got $Actual" } }
function Assert-Fails([scriptblock]$Body, [string]$Pattern) {
    try { & $Body } catch { if ($_.Exception.Message -match $Pattern) { return }; throw }
    throw "Expected failure: $Pattern"
}
function Assert-NoTargetClientProcess {}
function Assert-WorkspaceLayout {
    Assert-Equal (Split-Path -Parent $script:EveJSRoot) $script:WorkspaceRoot
}
function Read-PayloadManifest { return @{} }
function Assert-EveJSRootContract($Root) { return @{configPath=(Join-Path $Root 'tools\ClientSETUP\scripts\EvEJSConfig.bat')} }
function Write-Step($Message) {}
function Write-Okay($Message) {}
function Read-ActiveManifest { return $script:Receipt }
function Read-ActiveManifestRaw { return $script:Receipt }
function Test-ManifestMatchesPayloadMetadata($Manifest, $PayloadManifest) { return $true }
function Invoke-Verify($PayloadManifest) {
    Assert-Equal $script:WorkspaceRoot 'C:\handoff-fixture\old-workspace'
    Assert-Equal $script:EveJSRoot $script:Receipt.evejsRoot
    if ($script:FailVerify) { throw 'Fixture verification failed' }
}
function Assert-RestoreBackups($Manifest) {}
function Invoke-Restore {
    Assert-Equal $script:WorkspaceRoot 'C:\handoff-fixture\old-workspace'
    $script:Receipt.status = 'restored'
    $script:Restored = $true
}
function Move-TerminalRootStateToHistory($TerminalManifest) {
    Assert-Equal $script:WorkspaceRoot 'C:\handoff-fixture\different\new-workspace'
    Assert-Equal $TerminalManifest.status 'restored'
}
function Invoke-Install {
    Assert-Equal $script:EveJSRoot 'C:\handoff-fixture\different\new-workspace\RootB'
    Assert-Equal $script:WorkspaceRoot 'C:\handoff-fixture\different\new-workspace'
    $script:Installed = $true
}
function Reset-Fixture {
    $script:WorkspaceRoot = 'C:\handoff-fixture\different\new-workspace'
    Set-EveJSRootContext 'C:\handoff-fixture\different\new-workspace\RootB'
    $script:ClientRoot = 'C:\handoff-fixture\client\tq'
    $script:StateRoot = 'C:\handoff-fixture\client\_evejs\dlss5\install'
    $script:Receipt = [pscustomobject]@{
        schemaVersion=5; stateScope='client'; status='installed'
        workspaceRoot='C:\handoff-fixture\old-workspace'
        evejsRoot='C:\handoff-fixture\old-workspace\RootA'
        clientRoot=$script:ClientRoot; stateRoot=$script:StateRoot
        config=[pscustomobject]@{path='C:\handoff-fixture\old-workspace\RootA\tools\ClientSETUP\scripts\EvEJSConfig.bat'}
    }
    $script:FailVerify = $false
    $script:Restored = $false
    $script:Installed = $false
}

Reset-Fixture
Invoke-ClientScopedRootHandoff $script:Receipt
Assert-Equal $script:Restored $true
Assert-Equal $script:Installed $true

Reset-Fixture
$script:FailVerify = $true
Assert-Fails { Invoke-ClientScopedRootHandoff $script:Receipt } 'Fixture verification failed'
Assert-Equal $script:WorkspaceRoot 'C:\handoff-fixture\different\new-workspace'
Assert-Equal $script:EveJSRoot 'C:\handoff-fixture\different\new-workspace\RootB'
Assert-Equal $script:Restored $false
Assert-Equal $script:Installed $false

Reset-Fixture
$script:Receipt.clientRoot = 'C:\handoff-fixture\unrelated-client\tq'
Assert-Fails { Invoke-ClientScopedRootHandoff $script:Receipt } 'different client or state root'
Assert-Equal $script:Restored $false

Reset-Fixture
$script:Receipt.workspaceRoot = 'C:\handoff-fixture\wrong-owner'
Assert-Fails { Invoke-ClientScopedRootHandoff $script:Receipt } 'recorded immediate workspace'
Assert-Equal $script:Restored $false
Write-Host 'PASS non-sibling handoff contexts, failure restoration, client identity and workspace ownership (controlled providers)'
