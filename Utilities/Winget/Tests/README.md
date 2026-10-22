# Regressionstests fuer die Anwendungsverwaltung

Dieses Verzeichnis enthaelt alle drei Pester-Testsuiten der gemeinsamen
Installations-/Update-Bibliothek. Die Tests sind fuer Entwicklung und Pflege
gedacht, nicht fuer normale Installationslaeufe.

| Testsuite | Quellcode |
|---|---|
| Katalog und Vorpruefung | [Application-Preflight.Tests.ps1](Application-Preflight.Tests.ps1) |
| Installation und Konfiguration | [Install-Applications.Tests.ps1](Install-Applications.Tests.ps1) |
| Versionsbegrenzte Updates | [Update-Applications.Tests.ps1](Update-Applications.Tests.ps1) |

Bedienung der produktiven Skripte: [Winget\README.md](../README.md).
`Get-Help '.\Application-Preflight.Tests.ps1' -Full` zeigt die Kurzbeschreibung
und den README-Verweis, ohne Tests auszufuehren.

## Voraussetzungen und Abhaengigkeiten

- Windows mit Windows PowerShell 5.1 oder PowerShell 7.
- **Pester 3.4.0**. Die Tests verwenden dessen `Should Be`-/Mock-Syntax;
  Kompatibilitaet mit anderen Hauptversionen wird nicht zugesichert.
- Im Elternverzeichnis: `Application-Management.ps1`,
  `Application-VersionPolicy.ps1`, `Application-VersionPolicies.psd1`,
  `Install-Applications.ps1` und `Update-Applications.ps1`.
- Schreibrechte fuer Pesters temporaeres `TestDrive` und die dortigen Fixtures.

Pester-Verfuegbarkeit pruefen:

```powershell
Get-Module -ListAvailable Pester
Import-Module Pester -RequiredVersion 3.4.0
```

Die Tests laden die gemeinsame Bibliothek, nicht die echten
Installationseinstiege. Paketaktionen und Netzwerkdownloads werden ersetzt.
Administratorrechte und ein echter winget-Installationslauf sind nicht noetig.

## Alle Tests ausfuehren

Die folgenden Befehle werden **aus diesem Tests-Verzeichnis** gestartet.
Eine neue Sitzung pro Engine vermeidet uebernommenen Funktions-/Mock-Zustand.

```powershell
# Windows PowerShell 5.1
powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script . -EnableExit"
$LASTEXITCODE

# PowerShell 7
pwsh.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester -Script . -EnableExit"
$LASTEXITCODE
```

`-EnableExit` liefert dem Kindprozess einen fehlerhaften Exitcode bei
fehlgeschlagenen Tests. Fuer eine interaktive Ergebnisanalyse stattdessen:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script . -PassThru
$result | Select-Object TotalCount, PassedCount, FailedCount, SkippedCount
$result.TestResult | Where-Object { -not $_.Passed } |
    Select-Object Describe, Name, FailureMessage, StackTrace
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Regressionstests fehlgeschlagen."
}
```

Pester 3.4.0 hat keinen `Invoke-Pester -Show`-Parameter.
Die Testdateien nicht direkt mit `&` starten; der Pester-Runner stellt
`Describe`, `It`, `Mock` und `TestDrive` bereit.

## Application-Preflight.Tests.ps1

Prueft den gemeinsamen Katalog und die lesende Planung beider Betriebsarten:

- 36 eindeutige Pakete in den Gruppen 20/7/9 sowie gemeinsame Sprachoptionen.
- Vollstaendige Vorschau vor dem ersten Update.
- Lesende `list`-/`show`-Auswertung, unbekannte Versionen, fehlgeschlagene
  Abfragen, mehrdeutige Tabellen und Installer-Auswahl.
- Fehlende/ungueltige Ziele, EXE-Zuordnung und uebersprungene fehlende Pakete.
- Erneute Zustandspruefung zwischen Vorschau und Ausfuehrung.
- Erhaltung lokaler Rufus-, KeePassXC-, KeePass- und LibreOffice-Einstellungen.
- Blockieren laufender Anwendungen, fremder Profile und Konfigurationskonflikte.
- Beide CheckOnly-Modi ohne Elevation, Paketmutation, Backup oder Sprachdownload.

```powershell
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester -Script '.\Application-Preflight.Tests.ps1'
```

## Install-Applications.Tests.ps1

Prueft Installation und Isolation einzelner Paketfehler:

- Optionale Installer-, Ziel-, Sprach- und Versionsargumente.
- Sortierung, exakte ID-Auswahl, deaktivierte Eintraege und doppelte IDs.
- Fortsetzung nach Paketfehlern sowie EXE-/Konfigurationspruefungen.
- CLIP-STUDIO-Versions-Pin und Erhaltung vorhandener Konfiguration.
- KeePass-Vorpruefung, synthetisches deutsches Spracharchiv und Hash-Ablehnung.
- LibreOffice-Profilumleitung und Erhaltung anderer Bootstrap-Einstellungen.
- Log-Fallback, CSV-Ergebnisliste, fehlende Administratorrechte und fehlendes winget.
- Native Standard-/Fehlerausgabe und echte Prozess-Exitcodes.

```powershell
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester -Script '.\Install-Applications.Tests.ps1'
```

Der native Prozess-Test ersetzt `winget` durch eine harmlose Kindinstanz von
`cmd.exe`, die Text ausgibt und definierte Exitcodes liefert. Der Sprachtest
erzeugt ein synthetisches ZIP; erwartete Metadaten/Hashes werden nur im Test
gemockt. Es wird kein echtes KeePass-Sprachpaket heruntergeladen.

## Update-Applications.Tests.ps1

Prueft insbesondere die Versionsgrenzen:

- Hoechster stabiler Patch innerhalb der lizenzierten Reihe statt neuester
  unbegrenzter Version; numerische statt alphabetischer Sortierung.
- Ausschluss von Vorabversionen und fremden Reihen.
- Kein Upgrade fuer bereits aktuelle erlaubte Versionen.
- Kein automatisches Downgrade einer hoeheren unzulaessigen Version.
- Abbruch fuer unbekannte/mehrdeutige Versionen, Quellenfehler und fehlende Regeln.
- Exakte Vorgaben, konflikthafte Regelkombinationen und ungueltige Wildcards.
- Versionsvergleich nach Upgrade und Fortsetzung fuer unabhaengige Pakete.
- Gemeinsamer Versionsregelverweis von Installer und Updater.

```powershell
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester -Script '.\Update-Applications.Tests.ps1'
```

## Seiteneffekte, Aussagekraft und Pflege

Die Tests schreiben kleine Dateien, Verzeichnisse, Logs, CSV, Backups und
synthetische Archive in isolierte TestDrive-Fixtures. Sie installieren keine
Anwendungen, aktualisieren keine echten Pakete und veraendern keine
produktiven Programmkonfigurationen.

Ein gruenes Ergebnis beweist die getestete Logik, nicht die aktuelle
Verfuegbarkeit von Herstellerdownloads, realen Manifesten, Installern,
Sprachdateien oder den Zustand des eigenen Rechners. Dafuer zuerst die
Einstiegsskripte mit `-CheckOnly` verwenden; echte Installer nur auf einem
geeigneten Testsystem erproben.

Pester 3 kann unfiltrierte Mocks innerhalb eines Describe-Blocks weiterverwenden.
Bestehende BeforeEach-Initialisierung, Parameterfilter und Reihenfolge bewusst
beibehalten. Bei Aenderungen an Katalog, Versionsregeln oder Konfigurationsschutz
die betreffenden Regressionen und die Dokumentation im Elternverzeichnis
gemeinsam aktualisieren.

Diese Suiten decken ausschliesslich `Utilities\Winget` ab. Dateioperationen,
Ordnersymbole und Backups werden separat durch
[Testing\Shell.Safety.Tests.ps1](../../../Testing/Shell.Safety.Tests.ps1)
abgedeckt; siehe [Testing\README.md](../../../Testing/README.md).
