# Shell-Skripte – Bedienung, Sicherheit und Wiederherstellung

Diese Hilfe beschreibt die **sieben Einstiegsskripte** unter
`Legacy\FileOps`, `Legacy\Folder` und `Utilities\Backup`.
Aktuelle Dateiverweise und Aufrufe stehen in
[FileOps\README.md](FileOps/README.md), [Folder\README.md](Folder/README.md)
und [Backup\README.md](../Utilities/Backup/README.md).
Beispiele für vorhandene Skripte werden aus `Legacy` gestartet; Zielpfade
erst anpassen und mit `-WhatIf` prüfen.

Der Backup-Einstieg liegt unter
[Utilities\Backup\Locale Backup.ps1](../Utilities/Backup/Locale%20Backup.ps1),
die Regressionstests unter [Testing\Shell.Safety.Tests.ps1](../Testing/Shell.Safety.Tests.ps1).
`Folder\Shell.Backup.ps1` enthält die gemeinsam verwendeten Backup-Hilfsfunktionen.

## Voraussetzungen und gemeinsame Bedienung

- **Windows**, Windows PowerShell **5.1** oder PowerShell **7**. Die `.ps1`-Dateien
  sind UTF-8 **mit BOM**, damit deutsche Texte auch unter 5.1 lesbar bleiben.
- Keine pauschale Administratorpflicht: erforderlich sind Leserechte für Quellen
  sowie Schreib-, Umbenennungs-, Attribut- und gegebenenfalls Löschrechte für die
  ausdrücklich ausgewählten Ziele. UNC-Zugriff braucht passende Freigaberechte.
- Für RAR/CBR: separat installiertes **WinRAR `rar.exe`**, nicht `unrar.exe`.
  Beispielpfad: `C:\Program Files\WinRAR\rar.exe`. `RarExe` akzeptiert einen
  vollständigen EXE-Pfad oder einen Anwendungsnamen aus `PATH`. Bei fehlender EXE
  startet keine Archivverarbeitung. CBZ benötigt nur die mitgelieferte
  .NET-ZIP-Unterstützung; es werden keine zusätzlichen Pakete installiert.
- `FileOps\Shell.Common.ps1` ist die gemeinsame Bibliothek. Die FileOps-Einstiege
  laden sie direkt daneben; die Folder-Einstiege verwenden
  `$PSScriptRoot\..\FileOps\Shell.Common.ps1`. Beide Verzeichnisse beim Kopieren
  in dieser Struktur erhalten. `Utilities\Backup\Locale Backup.ps1` lädt
  `Legacy\FileOps\Shell.Common.ps1` und `Legacy\Folder\Shell.Backup.ps1`
  relativ zu seinem eigenen Speicherort. Fehlende/nicht ladbare Hilfsdateien werden
  klar gemeldet und ergeben Exitcode 1.
- Skriptnamen mit Leerzeichen mit dem Aufrufoperator `&` und Anführungszeichen
  starten. Alle Zielpfade sind **literale** Dateisystempfade, keine Wildcards.
  Relative Pfade beziehen sich auf das aktuelle Arbeitsverzeichnis.
- Alle sieben Einstiegsskripte unterstützen **`-WhatIf`**, **`-Confirm`** und
  **`-LogDirectory <Pfad>`**, zusätzlich die üblichen PowerShell-Common-Parameter
  (`Verbose`, `Debug`, `ErrorAction` usw.). Fehler werden intern bewusst
  abgefangen; `-ErrorAction SilentlyContinue` ist keine Erfolgsgarantie.

```powershell
& '.\Folder\Clear Folder.ps1' -Path 'D:\Meine Ordner\Beispiel' -WhatIf
& '.\Folder\Modify Folders.ps1' -Path 'D:\Ordner A','D:\Ordner B' -Confirm
```

**Dry-run-Grenzen:** `-WhatIf` prüft Voraussetzungen, liest Verzeichnisse, prüft
Icon-Kopfzeilen und berechnet Umbenennungspläne einschließlich SHA256-Werten.
Es startet **kein RAR**, erzeugt keine ZIP/Outlook-Kopien, benennt nichts um,
ändert keine Attribute, löscht keine Nutzdaten und beendet keine Prozesse.
**Logs und Ergebnis-CSV werden trotzdem angelegt**, ohne zusätzliche
Bestätigungsabfragen. Rücksetzungsjournale und Icon-Sicherungen entstehen erst
nach bestätigter Änderung. Eine Vorschau beweist weder ausreichenden freien
Speicher noch spätere Schreibrechte, Exklusivzugriff oder Anwendungskonsistenz.

`-Confirm` fragt pro Transaktion bzw. pro Lösch-/Kopierschritt.
`-Confirm:$false` führt bestätigungspflichtige Nutzdatenänderungen ohne Nachfrage
aus; es ist **kein** Testlauf. Abgelehnte Aktionen heißen `Skipped`, Vorschauen
`Planned`, echte Änderungen `Success`, Fehler `Failed`. Übersprungene Aktionen
werden nicht als ausgeführte Erfolge gemeldet.

### Protokolle, Zusammenfassung und Exitcodes

Standard für alle vorhandenen Einstiege: `Legacy\FileOps\Logs`.
Mit `-LogDirectory 'F:\Protokolle\Shell'` umstellbar.
Laufnamen enthalten Zeit bis Millisekunden, PID und GUID. Die `.log`-Datei enthält
Phase, Pfad, vollständigen ErrorRecord/Exception, Skript-Stack sowie bei nativen
Aufrufen Argumente, stdout/stderr und Exitcode. Die gleichnamige `.csv` enthält
`Time, Path, Phase, Status, Message`; am Ende stehen die Statuszahlen.

Bei Logfehlern erfolgt ein **einmaliger** Wechsel nach
`[IO.Path]::GetTempPath()\PowerShell-Shell-Logs`. Ist auch das nicht beschreibbar,
wird nur noch auf der Konsole berichtet; der Logger ruft sich nicht rekursiv auf.
Jeder Logfehler bleibt ein Fehler des Laufs, auch bei erfolgreichem Fallback.
Ohne beschreibbares Wiederherstellungsjournal bzw. Sicherungsverzeichnis werden
Umbenennungen bzw. Icon-Änderungen verweigert. Logs können sensible Pfadnamen und
native Ausgaben enthalten: Verzeichniszugriff entsprechend beschränken.

| Code | Bedeutung |
|---|---|
| `0` | Kein erkannter Fehler; kann `Skipped`/`Planned` enthalten. **Nicht** gleichbedeutend mit „alles tatsächlich gesichert“. |
| `1` | Globale Voraussetzung, Konfiguration oder Abhängigkeit verhindert den Lauf. |
| `2` | Mindestens ein Element-, Such-, Wiederherstellungs- oder Protokollfehler. Andere unabhängige Elemente werden soweit möglich weiter verarbeitet. |

Direkt nach einem Skriptaufruf: `$LASTEXITCODE` prüfen. Für Automation zusätzlich
die CSV auf `Skipped`, `Planned` und `Failed` prüfen. Bei globalem Fehler hat
Code 1 Vorrang vor bereits erkannten Element-/Logfehlern.

### Pfadsicherheit und technische Grenzen

Wurzeln, Dateien und vorhandene Elternketten werden auf Analysepunkte geprüft.
Junctions/symbolische Links werden bei allgemeinen Verzeichnissuchen **vor** dem
Abstieg ausgeschlossen; ausdrücklich angegebene umgeleitete Wurzeln werden
verweigert. Archiv- und Temp-Quellbäume mit Analysepunkten werden komplett
abgewiesen, statt einen stillschweigend unvollständigen Erfolg zu behaupten.
Mehrfach-Hardlinks werden bei geprüften Einzeldateioperationen ebenfalls
abgewiesen. Windows-Kurzpfade (8.3) werden in Langpfade aufgelöst, damit
Schutzvergleiche nicht durch Kurz-/Langschreibweise auseinanderfallen.

Quelle und Sicherungsziel dürfen nicht identisch, ineinander enthalten oder
überlappend sein. Archivquellen dürfen auch das aktive Logverzeichnis nicht
einschließen. Unzugängliche Pfade werden nicht „auf Verdacht“ verarbeitet.

Die Prüfungen sind **keine Sandbox gegen parallele, bösartige Änderungen am
Dateisystem**. Während eines Laufs keine Ordner verschieben, Junctions austauschen
oder dieselben Dateien durch andere Programme bearbeiten lassen. Es gibt keine
globale Transaktion über mehrere Ordner, kein VSS, keine Anwendungssnapshot-,
Stromausfall-, Festplattenausfall- oder vollständige ACL/ADS-Wiederherstellungsgarantie.

## 1. Clear Folder.ps1 / 2. Clear Folders.ps1

Beide verwenden **dieselbe Implementierung**, keine separaten Symbolalgorithmen.

| Parameter | Standard / Wirkung |
|---|---|
| `Path` | Erforderliche Angabe beim Aufruf; Singular: ein Ordner, Plural: `string[]`. Positionsparameter 0; Plural akzeptiert weitere Positionsargumente. Fehlende Pfade werden als Fehler gemeldet, nicht interaktiv abgefragt. |
| `Recurse` | Nur **Clear Folders.ps1**: Stammordner und reguläre Unterordner. Standard aus. |
| `ClearFolderReadOnly` | Standard aus; entfernt zusätzlich das ReadOnly-Attribut des Ordners. Andere Ordnerattribute bleiben erhalten. |
| `RemoveDesktopIni` | Standard aus; **explizit vollständige** Löschung von `desktop.ini` statt selektiver Bearbeitung. |
| `LogDirectory` | Gemeinsam: standardmäßig `Legacy\FileOps\Logs`. |

Standardmäßig werden nur `IconResource`, `IconFile`, `IconIndex` im Abschnitt
`[.ShellClassInfo]` entfernt. Andere Einträge, Kommentare und Abschnitte bleiben
inhaltlich erhalten. Die bearbeitete INI wird als UTF-16LE mit BOM geschrieben;
vorherige Bytes und Attribute sind in der Sicherung verfügbar. Mehrere
`[.ShellClassInfo]`-Abschnitte (auch bei verschiedener Großschreibung/Leerzeichen)
werden als mehrdeutig abgewiesen.

`desktop.ico` wird nur entfernt, wenn die ursprüngliche Symbolkonfiguration
genau darauf verweist (`desktop.ico`, `.\desktop.ico` oder der entsprechende
absolute Pfad, auch mit Kurzpfad). Eine **fremde/unreferenzierte** `desktop.ico`
bleibt auch mit `-RemoveDesktopIni` erhalten.

Vor Änderungen werden beide vorhandenen Dateien und ihre Attribute sowie die
Ordnerattribute unter `Logs\Icon-Recovery-<GUID>` gesichert. Bei Folgefehlern wird
automatisch zurückgesetzt; jeder Wiederherstellungsfehler steht im Log.
Sicherungen bleiben **auch nach Erfolg** erhalten.

```powershell
& '.\Folder\Clear Folder.ps1' -Path 'D:\Comics\Band 1' -WhatIf
& '.\Folder\Clear Folders.ps1' -Path 'D:\A','D:\B' -Recurse -Confirm
# Absichtlich weitreichender: gesamte desktop.ini entfernen und Ordner-ReadOnly lösen
& '.\Folder\Clear Folder.ps1' -Path 'D:\A' -RemoveDesktopIni -ClearFolderReadOnly -Confirm
```

## 3. Modify Folder.ps1 / 4. Modify Folders.ps1

| Parameter | Standard / Wirkung |
|---|---|
| `Path` | Singular: ein Ordner. Plural: Array oder mehrere Positionsargumente. Explizit angeben, keine versteckte Pfadabfrage. |
| `Recurse` | Nur **Modify Folders.ps1**: zusätzlich reguläre Unterordner; Standard aus. |
| `LogDirectory` | Gemeinsam: standardmäßig `Legacy\FileOps\Logs`. |

Für `D:\Comics\Band 1` muss die Quelle **`D:\Comics\Band 1.ico`** existieren.
Auch jeder rekursive Unterordner benötigt seine eigene benachbarte ICO-Datei.
Eine grundlegende ICO-Kopfzeilenprüfung findet vor Änderungen statt; dies ist
keine vollständige Bilddecoder-Prüfung.

Das Skript kopiert die Quelle nach `desktop.ico`, setzt im einzigen
`[.ShellClassInfo]`-Abschnitt `IconResource=.\desktop.ico,0` und entfernt veraltete
IconFile/IconIndex-Angaben **nur dort**. Andere INI-Einstellungen bleiben
inhaltlich erhalten. Fehlender Abschnitt/fehlende INI wird angelegt.
`desktop.ico` erhält Hidden/ReadOnly, `desktop.ini` Hidden/System, der Ordner
ReadOnly. Die Quelle wird nicht gelöscht.

Vorhandene Dateien – auch ein bisher fremdes `desktop.ico` – werden vollständig
gesichert, bevor sie ersetzt werden. Rücksetzung und `Icon-Recovery-<GUID>` wie
bei Clear. Explorer aktualisiert das dargestellte Symbol möglicherweise erst
nach Aktualisieren/erneutem Öffnen; das Skript beendet Explorer nicht.

```powershell
& '.\Folder\Modify Folder.ps1' -Path 'D:\Comics\Band 1' -WhatIf
& '.\Folder\Modify Folders.ps1' -Path 'D:\Comics' -Recurse -Confirm
```

## 5. Rename Graphics.ps1

| Parameter | Standard / Wirkung |
|---|---|
| `Path` | Explizit anzugebender Bildordner, Positionsparameter 0. |
| `Recurse` | Aus; reguläre Unterordner optional einbeziehen. |
| `ProcessWithoutBy` | Boolean `$true`; `$false` verarbeitet nur ursprüngliche Namen mit `_by_`. |
| `ForceCaseChange` | Boolean `$true`; reine Groß-/Kleinschreibungsänderungen durch Zweiphasen-Umbenennung. `$false` überspringt solche Änderungen ausdrücklich. |
| `LowerWords` | `vs,x,feat,ft,und,oder,and,or,with`; Array, auch `@()` erlaubt. Vergleich ordinal und ohne Beachtung der Großschreibung. `by` bleibt unabhängig davon immer klein. |
| `Extensions` | `jpg,jpeg,png,gif,bmp,tif,tiff,webp,svg,ico,heic,heif,avif,raw,dng,cr2,nef,arw,raf,orf,rw2,pef,sr2`. Mit/ohne Punkt, auch `.JPG` gültig. Leere effektive Menge ist ein globaler Fehler. |
| `StripNumericSuffix` | **Aus**; opt-in zur früheren Entfernung eines abschließenden Unterstrich-Suffixes mit mindestens einer Ziffer und nur Buchstaben/Ziffern/Bindestrichen. |
| `LogDirectory` | Gemeinsam: standardmäßig `Legacy\FileOps\Logs`. |

Unterstriche werden zu Leerzeichen, mehrfache Leerzeichen zusammengefasst,
Wortanfänge großgeschrieben, konfigurierte Verbindungswörter klein. Die übrige
Schreibweise eines Wortes bleibt erhalten. Beispiel:
`rock_And_roll_by_artist_2024.JPG` → `Rock and Roll by Artist 2024.JPG`.
Ohne `StripNumericSuffix` bleiben sinnvolle Zahlen erhalten. Mit diesem Schalter
kann auch eine bedeutsame Jahreszahl verschwinden: nur nach Namensprüfung verwenden.

Bei Kollisionen werden ` [1]`, ` [2]` usw. angehängt. Bereits vorhandene Ziele und
im Testlauf reservierte Ziele werden berücksichtigt; es wird niemals eine
andere Datei überschrieben. Jede Datei verwendet dieselbe journalgestützte
Umbenennungstransaktion wie Comics. Der erzeugte ` by `-Text bleibt beim
erneuten Lauf klein; bereits normalisierte Namen bleiben grundsätzlich stabil.

```powershell
& '.\FileOps\Rename Graphics.ps1' -Path 'D:\Meine Bilder' -Extensions '.JPG','png' -WhatIf
& '.\FileOps\Rename Graphics.ps1' -Path 'D:\Meine Bilder' -Recurse -ProcessWithoutBy:$false -Confirm
& '.\FileOps\Rename Graphics.ps1' -Path 'D:\Import' -StripNumericSuffix -WhatIf
```

## 6. Make CBR or CBZ.ps1

| Parameter | Standard / Wirkung |
|---|---|
| `Root` | Aktuelles Arbeitsverzeichnis; verarbeitet dessen **direkte Unterordner** als getrennte Comics. |
| `DirectoryNames` | `@()` = alle direkten Unterordner; andernfalls nur exakt benannte Unterordner, ohne Wildcards, Vergleich ohne Beachtung der Großschreibung. |
| `ArchiveType` | `rar` → `.cbr`; `zip` → `.cbz`. |
| `RarExe` | `rar.exe`; nur für RAR/CBR erforderlich. |
| `Overwrite` | Aus: vorhandene Archivnamen erhalten; neuer Name `Band (1).cbz` usw. Ein Rennen um einen Zielnamen verursacht einen Fehler statt Überschreiben. An: geprüfte Ersatzdatei atomar veröffentlichen, vorherige Version als `.previous-<GUID>` behalten. |
| `NoPause` | Kompatibilitätsparameter; automatische Abschlusspausen entfallen immer. |
| `ImageExtensions` | `jpg,jpeg,png,gif,bmp,tif,tiff,webp,avif`; nur diese **direkten** Dateien werden nummeriert. Leere wirksame Liste ist ein Fehler. |
| `Cleanup` | **Aus**; nur mit explizitem Schalter werden passende Begleiter gelöscht. |
| `CleanupExtensions` | `csv,url,txt,nfo`; nur bei Cleanup wirksam, `@()` erlaubt. |
| `CleanupNamePatterns` | `thumbs.db`, `*banner*.jpg`, `hentairulesbanner.*`; PowerShell-Wildcards nur für Dateinamen; `@()` erlaubt. |
| `PreserveNames` | `ComicInfo.xml,metadata.json,metadata.opf`; vom Umbenennen/Bereinigen ausgeschlossen. XML-Dateien und `ComicInfo.xml` werden unabhängig von Cleanup-Filtern niemals bereinigt. |
| `LogDirectory` | Gemeinsam: standardmäßig `Legacy\FileOps\Logs`. |

Ablauf pro Comic:

1. Quellbaum prüfen, Analysepunkte ausschließen (Archivierung verweigert den
   gesamten betroffenen Comic). Ohne direkte Bilder keine Bereinigung.
2. Nur bei `Cleanup`: gewählte Begleiter innerhalb **dieses Comics**, gegebenenfalls
   in Unterordnern, löschen. Dateien direkt unter Root bleiben unangetastet.
   Diese expliziten Löschungen haben **keine eigene Rücksetzung**.
3. Direkte Bilder natürlich sortieren: `1,2,10`, auch beliebig lange Zahlen ohne
   Integer-Überlauf. Gleichwertige Zahlen erhalten einen deterministischen
   ordinalen Namensvergleich als Tie-Break. Namen werden `0001.ext`, `0002.ext`
   usw.; die Breite wächst bei mehr als 9999 Bildern. Metadaten behalten ihre Namen.
4. Zweiphasig umbenennen, danach den ganzen Comic **rekursiv** archivieren:
   Bilder in Unterordnern bleiben unbenannt, sind aber enthalten; ebenso Metadaten
   und nicht ausdrücklich gelöschte Begleiter, einschließlich versteckter Dateien.

Wenn eine Cleanup- oder Umbenennungsbestätigung abgelehnt wird, wird dieser Comic
nicht anschließend als vollständig verarbeitet archiviert. In der Vorschau
werden weitere geplante Schritte trotzdem gezeigt. Ein Fehler eines Comics
verhindert nicht die Bearbeitung anderer Comics.

**Archivtransaktion:** Erstellung erfolgt ausschließlich in einer eindeutigen
`.shell-stage-<GUID>.rar/.zip` neben dem Ziel. RAR muss sowohl `a` als auch **`t`**
mit Exitcode **0** beenden (auch Warncodes sind Fehler). ZIP wird nach dem
Schließen wieder geöffnet; jeder Eintrag wird vollständig gelesen und gegen
den beim Schreiben ermittelten SHA256-Inhalt geprüft. Erst danach wird
veröffentlicht. ZIP ist damit mehr als eine bloße „Datei existiert“-Prüfung.

Ein vorhandenes Archiv wird **nie vorher gelöscht**. Überschreiben verwendet
`File.Replace`; auf Dateisystemen ohne diese Unterstützung wird abgebrochen,
ohne unsicheren Delete/Move-Ersatz. Ohne Overwrite verwendet die Veröffentlichung
`File.Move` ohne Überschreiben. Bei Fehlern werden nur eigene Arbeitsdateien
bereinigt; ein fehlgeschlagenes Aufräumen wird separat gemeldet. Eine erfolgreiche
Umbenennung bleibt bei anschließendem Archivfehler bestehen; das Journal erlaubt
die ursprüngliche Namenszuordnung nachzuvollziehen.

```powershell
& '.\FileOps\Make CBR or CBZ.ps1' -Root 'D:\Comics' -ArchiveType zip -WhatIf
& '.\FileOps\Make CBR or CBZ.ps1' -Root 'D:\Comics' -DirectoryNames 'Band 1','Band 2' `
    -ArchiveType rar -RarExe 'C:\Program Files\WinRAR\rar.exe' -Overwrite -Confirm
& '.\FileOps\Make CBR or CBZ.ps1' -Root 'D:\Comics' -ArchiveType zip `
    -Cleanup -CleanupExtensions 'url' -CleanupNamePatterns 'thumbs.db' -WhatIf
```

## 7. Locale Backup.ps1

Der Einstieg liegt unter `Utilities\Backup`. Seine
[README](../Utilities/Backup/README.md) enthält die aktuelle Dateistruktur.
Die Bibliothek ist in [Folder\README.md](Folder/README.md) dokumentiert.

### Was gesichert wird – und was nicht

**Keine vollständige Windows-, System-, Benutzerprofil- oder portable
Wiederherstellungssicherung.** Gesichert werden ausschließlich die jeweils
ausgewählten Datenordner, rekursiv als neue RAR-Archive. Es fehlen insbesondere
Registry, Betriebssystem, installierte Anwendungen und nicht ausgewählte
AppData-/Profilordner. ACLs, ADS, Links, installierte Programme, Cloud-Account-
Konfigurationen und eine Bare-Metal-Wiederherstellung werden nicht zugesichert.

Windows-Benutzerordner werden über **SHGetKnownFolderPath** ermittelt, nicht aus
geratenen lokalisierten Pfadnamen. Das gilt ausdrücklich auch für **Contacts**
und **Links**. Unterstützte Umleitungen per Known-Folder-Konfiguration werden
damit gefunden; tatsächliche Reparse-Punkte bleiben aus Sicherheitsgründen
gesperrt. Verfügbarkeit und reguläre Dateien werden je ausgewählter Quelle
geprüft. Fehlende/leere ausgewählte Ordner sind sichtbare Fehler.

**Musik umfasst jetzt alle Formate und alle Unterordner**, nicht mehr nur
direkte M4A-Dateien. Outlook-PST/OST-Einzelkopien sind eine eigene Aktion 8;
O enthält diese Aktion **nicht**. Wenn eine Outlook-Datei physisch innerhalb
eines anderweitig gewählten Ordners liegt (z.B. Dokumente), wird sie von dessen
normaler rekursiver Archivierung nicht speziell herausgefiltert.

Jede Quelle erhält einen **neuen eindeutigen Archivnamen** mit Laufkennung und
GUID. Es werden keine Tagesarchive mehr mit `rar a` aktualisiert; deshalb
erscheinen früher gelöschte Dateien nicht als Altbestand eines neuen Archivs.
Frühere Archive bleiben erhalten. Erstellung/Validierung/Publizieren wie oben.
Speicherverbrauch steigt entsprechend; alte Versionen werden **nicht automatisch
gelöscht**. Archivprüfungen ersetzen keinen regelmäßig getesteten Restore.

Cloud-Backups sichern nur **lokal verfügbare Dateien**, keine garantierte
vollständige Cloud-Kopie. Online-only-/Reparse-Platzhalter werden verweigert;
zuerst außerhalb des Skripts vollständig lokal verfügbar machen.

### Aktionen

| Action | Auswahl |
|---|---|
| `A` | Contacts, Favorites, Links, Documents, Desktop sichern; **erst nach vollständigem tatsächlichem Erfolg aller fünf Archive** Temp bereinigen. Kein Cleanup bei Vorschau, Ablehnung, Backup-/Logfehler. |
| `B` | Dieselben fünf Dokument-/Benutzerordner, **ohne** Temp. |
| `1` | Known Folder Pictures. |
| `2` | Known Folder Music, vollständig. |
| `3` | Known Folder Videos. |
| `4` | LocalBookPath. |
| `5` | LocalPhotoPath und LocalPicturesPath. |
| `6` | LocalMusicPath. |
| `7` | LocalIosPath. |
| `8` | Direkte `.pst`/`.ost` aus beiden konfigurierten Outlook-Ordnern, **kein RAR nötig**. |
| `O` | B + 1 + 2 + 3; kein Temp und keine zusätzliche Outlook-Aktion. |
| `P` | Alle fünf konfigurierten Cloud-Quellen. |
| `Q` | 4 + 5 + 6 + 7 + P; nicht die Known-Folder-Benutzerdaten und nicht Outlook. |
| `T` | Explizit nur freigegebenes Temp bereinigen; **kein RAR nötig**, keine vorgeschaltete Sicherung. |
| `X` | Ohne Datenaktion beenden. |

Ohne Action erscheint das Menü, gegebenenfalls mit Laufwerksabfrage.
Mit Action ist der Aufruf nicht interaktiv bezüglich fehlender Ziele:
`BackupPath` oder `DriveLetter` muss angegeben werden. `X` benötigt kein Ziel.

### Sämtliche Parameter

| Parameter | Standard / Bedeutung |
|---|---|
| `DriveLetter` | Einzelner Buchstabe, z.B. `F`. Ziel `F:\<BackupFolderName>`. |
| `BackupFolderName` | `Mein Backup`; einfacher Ordnername, keine Pfadtraversierung/Unterpfade. |
| `BackupPath` | Optionales direktes Zielverzeichnis (auch UNC). Nicht gemeinsam mit DriveLetter. Mit BackupPath wird BackupFolderName nicht verwendet. Keine Laufwerks-/Freigabewurzel. |
| `RarExe` | `rar`; auflösbare RAR-EXE, nur für Archivaktionen. |
| `UserArchivePrefix` | `UserA`; einfacher Dateinamenpräfix. |
| `LocalArchivePrefix` | `Ordner`; einfacher Dateinamenpräfix. |
| `CloudArchivePrefix` | `Cloud`; einfacher Dateinamenpräfix. |
| `LocalBookPath` | `E:\Buch`. |
| `LocalPhotoPath` | `E:\Foto`. |
| `LocalPicturesPath` | `E:\Pics`. |
| `LocalMusicPath` | `E:\Musik`. |
| `LocalIosPath` | `E:\iOS`. |
| `OneDrivePath` | `$env:OneDrive`; fehlt die Variable, muss bei P/Q explizit konfiguriert werden. |
| `DropboxPath` | Kein geratener Standard: für P/Q explizit angeben. |
| `CreativeCloudPath` | Kein Standard; explizit angeben. |
| `SynologyPath` | Kein Standard; explizit angeben. |
| `ICloudPath` | Kein Standard; explizit angeben. |
| `UserFolderPaths` | Hashtable `@{}`; gezielte Overrides für `Contacts,Favorites,Links,Documents,Desktop,Pictures,Music,Videos`. Unbekannte Schlüssel oder leere ausgewählte Werte sind Fehler. |
| `UserTempPath` | `[IO.Path]::GetTempPath()`; nur bei A/T relevant. Leere explizite Angabe deaktiviert diesen Temp-Pfad. |
| `SecondaryTempPath` | **Kein Standard**; optionaler ausdrücklich freigegebener weiterer Temp-Pfad. Der frühere pauschale Cache-Pfad wird nicht mehr angenommen. |
| `OutlookLocalPath` | Tatsächlicher .NET-Known-Folder LocalApplicationData + `Microsoft\Outlook`. |
| `OutlookDocumentsPath` | Wenn nicht angegeben: tatsächlicher Known Folder Documents + `Outlook-Dateien`. Bei anderem Outlook-Datenspeicher explizit überschreiben. |
| `StopOutlook` | Aus; nur Aktion 8 darf damit laufende Outlook-Prozesse **PID-basiert** und nach ShouldProcess zwangsweise beenden. Niemals automatisch. |
| `Action` | Eine der obigen Aktionen; ohne Angabe interaktives Menü. |
| `NoPause` | Keine Pause nach einer interaktiven Menüaktion. Einmalige Action-Aufrufe pausieren ohnehin nicht. |
| `LogDirectory` | Gemeinsam: standardmäßig `Legacy\FileOps\Logs`. |

### Temp-Schutz

Es wird **nicht bloß deshalb gelöscht, weil ein Ordner existiert**.
Laufwerks-/Freigabewurzeln, Benutzerprofil/Eltern, Windows-, ProgramFiles- und
ProgramData-Bereiche sowie Überschneidungen mit Backup-Ziel, Quellen und aktivem
Logverzeichnis sind verboten. Das gilt in beide Richtungen für Quelle/Ziel.
Nicht auflösbare Schutzpfade verhindern Cleanup (fail-closed). Bei A/T werden
auch nicht ausgewählte bekannte Benutzerordner und konfigurierte Quellen als
Schutzbereiche herangezogen. Nicht vorhandene konfigurierbare Quellen daher
vor dem Einsatz von Cleanup korrigieren; es wird nicht geraten.

Nur der tatsächliche Prozess-Temp-Standard ist ohne zusätzliche Markierung
freigegeben. **Jeder abweichende Temp-Ordner** braucht die Datei
`.shell-temp-cleanup-allowed`, deren Inhalt exakt dessen kanonischer absoluter
Langpfad ist. Diese Markierung muss der Benutzer nach sorgfältiger Prüfung
selbst anlegen; das Skript legt sie **niemals automatisch** an. Sie ersetzt keine
der anderen Schutzprüfungen und bleibt bei Cleanup erhalten. Beispiel ausschließlich
für einen bewusst dafür eingerichteten Cache:

```powershell
# Nach manueller Kontrolle des leeren/eigens eingerichteten Cache-Ordners:
# Inhalt von D:\MeinAppCache\.shell-temp-cleanup-allowed: D:\MeinAppCache
& '..\Utilities\Backup\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action T `
    -UserTempPath 'D:\MeinAppCache' -SecondaryTempPath '' -WhatIf
```

Ein Temp-Baum mit Analysepunkten wird vor Löschbeginn abgewiesen.
Gelöscht wird danach elementweise von unten nach oben, ohne rekursiven
„ganzen Baum löschen“-Aufruf; abgelehnte/neue/restliche Dateien bleiben erhalten
und verhindern gegebenenfalls die Löschung ihres Elternordners.
**Temp-Löschungen sind endgültig, keine Papierkorb-/Rollback-Funktion.**

### Outlook und Konsistenz

Neue Kopien liegen unter
`<Backup>\Outlook\<Laufkennung-GUID>\AppData-Outlook` bzw. `Dokumente-Outlook`.
Jede Einzeldatei wird zuerst als `.partial-<GUID>` kopiert und anhand SHA256
geprüft, dann ohne Überschreiben veröffentlicht. Frühere Läufe bleiben unverändert.
Bei Teilausfall kann ein neuer Versionsordner **unvollständig** sein:
CSV/Fehlerzahl prüfen, nicht bloß Ordnerexistenz.

Keine Garantie für anwendungskonsistente PST/OST-Dateien bei laufendem Outlook.
Schreibende/sperrende Anwendungen können eine Kopie verhindern. Vorzugsweise
Outlook selbst geordnet schließen; `StopOutlook` beendet erzwungen und kann
ungespeicherte Änderungen verlieren. Eine OST-Datei allein ist kein zugesicherter
portabler Ersatz für ein Postfachbackup.

```powershell
& '..\Utilities\Backup\Locale Backup.ps1' -DriveLetter F -Action B -NoPause -WhatIf
& '..\Utilities\Backup\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action 2 `
    -UserFolderPaths @{ Music = 'D:\Meine Musik' } `
    -RarExe 'C:\Program Files\WinRAR\rar.exe' -Confirm
& '..\Utilities\Backup\Locale Backup.ps1' -BackupPath 'F:\Mein Backup' -Action 8 `
    -OutlookLocalPath 'D:\Outlook Lokal' -OutlookDocumentsPath 'D:\Outlook Archiv' -WhatIf
```

## Wiederherstellung und Fehleranalyse

1. **Nicht blind erneut starten**, wenn eine Rücksetzung fehlgeschlagen ist.
   Betroffene Ordner vor weiteren Änderungen sichern und andere Programme schließen.
2. Im Log erste Fehlerphase und ursprünglichen ErrorRecord lesen. Spätere
   Rollbackfehler ersetzen den Originalfehler nicht. RAR-Ausgabe/Exitcode helfen
   bei fehlendem Programm, gesperrten Dateien, Platzmangel und ungültigen Archiven.
3. Umbenennung: `Logs\Rename-<GUID>.csv` enthält **vor der ersten Mutation** die
   ganze Zuordnung `Original,Temporary,Final,Rollback,Current,State,Hash`.
   Nach jeder Bewegung wird der Status aktualisiert; `.csv.previous` enthält
   die vorherige Journalversion. Bei einem abrupten Prozessabbruch kann der
   aktuelle Zustand dem Journal einen Schritt voraus sein; deshalb sämtliche
   aufgezeichneten Kandidaten mit Hash/Inhalt prüfen. Niemals allein wegen eines
   vorhandenen Final-Namens annehmen, er gehöre zu dieser Originaldatei.
4. Automatische Rücksetzung bewegt nur wirklich bewegte Einträge zuerst auf
   unabhängige `.shell-rollback-<GUID>`-Namen und erst dann zurück auf Original.
   Bei manuellem Restore dieselbe kollisionsfreie Zweiphasenstrategie verwenden;
   keine fremden belegten Originalpfade überschreiben. Journal aufbewahren.
5. Icons: `Icon-Recovery-<GUID>\recovery.json` dokumentiert Ordner, ursprüngliche
   Attribute, Datei-Existenz und Sicherungsdateien. Originalbytes zurückkopieren,
   ursprünglich nicht vorhandene neu erzeugte Dateien nur nach Identitätsprüfung
   entfernen, dann gespeicherte Datei-/Ordnerattribute wiederherstellen.
6. Archivüberschreibung: `<Archiv>.previous-<GUID>` enthält die vorige Datei.
   Erst prüfen, dann bei Bedarf ausdrücklich zurückstellen. `.shell-stage-*`
   und `.partial-*` sind **keine erfolgreichen Backups**. Nicht pauschal alle
   ähnlich benannten Dateien löschen; nur dem betreffenden Lauf zugeordnete.
7. Bei „Ziel bereits belegt“, Zugriff verweigert, ReadOnly, Virenscanner-Sperre
   oder nicht unterstütztem atomarem Replace: Ursache beheben, keine
   Force-/Delete-Umgehung einbauen. Speicherplatz und Dateisystem prüfen.

## Architektur und Regressionstests

- Sieben dünne `.ps1`-Einstiegsskripte: Parameter, ShouldProcess-Kontext
  und Exitcode, einschließlich `Utilities\Backup\Locale Backup.ps1`.
  Singular/Plural der Symbolskripte sind funktional dieselbe Operation; es gibt
  keine installierten PowerShell-Aliase und keinen abweichenden Einzelalgorithmus.
- `Shell.Common.ps1`: gemeinsame sichere Protokollierung, CSV/Status, Pfad-/Link-
  Prüfung, natürliche Sortierung, native Aufrufe, Archivveröffentlichung,
  Rename-Journale, Grafikumbenennung und Icon-Transaktionen.
- `Shell.Backup.ps1`: Known-Folder-Ermittlung, Backup-Auswahl, Temp-Schutz und
  versionierte Outlook-Einzelkopien. Beide Bibliotheken sind beim Laden
  nebenwirkungsfrei (nur Funktionsdefinitionen; native Typen erst bei Bedarf).
- [Testing\Shell.Safety.Tests.ps1](../Testing/Shell.Safety.Tests.ps1):
  Pester-**3.4.0**-Regressionen mit isolierten
  `TestDrive`-Fixtures, Fehler-Injektion, echten kleinen ZIP-Fixtures, gemocktem
  RAR, Junk-PST/OST-Testdateien und Junction-Test. Kein echtes Benutzerbackup,
  kein Outlook-Stopp. Native Exitcodes werden mit einer harmlosen Kind-Shell
  geprüft. Pester 3 unter PS7 benötigt bei Ausnahmetests konkrete Fehlermeldungen
  oder explizites try/catch; die Tests berücksichtigen das.

Aus `Legacy`, jeweils unter Windows PowerShell 5.1 und PowerShell 7
(weitere Aufrufe in [Testing\README.md](../Testing/README.md)):

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script '..\Testing\Shell.Safety.Tests.ps1' -PassThru
if ($result.FailedCount) { throw "$($result.FailedCount) Shell-Regressionen fehlgeschlagen" }
```

**Bewusst geänderte unsichere Altverhalten:** kein vorheriges Archivlöschen,
keine aktualisierten Tagesarchive, keine voreilige Temp-Löschung vor Backup,
keine geratenen Standard-Benutzerordner/Cloud-Pfade, komplette Musik statt M4A-
Auswahl, kein unbedingtes Löschen von desktop.ini/desktop.ico, keine automatische
Comic-Begleiterlöschung, kein unbedingtes Abschneiden numerischer Grafik-Suffixe,
keine unbemerkte Analysepunkt-Rekursion und keine falschen Erfolgsmeldungen bei
Log-, Zielverzeichnis- oder übersprungenen Bestätigungsschritten.
