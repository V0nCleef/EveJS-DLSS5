Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$integration=Split-Path -Parent $PSScriptRoot
. (Join-Path $integration 'ReShade-Lists.ps1')
. (Join-Path $integration 'Client-Attachments.ps1')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $integration 'Manage-EveJSDLSS5.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('dlss5-addon-ownership-'+[Guid]::NewGuid().ToString('N'))
$script:ClientRoot=Join-Path $fixture 'physical\tq'
$script:StateRoot=Join-Path $fixture 'physical\_evejs\dlss5\install'
$script:EveJSRoot=Join-Path $fixture 'missing-server'
$script:ReShadeConfigPath=Join-Path $script:ClientRoot 'bin64\ReShade.ini'
$script:ActiveManifestPath=Join-Path $script:StateRoot 'active-install.json'
$script:ProfileTransaction=$null
$script:Utf8NoBom=New-Object Text.UTF8Encoding($false)
$script:ProfileComponents=@{DLSS5=@('reshade','renodx');Original=@()}
function Assert-Equal($Actual,$Expected) { if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'." } }
function Read-List { return (Get-IniValueState ([IO.File]::ReadAllText($script:ReShadeConfigPath)) 'ADDON' 'LoadFromDllMain').value }
New-Item -ItemType Directory -Path (Split-Path -Parent $script:ReShadeConfigPath),$script:StateRoot -Force | Out-Null
try {
    foreach ($original in @('', 'first.addon64,name,,withcomma.addon64', 'first.addon64,renodx-dlss5.addon64,last.addon64')) {
        $key=[pscustomobject]@{section='ADDON';key='LoadFromDllMain';installedValue='renodx-dlss5.addon64';ownership='listMember';originalPresent=[bool]$original;originalValue=$original}
        $tracking=[pscustomobject]@{originalExists=$true;managedKeys=@($key);lastAppliedSha256=$null;lastAppliedProfile=$null;restoredAtUtc=$null}
        $manifest=[pscustomobject]@{reshadeConfig=$tracking}
        [IO.File]::WriteAllText($script:ReShadeConfigPath,"[ADDON]`nLoadFromDllMain=$original`n[Neighbor]`nKeep=yes`n")
        Set-ReShadeConfigForProfile $manifest DLSS5
        $enabled=Add-ReShadeListItem $original 'renodx-dlss5.addon64'
        Assert-Equal (Read-List) $enabled
        Set-ReShadeConfigForProfile $manifest DLSS5
        Assert-Equal (Read-List) $enabled
        Test-ReShadeConfigForProfile $manifest DLSS5
        $later=Add-ReShadeListItem $enabled 'later.addon64'
        [IO.File]::WriteAllText($script:ReShadeConfigPath,"[ADDON]`nLoadFromDllMain=$later`n[Neighbor]`nKeep=yes`n")
        Test-ReShadeConfigForProfile $manifest DLSS5
        Set-ReShadeConfigForProfile $manifest Original
        $expected=Add-ReShadeListItem $original 'later.addon64'
        Assert-Equal (Read-List) $expected
        Test-ReShadeConfigForProfile $manifest Original
        Set-ReShadeConfigForProfile $manifest DLSS5
        Restore-ReShadeConfig $manifest
        Assert-Equal (Read-List) $expected
        Assert-OwnedConfigRestoration $manifest
        Assert-Equal ([IO.File]::ReadAllText($script:ReShadeConfigPath).Contains('Keep=yes')) $true
    }
    # A new receipt does not resurrect another addon's deliberately removed entry.
    $key.originalValue='removed.addon64'; $key.originalPresent=$true
    Assert-Equal (Get-ReShadeEarlyLoadRestoredValue $key 'renodx-dlss5.addon64,later.addon64') 'later.addon64'
    # An old scalar receipt can recover the neighbors its installer erased.
    $key.PSObject.Properties.Remove('ownership')
    Assert-Equal (Get-ReShadeEarlyLoadRestoredValue $key 'renodx-dlss5.addon64,later.addon64') 'later.addon64,removed.addon64'
    # Duplicate keys fail verification; no broad rewrite silently combines them.
    [IO.File]::WriteAllText($script:ReShadeConfigPath,"[ADDON]`nLoadFromDllMain=renodx-dlss5.addon64`nLoadFromDllMain=other.addon64`n")
    $rejected=$false
    try { Test-ReShadeConfigForProfile $manifest DLSS5 } catch { $rejected=$_.Exception.Message -match 'Duplicate' }
    Assert-Equal $rejected $true
    'PASS: standalone shared-addon enable/repeat/verify/disable/restore, later neighbors, escaped commas, prior RenoDX ownership, legacy recovery and duplicate-key rejection.'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup escaped temporary fixture.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
