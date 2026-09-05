[CmdletBinding()]
param(
    [string]$IntegrationRoot = ''
)

# Dependency-free Windows PowerShell 5.1 contract tests. All writes, mocked
# downloads, archives and targets are disposable fixtures. Nothing invokes the
# production manager, a real game executable, a GUI, or the network.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IntegrationRoot) { $IntegrationRoot = Split-Path -Parent $PSScriptRoot }
$sourceRoot = [IO.Path]::GetFullPath($IntegrationRoot).TrimEnd('\')
$managerPath = Join-Path $sourceRoot 'Manage-EveJSDLSS5.ps1'
$helperPath = Join-Path $sourceRoot 'Public-Payload.ps1'
$standalonePath = Join-Path $sourceRoot 'Invoke-Standalone.ps1'
$manifestPath = Join-Path $sourceRoot 'payload-manifest.json'
$script:TestCount = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)
$originalTls = [Net.ServicePointManager]::SecurityProtocol

function Get-TestFunctions {
    param([string]$Path, [string[]]$Names)
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Cannot parse test source '$Path': $($parseErrors[0].Message)"
    }
    foreach ($name in $Names) {
        $matching = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        if ($matching.Count -ne 1) { throw "Expected one function '$name' in '$Path'." }
        $matching[0].Extent.Text
    }
}

# Only named function definitions are loaded. In particular, none of the
# manager's parameter initialization, install dispatch, or restore code runs.
. ([scriptblock]::Create((Get-TestFunctions -Path $managerPath -Names @(
    'Get-Sha256', 'Get-NormalizedPath', 'Assert-PathInsideRoot', 'Move-StagedFileIntoPlace'
)) -join "`n"))
. $helperPath
. ([scriptblock]::Create((Get-TestFunctions -Path $standalonePath -Names @(
    'Resolve-StandalonePhysicalPath', 'Resolve-EveJSDlss5StandaloneTarget'
)) -join "`n"))

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ($Expected -cne $Actual) { throw "Expected '$Expected', got '$Actual'. $Because" }
}

function Assert-True {
    param([bool]$Value, [string]$Because)
    if (-not $Value) { throw $Because }
}

function Assert-Throws {
    param([scriptblock]$Body, [string]$MessageLike = '*')
    $caught = $null
    try { & $Body | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught) { throw "Expected rejection matching '$MessageLike'; action succeeded." }
    if ($caught -notlike $MessageLike) { throw "Expected rejection matching '$MessageLike'; got '$caught'." }
}

function Assert-FixturePath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:FixtureRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Test attempted to write outside its disposable fixture: $full"
    }
    return $full
}

function Write-FixtureBytes {
    param([string]$Path, [byte[]]$Bytes)
    $full = Assert-FixturePath $Path
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    [IO.File]::WriteAllBytes($full, $Bytes)
    return $full
}

function Write-FixtureText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    return (Write-FixtureBytes -Path $Path -Bytes $script:Utf8NoBom.GetBytes($Text))
}

function New-FixtureRecord {
    param([string]$Path)
    return [pscustomobject]@{ bytes = (Get-Item -LiteralPath $Path).Length; sha256 = Get-Sha256 $Path }
}

function Copy-ManifestFixture {
    return ($script:ManifestJson | ConvertFrom-Json)
}

function Write-Step { param([string]$Message) }
function Write-Okay { param([string]$Message) }

# These script-local functions deliberately shadow the real cmdlets for the
# full suite. An unexpected call cannot contact a real server or certificate
# service. Every mocked write is independently confined to FixtureRoot.
function Invoke-WebRequest {
    param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile, [int]$TimeoutSec, [hashtable]$Headers)
    $script:DownloadCount++
    $script:LastDownloadUri = $Uri
    $script:LastDownloadPath = Assert-FixturePath $OutFile
    Assert-True ($UseBasicParsing.IsPresent) 'Download must use PowerShell 5.1 basic parsing.'
    Assert-True ($TimeoutSec -gt 0) 'Download needs a bounded timeout.'
    Assert-True ($Headers.ContainsKey('User-Agent')) 'Download needs its declared user agent.'
    switch ($script:DownloadMode) {
        'success' { Write-FixtureBytes $OutFile $script:DownloadBytes | Out-Null }
        'wrong-size' { Write-FixtureBytes $OutFile ([byte[]]@(1)) | Out-Null }
        'wrong-hash' {
            $wrong = [byte[]]$script:DownloadBytes.Clone()
            $wrong[0] = $wrong[0] -bxor 255
            Write-FixtureBytes $OutFile $wrong | Out-Null
        }
        'interrupted' {
            Write-FixtureBytes $OutFile ([byte[]]@(1, 2, 3)) | Out-Null
            throw 'Injected interrupted download.'
        }
        default { throw 'Network is forbidden by this test; download was not explicitly mocked.' }
    }
}

function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    Assert-FixturePath $LiteralPath | Out-Null
    $script:SignatureChecks++
    if ($null -eq $script:SignatureResult) { throw 'Authenticode result must be explicitly mocked.' }
    return $script:SignatureResult
}

function Invoke-PublicClientGuardBuilder {
    param([string]$RunnerPath, [string[]]$Arguments)
    # Never execute the native wrapper in this suite.
    if ($script:GeneratorMode -eq 'forbidden') { throw 'Native generation is forbidden by this test.' }
    $script:GeneratorCalls++
    $source = if ($Arguments[2].StartsWith('\\?\')) { $Arguments[2].Substring(4) } else { $Arguments[2] }
    $target = if ($Arguments[6].StartsWith('\\?\')) { $Arguments[6].Substring(4) } else { $Arguments[6] }
    Assert-FixturePath $source | Out-Null
    Assert-FixturePath $target | Out-Null
    Assert-Equal (Get-Sha256 $source) $Arguments[7] 'Each mocked stage must receive the verified input hash.'
    if ($script:GeneratorCalls -eq 1) {
        Assert-Equal 'SystemMenu' $Arguments[9]
        Assert-Equal 'ApplyGraphicsSettings' $Arguments[10]
        $bytes = if ($script:GeneratorMode -eq 'bad-stage1') { [byte[]]@(0) } else { $script:Stage1Bytes }
    } else {
        Assert-Equal 2 $script:GeneratorCalls
        Assert-Equal 'DeviceMgr' $Arguments[9]
        Assert-Equal 'CreateDevice' $Arguments[10]
        $bytes = if ($script:GeneratorMode -eq 'bad-stage2') { [byte[]]@(0) } else { $script:Stage2Bytes }
    }
    Write-FixtureBytes $target $bytes | Out-Null
    if ($script:GeneratorCalls -eq 2) {
        if ($script:GeneratorMode -eq 'throw-stage2') { throw 'Injected stage-two failure.' }
        if ($script:GeneratorMode -eq 'tamper-startup') { Write-FixtureBytes $script:StartupToolPath ([byte[]]@(0)) | Out-Null }
        if ($script:GeneratorMode -eq 'tamper-intermediate') { Write-FixtureBytes $source ([byte[]]@(0)) | Out-Null }
    }
}

function New-GenerationFixture {
    $m = Copy-ManifestFixture
    $script:IntegrationRoot = Join-Path $script:CaseRoot 'package'
    $script:ClientRoot = Join-Path $script:CaseRoot 'client'
    $script:GeneratorCalls = 0
    $script:GeneratorMode = 'success'
    $script:Stage1Bytes = $script:Utf8NoBom.GetBytes('Harmless stage-one archive fixture.')
    $script:Stage2Bytes = $script:Utf8NoBom.GetBytes('Harmless final two-stage archive fixture.')
    $original = Write-FixtureText (Join-Path $script:ClientRoot 'code.ccp') 'Harmless original archive fixture.'
    $originalRecord = New-FixtureRecord $original
    $stage1 = Write-FixtureBytes (Join-Path $script:CaseRoot 'expected-stage1.bin') $script:Stage1Bytes
    $stage2 = Write-FixtureBytes (Join-Path $script:CaseRoot 'expected-stage2.bin') $script:Stage2Bytes
    $m.generator.intermediateArchive = New-FixtureRecord $stage1
    $python = Write-FixtureText (Join-Path $script:ClientRoot $m.generator.pythonRuntime.path) 'Not a Python runtime.'
    $pythonRecord = New-FixtureRecord $python
    $m.generator.pythonRuntime = [pscustomobject]@{path='bin64\python27.dll';bytes=$pythonRecord.bytes;sha256=$pythonRecord.sha256}
    foreach ($tool in @($m.generator.tools)) {
        $toolPath = Write-FixtureText (Join-Path $script:IntegrationRoot $tool.path) ('Harmless tool ' + $tool.id)
        $record = New-FixtureRecord $toolPath
        $tool.bytes = $record.bytes; $tool.sha256 = $record.sha256
        if ($tool.id -eq 'startup-template') { $script:StartupToolPath = $toolPath }
    }
    $file = $m.files[4]
    $finalRecord = New-FixtureRecord $stage2
    $file.bytes = $finalRecord.bytes; $file.sha256 = $finalRecord.sha256
    $file.requiredOriginalBytes = $originalRecord.bytes; $file.requiredOriginalSha256 = $originalRecord.sha256
    return [pscustomobject]@{manifest=$m;file=$file;destination=(Join-Path $script:PayloadRoot 'fixture\code.ccp')}
}

function New-DownloadFixture {
    $source = Write-FixtureText (Join-Path $script:CaseRoot 'download-source.bin') 'Pinned fixture bytes. Not an executable.'
    $record = New-FixtureRecord $source
    $script:DownloadBytes = [IO.File]::ReadAllBytes($source)
    return [pscustomobject]@{
        id = 'fixture-artifact'
        name = 'Fixture artifact'
        url = 'https://example.invalid/never-contacted/fixture.zip'
        fileName = 'fixture.zip'
        bytes = $record.bytes
        sha256 = $record.sha256
        entries = @('payload.dll')
    }
}

function Get-FixtureArtifactDestination {
    param($Artifact)
    return (Join-Path (Join-Path (Join-Path $script:CacheRoot 'artifacts') $Artifact.sha256) $Artifact.fileName)
}

function Assert-NoPartials {
    $partials = @(Get-ChildItem -LiteralPath $script:CaseRoot -File -Recurse -Force | Where-Object {
        $_.Name -like '*.partial.*' -or $_.Name -like '*.evejs-dlss5.previous.*'
    })
    Assert-Equal 0 $partials.Count 'Rejected/committed data must not leave partial files behind.'
}

function New-FixtureZip {
    param([string[]]$Entries, [byte[]]$Bytes = [byte[]]@(70, 73, 88, 84, 85, 82, 69))
    $zipPath = Assert-FixturePath (Join-Path $script:CaseRoot ([Guid]::NewGuid().ToString('N') + '.zip'))
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries) {
            $entry = $archive.CreateEntry($name)
            $stream = $entry.Open()
            try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    return $zipPath
}

function Assert-ZipFixture {
    param([string]$Path, [string[]]$ExpectedEntries)
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        Assert-PublicZipContract -Archive $archive -Artifact ([pscustomobject]@{
            id = 'fixture'; entries = $ExpectedEntries
        })
    } finally { $archive.Dispose() }
}

function New-ExtractionFixture {
    $bytesPath = Write-FixtureText (Join-Path $script:CaseRoot 'payload-source.bin') 'Harmless extracted fixture bytes.'
    $record = New-FixtureRecord $bytesPath
    return [pscustomobject]@{
        path = New-FixtureZip -Entries @('payload.dll') -Bytes ([IO.File]::ReadAllBytes($bytesPath))
        artifact = [pscustomobject]@{ id = 'fixture'; entries = @('payload.dll') }
        file = [pscustomobject]@{ id = 'fixture-file'; archiveEntry = 'payload.dll'; bytes = $record.bytes; sha256 = $record.sha256 }
        destination = Join-Path $script:PayloadRoot 'fixture\payload.dll'
    }
}

function New-SignedFixture {
    $path = Write-FixtureText (Join-Path $script:CaseRoot 'signed-fixture.dll') 'This is NOT a real DLL or signed binary.'
    $record = New-FixtureRecord $path
    $record | Add-Member -NotePropertyName authenticode -NotePropertyValue ([pscustomobject]@{
        status = 'Valid'; publisher = 'NVIDIA Corporation'
        subject = 'CN=Fixture signer, O=NVIDIA Corporation, C=US'
        thumbprint = ('1' * 40)
    })
    $script:SignatureResult = [pscustomobject]@{
        Status = 'Valid'
        SignerCertificate = [pscustomobject]@{ Subject = $record.authenticode.subject; Thumbprint = $record.authenticode.thumbprint }
    }
    return [pscustomobject]@{ path = $path; record = $record }
}

function New-StandaloneFixture {
    param([string]$Version)
    $root = Join-Path $script:CaseRoot ('EveJS-' + $Version)
    $client = Join-Path $script:CaseRoot 'client\tq'
    $package = Join-Path $root 'mods\DLSS5'
    New-Item -ItemType Directory -Path $package -Force | Out-Null
    Write-FixtureText (Join-Path $root 'package.json') ('{"name":"eve.js","version":"' + $Version + '"}') | Out-Null
    $config = Join-Path $root 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
    Write-FixtureText $config ('set "EVEJS_CLIENT_PATH=' + $client + '"' + "`r`n" + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"' + "`r`n") | Out-Null
    Write-FixtureText (Join-Path $client 'start.ini') 'build=3396210' | Out-Null
    Write-FixtureText (Join-Path $client 'bin64\exefile.exe') 'INERT TEST FIXTURE - NEVER EXECUTE' | Out-Null
    return [pscustomobject]@{ root = $root; client = $client; package = $package; config = $config }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    $script:TestCount++
    $script:CaseRoot = Join-Path $script:FixtureRoot ('case-' + $script:TestCount.ToString('000'))
    New-Item -ItemType Directory -Path $script:CaseRoot | Out-Null
    $script:CacheRoot = Join-Path $script:CaseRoot 'state\cache'
    $script:PayloadRoot = Join-Path $script:CacheRoot 'payload'
    $script:DownloadMode = 'forbidden'
    $script:DownloadCount = 0
    $script:DownloadBytes = [byte[]]@()
    $script:LastDownloadUri = ''
    $script:LastDownloadPath = ''
    $script:SignatureResult = $null
    $script:SignatureChecks = 0
    $script:GeneratorMode = 'forbidden'
    try {
        & $Body
        Write-Host ('PASS ' + $Name) -ForegroundColor Green
    } catch {
        $message = $Name + ': ' + $_.Exception.Message
        $script:Failures.Add($message)
        Write-Host ('FAIL ' + $message) -ForegroundColor Red
    }
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$script:FixtureRoot = Join-Path $tempRoot ('evejs-dlss5-public-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:FixtureRoot | Out-Null
$markerPath = Write-FixtureText (Join-Path $script:FixtureRoot '.fixture-owner') 'Test-PublicBootstrap.ps1'
$script:ManifestJson = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)

try {
    Invoke-Test 'Reviewed manifest passes contract' {
        Assert-PublicPayloadManifestContract (Copy-ManifestFixture) | Out-Null
    }
    Invoke-Test 'Reject unsupported schema' {
        $m = Copy-ManifestFixture; $m.schemaVersion = 999
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*schemaVersion*'
    }
    Invoke-Test 'Reject unknown manifest property' {
        $m = Copy-ManifestFixture; $m | Add-Member -NotePropertyName executeAfterDownload -NotePropertyValue 'anything'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*unsupported property*'
    }
    Invoke-Test 'Reject missing manifest files' {
        $m = Copy-ManifestFixture; $m.PSObject.Properties.Remove('files')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*missing required property*'
    }
    Invoke-Test 'Reject artifact count change' {
        $m = Copy-ManifestFixture; $m.artifacts = @($m.artifacts[0])
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*exactly*download artifacts*'
    }
    Invoke-Test 'Reject duplicate artifact' {
        $m = Copy-ManifestFixture; $m.artifacts[1] = $m.artifacts[0]
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*duplicate download artifact*'
    }
    Invoke-Test 'Reject unpinned artifact URL' {
        $m = Copy-ManifestFixture; $m.artifacts[0].url = 'https://example.invalid/other.zip'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*URL mismatch*'
    }
    Invoke-Test 'Reject invalid artifact hash' {
        $m = Copy-ManifestFixture; $m.artifacts[0].sha256 = 'not-a-hash'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*64-character SHA-256*'
    }
    Invoke-Test 'Reject nonpositive artifact size' {
        $m = Copy-ManifestFixture; $m.artifacts[0].bytes = 0
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*invalid byte count*'
    }
    Invoke-Test 'Reject artifact path traversal' {
        $m = Copy-ManifestFixture; $m.artifacts[0].fileName = '..\outside.zip'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*unsafe path segment*'
    }
    Invoke-Test 'Reject duplicate declared ZIP entry' {
        $m = Copy-ManifestFixture; $m.artifacts[0].entries = @('same.dll', 'same.dll')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*duplicate expected ZIP entry*'
    }
    Invoke-Test 'Reject declared ZIP traversal' {
        $m = Copy-ManifestFixture; $m.artifacts[0].entries = @('../outside.dll')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*unsafe path segment*'
    }
    Invoke-Test 'Reject duplicate client destination' {
        $m = Copy-ManifestFixture; $m.files[1].destination = $m.files[0].destination
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*duplicate destination*'
    }
    Invoke-Test 'Reject unreviewed client destination' {
        $m = Copy-ManifestFixture; $m.files[0].destination = 'bin64\exefile.exe'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*Payload contract mismatch*'
    }
    Invoke-Test 'Reject generated payload original hash change to invalid hash' {
        $m = Copy-ManifestFixture; $m.files[4].requiredOriginalSha256 = 'wrong'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*64-character SHA-256*'
    }
    Invoke-Test 'Reject absent DLSSNR signer contract' {
        $m = Copy-ManifestFixture; $m.files[0].PSObject.Properties.Remove('authenticode')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*authenticode*'
    }
    Invoke-Test 'Reject absent Streamline signer contract' {
        $m = Copy-ManifestFixture; $m.files[1].PSObject.Properties.Remove('authenticode')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*authenticode*'
    }
    Invoke-Test 'Reject null NVIDIA signer contract' {
        $m = Copy-ManifestFixture; $m.files[0].authenticode = $null
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*authenticode*'
    }
    Invoke-Test 'Reject unsupported NVIDIA publisher' {
        $m = Copy-ManifestFixture; $m.files[0].authenticode.publisher = 'Unreviewed Publisher'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*publisher*'
    }
    Invoke-Test 'Reject unreviewed generator tool' {
        $m = Copy-ManifestFixture; $m.generator.tools[0].path = 'downloaded\anything.exe'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*unreviewed tool path*'
    }
    Invoke-Test 'Reject duplicate generator tool' {
        $m = Copy-ManifestFixture; $m.generator.tools[1] = $m.generator.tools[0]
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*duplicate tool*'
    }
    foreach ($field in @('archiveEntry', 'embeddedFilename', 'className', 'methodName')) {
        Invoke-Test ("Reject changed startup target " + $field) {
            $m = Copy-ManifestFixture; $m.generator.startupPatch.$field = 'unreviewed'
            Assert-Throws { Assert-PublicPayloadManifestContract $m } '*startup patch target*'
        }
    }
    foreach ($field in @('bytes', 'sha256')) {
        Invoke-Test ("Reject changed intermediate " + $field) {
            $m = Copy-ManifestFixture
            if ($field -eq 'bytes') { $m.generator.intermediateArchive.bytes++ }
            else { $m.generator.intermediateArchive.sha256 = '0' * 64 }
            Assert-Throws { Assert-PublicPayloadManifestContract $m } '*intermediate archive*'
        }
    }
    Invoke-Test 'Reject missing startup stage' {
        $m = Copy-ManifestFixture; $m.generator.PSObject.Properties.Remove('startupPatch')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*missing required property*'
    }
    Invoke-Test 'Reject extra startup stage property' {
        $m = Copy-ManifestFixture; $m.generator.startupPatch | Add-Member -NotePropertyName command -NotePropertyValue 'anything'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*unsupported property*'
    }
    Invoke-Test 'Reject modified startup PYC identity' {
        $m = Copy-ManifestFixture; $m.generator.startupPatch.patchedPycSha256 = '0' * 64
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*startup PYC contract*'
    }
    Invoke-Test 'Reject missing startup source tool' {
        $m = Copy-ManifestFixture; $m.generator.tools = @($m.generator.tools | Where-Object {$_.id -ne 'startup-template'})
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*exactly*reviewed tools*'
    }
    Invoke-Test 'Reject Python runtime outside client allowlist' {
        $m = Copy-ManifestFixture; $m.generator.pythonRuntime.path = '..\python27.dll'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*runtime path*'
    }
    Invoke-Test 'Reject missing Python runtime signature contract' {
        $m = Copy-ManifestFixture; $m.generator.pythonRuntime.PSObject.Properties.Remove('authenticode')
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*missing required property*'
    }
    Invoke-Test 'Reject unsupported Python publisher' {
        $m = Copy-ManifestFixture; $m.generator.pythonRuntime.authenticode.publisher = 'Unknown'
        Assert-Throws { Assert-PublicPayloadManifestContract $m } '*CCP publisher*'
    }

    Invoke-Test 'Two-stage generation verifies both stages then publishes only final' {
        $g = New-GenerationFixture
        Initialize-EveJSPublicClientGuard -Manifest $g.manifest -File $g.file -Destination $g.destination
        Assert-Equal 2 $script:GeneratorCalls
        Assert-Equal $g.file.sha256 (Get-Sha256 $g.destination)
        Assert-NoPartials
    }
    foreach ($mode in @('bad-stage1', 'bad-stage2', 'throw-stage2', 'tamper-startup', 'tamper-intermediate')) {
        Invoke-Test ("Failed generation cleans both stages: " + $mode) {
            $g = New-GenerationFixture; $script:GeneratorMode = $mode
            Assert-Throws { Initialize-EveJSPublicClientGuard -Manifest $g.manifest -File $g.file -Destination $g.destination }
            Assert-Equal $(if ($mode -eq 'bad-stage1') {1} else {2}) $script:GeneratorCalls
            Assert-True (-not (Test-Path -LiteralPath $g.destination)) 'No invalid final payload may be published.'
            Assert-NoPartials
        }
    }
    Invoke-Test 'Tampered startup source is rejected before any builder invocation' {
        $g = New-GenerationFixture
        Write-FixtureBytes $script:StartupToolPath ([byte[]]@(0)) | Out-Null
        Assert-Throws { Initialize-EveJSPublicClientGuard -Manifest $g.manifest -File $g.file -Destination $g.destination } '*size mismatch*'
        Assert-Equal 0 $script:GeneratorCalls
        Assert-True (-not (Test-Path -LiteralPath $g.destination)) 'No payload may be published.'
        Assert-NoPartials
    }
    Invoke-Test 'Verified final generation cache skips both builders' {
        $g = New-GenerationFixture
        Write-FixtureBytes $g.destination $script:Stage2Bytes | Out-Null
        Initialize-EveJSPublicClientGuard -Manifest $g.manifest -File $g.file -Destination $g.destination
        Assert-Equal 0 $script:GeneratorCalls
    }

    Invoke-Test 'File verification accepts exact bytes/hash' {
        $a = New-DownloadFixture
        Assert-PublicFileRecord -Path (Join-Path $script:CaseRoot 'download-source.bin') -Record $a -Label 'Fixture' | Out-Null
    }
    Invoke-Test 'File verification rejects wrong size' {
        $a = New-DownloadFixture; $a.bytes++
        Assert-Throws { Assert-PublicFileRecord -Path (Join-Path $script:CaseRoot 'download-source.bin') -Record $a -Label 'Fixture' } '*size mismatch*'
    }
    Invoke-Test 'File verification rejects wrong hash' {
        $a = New-DownloadFixture; $a.sha256 = '0' * 64
        Assert-Throws { Assert-PublicFileRecord -Path (Join-Path $script:CaseRoot 'download-source.bin') -Record $a -Label 'Fixture' } '*SHA-256 mismatch*'
    }
    Invoke-Test 'Extended path prefixes an absolute drive path exactly once' {
        $normal = Join-Path $script:CaseRoot 'long\fixture.bin'
        Assert-Equal ('\\?\' + [IO.Path]::GetFullPath($normal)) (Get-PublicExtendedPath $normal)
    }
    Invoke-Test 'Extended path maps UNC to extended UNC syntax' {
        $unc = '\\fixture-server\fixture-share\long\fixture.bin'
        Assert-Equal '\\?\UNC\fixture-server\fixture-share\long\fixture.bin' (Get-PublicExtendedPath $unc)
    }
    Invoke-Test 'Mocked verified download atomically populates cache' {
        $a = New-DownloadFixture; $script:DownloadMode = 'success'
        $path = Get-VerifiedPublicArtifact $a
        Assert-Equal (Get-FixtureArtifactDestination $a) $path
        Assert-Equal 1 $script:DownloadCount
        Assert-Equal $a.url $script:LastDownloadUri
        Assert-Equal $a.sha256 (Get-Sha256 $path)
        Assert-NoPartials
    }
    Invoke-Test 'Verified cache hit performs no network request' {
        $a = New-DownloadFixture; $script:DownloadMode = 'success'
        $path = Get-VerifiedPublicArtifact $a
        $script:DownloadMode = 'forbidden'
        Assert-Equal $path (Get-VerifiedPublicArtifact $a)
        Assert-Equal 1 $script:DownloadCount
        Assert-NoPartials
    }
    Invoke-Test 'Corrupt cache is reverified and replaced' {
        $a = New-DownloadFixture; $script:DownloadMode = 'success'
        $path = Get-VerifiedPublicArtifact $a
        Write-FixtureBytes $path ([byte[]]@(1, 2, 3)) | Out-Null
        Get-VerifiedPublicArtifact $a | Out-Null
        Assert-Equal 2 $script:DownloadCount
        Assert-Equal $a.sha256 (Get-Sha256 $path)
        Assert-NoPartials
    }
    foreach ($mode in @('wrong-size', 'wrong-hash', 'interrupted')) {
        Invoke-Test ("Download '$mode' rejects and cleans staging") {
            $a = New-DownloadFixture; $script:DownloadMode = $mode
            $expected = switch ($mode) { 'wrong-size' { '*size mismatch*' }; 'wrong-hash' { '*SHA-256 mismatch*' }; default { '*Injected interrupted*' } }
            Assert-Throws { Get-VerifiedPublicArtifact $a } $expected
            Assert-True (-not (Test-Path -LiteralPath (Get-FixtureArtifactDestination $a))) 'Failed download must not become a cache entry.'
            Assert-NoPartials
        }
    }
    Invoke-Test 'No-network cache miss fails without installed output' {
        $a = New-DownloadFixture
        Assert-Throws { Get-VerifiedPublicArtifact $a } '*Network is forbidden*'
        Assert-True (-not (Test-Path -LiteralPath (Get-FixtureArtifactDestination $a))) 'Cache miss must not publish output.'
        Assert-NoPartials
    }
    Invoke-Test 'Download restores caller progress preference on failure' {
        $a = New-DownloadFixture; $script:DownloadMode = 'interrupted'
        $before = $ProgressPreference
        Assert-Throws { Get-VerifiedPublicArtifact $a } '*Injected interrupted*'
        Assert-Equal $before $ProgressPreference
    }

    Invoke-Test 'ZIP contract accepts exact entry set' {
        Assert-ZipFixture (New-FixtureZip @('one.dll', 'two.dll')) @('one.dll', 'two.dll')
    }
    Invoke-Test 'ZIP contract rejects duplicate physical entries' {
        Assert-Throws { Assert-ZipFixture (New-FixtureZip @('one.dll', 'one.dll')) @('one.dll') } '*duplicate entry*'
    }
    Invoke-Test 'ZIP contract rejects missing entry' {
        Assert-Throws { Assert-ZipFixture (New-FixtureZip @('other.dll')) @('one.dll') } '*missing expected entry*'
    }
    Invoke-Test 'ZIP contract rejects additional entry' {
        Assert-Throws { Assert-ZipFixture (New-FixtureZip @('one.dll', 'extra.dll')) @('one.dll') } '*entry count mismatch*'
    }
    foreach ($badEntry in @('../escape.dll', 'nested/../../escape.dll', 'C:\escape.dll', '/escape.dll', 'folder\\escape.dll', 'payload.dll:alternate')) {
        Invoke-Test ("ZIP contract rejects unsafe entry '$badEntry'") {
            Assert-Throws { Assert-ZipFixture (New-FixtureZip @($badEntry)) @('one.dll') }
        }
    }
    Invoke-Test 'Verified ZIP entry materializes exact payload' {
        $x = New-ExtractionFixture
        Assert-Equal $x.destination (Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $x.destination)
        Assert-Equal $x.file.sha256 (Get-Sha256 $x.destination)
        Assert-NoPartials
    }
    Invoke-Test 'ZIP extraction rejects entry length before publishing' {
        $x = New-ExtractionFixture; $x.file.bytes++
        Assert-Throws { Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $x.destination } '*unexpected size*'
        Assert-True (-not (Test-Path -LiteralPath $x.destination)) 'Wrong entry length must not publish payload.'
        Assert-NoPartials
    }
    Invoke-Test 'ZIP extraction rejects entry hash and removes partial' {
        $x = New-ExtractionFixture; $x.file.sha256 = '0' * 64
        Assert-Throws { Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $x.destination } '*SHA-256 mismatch*'
        Assert-True (-not (Test-Path -LiteralPath $x.destination)) 'Wrong entry hash must not publish payload.'
        Assert-NoPartials
    }
    Invoke-Test 'ZIP extraction refuses a destination outside payload boundary' {
        $x = New-ExtractionFixture
        $outside = Join-Path $script:CaseRoot 'outside\payload.dll'
        Assert-Throws { Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $outside } '*outside the authorized materialized payload boundary*'
        Assert-True (-not (Test-Path -LiteralPath $outside)) 'Out-of-boundary payload must not be created.'
        Assert-True (-not (Test-Path -LiteralPath (Split-Path -Parent $outside))) 'Boundary rejection must happen before creating an outside directory.'
    }
    Invoke-Test 'ZIP extraction preserves preexisting out-of-boundary file' {
        $x = New-ExtractionFixture
        $outside = Write-FixtureText (Join-Path $script:CaseRoot 'outside\payload.dll') 'Must survive a rejected destination.'
        $before = Get-Sha256 $outside
        Assert-Throws { Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $outside } '*outside the authorized materialized payload boundary*'
        Assert-True (Test-Path -LiteralPath $outside -PathType Leaf) 'Boundary rejection must not delete an outside file.'
        Assert-Equal $before (Get-Sha256 $outside)
    }
    Invoke-Test 'Client guard rejects outside destination before creating anything' {
        $m = Copy-ManifestFixture
        $outside = Join-Path $script:CaseRoot 'outside\code.ccp'
        Assert-Throws { Initialize-EveJSPublicClientGuard -Manifest $m -File $m.files[4] -Destination $outside } '*outside the authorized materialized payload boundary*'
        Assert-True (-not (Test-Path -LiteralPath (Split-Path -Parent $outside))) 'Guard boundary rejection must not create an outside directory.'
    }
    Invoke-Test 'Client guard preserves preexisting out-of-boundary file' {
        $m = Copy-ManifestFixture
        $outside = Write-FixtureText (Join-Path $script:CaseRoot 'outside\code.ccp') 'Preserve outside guard target.'
        $before = Get-Sha256 $outside
        Assert-Throws { Initialize-EveJSPublicClientGuard -Manifest $m -File $m.files[4] -Destination $outside } '*outside the authorized materialized payload boundary*'
        Assert-True (Test-Path -LiteralPath $outside -PathType Leaf) 'Guard boundary rejection must not delete an outside file.'
        Assert-Equal $before (Get-Sha256 $outside)
    }

    Invoke-Test 'Authenticode accepts exact mocked status/subject/thumbprint/publisher' {
        $s = New-SignedFixture
        Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode | Out-Null
        Assert-Equal 1 $script:SignatureChecks
    }
    Invoke-Test 'Authenticode rejects unsigned payload' {
        $s = New-SignedFixture; $script:SignatureResult.Status = 'NotSigned'
        Assert-Throws { Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode } '*valid Authenticode signature*'
    }
    Invoke-Test 'Authenticode rejects absent signer' {
        $s = New-SignedFixture; $script:SignatureResult.SignerCertificate = $null
        Assert-Throws { Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode } '*valid Authenticode signature*'
    }
    Invoke-Test 'Authenticode rejects wrong signer subject' {
        $s = New-SignedFixture; $script:SignatureResult.SignerCertificate.Subject = 'CN=Wrong, O=NVIDIA Corporation, C=US'
        Assert-Throws { Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode } '*signer subject mismatch*'
    }
    Invoke-Test 'Authenticode rejects wrong signer thumbprint' {
        $s = New-SignedFixture; $script:SignatureResult.SignerCertificate.Thumbprint = '2' * 40
        Assert-Throws { Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode } '*signer certificate mismatch*'
    }
    Invoke-Test 'Authenticode rejects non-publisher organization even with matching subject' {
        $s = New-SignedFixture
        $s.record.authenticode.subject = 'CN=NVIDIA Corporation, O=Different Company, C=US'
        $script:SignatureResult.SignerCertificate.Subject = $s.record.authenticode.subject
        Assert-Throws { Assert-PublicFileRecord -Path $s.path -Record $s.record -Label 'Signed fixture' -CheckAuthenticode } '*not the expected publisher*'
    }
    Invoke-Test 'ZIP extraction enforces signer before publishing' {
        $x = New-ExtractionFixture; $s = New-SignedFixture
        $x.file | Add-Member -NotePropertyName authenticode -NotePropertyValue $s.record.authenticode
        $script:SignatureResult.Status = 'HashMismatch'
        Assert-Throws { Expand-VerifiedPublicZipEntry -ArchivePath $x.path -Artifact $x.artifact -File $x.file -Destination $x.destination } '*valid Authenticode signature*'
        Assert-True (-not (Test-Path -LiteralPath $x.destination)) 'Bad signature must not publish extracted payload.'
        Assert-NoPartials
    }

    foreach ($version in @('0.12.6', '0.12.7', '0.12.7.1')) {
        Invoke-Test ("Standalone $version resolves Mod layout to shared external state") {
            $f = New-StandaloneFixture $version
            $target = Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt
            Assert-Equal $f.root $target.EveJSRootPath
            Assert-Equal $f.client $target.ClientRoot
            Assert-Equal (Split-Path -Parent $f.root) $target.WorkspaceRoot
            Assert-Equal (Join-Path (Split-Path -Parent $f.client) '_evejs\dlss5\install') $target.StateRootPath
            Assert-True (-not (Test-Path -LiteralPath $target.StateRootPath)) 'Resolve must not create install state.'
        }
        Invoke-Test ("Standalone $version explicit install uses same state as Mod layout") {
            $f = New-StandaloneFixture $version
            $outsidePackage = Join-Path $script:CaseRoot 'downloads\DLSS5'
            $standalone = Resolve-EveJSDlss5StandaloneTarget -PackageRoot $outsidePackage -SelectedEveJSRoot $f.root -SelectedClientRoot $f.client -NoPrompt
            $mod = Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt
            Assert-Equal $mod.StateRootPath $standalone.StateRootPath
            Assert-Equal $mod.ClientRoot $standalone.ClientRoot
        }
    }
    Invoke-Test 'Standalone expands only explicit EVEJS_REPO_ROOT token as data' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText $f.config ('set "EVEJS_CLIENT_PATH=%EVEJS_REPO_ROOT%\..\client\tq"' + "`r`n" + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"') | Out-Null
        $target = Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt
        Assert-Equal $f.client $target.ClientRoot
    }
    Invoke-Test 'Standalone reads configuration without executing batch commands' {
        $f = New-StandaloneFixture '0.12.7'
        $sentinel = Join-Path $script:CaseRoot 'BATCH-WAS-EXECUTED.txt'
        Write-FixtureText $f.config ('set "EVEJS_CLIENT_PATH=' + $f.client + '"' + "`r`n" + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"' + "`r`n" + 'echo DO NOT EXECUTE > "' + $sentinel + '"') | Out-Null
        Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt | Out-Null
        Assert-True (-not (Test-Path -LiteralPath $sentinel)) 'Batch configuration must never execute.'
    }
    Invoke-Test 'Standalone rejects malformed EveJS version' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText (Join-Path $f.root 'package.json') '{"name":"eve.js","version":"0.12/8"}' | Out-Null
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt } '*sane version*'
    }
    Invoke-Test 'Standalone rejects unrelated package' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText (Join-Path $f.root 'package.json') '{"name":"unrelated","version":"0.12.7"}' | Out-Null
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt } '*eve.js package*'
    }
    Invoke-Test 'Standalone rejects ambiguous client settings' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText $f.config ((('set "EVEJS_CLIENT_PATH=' + $f.client + '"' + "`r`n") * 2) + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"') | Out-Null
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt } '*exactly one quoted*'
    }
    Invoke-Test 'Standalone rejects unresolved batch variable' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText $f.config ('set "EVEJS_CLIENT_PATH=%UNREVIEWED_LOCATION%\tq"' + "`r`n" + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"') | Out-Null
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -NoPrompt } '*unresolved batch variable*'
    }
    Invoke-Test 'Standalone explicit client overrides ambiguous stored setting' {
        $f = New-StandaloneFixture '0.12.7'
        Write-FixtureText $f.config ('set "EVEJS_CLIENT_PATH=%UNREVIEWED_LOCATION%\tq"' + "`r`n" + 'set "EVEJS_CLIENT_EXE=bin64\exefile.exe"') | Out-Null
        $target = Resolve-EveJSDlss5StandaloneTarget -PackageRoot $f.package -SelectedClientRoot $f.client -NoPrompt
        Assert-Equal $f.client $target.ClientRoot
    }
    Invoke-Test 'Standalone refuses guessing a root in noninteractive mode' {
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot (Join-Path $script:CaseRoot 'downloads\DLSS5') -NoPrompt } '*Could not infer the EveJS root*'
    }
    Invoke-Test 'Standalone rejects relative selected root' {
        Assert-Throws { Resolve-EveJSDlss5StandaloneTarget -PackageRoot $script:CaseRoot -SelectedEveJSRoot 'relative' -NoPrompt } '*absolute folder path*'
    }

    Write-Host ''
    Write-Host ('Public bootstrap: {0} passed, {1} failed, {2} total.' -f ($script:TestCount - $script:Failures.Count), $script:Failures.Count, $script:TestCount)
    if ($script:Failures.Count -gt 0) {
        throw ($script:Failures -join "`n")
    }
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalTls
    # Resolve and verify the exact newly-created target before recursive cleanup.
    # Refuse to delete if the marker or root identity has changed.
    $resolved = [IO.Path]::GetFullPath($script:FixtureRoot).TrimEnd('\')
    if (-not $resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^evejs-dlss5-public-tests-[0-9a-f]{32}$' -or
        -not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
        [IO.File]::ReadAllText($markerPath) -cne 'Test-PublicBootstrap.ps1') {
        throw "Refusing cleanup because disposable fixture identity changed: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
