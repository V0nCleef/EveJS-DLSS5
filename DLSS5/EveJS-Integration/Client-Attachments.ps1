# Server launch settings have independent lifetimes inside the physical-client
# journal. The manager's client mutex covers these transitions and payload work.
function Invoke-InRecordedServerContext {
    param([string]$Root,[string]$Workspace,[scriptblock]$Body)
    $previousRoot=$script:EveJSRoot; $previousWorkspace=$script:WorkspaceRoot
    try {
        $script:WorkspaceRoot=Get-NormalizedPath $Workspace
        Set-EveJSRootContext $Root
        & $Body
    } finally {
        $script:WorkspaceRoot=$previousWorkspace
        Set-EveJSRootContext $previousRoot
    }
}

function Test-HasServerAttachments {
    param($Manifest)
    return ($null -ne $Manifest -and $Manifest.PSObject.Properties.Name -contains 'serverAttachments')
}

function Get-ServerAttachment {
    param($Manifest,[string]$Root)
    if (-not (Test-HasServerAttachments $Manifest)) { return $null }
    $normalized=Get-NormalizedPath $Root
    $matches=@($Manifest.serverAttachments | Where-Object { ([string]$_.root).Equals($normalized,[StringComparison]::OrdinalIgnoreCase) })
    if ($matches.Count -gt 1) { throw 'Duplicate server attachment identity.' }
    if ($matches.Count) { return $matches[0] }
    return $null
}

function Assert-ServerAttachments {
    param($Manifest)
    Invoke-InRecordedServerContext ([string]$Manifest.evejsRoot) ([string]$Manifest.workspaceRoot) { Assert-ManifestTargets $Manifest }
    if (-not (Test-HasServerAttachments $Manifest)) { return }
    if (@($Manifest.serverAttachments).Count -gt 128) { throw 'Too many server attachments in the client journal.' }
    $roots=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($attachment in @($Manifest.serverAttachments)) {
        $root=Get-NormalizedPath ([string]$attachment.root)
        if (-not [IO.Path]::IsPathRooted([string]$attachment.root) -or -not $roots.Add($root) -or
            $attachment.status -notin @('attaching','attached','detaching','detached')) { throw 'Invalid server attachment identity or state.' }
        $expected=Join-Path $root 'tools\ClientSETUP\scripts\EvEJSConfig.bat'
        if (-not (Get-NormalizedPath ([string]$attachment.config.path)).Equals((Get-NormalizedPath $expected),[StringComparison]::OrdinalIgnoreCase) -or
            [string]$attachment.config.originalSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid server attachment configuration receipt.' }
        $backup=Assert-ClientScopedStatePath (Join-Path (Get-BackupRoot $Manifest) ([string]$attachment.config.backup))
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-Sha256 $backup) -ne [string]$attachment.config.originalSha256) { throw 'Server attachment backup is missing or changed.' }
    }
}

function Test-PrimaryServerDetached {
    param($Manifest)
    if (-not (Test-HasServerAttachments $Manifest)) { return $false }
    $attachment=Get-ServerAttachment $Manifest ([string]$Manifest.evejsRoot)
    return ($null -ne $attachment -and $attachment.status -eq 'detached')
}

function Initialize-ServerAttachments {
    param($Manifest)
    if (Test-HasServerAttachments $Manifest) { return }
    Add-OrSetProperty $Manifest 'serverAttachments' @([pscustomobject]@{
        root=Get-NormalizedPath ([string]$Manifest.evejsRoot); status='attached';
        config=($Manifest.config | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    })
}

function Assert-SelectedAttachmentWiring {
    $text=[IO.File]::ReadAllText((Assert-OwnedEveJSPath $script:ConfigPath))
    foreach ($pair in @(@('EVEJS_CLIENT_PATH',$script:ClientRoot),@('EVEJS_CLIENT_EXE','bin64\exefile.exe'),@('TRINITYPLATFORM','dx12'),@('EVEJS_DLSS5','on'))) {
        Assert-ExactBatchSettingValue -Text $text -Name $pair[0] -ExpectedValue $pair[1]
    }
}

function Invoke-EnsureServerAttachment {
    param($Manifest)
    Assert-ServerAttachments $Manifest
    Initialize-ServerAttachments $Manifest
    if (@($Manifest.serverAttachments | Where-Object { $_.status -in @('attaching','detaching') }).Count) { throw 'An interrupted server attachment needs Recover before retrying.' }
    $payload=Read-PayloadManifest
    if (-not (Test-ManifestMatchesPayloadMetadata -Manifest $Manifest -PayloadManifest $payload) -or (Get-ManifestProfile $Manifest) -ne $Profile) {
        throw 'The shared client has a different payload or control profile. Detach its server attachments before changing the shared installation.'
    }
    Invoke-InRecordedServerContext ([string]$Manifest.evejsRoot) ([string]$Manifest.workspaceRoot) { Invoke-Verify -PayloadManifest $payload -ClientOnly }
    $selected=Get-ServerAttachment $Manifest $script:EveJSRoot
    if ($null -ne $selected -and $selected.status -eq 'attached') {
        Assert-SelectedAttachmentWiring
        Write-Okay 'This server already shares the verified physical installation; no payload was reinstalled.'
        return
    }
    Assert-EveJSRootContract $script:EveJSRoot | Out-Null
    Assert-OwnedEveJSPath $script:ConfigPath | Out-Null
    $text=Get-UpdatedEveJSConfigText
    $relative='attachments\'+[Guid]::NewGuid().ToString('N')+'\EvEJSConfig.bat'
    $backup=Assert-ClientScopedStatePath (Join-Path (Get-BackupRoot $Manifest) $relative)
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    $originalHash=Get-Sha256 $script:ConfigPath
    Copy-FileAtomic -Source $script:ConfigPath -Destination $backup -ExpectedSha256 $originalHash
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { $installedHash=([BitConverter]::ToString($hasher.ComputeHash($script:Utf8NoBom.GetBytes($text)))).Replace('-','') }
    finally { $hasher.Dispose() }
    $attachment=[pscustomobject]@{root=$script:EveJSRoot;status='attaching';config=[pscustomobject]@{
        path=$script:ConfigPath;backup=$relative;originalSha256=$originalHash;installedSha256=$installedHash;applied=$false
    }}
    if ($null -ne $selected) {
        $history=if ($Manifest.PSObject.Properties.Name -contains 'serverAttachmentHistory') { @($Manifest.serverAttachmentHistory) } else { @() }
        Add-OrSetProperty $Manifest 'serverAttachmentHistory' @(@($history)+@($selected))
    }
    $others=@($Manifest.serverAttachments | Where-Object { -not ([string]$_.root).Equals($script:EveJSRoot,[StringComparison]::OrdinalIgnoreCase) })
    Add-OrSetProperty $Manifest 'serverAttachments' @($others+@($attachment))
    Write-JsonAtomic $Manifest $script:ActiveManifestPath
    Write-TextAtomic -Text $text -Path $script:ConfigPath
    if ((Get-Sha256 $script:ConfigPath) -ne $installedHash) { throw 'Attached server configuration changed before commit.' }
    $attachment.config.applied=$true
    $attachment.status='attached'
    Write-JsonAtomic $Manifest $script:ActiveManifestPath
    Assert-SelectedAttachmentWiring
    Write-Okay 'Server attached to the existing physical client without reinstalling payload files.'
}

function Invoke-VerifyServerAttachment {
    param($Manifest)
    Assert-ServerAttachments $Manifest
    $selected=Get-ServerAttachment $Manifest $script:EveJSRoot
    if ($null -eq $selected -or $selected.status -ne 'attached') { throw 'This server is not attached to the installed client package.' }
    Invoke-InRecordedServerContext ([string]$Manifest.evejsRoot) ([string]$Manifest.workspaceRoot) { Invoke-Verify -ClientOnly }
    Assert-SelectedAttachmentWiring
}

function Restore-ServerAttachmentConfig {
    param($Manifest,$Attachment)
    $proxy=$Manifest | ConvertTo-Json -Depth 24 | ConvertFrom-Json
    $proxy.config=$Attachment.config
    Invoke-InRecordedServerContext ([string]$Attachment.root) (Split-Path -Parent ([string]$Attachment.root)) { Restore-OwnedBatchSettings $proxy }
    $Attachment.config=$proxy.config
    $Attachment.status='detached'
    Write-JsonAtomic $Manifest $script:ActiveManifestPath
}

function Invoke-DetachServerAttachment {
    param($Manifest)
    Assert-ServerAttachments $Manifest
    if (@($Manifest.serverAttachments | Where-Object { $_.status -in @('attaching','detaching') }).Count) { throw 'Recover interrupted server attachments before removal.' }
    $selected=Get-ServerAttachment $Manifest $script:EveJSRoot
    if ($null -eq $selected) { throw 'No attachment to remove for the selected server.' }
    if ($selected.status -eq 'attached') {
        $selected.status='detaching'
        Write-JsonAtomic $Manifest $script:ActiveManifestPath
        Restore-ServerAttachmentConfig $Manifest $selected
    }
    if (@($Manifest.serverAttachments | Where-Object { $_.status -eq 'attached' }).Count) {
        Write-Okay 'Server detached; the physical payload remains installed for other attached servers.'
        return
    }
    Invoke-InRecordedServerContext ([string]$Manifest.evejsRoot) ([string]$Manifest.workspaceRoot) { Invoke-Restore -PhysicalOnly }
}

function Invoke-RecoverServerAttachments {
    $manifest=Read-ActiveManifestRaw
    if (-not (Test-HasServerAttachments $manifest)) { return }
    Assert-ServerAttachments $manifest
    foreach ($attachment in @($manifest.serverAttachments | Where-Object { $_.status -in @('attaching','detaching') })) {
        Restore-ServerAttachmentConfig $manifest $attachment
    }
}

function Assert-NoAttachedPayloadChange {
    $manifest=Read-ActiveManifestRaw
    if ((Test-HasServerAttachments $manifest) -and @($manifest.serverAttachments | Where-Object { $_.status -ne 'detached' }).Count) {
        throw 'Detach the server attachments before changing the shared payload or global control profile.'
    }
}
