[CmdletBinding()]
param()

# Evaluate selected authored functions only. All process/network/file calls
# below are mocked, except a uniquely named disposable cache directory.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$integration = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dlss5-corrections-' + [Guid]::NewGuid().ToString('N'))
$fixture = [IO.Path]::GetFullPath($fixture)
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
if (-not $fixture.StartsWith($temporaryRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture boundary.' }

function Read-Function {
    param([string]$Path, [string]$Name)
    $tokens = $null; $errors = $null
    $tree = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    $found = @($tree.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true))
    if ($found.Count -ne 1) { throw "Missing or duplicate function: $Name" }
    return $found[0].Extent.Text
}

function Assert-True { param([bool]$Value, [string]$Label) if (-not $Value) { throw $Label } }
function Assert-Fails { param([scriptblock]$Body, [string]$Pattern) try { & $Body } catch { if ($_.Exception.Message -match $Pattern) { return }; throw }; throw "Expected failure: $Pattern" }

$manager = Join-Path $integration 'Manage-EveJSDLSS5.ps1'
foreach ($name in @('Get-TargetClientProcessState', 'Get-IsolatedClientProcesses', 'Assert-NoTargetClientProcess')) {
    . ([scriptblock]::Create((Read-Function $manager $name)))
}
$script:ExePath = 'C:\fixture\selected\bin64\exefile.exe'
$script:FakeProcesses = @()
function Get-PhysicalPath { param($Path) if ($Path -eq 'unreadable') { throw 'unreadable' }; return [string]$Path }
function Get-Process { param($Name, $ErrorAction) return $script:FakeProcesses }

$script:FakeProcesses = @([pscustomobject]@{ Id=11; Path='C:\fixture\other\bin64\exefile.exe' })
Assert-NoTargetClientProcess
Assert-True (@(Get-IsolatedClientProcesses).Count -eq 0) 'Unrelated client was selected.'
$script:FakeProcesses += [pscustomobject]@{ Id=12; Path=$script:ExePath.ToUpperInvariant() }
Assert-Fails { Assert-NoTargetClientProcess } 'selected physical client \(PID 12\)'
$script:FakeProcesses = @([pscustomobject]@{ Id=13; Path=$null })
Assert-Fails { Assert-NoTargetClientProcess } '13 could not be resolved'
$script:FakeProcesses = @([pscustomobject]@{ Id=14; Path='unreadable' })
Assert-Fails { Assert-NoTargetClientProcess } '14 could not be resolved'
$script:FakeProcesses = @()
Assert-NoTargetClientProcess

. ([scriptblock]::Create((Read-Function (Join-Path $integration 'Public-Payload.ps1') 'Initialize-PublicPayload')))
$script:CacheRoot = Join-Path $fixture 'cache'
$script:PayloadRoot = Join-Path $script:CacheRoot 'payload'
$script:IntegrationRoot = $integration
$script:ValidCache = $true
$script:Fetches = 0
$script:Expansions = 0
$script:Signatures = 0
function Assert-PublicBundledAssets { param($Manifest) }
function Assert-PublicPlainPath { param($Path) }
function Assert-PathInsideRoot { param($Path, $Root, $BoundaryName) Assert-True ([IO.Path]::GetFullPath($Path).StartsWith($fixture + '\')) 'Fixture path escaped.' }
function Test-PublicFileRecord { param($Path, $Record) return $script:ValidCache }
function Get-PublicArtifactById { param($Manifest, $Id) return [pscustomobject]@{ id=$Id } }
function Get-VerifiedPublicArtifact { param($Artifact) $script:Fetches += 1; return (Join-Path $fixture 'mock.zip') }
function Expand-VerifiedPublicZipEntry { param($ArchivePath, $Artifact, $File, $Destination) $script:Expansions += 1 }
function Assert-PublicFileRecord { param($Path, $Record, $Label, [switch]$CheckAuthenticode) if ($CheckAuthenticode) { $script:Signatures += 1 } }
function Test-AsciiMarker { param($Path, $Marker) return $true }
$manifest = [pscustomobject]@{ files=@(
    [pscustomobject]@{ id='reshade-evejs'; source='one.dll'; sourceKind='archive'; artifactId='shared'; authenticode=@{} },
    [pscustomobject]@{ id='another'; source='two.dll'; sourceKind='archive'; artifactId='shared'; authenticode=@{} }
) }
try {
    Initialize-PublicPayload $manifest | Out-Null
    Assert-True ($script:Fetches -eq 0 -and $script:Expansions -eq 0) 'Valid cache fetched/extracted an archive.'
    Assert-True ($script:Signatures -eq 2) 'Valid cache skipped final signature checks.'
    $script:ValidCache = $false
    Initialize-PublicPayload $manifest | Out-Null
    Assert-True ($script:Fetches -eq 1 -and $script:Expansions -eq 2) 'Missing files did not share one verified archive fetch.'
    Assert-True ($script:Signatures -eq 4) 'Materialized files skipped final signature checks.'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        $item = Get-Item -LiteralPath $fixture -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing reparse cleanup.' }
        if (-not $item.FullName.StartsWith($temporaryRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $item.Name -notmatch '^dlss5-corrections-[0-9a-f]{32}$') { throw 'Refusing fixture cleanup.' }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}
$wrapper = [IO.File]::ReadAllText((Join-Path $integration 'Verify-Runtime.bat'))
Assert-True ($wrapper -match 'Invoke-Standalone\.ps1" -Action Runtime -ProcessId') 'Explicit PID bypasses standalone target resolution.'
Write-Host 'PASS: target processes (5 cases), lazy cache/signatures (2 cases), explicit-PID wrapper (1 case). No real manager, client or network operation was run.'
