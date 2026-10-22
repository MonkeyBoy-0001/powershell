# Ordnersymbole und Backup-Hilfsfunktionen

Diese Dokumentation beschreibt alle PowerShell-Skripte in `Legacy\Folder`.
Die Beispiele beziehen sich auf dieses Arbeitsverzeichnis.

## Aktueller Lieferumfang und Einschraenkungen

Die vier Ordnersymbol-Einstiegsskripte laden die vorhandene gemeinsame
[Shell.Common.ps1](../FileOps/Shell.Common.ps1) ueber
`$PSScriptRoot\..\FileOps\Shell.Common.ps1`. Der Ladepfad ist unabhaengig vom
Arbeitsverzeichnis. Beim Kopieren die benachbarten Verzeichnisse `Folder` und
`FileOps` mit dieser Struktur erhalten; keine zweite Bibliothekskopie erforderlich.
Fehlt die Bibliothek oder ist sie nicht ladbar, wird Exitcode 1 gemeldet.

Der Backup-Einstieg liegt unter
[Utilities\Backup\Locale Backup.ps1](../../Utilities/Backup/Locale%20Backup.ps1).
Seine Parameter und Menueaktionen sind in der
[Backup-README](../../Utilities/Backup/README.md) beschrieben.
`Shell.Backup.ps1` bleibt hier als gemeinsame Funktionsbibliothek.

| Datei | Aufgabe |
|---|---|
| [Clear Folder.ps1](Clear%20Folder.ps1) | Symbolkonfiguration eines Ordners entfernen. |
| [Clear Folders.ps1](Clear%20Folders.ps1) | Dieselbe Aktion fuer mehrere Ordner, optional rekursiv. |
| [Modify Folder.ps1](Modify%20Folder.ps1) | Ein benachbartes ICO als Symbol eines Ordners einrichten. |
| [Modify Folders.ps1](Modify%20Folders.ps1) | Dieselbe Aktion fuer mehrere Ordner, optional rekursiv. |
| [Shell.Backup.ps1](Shell.Backup.ps1) | Known-Folder-Ermittlung, Backup-Auswahl, Temp-Pruefungen und Outlook-Einzelkopien. |

## Voraussetzungen und gemeinsame Parameter

Windows mit Windows PowerShell 5.1 oder PowerShell 7. Erforderlich sind Lese-,
Schreib-, Attribut- und gegebenenfalls Loeschrechte fuer die ausgewaehlten
Ordner; Administratorrechte sind nicht generell vorgeschrieben.
Ordnersymbole benoetigen weder RAR noch weitere Downloads.

`Get-Help '.\Clear Folder.ps1' -Full` zeigt die Kommentarhilfe einschliesslich
des README-Verweises, ohne eine Aktion auszufuehren. Alle Skripte in diesem
Ordner enthalten einen solchen `.LINK`-Verweis.

| Parameter | Gilt fuer | Bedeutung |
|---|---|---|
| `Path` | Alle vier Einstiege | Expliziter literaler Ordnerpfad, Position 0. Plural-Skripte akzeptieren ein Array und weitere Positionsargumente. |
| `Recurse` | Nur Plural-Skripte | Stammordner und regulaere Unterordner bearbeiten; standardmaessig aus. |
| `LogDirectory` | Alle vier Einstiege | Beschreibbarer Log- und Sicherungsordner, getrennt vom bearbeiteten Ordnerbaum. |
| `WhatIf` | Alle vier Einstiege | Nur pruefen und planen; keine Symbol- oder Attributaenderung. Logs und CSV werden trotzdem geschrieben. |
| `Confirm` | Alle vier Einstiege | Vor jeder Symboltransaktion nachfragen. |

Fehlende Zielangaben werden als Fehler gemeldet statt interaktiv abgefragt.
Relative Pfade beziehen sich auf das Arbeitsverzeichnis. Skripte normal mit
`&` ausfuehren, nicht dot-sourcen.

## Clear Folder.ps1 und Clear Folders.ps1

Entfernen nur `IconResource`, `IconFile` und `IconIndex` im Abschnitt
`[.ShellClassInfo]` der `desktop.ini`. Andere Eintraege und Abschnitte bleiben
inhaltlich erhalten. Mehrere ShellClassInfo-Abschnitte werden als mehrdeutig
abgewiesen.

| Zusaetzlicher Parameter | Standard | Bedeutung |
|---|---|---|
| `ClearFolderReadOnly` | Aus | Zusaetzlich das ReadOnly-Attribut des Ordners entfernen. |
| `RemoveDesktopIni` | Aus | Die gesamte `desktop.ini` statt nur ihrer Symbolangaben loeschen. |

`desktop.ico` wird nur geloescht, wenn die urspruengliche INI genau diese Datei
referenziert. Eine unreferenzierte oder fremde Datei bleibt erhalten, auch mit
`-RemoveDesktopIni`. Eine bearbeitete INI wird als UTF-16LE mit BOM gespeichert.

Beispiele:

```powershell
& '.\Clear Folder.ps1' -Path 'D:\Daten\Beispiel' -WhatIf `
    -LogDirectory 'D:\Protokolle\Ordnersymbole'

& '.\Clear Folders.ps1' -Path 'D:\Daten\A','D:\Daten\B' -Recurse -Confirm `
    -LogDirectory 'D:\Protokolle\Ordnersymbole'
```

`RemoveDesktopIni` entfernt auch andere INI-Einstellungen und sollte nur
bewusst eingesetzt werden. Vorher mit `-WhatIf` pruefen.

## Modify Folder.ps1 und Modify Folders.ps1

Fuer `D:\Daten\Beispiel` muss **`D:\Daten\Beispiel.ico`** existieren, also
neben dem Ordner und mit demselben Namen. Jeder rekursiv bearbeitete Unterordner
braucht ebenfalls eine eigene benachbarte ICO-Datei.

Der Helfer prueft den ICO-Dateikopf, kopiert die Quelle nach `desktop.ico` und
setzt `IconResource=.\desktop.ico,0` in `desktop.ini`. Alte IconFile-/IconIndex-
Angaben werden nur im ShellClassInfo-Abschnitt entfernt. Fehlende INI bzw.
fehlender Abschnitt werden angelegt. Die Quelle bleibt erhalten.

| Ziel | Gesetzte Attribute |
|---|---|
| `desktop.ico` | Hidden und ReadOnly |
| `desktop.ini` | Hidden und System |
| Bearbeiteter Ordner | ReadOnly |

Andere INI-Einstellungen bleiben inhaltlich erhalten. Vorhandene Symboldateien
werden vor dem Ersetzen gesichert. Die Kopfpruefung ist kein vollstaendiger
Bilddecoder-Test. Explorer wird nicht beendet; die Anzeige muss eventuell
manuell aktualisiert werden.

Beispiele:

```powershell
& '.\Modify Folder.ps1' -Path 'D:\Daten\Beispiel' -WhatIf `
    -LogDirectory 'D:\Protokolle\Ordnersymbole'

& '.\Modify Folders.ps1' -Path 'D:\Daten\A','D:\Daten\B' -Confirm `
    -LogDirectory 'D:\Protokolle\Ordnersymbole'
```

## Protokolle und Wiederherstellung der Ordnersymbole

Die gemeinsame Bibliothek waehlt standardmaessig `Logs` neben ihrer eigenen
Datei: **`Legacy\FileOps\Logs`**, auch fuer die Ordnersymbol-Skripte.
Mit `-LogDirectory` kann ein anderes Ziel gewaehlt werden.

Logs und gleichnamige Ergebnis-CSV enthalten Phasen, Pfade und Status:
`Success`, `Failed`, `Skipped` oder `Planned`.

| Exitcode | Bedeutung |
|---|---|
| `0` | Kein erkannter Fehler; keine Garantie, dass alle Aktionen ausgefuehrt wurden. |
| `1` | Globale Voraussetzung oder Abhaengigkeit fehlt. |
| `2` | Mindestens ein Ziel-, Such-, Sicherungs-, Rollback- oder Protokollfehler. |

`$LASTEXITCODE` direkt nach dem Aufruf pruefen. Vor einer bestaetigten
Symbolaenderung entsteht `Icon-Recovery-<GUID>` im Logverzeichnis:
Dateikopien und `recovery.json` dokumentieren urspruengliche Bytes, Existenz
und Attribute. Bei Fehlern wird automatisch zurueckgesetzt; Sicherungen
bleiben auch nach Erfolg erhalten.

Ohne persistente Sicherung werden Symbolaenderungen verweigert.
Ruecksetzungsfehler im Log zuerst klaeren, nicht blind erneut starten.
Log-/Sicherungsordner duerfen nicht mit dem bearbeiteten Ordner ueberlappen.
Junctions, symbolische Links und gepruefte Dateien mit mehreren Hardlinks werden
nicht wie normale Ziele verarbeitet. Keine parallelen Aenderungen vornehmen.

## Shell.Backup.ps1

Diese Bibliothek definiert nur Funktionen und benoetigt `Shell.Common.ps1`.
Zum Laden fuer Entwicklung, ohne eine Sicherung oder Bereinigung auszufuehren:

```powershell
. '..\FileOps\Shell.Common.ps1'
. '.\Shell.Backup.ps1'
```

| Funktion | Zweck |
|---|---|
| `Get-UserKnownFolder` | Windows-Benutzerordner ueber SHGetKnownFolderPath aufloesen; gezielte Hashtable-Overrides unterstuetzen. |
| `Assert-BackupName` | Einfache Ordnernamen/Archivpraefixe validieren. |
| `Assert-TempCleanupPath` | Temp-Pfad, Schutzbereiche, Markierung und enthaltene Analysepunkte pruefen. |
| `Remove-ConfiguredTempContent` | Freigegebenen Temp-Inhalt elementweise nach ShouldProcess loeschen. |
| `Copy-OutlookSnapshotFile` | Eine Datei in eine neue Arbeitsdatei kopieren, SHA256 vergleichen und veroeffentlichen. |
| `Copy-OutlookData` | Direkte PST-/OST-Dateien aus ausgewaehlten Ordnern versioniert kopieren; optional Outlook PID-basiert beenden. |
| `Get-BackupSelections` | Aktion in Known-Folder- und konfigurierte Quellauswahl umsetzen. |
| `Invoke-BackupAction` | Aktion mit Laufkontext, Backup-Ziel und Options-Hashtable koordinieren. |

### Aktionen der Bibliothek

Diese Werte werden vom Parameter `-Action` des Backup-Einstiegs an die
internen Funktionen weitergereicht. Die Bibliothek nicht direkt als
Backup-Einstieg ausfuehren.

| Aktion | Auswahl |
|---|---|
| `A` | Contacts, Favorites, Links, Documents, Desktop sichern; danach Temp nur bei vollstaendig erfolgreicher Sicherung bereinigen. |
| `B` | Dieselben fuenf Ordner, ohne Temp. |
| `1`, `2`, `3` | Pictures, Music bzw. Videos. |
| `4` | LocalBookPath. |
| `5` | LocalPhotoPath und LocalPicturesPath. |
| `6`, `7` | LocalMusicPath bzw. LocalIosPath. |
| `8` | Direkte PST-/OST-Dateien aus beiden Outlook-Quellen kopieren. |
| `O` | B sowie Pictures, Music und Videos; keine separate Outlook-Aktion, kein Temp. |
| `P` | OneDrivePath, DropboxPath, CreativeCloudPath, SynologyPath, ICloudPath. |
| `Q` | Alle lokalen Quellen aus 4 bis 7 plus P. |
| `T` | Nur freigegebenen Temp-Inhalt bereinigen, ohne vorgeschaltete Sicherung. |
| `X` | Ohne Datenaktion beenden. |

`Invoke-BackupAction` erwartet `Context`, `Action`, `BackupRoot` und `Options`.
`Utilities\Backup\Locale Backup.ps1` validiert Parameter, stellt
ShouldProcess/Laufkontext bereit und setzt die benoetigten Optionen: `UserArchivePrefix`,
`LocalArchivePrefix`, `CloudArchivePrefix`, `UserFolderPaths`, `RarExe`, die oben
genannten Quellpfade, `OutlookLocalPath`, `OutlookDocumentsPath`, `StopOutlook`,
`UserTempPath` und `SecondaryTempPath`. Menue-/Laufwerksparameter und Standardwerte
werden durch diesen Einstieg und nicht durch die Bibliothek bereitgestellt.

RAR-Aktionen brauchen WinRAR. Outlook-Kopien, T und X brauchen kein RAR.
Benutzerordner werden ueber Windows ermittelt; fehlende ausgewaehlte Quellen
sind Fehler. Cloud-Quellen muessen vollstaendig lokal verfuegbar sein.

Temp-Loeschungen sind endgueltig. Benutzerdefinierte Temp-Verzeichnisse brauchen
eine manuell angelegte `.shell-temp-cleanup-allowed` mit ihrem kanonischen
absoluten Pfad als Inhalt. Diese Markierung ersetzt keine Schutzpruefung.
Wurzeln, Profil-/Systembereiche sowie Ueberlappungen mit Backup, Quellen oder
Logs werden verweigert. Fuer Aktion A muss die Sicherung tatsaechlich erfolgreich
sein; eine Vorschau reicht nicht.

Outlook moeglichst selbst schliessen. Erzwungenes Beenden kann ungespeicherte
Aenderungen verlieren. Kopierte PST-/OST-Dateien sind keine garantierten
anwendungskonsistenten Snapshots; OST allein ist kein portables Postfachbackup.
Die Bibliothek bietet keine vollstaendige Windows-, Registry-, Profil- oder
Bare-Metal-Sicherung.

## Weitere Dokumentation

[Skript-Help.md](../Skript-Help.md) beschreibt die Verfahren ausfuehrlicher.
Der [Backup-Einstieg](../../Utilities/Backup/README.md) und die
[Regressionstests](../../Testing/README.md) sind in ihren eigenen Ordnern dokumentiert.
Die gemeinsame Bibliothek ist in [FileOps\README.md](../FileOps/README.md)
dokumentiert.
