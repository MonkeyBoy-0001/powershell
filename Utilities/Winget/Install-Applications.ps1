#requires -Version 5.1

<#
.SYNOPSIS
Installiert die gemeinsame Anwendungsauswahl oder prüft sie ohne Installation.
.DESCRIPTION
-CheckOnly prüft Konfiguration, Zielpfade, vorhandene Pakete und winget-Manifeste
ohne Administratorrechte. Es werden nur Logs/CSV geschrieben, keine Pakete,
Zielordner, Konfigurationen, Sicherungen oder Pins. Kein Test des Installers selbst.
Einstieg und Dateiverweise: README.md. Ausführliche Hilfe: Install-and-Update-Help.md.
.LINK
README.md
.LINK
Install-and-Update-Help.md
.PARAMETER InstalledToolsRoot
Ziel installierter Werkzeuge (C:\Tools).
.PARAMETER PortableToolsRoot
Ziel lokal konfigurierter Werkzeuge (D:\Tools).
.PARAMETER LogDirectory
Verzeichnis für Log und CSV. Bei Schreibfehler Ersatzlog neben dem Skript.
.PARAMETER ApplicationId
Exakte Paket-IDs; ohne Angabe alle konfigurierten Pakete.
.PARAMETER CheckOnly
Nur lesende Prüfung und Vorschau; keine Installation. Logs/CSV sind erlaubt.
.NOTES
Normalbetrieb benötigt Administratorrechte und winget. Exitcodes:
0 = erfolgreich geprüft/verarbeitet; 1 = Grundvoraussetzung fehlt;
2 = mindestens ein Paket-, Prüf- oder Protokollfehler.
.EXAMPLE
.\Install-Applications.ps1 -CheckOnly
.EXAMPLE
.\Install-Applications.ps1 -ApplicationId DominikReichl.KeePass
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
exit (Start-ApplicationRun -Mode Install -InstalledToolsRoot $InstalledToolsRoot `
    -PortableToolsRoot $PortableToolsRoot -LogDirectory $LogDirectory `
    -ApplicationId $ApplicationId -CheckOnly:$CheckOnly)
