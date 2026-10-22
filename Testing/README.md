# Regressionstests fuer Dateioperationen, Backups und VS Code

[Shell.Safety.Tests.ps1](Shell.Safety.Tests.ps1) prueft die beiden gemeinsamen
Bibliotheken und alle sieben zugehoerigen Einstiegsskripte. Dies ist eine
Pester-Testsuite, kein auszufuehrendes Backup- oder Bereinigungsskript.

[VSCode.Workspaces.Tests.ps1](VSCode.Workspaces.Tests.ps1) prueft separat die
[portable VS-Code-Einrichtung](../Utilities/VSCode/README.md). Diese Suite
benoetigt zusaetzlich ein installiertes `pwsh.exe`, aber kein VS Code und
keinen Marketplace-Zugriff. Die Installations-CLI wird gemockt.

## Voraussetzungen und Dateistruktur

Windows, Windows PowerShell 5.1 oder PowerShell 7 sowie **Pester 3.4.0**.
Andere Pester-Hauptversionen werden wegen unterschiedlicher Mock-/Should-Syntax
nicht zugesichert. Schreibrechte fuer temporaere TestDrive-Fixtures und
Unterstuetzung fuer NTFS-Junctions/Hardlinks werden benoetigt.

Die Suite ermittelt den Workspace relativ zu ihrem eigenen Speicherort:

| Bereich | Dateien und Dokumentation |
|---|---|
| Dateioperationen | [FileOps\README.md](../Legacy/FileOps/README.md), [Shell.Common.ps1](../Legacy/FileOps/Shell.Common.ps1) |
| Ordnersymbole und Backup-Helfer | [Folder\README.md](../Legacy/Folder/README.md), [Shell.Backup.ps1](../Legacy/Folder/Shell.Backup.ps1) |
| Backup-Einstieg | [Backup\README.md](../Utilities/Backup/README.md), [Locale Backup.ps1](../Utilities/Backup/Locale%20Backup.ps1) |
| Winget-Tests | [Winget\Tests\README.md](../Utilities/Winget/Tests/README.md) |
| VS-Code-Einrichtung | [Initialize-VSCodeWorkspaces.ps1](../Utilities/VSCode/Initialize-VSCodeWorkspaces.ps1), [README.md](../Utilities/VSCode/README.md) |

Die Verzeichnisse `Testing`, `Legacy` und `Utilities` in dieser Struktur
erhalten. Kein RAR-Programm, keine installierten Anwendungen, keine echten
PST-/OST-Dateien und keine Netzwerkdownloads sind fuer die Suite erforderlich.

## Aufrufe

Aus **diesem Testing-Verzeichnis**, jeweils in einem neuen Prozess:

```powershell
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script .\Shell.Safety.Tests.ps1 -EnableExit"
$LASTEXITCODE

pwsh.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script .\Shell.Safety.Tests.ps1 -EnableExit"
$LASTEXITCODE
```

Interaktiv mit Ergebnisobjekt:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script '.\Shell.Safety.Tests.ps1' -PassThru
$result | Select-Object TotalCount, PassedCount, FailedCount, SkippedCount
$result.TestResult | Where-Object { -not $_.Passed } |
    Select-Object Describe, Name, FailureMessage, StackTrace
if ($result.FailedCount) { throw "$($result.FailedCount) Tests fehlgeschlagen." }
```

Alle fuenf Suiten aus dem **Workspace-Stamm** ausfuehren:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script @(
    '.\Testing\Shell.Safety.Tests.ps1'
    '.\Testing\VSCode.Workspaces.Tests.ps1'
    '.\Utilities\Winget\Tests'
) -PassThru
if ($result.FailedCount) { throw "$($result.FailedCount) Tests fehlgeschlagen." }
```

Nur die VS-Code-Suite aus dem **Workspace-Stamm**:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script '.\Testing\VSCode.Workspaces.Tests.ps1' -PassThru
if ($result.FailedCount) { throw "$($result.FailedCount) Tests fehlgeschlagen." }
```

Diese Suite prueft generierte JSON-Dateien und Ordner, passende Themes,
Erweiterungsempfehlungen und Installationsaufrufe, Schutz vorhandener Dateien,
bytegenaue Sicherungen, Fehlerberichte, Pfadablehnungen, Snippets und eine
tatsaechlich ausgefuehrte reine Syntaxaufgabe. Die Native-CLI-Tests verwenden
nur harmlose `cmd.exe`-Ausgaben und Exitcodes. Die vom Setup erzeugten
PowerShell-Beispieltests benoetigen hingegen **Pester 5**; die Setup-Tests
selbst weiterhin **Pester 3.4.0**.

Pester 3.4.0 hat keinen `-Show`-Parameter. Die Suite nicht direkt mit `&`
starten. `Get-Help '.\Shell.Safety.Tests.ps1' -Full` zeigt die Kurzbeschreibung
und den README-Verweis, ohne die Tests auszufuehren.

## Abdeckung und Isolation

Die folgenden Punkte betreffen `Shell.Safety.Tests.ps1`:

- HashSets, Grafiknamen, Kollisionen, Vorschau und natuerliche Sortierung.
- Zweiphasige Umbenennung, persistente Journale und injizierte Rollbackfehler.
- Echte kleine ZIP-Archive mit SHA256, atomare Veroeffentlichung und Erhaltung
  vorhandener Archive bei Fehlern.
- Gemockte RAR-Erstellung/-Pruefung sowie native Ausgabe/Exitcodes einer
  harmlosen Windows-PowerShell-Kindinstanz.
- Ordnersymbole, selektive INI-Bearbeitung, Sicherungen und Attribut-Rollback.
- Pfadueberlappungen, gesperrte Schutzbereiche, Junctions, Hardlinks und
  explizit freigegebene temporaere Testverzeichnisse.
- Backup-Auswahl, eindeutige Versionen, Erfolgsschranke vor Temp-Bereinigung
  sowie Kopien synthetischer PST-/OST-Fixtures ohne Outlook-Stopp.
- Comic-Metadaten, Cleanup-Filter, unabhaengige Fehler und alle sieben
  Einstiegsskripte mit isolierten `-WhatIf`-Aufrufen.
- Logs, Fallback, Exitcodes, fehlende Abhaengigkeiten und Dot-Sourcing.

Die Suite erstellt und veraendert ausschliesslich ihre TestDrive-Fixtures.
Reale System-/Profilpfade werden bei Schutztests nur auf Ablehnung geprueft,
nicht bereinigt. Es werden keine echten Benutzerbackups, Installationen,
Outlook-Prozessstopps oder RAR-Installationen ausgefuehrt.

Ein erfolgreiches Ergebnis ist kein Nachweis fuer reale Installationszustaende,
Herstellerdownloads, freien Speicher, Rechte auf fremden Zielen oder
Anwendungskonsistenz. Vor produktiven Dateioperationen die jeweiligen Quellen
und Ziele mit `-WhatIf` pruefen; Archive regelmaessig testweise wiederherstellen.
