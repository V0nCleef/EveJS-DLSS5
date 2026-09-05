Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# This file is dot-sourced only after Manage-EveJSDLSS5.ps1 has verified its
# SHA-256. Keep every network and archive operation in this reviewed helper;
# downloaded installers are never executed.

function Assert-PublicObjectProperties {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($null -eq $Value) {
        throw "$Label is missing."
    }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $Required) {
        if ($names -notcontains $name) {
            throw "$Label is missing required property '$name'."
        }
    }
    foreach ($name in $names) {
        if ($Allowed -notcontains $name) {
            throw "$Label contains unsupported property '$name'."
        }
    }
}

function Assert-PublicSha256Value {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "$Label must be a 64-character SHA-256 value."
    }
    return $Value.ToUpperInvariant()
}

function Assert-PublicRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not $Value -or [IO.Path]::IsPathRooted($Value)) {
        throw "$Label must be a non-empty relative path."
    }
    if ($Value -match '[:*?"<>|]') {
        throw "$Label contains a forbidden path character."
    }
    $parts = @($Value -split '[\\/]')
    if ($parts.Count -eq 0 -or @($parts | Where-Object { -not $_ -or $_ -in @('.', '..') }).Count -gt 0) {
        throw "$Label contains an unsafe path segment."
    }
    return ($parts -join '\')
}

function Assert-PublicPlainPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Get-NormalizedPath $Path
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($part in @($full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing a reparse point in the public package/cache path: $current"
        }
    }
    return $full
}

function Get-PublicExtendedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Assert-PublicPlainPath -Path $Path
    if (-not [IO.Path]::IsPathRooted($full)) {
        throw "An extended filesystem argument must be absolute: $Path"
    }
    if ($full.StartsWith('\\?\', [StringComparison]::Ordinal)) {
        return $full
    }
    if ($full.StartsWith('\\', [StringComparison]::Ordinal)) {
        return '\\?\UNC\' + $full.Substring(2)
    }
    return '\\?\' + $full
}

function Assert-PublicPayloadManifestContract {
    param([Parameter(Mandatory = $true)]$Manifest)

    Assert-PublicObjectProperties -Value $Manifest `
        -Required @('schemaVersion', 'integrationVersion', 'clientBuild', 'artifacts', 'generator', 'files') `
        -Allowed @('schemaVersion', 'integrationVersion', 'clientBuild', 'artifacts', 'generator', 'files') `
        -Label 'Payload manifest'
    if ([int]$Manifest.schemaVersion -ne 5) {
        throw "Unsupported public payload schemaVersion '$($Manifest.schemaVersion)'."
    }
    if (-not ([string]$Manifest.integrationVersion).Equals('0.5.6', [StringComparison]::Ordinal)) {
        throw "Unsupported public integrationVersion '$($Manifest.integrationVersion)'."
    }
    if ([int]$Manifest.clientBuild -ne 3396210) {
        throw "Unsupported client build '$($Manifest.clientBuild)'."
    }

    $expectedArtifacts = [ordered]@{
        'renodx-dlss5-4.70' = 'https://github.com/RankFTW/rhi-repo/releases/download/renodx-dlss5-4.70/renodx-dlss5_4.70.zip'
        'nvidia-dlssnr-310.8.0' = 'https://github.com/RankFTW/rhi-repo/releases/download/dlssnr-310.8.0/nvngx_dlssnr_310.8.0.zip'
        'nvidia-streamline-2.13.0.0' = 'https://github.com/RankFTW/rhi-repo/releases/download/streamline-2.13.0.0/streamline_2.13.0.0.zip'
    }
    $artifacts = @($Manifest.artifacts)
    if ($artifacts.Count -ne $expectedArtifacts.Count) {
        throw "Payload manifest must declare exactly $($expectedArtifacts.Count) download artifacts."
    }
    $artifactIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($artifact in $artifacts) {
        Assert-PublicObjectProperties -Value $artifact `
            -Required @('id', 'name', 'url', 'fileName', 'bytes', 'sha256', 'entries', 'licenseId') `
            -Allowed @('id', 'name', 'url', 'fileName', 'bytes', 'sha256', 'entries', 'licenseId') `
            -Label 'Download artifact'
        $id = [string]$artifact.id
        if (-not $expectedArtifacts.Contains($id)) {
            throw "Payload manifest contains unknown download artifact '$id'."
        }
        if (-not $artifactIds.Add($id)) {
            throw "Payload manifest contains duplicate download artifact '$id'."
        }
        if (-not ([string]$artifact.url).Equals([string]$expectedArtifacts[$id], [StringComparison]::Ordinal)) {
            throw "Download URL mismatch for artifact '$id'."
        }
        $uri = $null
        if (-not [Uri]::TryCreate([string]$artifact.url, [UriKind]::Absolute, [ref]$uri) -or
            -not $uri.Scheme.Equals('https', [StringComparison]::OrdinalIgnoreCase) -or
            -not $uri.Host.Equals('github.com', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Artifact '$id' must use the pinned HTTPS github.com release URL."
        }
        if ([Int64]$artifact.bytes -le 0) {
            throw "Artifact '$id' has an invalid byte count."
        }
        Assert-PublicSha256Value -Value ([string]$artifact.sha256) -Label "Artifact '$id' sha256" | Out-Null
        Assert-PublicRelativePath -Value ([string]$artifact.fileName) -Label "Artifact '$id' fileName" | Out-Null
        $entryNames = @($artifact.entries)
        if ($entryNames.Count -eq 0) {
            throw "Artifact '$id' must declare its complete ZIP entry list."
        }
        $entrySet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entryNameValue in $entryNames) {
            $entryName = [string]$entryNameValue
            Assert-PublicRelativePath -Value $entryName -Label "Artifact '$id' ZIP entry" | Out-Null
            if (-not $entrySet.Add($entryName)) {
                throw "Artifact '$id' contains a duplicate expected ZIP entry '$entryName'."
            }
        }
    }

    Assert-PublicObjectProperties -Value $Manifest.generator `
        -Required @('id', 'archiveEntry', 'embeddedFilename', 'originalPycBytes', 'originalPycSha256', 'patchedPycBytes', 'patchedPycSha256', 'pythonRuntime', 'tools', 'intermediateArchive', 'startupPatch') `
        -Allowed @('id', 'archiveEntry', 'embeddedFilename', 'originalPycBytes', 'originalPycSha256', 'patchedPycBytes', 'patchedPycSha256', 'pythonRuntime', 'tools', 'intermediateArchive', 'startupPatch') `
        -Label 'Client guard generator'
    if (-not ([string]$Manifest.generator.id).Equals('evejs-code-ccp-v12-local-source-v1', [StringComparison]::Ordinal)) {
        throw "Unsupported client guard generator '$($Manifest.generator.id)'."
    }
    if (-not ([string]$Manifest.generator.archiveEntry).Equals('eve/client/script/ui/shared/systemMenu/systemmenu.pyj', [StringComparison]::Ordinal) -or
        -not ([string]$Manifest.generator.embeddedFilename).Equals('eve/client/script/ui/shared/systemMenu/systemmenu.py', [StringComparison]::Ordinal)) {
        throw 'Client guard archive entry or embedded filename does not match the reviewed V12 candidate contract.'
    }
    Assert-PublicRelativePath -Value ([string]$Manifest.generator.archiveEntry) -Label 'Client guard archive entry' | Out-Null
    if ([Int64]$Manifest.generator.originalPycBytes -le 0 -or [Int64]$Manifest.generator.patchedPycBytes -le 0) {
        throw 'Client guard PYC byte counts must be positive.'
    }
    Assert-PublicSha256Value -Value ([string]$Manifest.generator.originalPycSha256) -Label 'Client guard original PYC sha256' | Out-Null
    Assert-PublicSha256Value -Value ([string]$Manifest.generator.patchedPycSha256) -Label 'Client guard patched PYC sha256' | Out-Null
    Assert-PublicObjectProperties -Value $Manifest.generator.intermediateArchive `
        -Required @('bytes', 'sha256') -Allowed @('bytes', 'sha256') -Label 'Client guard intermediate archive'
    if ([Int64]$Manifest.generator.intermediateArchive.bytes -ne 30760389 -or
        [string]$Manifest.generator.intermediateArchive.sha256 -cne '41A380AEF24D7304F595C7F4DBF93B5BD45D2F42A343E6DACD1C0096526A1FB1') {
        throw 'Client guard intermediate archive does not match the reviewed V12 first-stage output.'
    }
    $startup = $Manifest.generator.startupPatch
    Assert-PublicObjectProperties -Value $startup `
        -Required @('archiveEntry', 'embeddedFilename', 'className', 'methodName', 'originalPycBytes', 'originalPycSha256', 'patchedPycBytes', 'patchedPycSha256') `
        -Allowed @('archiveEntry', 'embeddedFilename', 'className', 'methodName', 'originalPycBytes', 'originalPycSha256', 'patchedPycBytes', 'patchedPycSha256') `
        -Label 'Client startup patch'
    if ([string]$startup.archiveEntry -cne 'carbonui/services/device.pyj' -or
        [string]$startup.embeddedFilename -cne 'carbonui/services/device.py' -or
        [string]$startup.className -cne 'DeviceMgr' -or [string]$startup.methodName -cne 'CreateDevice') {
        throw 'Client startup patch target does not match the reviewed class/method/archive contract.'
    }
    if ([Int64]$startup.originalPycBytes -ne 27911 -or
        [string]$startup.originalPycSha256 -cne '924F5050A7476845B8DBBB4CC96032A14C7773FF18373D707B605A75821A6F61' -or
        [Int64]$startup.patchedPycBytes -ne 30723 -or
        [string]$startup.patchedPycSha256 -cne 'C0F26D50BFB11AF910F67E3CC365EAFC82A275FAEF060926ED2FD1F7F859E409') {
        throw 'Client startup PYC contract does not match the reviewed V12 bytes.'
    }
    Assert-PublicObjectProperties -Value $Manifest.generator.pythonRuntime `
        -Required @('path', 'bytes', 'sha256', 'authenticode') `
        -Allowed @('path', 'bytes', 'sha256', 'authenticode') `
        -Label 'Client guard Python runtime'
    if (-not ([string]$Manifest.generator.pythonRuntime.path).Equals('bin64\python27.dll', [StringComparison]::Ordinal)) {
        throw 'Client guard Python runtime path must be bin64\python27.dll.'
    }
    if ([Int64]$Manifest.generator.pythonRuntime.bytes -le 0) {
        throw 'Client guard Python runtime byte count must be positive.'
    }
    Assert-PublicSha256Value -Value ([string]$Manifest.generator.pythonRuntime.sha256) -Label 'Client guard Python runtime sha256' | Out-Null
    Assert-PublicObjectProperties -Value $Manifest.generator.pythonRuntime.authenticode `
        -Required @('status', 'publisher', 'subject', 'thumbprint') `
        -Allowed @('status', 'publisher', 'subject', 'thumbprint') `
        -Label 'Client guard Python runtime Authenticode contract'
    if (-not ([string]$Manifest.generator.pythonRuntime.authenticode.status).Equals('Valid', [StringComparison]::Ordinal) -or
        -not ([string]$Manifest.generator.pythonRuntime.authenticode.publisher).Equals('CCP ehf.', [StringComparison]::Ordinal)) {
        throw 'Client guard Python runtime must require the pinned valid CCP publisher.'
    }
    $pythonThumbprint = ([string]$Manifest.generator.pythonRuntime.authenticode.thumbprint -replace '\s', '')
    if ($pythonThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
        throw 'Client guard Python runtime certificate thumbprint must be a 40-character SHA-1 value.'
    }
    $expectedTools = [ordered]@{
        'runner' = 'client-patches\tools\run_py27.exe'
        'runner-source' = 'client-patches\tools\run_py27.cpp'
        'builder' = 'client-patches\tools\build_code_ccp.py'
        'graphics-template' = 'client-patches\templates\systemmenu_apply_graphics.py.in'
        'startup-template' = 'client-patches\templates\device_create.py.in'
        'local-source' = 'client-patches\tools\local_source.py'
        'reconstruct' = 'client-patches\tools\reconstruct.py'
    }
    if (@($Manifest.generator.tools).Count -ne $expectedTools.Count) {
        throw "Client guard generator must declare exactly $($expectedTools.Count) reviewed tools."
    }
    $toolIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($tool in @($Manifest.generator.tools)) {
        Assert-PublicObjectProperties -Value $tool `
            -Required @('id', 'path', 'bytes', 'sha256') `
            -Allowed @('id', 'path', 'bytes', 'sha256') `
            -Label 'Client guard tool'
        if (-not $toolIds.Add([string]$tool.id)) {
            throw "Client guard generator contains duplicate tool '$($tool.id)'."
        }
        if (-not $expectedTools.Contains([string]$tool.id) -or
            -not ([string]$tool.path).Equals([string]$expectedTools[[string]$tool.id], [StringComparison]::Ordinal)) {
            throw "Client guard generator contains an unreviewed tool path for '$($tool.id)'."
        }
        Assert-PublicRelativePath -Value ([string]$tool.path) -Label "Client guard tool '$($tool.id)' path" | Out-Null
        if ([Int64]$tool.bytes -le 0) {
            throw "Client guard tool '$($tool.id)' has an invalid byte count."
        }
        Assert-PublicSha256Value -Value ([string]$tool.sha256) -Label "Client guard tool '$($tool.id)' sha256" | Out-Null
    }

    $expectedFiles = [ordered]@{
        'nvidia-dlssnr' = [ordered]@{ destination = 'bin64\nvngx_dlssnr.dll'; component = 'neuralRuntime'; sourceKind = 'archive'; artifactId = 'nvidia-dlssnr-310.8.0'; archiveEntry = 'nvngx_dlssnr.dll' }
        'nvidia-streamline-dlss-nr' = [ordered]@{ destination = 'bin64\sl.dlss_nr.dll'; component = 'neuralRuntime'; sourceKind = 'archive'; artifactId = 'nvidia-streamline-2.13.0.0'; archiveEntry = 'sl.dlss_nr.dll' }
        'renodx-dlss5' = [ordered]@{ destination = 'bin64\renodx-dlss5.addon64'; component = 'renodx'; sourceKind = 'archive'; artifactId = 'renodx-dlss5-4.70'; archiveEntry = 'renodx-dlss5.addon64' }
        'reshade-evejs' = [ordered]@{ destination = 'bin64\dxgi.dll'; component = 'reshade'; sourceKind = 'bundled'; artifactId = ''; archiveEntry = '' }
        'evejs-transition-guard' = [ordered]@{ destination = 'code.ccp'; component = 'clientGuard'; sourceKind = 'generated'; artifactId = ''; archiveEntry = '' }
    }
    $files = @($Manifest.files)
    if ($files.Count -ne $expectedFiles.Count) {
        throw "Payload manifest must declare exactly $($expectedFiles.Count) client files."
    }
    $fileIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $destinations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        Assert-PublicObjectProperties -Value $file `
            -Required @('id', 'source', 'destination', 'component', 'sourceKind', 'bytes', 'sha256', 'version', 'licenseId') `
            -Allowed @('id', 'source', 'destination', 'component', 'sourceKind', 'artifactId', 'archiveEntry', 'packagePath', 'generatorId', 'bytes', 'sha256', 'version', 'licenseId', 'authenticode', 'requiredOriginalBytes', 'requiredOriginalSha256') `
            -Label 'Payload file'
        $id = [string]$file.id
        if (-not $expectedFiles.Contains($id)) {
            throw "Payload manifest contains unknown client file '$id'."
        }
        if (-not $fileIds.Add($id)) {
            throw "Payload manifest contains duplicate client file '$id'."
        }
        if (-not $destinations.Add([string]$file.destination)) {
            throw "Payload manifest contains duplicate destination '$($file.destination)'."
        }
        $expected = $expectedFiles[$id]
        foreach ($property in @('destination', 'component', 'sourceKind')) {
            if (-not ([string]$file.$property).Equals([string]$expected[$property], [StringComparison]::Ordinal)) {
                throw "Payload contract mismatch for '$id' property '$property'."
            }
        }
        Assert-PublicRelativePath -Value ([string]$file.source) -Label "Payload '$id' source" | Out-Null
        Assert-PublicRelativePath -Value ([string]$file.destination) -Label "Payload '$id' destination" | Out-Null
        if ([Int64]$file.bytes -le 0) {
            throw "Payload '$id' has an invalid byte count."
        }
        Assert-PublicSha256Value -Value ([string]$file.sha256) -Label "Payload '$id' sha256" | Out-Null

        switch ([string]$file.sourceKind) {
            'archive' {
                foreach ($property in @('artifactId', 'archiveEntry')) {
                    if (-not ($file.PSObject.Properties.Name -contains $property) -or -not $file.$property) {
                        throw "Archive payload '$id' is missing '$property'."
                    }
                }
                if (-not ([string]$file.artifactId).Equals([string]$expected.artifactId, [StringComparison]::Ordinal) -or
                    -not ([string]$file.archiveEntry).Equals([string]$expected.archiveEntry, [StringComparison]::Ordinal)) {
                    throw "Archive source contract mismatch for payload '$id'."
                }
            }
            'bundled' {
                if (-not ($file.PSObject.Properties.Name -contains 'packagePath') -or -not $file.packagePath) {
                    throw "Bundled payload '$id' is missing packagePath."
                }
                Assert-PublicRelativePath -Value ([string]$file.packagePath) -Label "Bundled payload '$id' packagePath" | Out-Null
            }
            'generated' {
                if (-not ($file.PSObject.Properties.Name -contains 'generatorId') -or
                    -not ([string]$file.generatorId).Equals([string]$Manifest.generator.id, [StringComparison]::Ordinal)) {
                    throw "Generated payload '$id' has an unsupported generator."
                }
                foreach ($property in @('requiredOriginalBytes', 'requiredOriginalSha256')) {
                    if (-not ($file.PSObject.Properties.Name -contains $property) -or -not $file.$property) {
                        throw "Generated payload '$id' is missing '$property'."
                    }
                }
                Assert-PublicSha256Value -Value ([string]$file.requiredOriginalSha256) -Label "Generated payload '$id' required original sha256" | Out-Null
            }
            default { throw "Payload '$id' has unsupported sourceKind '$($file.sourceKind)'." }
        }

        if ($id -in @('nvidia-dlssnr', 'nvidia-streamline-dlss-nr') -and
            (-not ($file.PSObject.Properties.Name -contains 'authenticode') -or $null -eq $file.authenticode)) {
            throw "NVIDIA payload '$id' must require Authenticode verification."
        }
        if ($file.PSObject.Properties.Name -contains 'authenticode' -and $null -ne $file.authenticode) {
            Assert-PublicObjectProperties -Value $file.authenticode `
                -Required @('status', 'publisher', 'subject', 'thumbprint') `
                -Allowed @('status', 'publisher', 'subject', 'thumbprint') `
                -Label "Payload '$id' Authenticode contract"
            if (-not ([string]$file.authenticode.status).Equals('Valid', [StringComparison]::Ordinal)) {
                throw "Payload '$id' has an unsupported Authenticode status contract."
            }
            if (-not ([string]$file.authenticode.publisher).Equals('NVIDIA Corporation', [StringComparison]::Ordinal)) {
                throw "Payload '$id' has an unsupported Authenticode publisher contract."
            }
            $thumbprint = ([string]$file.authenticode.thumbprint -replace '\s', '')
            if ($thumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
                throw "Payload '$id' certificate thumbprint must be a 40-character SHA-1 value."
            }
        }
    }
    return $Manifest
}

function Get-PublicArtifactById {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Id
    )
    $matches = @($Manifest.artifacts | Where-Object { ([string]$_.id).Equals($Id, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one artifact '$Id', found $($matches.Count)."
    }
    return $matches[0]
}

function Assert-PublicFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$CheckAuthenticode
    )
    Assert-PublicPlainPath -Path $Path | Out-Null
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "$Label is a reparse point; refusing an ambiguous file boundary."
    }
    if ([Int64]$item.Length -ne [Int64]$Record.bytes) {
        throw "$Label size mismatch. Expected $($Record.bytes), got $($item.Length)."
    }
    $expectedHash = ([string]$Record.sha256).ToUpperInvariant()
    $actualHash = Get-Sha256 $Path
    if (-not $actualHash.Equals($expectedHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label SHA-256 mismatch. Expected $expectedHash, got $actualHash."
    }
    if ($CheckAuthenticode -and $Record.PSObject.Properties.Name -contains 'authenticode' -and $null -ne $Record.authenticode) {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if (-not ([string]$signature.Status).Equals('Valid', [StringComparison]::Ordinal) -or $null -eq $signature.SignerCertificate) {
            throw "$Label does not have a valid Authenticode signature (status: $($signature.Status))."
        }
        $contract = $Record.authenticode
        $subject = [string]$signature.SignerCertificate.Subject
        $thumbprint = ([string]$signature.SignerCertificate.Thumbprint).ToUpperInvariant()
        if (-not $subject.Equals([string]$contract.subject, [StringComparison]::Ordinal)) {
            throw "$Label signer subject mismatch. Got '$subject'."
        }
        if (-not $thumbprint.Equals(([string]$contract.thumbprint).ToUpperInvariant(), [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label signer certificate mismatch. Got '$thumbprint'."
        }
        $publisherPattern = '(^|,\s*)O=' + [Regex]::Escape([string]$contract.publisher) + '(,|$)'
        if ($subject -notmatch $publisherPattern) {
            throw "$Label signer is not the expected publisher '$($contract.publisher)'."
        }
    }
    return $Path
}

function Test-PublicFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Record,
        [switch]$CheckAuthenticode
    )
    Assert-PublicPlainPath -Path $Path | Out-Null
    try {
        Assert-PublicFileRecord -Path $Path -Record $Record -Label 'Cached file' -CheckAuthenticode:$CheckAuthenticode | Out-Null
        return $true
    } catch {
        return $false
    }
}

function New-PublicStagedPath {
    param([Parameter(Mandatory = $true)][string]$Destination)
    $directory = Split-Path -Parent $Destination
    $name = [IO.Path]::GetFileNameWithoutExtension($Destination)
    $extension = [IO.Path]::GetExtension($Destination)
    return (Join-Path $directory ($name + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N') + $extension))
}

function Get-VerifiedPublicArtifact {
    param([Parameter(Mandatory = $true)]$Artifact)

    $hash = ([string]$Artifact.sha256).ToUpperInvariant()
    $directory = Join-Path (Join-Path $script:CacheRoot 'artifacts') $hash
    $destination = Join-Path $directory ([string]$Artifact.fileName)
    Assert-PathInsideRoot -Path $destination -Root $script:CacheRoot -BoundaryName 'DLSS5 cache' | Out-Null
    Assert-PublicPlainPath -Path $destination | Out-Null
    if (Test-PublicFileRecord -Path $destination -Record $Artifact) {
        Write-Okay "verified cached source: $($Artifact.name)"
        return $destination
    }
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Remove-Item -LiteralPath $destination -Force
    }

    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $staged = New-PublicStagedPath -Destination $destination
    Assert-PathInsideRoot -Path $staged -Root $script:CacheRoot -BoundaryName 'DLSS5 cache' | Out-Null
    Write-Step "Downloading pinned source: $($Artifact.name)"
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -UseBasicParsing `
            -Uri ([string]$Artifact.url) `
            -OutFile $staged `
            -TimeoutSec 900 `
            -Headers @{ 'User-Agent' = 'EveJS-DLSS5/0.5.6' } | Out-Null
        Assert-PublicFileRecord -Path $staged -Record $Artifact -Label "Downloaded artifact '$($Artifact.id)'" | Out-Null
        Move-StagedFileIntoPlace -StagedPath $staged -Destination $destination
    } finally {
        $ProgressPreference = $oldProgress
        if (Test-Path -LiteralPath $staged -PathType Leaf) {
            Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
        }
    }
    Assert-PublicFileRecord -Path $destination -Record $Artifact -Label "Cached artifact '$($Artifact.id)'" | Out-Null
    Write-Okay "download hash verified: $hash"
    return $destination
}

function Assert-PublicZipContract {
    param(
        [Parameter(Mandatory = $true)][IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)]$Artifact
    )

    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($nameValue in @($Artifact.entries)) {
        [void]$expected.Add([string]$nameValue)
    }
    $actual = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($entry in @($Archive.Entries)) {
        $name = [string]$entry.FullName
        Assert-PublicRelativePath -Value $name -Label "Artifact '$($Artifact.id)' ZIP entry" | Out-Null
        if (-not $actual.Add($name)) {
            throw "Artifact '$($Artifact.id)' ZIP contains duplicate entry '$name'."
        }
    }
    if ($actual.Count -ne $expected.Count) {
        throw "Artifact '$($Artifact.id)' ZIP entry count mismatch. Expected $($expected.Count), got $($actual.Count)."
    }
    foreach ($name in $expected) {
        if (-not $actual.Contains($name)) {
            throw "Artifact '$($Artifact.id)' ZIP is missing expected entry '$name'."
        }
    }
}

function Expand-VerifiedPublicZipEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # Validate before touching an existing file or creating a parent directory.
    Assert-PathInsideRoot -Path $Destination -Root $script:PayloadRoot -BoundaryName 'materialized payload' | Out-Null
    Assert-PublicPlainPath -Path $Destination | Out-Null
    $checkSignature = ($File.PSObject.Properties.Name -contains 'authenticode' -and $null -ne $File.authenticode)
    if (Test-PublicFileRecord -Path $Destination -Record $File -CheckAuthenticode:$checkSignature) {
        return $Destination
    }
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        Remove-Item -LiteralPath $Destination -Force
    }
    $parent = Split-Path -Parent $Destination
    Assert-PublicPlainPath -Path $Destination | Out-Null
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staged = New-PublicStagedPath -Destination $Destination
    Assert-PathInsideRoot -Path $staged -Root $script:PayloadRoot -BoundaryName 'materialized payload' | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        Assert-PublicZipContract -Archive $archive -Artifact $Artifact
        $matches = @($archive.Entries | Where-Object { ([string]$_.FullName).Equals([string]$File.archiveEntry, [StringComparison]::Ordinal) })
        if ($matches.Count -ne 1) {
            throw "Artifact '$($Artifact.id)' must contain exactly one '$($File.archiveEntry)' entry."
        }
        if ([Int64]$matches[0].Length -ne [Int64]$File.bytes) {
            throw "Artifact '$($Artifact.id)' entry '$($File.archiveEntry)' has an unexpected size."
        }
        $input = $matches[0].Open()
        $output = New-Object IO.FileStream($staged, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $input.CopyTo($output)
        } finally {
            $output.Dispose()
            $input.Dispose()
        }
        Assert-PublicFileRecord -Path $staged -Record $File -Label "Extracted payload '$($File.id)'" -CheckAuthenticode:$checkSignature | Out-Null
        Move-StagedFileIntoPlace -StagedPath $staged -Destination $Destination
    } finally {
        $archive.Dispose()
        if (Test-Path -LiteralPath $staged -PathType Leaf) {
            Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
        }
    }
    Assert-PublicFileRecord -Path $Destination -Record $File -Label "Materialized payload '$($File.id)'" -CheckAuthenticode:$checkSignature | Out-Null
    return $Destination
}

function Assert-PublicBundledAssets {
    param([Parameter(Mandatory = $true)]$Manifest)

    foreach ($file in @($Manifest.files | Where-Object { ([string]$_.sourceKind).Equals('bundled', [StringComparison]::Ordinal) })) {
        $packagePath = Join-Path $script:IntegrationRoot ([string]$file.packagePath)
        Assert-PathInsideRoot -Path $packagePath -Root $script:IntegrationRoot -BoundaryName 'DLSS5 package' | Out-Null
        Assert-PublicFileRecord -Path $packagePath -Record $file -Label "Bundled payload '$($file.id)'" | Out-Null
    }
    Assert-PublicGeneratorAssets -Manifest $Manifest
}

function Assert-PublicGeneratorAssets {
    param([Parameter(Mandatory = $true)]$Manifest)

    # Authenticate the complete source chain even on cache hits. A new import,
    # .pyc, initializer, source stub, or reparse point must not extend this
    # narrowly reviewed generator's executable/search surface.
    $root = Join-Path $script:IntegrationRoot 'client-patches'
    Assert-PublicPlainPath -Path $root | Out-Null
    $allowed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($tool in @($Manifest.generator.tools)) {
        $toolPath = Join-Path $script:IntegrationRoot ([string]$tool.path)
        Assert-PathInsideRoot -Path $toolPath -Root $script:IntegrationRoot -BoundaryName 'DLSS5 package' | Out-Null
        Assert-PublicFileRecord -Path $toolPath -Record $tool -Label "Client guard tool '$($tool.id)'" | Out-Null
        [void]$allowed.Add(([string]$tool.path).Substring('client-patches\'.Length))
    }
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Client guard inventory contains a reparse point.'
            }
            $relative = $item.FullName.Substring($root.Length + 1)
            if ($item.PSIsContainer) {
                if ($relative -cnotin @('tools', 'templates')) {
                    throw "Unexpected client guard directory: $relative"
                }
                $pending.Enqueue($item.FullName)
            } elseif (-not $allowed.Contains($relative)) {
                throw "Unexpected client guard file: $relative"
            }
        }
    }
}

function Get-PublicGeneratorTool {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Id
    )
    $matches = @($Manifest.generator.tools | Where-Object { ([string]$_.id).Equals($Id, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one client guard tool '$Id', found $($matches.Count)."
    }
    return $matches[0]
}

function Invoke-PublicClientGuardBuilder {
    param([string]$RunnerPath, [string[]]$Arguments)

    $quotedArguments = @($Arguments | ForEach-Object {
        if ($_ -match '["\r\n]' -or $_.EndsWith('\')) {
            throw 'Client guard argument contains an unsupported quote, newline, or trailing separator.'
        }
        '"' + $_ + '"'
    })
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-PublicExtendedPath $RunnerPath
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.WorkingDirectory = Get-PublicExtendedPath (Split-Path -Parent $RunnerPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Windows did not start the pinned client guard builder.' }
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill()
            if (-not $process.WaitForExit(5000)) { throw 'The client guard builder could not be reaped after timeout.' }
            throw 'The client guard builder stage exceeded two minutes and was stopped.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Client guard builder failed with exit code $($process.ExitCode): $($stderr.Trim()) $($stdout.Trim())"
        }
    } finally {
        try {
            if ($started -and -not $process.HasExited) {
                $process.Kill()
                if (-not $process.WaitForExit(5000)) { throw 'The client guard builder could not be reaped during cleanup.' }
            }
        } finally { $process.Dispose() }
    }
}

function Initialize-EveJSPublicClientGuard {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Assert-PathInsideRoot -Path $Destination -Root $script:PayloadRoot -BoundaryName 'materialized payload' | Out-Null
    Assert-PublicPlainPath -Path $Destination | Out-Null
    Assert-PublicGeneratorAssets -Manifest $Manifest
    if (Test-PublicFileRecord -Path $Destination -Record $File) {
        return
    }
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        Remove-Item -LiteralPath $Destination -Force
    }

    $originalRecord = [pscustomobject]@{
        bytes = [Int64]$File.requiredOriginalBytes
        sha256 = [string]$File.requiredOriginalSha256
    }
    $originalPath = Join-Path $script:ClientRoot ([string]$File.destination)
    if (-not (Test-PublicFileRecord -Path $originalPath -Record $originalRecord)) {
        # A later repair may need to recreate an evicted cache while the
        # patched archive is installed. Only the journal's verified original
        # is acceptable as input; never compile from an unknown live archive.
        $active = Read-ActiveManifest
        if ($null -eq $active) {
            throw 'The client guard requires the exact unmodified build-3396210 code.ccp.'
        }
        $operations = @($active.operations | Where-Object { ([string]$_.destination).Equals([string]$File.destination, [StringComparison]::OrdinalIgnoreCase) })
        if ($operations.Count -ne 1 -or -not $operations[0].backup) {
            throw 'The client guard cannot find exactly one recorded original code.ccp backup.'
        }
        $originalPath = Join-Path (Get-BackupRoot $active) ([string]$operations[0].backup)
    }
    Assert-PublicFileRecord -Path $originalPath -Record $originalRecord -Label 'Original client code.ccp' | Out-Null

    $pythonRecord = $Manifest.generator.pythonRuntime
    $pythonPath = Join-Path $script:ClientRoot ([string]$pythonRecord.path)
    Assert-PathInsideRoot -Path $pythonPath -Root $script:ClientRoot -BoundaryName 'client' | Out-Null
    Assert-PublicFileRecord -Path $pythonPath -Record $pythonRecord -Label 'Client Python runtime' -CheckAuthenticode | Out-Null

    $runnerRecord = Get-PublicGeneratorTool -Manifest $Manifest -Id 'runner'
    $builderRecord = Get-PublicGeneratorTool -Manifest $Manifest -Id 'builder'
    $stubRecord = Get-PublicGeneratorTool -Manifest $Manifest -Id 'graphics-template'
    $startupRecord = Get-PublicGeneratorTool -Manifest $Manifest -Id 'startup-template'
    $runnerPath = Join-Path $script:IntegrationRoot ([string]$runnerRecord.path)
    $builderPath = Join-Path $script:IntegrationRoot ([string]$builderRecord.path)
    foreach ($tool in @($Manifest.generator.tools)) {
        Assert-PublicFileRecord -Path (Join-Path $script:IntegrationRoot ([string]$tool.path)) -Record $tool -Label "Client guard tool '$($tool.id)'" | Out-Null
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $intermediate = New-PublicStagedPath -Destination ($Destination + '.stage1')
    $staged = New-PublicStagedPath -Destination $Destination
    foreach ($path in @($intermediate, $staged)) {
        Assert-PathInsideRoot -Path $path -Root $script:PayloadRoot -BoundaryName 'materialized payload' | Out-Null
        Assert-PublicPlainPath -Path $path | Out-Null
    }
    $startup = $Manifest.generator.startupPatch
    $stages = @(
        [pscustomobject]@{
            source = $originalPath; sourceRecord = $originalRecord; stub = $stubRecord
            entry = $Manifest.generator.archiveEntry; embedded = $Manifest.generator.embeddedFilename
            target = $intermediate; targetRecord = $Manifest.generator.intermediateArchive
            className = 'SystemMenu'; methodName = 'ApplyGraphicsSettings'
        },
        [pscustomobject]@{
            source = $intermediate; sourceRecord = $Manifest.generator.intermediateArchive; stub = $startupRecord
            entry = $startup.archiveEntry; embedded = $startup.embeddedFilename
            target = $staged; targetRecord = $File
            className = $startup.className; methodName = $startup.methodName
        }
    )
    Write-Step 'Deriving local client source and building the exact V12 guards in two verified stages'
    try {
        foreach ($stage in $stages) {
            # Do not let a between-stage helper/template change execute before
            # the post-build checks. This also rechecks runner and builder.
            Assert-PublicGeneratorAssets -Manifest $Manifest
            Assert-PublicFileRecord -Path $stage.source -Record $stage.sourceRecord -Label 'Client guard stage input' | Out-Null
            $stubPath = Join-Path $script:IntegrationRoot ([string]$stage.stub.path)
            $arguments = @(
                (Get-PublicExtendedPath $pythonPath),
                (Get-PublicExtendedPath $builderPath),
                (Get-PublicExtendedPath $stage.source),
                (Get-PublicExtendedPath $stubPath),
                [string]$stage.entry,
                [string]$stage.embedded,
                (Get-PublicExtendedPath $stage.target),
                [string]$stage.sourceRecord.sha256,
                [string]$stage.targetRecord.sha256,
                [string]$stage.className,
                [string]$stage.methodName
            )
            Invoke-PublicClientGuardBuilder -RunnerPath $runnerPath -Arguments $arguments
            # Stage two cannot run on an unverified intermediate, even if a
            # failed/substituted process returned success without correct output.
            Assert-PublicFileRecord -Path $stage.target -Record $stage.targetRecord -Label 'Generated client guard stage output' | Out-Null
        }
        Assert-PublicFileRecord -Path $intermediate -Record $Manifest.generator.intermediateArchive -Label 'Intermediate archive after generation' | Out-Null
        Assert-PublicFileRecord -Path $originalPath -Record $originalRecord -Label 'Original client code.ccp after generation' | Out-Null
        Assert-PublicFileRecord -Path $pythonPath -Record $pythonRecord -Label 'Client Python runtime after generation' -CheckAuthenticode | Out-Null
        Assert-PublicGeneratorAssets -Manifest $Manifest
        Move-StagedFileIntoPlace -StagedPath $staged -Destination $Destination
        Write-Okay 'locally derived archive exactly matches accepted V12 runtime bytes; this new package still requires its own manual acceptance'
    } finally {
        foreach ($path in @($intermediate, $staged)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Initialize-PublicPayload {
    param([Parameter(Mandatory = $true)]$Manifest)

    Assert-PublicBundledAssets -Manifest $Manifest
    Assert-PublicPlainPath -Path $script:CacheRoot | Out-Null
    Assert-PublicPlainPath -Path $script:PayloadRoot | Out-Null
    New-Item -ItemType Directory -Path $script:CacheRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:PayloadRoot -Force | Out-Null

    $artifactPaths = @{}
    foreach ($file in @($Manifest.files | Where-Object { ([string]$_.sourceKind).Equals('archive', [StringComparison]::Ordinal) })) {
        $artifactId = [string]$file.artifactId
        if (-not $artifactPaths.ContainsKey($artifactId)) {
            $artifact = Get-PublicArtifactById -Manifest $Manifest -Id $artifactId
            $artifactPaths[$artifactId] = Get-VerifiedPublicArtifact -Artifact $artifact
        }
    }

    foreach ($file in @($Manifest.files)) {
        $destination = Join-Path $script:PayloadRoot ([string]$file.source)
        Assert-PathInsideRoot -Path $destination -Root $script:PayloadRoot -BoundaryName 'materialized payload' | Out-Null
        switch ([string]$file.sourceKind) {
            'archive' {
                $artifact = Get-PublicArtifactById -Manifest $Manifest -Id ([string]$file.artifactId)
                Expand-VerifiedPublicZipEntry `
                    -ArchivePath ([string]$artifactPaths[[string]$file.artifactId]) `
                    -Artifact $artifact `
                    -File $file `
                    -Destination $destination | Out-Null
            }
            'bundled' {
                if (-not (Test-PublicFileRecord -Path $destination -Record $file)) {
                    $packagePath = Join-Path $script:IntegrationRoot ([string]$file.packagePath)
                    $parent = Split-Path -Parent $destination
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                    Copy-FileAtomic -Source $packagePath -Destination $destination -ExpectedSha256 ([string]$file.sha256)
                }
            }
            'generated' {
                Initialize-EveJSPublicClientGuard -Manifest $Manifest -File $file -Destination $destination
            }
            default { throw "Unsupported payload sourceKind '$($file.sourceKind)'." }
        }
        $checkSignature = ($file.PSObject.Properties.Name -contains 'authenticode' -and $null -ne $file.authenticode)
        Assert-PublicFileRecord -Path $destination -Record $file -Label "Materialized payload '$($file.id)'" -CheckAuthenticode:$checkSignature | Out-Null
    }

    $reshade = @($Manifest.files | Where-Object { ([string]$_.id).Equals('reshade-evejs', [StringComparison]::Ordinal) })[0]
    $reshadePath = Join-Path $script:PayloadRoot ([string]$reshade.source)
    if (-not (Test-AsciiMarker -Path $reshadePath -Marker 'Searching for add-ons')) {
        throw 'The bundled ReShade64.dll is not the Addon build.'
    }
    return $Manifest
}
