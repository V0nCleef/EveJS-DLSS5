[CmdletBinding()]
param(
    [string]$PackageRoot = '',
    [switch]$CreateZip,
    [switch]$SourceStableGo
)

# Release-preparation tooling only. Never ship this script in the runtime package.
# Check-only is the default. This script neither downloads nor executes payloads.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CreateZip -and -not $SourceStableGo) { throw 'Creating a ZIP requires the reviewed SourceStableGo gate.' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$shippingFiles = @(
    'evejs-launcher.client-mod.json',
    'Install-DLSS5.bat',
    'Uninstall-DLSS5.bat',
    'Verify-DLSS5.bat',
    'README.md',
    'THIRD-PARTY-NOTICES.md',
    'RELEASE-CHECKLIST.md',
    'CHANGELOG.md',
    'SOURCE-GENERATION.md',
    'LICENSE',
    'LICENSING.md',
    'EveJS-Integration\Install-DLSS5.bat',
    'EveJS-Integration\Invoke-Standalone.ps1',
    'EveJS-Integration\Manage-EveJSDLSS5.ps1',
    'EveJS-Integration\payload-manifest.json',
    'EveJS-Integration\Public-Payload.ps1',
    'EveJS-Integration\Restore-Originals.bat',
    'EveJS-Integration\Verify-DLSS5.bat',
    'EveJS-Integration\Verify-Runtime.bat',
    'EveJS-Integration\client-patches\templates\systemmenu_apply_graphics.py.in',
    'EveJS-Integration\client-patches\templates\device_create.py.in',
    'EveJS-Integration\client-patches\tools\local_source.py',
    'EveJS-Integration\client-patches\tools\reconstruct.py',
    'EveJS-Integration\client-patches\tools\build_code_ccp.py',
    'EveJS-Integration\client-patches\tools\run_py27.cpp',
    'EveJS-Integration\client-patches\tools\run_py27.exe',
    'EveJS-Integration\payload\reshade\ReShade64.dll',
    'source\reshade\reshade-6.8.0-evejs-v10.patch',
    'source\reshade\version-6.8.0.9.h',
    'source\reshade\reshade-6.8.0-evejs-v11.patch',
    'source\reshade\version-6.8.0.10.h',
    'source\reshade\BUILDING.md',
    'source\reshade\provenance.json',
    'THIRD-PARTY-NOTICES\NVIDIA-RTX-SDK.txt',
    'THIRD-PARTY-NOTICES\RenoDX-MIT.txt',
    'THIRD-PARTY-NOTICES\ReShade-BSD-3-Clause.txt',
    'THIRD-PARTY-NOTICES\Streamline-MIT.txt',
    'THIRD-PARTY-NOTICES\Microsoft-DirectX-Headers-MIT.txt'
)

function Assert-PlainPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "An absolute path is required: $Path" }
    $full = [IO.Path]::GetFullPath($Path)
    $volume = [IO.Path]::GetPathRoot($full)
    $current = $volume
    foreach ($part in @($full.Substring($volume.Length) -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse points are forbidden in packaging paths: $current"
        }
    }
    return $full.TrimEnd('\')
}

function Get-SafePackagePath {
    param([Parameter(Mandatory = $true)][string]$Relative)
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?"<>|]' -or
        @($Relative -split '[\\/]' | Where-Object { -not $_ -or $_ -in @('.', '..') }).Count -gt 0) {
        throw "Unsafe package-relative path: $Relative"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $script:SourceRoot $Relative))
    if (-not $full.StartsWith($script:SourceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package path escapes its source root: $Relative"
    }
    return (Assert-PlainPath $full)
}

function Get-StreamSha256 {
    param([Parameter(Mandatory = $true)][IO.Stream]$Stream)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Assert-FileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Relative,
        [Parameter(Mandatory = $true)]$Record
    )
    if (-not $script:AllowFiles.Contains($Relative.Replace('/', '\'))) {
        throw "Manifest refers to a file outside the shipping allowlist: $Relative"
    }
    $path = Get-SafePackagePath $Relative
    $hash = [string]$Record.sha256
    if ($hash -notmatch '^[0-9A-Fa-f]{64}$' -or [Int64]$Record.bytes -le 0) {
        throw "Invalid manifest hash or byte count: $Relative"
    }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or [Int64]$item.Length -ne [Int64]$Record.bytes -or
        -not (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.Equals($hash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest byte count or SHA-256 mismatch: $Relative"
    }
}

function Get-ManagerPin {
    param([string]$Text, [string]$VariableName)
    $pattern = '(?m)^\s*\$script:' + [Regex]::Escape($VariableName) + '\s*=\s*"(?<hash>[0-9A-Fa-f]{64})"\s*$'
    $matches = [Regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) { throw "Manager must contain exactly one finalized $VariableName pin." }
    return $matches[0].Groups['hash'].Value.ToUpperInvariant()
}

function Assert-Pin {
    param([string]$Relative, [string]$Expected)
    if ($Expected -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid SHA-256 pin for $Relative" }
    $actual = (Get-FileHash -LiteralPath (Get-SafePackagePath $Relative) -Algorithm SHA256).Hash
    if (-not $actual.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Trust-chain SHA-256 mismatch for $Relative. Expected $Expected; got $actual."
    }
}

if (-not $PackageRoot) { $PackageRoot = Join-Path $PSScriptRoot 'DLSS5' }
$script:SourceRoot = Assert-PlainPath ([IO.Path]::GetFullPath($PackageRoot))
if (-not (Test-Path -LiteralPath $script:SourceRoot -PathType Container)) { throw 'Package source directory is missing.' }
$script:AllowFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$allowDirectories = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($relative in $shippingFiles) {
    if (-not $script:AllowFiles.Add($relative)) { throw "Duplicate shipping allowlist entry: $relative" }
    $parent = Split-Path -Parent $relative
    while ($parent) {
        [void]$allowDirectories.Add($parent)
        $parent = Split-Path -Parent $parent
    }
}
[void]$allowDirectories.Add('EveJS-Integration\tests')

# Walk manually: recursive provider enumeration can traverse a junction before
# its attributes have been inspected. Even excluded test paths must be plain.
$pending = New-Object 'System.Collections.Generic.Queue[string]'
$pending.Enqueue($script:SourceRoot)
while ($pending.Count -gt 0) {
    $directory = $pending.Dequeue()
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Reparse point in source tree: $($item.FullName)"
        }
        $relative = $item.FullName.Substring($script:SourceRoot.Length + 1)
        if ($item.Name -match '(?i)(swapper|^code\.ccp$|^nvngx.*\.dll$|^sl\..*\.dll$|^renodx.*\.(addon64|dll)$)' -or
            ($item.PSIsContainer -and $item.Name -match '(?i)^(cache|caches|private-evidence|vendor|vendor-candidates|ResFiles|_local|_evejs|state(?:-.*)?|backups?)$')) {
            throw "Forbidden downloaded payload, client archive, cache, or private evidence: $relative"
        }
        $testOnly = $relative.Equals('EveJS-Integration\tests', [StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith('EveJS-Integration\tests\', [StringComparison]::OrdinalIgnoreCase)
        if ($item.PSIsContainer) {
            if (-not $testOnly -and -not $allowDirectories.Contains($relative)) { throw "Unrecognized runtime directory: $relative" }
            $pending.Enqueue($item.FullName)
        } elseif (-not $testOnly -and -not $relative.Equals('.release-work', [StringComparison]::OrdinalIgnoreCase) -and
            -not $script:AllowFiles.Contains($relative)) {
            throw "Unrecognized runtime file: $relative"
        }
    }
}

$inventory = New-Object 'System.Collections.Generic.List[object]'
$utf8 = New-Object Text.UTF8Encoding($false, $true)
foreach ($relative in $shippingFiles) {
    $path = Get-SafePackagePath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required shipping file is missing: $relative" }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Length -le 0) { throw "Shipping file is empty: $relative" }
    if ([IO.Path]::GetExtension($relative) -in @('.md', '.txt', '.json', '.ps1', '.bat', '.py', '.in', '.cpp', '.h', '.patch')) {
        # Upstream NVIDIA's notice currently contains Windows-1252 punctuation.
        # Preserve the exact notice bytes while still scanning its text.
        $textEncoding = if ([IO.Path]::GetExtension($relative) -eq '.txt') { [Text.Encoding]::GetEncoding(1252) } else { $utf8 }
        $text = [IO.File]::ReadAllText($path, $textEncoding)
        if ($text -match '(?i)([A-Z]:[\\/](Users|Documents and Settings)[\\/]|[A-Z]:[\\/]Eve Local[\\/]|/Users/|/home/|file:///|\\\\[^\\\s]+\\Users\\)') {
            throw "Local machine or user-directory path in shipped text: $relative"
        }
    }
    $inventory.Add([pscustomobject]@{
        relative = $relative
        bytes = [Int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    })
}

$descriptor = [IO.File]::ReadAllText((Get-SafePackagePath 'evejs-launcher.client-mod.json'), $utf8) | ConvertFrom-Json
if ([int]$descriptor.schemaVersion -ne 3 -or $descriptor.id -ne 'evejs-dlss5' -or $descriptor.version -ne '0.5.6' -or
    $descriptor.manager.path -cne 'EveJS-Integration/Manage-EveJSDLSS5.ps1') {
    throw 'Unexpected development package identity or manager path.'
}
$compatibilityNames = @($descriptor.compatibility.PSObject.Properties.Name | Sort-Object)
if (($compatibilityNames -join ',') -cne 'clientBuild,evejsVersionPolicy,profile' -or
    [string]$descriptor.compatibility.evejsVersionPolicy -cne 'any' -or
    [int]$descriptor.compatibility.clientBuild -ne 3396210 -or
    [string]$descriptor.compatibility.profile -cne 'DLSS5') {
    throw 'Unexpected descriptor compatibility policy.'
}
Assert-Pin 'EveJS-Integration\Manage-EveJSDLSS5.ps1' ([string]$descriptor.manager.sha256)
$managerText = [IO.File]::ReadAllText((Get-SafePackagePath 'EveJS-Integration\Manage-EveJSDLSS5.ps1'), $utf8)
Assert-Pin 'EveJS-Integration\Public-Payload.ps1' (Get-ManagerPin $managerText 'ExpectedPublicPayloadHelperSha256')
Assert-Pin 'EveJS-Integration\payload-manifest.json' (Get-ManagerPin $managerText 'ExpectedPayloadManifestSha256')
$manifest = [IO.File]::ReadAllText((Get-SafePackagePath 'EveJS-Integration\payload-manifest.json'), $utf8) | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 5 -or $manifest.integrationVersion -ne '0.5.6' -or $manifest.generator.id -cne 'evejs-code-ccp-v12-local-source-v1') { throw 'Unexpected payload manifest identity.' }
$bundled = @($manifest.files | Where-Object { $_.sourceKind -eq 'bundled' })
if ($bundled.Count -ne 1 -or $bundled[0].id -ne 'reshade-evejs' -or $bundled[0].packagePath -cne 'payload\reshade\ReShade64.dll') {
    throw 'Only the reviewed ReShade binary may be bundled.'
}
Assert-FileRecord ('EveJS-Integration\' + [string]$bundled[0].packagePath) $bundled[0]
$expectedTools = @{
    'runner' = 'client-patches\tools\run_py27.exe'
    'runner-source' = 'client-patches\tools\run_py27.cpp'
    'builder' = 'client-patches\tools\build_code_ccp.py'
    'graphics-template' = 'client-patches\templates\systemmenu_apply_graphics.py.in'
    'startup-template' = 'client-patches\templates\device_create.py.in'
    'local-source' = 'client-patches\tools\local_source.py'
    'reconstruct' = 'client-patches\tools\reconstruct.py'
}
$toolsSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($tool in @($manifest.generator.tools)) {
    if (-not $expectedTools.ContainsKey([string]$tool.id) -or -not $toolsSeen.Add([string]$tool.id) -or
        [string]$tool.path -cne [string]$expectedTools[[string]$tool.id]) { throw "Unexpected or duplicate generator tool: $($tool.id)" }
    Assert-FileRecord ('EveJS-Integration\' + [string]$tool.path) $tool
}
if ($toolsSeen.Count -ne $expectedTools.Count) { throw 'The generator tool inventory is incomplete.' }

$totalBytes = [Int64]($inventory | Measure-Object -Property bytes -Sum).Sum
Write-Host "CHECK PASSED: $($inventory.Count) shipping files, $totalBytes bytes; finalized trust chain and payload/tool hashes verified."
Write-Host 'Tests and .release-work are excluded. This is an unpublished release candidate; manual acceptance and publication approval are separate gates.'
if (-not $CreateZip) { return }

$outputDirectory = Assert-PlainPath (Join-Path $PSScriptRoot 'candidate-output')
if (Test-Path -LiteralPath $outputDirectory) {
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { throw 'candidate-output is not a directory.' }
} else { New-Item -ItemType Directory -Path $outputDirectory | Out-Null }
$candidateName = 'EveJS-DLSS5-0.5.6-RELEASE-CANDIDATE-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N') + '.zip'
$candidatePath = Join-Path $outputDirectory $candidateName
$partialPath = $candidatePath + '.partial'
if ((Test-Path -LiteralPath $candidatePath) -or (Test-Path -LiteralPath $partialPath)) { throw 'Candidate already exists; nothing will be overwritten.' }

# No staging-tree copy and no deleting old artifacts. A failed build retains its
# uniquely named .partial file for inspection, never a seemingly complete ZIP.
$zipFile = New-Object IO.FileStream($partialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $archive = New-Object IO.Compression.ZipArchive($zipFile, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($record in $inventory) {
            $source = Get-SafePackagePath $record.relative
            $inputFile = New-Object IO.FileStream($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ($inputFile.Length -ne $record.bytes -or (Get-StreamSha256 $inputFile) -ne $record.sha256) {
                    throw "Source changed after validation: $($record.relative)"
                }
                $inputFile.Position = 0
                $entry = $archive.CreateEntry(('DLSS5/' + $record.relative.Replace('\', '/')), [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $entryStream = $entry.Open()
                try { $inputFile.CopyTo($entryStream) } finally { $entryStream.Dispose() }
            } finally { $inputFile.Dispose() }
        }
    } finally { $archive.Dispose() }
} finally { $zipFile.Dispose() }

$checkArchive = [IO.Compression.ZipFile]::OpenRead($partialPath)
try {
    if ($checkArchive.Entries.Count -ne $inventory.Count) { throw 'Candidate ZIP entry count mismatch.' }
    foreach ($record in $inventory) {
        $entry = $checkArchive.GetEntry('DLSS5/' + $record.relative.Replace('\', '/'))
        if ($null -eq $entry -or $entry.Length -ne $record.bytes) { throw "Candidate ZIP entry mismatch: $($record.relative)" }
        $entryStream = $entry.Open()
        try {
            if ((Get-StreamSha256 $entryStream) -ne $record.sha256) { throw "Candidate ZIP SHA-256 mismatch: $($record.relative)" }
        } finally { $entryStream.Dispose() }
    }
} finally { $checkArchive.Dispose() }
[IO.File]::Move($partialPath, $candidatePath)
[pscustomobject]@{
    status = 'RELEASE-CANDIDATE-NOT-MANUALLY-ACCEPTED'
    path = $candidatePath
    bytes = (Get-Item -LiteralPath $candidatePath).Length
    sha256 = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
    files = $inventory.Count
}
