Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
. (Join-Path $integration 'Client-Attachments.ps1')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $integration 'Manage-EveJSDLSS5.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('dlss5-client-only-'+[Guid]::NewGuid().ToString('N'))
$script:WorkspaceRoot=Join-Path $fixture 'new-workspace'
Set-EveJSRootContext (Join-Path $script:WorkspaceRoot 'unattached-server')
$selected=$script:EveJSRoot
$script:Receipt=[pscustomobject]@{evejsRoot=(Join-Path $fixture 'deleted-owner');workspaceRoot=$fixture}
$script:RestoreCalls=0
function Read-ActiveManifestRaw { return $script:Receipt }
function Invoke-Restore {
    param([switch]$PhysicalOnly,[switch]$ClientOnly)
    if (-not $PhysicalOnly -or -not $ClientOnly) { throw 'Removal must use both physical-only and client-only modes.' }
    if ($script:EveJSRoot -ne $script:Receipt.evejsRoot) { throw 'Wrong retained journal context.' }
    if (Test-Path -LiteralPath $script:EveJSRoot) { throw 'The deleted server should not be recreated.' }
    $script:RestoreCalls++
}
Invoke-UninstallClient
if ($script:RestoreCalls -ne 1 -or $script:EveJSRoot -ne $selected) { throw 'Removal did not restore the calling context.' }
$script:Receipt=$null
$rejected=$false
try { Invoke-UninstallClient } catch { $rejected=$_.Exception.Message -match 'No DLSS5 install journal' }
if (-not $rejected) { throw 'Removal without an ownership journal must remain unavailable.' }
Write-Host 'CLIENT-ONLY REMOVAL CHECKS PASSED'
