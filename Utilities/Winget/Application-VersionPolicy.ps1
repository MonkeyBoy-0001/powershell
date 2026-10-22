#requires -Version 5.1

<#
.SYNOPSIS
Laedt und validiert benannte Versionsregeln fuer Anwendungseintraege.
.DESCRIPTION
Funktionsbibliothek ohne Paketaktionen. Datenformat und Verwendung stehen
in README.md neben diesem Skript.
.LINK
README.md
#>


function Resolve-ApplicationVersionPolicy {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Application,

        [Parameter(Mandatory)]
        [string]$PolicyFile
    )

    $reference = $Application.PSObject.Properties['VersionPolicy']
    if ($null -eq $reference) {
        return $Application
    }
    if ($reference.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($reference.Value)) {
        throw 'VersionPolicy must name an entry in Application-VersionPolicies.psd1.'
    }
    if ($null -ne $Application.PSObject.Properties['Version'] -or
        $null -ne $Application.PSObject.Properties['VersionPin']) {
        throw 'VersionPolicy must not be combined with inline Version or VersionPin settings.'
    }

    $policies = Import-PowerShellDataFile -LiteralPath $PolicyFile -ErrorAction Stop
    if (-not $policies.ContainsKey($reference.Value)) {
        throw "Unknown version policy: $($reference.Value)"
    }
    $policy = $policies[$reference.Value]
    if ($policy -isnot [System.Collections.IDictionary] -or $policy.Count -eq 0) {
        throw "Invalid version policy: $($reference.Value)"
    }
    $resolved = $Application.PSObject.Copy()
    foreach ($key in $policy.Keys) {
        if ($key -notin @('Version', 'VersionPin') -or
            $policy[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($policy[$key])) {
            throw "Invalid property in version policy '$($reference.Value)': $key"
        }
        $resolved | Add-Member -NotePropertyName $key -NotePropertyValue $policy[$key]
    }
    return $resolved
}
