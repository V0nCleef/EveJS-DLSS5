[CmdletBinding()]
param(
    [ValidateSet("Status", "Preflight", "Install", "Ensure", "UpgradePayload", "ApplyProfile", "Verify", "Runtime", "Restore")]
    [string]$Action = "Status",

    [ValidateSet("Original", "UpdatedRuntime", "NeuralRuntime", "ReShadeOnly", "Full", "NativePlusNeural", "NativePlusReShade", "DLSS5")]
    [string]$Profile = "DLSS5",

    [ValidateRange(0, [int]::MaxValue)]
    [int]$ProcessId = 0,

    [string]$WorkspaceRoot = "",

    [string]$EveJSRootPath = "",

    [string]$ClientRoot = "",

    [ValidatePattern('^state(?:-[A-Za-z0-9][A-Za-z0-9._-]*)?$')]
    [string]$StateDirectory = "state",

    [string]$StateRootPath = "",

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-InitialPhysicalPath {
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
    return [IO.Path]::GetFullPath($current).TrimEnd("\\")
}

$script:IntegrationRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd("\\")
$script:DlssRoot = [IO.Path]::GetFullPath((Split-Path -Parent $script:IntegrationRoot)).TrimEnd("\\")
$packageParent = [IO.Path]::GetFullPath((Split-Path -Parent $script:DlssRoot)).TrimEnd("\\")
$detectedEveJSRoot = $null
if ((Split-Path -Leaf $packageParent).Equals('mods', [StringComparison]::OrdinalIgnoreCase)) {
    $candidateEveJSRoot = [IO.Path]::GetFullPath((Split-Path -Parent $packageParent)).TrimEnd("\\")
    $candidatePackageJson = Join-Path $candidateEveJSRoot 'package.json'
    if (Test-Path -LiteralPath $candidatePackageJson -PathType Leaf) {
        $detectedEveJSRoot = $candidateEveJSRoot
    }
}
$defaultWorkspaceRoot = if ($detectedEveJSRoot) {
    [IO.Path]::GetFullPath((Split-Path -Parent $detectedEveJSRoot)).TrimEnd("\\")
} else {
    $packageParent
}
if ($WorkspaceRoot) {
    if (-not [IO.Path]::IsPathRooted($WorkspaceRoot)) {
        throw "WorkspaceRoot must be an absolute path."
    }
    $script:WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd("\\")
} else {
    $script:WorkspaceRoot = $defaultWorkspaceRoot
}

if ($EveJSRootPath) {
    if (-not [IO.Path]::IsPathRooted($EveJSRootPath)) {
        throw "EveJSRootPath must be an absolute path."
    }
    $script:EveJSRoot = [IO.Path]::GetFullPath($EveJSRootPath).TrimEnd("\\")
} elseif ($detectedEveJSRoot) {
    $script:EveJSRoot = [IO.Path]::GetFullPath($detectedEveJSRoot).TrimEnd("\\")
} else {
    throw "EveJSRootPath is required when the DLSS5 package is not inside an EveJS mods folder."
}

$defaultClientRoot = Join-Path $script:WorkspaceRoot "EVE Online - 3396210\EVE Online - 3396210\tq"
if ($ClientRoot) {
    if (-not [IO.Path]::IsPathRooted($ClientRoot)) {
        throw "ClientRoot must be an absolute path."
    }
    $script:ClientRoot = Resolve-InitialPhysicalPath $ClientRoot
} else {
    $script:ClientRoot = Resolve-InitialPhysicalPath $defaultClientRoot
}
$script:BinRoot = Join-Path $script:ClientRoot "bin64"
$script:ExePath = Join-Path $script:BinRoot "exefile.exe"
$script:ConfigPath = Join-Path $script:EveJSRoot "tools\ClientSETUP\scripts\EvEJSConfig.bat"
$script:PayloadManifestPath = Join-Path $script:IntegrationRoot "payload-manifest.json"
$script:PublicPayloadHelperPath = Join-Path $script:IntegrationRoot "Public-Payload.ps1"
$script:StateDirectory = $StateDirectory
$expectedClientStateRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $script:ClientRoot) "_evejs\dlss5\install")).TrimEnd("\\")
if ($StateRootPath) {
    if (-not [IO.Path]::IsPathRooted($StateRootPath)) {
        throw "StateRootPath must be an absolute path."
    }
    $script:StateRoot = [IO.Path]::GetFullPath($StateRootPath).TrimEnd("\\")
    if (-not $script:StateRoot.Equals($expectedClientStateRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "StateRootPath must use the client-scoped location '$expectedClientStateRoot'."
    }
} else {
    $script:StateRoot = $expectedClientStateRoot
}
$script:CacheRoot = Join-Path $script:StateRoot "cache"
$script:PayloadRoot = Join-Path $script:CacheRoot "payload"
$script:ActiveManifestPath = Join-Path $script:StateRoot "active-install.json"
$script:BaselinePath = Join-Path $script:StateRoot "baseline-tq.json"
$script:ReShadeConfigPath = Join-Path $script:BinRoot "ReShade.ini"
$script:ReShadeLogPath = Join-Path $script:BinRoot "ReShade.log"
$script:ExpectedExeSha256 = "2AAF7A9A8DFCDE85E4ADB50C1ECCD3756A4D29AEB854DFE69629846BA56EE979"
$script:ExpectedPublicPayloadHelperSha256 = "B21B06F0EFD561E45DABAC6174D2FA71870EDF3923FE3140D591332AE7091EAA"
$script:ExpectedPayloadManifestSha256 = "B722CD61F078C7079BC76085BB14127062FA7B2E67B294A79C28864E061CDB4B"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:ManagedReShadeKeys = @(
    [pscustomobject][ordered]@{
        section = "ADDON"
        key = "LoadFromDllMain"
        value = "renodx-dlss5.addon64"
    },
    [pscustomobject][ordered]@{
        section = "RenoDX.DLSS5"
        key = "EnableHooks"
        value = "2"
    },
    [pscustomobject][ordered]@{
        section = "RenoDX.DLSS5"
        key = "NeuralUplift"
        value = "1"
    }
)
$script:ProfileComponents = @{
    Original = @()
    # Legacy replacement-stack profiles are retained as A/B diagnostics. They
    # are not the community install path because they replace EVE's existing
    # DLSS and Streamline runtimes.
    UpdatedRuntime = @("runtime")
    NeuralRuntime = @("runtime", "neuralRuntime")
    ReShadeOnly = @("runtime", "neuralRuntime", "reshade")
    Full = @("runtime", "neuralRuntime", "reshade", "renodx", "clientGuard")

    # Additive profiles deliberately leave EVE's native DLSS/Streamline files
    # untouched. DLSS 5 is a neural post-pass over native DLSS output, not a
    # replacement Trinity upscaler enum.
    NativePlusNeural = @("neuralRuntime")
    NativePlusReShade = @("neuralRuntime", "reshade")
    DLSS5 = @("neuralRuntime", "reshade", "renodx", "clientGuard")
}

function Write-Step {
    param([string]$Message)
    Write-Host ("[DLSS5] " + $Message) -ForegroundColor Cyan
}

function Write-Okay {
    param([string]$Message)
    Write-Host ("  OK  " + $Message) -ForegroundColor Green
}

function Write-WarningLine {
    param([string]$Message)
    Write-Host ("  WARN  " + $Message) -ForegroundColor Yellow
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Read-TextFileShared {
    param([Parameter(Mandatory = $true)][string]$Path)

    # ReShade can keep ReShade.log open without granting the default
    # ReadAllText sharing mode. Runtime verification must inspect the live log,
    # so open it explicitly with read/write/delete sharing and take a snapshot.
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $stream = New-Object IO.FileStream(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        $share
    )
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)

    # ProcessModule.FileName can expose a perfectly valid Windows path with
    # redundant separators (for example, "bin64\\_trinity_dx12.dll"). .NET
    # Framework's GetFullPath does not collapse those separators, which made
    # the containment check reject the isolated client it was meant to prove.
    # Preserve the volume/UNC root and canonicalize only the remainder.
    $root = [IO.Path]::GetPathRoot($full)
    if ($root -and $full.Length -gt $root.Length) {
        $separator = [IO.Path]::DirectorySeparatorChar.ToString()
        $remainder = $full.Substring($root.Length) -replace '[\\/]+', $separator
        $full = $root + $remainder
    }
    return $full.TrimEnd("\\")
}

function Get-PhysicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedPath $Path
    $root = [IO.Path]::GetPathRoot($full)
    if (-not $root) {
        return $full
    }

    $current = $root
    $remainder = $full.Substring($root.Length)
    foreach ($part in @($remainder -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $part
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $targets = @($item.Target)
                if ($targets.Count -ne 1 -or -not $targets[0]) {
                    throw "Cannot resolve reparse point unambiguously: $candidate"
                }
                $target = [string]$targets[0]
                if (-not [IO.Path]::IsPathRooted($target)) {
                    $target = Join-Path (Split-Path -Parent $candidate) $target
                }
                $current = Get-NormalizedPath $target
                continue
            }
        }
        $current = $candidate
    }
    return (Get-NormalizedPath $current)
}

function Assert-NoReparsePointsInExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BoundaryName
    )

    $full = Get-NormalizedPath $Path
    $volume = [IO.Path]::GetPathRoot($full)
    if (-not $volume) {
        throw "Cannot validate an unrooted $BoundaryName path: $full"
    }

    $current = $volume
    foreach ($part in @($full.Substring($volume.Length) -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing a reparse point in the $BoundaryName path: $current"
        }
    }
    return $full
}

function Assert-ClientScopedStateBoundary {
    $physicalClient = Get-PhysicalPath $script:ClientRoot
    $expectedState = Get-NormalizedPath (Join-Path (Split-Path -Parent $physicalClient) "_evejs\dlss5\install")
    $selectedState = Get-NormalizedPath $script:StateRoot
    if (-not $selectedState.Equals($expectedState, [StringComparison]::OrdinalIgnoreCase)) {
        throw "DLSS5 mutable state must be client-scoped at '$expectedState'."
    }

    Assert-NoReparsePointsInExistingPath -Path $selectedState -BoundaryName "client-scoped state" | Out-Null

    # These are the only mutable top-level state trees owned by the manager or
    # the reviewed payload helper. Reject a pre-existing junction even before
    # an operation needs that tree, so no receipt or backup can be redirected
    # between preflight and rollback.
    foreach ($ownedChild in @("cache", "backups", "history", "uninstall-preserved")) {
        Assert-NoReparsePointsInExistingPath `
            -Path (Join-Path $selectedState $ownedChild) `
            -BoundaryName "client-scoped state" | Out-Null
    }
    return $selectedState
}

function Test-FileDirectlyInDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$DirectoryPath
    )
    $file = Get-NormalizedPath $FilePath
    $parent = Get-NormalizedPath ([IO.Path]::GetDirectoryName($file))
    $directory = Get-NormalizedPath $DirectoryPath
    return $parent.Equals($directory, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$BoundaryName
    )
    $full = Get-NormalizedPath $Path
    $normalizedRoot = Get-NormalizedPath $Root
    $inside = $false
    if ($full.Length -ge $normalizedRoot.Length -and
        $full.Substring(0, $normalizedRoot.Length).Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $inside = ($full.Length -eq $normalizedRoot.Length) -or
            ($full[$normalizedRoot.Length] -eq [IO.Path]::DirectorySeparatorChar)
    }
    if (-not $inside) {
        throw "Refusing path outside the authorized $BoundaryName boundary: $full"
    }
    return $full
}

function Assert-ClientScopedStatePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-ClientScopedStateBoundary | Out-Null
    $full = Assert-PathInsideRoot -Path $Path -Root $script:StateRoot -BoundaryName "client-scoped state"
    Assert-NoReparsePointsInExistingPath -Path $full -BoundaryName "client-scoped state" | Out-Null
    return $full
}

function Assert-OwnedClientPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Assert-PathInsideRoot -Path $Path -Root $script:ClientRoot -BoundaryName "owned client"
    Assert-NoReparsePointsInExistingPath -Path $full -BoundaryName "owned client" | Out-Null
    return $full
}

function Assert-OwnedEveJSPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Assert-PathInsideRoot -Path $Path -Root $script:EveJSRoot -BoundaryName "owned EveJS"
    Assert-NoReparsePointsInExistingPath -Path $full -BoundaryName "owned EveJS" | Out-Null
    return $full
}

function Assert-PathInsideAuthorizedRoots {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedPath $Path

    # State may sit lexically below WorkspaceRoot in synthetic or portable
    # layouts. Check it first so a broad workspace match can never bypass the
    # physical no-reparse policy for receipts, backups, cache, or history.
    try {
        return (Assert-ClientScopedStatePath -Path $full)
    } catch {
        if ($_.Exception.Message -notlike "Refusing path outside the authorized client-scoped state boundary:*") {
            throw
        }
    }

    try {
        return (Assert-OwnedClientPath -Path $full)
    } catch {
        if ($_.Exception.Message -notlike "Refusing path outside the authorized owned client boundary:*") {
            throw
        }
    }

    try {
        return (Assert-OwnedEveJSPath -Path $full)
    } catch {
        if ($_.Exception.Message -notlike "Refusing path outside the authorized owned EveJS boundary:*") {
            throw
        }
    }

    foreach ($root in @($script:IntegrationRoot, $script:WorkspaceRoot)) {
        try {
            return (Assert-PathInsideRoot -Path $full -Root $root -BoundaryName "write")
        } catch {
            if ($_.Exception.Message -notlike "Refusing path outside the authorized write boundary:*") {
                throw
            }
        }
    }
    throw "Refusing path outside every authorized write root: $full"
}

function Move-StagedFileIntoPlace {
    param(
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        # Windows PowerShell 5.1 cannot bind File.Replace when backupFileName is
        # null, even though newer .NET runtimes accept it. Use a real temporary
        # backup path, then remove that transient copy after the atomic swap.
        $replaceBackup = $Destination + ".evejs-dlss5.previous." + $PID + "." + [Guid]::NewGuid().ToString("N") + ".tmp"
        try {
            [IO.File]::Replace($StagedPath, $Destination, $replaceBackup)
        } finally {
            if (Test-Path -LiteralPath $replaceBackup -PathType Leaf) {
                Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        [IO.File]::Move($StagedPath, $Destination)
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $full = Assert-PathInsideAuthorizedRoots $Path
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporary = $full + ".tmp." + $PID + "." + [Guid]::NewGuid().ToString("N")
    try {
        $json = $Value | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, $script:Utf8NoBom)
        Move-StagedFileIntoPlace -StagedPath $temporary -Destination $full
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Write-TextAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $full = Assert-PathInsideAuthorizedRoots $Path
    $temporary = $full + ".tmp." + $PID + "." + [Guid]::NewGuid().ToString("N")
    try {
        [IO.File]::WriteAllText($temporary, $Text, $script:Utf8NoBom)
        Move-StagedFileIntoPlace -StagedPath $temporary -Destination $full
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Copy-FileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    $sourceFull = Assert-PathInsideAuthorizedRoots $Source
    $destinationFull = Assert-PathInsideAuthorizedRoots $Destination
    $parent = Split-Path -Parent $destinationFull
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporary = $destinationFull + ".evejs-dlss5." + $PID + "." + [Guid]::NewGuid().ToString("N") + ".tmp"
    try {
        Copy-Item -LiteralPath $sourceFull -Destination $temporary
        $actual = Get-Sha256 $temporary
        if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
            throw "Staged hash mismatch for $destinationFull (expected $ExpectedSha256, got $actual)"
        }
        Move-StagedFileIntoPlace -StagedPath $temporary -Destination $destinationFull
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Test-AsciiMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Marker
    )
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    return $text.Contains($Marker)
}

function Get-NeuralLogEvidence {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $registrationCount = [regex]::Matches(
        $Text,
        'Registered add-on "DLSS 5 Neural Rendering"',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    ).Count

    $successfulFrames = [Int64]0
    foreach ($match in [regex]::Matches(
        $Text,
        '(?:inline feature 18 evaluation succeeded \(count=|Successful NR frames:\s*)(\d+)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )) {
        $count = [Int64]$match.Groups[1].Value
        if ($count -gt $successfulFrames) { $successfulFrames = $count }
    }

    $lines = @([regex]::Split($Text, '\r?\n'))
    $failureLines = New-Object System.Collections.Generic.List[string]
    $recoveredNativeFallbackLines = New-Object System.Collections.Generic.List[string]
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line -match '(?i)(nvngx_dlssnr\.dll was not found|nvngx_dlssnr\.dll was loaded but never initialized|signed feature (?:is missing|has no)|not a usable signed NGX runtime|not a valid signed NGX runtime|NGX/Streamline runtime has no complete|direct Init_Ext failed|DLSS-NR AllocateParameters failed|feature 18 create (?:failed|raised)|feature 18 evaluate (?:failed|raised)|NR is unavailable in this session|NR skipped:)') {
            $trimmed = $line.Trim()

            # RenoDX 4.60 can probe direct low-resolution NR upscaling when the
            # game changes its DLSS contract. NVIDIA's signed 310.8 runtime
            # rejects EVE's color contract with 0xbad00005, after which the
            # add-on deliberately retains the game's DLSS output and rebuilds
            # a full-resolution neural post-pass. Treat that one sequence as a
            # recovered warning only when every recovery marker appears later
            # and in order. All other create/evaluate failures remain fatal.
            $recoveredNativeFallback = $false
            if ($line -match '(?i)feature 18 evaluate failed with 0xbad00005;.*game DLSS output was retained.*NR upscaling is blocked for this title and following frames use the native path') {
                $fallbackMarkerIndex = -1
                $fallbackSearchEnd = [Math]::Min($lines.Count - 1, $lineIndex + 12)
                for ($candidateIndex = $lineIndex + 1; $candidateIndex -le $fallbackSearchEnd; $candidateIndex++) {
                    if ($lines[$candidateIndex] -match '(?i)NR upscaling fell back to native:.*NR continues on the native path') {
                        $fallbackMarkerIndex = $candidateIndex
                        break
                    }
                }

                if ($fallbackMarkerIndex -ge 0) {
                    $nativeResourceIndex = -1
                    $nativeResourceWidth = ""
                    $nativeResourceHeight = ""
                    $resourceSearchEnd = [Math]::Min($lines.Count - 1, $fallbackMarkerIndex + 12)
                    for ($candidateIndex = $fallbackMarkerIndex + 1; $candidateIndex -le $resourceSearchEnd; $candidateIndex++) {
                        $nativeResource = [regex]::Match(
                            $lines[$candidateIndex],
                            'created inline NR resources (?<inputWidth>\d+)x(?<inputHeight>\d+) -> (?<outputWidth>\d+)x(?<outputHeight>\d+) \(native\)',
                            [Text.RegularExpressions.RegexOptions]::IgnoreCase
                        )
                        if ($nativeResource.Success -and
                            $nativeResource.Groups['inputWidth'].Value -eq $nativeResource.Groups['outputWidth'].Value -and
                            $nativeResource.Groups['inputHeight'].Value -eq $nativeResource.Groups['outputHeight'].Value) {
                            $nativeResourceIndex = $candidateIndex
                            $nativeResourceWidth = $nativeResource.Groups['inputWidth'].Value
                            $nativeResourceHeight = $nativeResource.Groups['inputHeight'].Value
                            break
                        }
                    }

                    $featureSearchEnd = [Math]::Min($lines.Count - 1, $nativeResourceIndex + 12)
                    for ($candidateIndex = $nativeResourceIndex + 1; $nativeResourceIndex -ge 0 -and $candidateIndex -le $featureSearchEnd; $candidateIndex++) {
                        $nativeFeature = [regex]::Match(
                            $lines[$candidateIndex],
                            'feature 18 created .* NR input (?<inputWidth>\d+)x(?<inputHeight>\d+) -> output (?<outputWidth>\d+)x(?<outputHeight>\d+) with guides (?<guideWidth>\d+)x(?<guideHeight>\d+)',
                            [Text.RegularExpressions.RegexOptions]::IgnoreCase
                        )
                        if ($nativeFeature.Success) {
                            $inputSize = "$($nativeFeature.Groups['inputWidth'].Value)x$($nativeFeature.Groups['inputHeight'].Value)"
                            $outputSize = "$($nativeFeature.Groups['outputWidth'].Value)x$($nativeFeature.Groups['outputHeight'].Value)"
                            $guideSize = "$($nativeFeature.Groups['guideWidth'].Value)x$($nativeFeature.Groups['guideHeight'].Value)"
                            $resourceSize = "${nativeResourceWidth}x${nativeResourceHeight}"
                            if ($inputSize -eq $outputSize -and $inputSize -eq $guideSize -and $inputSize -eq $resourceSize) {
                                $recoveredNativeFallback = $true
                                break
                            }
                        }
                    }
                }
            }

            if ($trimmed -and $recoveredNativeFallback) {
                if (-not $recoveredNativeFallbackLines.Contains($trimmed)) {
                    $recoveredNativeFallbackLines.Add($trimmed)
                }
            } elseif ($trimmed -and -not $failureLines.Contains($trimmed)) {
                $failureLines.Add($trimmed)
            }
        }
    }

    return [pscustomobject][ordered]@{
        registrationCount = $registrationCount
        hookArmed = [regex]::IsMatch(
            $Text,
            'D3D12 NGX hooks installed(?:; inline DLSS contract capture armed| across\s+\d+)',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        runtimeInitialized = $Text.IndexOf('signed DLSSNR 310.8.0 D3D12 runtime initialized', [StringComparison]::OrdinalIgnoreCase) -ge 0
        successfulFrames = $successfulFrames
        recoveredNativeFallbackCount = $recoveredNativeFallbackLines.Count
        recoveredNativeFallbackLines = $recoveredNativeFallbackLines.ToArray()
        failureLines = $failureLines.ToArray()
    }
}

function Test-FileAbsentFromBaseline {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $baselinePath = Assert-ClientScopedStatePath -Path $script:BaselinePath
    if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw "Client baseline is missing: $baselinePath"
    }
    $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    Assert-BaselineTargets -Baseline $baseline
    foreach ($file in @($baseline.files)) {
        if (([string]$file.path).Equals($RelativePath, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Assert-BaselineTargets {
    param([Parameter(Mandatory = $true)]$Baseline)

    if (-not ($Baseline.PSObject.Properties.Name -contains "schemaVersion") -or
        [int]$Baseline.schemaVersion -ne 5 -or
        -not ($Baseline.PSObject.Properties.Name -contains "stateScope") -or
        -not ([string]$Baseline.stateScope).Equals("client", [StringComparison]::Ordinal)) {
        throw "The client-scoped baseline must use schemaVersion 5 and stateScope client."
    }

    if (-not ($Baseline.PSObject.Properties.Name -contains "clientRoot") -or
        -not $Baseline.clientRoot) {
        throw "The client baseline does not record its EVE client root."
    }
    $recordedClient = Get-NormalizedPath ([string]$Baseline.clientRoot)
    if (-not $recordedClient.Equals($script:ClientRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected EVE client does not match this baseline. Recorded '$recordedClient'; selected '$script:ClientRoot'."
    }

    $recordedWorkspace = $null
    if ($Baseline.PSObject.Properties.Name -contains "workspaceRoot") {
        if (-not $Baseline.workspaceRoot) {
            throw "The client baseline contains an empty EveJS workspace root."
        }
        $recordedWorkspace = Get-NormalizedPath ([string]$Baseline.workspaceRoot)
        if (-not $recordedWorkspace.Equals($script:WorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected EveJS workspace does not match this baseline. Recorded '$recordedWorkspace'; selected '$script:WorkspaceRoot'."
        }
    }

    if ($Baseline.PSObject.Properties.Name -contains "evejsRoot") {
        if (-not $Baseline.evejsRoot) {
            throw "The client baseline contains an empty EveJS root."
        }
        $recordedEveJSRoot = Get-NormalizedPath ([string]$Baseline.evejsRoot)
        if (-not $recordedEveJSRoot.Equals($script:EveJSRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected EveJS root does not match this baseline. Recorded '$recordedEveJSRoot'; selected '$script:EveJSRoot'."
        }
    } elseif ($null -ne $recordedWorkspace) {
        $legacyEveJSRoot = Get-NormalizedPath (Join-Path $recordedWorkspace "v0.12.6")
        if (-not $legacyEveJSRoot.Equals($script:EveJSRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected EveJS root does not match this legacy baseline. Recorded '$legacyEveJSRoot'; selected '$script:EveJSRoot'."
        }
    }

    if ($Baseline.PSObject.Properties.Name -contains "stateRoot" -and $Baseline.stateRoot) {
        $recordedStateRoot = Get-NormalizedPath ([string]$Baseline.stateRoot)
        if (-not $recordedStateRoot.Equals($script:StateRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected state root does not match this baseline. Recorded '$recordedStateRoot'; selected '$script:StateRoot'."
        }
    }
}

function Assert-NoTargetClientProcess {
    $processes = @(Get-Process -Name "exefile" -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
        $processIds = @($processes | ForEach-Object { [string]$_.Id }) -join ", "
        throw "An EVE client process is running (exefile.exe PID $processIds). Close every EVE client before changing shared DLLs or configuration."
    }
}

function Get-IsolatedClientProcesses {
    $targetExe = Get-PhysicalPath $script:ExePath
    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($process in @(Get-Process -Name "exefile" -ErrorAction SilentlyContinue)) {
        $processPath = $null
        try { $processPath = $process.Path } catch { }
        if ($processPath -and (Get-PhysicalPath $processPath).Equals($targetExe, [StringComparison]::OrdinalIgnoreCase)) {
            $matches.Add($process)
        }
    }
    return $matches.ToArray()
}

function Select-RuntimeTargetProcess {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Processes,
        [ValidateRange(0, [int]::MaxValue)][int]$RequestedProcessId = 0
    )

    $candidates = @($Processes)
    if ($RequestedProcessId -gt 0) {
        $selected = @($candidates | Where-Object { [int]$_.Id -eq $RequestedProcessId })
        if ($selected.Count -eq 0) {
            $available = if ($candidates.Count -gt 0) {
                (@($candidates | ForEach-Object { [string]$_.Id }) -join ", ")
            } else {
                "none"
            }
            throw "PID $RequestedProcessId is not an isolated EVE client from this copied bin64 folder. Available isolated PID(s): $available."
        }
        return $selected[0]
    }

    if ($candidates.Count -eq 0) {
        throw "The isolated EVE client is not running. Launch it through this EveJS copy, then run Runtime again."
    }
    if ($candidates.Count -gt 1) {
        $available = @($candidates | ForEach-Object { [string]$_.Id }) -join ", "
        throw "Multiple isolated EVE clients are running (PIDs: $available). Run Runtime with -ProcessId <PID> so each client is verified explicitly."
    }
    return $candidates[0]
}

function Read-PayloadManifest {
    if (-not (Test-Path -LiteralPath $script:PayloadManifestPath -PathType Leaf)) {
        throw "Payload manifest not found: $script:PayloadManifestPath"
    }
    $item = Get-Item -LiteralPath $script:PayloadManifestPath
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The payload manifest is a reparse point.'
    }
    if ([Int64]$item.Length -lt 1 -or [Int64]$item.Length -gt 65536) {
        throw 'The payload manifest size is outside the supported limit.'
    }
    $actualHash = Get-Sha256 $script:PayloadManifestPath
    if (-not $actualHash.Equals($script:ExpectedPayloadManifestSha256, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The payload manifest is not the exact reviewed manifest for this manager. Expected $script:ExpectedPayloadManifestSha256, got $actualHash"
    }
    $manifest = [IO.File]::ReadAllText($script:PayloadManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $manifest = Assert-PublicPayloadManifestContract -Manifest $manifest
    Assert-PublicGeneratorAssets -Manifest $manifest
    return $manifest
}

function Assert-ManifestTargets {
    param([Parameter(Mandatory = $true)]$Manifest)

    if (-not ($Manifest.PSObject.Properties.Name -contains "schemaVersion") -or
        [int]$Manifest.schemaVersion -ne 5 -or
        -not ($Manifest.PSObject.Properties.Name -contains "stateScope") -or
        -not ([string]$Manifest.stateScope).Equals("client", [StringComparison]::Ordinal)) {
        throw "The client-scoped install journal must use schemaVersion 5 and stateScope client. Legacy root-local journals are not adopted."
    }

    if (-not ($Manifest.PSObject.Properties.Name -contains "workspaceRoot") -or
        -not $Manifest.workspaceRoot) {
        throw "The install journal does not record its EveJS workspace root. Refusing an ambiguous target."
    }
    if (-not ($Manifest.PSObject.Properties.Name -contains "clientRoot") -or
        -not $Manifest.clientRoot) {
        throw "The install journal does not record its EVE client root. Refusing an ambiguous target."
    }

    $recordedWorkspace = Get-NormalizedPath ([string]$Manifest.workspaceRoot)
    $hasRecordedEveJSRoot = ($Manifest.PSObject.Properties.Name -contains "evejsRoot")
    if ($hasRecordedEveJSRoot) {
        if (-not $Manifest.evejsRoot) {
            throw "The install journal contains an empty EveJS root. Refusing an ambiguous target."
        }
        $recordedEveJSRoot = Get-NormalizedPath ([string]$Manifest.evejsRoot)
    } else {
        # Schema-3 journals predate the explicit EveJS root. Their only valid
        # interpretation is the historical <workspace>\v0.12.6 layout.
        $recordedEveJSRoot = Get-NormalizedPath (Join-Path $recordedWorkspace "v0.12.6")
    }
    $recordedClientValue = [string]$Manifest.clientRoot
    $recordedClient = if ([IO.Path]::IsPathRooted($recordedClientValue)) {
        Get-NormalizedPath $recordedClientValue
    } else {
        Get-NormalizedPath (Join-Path $recordedWorkspace $recordedClientValue)
    }

    if (-not $recordedWorkspace.Equals($script:WorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected EveJS workspace does not match this journal. Recorded '$recordedWorkspace'; selected '$script:WorkspaceRoot'."
    }
    if (-not $recordedEveJSRoot.Equals($script:EveJSRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected EveJS root does not match this journal. Recorded '$recordedEveJSRoot'; selected '$script:EveJSRoot'."
    }
    if (-not $recordedClient.Equals($script:ClientRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected EVE client does not match this journal. Recorded '$recordedClient'; selected '$script:ClientRoot'."
    }

    if ($Manifest.PSObject.Properties.Name -contains "stateDirectory" -and $Manifest.stateDirectory -and
        -not ([string]$Manifest.stateDirectory).Equals($script:StateDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected state directory does not match this journal. Recorded '$($Manifest.stateDirectory)'; selected '$script:StateDirectory'."
    }

    $hasRecordedStateRoot = (($Manifest.PSObject.Properties.Name -contains "stateRoot") -and [bool]$Manifest.stateRoot)
    if ($hasRecordedStateRoot) {
        $recordedStateRoot = Get-NormalizedPath ([string]$Manifest.stateRoot)
        if (-not $recordedStateRoot.Equals($script:StateRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected state root does not match this journal. Recorded '$recordedStateRoot'; selected '$script:StateRoot'."
        }
    }

    if (-not ($Manifest.PSObject.Properties.Name -contains "backupDirectory") -or
        -not $Manifest.backupDirectory) {
        throw "The install journal does not record its backup directory."
    }
    if ([IO.Path]::IsPathRooted([string]$Manifest.backupDirectory)) {
        throw "The install journal contains an absolute backup directory. Refusing an ambiguous target."
    }
    $recordedBackupRoot = if ($hasRecordedStateRoot) {
        Join-Path $script:StateRoot ([string]$Manifest.backupDirectory)
    } else {
        Join-Path $script:IntegrationRoot ([string]$Manifest.backupDirectory)
    }
    $recordedBackupRoot = Assert-ClientScopedStatePath -Path $recordedBackupRoot

    foreach ($operation in @($Manifest.operations)) {
        $source = Assert-ClientScopedStatePath -Path (Join-Path $script:PayloadRoot ([string]$operation.source))
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        Assert-PathInsideRoot -Path $source -Root $script:PayloadRoot -BoundaryName "payload" | Out-Null
        if ($operation.backup) {
            $backup = Assert-ClientScopedStatePath -Path (Join-Path $recordedBackupRoot ([string]$operation.backup))
            Assert-PathInsideRoot -Path $backup -Root $recordedBackupRoot -BoundaryName "backup" | Out-Null
        }
    }

    if ($Manifest.config -and $Manifest.config.backup) {
        $configBackup = Assert-ClientScopedStatePath -Path (Join-Path $recordedBackupRoot ([string]$Manifest.config.backup))
        Assert-PathInsideRoot -Path $configBackup -Root $recordedBackupRoot -BoundaryName "backup" | Out-Null
    }
    if ($Manifest.config -and
        ($Manifest.config.PSObject.Properties.Name -contains "path") -and
        $Manifest.config.path) {
        $recordedConfig = Get-NormalizedPath ([string]$Manifest.config.path)
        if (-not $recordedConfig.Equals($script:ConfigPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected EveJS config does not match this journal. Recorded '$recordedConfig'; selected '$script:ConfigPath'."
        }
    }
}

function Read-ActiveManifestRaw {
    $activeManifestPath = Assert-ClientScopedStatePath -Path $script:ActiveManifestPath
    if (-not (Test-Path -LiteralPath $activeManifestPath -PathType Leaf)) {
        return $null
    }
    $item = Get-Item -LiteralPath $activeManifestPath -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "The client-scoped install journal is a reparse point."
    }
    if ([Int64]$item.Length -lt 2 -or [Int64]$item.Length -gt 1048576) {
        throw "The client-scoped install journal size is outside the supported limit."
    }
    return ([IO.File]::ReadAllText($activeManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Read-ActiveManifest {
    $manifest = Read-ActiveManifestRaw
    if ($null -eq $manifest) { return $null }
    Assert-ManifestTargets -Manifest $manifest
    return $manifest
}

function Get-ManifestProfile {
    param([Parameter(Mandatory = $true)]$Manifest)
    if ($Manifest.PSObject.Properties.Name -contains "profile" -and $Manifest.profile) {
        return [string]$Manifest.profile
    }
    return "DLSS5"
}

function Get-OperationComponent {
    param(
        [Parameter(Mandatory = $true)]$Operation,
        [Parameter(Mandatory = $true)]$PayloadManifest
    )
    if ($Operation.PSObject.Properties.Name -contains "component" -and $Operation.component) {
        return [string]$Operation.component
    }
    $payloadFile = @($PayloadManifest.files | Where-Object {
        ([string]$_.destination).Equals([string]$Operation.destination, [StringComparison]::OrdinalIgnoreCase)
    }) | Select-Object -First 1
    if ($null -eq $payloadFile -or -not $payloadFile.component) {
        throw "No component classification exists for $($Operation.destination)"
    }
    return [string]$payloadFile.component
}

function Assert-ManifestPayloadCoverage {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$PayloadManifest
    )

    foreach ($file in @($PayloadManifest.files)) {
        $matches = @($Manifest.operations | Where-Object {
            ([string]$_.destination).Equals([string]$file.destination, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($matches.Count -ne 1) {
            throw "Install journal coverage mismatch for $($file.destination): expected one operation, found $($matches.Count)."
        }
    }
    foreach ($operation in @($Manifest.operations)) {
        $matches = @($PayloadManifest.files | Where-Object {
            ([string]$_.destination).Equals([string]$operation.destination, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($matches.Count -ne 1) {
            throw "Install journal contains an unknown or duplicate payload target: $($operation.destination)"
        }
    }
}

function Test-ManifestMatchesPayloadMetadata {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$PayloadManifest
    )

    Assert-ManifestPayloadCoverage -Manifest $Manifest -PayloadManifest $PayloadManifest
    if (-not ($Manifest.PSObject.Properties.Name -contains "integrationVersion") -or
        -not ([string]$Manifest.integrationVersion).Equals([string]$PayloadManifest.integrationVersion, [StringComparison]::Ordinal)) {
        return $false
    }

    foreach ($file in @($PayloadManifest.files)) {
        $operation = @($Manifest.operations | Where-Object {
            ([string]$_.destination).Equals([string]$file.destination, [StringComparison]::OrdinalIgnoreCase)
        })[0]
        $operationProperties = @($operation.PSObject.Properties.Name)
        foreach ($requiredProperty in @("source", "component", "installedSha256", "installedBytes")) {
            if ($operationProperties -notcontains $requiredProperty) {
                return $false
            }
        }
        if (-not ([string]$operation.source).Equals([string]$file.source, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([string]$operation.component).Equals([string]$file.component, [StringComparison]::Ordinal) -or
            -not ([string]$operation.installedSha256).Equals([string]$file.sha256, [StringComparison]::OrdinalIgnoreCase) -or
            [Int64]$operation.installedBytes -ne [Int64]$file.bytes) {
            return $false
        }

        if ($file.PSObject.Properties.Name -contains "requiredOriginalSha256" -and $file.requiredOriginalSha256) {
            if (-not ($operation.PSObject.Properties.Name -contains "requiredOriginalSha256") -or
                -not ([string]$operation.requiredOriginalSha256).Equals([string]$file.requiredOriginalSha256, [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
        if ($file.PSObject.Properties.Name -contains "requiredOriginalBytes") {
            if (-not ($operation.PSObject.Properties.Name -contains "requiredOriginalBytes") -or
                [Int64]$operation.requiredOriginalBytes -ne [Int64]$file.requiredOriginalBytes) {
                return $false
            }
        }
    }
    return $true
}

function Test-ComponentEnabled {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileName,
        [Parameter(Mandatory = $true)][string]$Component
    )
    if (-not $script:ProfileComponents.ContainsKey($ProfileName)) {
        throw "Unknown integration profile: $ProfileName"
    }
    return @($script:ProfileComponents[$ProfileName]) -contains $Component
}

function Add-OrSetProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-IniValueState {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $insideSection = $false
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $insideSection = $matches[1].Equals($Section, [StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if (-not $insideSection -or $trimmed.Length -eq 0 -or
            $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
            continue
        }
        $equals = $trimmed.IndexOf('=')
        if ($equals -lt 0) { continue }
        $candidate = $trimmed.Substring(0, $equals).Trim()
        if ($candidate.Equals($Key, [StringComparison]::OrdinalIgnoreCase)) {
            $values.Add($trimmed.Substring($equals + 1).Trim())
        }
    }

    return [pscustomobject][ordered]@{
        present = $values.Count -gt 0
        count = $values.Count
        value = if ($values.Count -gt 0) { $values[$values.Count - 1] } else { $null }
    }
}

function Set-IniValueText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) { $lines.Add($line) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -eq 0) {
        $lines.RemoveAt($lines.Count - 1)
    }

    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[([^\]]+)\]$') {
            if ($sectionStart -ge 0) {
                $sectionEnd = $i
                break
            }
            if ($matches[1].Equals($Section, [StringComparison]::OrdinalIgnoreCase)) {
                $sectionStart = $i
            }
        }
    }

    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -gt 0) { $lines.Add("") }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    } else {
        $matchesAt = New-Object System.Collections.Generic.List[int]
        for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
            $trimmed = $lines[$i].Trim()
            if ($trimmed.Length -eq 0 -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) { continue }
            $equals = $trimmed.IndexOf('=')
            if ($equals -lt 0) { continue }
            if ($trimmed.Substring(0, $equals).Trim().Equals($Key, [StringComparison]::OrdinalIgnoreCase)) {
                $matchesAt.Add($i)
            }
        }
        if ($matchesAt.Count -eq 0) {
            $lines.Insert($sectionEnd, "$Key=$Value")
        } else {
            $lines[$matchesAt[0]] = "$Key=$Value"
            for ($i = $matchesAt.Count - 1; $i -ge 1; $i--) {
                $lines.RemoveAt($matchesAt[$i])
            }
        }
    }

    return (($lines -join "`r`n").TrimEnd([char[]]@("`r", "`n")) + "`r`n")
}

function Remove-IniValueText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) { $lines.Add($line) }
    $insideSection = $false
    $matchesAt = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $insideSection = $matches[1].Equals($Section, [StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if (-not $insideSection -or $trimmed.Length -eq 0 -or
            $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
            continue
        }
        $equals = $trimmed.IndexOf('=')
        if ($equals -ge 0 -and
            $trimmed.Substring(0, $equals).Trim().Equals($Key, [StringComparison]::OrdinalIgnoreCase)) {
            $matchesAt.Add($i)
        }
    }
    for ($i = $matchesAt.Count - 1; $i -ge 0; $i--) {
        $lines.RemoveAt($matchesAt[$i])
    }
    return (($lines -join "`r`n").TrimEnd([char[]]@("`r", "`n")) + "`r`n")
}

function Remove-IniSectionText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section
    )

    $result = New-Object System.Collections.Generic.List[string]
    $insideTarget = $false
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) {
        $header = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
        if ($header.Success) {
            $insideTarget = $header.Groups[1].Value.Equals($Section, [StringComparison]::OrdinalIgnoreCase)
            if ($insideTarget) { continue }
        }
        if (-not $insideTarget) { $result.Add($line) }
    }
    return (($result -join "`r`n").TrimEnd([char[]]@("`r", "`n")) + "`r`n")
}

function Get-IniSectionText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section
    )

    $result = New-Object System.Collections.Generic.List[string]
    $insideTarget = $false
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) {
        $header = [regex]::Match($line, '^\s*\[([^\]]+)\]\s*$')
        if ($header.Success) {
            $isTarget = $header.Groups[1].Value.Equals($Section, [StringComparison]::OrdinalIgnoreCase)
            if ($isTarget) {
                if ($result.Count -gt 0 -and $result[$result.Count - 1].Length -gt 0) { $result.Add("") }
                $insideTarget = $true
                $result.Add($line)
                continue
            }
            $insideTarget = $false
        }
        if ($insideTarget) { $result.Add($line) }
    }
    return (($result -join "`r`n").TrimEnd([char[]]@("`r", "`n")))
}

function Restore-IniSectionText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$CurrentText,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$OriginalText,
        [Parameter(Mandatory = $true)][string]$Section
    )

    $withoutCurrent = Remove-IniSectionText -Text $CurrentText -Section $Section
    $originalSection = Get-IniSectionText -Text $OriginalText -Section $Section
    if ([string]::IsNullOrWhiteSpace($originalSection)) { return $withoutCurrent }
    return ($withoutCurrent.TrimEnd([char[]]@("`r", "`n")) + "`r`n`r`n" + $originalSection + "`r`n")
}

function Test-IniHasMeaningfulValues {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    foreach ($line in @([regex]::Split($Text, '\r?\n'))) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith(";") -or
            $trimmed.StartsWith("#") -or $trimmed -match '^\[[^\]]+\]$') {
            continue
        }
        return $true
    }
    return $false
}

function Initialize-ReShadeConfigTracking {
    param([Parameter(Mandatory = $true)]$Manifest)
    if ($Manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $Manifest.reshadeConfig) {
        # The set of integration-owned keys can grow between payload versions.
        # Capture any newly owned key from the file as it exists *before* we
        # write our value, so uninstall still restores a user's prior value.
        $exists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
        $currentText = if ($exists) { [IO.File]::ReadAllText($script:ReShadeConfigPath) } else { "" }
        $managed = @($Manifest.reshadeConfig.managedKeys)
        $changed = $false
        foreach ($key in $script:ManagedReShadeKeys) {
            $matches = @($managed | Where-Object {
                ([string]$_.section).Equals([string]$key.section, [StringComparison]::OrdinalIgnoreCase) -and
                ([string]$_.key).Equals([string]$key.key, [StringComparison]::OrdinalIgnoreCase)
            })
            if ($matches.Count -gt 1) {
                throw "Duplicate ReShade.ini ownership record: [$($key.section)] $($key.key)"
            }
            if ($matches.Count -eq 0) {
                $state = Get-IniValueState -Text $currentText -Section $key.section -Key $key.key
                $managed += [pscustomobject][ordered]@{
                    section = [string]$key.section
                    key = [string]$key.key
                    installedValue = [string]$key.value
                    originalPresent = [bool]$state.present
                    originalValue = if ($state.present) { [string]$state.value } else { $null }
                }
                $changed = $true
            } elseif (-not ([string]$matches[0].installedValue).Equals([string]$key.value, [StringComparison]::Ordinal)) {
                Add-OrSetProperty -Object $matches[0] -Name "installedValue" -Value ([string]$key.value)
                $changed = $true
            }
        }
        if ($changed) {
            Add-OrSetProperty -Object $Manifest.reshadeConfig -Name "schemaVersion" -Value 2
            Add-OrSetProperty -Object $Manifest.reshadeConfig -Name "managedKeys" -Value $managed
            Write-JsonAtomic -Value $Manifest -Path $script:ActiveManifestPath
            Write-Okay "extended ReShade.ini ownership boundary for the current payload"
        }
        return
    }

    Assert-PathInsideRoot -Path $script:ReShadeConfigPath -Root $script:ClientRoot -BoundaryName "client" | Out-Null
    $exists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
    $originalText = if ($exists) { [IO.File]::ReadAllText($script:ReShadeConfigPath) } else { "" }
    $backupRelative = if ($exists) { "support\ReShade.ini" } else { $null }
    if ($exists) {
        $backup = Assert-ClientScopedStatePath -Path (Join-Path (Get-BackupRoot $Manifest) $backupRelative)
        $backupParent = Assert-ClientScopedStatePath -Path (Split-Path -Parent $backup)
        New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
        $originalReShadeHash = Get-Sha256 $script:ReShadeConfigPath
        Copy-FileAtomic -Source $script:ReShadeConfigPath -Destination $backup -ExpectedSha256 $originalReShadeHash
        if ((Get-Sha256 $backup) -ne $originalReShadeHash) {
            throw "Backup verification failed for pre-existing ReShade.ini"
        }
    }

    $managed = New-Object System.Collections.Generic.List[object]
    foreach ($key in $script:ManagedReShadeKeys) {
        $state = Get-IniValueState -Text $originalText -Section $key.section -Key $key.key
        $managed.Add([pscustomobject][ordered]@{
            section = [string]$key.section
            key = [string]$key.key
            installedValue = [string]$key.value
            originalPresent = [bool]$state.present
            originalValue = if ($state.present) { [string]$state.value } else { $null }
        })
    }

    Add-OrSetProperty -Object $Manifest -Name "reshadeConfig" -Value ([pscustomobject][ordered]@{
        schemaVersion = 2
        path = "bin64\ReShade.ini"
        capturedAtUtc = [DateTime]::UtcNow.ToString("o")
        originalExists = $exists
        originalSha256 = if ($exists) { Get-Sha256 $script:ReShadeConfigPath } else { $null }
        backup = $backupRelative
        managedKeys = $managed.ToArray()
        lastAppliedProfile = $null
        lastAppliedSha256 = $null
        preservedOnRestore = $null
        restoredAtUtc = $null
    })
    Write-JsonAtomic -Value $Manifest -Path $script:ActiveManifestPath
    Write-Okay "captured ReShade.ini ownership boundary"
}

function Set-ReShadeConfigForProfile {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ProfileName
    )

    $usesReShade = Test-ComponentEnabled -ProfileName $ProfileName -Component "reshade"
    $tracked = $Manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $Manifest.reshadeConfig
    if (-not $usesReShade -and -not $tracked) { return }
    if (-not $tracked) { Initialize-ReShadeConfigTracking -Manifest $Manifest }

    $enableRenoDx = Test-ComponentEnabled -ProfileName $ProfileName -Component "renodx"
    $exists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
    if ($exists) {
        $text = [IO.File]::ReadAllText($script:ReShadeConfigPath)
    } elseif ([bool]$Manifest.reshadeConfig.originalExists) {
        $backup = Assert-ClientScopedStatePath -Path (Join-Path (Get-BackupRoot $Manifest) ([string]$Manifest.reshadeConfig.backup))
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-Sha256 $backup) -ne [string]$Manifest.reshadeConfig.originalSha256) {
            throw "Original ReShade.ini backup is missing or invalid: $backup"
        }
        $text = [IO.File]::ReadAllText($backup)
    } else {
        $text = ""
    }

    foreach ($managed in @($Manifest.reshadeConfig.managedKeys)) {
        if ($enableRenoDx) {
            $text = Set-IniValueText -Text $text -Section ([string]$managed.section) -Key ([string]$managed.key) -Value ([string]$managed.installedValue)
        } elseif ([bool]$managed.originalPresent) {
            $text = Set-IniValueText -Text $text -Section ([string]$managed.section) -Key ([string]$managed.key) -Value ([string]$managed.originalValue)
        } else {
            $text = Remove-IniValueText -Text $text -Section ([string]$managed.section) -Key ([string]$managed.key)
        }
    }

    if (-not [bool]$Manifest.reshadeConfig.originalExists -and -not (Test-IniHasMeaningfulValues -Text $text)) {
        if (Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf) {
            Remove-Item -LiteralPath (Assert-PathInsideRoot -Path $script:ReShadeConfigPath -Root $script:ClientRoot -BoundaryName "client") -Force
        }
        $Manifest.reshadeConfig.lastAppliedSha256 = $null
    } else {
        Write-TextAtomic -Text $text -Path $script:ReShadeConfigPath
        $Manifest.reshadeConfig.lastAppliedSha256 = Get-Sha256 $script:ReShadeConfigPath
    }
    $Manifest.reshadeConfig.lastAppliedProfile = $ProfileName
    Write-JsonAtomic -Value $Manifest -Path $script:ActiveManifestPath

    if ($enableRenoDx) {
        Write-Okay "ReShade.ini enables early RenoDX loading and DLSS 5 Neural Rendering"
    } else {
        Write-Okay "DLSS5-owned ReShade.ini keys are disabled or restored"
    }
}

function Test-ReShadeConfigForProfile {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ProfileName
    )
    $enableRenoDx = Test-ComponentEnabled -ProfileName $ProfileName -Component "renodx"
    $tracked = $Manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $Manifest.reshadeConfig
    if ($enableRenoDx -and -not $tracked) {
        throw "The RenoDX profile has no ReShade.ini ownership record."
    }
    if (-not $tracked) { return }

    $exists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
    if (-not $enableRenoDx -and [bool]$Manifest.reshadeConfig.originalExists -and -not $exists) {
        throw "The pre-existing ReShade.ini is missing outside the RenoDX profile."
    }
    $text = if ($exists) { [IO.File]::ReadAllText($script:ReShadeConfigPath) } else { "" }
    foreach ($managed in @($Manifest.reshadeConfig.managedKeys)) {
        $expectedPresent = if ($enableRenoDx) { $true } else { [bool]$managed.originalPresent }
        $expectedValue = if ($enableRenoDx) { [string]$managed.installedValue } else { [string]$managed.originalValue }
        $state = Get-IniValueState -Text $text -Section ([string]$managed.section) -Key ([string]$managed.key)
        if ($state.count -gt 1) {
            throw "Duplicate ReShade.ini key: [$($managed.section)] $($managed.key)"
        }
        if ($expectedPresent) {
            $valueMatches = $state.present -and ([string]$state.value).Equals($expectedValue, [StringComparison]::Ordinal)
            if ($enableRenoDx -and
                ([string]$managed.section).Equals("RenoDX.DLSS5", [StringComparison]::OrdinalIgnoreCase) -and
                ([string]$managed.key).Equals("NeuralUplift", [StringComparison]::OrdinalIgnoreCase)) {
                # NeuralUplift is live per-user state. RenoDX and the F6 control
                # legitimately persist either 0 or 1 after installation. Keep
                # presence and domain validation without forcing the install
                # default back over the user's runtime choice.
                $valueMatches = $state.present -and ([string]$state.value -in @("0", "1"))
            }
            if (-not $valueMatches) {
                throw "ReShade.ini mismatch: [$($managed.section)] $($managed.key)"
            }
        } elseif ($state.present) {
            throw "A DLSS5-owned ReShade.ini key remains enabled outside a RenoDX profile: [$($managed.section)] $($managed.key)"
        }
    }
}

function Restore-ReShadeConfig {
    param([Parameter(Mandatory = $true)]$Manifest)
    if (-not ($Manifest.PSObject.Properties.Name -contains "reshadeConfig") -or $null -eq $Manifest.reshadeConfig) {
        return
    }

    $preserveRoot = $null
    $currentExists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
    $currentText = if ($currentExists) { [IO.File]::ReadAllText($script:ReShadeConfigPath) } else { "" }
    if ($currentExists) {
        $preserveRoot = Assert-ClientScopedStatePath -Path (Join-Path $script:StateRoot ("uninstall-preserved\" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")))
        New-Item -ItemType Directory -Path $preserveRoot -Force | Out-Null
        $preserved = Assert-ClientScopedStatePath -Path (Join-Path $preserveRoot "ReShade.ini")
        Copy-Item -LiteralPath $script:ReShadeConfigPath -Destination $preserved
        $Manifest.reshadeConfig.preservedOnRestore = $preserved.Substring($script:StateRoot.Length + 1)
        Add-OrSetProperty -Object $Manifest.reshadeConfig -Name "preservedPathsRelativeTo" -Value "stateRoot"
        Write-Okay "archived current ReShade.ini before removal"
    }

    $originalText = ""
    if ([bool]$Manifest.reshadeConfig.originalExists) {
        $backup = Assert-ClientScopedStatePath -Path (Join-Path (Get-BackupRoot $Manifest) ([string]$Manifest.reshadeConfig.backup))
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
            (Get-Sha256 $backup) -ne [string]$Manifest.reshadeConfig.originalSha256) {
            throw "Original ReShade.ini backup is missing or invalid: $backup"
        }
        $originalText = [IO.File]::ReadAllText($backup)

        if (-not $currentExists) {
            Copy-FileAtomic -Source $backup -Destination $script:ReShadeConfigPath -ExpectedSha256 ([string]$Manifest.reshadeConfig.originalSha256)
            Write-Okay "restored missing pre-existing ReShade.ini"
        }
    }

    if ($currentExists -and -not [bool]$Manifest.reshadeConfig.originalExists) {
        # ReShade and RenoDX may generate many settings after first use. When
        # no ReShade.ini existed before installation, exact rollback means the
        # active file must go. The live version was archived above first.
        Remove-Item -LiteralPath (Assert-PathInsideRoot -Path $script:ReShadeConfigPath -Root $script:ClientRoot -BoundaryName "client") -Force
        Write-Okay "removed generated ReShade.ini (archived before removal)"
    } elseif ($currentExists) {
        $restoredText = $currentText
        foreach ($managed in @($Manifest.reshadeConfig.managedKeys)) {
            if ([bool]$managed.originalPresent) {
                $restoredText = Set-IniValueText -Text $restoredText -Section ([string]$managed.section) -Key ([string]$managed.key) -Value ([string]$managed.originalValue)
            } else {
                $restoredText = Remove-IniValueText -Text $restoredText -Section ([string]$managed.section) -Key ([string]$managed.key)
            }
        }

        # Replace the whole RenoDX section with its pre-install version. This
        # removes settings generated dynamically by the add-on without
        # clobbering unrelated ReShade settings changed after installation.
        $restoredText = Restore-IniSectionText -CurrentText $restoredText -OriginalText $originalText -Section "RenoDX.DLSS5"
        Write-TextAtomic -Text $restoredText -Path $script:ReShadeConfigPath
        Write-Okay "restored the original RenoDX section and preserved unrelated ReShade settings"
    }

    $preservedGenerated = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in @("bin64\ReShade.log", "bin64\ReShadePreset.ini")) {
        $artifactPath = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot $relativePath)
        if ((Test-Path -LiteralPath $artifactPath -PathType Leaf) -and (Test-FileAbsentFromBaseline -RelativePath $relativePath)) {
            if ($null -eq $preserveRoot) {
                $preserveRoot = Assert-ClientScopedStatePath -Path (Join-Path $script:StateRoot ("uninstall-preserved\" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")))
                New-Item -ItemType Directory -Path $preserveRoot -Force | Out-Null
            }
            $preserved = Assert-ClientScopedStatePath -Path (Join-Path $preserveRoot ([IO.Path]::GetFileName($relativePath)))
            Copy-Item -LiteralPath $artifactPath -Destination $preserved
            Remove-Item -LiteralPath (Assert-PathInsideRoot -Path $artifactPath -Root $script:ClientRoot -BoundaryName "client") -Force
            $preservedGenerated.Add($preserved.Substring($script:StateRoot.Length + 1))
            Write-Okay "archived and removed generated $relativePath"
        }
    }
    Add-OrSetProperty -Object $Manifest.reshadeConfig -Name "generatedArtifactsPreservedOnRestore" -Value $preservedGenerated.ToArray()
    Add-OrSetProperty -Object $Manifest.reshadeConfig -Name "preservedPathsRelativeTo" -Value "stateRoot"
    $Manifest.reshadeConfig.restoredAtUtc = [DateTime]::UtcNow.ToString("o")
}

function Get-LiteralBatchSettingMatches {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $escapedName = [Regex]::Escape($Name)
    $pattern = '(?im)^\s*@?set\s+(?:"' + $escapedName + '=([^"\r\n]*)"|' + $escapedName + '=([^\r\n]*?))\s*$'
    return @([Regex]::Matches($Text, $pattern))
}

function Get-LiteralBatchSettingCandidateCount {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $pattern = '(?im)^\s*@?set\s+"?' + [Regex]::Escape($Name) + '='
    return [Regex]::Matches($Text, $pattern).Count
}

function Get-LiteralBatchSettingValue {
    param([Parameter(Mandatory = $true)]$Match)

    if ($Match.Groups[1].Success) {
        return [string]$Match.Groups[1].Value
    }
    return ([string]$Match.Groups[2].Value).TrimEnd()
}

function Assert-ExactBatchSettingValue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExpectedValue
    )

    $matches = @(Get-LiteralBatchSettingMatches -Text $Text -Name $Name)
    $candidateCount = Get-LiteralBatchSettingCandidateCount -Text $Text -Name $Name
    if ($matches.Count -ne 1 -or $candidateCount -ne 1) {
        throw "EvEJSConfig.bat must contain exactly one literal $Name assignment."
    }
    $actualValue = Get-LiteralBatchSettingValue -Match $matches[0]
    if (-not $actualValue.Equals($ExpectedValue, [StringComparison]::OrdinalIgnoreCase)) {
        throw "EvEJSConfig.bat $Name mismatch. Expected '$ExpectedValue', got '$actualValue'."
    }
}

function Assert-EveJSRootContract {
    param([Parameter(Mandatory = $true)][string]$Root)

    $normalizedRoot = Get-NormalizedPath $Root
    if (-not (Test-Path -LiteralPath $normalizedRoot -PathType Container)) {
        throw "Required EveJS root is missing: $normalizedRoot"
    }
    Assert-NoReparsePointsInExistingPath -Path $normalizedRoot -BoundaryName "EveJS root" | Out-Null
    $rootItem = Get-Item -LiteralPath $normalizedRoot -Force
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "The EveJS root is a reparse point: $normalizedRoot"
    }

    $packagePath = Join-Path $normalizedRoot "package.json"
    Assert-NoReparsePointsInExistingPath -Path $packagePath -BoundaryName "EveJS package metadata" | Out-Null
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "Required EveJS package metadata is missing: $packagePath"
    }
    $package = [IO.File]::ReadAllText($packagePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $packageProperties = @($package.PSObject.Properties.Name)
    $version = if ($packageProperties -contains "version") { ([string]$package.version).Trim() } else { "" }
    if ($packageProperties -notcontains "name" -or
        -not ([string]$package.name).Equals("eve.js", [StringComparison]::Ordinal) -or
        [string]::IsNullOrWhiteSpace($version) -or
        $version.Length -gt 64 -or
        $version -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]*$' -or
        $version.Contains("..")) {
        throw "The selected EveJS root must contain package name eve.js and a non-empty, sane version string."
    }

    $configPath = Join-Path $normalizedRoot "tools\ClientSETUP\scripts\EvEJSConfig.bat"
    Assert-NoReparsePointsInExistingPath -Path $configPath -BoundaryName "EveJS configuration" | Out-Null
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Required EveJS client configuration is missing: $configPath"
    }
    $configText = [IO.File]::ReadAllText($configPath)
    foreach ($requiredSetting in @("EVEJS_CLIENT_PATH", "EVEJS_CLIENT_EXE")) {
        $matches = @(Get-LiteralBatchSettingMatches -Text $configText -Name $requiredSetting)
        $candidateCount = Get-LiteralBatchSettingCandidateCount -Text $configText -Name $requiredSetting
        if ($matches.Count -ne 1 -or $candidateCount -ne 1) {
            throw "EvEJSConfig.bat must contain exactly one unambiguous literal $requiredSetting assignment."
        }
        $settingValue = Get-LiteralBatchSettingValue -Match $matches[0]
        if ($requiredSetting -eq "EVEJS_CLIENT_PATH" -and [string]::IsNullOrWhiteSpace($settingValue)) {
            throw "EvEJSConfig.bat EVEJS_CLIENT_PATH must not be empty."
        }
        if ($requiredSetting -eq "EVEJS_CLIENT_EXE" -and
            -not [string]::IsNullOrWhiteSpace($settingValue) -and
            -not $settingValue.Equals("bin64\exefile.exe", [StringComparison]::OrdinalIgnoreCase)) {
            throw "EvEJSConfig.bat EVEJS_CLIENT_EXE must be empty or bin64\exefile.exe."
        }
    }
    foreach ($managedSetting in @("TRINITYPLATFORM", "EVEJS_DLSS5")) {
        $matches = @(Get-LiteralBatchSettingMatches -Text $configText -Name $managedSetting)
        $candidateCount = Get-LiteralBatchSettingCandidateCount -Text $configText -Name $managedSetting
        if ($matches.Count -ne $candidateCount) {
            throw "EvEJSConfig.bat contains an ambiguous $managedSetting assignment that cannot be normalized safely."
        }
    }

    return [pscustomobject][ordered]@{
        root = $normalizedRoot
        version = $version
        configPath = $configPath
    }
}

function Assert-WorkspaceLayout {
    Assert-PathInsideAuthorizedRoots -Path $script:StateRoot | Out-Null
    Assert-PathInsideRoot -Path $script:EveJSRoot -Root $script:WorkspaceRoot -BoundaryName "EveJS workspace" | Out-Null
    Assert-PathInsideRoot -Path $script:ClientRoot -Root $script:ClientRoot -BoundaryName "client" | Out-Null
    Assert-PathInsideRoot -Path $script:ConfigPath -Root $script:EveJSRoot -BoundaryName "EveJS root" | Out-Null
    Assert-PathInsideRoot -Path $script:PayloadRoot -Root $script:StateRoot -BoundaryName "DLSS5 state" | Out-Null
    Assert-OwnedEveJSPath -Path $script:ConfigPath | Out-Null
    foreach ($ownedClientPath in @(
        $script:ClientRoot,
        $script:BinRoot,
        $script:ExePath,
        (Join-Path $script:ClientRoot "start.ini"),
        (Join-Path $script:BinRoot "blue.dll"),
        (Join-Path $script:BinRoot "_trinity_dx12.dll"),
        $script:ReShadeConfigPath,
        $script:ReShadeLogPath,
        (Join-Path $script:BinRoot "ReShadePreset.ini")
    )) {
        Assert-OwnedClientPath -Path $ownedClientPath | Out-Null
    }

    foreach ($required in @(
        $script:EveJSRoot,
        (Join-Path $script:EveJSRoot "package.json"),
        $script:ClientRoot,
        $script:BinRoot,
        $script:ExePath,
        (Join-Path $script:ClientRoot "start.ini"),
        (Join-Path $script:BinRoot "blue.dll"),
        (Join-Path $script:BinRoot "_trinity_dx12.dll"),
        $script:ConfigPath
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required EveJS/client path is missing: $required"
        }
    }

    $evejsItem = Get-Item -LiteralPath $script:EveJSRoot
    $clientItem = Get-Item -LiteralPath $script:ClientRoot
    $binItem = Get-Item -LiteralPath $script:BinRoot
    if (($evejsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($clientItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($binItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "The EveJS root, target client, or bin64 folder is a reparse point. Refusing an ambiguous write boundary."
    }

    $evejsContract = Assert-EveJSRootContract -Root $script:EveJSRoot
    if (-not (Get-NormalizedPath ([string]$evejsContract.configPath)).Equals((Get-NormalizedPath $script:ConfigPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw "The selected EveJS configuration path does not match the expected layout."
    }
    $physicalStateRoot = Get-NormalizedPath (Join-Path (Split-Path -Parent (Get-PhysicalPath $script:ClientRoot)) "_evejs\dlss5\install")
    if (-not (Get-NormalizedPath $script:StateRoot).Equals($physicalStateRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "DLSS5 mutable state must be client-scoped at '$physicalStateRoot'."
    }

    $startIni = Get-Content -LiteralPath (Join-Path $script:ClientRoot "start.ini") -Raw
    if ($startIni -notmatch '(?m)^build\s*=\s*3396210\s*$') {
        throw "The copied client is not the expected build 3396210."
    }
    if ($startIni -notmatch '(?m)^server\s*=\s*127\.0\.0\.1\s*$') {
        throw "The copied client is not configured for the local EveJS server."
    }

    $exeHash = Get-Sha256 $script:ExePath
    if ($exeHash -ne $script:ExpectedExeSha256) {
        throw "exefile.exe baseline mismatch. Expected $script:ExpectedExeSha256, got $exeHash"
    }
}

function Assert-Payload {
    $manifest = Read-PayloadManifest
    return (Initialize-PublicPayload -Manifest $manifest)
}

function Assert-RequiredOriginalTarget {
    param(
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not ($File.PSObject.Properties.Name -contains "requiredOriginalSha256") -or
        -not $File.requiredOriginalSha256) {
        return
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Required original file is missing: $($File.destination)"
    }

    $actualHash = Get-Sha256 $Destination
    $requiredHash = ([string]$File.requiredOriginalSha256).ToUpperInvariant()
    if (-not $actualHash.Equals($requiredHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported original file for $($File.destination). Expected $requiredHash, got $actualHash"
    }
    if ($File.PSObject.Properties.Name -contains "requiredOriginalBytes") {
        $actualBytes = [Int64](Get-Item -LiteralPath $Destination).Length
        if ($actualBytes -ne [Int64]$File.requiredOriginalBytes) {
            throw "Unsupported original file size for $($File.destination). Expected $($File.requiredOriginalBytes), got $actualBytes"
        }
    }
}

function New-ClientBaseline {
    Write-Step "Hashing the untouched tq client baseline"
    $files = @(Get-ChildItem -LiteralPath $script:ClientRoot -File -Recurse | Sort-Object FullName)
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($script:ClientRoot.Length + 1)
        $entries.Add([ordered]@{
            path = $relative
            bytes = [Int64]$file.Length
            sha256 = Get-Sha256 $file.FullName
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
        })
    }
    $baseline = [ordered]@{
        schemaVersion = 5
        stateScope = "client"
        createdAtUtc = [DateTime]::UtcNow.ToString("o")
        workspaceRoot = $script:WorkspaceRoot
        evejsRoot = $script:EveJSRoot
        clientRoot = $script:ClientRoot
        stateRoot = $script:StateRoot
        fileCount = $entries.Count
        files = $entries.ToArray()
    }
    Write-JsonAtomic -Value $baseline -Path $script:BaselinePath
    Write-Okay "$($entries.Count) client files recorded in $script:BaselinePath"
    return $baseline
}

function Get-UpdatedEveJSConfigText {
    $lines = [IO.File]::ReadAllLines($script:ConfigPath)
    $output = New-Object System.Collections.Generic.List[string]
    $foundClientPath = $false
    $foundClientExe = $false
    $insertedDlssBlock = $false

    foreach ($line in $lines) {
        if (@(Get-LiteralBatchSettingMatches -Text $line -Name "EVEJS_CLIENT_PATH").Count -eq 1) {
            $output.Add('set "EVEJS_CLIENT_PATH=' + $script:ClientRoot + '"')
            $foundClientPath = $true
            continue
        }
        if (@(Get-LiteralBatchSettingMatches -Text $line -Name "TRINITYPLATFORM").Count -eq 1 -or
            @(Get-LiteralBatchSettingMatches -Text $line -Name "EVEJS_DLSS5").Count -eq 1) {
            continue
        }
        if ($line -eq 'rem DLSS5 integration: force the DX12 Trinity renderer required by RenoDX.') {
            continue
        }

        $clientExeMatches = @(Get-LiteralBatchSettingMatches -Text $line -Name "EVEJS_CLIENT_EXE")
        if ($clientExeMatches.Count -eq 1) {
            $output.Add('set "EVEJS_CLIENT_EXE=bin64\exefile.exe"')
            $foundClientExe = $true
            $output.Add('')
            $output.Add('rem DLSS5 integration: force the DX12 Trinity renderer required by RenoDX.')
            $output.Add('set "TRINITYPLATFORM=dx12"')
            $output.Add('set "EVEJS_DLSS5=on"')
            $insertedDlssBlock = $true
            continue
        }

        $output.Add($line)
    }

    if (-not $foundClientPath) {
        throw "EVEJS_CLIENT_PATH was not found in $script:ConfigPath"
    }
    if (-not $foundClientExe -or -not $insertedDlssBlock) {
        throw "EVEJS_CLIENT_EXE was not found in $script:ConfigPath"
    }
    return (($output -join "`r`n").TrimEnd([char[]]@("`r", "`n")) + "`r`n")
}

function New-InstallManifest {
    param(
        [Parameter(Mandatory = $true)]$PayloadManifest,
        [Parameter(Mandatory = $true)][string]$BackupName,
        [Parameter(Mandatory = $true)][string]$ProfileName
    )
    $operations = New-Object System.Collections.Generic.List[object]
    foreach ($file in @($PayloadManifest.files)) {
        $source = Assert-ClientScopedStatePath -Path (Join-Path $script:PayloadRoot ([string]$file.source))
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$file.destination))
        Assert-PathInsideRoot -Path $source -Root $script:PayloadRoot -BoundaryName "materialized payload" | Out-Null
        $exists = Test-Path -LiteralPath $destination -PathType Leaf
        $kind = if ($exists) { "replace" } else { "add" }
        $originalHash = if ($exists) { Get-Sha256 $destination } else { $null }
        $originalBytes = if ($exists) { [Int64](Get-Item -LiteralPath $destination).Length } else { $null }
        Assert-RequiredOriginalTarget -File $file -Destination $destination
        $backup = if ($exists) { Join-Path "client" $file.destination } else { $null }
        $operations.Add([pscustomobject][ordered]@{
            source = [string]$file.source
            destination = [string]$file.destination
            component = [string]$file.component
            kind = $kind
            originalSha256 = $originalHash
            originalBytes = $originalBytes
            installedSha256 = [string]$file.sha256
            installedBytes = [Int64]$file.bytes
            requiredOriginalSha256 = if ($file.PSObject.Properties.Name -contains "requiredOriginalSha256") { [string]$file.requiredOriginalSha256 } else { $null }
            requiredOriginalBytes = if ($file.PSObject.Properties.Name -contains "requiredOriginalBytes") { [Int64]$file.requiredOriginalBytes } else { $null }
            backup = $backup
            applied = $false
        })
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 5
        stateScope = "client"
        integrationVersion = [string]$PayloadManifest.integrationVersion
        status = "prepared"
        profile = $ProfileName
        profileAppliedAtUtc = $null
        profileHistory = @()
        createdAtUtc = [DateTime]::UtcNow.ToString("o")
        installedAtUtc = $null
        restoredAtUtc = $null
        workspaceRoot = $script:WorkspaceRoot
        evejsRoot = $script:EveJSRoot
        clientRoot = $script:ClientRoot
        stateRoot = $script:StateRoot
        backupDirectory = Join-Path "backups" $BackupName
        executable = [ordered]@{
            path = "bin64\exefile.exe"
            sha256 = Get-Sha256 $script:ExePath
            modified = $false
        }
        config = [pscustomobject][ordered]@{
            path = $script:ConfigPath
            backup = "config\EvEJSConfig.bat"
            originalSha256 = Get-Sha256 $script:ConfigPath
            installedSha256 = $null
            applied = $false
        }
        operations = $operations.ToArray()
    }
}

function Get-BackupRoot {
    param([Parameter(Mandatory = $true)]$Manifest)
    $hasRecordedStateRoot = (($Manifest.PSObject.Properties.Name -contains "stateRoot") -and [bool]$Manifest.stateRoot)
    $path = if ($hasRecordedStateRoot) {
        Join-Path $script:StateRoot ([string]$Manifest.backupDirectory)
    } else {
        Join-Path $script:IntegrationRoot ([string]$Manifest.backupDirectory)
    }
    return (Assert-ClientScopedStatePath -Path $path)
}

function Backup-InstallTargets {
    param([Parameter(Mandatory = $true)]$Manifest)
    $backupRoot = Get-BackupRoot $Manifest
    if (Test-Path -LiteralPath $backupRoot) {
        throw "Backup directory already exists: $backupRoot"
    }
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
    Assert-ClientScopedStatePath -Path $backupRoot | Out-Null

    foreach ($operation in @($Manifest.operations)) {
        if ($operation.kind -ne "replace") { continue }
        $source = Join-Path $script:ClientRoot ([string]$operation.destination)
        $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
        $parent = Assert-ClientScopedStatePath -Path (Split-Path -Parent $backup)
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-FileAtomic -Source $source -Destination $backup -ExpectedSha256 ([string]$operation.originalSha256)
        if ((Get-Sha256 $backup) -ne [string]$operation.originalSha256) {
            throw "Backup verification failed for $($operation.destination)"
        }
    }

    $configBackup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$Manifest.config.backup))
    $configBackupParent = Assert-ClientScopedStatePath -Path (Split-Path -Parent $configBackup)
    New-Item -ItemType Directory -Path $configBackupParent -Force | Out-Null
    Copy-FileAtomic -Source $script:ConfigPath -Destination $configBackup -ExpectedSha256 ([string]$Manifest.config.originalSha256)
    if ((Get-Sha256 $configBackup) -ne [string]$Manifest.config.originalSha256) {
        throw "Backup verification failed for EvEJSConfig.bat"
    }

    $Manifest.status = "backedUp"
    Write-JsonAtomic -Value $Manifest -Path $script:ActiveManifestPath
}

function Invoke-RecoveryRollback {
    param([Parameter(Mandatory = $true)]$Manifest)
    $backupRoot = Get-BackupRoot $Manifest
    foreach ($operation in @($Manifest.operations)) {
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($operation.kind -eq "replace") {
            $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
            if (Test-Path -LiteralPath $backup -PathType Leaf) {
                Copy-FileAtomic -Source $backup -Destination $destination -ExpectedSha256 ([string]$operation.originalSha256)
            }
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            $current = Get-Sha256 $destination
            if ($current -eq [string]$operation.installedSha256) {
                Remove-Item -LiteralPath $destination -Force
            }
        }
    }

    $configBackup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$Manifest.config.backup))
    if (Test-Path -LiteralPath $configBackup -PathType Leaf) {
        Copy-FileAtomic -Source $configBackup -Destination $script:ConfigPath -ExpectedSha256 ([string]$Manifest.config.originalSha256)
    }
    Restore-ReShadeConfig -Manifest $Manifest
}

function Assert-RecoveryRollbackComplete {
    param([Parameter(Mandatory = $true)]$Manifest)

    foreach ($operation in @($Manifest.operations)) {
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($operation.kind -eq "replace") {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                (Get-Sha256 $destination) -ne [string]$operation.originalSha256) {
                throw "Rollback verification failed for replaced file: $($operation.destination)"
            }
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            throw "Rollback verification found an installer-added file: $($operation.destination)"
        }
    }

    $exeHash = Get-Sha256 $script:ExePath
    if ($exeHash -ne [string]$Manifest.executable.sha256 -or $exeHash -ne $script:ExpectedExeSha256) {
        throw "Rollback verification found an unexpected exefile.exe hash."
    }
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf) -or
        (Get-Sha256 $script:ConfigPath) -ne [string]$Manifest.config.originalSha256) {
        throw "Rollback verification found an unrestored EvEJSConfig.bat."
    }

    if ($Manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $Manifest.reshadeConfig) {
        $configExists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
        if (-not [bool]$Manifest.reshadeConfig.originalExists -and $configExists) {
            throw "Rollback verification found a generated ReShade.ini."
        }
        if ([bool]$Manifest.reshadeConfig.originalExists) {
            if (-not $configExists) {
                throw "Rollback verification found the pre-existing ReShade.ini missing."
            }
            $backup = Assert-ClientScopedStatePath -Path (Join-Path (Get-BackupRoot $Manifest) ([string]$Manifest.reshadeConfig.backup))
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
                (Get-Sha256 $backup) -ne [string]$Manifest.reshadeConfig.originalSha256) {
                throw "Rollback verification found an invalid ReShade.ini backup."
            }
            $currentSection = Get-IniSectionText -Text ([IO.File]::ReadAllText($script:ReShadeConfigPath)) -Section "RenoDX.DLSS5"
            $originalSection = Get-IniSectionText -Text ([IO.File]::ReadAllText($backup)) -Section "RenoDX.DLSS5"
            if (-not $currentSection.Equals($originalSection, [StringComparison]::Ordinal)) {
                throw "Rollback verification found an unrestored RenoDX ReShade.ini section."
            }
        }
    }

    foreach ($relativePath in @("bin64\ReShade.log", "bin64\ReShadePreset.ini")) {
        $artifactPath = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot $relativePath)
        if ((Test-FileAbsentFromBaseline -RelativePath $relativePath) -and
            (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "Rollback verification found a generated ReShade artifact: $relativePath"
        }
    }
}

function Invoke-Preflight {
    Assert-NoTargetClientProcess
    Assert-WorkspaceLayout
    $payload = Assert-Payload
    foreach ($file in @($payload.files)) {
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$file.destination))
        Assert-RequiredOriginalTarget -File $file -Destination $destination
    }

    Write-Step "Preflight passed"
    Write-Okay "write boundary: $script:WorkspaceRoot"
    Write-Okay "target client: $script:ClientRoot"
    Write-Okay "exefile.exe remains byte-for-byte untouched"
    Write-Okay "DX12 module present: bin64\_trinity_dx12.dll"
    $enabledFiles = @($payload.files | Where-Object {
        Test-ComponentEnabled -ProfileName $Profile -Component ([string]$_.component)
    })
    Write-Okay "$(@($payload.files).Count) pinned payload files verified; $($enabledFiles.Count) selected for '$Profile'"
    if (-not (Test-ComponentEnabled -ProfileName $Profile -Component "runtime")) {
        Write-Okay "EVE's existing DLSS and Streamline runtime files remain untouched"
    }
    $neuralRuntime = @($payload.files | Where-Object {
        ([string]$_.destination).Equals("bin64\nvngx_dlssnr.dll", [StringComparison]::OrdinalIgnoreCase)
    }) | Select-Object -First 1
    if ($neuralRuntime) {
        Write-Okay "DLSSNR $($neuralRuntime.version) SHA-256 and NVIDIA Authenticode signature were verified"
    }
    $renoDx = @($payload.files | Where-Object { ([string]$_.component) -eq "renodx" }) | Select-Object -First 1
    if ($renoDx) {
        Write-Okay "RenoDX DLSS5 add-on $($renoDx.version) is hash-pinned"
    }

    Write-Host ""
    Write-Host "  Planned client changes for '$Profile':" -ForegroundColor White
    foreach ($file in $enabledFiles) {
        $target = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$file.destination))
        $verb = if (Test-Path -LiteralPath $target -PathType Leaf) { "replace" } else { "add" }
        $old = if (Test-Path -LiteralPath $target -PathType Leaf) { (Get-Item -LiteralPath $target).VersionInfo.FileVersion } else { "-" }
        Write-Host ("    {0,-7} {1,-38} {2,-14} -> {3}" -f $verb, $file.destination, $old, $file.version)
    }
    return $payload
}

function Assert-NoInstalledLegacyRootLocalJournal {
    $legacyStateRoot = Get-NormalizedPath (Join-Path $script:EveJSRoot "_local\dlss5\install")
    if ($legacyStateRoot.Equals((Get-NormalizedPath $script:StateRoot), [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    $legacyManifestPath = Join-Path $legacyStateRoot "active-install.json"
    if (-not (Test-Path -LiteralPath $legacyManifestPath -PathType Leaf)) { return }

    $legacyItem = Get-Item -LiteralPath $legacyManifestPath -Force
    if ($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint -or
        [Int64]$legacyItem.Length -lt 2 -or [Int64]$legacyItem.Length -gt 1048576) {
        throw "A legacy root-local DLSS5 journal exists but cannot be safely inspected: $legacyManifestPath"
    }
    try {
        $legacy = [IO.File]::ReadAllText($legacyManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        throw "A legacy root-local DLSS5 journal exists but is invalid. Restore or repair it with its original package before installing this client-scoped package: $legacyManifestPath"
    }
    $legacyStatus = if ($legacy.PSObject.Properties.Name -contains "status") { [string]$legacy.status } else { "unknown" }
    if ($legacyStatus -notin @("restored", "rolledBack")) {
        throw "Legacy root-local DLSS5 state is '$legacyStatus' at $legacyManifestPath. This client-scoped package will not copy or relabel that receipt. Restore it with the original package first."
    }
}

function Invoke-Install {
    Assert-NoTargetClientProcess
    Assert-NoInstalledLegacyRootLocalJournal
    $existing = Read-ActiveManifest
    if ($null -ne $existing) {
        if ($existing.status -eq "installed") {
            throw "DLSS5 is already installed. Use -Action Verify or -Action Restore."
        }
        if ($existing.status -notin @("restored", "rolledBack")) {
            throw "An incomplete install journal exists with status '$($existing.status)'. Run -Action Restore first."
        }
        $history = Assert-ClientScopedStatePath -Path (Join-Path $script:StateRoot "history")
        New-Item -ItemType Directory -Path $history -Force | Out-Null
        $archiveName = "active-install-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ") + ".json"
        $archivePath = Assert-ClientScopedStatePath -Path (Join-Path $history $archiveName)
        $activeManifestPath = Assert-ClientScopedStatePath -Path $script:ActiveManifestPath
        if (Test-Path -LiteralPath $archivePath) {
            throw "Install history destination already exists: $archivePath"
        }
        Move-Item -LiteralPath $activeManifestPath -Destination $archivePath
    }

    $payload = Invoke-Preflight
    New-ClientBaseline | Out-Null
    $backupName = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $manifest = New-InstallManifest -PayloadManifest $payload -BackupName $backupName -ProfileName $Profile
    Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath

    try {
        Write-Step "Backing up every existing target covered by the rollback journal"
        Backup-InstallTargets -Manifest $manifest
        Write-Okay "verified backup: $($manifest.backupDirectory)"

        $manifest.status = "applying"
        Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
        if (Test-ComponentEnabled -ProfileName $Profile -Component "reshade") {
            Initialize-ReShadeConfigTracking -Manifest $manifest
        }
        Write-Step "Applying the pinned files for profile '$Profile'"
        foreach ($operation in @($manifest.operations)) {
            $enabled = Test-ComponentEnabled -ProfileName $Profile -Component ([string]$operation.component)
            if (-not $enabled) { continue }
            $source = Assert-ClientScopedStatePath -Path (Join-Path $script:PayloadRoot ([string]$operation.source))
            $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
            Copy-FileAtomic -Source $source -Destination $destination -ExpectedSha256 ([string]$operation.installedSha256)
            $operation.applied = $true
            Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
            Write-Okay $operation.destination
        }

        Set-ReShadeConfigForProfile -Manifest $manifest -ProfileName $Profile

        Write-Step "Pointing EveJS at the copied client and forcing Trinity DX12"
        $configText = Get-UpdatedEveJSConfigText
        Write-TextAtomic -Text $configText -Path $script:ConfigPath
        $manifest.config.installedSha256 = Get-Sha256 $script:ConfigPath
        $manifest.config.applied = $true
        $manifest.status = "installed"
        $manifest.installedAtUtc = [DateTime]::UtcNow.ToString("o")
        $manifest.profile = $Profile
        $manifest.profileAppliedAtUtc = $manifest.installedAtUtc
        $manifest.profileHistory = @([pscustomobject][ordered]@{
            atUtc = $manifest.installedAtUtc
            from = $null
            to = $Profile
            reason = "initial install"
        })
        Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
        Invoke-Verify -PayloadManifest $payload
    } catch {
        $failure = $_.Exception.Message
        Write-WarningLine "install failed; restoring the verified originals"
        try {
            $manifest.status = "rollbackPending"
            Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
            Invoke-RecoveryRollback -Manifest $manifest
            Assert-RestoreBackups -Manifest $manifest
            Assert-RecoveryRollbackComplete -Manifest $manifest
            $manifest.status = "rolledBack"
            Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
        } catch {
            $rollbackFailure = $_.Exception.Message
            throw "Install failed: $failure. Automatic rollback also failed: $rollbackFailure"
        }
        throw "Install failed and was rolled back: $failure"
    }

    Write-Host ""
    Write-Host "DLSS5 integration installed. Runtime activation still requires an in-game smoke test." -ForegroundColor Green
}

function Set-EveJSRootContext {
    param([Parameter(Mandatory = $true)][string]$Root)
    $script:EveJSRoot = Get-NormalizedPath $Root
    $script:ConfigPath = Join-Path $script:EveJSRoot "tools\ClientSETUP\scripts\EvEJSConfig.bat"
}

function Assert-RestoreBackups {
    param([Parameter(Mandatory = $true)]$Manifest)

    $backupRoot = Get-BackupRoot $Manifest
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw "Verified backup directory is missing: $backupRoot"
    }
    foreach ($operation in @($Manifest.operations)) {
        if ($operation.kind -ne "replace") { continue }
        $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup file is missing: $backup"
        }
        if ((Get-Sha256 $backup) -ne [string]$operation.originalSha256) {
            throw "Backup hash mismatch: $backup"
        }
        if ($operation.PSObject.Properties.Name -contains "originalBytes" -and
            $null -ne $operation.originalBytes -and
            [Int64](Get-Item -LiteralPath $backup).Length -ne [Int64]$operation.originalBytes) {
            throw "Backup byte count mismatch: $backup"
        }
    }

    $configBackup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$Manifest.config.backup))
    if (-not (Test-Path -LiteralPath $configBackup -PathType Leaf) -or
        (Get-Sha256 $configBackup) -ne [string]$Manifest.config.originalSha256) {
        throw "Config backup is missing or has the wrong hash: $configBackup"
    }
    if ($Manifest.PSObject.Properties.Name -contains "reshadeConfig" -and
        $null -ne $Manifest.reshadeConfig -and [bool]$Manifest.reshadeConfig.originalExists) {
        $reshadeBackup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$Manifest.reshadeConfig.backup))
        if (-not (Test-Path -LiteralPath $reshadeBackup -PathType Leaf) -or
            (Get-Sha256 $reshadeBackup) -ne [string]$Manifest.reshadeConfig.originalSha256) {
            throw "ReShade.ini backup is missing or has the wrong hash: $reshadeBackup"
        }
    }
    Write-Okay "every rollback backup for the active root is present and hash-verified"
}

function Move-TerminalRootStateToHistory {
    param([Parameter(Mandatory = $true)]$TerminalManifest)

    if ([string]$TerminalManifest.status -notin @("restored", "rolledBack")) {
        throw "Only a fully rolled-back receipt may be archived for root handoff."
    }
    $historyRoot = Assert-ClientScopedStatePath -Path (Join-Path $script:StateRoot "history")
    New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
    $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $manifestArchive = Assert-ClientScopedStatePath -Path (Join-Path $historyRoot ("active-install-before-root-handoff-" + $stamp + ".json"))
    $baselineArchive = Assert-ClientScopedStatePath -Path (Join-Path $historyRoot ("baseline-before-root-handoff-" + $stamp + ".json"))
    $activeManifestPath = Assert-ClientScopedStatePath -Path $script:ActiveManifestPath
    $baselinePath = Assert-ClientScopedStatePath -Path $script:BaselinePath
    if ((Test-Path -LiteralPath $manifestArchive) -or (Test-Path -LiteralPath $baselineArchive)) {
        throw "Root-handoff history destination already exists."
    }
    if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
        throw "The verified old-root baseline disappeared before archival."
    }

    Move-Item -LiteralPath $baselinePath -Destination $baselineArchive
    try {
        Move-Item -LiteralPath $activeManifestPath -Destination $manifestArchive
    } catch {
        Move-Item -LiteralPath $baselineArchive -Destination $baselinePath -ErrorAction SilentlyContinue
        throw
    }
    Write-Okay "archived the rolled-back old-root receipt unchanged: $manifestArchive"
    Write-Okay "archived the old-root client baseline: $baselineArchive"
}

function Invoke-ClientScopedRootHandoff {
    param([Parameter(Mandatory = $true)]$CandidateManifest)

    Assert-NoTargetClientProcess
    Assert-WorkspaceLayout
    $payload = Read-PayloadManifest

    if (-not ($CandidateManifest.PSObject.Properties.Name -contains "schemaVersion") -or
        [int]$CandidateManifest.schemaVersion -ne 5 -or
        -not ($CandidateManifest.PSObject.Properties.Name -contains "stateScope") -or
        -not ([string]$CandidateManifest.stateScope).Equals("client", [StringComparison]::Ordinal) -or
        [string]$CandidateManifest.status -notin @("installed", "restored", "rolledBack")) {
        throw "Automatic root handoff requires an installed or fully rolled-back schema-5 client-scoped receipt."
    }

    foreach ($requiredPathProperty in @("workspaceRoot", "evejsRoot", "clientRoot", "stateRoot")) {
        if ($CandidateManifest.PSObject.Properties.Name -notcontains $requiredPathProperty -or
            [string]::IsNullOrWhiteSpace([string]$CandidateManifest.$requiredPathProperty) -or
            -not [IO.Path]::IsPathRooted([string]$CandidateManifest.$requiredPathProperty)) {
            throw "The client-scoped receipt has no unambiguous $requiredPathProperty path."
        }
    }
    if (-not ($CandidateManifest.PSObject.Properties.Name -contains "config") -or
        $null -eq $CandidateManifest.config -or
        $CandidateManifest.config.PSObject.Properties.Name -notcontains "path" -or
        [string]::IsNullOrWhiteSpace([string]$CandidateManifest.config.path) -or
        -not [IO.Path]::IsPathRooted([string]$CandidateManifest.config.path)) {
        throw "The client-scoped receipt has no unambiguous EveJS configuration path."
    }

    $targetRoot = Get-NormalizedPath $script:EveJSRoot
    $targetWorkspace = Get-NormalizedPath $script:WorkspaceRoot
    $oldRoot = Get-NormalizedPath ([string]$CandidateManifest.evejsRoot)
    $oldWorkspace = Get-NormalizedPath ([string]$CandidateManifest.workspaceRoot)
    $recordedClient = Get-NormalizedPath ([string]$CandidateManifest.clientRoot)
    $recordedState = Get-NormalizedPath ([string]$CandidateManifest.stateRoot)
    $targetParent = Get-NormalizedPath (Split-Path -Parent $targetRoot)
    $oldParent = Get-NormalizedPath (Split-Path -Parent $oldRoot)

    if ($oldRoot.Equals($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Root handoff was requested for the same EveJS root."
    }
    if (-not $targetParent.Equals($oldParent, [StringComparison]::OrdinalIgnoreCase) -or
        -not $targetWorkspace.Equals($targetParent, [StringComparison]::OrdinalIgnoreCase) -or
        -not $oldWorkspace.Equals($oldParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Automatic DLSS5 handoff is allowed only between different immediate sibling EveJS roots."
    }
    if (-not $recordedClient.Equals((Get-NormalizedPath $script:ClientRoot), [StringComparison]::OrdinalIgnoreCase) -or
        -not $recordedState.Equals((Get-NormalizedPath $script:StateRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw "The installed receipt belongs to a different client or state root; automatic handoff is forbidden."
    }

    $oldContract = Assert-EveJSRootContract -Root $oldRoot
    if (-not (Get-NormalizedPath ([string]$CandidateManifest.config.path)).Equals((Get-NormalizedPath ([string]$oldContract.configPath)), [StringComparison]::OrdinalIgnoreCase)) {
        throw "The installed receipt's configuration path is not inside the recorded old EveJS root."
    }

    Write-Step "Handing the shared client from '$oldRoot' to '$targetRoot'"
    try {
        Set-EveJSRootContext -Root $oldRoot
        Assert-WorkspaceLayout
        $installed = Read-ActiveManifest
        if (-not (Test-ManifestMatchesPayloadMetadata -Manifest $installed -PayloadManifest $payload)) {
            throw "The old-root receipt does not match the exact client-scoped payload metadata."
        }
        Invoke-Verify -PayloadManifest $payload
        Assert-RestoreBackups -Manifest $installed
        if ([string]$installed.status -eq "installed") {
            Invoke-Restore
        } else {
            Write-Okay "the old-root receipt already proves a complete rollback; no client files were changed"
        }
    } finally {
        Set-EveJSRootContext -Root $targetRoot
    }

    $terminal = Read-ActiveManifestRaw
    if ($null -eq $terminal -or
        [string]$terminal.status -notin @("restored", "rolledBack") -or
        -not (Get-NormalizedPath ([string]$terminal.evejsRoot)).Equals($oldRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The old-root receipt was not left in a fully rolled-back state; target installation was not attempted."
    }
    Move-TerminalRootStateToHistory -TerminalManifest $terminal

    try {
        Invoke-Install
    } catch {
        $targetFailure = $_.Exception.Message
        $stockVerified = $false
        $postFailureProblem = $null
        try {
            $failedTargetManifest = Read-ActiveManifest
            if ($null -eq $failedTargetManifest) {
                # Invoke-Install creates its journal before touching the client.
                # No new journal therefore proves the target was rejected while
                # the already-verified old-root rollback was still stock.
                $stockVerified = $true
            } elseif ([string]$failedTargetManifest.status -eq "rolledBack") {
                Assert-RecoveryRollbackComplete -Manifest $failedTargetManifest
                $stockVerified = $true
            }
        } catch {
            $postFailureProblem = $_.Exception.Message
        }
        if ($stockVerified) {
            throw "The old EveJS root was safely restored, but installing DLSS5 for the target root failed. The shared client is verified stock. $targetFailure"
        }
        $recoveryDetail = if ($postFailureProblem) { " Post-failure verification: $postFailureProblem" } else { "" }
        throw "The old EveJS root was restored, but the target install did not reach a verified rollback. Do not launch the client; the client-scoped recovery journal was retained for explicit Restore.$recoveryDetail Target failure: $targetFailure"
    }
    Write-Okay "client-scoped root handoff completed with a fresh target-root receipt"
}

function Invoke-Ensure {
    $candidate = Read-ActiveManifestRaw
    if ($null -ne $candidate -and
        $candidate.PSObject.Properties.Name -contains "evejsRoot" -and
        $candidate.evejsRoot -and
        -not (Get-NormalizedPath ([string]$candidate.evejsRoot)).Equals((Get-NormalizedPath $script:EveJSRoot), [StringComparison]::OrdinalIgnoreCase)) {
        Invoke-ClientScopedRootHandoff -CandidateManifest $candidate
        return
    }

    $existing = Read-ActiveManifest
    if ($null -eq $existing -or $existing.status -in @("restored", "rolledBack")) {
        Invoke-Install
        return
    }
    if ($existing.status -ne "installed") {
        throw "DLSS5 cannot be ensured while the install journal has status '$($existing.status)'. Run -Action Restore first."
    }

    # A launcher may call Ensure before every client start. Keep that operation
    # idempotent while still validating package updates and every owned byte.
    # The exact package/profile path is strictly read-only, so a second client
    # can launch while the first one still has the DLLs mapped. Any update or
    # profile transition still requires every target client to be closed.
    Assert-WorkspaceLayout
    $payload = Read-PayloadManifest
    $payloadMatches = Test-ManifestMatchesPayloadMetadata -Manifest $existing -PayloadManifest $payload
    $profileMatches = (Get-ManifestProfile $existing) -eq $Profile
    if ($payloadMatches -and $profileMatches) {
        Write-Okay "active package and profile already match; running read-only verification"
        Invoke-Verify -PayloadManifest $payload
        return
    }

    if (-not $payloadMatches) {
        Invoke-UpgradePayload
        $existing = Read-ActiveManifest
    }
    if ((Get-ManifestProfile $existing) -ne $Profile) {
        Invoke-ApplyProfile
    }
}

function Get-PayloadUpgradeMode {
    param(
        [Parameter(Mandatory = $true)]$Operation,
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][bool]$ComponentEnabled,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $sameHash = ([string]$Operation.installedSha256).Equals([string]$File.sha256, [StringComparison]::OrdinalIgnoreCase)
    $sameBytes = [Int64]$Operation.installedBytes -eq [Int64]$File.bytes
    $sameSource = ([string]$Operation.source).Equals([string]$File.source, [StringComparison]::OrdinalIgnoreCase)
    $sameComponent = ([string]$Operation.component).Equals([string]$File.component, [StringComparison]::OrdinalIgnoreCase)
    if ($sameHash -and $sameBytes -and $sameSource -and $sameComponent) {
        return "Unchanged"
    }

    if ($ComponentEnabled) {
        if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and
            (Get-Sha256 $Destination) -eq [string]$File.sha256) {
            # The exact new payload is already active (for example, after a
            # separately verified hotfix). Adopt only that byte-identical file;
            # never rewrite an enabled component during journal migration.
            return "AdoptInstalled"
        }
        throw "Payload upgrade stopped: enabled component '$($File.component)' is not already at the exact new payload: $($Operation.destination)"
    }

    if ($Operation.kind -eq "replace") {
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
            (Get-Sha256 $Destination) -ne [string]$Operation.originalSha256) {
            throw "Payload upgrade stopped: disabled replacement is not at its recorded original: $($Operation.destination)"
        }
    } elseif ($Operation.kind -eq "add") {
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            throw "Payload upgrade stopped: disabled addition is unexpectedly present: $($Operation.destination)"
        }
    } else {
        throw "Payload upgrade encountered unknown operation kind '$($Operation.kind)' for $($Operation.destination)."
    }
    return "JournalDisabled"
}

function Invoke-UpgradePayload {
    Assert-NoTargetClientProcess
    Assert-WorkspaceLayout
    $payload = Read-PayloadManifest
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest -or $manifest.status -ne "installed") {
        throw "No completed integration journal is available for a payload upgrade."
    }

    # Public packages own only five files. Do not silently reinterpret the
    # larger historical lab receipt and lose its original-file inventory.
    if (@($manifest.operations).Count -ne @($payload.files).Count) {
        throw 'This package cannot migrate a legacy or different-file-set receipt. Restore with the original package first; keep its backups, then install this package with all target clients closed.'
    }
    foreach ($operation in @($manifest.operations)) {
        $newTargets = @($payload.files | Where-Object {
            ([string]$_.destination).Equals([string]$operation.destination, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($newTargets.Count -ne 1) {
            throw 'Payload upgrade would change the owned file set. Restore with the original package first; keep its backups.'
        }
    }
    $payload = Initialize-PublicPayload -Manifest $payload

    $currentProfile = Get-ManifestProfile $manifest
    $changes = New-Object System.Collections.Generic.List[object]
    foreach ($file in @($payload.files)) {
        $matches = @($manifest.operations | Where-Object {
            ([string]$_.destination).Equals([string]$file.destination, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($matches.Count -ne 1) {
            throw "Payload upgrade requires exactly one journal operation for $($file.destination); found $($matches.Count)."
        }

        $operation = $matches[0]
        $component = [string]$file.component
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        $upgradeMode = Get-PayloadUpgradeMode `
            -Operation $operation `
            -File $file `
            -ComponentEnabled (Test-ComponentEnabled -ProfileName $currentProfile -Component $component) `
            -Destination $destination
        if ($upgradeMode -eq "Unchanged") { continue }

        $changes.Add([pscustomobject][ordered]@{
            operation = $operation
            file = $file
            mode = $upgradeMode
            oldSource = [string]$operation.source
            oldSha256 = [string]$operation.installedSha256
            oldBytes = [Int64]$operation.installedBytes
        })
    }

    # Packaging-only releases can keep every client payload byte unchanged.
    # Their receipt still needs the normal archived/atomic metadata migration,
    # including verification failure rollback, before Ensure can match it.
    $samePackageVersion = ($manifest.PSObject.Properties.Name -contains 'integrationVersion') -and
        ([string]$manifest.integrationVersion).Equals([string]$payload.integrationVersion, [StringComparison]::Ordinal)
    if ($changes.Count -eq 0 -and $samePackageVersion) {
        Write-Okay "active journal already matches payload version $($payload.integrationVersion)"
        Invoke-Verify -PayloadManifest $payload
        return
    }

    $historyRoot = Assert-ClientScopedStatePath -Path (Join-Path $script:StateRoot "history")
    New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
    $archiveName = "active-install-before-payload-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ") + ".json"
    $archivePath = Assert-ClientScopedStatePath -Path (Join-Path $historyRoot $archiveName)
    $activeManifestPath = Assert-ClientScopedStatePath -Path $script:ActiveManifestPath
    if (Test-Path -LiteralPath $archivePath) {
        throw "Payload history destination already exists: $archivePath"
    }
    Copy-Item -LiteralPath $activeManifestPath -Destination $archivePath
    $archiveHash = Get-Sha256 $archivePath

    $now = [DateTime]::UtcNow.ToString("o")
    $payloadHistory = @()
    if ($manifest.PSObject.Properties.Name -contains "payloadHistory" -and $manifest.payloadHistory) {
        $payloadHistory = @($manifest.payloadHistory)
    }
    foreach ($change in $changes) {
        Add-OrSetProperty -Object $change.operation -Name "source" -Value ([string]$change.file.source)
        Add-OrSetProperty -Object $change.operation -Name "component" -Value ([string]$change.file.component)
        Add-OrSetProperty -Object $change.operation -Name "installedSha256" -Value ([string]$change.file.sha256)
        Add-OrSetProperty -Object $change.operation -Name "installedBytes" -Value ([Int64]$change.file.bytes)
        Add-OrSetProperty -Object $change.operation -Name "applied" -Value ($change.mode -eq "AdoptInstalled")
        $payloadHistory += [pscustomobject][ordered]@{
            atUtc = $now
            destination = [string]$change.operation.destination
            component = [string]$change.file.component
            fromSource = $change.oldSource
            toSource = [string]$change.file.source
            fromSha256 = $change.oldSha256
            toSha256 = [string]$change.file.sha256
            fromBytes = $change.oldBytes
            toBytes = [Int64]$change.file.bytes
            reason = if ($change.mode -eq "AdoptInstalled") {
                "adopted exact already-installed payload without rewriting enabled component"
            } else {
                "verified supplemental payload upgrade while component disabled"
            }
        }
        Write-Okay "journaled payload upgrade for $($change.operation.destination)"
    }
    Add-OrSetProperty -Object $manifest -Name "integrationVersion" -Value ([string]$payload.integrationVersion)
    Add-OrSetProperty -Object $manifest -Name "payloadHistory" -Value $payloadHistory
    Add-OrSetProperty -Object $manifest -Name "payloadUpgradedAtUtc" -Value $now

    try {
        Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
        Invoke-Verify -PayloadManifest $payload
    } catch {
        $failure = $_.Exception.Message
        Copy-FileAtomic -Source $archivePath -Destination $script:ActiveManifestPath -ExpectedSha256 $archiveHash
        throw "Payload upgrade failed; the prior journal was restored: $failure"
    }

    Write-Host ""
    Write-Host "Payload journal upgraded safely. Enabled components were adopted only when already byte-identical; no client file was rewritten." -ForegroundColor Green
}

function Invoke-ApplyProfile {
    Assert-NoTargetClientProcess
    Assert-WorkspaceLayout
    $payload = Assert-Payload
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest -or $manifest.status -notin @("installed", "restored")) {
        throw "No complete integration journal is available. Run -Action Install first."
    }
    Assert-ManifestPayloadCoverage -Manifest $manifest -PayloadManifest $payload

    $currentProfile = Get-ManifestProfile $manifest
    $backupRoot = Get-BackupRoot $manifest
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw "Verified backup directory is missing: $backupRoot"
    }
    if ((Test-ComponentEnabled -ProfileName $Profile -Component "reshade") -or
        ($manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $manifest.reshadeConfig)) {
        Initialize-ReShadeConfigTracking -Manifest $manifest
    }

    # Refuse unknown drift before changing profiles. A profile transition may
    # replace only a recorded original or one of our pinned payload files.
    foreach ($operation in @($manifest.operations)) {
        $component = Get-OperationComponent -Operation $operation -PayloadManifest $payload
        Add-OrSetProperty -Object $operation -Name "component" -Value $component
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($operation.kind -eq "replace") {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
                throw "Profile transition stopped: replaced file is missing: $($operation.destination)"
            }
            $currentHash = Get-Sha256 $destination
            if ($currentHash -notin @([string]$operation.originalSha256, [string]$operation.installedSha256)) {
                throw "Profile transition stopped on user drift: $($operation.destination)"
            }
            $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
                (Get-Sha256 $backup) -ne [string]$operation.originalSha256) {
                throw "Original backup is missing or invalid: $backup"
            }
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            if ((Get-Sha256 $destination) -ne [string]$operation.installedSha256) {
                throw "Profile transition stopped on user-owned added file: $($operation.destination)"
            }
        }
    }

    if (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf) {
        $configHash = Get-Sha256 $script:ConfigPath
        $knownConfigHashes = @([string]$manifest.config.originalSha256)
        if ($manifest.config.installedSha256) {
            $knownConfigHashes += [string]$manifest.config.installedSha256
        }
        if ($configHash -notin $knownConfigHashes) {
            throw "Profile transition stopped because EvEJSConfig.bat changed after installation."
        }
    }

    Write-Step "Applying component profile '$Profile'"
    foreach ($operation in @($manifest.operations)) {
        $enabled = Test-ComponentEnabled -ProfileName $Profile -Component ([string]$operation.component)
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($enabled) {
            $source = Assert-ClientScopedStatePath -Path (Join-Path $script:PayloadRoot ([string]$operation.source))
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                (Get-Sha256 $destination) -ne [string]$operation.installedSha256) {
                Copy-FileAtomic -Source $source -Destination $destination -ExpectedSha256 ([string]$operation.installedSha256)
                Write-Okay "enabled $($operation.destination)"
            }
            Add-OrSetProperty -Object $operation -Name "applied" -Value $true
        } elseif ($operation.kind -eq "replace") {
            if ((Get-Sha256 $destination) -ne [string]$operation.originalSha256) {
                $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
                Copy-FileAtomic -Source $backup -Destination $destination -ExpectedSha256 ([string]$operation.originalSha256)
                Write-Okay "restored original $($operation.destination)"
            }
            Add-OrSetProperty -Object $operation -Name "applied" -Value $false
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
            Write-Okay "disabled $($operation.destination)"
            Add-OrSetProperty -Object $operation -Name "applied" -Value $false
        } else {
            Add-OrSetProperty -Object $operation -Name "applied" -Value $false
        }
    }

    # Configure only the two INI keys owned by this integration after the
    # matching ReShade/RenoDX binaries are in place. All unrelated ReShade
    # settings remain user-owned and are preserved byte-for-byte where
    # possible.
    Set-ReShadeConfigForProfile -Manifest $manifest -ProfileName $Profile

    # Keep the copied client selected and DX12 active in every diagnostic
    # profile. Full uninstall is the separate Restore action.
    $configText = Get-UpdatedEveJSConfigText
    Write-TextAtomic -Text $configText -Path $script:ConfigPath
    $manifest.config.installedSha256 = Get-Sha256 $script:ConfigPath
    $manifest.config.applied = $true

    $now = [DateTime]::UtcNow.ToString("o")
    $history = @()
    if ($manifest.PSObject.Properties.Name -contains "profileHistory" -and $manifest.profileHistory) {
        $history = @($manifest.profileHistory)
    }
    $history += [pscustomobject][ordered]@{
        atUtc = $now
        from = $currentProfile
        to = $Profile
        reason = "component A/B transition"
    }
    Add-OrSetProperty -Object $manifest -Name "profileHistory" -Value $history
    Add-OrSetProperty -Object $manifest -Name "profile" -Value $Profile
    Add-OrSetProperty -Object $manifest -Name "profileAppliedAtUtc" -Value $now
    $manifest.status = "installed"
    Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath

    Invoke-Verify -PayloadManifest $payload
    Write-Host ""
    Write-Host "Profile '$Profile' is staged. Launch only through this EveJS copy for its control test." -ForegroundColor Green
}

function Invoke-Verify {
    param($PayloadManifest = $null)

    Assert-WorkspaceLayout
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest -or $manifest.status -notin @("installed", "restored", "rolledBack")) {
        throw "There is no completed DLSS5 installation or rollback to verify."
    }
    if ($manifest.status -in @("restored", "rolledBack")) {
        Write-Step "Verifying complete DLSS5 rollback"
        foreach ($operation in @($manifest.operations)) {
            $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
            if ($operation.kind -eq "replace") {
                if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                    (Get-Sha256 $destination) -ne [string]$operation.originalSha256) {
                    throw "Restored file hash mismatch: $($operation.destination)"
                }
            } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
                throw "Installer-added file remains after rollback: $($operation.destination)"
            }
        }

        $exeHash = Get-Sha256 $script:ExePath
        if ($exeHash -ne [string]$manifest.executable.sha256 -or $exeHash -ne $script:ExpectedExeSha256) {
            throw "exefile.exe changed unexpectedly during rollback."
        }
        if ((Get-Sha256 $script:ConfigPath) -ne [string]$manifest.config.originalSha256) {
            throw "EvEJSConfig.bat was not restored to its pre-install hash."
        }

        if ($manifest.PSObject.Properties.Name -contains "reshadeConfig" -and $null -ne $manifest.reshadeConfig) {
            $configExists = Test-Path -LiteralPath $script:ReShadeConfigPath -PathType Leaf
            if (-not [bool]$manifest.reshadeConfig.originalExists -and $configExists) {
                throw "Generated ReShade.ini remains after rollback."
            }
            if ([bool]$manifest.reshadeConfig.originalExists) {
                if (-not $configExists) { throw "Pre-existing ReShade.ini is missing after rollback." }
                $backup = Assert-ClientScopedStatePath -Path (Join-Path (Get-BackupRoot $manifest) ([string]$manifest.reshadeConfig.backup))
                $currentSection = Get-IniSectionText -Text ([IO.File]::ReadAllText($script:ReShadeConfigPath)) -Section "RenoDX.DLSS5"
                $originalSection = Get-IniSectionText -Text ([IO.File]::ReadAllText($backup)) -Section "RenoDX.DLSS5"
                if (-not $currentSection.Equals($originalSection, [StringComparison]::Ordinal)) {
                    throw "The original RenoDX ReShade.ini section was not restored."
                }
            }
        }

        foreach ($relativePath in @("bin64\ReShade.log", "bin64\ReShadePreset.ini")) {
            if ((Test-FileAbsentFromBaseline -RelativePath $relativePath) -and
                (Test-Path -LiteralPath (Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot $relativePath)) -PathType Leaf)) {
                throw "Generated ReShade artifact remains after rollback: $relativePath"
            }
        }

        Write-Okay "every replaced file matches its original hash and every added file is absent"
        Write-Okay "exefile.exe is unchanged: $exeHash"
        Write-Okay "EvEJSConfig.bat is restored to its pre-install hash"
        Write-Okay "generated ReShade configuration and logs are absent or restored"
        return
    }

    # Installed-state verification checks client bytes against the reviewed
    # manifest and receipt. It never needs to download or recreate the cache.
    $payload = if ($null -eq $PayloadManifest) { Read-PayloadManifest } else { $PayloadManifest }
    Assert-ManifestPayloadCoverage -Manifest $manifest -PayloadManifest $payload
    $currentProfile = Get-ManifestProfile $manifest
    $enabledCount = 0
    Write-Step "Verifying profile '$currentProfile' and launcher wiring"
    foreach ($operation in @($manifest.operations)) {
        $component = Get-OperationComponent -Operation $operation -PayloadManifest $payload
        Add-OrSetProperty -Object $operation -Name "component" -Value $component
        $enabled = Test-ComponentEnabled -ProfileName $currentProfile -Component $component
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($enabled) {
            $enabledCount++
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
                throw "Enabled profile file is missing: $($operation.destination)"
            }
            if ((Get-Sha256 $destination) -ne [string]$operation.installedSha256) {
                throw "Enabled profile hash mismatch: $($operation.destination)"
            }
        } elseif ($operation.kind -eq "replace") {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                (Get-Sha256 $destination) -ne [string]$operation.originalSha256) {
                throw "Original profile file mismatch: $($operation.destination)"
            }
        } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            throw "Disabled profile file is still present: $($operation.destination)"
        }
    }

    $exeHash = Get-Sha256 $script:ExePath
    if ($exeHash -ne [string]$manifest.executable.sha256 -or $exeHash -ne $script:ExpectedExeSha256) {
        throw "exefile.exe changed unexpectedly."
    }

    $configHash = Get-Sha256 $script:ConfigPath
    if ($configHash -ne [string]$manifest.config.installedSha256) {
        throw "EvEJSConfig.bat changed after installation."
    }
    $configText = [IO.File]::ReadAllText($script:ConfigPath)
    Assert-ExactBatchSettingValue -Text $configText -Name "EVEJS_CLIENT_PATH" -ExpectedValue $script:ClientRoot
    Assert-ExactBatchSettingValue -Text $configText -Name "EVEJS_CLIENT_EXE" -ExpectedValue "bin64\exefile.exe"
    Assert-ExactBatchSettingValue -Text $configText -Name "TRINITYPLATFORM" -ExpectedValue "dx12"
    Assert-ExactBatchSettingValue -Text $configText -Name "EVEJS_DLSS5" -ExpectedValue "on"

    if (Test-ComponentEnabled -ProfileName $currentProfile -Component "reshade") {
        $reshade = Assert-OwnedClientPath -Path (Join-Path $script:BinRoot "dxgi.dll")
        if (-not (Test-AsciiMarker -Path $reshade -Marker "Searching for add-ons")) {
            throw "The installed dxgi.dll is not the ReShade Addon loader."
        }
    }
    Test-ReShadeConfigForProfile -Manifest $manifest -ProfileName $currentProfile

    Write-Okay "$enabledCount payload files enabled; every disabled file is restored or absent"
    Write-Okay "exefile.exe is unchanged: $exeHash"
    Write-Okay "EveJS points only at the copied tq client"
    Write-Okay "TRINITYPLATFORM=dx12 is enabled"
    if (Test-ComponentEnabled -ProfileName $currentProfile -Component "reshade") {
        Write-Okay "ReShade Addon loader marker is present"
    } else {
        Write-Okay "ReShade proxy is disabled for this control"
    }
}

function Invoke-RuntimeCheck {
    param(
        [ValidateRange(0, [int]::MaxValue)][int]$RequestedProcessId = 0
    )

    Assert-WorkspaceLayout
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest -or $manifest.status -ne "installed") {
        throw "There is no staged profile to inspect."
    }
    $currentProfile = Get-ManifestProfile $manifest
    $isolatedProcesses = @(Get-IsolatedClientProcesses)
    $targetProcess = Select-RuntimeTargetProcess -Processes $isolatedProcesses -RequestedProcessId $RequestedProcessId
    $sharedRuntimeLog = $isolatedProcesses.Count -gt 1

    Write-Step "Inspecting profile '$currentProfile' in isolated exefile.exe PID $($targetProcess.Id)"
    $modules = @($targetProcess.Modules | ForEach-Object {
        [pscustomobject]@{ Name = $_.ModuleName.ToLowerInvariant(); Path = $_.FileName }
    })

    $dx12 = @($modules | Where-Object { $_.Name -eq "_trinity_dx12.dll" })
    if ($dx12.Count -eq 0) {
        throw "The DX12 Trinity renderer is not loaded."
    }
    $dx12Path = Get-NormalizedPath $dx12[0].Path
    if (-not (Test-FileDirectlyInDirectory -FilePath $dx12Path -DirectoryPath $script:BinRoot)) {
        throw "_trinity_dx12.dll loaded from outside the isolated bin64 folder: $dx12Path"
    }
    Write-Okay "_trinity_dx12.dll loaded from isolated bin64"

    if (@($modules | Where-Object { $_.Name -eq "_trinity_dx11.dll" }).Count -gt 0) {
        throw "Both DX11 and DX12 Trinity modules are loaded; this is not a valid DLSS5 test."
    }

    $expectReShade = Test-ComponentEnabled -ProfileName $currentProfile -Component "reshade"
    $localDxgi = @($modules | Where-Object {
        $_.Name -eq "dxgi.dll" -and
        (Test-FileDirectlyInDirectory -FilePath $_.Path -DirectoryPath $script:BinRoot)
    })
    if ($expectReShade -and $localDxgi.Count -eq 0) {
        throw "ReShade dxgi.dll is enabled by the profile but is not loaded from isolated bin64."
    }
    if (-not $expectReShade -and $localDxgi.Count -gt 0) {
        throw "A local dxgi.dll is loaded even though ReShade is disabled by the profile."
    }
    if ($expectReShade) {
        Write-Okay "ReShade dxgi.dll is active"
    } else {
        Write-Okay "system DXGI is active; ReShade is absent"
    }

    $expectRenoDx = Test-ComponentEnabled -ProfileName $currentProfile -Component "renodx"
    $renoDx = @($modules | Where-Object { $_.Name -eq "renodx-dlss5.addon64" })
    if ($expectRenoDx -and $renoDx.Count -eq 0) {
        throw "RenoDX is enabled by the profile but is not loaded."
    }
    if (-not $expectRenoDx -and $renoDx.Count -gt 0) {
        throw "RenoDX loaded even though it is disabled by the profile."
    }
    if ($expectRenoDx) {
        $renoPath = Get-NormalizedPath $renoDx[0].Path
        if (-not (Test-FileDirectlyInDirectory -FilePath $renoPath -DirectoryPath $script:BinRoot)) {
            throw "RenoDX loaded from outside the isolated bin64 folder: $renoPath"
        }
        Write-Okay "RenoDX add-on is active"
    } else {
        Write-Okay "RenoDX add-on is absent"
    }

    if (@($modules | Where-Object { $_.Name -eq "nvngx_dlss.dll" }).Count -gt 0) {
        Write-Okay "native nvngx_dlss.dll is active"
    } else {
        Write-WarningLine "nvngx_dlss.dll is not loaded yet; select native DLSS and render a scene"
    }

    $expectNeuralRuntime = Test-ComponentEnabled -ProfileName $currentProfile -Component "neuralRuntime"
    foreach ($name in @("nvngx_dlssnr.dll", "sl.dlss_nr.dll")) {
        $loaded = @($modules | Where-Object { $_.Name -eq $name }).Count -gt 0
        if ($loaded) {
            if (-not $expectNeuralRuntime) {
                throw "$name loaded even though the neural runtime is disabled by the profile."
            }
            Write-Okay "$name is active"
        } elseif ($expectRenoDx -and $name -eq "sl.dlss_nr.dll") {
            Write-Okay "$name remains unloaded in EnableHooks=2 NGX-only mode"
        } elseif ($expectRenoDx) {
            Write-WarningLine "$name is not loaded yet; neural-rendered frames are not proven"
        } elseif ($expectNeuralRuntime) {
            Write-WarningLine "$name is present but inactive in this control profile"
        }
    }

    if ($expectReShade) {
        if (-not (Test-Path -LiteralPath $script:ReShadeLogPath -PathType Leaf)) {
            throw "ReShade is active but no ReShade.log exists for runtime verification."
        }

        $logItem = Get-Item -LiteralPath $script:ReShadeLogPath
        $logReferenceProcess = $targetProcess
        if ($sharedRuntimeLog) {
            $logReferenceProcess = @($isolatedProcesses | Sort-Object StartTime -Descending)[0]
        }
        $processStartUtc = $logReferenceProcess.StartTime.ToUniversalTime()
        if ($logItem.LastWriteTimeUtc -lt $processStartUtc.AddSeconds(-2)) {
            throw "ReShade.log predates the current client launch; refusing stale runtime evidence."
        }
        if ($sharedRuntimeLog) {
            Write-WarningLine "ReShade.log is shared by $($isolatedProcesses.Count) clients; module checks apply to PID $($targetProcess.Id), while log counters prove only the shared current session"
            Write-Okay "shared ReShade.log is current relative to newest PID $($logReferenceProcess.Id) ($($logItem.LastWriteTimeUtc.ToString('u')))"
        } else {
            Write-Okay "ReShade.log belongs to the current launch ($($logItem.LastWriteTimeUtc.ToString('u')))"
        }

        if ($expectRenoDx) {
            $logText = Read-TextFileShared -Path $script:ReShadeLogPath
            $evidence = Get-NeuralLogEvidence -Text $logText
            if ($evidence.registrationCount -lt 1) {
                throw "The current ReShade.log does not show DLSS 5 Neural Rendering registration."
            }
            if ($evidence.registrationCount -gt 1) {
                Write-WarningLine "DLSS 5 registered $($evidence.registrationCount) times; early-load churn may still be present"
            } else {
                Write-Okay "DLSS 5 Neural Rendering registered once"
            }
            if (-not $evidence.hookArmed) {
                throw "The current ReShade.log does not show the D3D12 NGX hook being armed."
            }
            Write-Okay "D3D12 NGX hook is armed"

            if ($evidence.recoveredNativeFallbackCount -gt 0) {
                Write-WarningLine "$($evidence.recoveredNativeFallbackCount) direct low-resolution NR upscaling attempt(s) rejected; full-resolution neural post-pass recovery observed"
            }
            if (@($evidence.failureLines).Count -gt 0) {
                throw ("The neural add-on logged a fatal initialization/evaluation error:`n  - " + (@($evidence.failureLines) -join "`n  - "))
            }
            if (-not $evidence.runtimeInitialized) {
                throw "The signed DLSSNR runtime has not initialized; neural-rendered frames are not proven."
            }
            Write-Okay "signed DLSSNR 310.8.0 runtime initialized"

            if ($evidence.successfulFrames -lt 1) {
                throw "No successful neural evaluation is recorded for this launch."
            }
            if ($sharedRuntimeLog) {
                Write-Okay "shared current-session log records $($evidence.successfulFrames) successful neural frame evaluations; use each client's overlay for per-PID frame proof"
            } else {
                Write-Okay "$($evidence.successfulFrames) successful neural frame evaluations recorded"
            }
        }
    }
}

function Test-RestoreDrift {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [switch]$AllowDrift
    )
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($operation in @($Manifest.operations)) {
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            if ($operation.kind -eq "replace") {
                $problems.Add("missing replaced file: $($operation.destination)")
            }
            continue
        }
        $current = Get-Sha256 $destination
        if ($operation.kind -eq "replace") {
            if ($current -notin @([string]$operation.originalSha256, [string]$operation.installedSha256)) {
                $problems.Add("changed since install: $($operation.destination)")
            }
        } elseif ($current -ne [string]$operation.installedSha256) {
            $problems.Add("changed since install: $($operation.destination)")
        }
    }
    if ((Test-Path -LiteralPath $script:ConfigPath -PathType Leaf) -and $Manifest.config.installedSha256) {
        $configHash = Get-Sha256 $script:ConfigPath
        if ($configHash -notin @([string]$Manifest.config.originalSha256, [string]$Manifest.config.installedSha256)) {
            $problems.Add("changed since install: EvEJSConfig.bat")
        }
    }
    if ($problems.Count -gt 0 -and -not $AllowDrift) {
        throw ("Restore stopped to avoid overwriting newer changes. Re-run with -Force only if intended:`n  - " + ($problems -join "`n  - "))
    }
}

function Invoke-Restore {
    Assert-NoTargetClientProcess
    Assert-WorkspaceLayout
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest) {
        throw "No DLSS5 install journal exists."
    }
    if ($manifest.status -in @("restored", "rolledBack")) {
        # Re-run generated-artifact cleanup so an interrupted or older
        # uninstaller can be repaired idempotently without touching originals.
        Restore-ReShadeConfig -Manifest $manifest
        Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
        Invoke-Verify
        Write-Okay "the integration was already restored; rollback residue check is clean"
        return
    }

    Assert-RestoreBackups -Manifest $manifest
    $backupRoot = Get-BackupRoot $manifest
    $configBackup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$manifest.config.backup))

    Test-RestoreDrift -Manifest $manifest -AllowDrift:$Force
    Write-Step "Restoring original EVE client files and EveJS configuration"
    $reverseOperations = @($manifest.operations)
    [Array]::Reverse($reverseOperations)
    foreach ($operation in $reverseOperations) {
        $destination = Assert-OwnedClientPath -Path (Join-Path $script:ClientRoot ([string]$operation.destination))
        if ($operation.kind -eq "add") {
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                Remove-Item -LiteralPath $destination -Force
                Write-Okay "removed $($operation.destination)"
            }
        } else {
            $backup = Assert-ClientScopedStatePath -Path (Join-Path $backupRoot ([string]$operation.backup))
            Copy-FileAtomic -Source $backup -Destination $destination -ExpectedSha256 ([string]$operation.originalSha256)
            Write-Okay "restored $($operation.destination)"
        }
    }
    Restore-ReShadeConfig -Manifest $manifest
    Copy-FileAtomic -Source $configBackup -Destination $script:ConfigPath -ExpectedSha256 ([string]$manifest.config.originalSha256)

    if ((Get-Sha256 $script:ExePath) -ne [string]$manifest.executable.sha256) {
        throw "exefile.exe no longer matches the recorded baseline after restore."
    }

    $manifest.status = "restored"
    $manifest.restoredAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-JsonAtomic -Value $manifest -Path $script:ActiveManifestPath
    Invoke-Verify
    Write-Host ""
    Write-Host "Original client files and EveJS config restored. Backups and audit state were retained." -ForegroundColor Green
}

function Invoke-Status {
    Write-Host "EveJS DLSS5 integration" -ForegroundColor Cyan
    Write-Host "  Workspace : $script:WorkspaceRoot"
    Write-Host "  EveJS root: $script:EveJSRoot"
    Write-Host "  Client    : $script:ClientRoot"
    $manifest = Read-ActiveManifest
    if ($null -eq $manifest) {
        Write-Host "  Status    : not installed" -ForegroundColor Yellow
        return
    }
    Write-Host "  Status    : $($manifest.status)" -ForegroundColor $(if ($manifest.status -eq "installed") { "Green" } else { "Yellow" })
    if ($manifest.status -eq "installed") { Write-Host "  Profile   : $(Get-ManifestProfile $manifest)" }
    if ($manifest.installedAtUtc) { Write-Host "  Installed : $($manifest.installedAtUtc)" }
    if ($manifest.PSObject.Properties.Name -contains "profileAppliedAtUtc" -and $manifest.profileAppliedAtUtc) {
        Write-Host "  Profile at: $($manifest.profileAppliedAtUtc)"
    }
    if ($manifest.restoredAtUtc) { Write-Host "  Restored  : $($manifest.restoredAtUtc)" }
    Write-Host "  Journal   : $script:ActiveManifestPath"
}

$managerMutex = $null
$ownsManagerMutex = $false
try {
    if (-not (Test-Path -LiteralPath $script:PublicPayloadHelperPath -PathType Leaf)) {
        throw "The reviewed public payload helper is missing: $script:PublicPayloadHelperPath"
    }
    $helperItem = Get-Item -LiteralPath $script:PublicPayloadHelperPath
    if ($helperItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The public payload helper is a reparse point.'
    }
    $helperHash = Get-Sha256 $script:PublicPayloadHelperPath
    if (-not $helperHash.Equals($script:ExpectedPublicPayloadHelperSha256, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The public payload helper is not the exact reviewed implementation. Expected $script:ExpectedPublicPayloadHelperSha256, got $helperHash"
    }
    . $script:PublicPayloadHelperPath

    if ($Action -notin @('Status', 'Runtime')) {
        $lockPath = (Get-PhysicalPath $script:ClientRoot).ToUpperInvariant()
        $lockHasher = [Security.Cryptography.SHA256]::Create()
        try {
            $lockDigest = $lockHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($lockPath))
            $lockKey = ([BitConverter]::ToString($lockDigest)).Replace('-', '')
        } finally {
            $lockHasher.Dispose()
        }
        $managerMutex = New-Object Threading.Mutex($false, ('Local\EveJSDLSS5-' + $lockKey))
        try {
            # Do not spend the launcher's preparation budget waiting behind
            # another installer. The user can retry when that preparation ends.
            $ownsManagerMutex = $managerMutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $ownsManagerMutex = $true
        }
        if (-not $ownsManagerMutex) {
            throw 'Another DLSS5 manager is still preparing this client. Wait for it to finish, then retry.'
        }
    }
    switch ($Action) {
        "Status" { Invoke-Status }
        "Preflight" { Invoke-Preflight | Out-Null }
        "Install" { Invoke-Install }
        "Ensure" { Invoke-Ensure }
        "UpgradePayload" { Invoke-UpgradePayload }
        "ApplyProfile" { Invoke-ApplyProfile }
        "Verify" { Invoke-Verify }
        "Runtime" { Invoke-RuntimeCheck -RequestedProcessId $ProcessId }
        "Restore" { Invoke-Restore }
    }
} catch {
    Write-Host ""
    Write-Host ("DLSS5 integration error: " + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo.ScriptLineNumber) {
        Write-Host ("  at line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.InvocationInfo.Line.Trim()) -ForegroundColor DarkGray
    }
    exit 1
} finally {
    if ($null -ne $managerMutex) {
        if ($ownsManagerMutex) {
            $managerMutex.ReleaseMutex()
        }
        $managerMutex.Dispose()
    }
}
