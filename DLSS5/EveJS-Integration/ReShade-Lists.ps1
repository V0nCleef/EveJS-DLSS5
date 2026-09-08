# ReShade serializes lists with a single comma separator and doubled literal
# commas. Shared by standalone ownership and private launcher preparation.
function Split-ReShadeList {
    param([AllowEmptyString()][string]$Value)
    $entry=New-Object Text.StringBuilder
    for ($index=0; $index -lt $Value.Length; $index++) {
        if ($Value[$index] -eq ',') {
            if ($index+1 -lt $Value.Length -and $Value[$index+1] -eq ',') {
                [void]$entry.Append(','); $index++
            } else {
                if ($entry.Length) { $entry.ToString() }
                [void]$entry.Clear()
            }
        } else { [void]$entry.Append($Value[$index]) }
    }
    if ($entry.Length) { $entry.ToString() }
}

function Test-ReShadeListItem {
    param([AllowEmptyString()][string]$Value,[string]$Item)
    foreach ($entry in @(Split-ReShadeList $Value)) {
        if ($entry.Equals($Item,[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Add-ReShadeListItem {
    param([AllowEmptyString()][string]$Value,[string]$Item)
    if (Test-ReShadeListItem $Value $Item) { return $Value }
    return (@(@(Split-ReShadeList $Value) + @($Item) | ForEach-Object { $_.Replace(',',',,') }) -join ',')
}

function Remove-ReShadeListItem {
    param([AllowEmptyString()][string]$Value,[string]$Item)
    if (-not (Test-ReShadeListItem $Value $Item)) { return $Value }
    return (@(Split-ReShadeList $Value | Where-Object {
        -not $_.Equals($Item,[StringComparison]::OrdinalIgnoreCase)
    } | ForEach-Object { $_.Replace(',',',,') }) -join ',')
}

function Test-ReShadeEarlyLoadKey {
    param($Key)
    return ([string]$Key.section -ieq 'ADDON' -and [string]$Key.key -ieq 'LoadFromDllMain')
}

function Get-ReShadeEarlyLoadRestoredValue {
    param($Managed,[AllowEmptyString()][string]$Current)
    $item='renodx-dlss5.addon64'
    $original=if ([bool]$Managed.originalPresent) { [string]$Managed.originalValue } else { '' }
    if (Test-ReShadeListItem $original $item) { return $Current }
    $restored=Remove-ReShadeListItem $Current $item
    if ($Managed.PSObject.Properties.Name -notcontains 'ownership' -or $Managed.ownership -ne 'listMember') {
        # Old scalar installers could have erased the original neighbors.
        # Restore those captured entries without erasing later additions.
        foreach ($entry in @(Split-ReShadeList $original)) { $restored=Add-ReShadeListItem $restored $entry }
    }
    return $restored
}
