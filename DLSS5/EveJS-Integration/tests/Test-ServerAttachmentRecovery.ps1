Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
. (Join-Path $integration 'Client-Attachments.ps1')
. (Join-Path $integration 'ReShade-Lists.ps1')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $integration 'Manage-EveJSDLSS5.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('dlss5-attachment-recovery-'+[Guid]::NewGuid().ToString('N'))
$first=Join-Path $fixture 'workspace-a\RootA'; $second=Join-Path $fixture 'workspace-b\RootB'
$script:ClientRoot=Join-Path $fixture 'physical\tq'
$script:StateRoot=Join-Path $fixture 'physical\_evejs\dlss5\install'
$script:PayloadRoot=Join-Path $script:StateRoot 'cache\payload'
$script:ActiveManifestPath=Join-Path $script:StateRoot 'active-install.json'
$script:ProfileTransaction=$null
$script:Utf8NoBom=New-Object Text.UTF8Encoding($false)
$Profile='DLSS5'
$configRelative='tools\ClientSETUP\scripts\EvEJSConfig.bat'
$original="@echo off`r`nset EVEJS_CLIENT_PATH=C:\example\tq`r`nset EVEJS_CLIENT_EXE=bin64\exefile.exe`r`nset OTHER=retain`r`n"
function Assert-Equal($Actual,$Expected) { if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'." } }
function Invoke-Verify { param($PayloadManifest,[switch]$ClientOnly) if (-not $ClientOnly) { throw 'Expected physical-only verification.' } }
function Read-PayloadManifest { return @{integrationVersion='fixture'} }
function Test-ManifestMatchesPayloadMetadata { param($Manifest,$PayloadManifest) return $true }
$script:RealTextWriter=${function:Write-TextAtomic}
$script:RealJsonWriter=${function:Write-JsonAtomic}
$script:WriteFailure=''
function Write-TextAtomic {
    param([string]$Text,[string]$Path)
    if ($script:WriteFailure -eq 'before') { $script:WriteFailure=''; throw 'injected before config write' }
    & $script:RealTextWriter -Text $Text -Path $Path
    if ($script:WriteFailure -eq 'after') { $script:WriteFailure=''; throw 'injected after config write' }
}
$script:FailDetachedCommit=$false
function Write-JsonAtomic {
    param($Value,[string]$Path)
    if ($script:FailDetachedCommit -and (Test-HasServerAttachments $Value)) {
        $entry=Get-ServerAttachment $Value $second
        if ($null -ne $entry -and $entry.status -eq 'detached') { $script:FailDetachedCommit=$false; throw 'injected detached commit failure' }
    }
    & $script:RealJsonWriter -Value $Value -Path $Path
}
try {
    foreach ($root in @($first,$second)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $root $configRelative)) -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $root 'package.json'),'{"name":"eve.js","version":"0.12.7.1"}')
        [IO.File]::WriteAllText((Join-Path $root $configRelative),$original)
    }
    New-Item -ItemType Directory -Path (Join-Path $script:StateRoot 'backups\initial'),$script:ClientRoot -Force | Out-Null
    $sentinel=Join-Path $script:ClientRoot 'payload.bin'
    [IO.File]::WriteAllText($sentinel,'physical payload stays installed')
    $script:WorkspaceRoot=Split-Path -Parent $first; Set-EveJSRootContext $first
    $backup=Join-Path $script:StateRoot 'backups\initial\config.bat'
    [IO.File]::WriteAllText($backup,$original)
    $installed=Get-UpdatedEveJSConfigText
    Write-TextAtomic $installed $script:ConfigPath
    $manifest=[pscustomobject]@{schemaVersion=5;stateScope='client';status='installed';profile='DLSS5';workspaceRoot=$script:WorkspaceRoot;evejsRoot=$first;clientRoot=$script:ClientRoot;stateRoot=$script:StateRoot;backupDirectory='backups\initial';operations=@();config=[pscustomobject]@{path=$script:ConfigPath;backup='config.bat';originalSha256=(Get-Sha256 $backup);installedSha256=(Get-Sha256 $script:ConfigPath)}}
    Write-JsonAtomic $manifest $script:ActiveManifestPath
    $script:WorkspaceRoot=Split-Path -Parent $second; Set-EveJSRootContext $second
    foreach ($failure in @('before','after')) {
        $script:WriteFailure=$failure
        $rejected=$false
        try { Invoke-EnsureServerAttachment (Read-ActiveManifestRaw) } catch { $rejected=$_.Exception.Message -match 'injected' }
        Assert-Equal $rejected $true
        Assert-Equal (Get-ServerAttachment (Read-ActiveManifestRaw) $second).status 'attaching'
        Invoke-RecoverServerAttachments
        Assert-Equal ([IO.File]::ReadAllText($script:ConfigPath)) $original
        Assert-Equal (Get-ServerAttachment (Read-ActiveManifestRaw) $second).status 'detached'
        Assert-Equal (Get-ServerAttachment (Read-ActiveManifestRaw) $first).status 'attached'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $first $configRelative))) $installed
    }
    Invoke-EnsureServerAttachment (Read-ActiveManifestRaw)
    $script:FailDetachedCommit=$true; $rejected=$false
    try { Invoke-DetachServerAttachment (Read-ActiveManifestRaw) } catch { $rejected=$_.Exception.Message -match 'injected' }
    Assert-Equal $rejected $true
    Assert-Equal (Get-ServerAttachment (Read-ActiveManifestRaw) $second).status 'detaching'
    Assert-Equal ([IO.File]::ReadAllText($script:ConfigPath)) $original
    [IO.File]::AppendAllText($script:ConfigPath,"set LATER=preserve`r`n")
    Invoke-RecoverServerAttachments
    Assert-Equal ([IO.File]::ReadAllText($script:ConfigPath)) ($original+"set LATER=preserve`r`n")
    Assert-Equal (Get-ServerAttachment (Read-ActiveManifestRaw) $second).status 'detached'
    Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'physical payload stays installed'
    'PASS: interrupted attach before/after config mutation, interrupted detach commit, exact config recovery, later edit preservation, other attachment and payload retained. Physical verification is mocked.'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup escaped temporary fixture.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
