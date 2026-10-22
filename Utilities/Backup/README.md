# Versionierte Datensicherung

[Locale Backup.ps1](Locale%20Backup.ps1) sichert ausgewaehlte Benutzer- und
Datenordner als neue RAR-Archive oder kopiert Outlook-Dateien in neue Versionen.
Es ist **keine vollstaendige System-, Registry- oder Benutzerprofilsicherung**.
Die folgenden Beispiele werden aus `Utilities\Backup` gestartet.

## Dateien und Voraussetzungen

| Datei | Aufgabe |
|---|---|
| [Locale Backup.ps1](Locale%20Backup.ps1) | Einstieg mit Parametern, interaktivem Menue, ShouldProcess und Exitcodes. |
| [Shell.Common.ps1](../../Legacy/FileOps/Shell.Common.ps1) | Gemeinsame Pfadpruefungen, Archivierung, Protokolle und Laufsteuerung. |
| [Shell.Backup.ps1](../../Legacy/Folder/Shell.Backup.ps1) | Quellauswahl, Windows-Benutzerordner, Temp-Schutz und Outlook-Kopien. |

Windows mit Windows PowerShell 5.1 oder PowerShell 7 ist erforderlich.
Die Helfer werden relativ zu `$PSScriptRoot` geladen; die Verzeichnisstruktur
`Utilities\Backup`, `Legacy\FileOps` und `Legacy\Folder` beim Kopieren erhalten.
Es sind keine separaten Kopien der Bibliotheken neben dem Einstieg noetig.

RAR-Aktionen benoetigen WinRAR `rar.exe`, nicht `unrar.exe`. Wenn RAR nicht in
`PATH` liegt, den vollstaendigen Pfad mit `-RarExe` angeben. Outlook-Kopien und
die Aktionen T/X benoetigen kein RAR. Rechte fuer Quellen und ausgewaehlte Ziele
sowie ausreichender Speicher sind erforderlich, aber keine pauschale Elevation.
Pester wird nur fuer die [Tests](../../Testing/README.md) benoetigt.

## Sicherer Einstieg

```powershell
Get-Help '.\Locale Backup.ps1' -Full

# Musikarchiv nur planen, keine Nutzdaten schreiben
& '.\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action 2 `
    -UserFolderPaths @{ Music = 'D:\Meine Musik' } `
    -RarExe 'C:\Program Files\WinRAR\rar.exe' -WhatIf
$LASTEXITCODE

# Dokument-/Benutzerordner nach Bestaetigung sichern, ohne Temp-Bereinigung
& '.\Locale Backup.ps1' -DriveLetter F -Action B `
    -RarExe 'C:\Program Files\WinRAR\rar.exe' -Confirm
$LASTEXITCODE

# Outlook-Kopien nur planen; kein RAR und kein Prozessstopp
& '.\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action 8 `
    -OutlookLocalPath 'D:\Outlook Lokal' `
    -OutlookDocumentsPath 'D:\Outlook Archiv' -WhatIf
```

`-WhatIf` prueft und plant, ohne Nutzdaten zu loeschen, Archive/Kopien anzulegen
oder Prozesse zu beenden. **Logs und CSV werden trotzdem geschrieben.**
Eine Vorschau garantiert keinen spaeteren Speicherplatz oder Schreibzugriff.
`-Confirm` fragt vor Archiv-, Kopier- und Loeschschritten.

Ohne `Action` erscheint ein Menue; ohne Ziel wird zuerst ein Laufwerk abgefragt.
Mit `Action` ist `BackupPath` oder `DriveLetter` erforderlich, ausser bei X.
Fuer automatisierte Aufrufe immer Aktion und Ziel explizit angeben.
Normal mit `&` starten; Dot-Sourcing fuehrt keine Backup-Aktion aus.

## Aktionen

| Action | Auswahl |
|---|---|
| `A` | Contacts, Favorites, Links, Documents, Desktop sichern; Temp erst nach tatsaechlichem Erfolg aller fuenf Archive bereinigen. |
| `B` | Dieselben fuenf Benutzerordner, ohne Temp. |
| `1`, `2`, `3` | Pictures, Music bzw. Videos, jeweils rekursiv und mit allen Dateiformaten. |
| `4` | LocalBookPath. |
| `5` | LocalPhotoPath und LocalPicturesPath. |
| `6`, `7` | LocalMusicPath bzw. LocalIosPath. |
| `8` | Direkte PST-/OST-Dateien aus beiden Outlook-Quellen; kein rekursives Postfachbackup. |
| `O` | B plus Pictures, Music und Videos; kein Temp, keine separate Outlook-Aktion. |
| `P` | Alle fuenf konfigurierten Cloud-Quellen. |
| `Q` | Lokale Quellen aus 4 bis 7 plus P. |
| `T` | Nur ausdruecklich freigegebenen Temp-Inhalt bereinigen, ohne vorgeschaltete Sicherung. |
| `X` | Ohne Datenaktion beenden; Logs werden trotzdem geschrieben. |

## Parameter

| Parameter | Standard / Bedeutung |
|---|---|
| `DriveLetter` | Einzelner Buchstabe, zum Beispiel `F`; Ziel `<Laufwerk>:\<BackupFolderName>`. |
| `BackupFolderName` | `Mein Backup`; einfacher Ordnername. |
| `BackupPath` | Direktes Ziel, auch UNC; nicht zusammen mit DriveLetter. Keine Laufwerks-/Freigabewurzel. |
| `RarExe` | `rar`; EXE-Pfad oder aufloesbarer Programmname. |
| `UserArchivePrefix` | `UserA`; einfacher Dateinamenpraefix fuer Benutzerordner. |
| `LocalArchivePrefix` | `Ordner`; Praefix fuer lokale Quellen. |
| `CloudArchivePrefix` | `Cloud`; Praefix fuer Cloud-Quellen. |
| `LocalBookPath` | `E:\Buch`. |
| `LocalPhotoPath` | `E:\Foto`. |
| `LocalPicturesPath` | `E:\Pics`. |
| `LocalMusicPath` | `E:\Musik`. |
| `LocalIosPath` | `E:\iOS`. |
| `OneDrivePath` | `$env:OneDrive`; bei fehlender Variable explizit angeben. |
| `DropboxPath`, `CreativeCloudPath`, `SynologyPath`, `ICloudPath` | Kein Standard; fuer P/Q konfigurieren. |
| `UserFolderPaths` | Hashtable `@{}` mit Overrides fuer Contacts, Favorites, Links, Documents, Desktop, Pictures, Music, Videos. Unbekannte Schluessel werden abgewiesen. |
| `UserTempPath` | `[IO.Path]::GetTempPath()`; nur A/T. Explizit `''` deaktiviert diesen Temp-Pfad. |
| `SecondaryTempPath` | Kein Standard; optionaler zweiter freigegebener Temp-Pfad. |
| `OutlookLocalPath` | Windows LocalApplicationData plus `Microsoft\Outlook`. |
| `OutlookDocumentsPath` | Ohne Angabe: Windows Documents plus `Outlook-Dateien`. |
| `StopOutlook` | Aus; nur Aktion 8 kann Outlook nach ShouldProcess PID-basiert zwangsweise beenden. |
| `Action` | Eine Aktion aus der Tabelle; ohne Angabe interaktives Menue. |
| `NoPause` | Keine Pause nach interaktiven Aktionen. Explizite Action-Aufrufe pausieren ohnehin nicht. |
| `LogDirectory` | `Legacy\FileOps\Logs`, neben der gemeinsamen Bibliothek. |
| `WhatIf`, `Confirm` | PowerShell-Vorschau bzw. Bestaetigung. |

## Daten- und Temp-Schutz

Jede Archivquelle erhaelt einen neuen eindeutigen Namen. RAR erstellt zuerst eine
Arbeitsdatei, prueft sie mit `rar t` und veroeffentlicht sie erst nach Exitcode 0.
Vorherige Archive werden nicht aktualisiert oder automatisch geloescht.
Quelle, Backup-Ziel und aktives Logverzeichnis duerfen nicht ueberlappen.
Junctions, symbolische Links und nicht lokal verfuegbare Cloud-Platzhalter
werden abgewiesen. Es gibt keine VSS-, ACL-/ADS- oder Stromausfallgarantie.

Aktion A bereinigt Temp nicht nach Fehlern, abgelehnten Sicherungen, Vorschauen
oder Logfehlern. Aktion T ist dagegen eine explizite Bereinigung ohne Backup.
**Loeschungen sind endgueltig, ohne Papierkorb oder Rollback.**

Jeder vom Prozessstandard abweichende Temp-Pfad braucht eine manuell angelegte
`.shell-temp-cleanup-allowed`, deren Inhalt sein kanonischer absoluter Pfad ist.
Die Markierung bleibt erhalten und ersetzt keine anderen Schutzpruefungen.
Wurzeln, Profil-/Systembereiche und Ueberlappungen mit Quellen, Backup oder Logs
werden abgewiesen. Auch nicht ausgewaehlte konfigurierte Quellpfade werden
geschuetzt und muessen pruefbar sein.

Outlook vorzugsweise selbst geordnet schliessen. `StopOutlook` kann ungespeicherte
Aenderungen verlieren. Kopien werden anhand SHA256 geprueft und versioniert
unter `<Backup>\Outlook\<Laufkennung>` abgelegt, sind aber ohne Anwendungssnapshot
nicht garantiert konsistent. Eine OST-Datei allein ersetzt kein Postfachbackup.

## Diagnose und Exitcodes

Das Log enthaelt Phasen, Pfade, Ausnahmen und native Exitcodes; die gleichnamige
CSV enthaelt `Time,Path,Phase,Status,Message`. Statuswerte sind `Success`,
`Failed`, `Skipped` und `Planned`. Bei Logfehlern versucht die Bibliothek einen
Fallback unter dem Prozess-Temp-Verzeichnis; der Lauf bleibt fehlerhaft.

| Exitcode | Bedeutung |
|---|---|
| `0` | Kein erkannter Fehler; kann uebersprungene oder geplante Aktionen enthalten. |
| `1` | Globale Voraussetzung, Zielangabe oder Abhaengigkeit verhindert den Lauf. |
| `2` | Mindestens ein Element-, Such-, Log- oder Wiederherstellungsfehler. |

`$LASTEXITCODE` sofort nach dem Aufruf lesen. Teilergebnisse und neue
Outlook-Versionsordner koennen unvollstaendig sein; CSV statt blosser
Dateiexistenz pruefen. Keine parallelen Sicherungen derselben Daten starten.

Ausfuehrliche Verfahrens- und Wiederherstellungshinweise:
[Legacy\Skript-Help.md](../../Legacy/Skript-Help.md).
Interne Funktionen: [Legacy\Folder\README.md](../../Legacy/Folder/README.md).
