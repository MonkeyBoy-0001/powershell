#requires -Version 5.1

<#
.SYNOPSIS
Versionierte Sicherung ausgewählter Benutzerdaten; keine Vollsystemsicherung.
.DESCRIPTION
RAR-Archive werden neu erstellt, geprüft und unveränderlich veröffentlicht.
A sichert zuerst Dokumentordner und bereinigt Temp nur bei vollständigem Erfolg.
T ist die explizite reine Temp-Aktion. Outlook ist separat (8), kein automatischer
Prozessstopp. Alle Parameter, Menüpunkte und Sicherheitsgrenzen: README.md.
.LINK
README.md
.LINK
..\..\Legacy\Skript-Help.md
.EXAMPLE
& '.\Locale Backup.ps1' -DriveLetter F -Action B -NoPause -WhatIf
.EXAMPLE
& '.\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action 2 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidatePattern('^[A-Za-z]$')][string]$DriveLetter,
    [string]$BackupFolderName = 'Mein Backup',
    [string]$BackupPath,
    [string]$RarExe = 'rar',
    [string]$UserArchivePrefix = 'UserA',
    [string]$LocalArchivePrefix = 'Ordner',
    [string]$CloudArchivePrefix = 'Cloud',
    [string]$LocalBookPath = 'E:\Buch',
    [string]$LocalPhotoPath = 'E:\Foto',
    [string]$LocalPicturesPath = 'E:\Pics',
    [string]$LocalMusicPath = 'E:\Musik',
    [string]$LocalIosPath = 'E:\iOS',
    [string]$OneDrivePath = $env:OneDrive,
    [string]$DropboxPath,
    [string]$CreativeCloudPath,
    [string]$SynologyPath,
    [string]$ICloudPath,
    [string]$UserTempPath = [IO.Path]::GetTempPath(),
    [string]$SecondaryTempPath,
    [string]$OutlookLocalPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\Outlook'),
    [string]$OutlookDocumentsPath,
    [hashtable]$UserFolderPaths = @{},
    [switch]$StopOutlook,
    [ValidateSet('A','B','1','2','3','4','5','6','7','8','O','P','Q','T','X')][string]$Action,
    [switch]$NoPause,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot '..\..\Legacy\FileOps\Shell.Common.ps1')
    . (Join-Path $PSScriptRoot '..\..\Legacy\Folder\Shell.Backup.ps1')
}
catch { Write-Error "Abhängigkeit Shell.Common.ps1/Shell.Backup.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$options = @{}
foreach ($name in @('RarExe','UserArchivePrefix','LocalArchivePrefix','CloudArchivePrefix','LocalBookPath','LocalPhotoPath','LocalPicturesPath','LocalMusicPath','LocalIosPath','OneDrivePath','DropboxPath','CreativeCloudPath','SynologyPath','ICloudPath','UserTempPath','SecondaryTempPath','OutlookLocalPath','OutlookDocumentsPath','UserFolderPaths','StopOutlook')) {
    $options[$name] = Get-Variable -Name $name -ValueOnly
}
$code = Invoke-ShellEntry 'Locale-Backup' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    if ($Action -eq 'X') { Add-ShellResult $context '' Skipped Aktion 'Ohne Aktion beendet.'; return }
    if ($BackupPath -and $DriveLetter) { throw 'BackupPath und DriveLetter nicht gleichzeitig verwenden.' }
    $destination = $BackupPath
    if (-not $destination) {
        Assert-BackupName $BackupFolderName
        $drive = $DriveLetter
        if (-not $drive) {
            if ($Action) { throw 'Für automatisierte Aktionen BackupPath oder DriveLetter angeben.' }
            $drive = (Read-Host 'Ziellaufwerk [A..Z]').Trim()
        }
        if ($drive -notmatch '^[A-Za-z]$') { throw 'Ungültiger Laufwerksbuchstabe.' }
        $destination = Join-Path ($drive + ':\') $BackupFolderName
    }
    $destination = Get-SafePath $destination -Directory
    if ($destination.TrimEnd('\') -ieq ([IO.Path]::GetPathRoot($destination)).TrimEnd('\')) { throw 'Backup-Ziel darf keine Laufwerks-/Freigabewurzel sein.' }
    if ($Action) { Invoke-BackupAction $context $Action $destination $options }
    else {
        while ($true) {
            Write-Host '[A] Dokumente, dann Temp bei Erfolg  [B] Dokumente ohne Temp'
            Write-Host '[1] Fotos [2] gesamte Musik [3] Videos [8] Outlook separat'
            Write-Host '[4] lokale Bücher [5] lokale Fotos [6] lokale Musik [7] iOS'
            Write-Host '[O] ausgewählte Benutzerordner (ohne Outlook) [P] Cloud [Q] lokal + Cloud'
            Write-Host '[T] nur freigegebenes Temp bereinigen [X] Ende'
            $selection = (Read-Host 'Aktion').Trim().ToUpperInvariant()
            if ($selection -eq 'X') { break }
            if ($selection -notin @('A','B','1','2','3','4','5','6','7','8','O','P','Q','T')) { Write-Warning 'Ungültige Auswahl.'; continue }
            try { Invoke-BackupAction $context $selection $destination $options }
            catch { Add-ShellResult $context $selection Failed Aktion 'Aktion konnte nicht ausgeführt werden.' $_ }
            if (-not $NoPause -and -not $context.DryRun) { $null = Read-Host 'Weiter mit Enter' }
        }
    }
}
exit $code
