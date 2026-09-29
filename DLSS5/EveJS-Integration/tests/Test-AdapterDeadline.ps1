[CmdletBinding()]
param()

# Exercise the adapter's real process wait against a harmless disposable
# manager. No EVE files, downloads, or production manager are used.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$adapter = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-LauncherMod.ps1'
$tokens = $null
$errors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($adapter, [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) { throw "Adapter does not parse: $($errors[0].Message)" }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture = Join-Path $tempRoot ('evejs-dlss5-deadline-' + [Guid]::NewGuid().ToString('N'))
$fixture = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
if (-not $fixture.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid disposable fixture path.' }
New-Item -ItemType Directory -Path $fixture | Out-Null
$marker = Join-Path $fixture '.fixture-owner'
[IO.File]::WriteAllText($marker, 'Test-AdapterDeadline.ps1')
try {
    $stub = @'
param($Action, $Profile, $ClientRoot, $EveJSRootPath, $WorkspaceRoot)
Write-Output "stage-$Action"
if ($Action -eq 'Verify') { Start-Sleep -Seconds 5 } else { Start-Sleep -Seconds 1 }
Write-Output "complete-$Action"
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'Manage-EveJSDLSS5.ps1'), $stub)
    foreach ($name in @('Get-PlainPath', 'Invoke-BinaryManager')) {
        $matches = @($tree.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        if ($matches.Count -ne 1) { throw "Missing adapter function $name" }
        $source = $matches[0].Extent.Text
        if ($name -eq 'Invoke-BinaryManager') {
            $old = "Join-Path `$PSScriptRoot 'Manage-EveJSDLSS5.ps1'"
            $new = "Join-Path `$script:FixtureRoot 'Manage-EveJSDLSS5.ps1'"
            if ($source.Split([string[]]@($old), [StringSplitOptions]::None).Count -ne 2) { throw 'Manager fixture substitution is ambiguous.' }
            $source = $source.Replace($old, $new)
        }
        . ([scriptblock]::Create($source))
    }
    $script:FixtureRoot = $fixture
    $script:PackageRoot = $fixture
    $server = Join-Path $fixture 'server'
    $client = Join-Path $fixture 'client'
    New-Item -ItemType Directory -Path $server, $client | Out-Null

    $script:OperationClock = [Diagnostics.Stopwatch]::StartNew()
    $script:ManagerBudgetMilliseconds = 17000
    Invoke-BinaryManager -Action Ensure -Client $client -EveJS $server
    if ($script:OperationClock.Elapsed.TotalSeconds -gt 7) { throw 'A one-second manager exceeded its remaining budget.' }

    $script:OperationClock = [Diagnostics.Stopwatch]::StartNew()
    $script:ManagerBudgetMilliseconds = 13000
    $failure = $null
    try { Invoke-BinaryManager -Action Verify -Client $client -EveJS $server }
    catch { $failure = $_.Exception.Message }
    if (-not $failure -or $failure -notmatch 'Verify timed out within the launcher operation budget' -or
        $failure -notmatch 'stage-Verify') { throw "Timeout did not retain the manager stage: $failure" }
    if ($script:OperationClock.Elapsed.TotalSeconds -gt 9) { throw 'Timed-out manager was not stopped promptly.' }
    Write-Host 'PASS adapter manager wait uses its operation budget and reports the last stage.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
    if (-not $resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^evejs-dlss5-deadline-[0-9a-f]{32}$' -or
        -not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        [IO.File]::ReadAllText($marker) -cne 'Test-AdapterDeadline.ps1') {
        throw "Refusing disposable fixture cleanup: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
