#requires -Version 5.1

<#
.SYNOPSIS
Prüft alle konfigurierten Anwendungen vorab und aktualisiert nur installierte Pakete.
.DESCRIPTION
Die komplette Vorschau erscheint vor dem ersten Update. Fehlende Anwendungen
werden nicht installiert. Sprach-, Ziel- und Versionsvorgaben sowie lokale
Konfigurationen stammen aus derselben Bibliothek wie bei der Installation.
-CheckOnly beendet den Lauf nach der lesenden Prüfung (nur Logs/CSV).
Siehe README.md für den Einstieg und Install-and-Update-Help.md für Details.
.LINK
README.md
.LINK
Install-and-Update-Help.md
.PARAMETER InstalledToolsRoot
Bestehendes Ziel installierter Werkzeuge (C:\Tools); keine automatische Umstellung.
.PARAMETER PortableToolsRoot
Bestehendes Ziel lokal konfigurierter Werkzeuge (D:\Tools).
.PARAMETER LogDirectory
Verzeichnis für Log und CSV. Bei Schreibfehler Ersatzlog neben dem Skript.
.PARAMETER ApplicationId
Exakte Paket-IDs; ohne Angabe alle konfigurierten Pakete.
.PARAMETER CheckOnly
Nur lesende Vorschau ohne Administratorrechte; keine Updates oder Konfigurationsänderungen.
.NOTES
Normalbetrieb benötigt Administratorrechte und winget. Exitcodes:
0 = erfolgreich geprüft/verarbeitet (auch fehlend/aktuell/deaktiviert);
1 = Grundvoraussetzung fehlt; 2 = mindestens ein Paket-, Prüf- oder Protokollfehler.
.EXAMPLE
.\Update-Applications.ps1 -CheckOnly
.EXAMPLE
.\Update-Applications.ps1 -ApplicationId Celsys.ClipStudioPaint
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$InstalledToolsRoot = 'C:\Tools',
    [ValidateNotNullOrEmpty()][string]$PortableToolsRoot = 'D:\Tools',
    [ValidateNotNullOrEmpty()][string]$LogDirectory = (Join-Path $PSScriptRoot 'Logs'),
    [ValidateNotNullOrEmpty()][string[]]$ApplicationId,
    [switch]$CheckOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Application-Management.ps1')
exit (Start-ApplicationRun -Mode Update -InstalledToolsRoot $InstalledToolsRoot `
    -PortableToolsRoot $PortableToolsRoot -LogDirectory $LogDirectory `
    -ApplicationId $ApplicationId -CheckOnly:$CheckOnly)
