[CmdletBinding()]
param(
    [ValidateSet('Status', 'Preflight', 'Install', 'Ensure', 'Verify', 'Runtime', 'Restore')]
    [string]$Action = 'Ensure',
    [string]$EveJSRootPath = '',
    [string]$ClientRoot = '',
    [ValidateRange(0, [int]::MaxValue)]
    [int]$ProcessId = 0,
    [switch]$NonInteractive,
    [switch]$ResolveOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-StandalonePhysicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volume = [IO.Path]::GetPathRoot($full)
    $current = $volume
    foreach ($part in @($full.Substring($volume.Length) -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $part
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $targets = @($item.Target)
            if ($targets.Count -ne 1 -or -not $targets[0]) {
                throw "Cannot resolve reparse point unambiguously: $candidate"
            }
            $target = [string]$targets[0]
            if (-not [IO.Path]::IsPathRooted($target)) {
                $target = Join-Path (Split-Path -Parent $candidate) $target
            }
            $current = [IO.Path]::GetFullPath($target)
        } else {
            $current = $candidate
        }
    }
    return [IO.Path]::GetFullPath($current).TrimEnd('\')
}

function Resolve-EveJSDlss5StandaloneTarget {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [string]$SelectedEveJSRoot = '',
        [string]$SelectedClientRoot = '',
        [switch]$NoPrompt
    )

    $evejsRoot = $SelectedEveJSRoot.Trim().Trim('"')
    if (-not $evejsRoot) {
        $packageParent = Split-Path -Parent ([IO.Path]::GetFullPath($PackageRoot))
        if ((Split-Path -Leaf $packageParent).Equals('mods', [StringComparison]::OrdinalIgnoreCase)) {
            $evejsRoot = Split-Path -Parent $packageParent
        }
    }
    if (-not $evejsRoot) {
        if ($NoPrompt) {
            throw 'Could not infer the EveJS root. Supply -EveJSRootPath or place DLSS5 inside <EveJS>\mods.'
        }
        $evejsRoot = (Read-Host 'Path to your EveJS folder (the folder containing package.json and Play.bat)').Trim().Trim('"')
    }
    if (-not $evejsRoot -or -not [IO.Path]::IsPathRooted($evejsRoot)) {
        throw 'EveJSRootPath must be an absolute folder path.'
    }
    $evejsRoot = [IO.Path]::GetFullPath($evejsRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $evejsRoot -PathType Container)) {
        throw "EveJS folder does not exist: $evejsRoot"
    }
    $rootItem = Get-Item -LiteralPath $evejsRoot
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The selected EveJS root is a reparse point. Select its real folder.'
    }
    $packageJsonPath = Join-Path $evejsRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        throw "The selected folder has no package.json: $evejsRoot"
    }
    $packageJson = [IO.File]::ReadAllText($packageJsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $packageProperties = @($packageJson.PSObject.Properties.Name)
    $evejsVersion = if ($packageProperties -contains 'version') { ([string]$packageJson.version).Trim() } else { '' }
    if ($packageProperties -notcontains 'name' -or
        -not ([string]$packageJson.name).Equals('eve.js', [StringComparison]::Ordinal) -or
        [string]::IsNullOrWhiteSpace($evejsVersion) -or
        $evejsVersion.Length -gt 64 -or
        $evejsVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]*$' -or
        $evejsVersion.Contains('..')) {
        throw 'The selected folder must contain an eve.js package with a non-empty, sane version string.'
    }

    $configPath = Join-Path $evejsRoot 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "EveJS client configuration is missing: $configPath"
    }
    $configLayoutText = [IO.File]::ReadAllText($configPath)
    foreach ($requiredSetting in @('EVEJS_CLIENT_PATH', 'EVEJS_CLIENT_EXE')) {
        $settingMatches = [Regex]::Matches(
            $configLayoutText,
            '(?im)^\s*set\s+"' + [Regex]::Escape($requiredSetting) + '=[^"]*"\s*$'
        )
        if ($settingMatches.Count -ne 1) {
            throw "EvEJSConfig.bat must contain exactly one quoted $requiredSetting setting."
        }
    }
    $client = $SelectedClientRoot.Trim().Trim('"')
    if (-not $client) {
        # Read the setting as data. Never execute a user-controlled batch file
        # merely to discover the target client.
        $configText = [IO.File]::ReadAllText($configPath)
        $matches = [Regex]::Matches($configText, '(?im)^\s*set\s+"EVEJS_CLIENT_PATH=([^"]*)"\s*$')
        if ($matches.Count -ne 1) {
            throw 'EvEJSConfig.bat must contain exactly one quoted EVEJS_CLIENT_PATH setting, or supply -ClientRoot.'
        }
        $client = $matches[0].Groups[1].Value.Trim()
        $client = [Regex]::Replace($client, '(?i)%EVEJS_REPO_ROOT%', [Text.RegularExpressions.MatchEvaluator]{ param($match) $evejsRoot })
        if ($client.Contains('%')) {
            throw 'EVEJS_CLIENT_PATH contains an unresolved batch variable. Supply -ClientRoot with the exact client path.'
        }
    }
    if (-not $client) {
        if ($NoPrompt) {
            throw 'EVEJS_CLIENT_PATH is empty. Supply -ClientRoot or configure the client in EveJS first.'
        }
        $client = (Read-Host 'Path to the local EveJS tq client folder').Trim().Trim('"')
    }
    if (-not $client -or -not [IO.Path]::IsPathRooted($client)) {
        throw 'ClientRoot must be an absolute tq folder path.'
    }
    $client = [IO.Path]::GetFullPath($client).TrimEnd('\')
    foreach ($required in @($client, (Join-Path $client 'start.ini'), (Join-Path $client 'bin64\exefile.exe'))) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required client path is missing: $required"
        }
    }
    $clientItem = Get-Item -LiteralPath $client
    if ($clientItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The selected client root is a reparse point. Select its real tq folder.'
    }
    $client = Resolve-StandalonePhysicalPath $client

    return [pscustomobject][ordered]@{
        WorkspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $evejsRoot)).TrimEnd('\')
        EveJSRootPath = $evejsRoot
        ClientRoot = $client
        StateRootPath = Join-Path (Split-Path -Parent $client) '_evejs\dlss5\install'
    }
}

try {
    $packageRoot = Split-Path -Parent $PSScriptRoot
    $target = Resolve-EveJSDlss5StandaloneTarget `
        -PackageRoot $packageRoot `
        -SelectedEveJSRoot $EveJSRootPath `
        -SelectedClientRoot $ClientRoot `
        -NoPrompt:$NonInteractive
    if ($ResolveOnly) {
        $target
        return
    }
    Write-Host "EveJS root: $($target.EveJSRootPath)"
    Write-Host "Client:     $($target.ClientRoot)"
    Write-Host "Client state: $($target.StateRootPath)"
    Write-Host ''
    $manager = Join-Path $PSScriptRoot 'Manage-EveJSDLSS5.ps1'
    & $manager `
        -Action $Action `
        -Profile 'DLSS5' `
        -WorkspaceRoot $target.WorkspaceRoot `
        -EveJSRootPath $target.EveJSRootPath `
        -ClientRoot $target.ClientRoot `
        -StateRootPath $target.StateRootPath `
        -ProcessId $ProcessId
    if (-not $?) { exit 1 }
} catch {
    Write-Host ("DLSS5 standalone error: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
