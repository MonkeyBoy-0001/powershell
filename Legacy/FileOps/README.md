# Dateioperationen

Diese Dokumentation beschreibt alle PowerShell-Skripte in `Legacy\FileOps`.
Die Beispiele werden **aus diesem Verzeichnis** gestartet. Beispielpfade vor
der Verwendung anpassen und zuerst `-WhatIf` verwenden.

## Dateien und Voraussetzungen

| Datei | Aufgabe | Aufruf |
|---|---|---|
| [Make CBR or CBZ.ps1](Make%20CBR%20or%20CBZ.ps1) | Comic-Bilder nummerieren und CBR-/CBZ-Archive erstellen. | Direkt ausfuehren. |
| [Rename Graphics.ps1](Rename%20Graphics.ps1) | Grafiknamen vereinheitlichen, ohne andere Dateien zu ueberschreiben. | Direkt ausfuehren. |
| [Shell.Common.ps1](Shell.Common.ps1) | Gemeinsame Funktionen fuer Pfade, Logs, Archive, Umbenennungen und Ordnersymbole. | Bibliothek; nicht als eigenstaendige Aufgabe starten. |

Erforderlich sind Windows, Windows PowerShell 5.1 oder PowerShell 7 und
ausreichende Rechte fuer die ausgewaehlten Dateien. Administratorrechte sind
nicht pauschal erforderlich. Beide Einstiegsskripte brauchen die hier vorhandene
`Shell.Common.ps1`. Beim Kopieren diesen Dateisatz zusammenhalten.

CBZ verwendet die .NET-ZIP-Unterstuetzung. CBR benoetigt separat installiertes
WinRAR mit `rar.exe`; `unrar.exe` reicht nicht. Ist `rar.exe` nicht in `PATH`,
den vollstaendigen Pfad mit `-RarExe` angeben. Auf dem am 21.10.2026 geprueften
Rechner war dies erforderlich.

## Gemeinsame Bedienung

Die Einstiegsskripte unterstuetzen `-WhatIf`, `-Confirm` und `-LogDirectory`.
Alle Skripte verweisen in ihrer Kommentarhilfe unter `.LINK` auf diese README.
Zum Beispiel zeigt `Get-Help '.\Rename Graphics.ps1' -Full` die Hilfe samt
README-Verweis, ohne die Umbenennung auszufuehren.
Pfadargumente sind literal; relative Pfade beziehen sich auf das aktuelle
Arbeitsverzeichnis. Wegen der Leerzeichen die Skriptnamen mit `&` und
Anfuehrungszeichen aufrufen.

`-WhatIf` liest und prueft Quellen und berechnet Plaene, fuehrt aber keine
Umbenennung, Archivierung oder Nutzdatenloeschung aus. **Logs und Ergebnis-CSV
werden trotzdem geschrieben.** Schreibrechte, Speicherplatz und ein spaeterer
exklusiver Dateizugriff sind damit nicht garantiert.

`-Confirm` fragt vor den jeweiligen Transaktionen bzw. Loeschschritten.
`-Confirm:$false` ist kein Testlauf. Die Einstiegsskripte normal aufrufen;
Dot-Sourcing fuehrt ihre Aufgabe nicht aus.

## Make CBR or CBZ.ps1

Verarbeitet die direkten Unterordner von `Root` als einzelne Comics. Direkte
Bilddateien werden natuerlich sortiert (`1`, `2`, `10`) und zweiphasig nach
`0001.ext`, `0002.ext` usw. umbenannt. Das anschliessende Archiv enthaelt den
gesamten Comic-Unterordner rekursiv, einschliesslich Metadaten, versteckter
Dateien und Bildern in tieferen Ordnern. Tiefere Bilder werden nicht umbenannt.

| Parameter | Standard | Bedeutung |
|---|---|---|
| `Root` | Aktuelles Arbeitsverzeichnis | Stamm mit direkten Comic-Unterordnern; Position 0. |
| `DirectoryNames` | `@()` | Alle direkten Unterordner; sonst nur exakt benannte Ordner, keine Wildcards. |
| `ArchiveType` | `rar` | `rar` erzeugt `.cbr`, `zip` erzeugt `.cbz`. |
| `RarExe` | `rar.exe` | EXE-Pfad oder Programmname in `PATH`; nur fuer CBR erforderlich. |
| `Overwrite` | Aus | Vorhandenes Archiv atomar ersetzen und alte Version als `.previous-<GUID>` behalten. Ohne Schalter wird ein neuer nummerierter Archivname verwendet. |
| `ImageExtensions` | `jpg,jpeg,png,gif,bmp,tif,tiff,webp,avif` | Direkte Bilder fuer die Nummerierung; leere wirksame Auswahl ist ein Fehler. |
| `Cleanup` | Aus | Explizit passende Begleitdateien vor der Nummerierung loeschen, auch in Unterordnern. |
| `CleanupExtensions` | `csv,url,txt,nfo` | Erweiterungen fuer Cleanup; `@()` erlaubt. |
| `CleanupNamePatterns` | `thumbs.db`, `*banner*.jpg`, `hentairulesbanner.*` | Dateinamenmuster fuer Cleanup; `@()` erlaubt. |
| `PreserveNames` | `ComicInfo.xml,metadata.json,metadata.opf` | Vom Umbenennen und Bereinigen ausgenommene Namen. XML-Dateien werden niemals bereinigt. |
| `NoPause` | Aus | Kompatibilitaetsparameter; es gibt ohnehin keine automatische Abschlusspause. |
| `LogDirectory` | `Logs` neben `Shell.Common.ps1` | Textlogs, Ergebnis-CSV und Wiederherstellungsjournale. |

```powershell
# Vorschau ohne WinRAR
& '.\Make CBR or CBZ.ps1' -Root 'D:\Comics' -ArchiveType zip -WhatIf

# Ausgewaehlte Comics nach Bestaetigung verarbeiten
& '.\Make CBR or CBZ.ps1' -Root 'D:\Comics' -DirectoryNames 'Band 1','Band 2' `
    -ArchiveType rar -RarExe 'C:\Program Files\WinRAR\rar.exe' -Confirm
$LASTEXITCODE

# Nur Vorschau einer ausdruecklichen Bereinigung
& '.\Make CBR or CBZ.ps1' -Root 'D:\Comics' -ArchiveType zip `
    -Cleanup -CleanupExtensions 'url' -CleanupNamePatterns 'thumbs.db' -WhatIf
```

Ohne direkte Bilder wird ein Comic abgewiesen. Ohne `Cleanup` werden keine
Begleitdateien geloescht. Cleanup-Loeschungen sind endgueltig und haben keinen
eigenen Rollback. Eine abgelehnte Bereinigung oder Umbenennung verhindert die
anschliessende Archivierung dieses Comics; im Testlauf werden weitere Schritte
weiterhin als Vorschau angezeigt.

Archive entstehen zuerst als eindeutige Arbeitsdateien neben dem Ziel. RAR muss
Erstellung und Integritaetstest mit Exitcode 0 beenden. ZIP-Eintraege werden nach
dem Schreiben erneut gelesen und mit SHA256 geprueft. Erst danach wird das Archiv
veroeffentlicht. Ein spaeterer Archivfehler setzt eine bereits erfolgreiche
Umbenennung nicht zurueck; dafuer bleibt das Umbenennungsjournal erhalten.

## Rename Graphics.ps1

Ersetzt Unterstriche durch Leerzeichen, fasst Leerzeichen zusammen und schreibt
Wortanfaenge gross. Konfigurierte Verbindungswoerter sowie `by` bleiben klein.
Die uebrige Schreibweise bleibt erhalten. Beispiel:
`rock_And_roll_by_artist_2024.JPG` wird `Rock and Roll by Artist 2024.JPG`.

| Parameter | Standard | Bedeutung |
|---|---|---|
| `Path` | Kein Standard | Bildordner explizit angeben; Position 0. |
| `Recurse` | Aus | Regulaere Unterordner einbeziehen. |
| `ProcessWithoutBy` | `$true` | Bei `$false` nur urspruengliche Namen mit `_by_` verarbeiten. |
| `ForceCaseChange` | `$true` | Auch reine Gross-/Kleinschreibungsunterschiede umbenennen. |
| `LowerWords` | `vs,x,feat,ft,und,oder,and,or,with` | Kleinzuschreibende Woerter; `@()` erlaubt, `by` bleibt immer klein. |
| `Extensions` | Siehe unten | Grafik-Erweiterungen, ohne Beachtung der Grossschreibung, mit oder ohne Punkt. |
| `StripNumericSuffix` | Aus | Abschliessendes Unterstrich-Suffix mit mindestens einer Ziffer und nur Buchstaben/Ziffern/Bindestrichen entfernen. Kann auch Jahreszahlen entfernen. |
| `LogDirectory` | `Logs` neben `Shell.Common.ps1` | Logs, CSV und Journale. |

Standard-Erweiterungen:
`jpg,jpeg,png,gif,bmp,tif,tiff,webp,svg,ico,heic,heif,avif,raw,dng,cr2,nef,arw,raf,orf,rw2,pef,sr2`.
Eine leere wirksame Liste wird abgewiesen.

```powershell
& '.\Rename Graphics.ps1' -Path 'D:\Meine Bilder' -Recurse -WhatIf
& '.\Rename Graphics.ps1' -Path 'D:\Meine Bilder' -Extensions '.JPG','png' -Confirm
& '.\Rename Graphics.ps1' -Path 'D:\Import' -ProcessWithoutBy:$false `
    -ForceCaseChange:$false -WhatIf
```

Bei Namenskollisionen werden ` [1]`, ` [2]` usw. angehaengt. Vorhandene Dateien
werden nicht ueberschrieben. Jede Umbenennung verwendet temporaere Namen und
ein persistentes Journal; bei Fehlern wird eine Ruecksetzung versucht.

## Shell.Common.ps1

Dot-Sourcing definiert Funktionen, ohne die Dateioperationen zu starten:

```powershell
. '.\Shell.Common.ps1'
```

| Funktionsbereich | Wichtige Funktionen |
|---|---|
| Pfade und Dateisuche | `Get-SafePath`, `Test-PathOverlap`, `Assert-SeparatePaths`, `Get-SafeTree` |
| Laufsteuerung und Diagnose | `New-ShellContext`, `Invoke-ShellEntry`, `Write-ShellLog`, `Add-ShellResult`, `Confirm-ShellOperation`, `Complete-ShellRun` |
| Archive und native Prozesse | `Resolve-RarExecutable`, `Invoke-ShellNative`, `New-SafeArchive`, `New-ZipStage`, `Test-ZipStage`, `Publish-ShellFile` |
| Umbenennung | `Invoke-GraphicsRename`, `Invoke-ComicProcessing`, `Invoke-RenameTransaction`, `Save-RenameJournal`, `Undo-SequentialRename` |
| Ordnersymbole | `Invoke-FolderIcons`, `Invoke-IconTransaction`, `Get-IconIniPlan`, `Set-ShellAttributes` |

Die Funktionen sind interne Bausteine, kein eigenstaendiger CLI-Einstieg.
Mutierende Funktionen erwarten einen passenden Laufkontext mit
ShouldProcess-Unterstuetzung. Im Normalfall die Einstiegsskripte verwenden.
Native Windows-Typen werden erst bei Bedarf durch `Initialize-ShellNative` geladen.

## Logs, Fehler und Wiederherstellung

Standardablage ist **`Legacy\FileOps\Logs`**. Laufnamen enthalten Zeitstempel, PID und GUID.
Die Ergebnis-CSV enthaelt `Time,Path,Phase,Status,Message`.

| Wert | Bedeutung |
|---|---|
| Status `Success` / `Failed` | Ausgefuehrte erfolgreiche Aktion / erkannter Fehler. |
| Status `Skipped` / `Planned` | Nicht ausgefuehrt / nur vorgeschlagen durch `-WhatIf`. |
| Exitcode `0` | Kein erkannter Fehler; kann uebersprungene oder nur geplante Aktionen enthalten. |
| Exitcode `1` | Globale Voraussetzung oder Abhaengigkeit fehlt. |
| Exitcode `2` | Element-, Such-, Wiederherstellungs- oder Protokollfehler. |

Bei Logfehlern wird einmalig auf
`[IO.Path]::GetTempPath()\PowerShell-Shell-Logs` ausgewichen, danach notfalls nur
auf die Konsole. Ein Logfehler bleibt ein Fehler des Laufs.

`Rename-<GUID>.csv` enthaelt Original-, temporaere, finale und Rollback-Pfade,
aktuellen Zustand und Hash. Nach fehlgeschlagenem Rollback nicht blind erneut
starten: Dateien anhand Journal und Inhalt zuordnen und keine fremden Ziele
ueberschreiben. `.previous-<GUID>` enthaelt gegebenenfalls ein altes Archiv.
Arbeitsdateien sind keine erfolgreichen Sicherungen.

Junctions und symbolische Links werden nicht verfolgt; Archive mit solchen
Eintraegen werden abgewiesen. Gepruefte Einzeldateioperationen verweigern
mehrfache Hardlinks. Quellen duerfen nicht mit Archivziel oder aktivem Logordner
ueberlappen. Keine parallelen Veraenderungen derselben Dateien vornehmen.
Es gibt keine globale Transaktion, VSS- oder vollstaendige ACL-/ADS-Sicherung.

## Weitere Dokumentation

[Skript-Help.md](../Skript-Help.md) enthaelt ausfuehrliche Hintergrundinformationen.
Die wiederhergestellte Suite liegt unter
[Testing\Shell.Safety.Tests.ps1](../../Testing/Shell.Safety.Tests.ps1);
Aufrufe und Voraussetzungen stehen in [Testing\README.md](../../Testing/README.md).
Die Ordnersymbol-Einstiege und die Backup-Bibliothek sind in
[Legacy\Folder\README.md](../Folder/README.md) dokumentiert.
