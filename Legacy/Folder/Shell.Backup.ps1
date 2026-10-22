#requires -Version 5.1

<#
.SYNOPSIS
Hilfsfunktionen fuer Sicherungen, Benutzerordner und Outlook-Kopien.
.DESCRIPTION
Benoetigt die zuvor geladene ..\FileOps\Shell.Common.ps1. Laden allein fuehrt
keine Sicherung oder Bereinigung aus. README.md dokumentiert die Funktionen
und den Backup-Einstieg unter ..\..\Utilities\Backup.
.LINK
README.md
#>


function Get-UserKnownFolder {
    param([string]$Name, [hashtable]$Overrides = @{})
    if ($Overrides.ContainsKey($Name)) {
        if ([string]::IsNullOrWhiteSpace($Overrides[$Name])) { throw "Leere Überschreibung für Benutzerordner '$Name'." }
        return Get-SafePath $Overrides[$Name] -Directory -MustExist
    }
    $ids = @{
        Contacts = '56784854-C6CB-462B-8169-88E350ACB882'
        Favorites = '1777F761-68AD-4D8A-87BD-30B759FA33DD'
        Links = 'BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968'
        Documents = 'FDD39AD0-238F-46AF-ADB4-6C85480369C7'
        Desktop = 'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'
        Pictures = '33E28130-4E1E-4676-835A-98395C3BC3BB'
        Music = '4BD8D571-6D19-48D3-BE97-422220080E43'
        Videos = '18989B1D-99B5-455B-841C-AB7C74E4DDFC'
    }
    if (-not $ids.ContainsKey($Name)) { throw "Unbekannter Benutzerordner: $Name" }
    Initialize-ShellNative
    $path = [ShellSafety.Native]::KnownFolder($ids[$Name])
    if ([string]::IsNullOrWhiteSpace($path)) { throw "Windows Known Folder '$Name' ist nicht verfügbar." }
    return Get-SafePath $path -Directory -MustExist
}

function Assert-BackupName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.','..') -or
        $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        throw "Ungültiger einfacher Ordnername/Archivpräfix: '$Name'."
    }
}

function Assert-TempCleanupPath {
    param([string]$Path, [string]$BackupRoot, [AllowEmptyCollection()][string[]]$Sources = @())
    $safe = Get-SafePath $Path -Directory -MustExist
    $root = [IO.Path]::GetPathRoot($safe)
    if ($safe.TrimEnd('\') -ieq $root.TrimEnd('\')) { throw "Laufwerks-/Freigabewurzel ist kein Temp-Ziel: $safe" }
    if ($env:USERPROFILE) {
        $profile = Get-SafePath $env:USERPROFILE -Directory -MustExist
        if ($profile -ieq $safe -or $profile.StartsWith($safe.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Benutzerprofil oder dessen Elternordner darf nicht bereinigt werden: $safe"
        }
    }
    foreach ($system in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        if ($system -and (Test-Path -LiteralPath $system)) {
            if (Test-PathOverlap $safe $system) { throw "System-/Programmverzeichnis darf nicht bereinigt werden: $safe" }
        }
    }
    Assert-SeparatePaths $safe $BackupRoot
    foreach ($source in $Sources) {
        if (-not [string]::IsNullOrWhiteSpace($source)) { Assert-SeparatePaths $safe $source }
    }
    $defaultTemp = Get-SafePath ([IO.Path]::GetTempPath()) -Directory -MustExist
    if ($safe -ine $defaultTemp) {
        $marker = Get-SafePath (Join-Path $safe '.shell-temp-cleanup-allowed') -MustExist
        if (-not [IO.File]::Exists($marker) -or [IO.File]::ReadAllText($marker).Trim() -ine $safe) {
            throw "Benutzerdefinierter Temp-Pfad benötigt .shell-temp-cleanup-allowed mit seinem kanonischen absoluten Pfad: $safe"
        }
    }
    $null = @(Get-SafeTree $safe -Recurse -RejectReparse)
    return $safe
}

function Remove-ConfiguredTempContent {
    param($Context, [string[]]$Paths, [string]$BackupRoot, [AllowEmptyCollection()][string[]]$Sources = @())
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try {
            $safe = Assert-TempCleanupPath $path $BackupRoot $Sources
            if ($Context.LogDirectory -and (Test-PathOverlap $safe $Context.LogDirectory)) { throw 'Temp-Pfad überlappt das aktive Protokollverzeichnis.' }
            $items = @(Get-SafeTree $safe -Recurse -RejectReparse | Where-Object Name -ne '.shell-temp-cleanup-allowed' | Sort-Object { $_.FullName.Length } -Descending)
            if (-not $items.Count) { Add-ShellResult $Context $safe Skipped Bereinigung 'Temp-Ordner ist leer.'; continue }
            foreach ($item in $items) {
                try {
                    if (-not (Confirm-ShellOperation $Context $item.FullName 'Explizit freigegebenen Temp-Inhalt löschen')) { continue }
                    $null = Get-SafePath $item.FullName -MustExist
                    if ($item.PSIsContainer) {
                        # Kein rekursives Löschen: abgelehnte/neu entstandene Inhalte bleiben erhalten.
                        [IO.Directory]::Delete($item.FullName, $false)
                    }
                    else {
                        Set-ShellAttributes $item.FullName -Remove ([IO.FileAttributes]::ReadOnly)
                        [IO.File]::Delete($item.FullName)
                    }
                    Add-ShellResult $Context $item.FullName Success Bereinigung 'Gelöscht.'
                }
                catch { Add-ShellResult $Context $item.FullName Failed Bereinigung 'Temp-Element nicht gelöscht.' $_ }
            }
        }
        catch { Add-ShellResult $Context $path Failed TempPrüfung 'Temp-Bereinigung abgelehnt/fehlgeschlagen.' $_ }
    }
}

function Copy-OutlookSnapshotFile {
    param($Context, [string]$Source, [string]$Destination)
    $sourcePath = Get-SafePath $Source -MustExist
    $destinationPath = Get-SafePath $Destination
    Assert-SeparatePaths $sourcePath $destinationPath
    if (-not (Confirm-ShellOperation $Context $destinationPath "Outlook-Datei '$sourcePath' in neue Version kopieren")) { return }
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath))
    $stage = "$destinationPath.partial-$([guid]::NewGuid().ToString('N'))"
    try {
        # Kein gleichzeitiger Schreiber zugelassen; dennoch keine VSS-/Anwendungskonsistenzgarantie.
        $input = [IO.File]::Open($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $hash = Get-StreamHash $input
            $input.Position = 0
            $output = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose() }
        }
        finally { $input.Dispose() }
        $check = [IO.File]::OpenRead($stage)
        try { $copiedHash = Get-StreamHash $check } finally { $check.Dispose() }
        if ($hash -ne $copiedHash) { throw 'Prüfsumme der Outlook-Kopie stimmt nicht überein.' }
        Publish-ShellFile $stage $destinationPath -Context $Context
        Add-ShellResult $Context $destinationPath Success Outlook 'Versionierte Einzelkopie geprüft und veröffentlicht.'
    }
    finally { Remove-OwnedStage $stage $Context }
}

function Copy-OutlookData {
    param($Context, [string[]]$Paths, [string]$BackupRoot, [switch]$StopOutlook)
    $valid = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        try {
            $safe = Get-SafePath $Paths[$i] -Directory -MustExist
            Assert-SeparatePaths $safe $BackupRoot
            $files = @(Get-SafeTree $safe -RejectReparse | Where-Object { -not $_.PSIsContainer -and $_.Extension -in @('.pst','.ost') })
            if (-not $files.Count) { throw "Keine direkten PST/OST-Dateien: $safe" }
            $valid.Add([pscustomobject]@{ Index = $i; Path = $safe; Files = $files })
        }
        catch { Add-ShellResult $Context $Paths[$i] Failed OutlookPrüfung 'Outlook-Quelle nicht verfügbar/unsicher.' $_ }
    }
    if (-not $valid.Count) { return }
    if ($StopOutlook) {
        foreach ($process in @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue)) {
            try {
                if (Confirm-ShellOperation $Context "OUTLOOK PID=$($process.Id)" 'Outlook explizit zwangsweise beenden') {
                    Stop-Process -Id $process.Id -Force -Confirm:$false -ErrorAction Stop
                    Add-ShellResult $Context "PID=$($process.Id)" Success Outlook 'Outlook beendet.'
                }
            }
            catch { Add-ShellResult $Context "PID=$($process.Id)" Failed Outlook 'Outlook konnte nicht beendet werden.' $_ }
        }
    }
    else { Write-ShellLog $Context 'Outlook wird nicht automatisch beendet. Geöffnete Dateien können nicht kopierbar/inkonsistent sein.' WARN }
    $version = Join-Path $BackupRoot ("Outlook\" + $Context.RunId + '-' + [guid]::NewGuid().ToString('N'))
    foreach ($source in $valid) {
        $name = if ($source.Index -eq 0) { 'AppData-Outlook' } else { 'Dokumente-Outlook' }
        foreach ($file in $source.Files) {
            try { Copy-OutlookSnapshotFile $Context $file.FullName (Join-Path (Join-Path $version $name) $file.Name) }
            catch { Add-ShellResult $Context $file.FullName Failed Outlook 'Outlook-Kopie fehlgeschlagen; ältere Versionen unverändert.' $_ }
        }
    }
}

function Get-BackupSelections {
    param([string]$Action, [hashtable]$Options)
    $docs = @('Contacts','Favorites','Links','Documents','Desktop')
    $known = switch ($Action) {
        { $_ -in @('A','B') } { $docs }
        '1' { 'Pictures' }
        '2' { 'Music' }
        '3' { 'Videos' }
        'O' { $docs + @('Pictures','Music','Videos') }
    }
    foreach ($name in $known) {
        [pscustomobject]@{ Name = $name; Known = $true; Path = $null; Prefix = $Options.UserArchivePrefix }
    }
    $local = switch ($Action) {
        '4' { 'LocalBookPath' }
        '5' { 'LocalPhotoPath'; 'LocalPicturesPath' }
        '6' { 'LocalMusicPath' }
        '7' { 'LocalIosPath' }
        'Q' { 'LocalBookPath'; 'LocalPhotoPath'; 'LocalPicturesPath'; 'LocalMusicPath'; 'LocalIosPath' }
    }
    foreach ($name in $local) {
        [pscustomobject]@{ Name = $name; Known = $false; Path = $Options[$name]; Prefix = $Options.LocalArchivePrefix }
    }
    if ($Action -in @('P','Q')) {
        foreach ($name in @('OneDrivePath','DropboxPath','CreativeCloudPath','SynologyPath','ICloudPath')) {
            [pscustomobject]@{ Name = $name; Known = $false; Path = $Options[$name]; Prefix = $Options.CloudArchivePrefix }
        }
    }
}

function Invoke-BackupAction {
    param($Context, [string]$Action, [string]$BackupRoot, [hashtable]$Options)
    if ($Action -eq 'X') { Add-ShellResult $Context $BackupRoot Skipped Aktion 'Ohne Aktion beendet.'; return }
    $root = Get-SafePath $BackupRoot -Directory
    foreach ($prefix in @($Options.UserArchivePrefix, $Options.LocalArchivePrefix, $Options.CloudArchivePrefix)) { Assert-BackupName $prefix }
    foreach ($key in $Options.UserFolderPaths.Keys) {
        if ($key -notin @('Contacts','Favorites','Links','Documents','Desktop','Pictures','Music','Videos')) { throw "Unbekannter UserFolderPaths-Schlüssel: $key" }
    }
    if ($Action -eq '8') {
        $documentsOutlook = $Options.OutlookDocumentsPath
        if (-not $documentsOutlook) {
            try { $documentsOutlook = Join-Path (Get-UserKnownFolder Documents $Options.UserFolderPaths) 'Outlook-Dateien' }
            catch { Add-ShellResult $Context 'Documents\Outlook-Dateien' Failed OutlookPrüfung 'Dokumente-Outlook-Standardpfad nicht verfügbar.' $_ }
        }
        Copy-OutlookData $Context @($Options.OutlookLocalPath,$documentsOutlook) $root -StopOutlook:$Options.StopOutlook
        return
    }
    $selections = @(Get-BackupSelections $Action $Options)
    $resolvedRar = $null
    if ($selections.Count) { $resolvedRar = Resolve-RarExecutable $Options.RarExe }
    $before = $Context.Results.Count
    $completed = 0
    $selectedPaths = [Collections.Generic.List[string]]::new()
    foreach ($selection in $selections) {
        try {
            $source = if ($selection.Known) { Get-UserKnownFolder $selection.Name $Options.UserFolderPaths } else { Get-SafePath $selection.Path -Directory -MustExist }
            $selectedPaths.Add($source)
            Assert-SeparatePaths $source $root
            $archiveName = '{0}-{1}-{2}-{3}.rar' -f $selection.Prefix, $selection.Name, $Context.RunId, [guid]::NewGuid().ToString('N')
            if (New-SafeArchive $Context $source (Join-Path $root $archiveName) rar $resolvedRar) { $completed++ }
        }
        catch { Add-ShellResult $Context $selection.Name Failed Sicherung 'Ausgewählte Quelle konnte nicht gesichert werden.' $_ }
    }
    if ($Action -in @('A','T')) {
        $canClean = $Action -eq 'T' -or ($completed -eq $selections.Count -and $completed -gt 0 -and
            -not $Context.LogFailed -and @($Context.Results | Select-Object -Skip $before | Where-Object { $_.Status -in @('Failed','Skipped','Planned') }).Count -eq 0)
        if (-not $canClean) {
            Add-ShellResult $Context $root Skipped Bereinigung 'Aktion A: Temp bleibt erhalten, weil nicht alle Dokumentarchive tatsächlich erfolgreich gesichert wurden.'
            return
        }
        # Schützt auch nicht ausgewählte bekannte Benutzer- und konfigurierte Quellordner.
        $protected = [Collections.Generic.List[string]]::new()
        foreach ($source in $selectedPaths) { $protected.Add($source) }
        foreach ($key in @('LocalBookPath','LocalPhotoPath','LocalPicturesPath','LocalMusicPath','LocalIosPath','OneDrivePath','DropboxPath','CreativeCloudPath','SynologyPath','ICloudPath','OutlookLocalPath','OutlookDocumentsPath')) {
            if ($Options[$key]) { $protected.Add($Options[$key]) }
        }
        foreach ($name in @('Contacts','Favorites','Links','Documents','Desktop','Pictures','Music','Videos')) {
            try { $protected.Add((Get-UserKnownFolder $name $Options.UserFolderPaths)) }
            catch {
                # Unbekannter Schutzpfad: Bereinigung fail-closed, statt ins Blaue zu löschen.
                Add-ShellResult $Context $name Failed TempPrüfung 'Benutzerordner nicht prüfbar; Temp-Bereinigung unterbleibt.' $_
                return
            }
        }
        Remove-ConfiguredTempContent $Context @($Options.UserTempPath,$Options.SecondaryTempPath) $root $protected.ToArray()
    }
}
