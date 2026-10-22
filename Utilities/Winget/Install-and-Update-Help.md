# Benutzerhilfe: Anwendungen installieren und aktualisieren

Diese Hilfe beschreibt `Install-Applications.ps1` und `Update-Applications.ps1`
einschliesslich ihrer Konfiguration, Dateien, Installationsziele, Versionsgrenzen
und Fehlerbehandlung. Stand: **10.09.2026**.

**Wichtig:** Ohne `-CheckOnly` fuehren beide Skripte echte Systemaenderungen aus.
Mit `-CheckOnly` pruefen sie nur lesend und schreiben Logs/CSV. Das ist keine
Ausfuehrungsprobe des Installers. Sie sind keine vollstaendigen Backup-,
Deinstallations- oder Umzugswerkzeuge.

## Inhalt

- [1. Welches Skript brauche ich?](#1-welches-skript-brauche-ich)
- [2. Dateien und Verzeichnisstruktur](#2-dateien-und-verzeichnisstruktur)
- [3. Voraussetzungen und sicherer Start](#3-voraussetzungen-und-sicherer-start)
- [4. Aufrufe und Parameter](#4-aufrufe-und-parameter)
- [5. Installationsziele und Anwendungsauswahl](#5-installationsziele-und-anwendungsauswahl)
- [6. Ablauf der Installation](#6-ablauf-der-installation)
- [7. Ablauf der Updates](#7-ablauf-der-updates)
- [8. Anwendungen konfigurieren](#8-anwendungen-konfigurieren)
- [9. Gemeinsame Versionsvorgaben](#9-gemeinsame-versionsvorgaben)
- [10. Sprache und lokale Konfiguration](#10-sprache-und-lokale-konfiguration)
- [11. Protokolle, Ergebnisse und Rueckgabecodes](#11-protokolle-ergebnisse-und-rueckgabecodes)
- [12. Fehler beheben und sicher wiederholen](#12-fehler-beheben-und-sicher-wiederholen)
- [13. Pflege und weiterfuehrende Informationen](#13-pflege-und-weiterfuehrende-informationen)

## 1. Welches Skript brauche ich?

| Aufgabe | Skript / Vorgehen |
|---|---|
| Konfigurierte Anwendungen erstmals installieren | `Install-Applications.ps1` |
| Einzelne Anwendung erneut verarbeiten | `Install-Applications.ps1 -ApplicationId '<exakte ID>'` |
| Konfiguration und geplante Installation ohne Installation pruefen | `Install-Applications.ps1 -CheckOnly` |
| Verfuegbare Updates nur auflisten | `Update-Applications.ps1 -CheckOnly` |
| Installationsziele fuer Werkzeuge festlegen | Gleiche Zielparameter bei Installation und Updates verwenden. |
| Vorhandene konfigurierte Anwendungen aktualisieren | `Update-Applications.ps1` |
| CLIP STUDIO PAINT innerhalb der lizenzierten Reihe 5.0.x aktualisieren | Update-Skript; gemeinsame Versionsvorgabe beachten. |
| LibreOffice unter Erhaltung des lokalen Profils aktualisieren | `Update-Applications.ps1 -ApplicationId 'TheDocumentFoundation.LibreOffice'` |
| Bestehende Programme in ein anderes Verzeichnis verschieben | Nicht automatisch unterstuetzt; vorher sichern und gezielt migrieren. |

Beide Skripte verwenden **denselben Katalog mit 36 Paketen** aus
`Get-ApplicationGroups` in `Application-Management.ps1`. Neue Eintraege,
Deaktivierung, Sprache, Installer, Ziele und lokale Konfiguration gelten damit
auch fuer Updates. Der Updater installiert fehlende Anwendungen nicht.

## 2. Dateien und Verzeichnisstruktur

Die fuenf zur Ausfuehrung gehoerenden Dateien im Verzeichnis `Winget` zusammenhalten:

```text
Winget\
  Install-Applications.ps1
  Update-Applications.ps1
  Application-Management.ps1
  Application-VersionPolicy.ps1
  Application-VersionPolicies.psd1
  Install-and-Update-Help.md
  README.md
  Tests\
    Application-Preflight.Tests.ps1
    Install-Applications.Tests.ps1
    Update-Applications.Tests.ps1
  Logs\                              wird bei Bedarf erzeugt
```

| Datei / Verzeichnis | Funktion | Fuer den normalen Lauf erforderlich? |
|---|---|---|
| `Install-Applications.ps1` | Einstieg und Parameter fuer Installation oder Installationspruefung. | Fuer Installationen. |
| `Update-Applications.ps1` | Einstieg und Parameter fuer Updates oder Update-Vorschau. | Fuer Updates. |
| `Application-Management.ps1` | Gemeinsamer Katalog, Pruefungen, Vorschau, Ausfuehrung, Konfigurationsschutz und Logs. Laden definiert Funktionen, startet keine Installation. | Ja, fuer beide Skripte. |
| `Application-VersionPolicy.ps1` | Gemeinsame Funktion `Resolve-ApplicationVersionPolicy`; liest und validiert benannte Versionsregeln. Nicht separat starten. | Ja, fuer beide Skripte. |
| `Application-VersionPolicies.psd1` | Zentrale Daten fuer CLIP STUDIO PAINT und KeePass; keine auszufuehrende Anwendung. | Ja, fuer die konfigurierten Regelverweise. |
| `Install-and-Update-Help.md` | Diese gemeinsame Benutzerhilfe. | Nein. |
| [README.md](README.md) | Einstieg, Dateiverweise, technische Pruefdaten und bekannte Grenzen. | Nein. |
| `Tests\*.Tests.ps1` | Pester-Regressionstests ohne echte Paketinstallationen. | Nein; nur zur Pflege. |
| `Logs\` | Standardablage der Protokolle und CSV-Ergebnisse beider Skripte. | Muss beschreibbar sein oder angelegt werden koennen. |

Die Skripte ermitteln Hilfsdateien und Standard-Logverzeichnisse relativ zu
ihrem eigenen Speicherort (`$PSScriptRoot`), nicht relativ zum Installationsziel.
Beim Kopieren auf einen anderen Rechner nicht nur die beiden Hauptskripte kopieren.
Der KeePass-Sprachdownload verwendet im Normalbetrieb eine kurzlebige ZIP-Datei
im aktuellen Logverzeichnis; Sicherungsdateien liegen beim jeweiligen Programm.
In `-CheckOnly` gibt es weder diesen Download noch Konfigurationssicherungen.

## 3. Voraussetzungen und sicherer Start

| Voraussetzung | Bedeutung |
|---|---|
| Windows mit Windows PowerShell 5.1 oder PowerShell 7 | Die Skripte setzen mindestens PowerShell 5.1 voraus und verwenden Windows-Funktionen. |
| Als Administrator gestartete PowerShell | Nur fuer echte Installation/Updates erforderlich, nicht fuer `-CheckOnly`. |
| Funktionsfaehiges `winget` | Bestandteil des Microsoft App Installers; im Suchpfad bzw. per App-Ausfuehrungsalias erreichbar. |
| Unterstuetzung der verwendeten winget-Optionen | Dazu gehoeren `install`, `upgrade`, `show --versions`, `list` und fuer Installations-Pins `pin add --version`. Veraltetes winget bei Optionsfehlern aktualisieren. |
| Internetzugang | Zugriff auf die winget-Quelle, Herstellerdownloads und fuer KeePass auf SourceForge. |
| Genuegend Speicher und Schreibrechte | Fuer Programme, Downloads, Profile, Sicherungen und Logs. |
| Verfuegbare Werkzeugziele | Standardmaessig `C:\Tools` und `D:\Tools`; ein fehlendes Laufwerk wird nicht automatisch ersetzt. |
| Eigene Lizenzberechtigungen | Die Skripte akzeptieren Paketvereinbarungen, erwerben aber keine Lizenzen und aktivieren keine kommerzielle Software. |

Vorher Daten und Einstellungen wichtiger Anwendungen sichern und betroffene
Programme schliessen. Insbesondere darf bei der KeePass-Verarbeitung keine
KeePass-Instanz laufen. Keine parallelen Skript-, winget- oder Hersteller-Updates
derselben Anwendung starten.

### Schrittweise starten

Fuer eine erste `-CheckOnly`-Pruefung reicht eine normale PowerShell.
Fuer Installation/Updates mit **Als Administrator ausfuehren** oeffnen.
Danach zum tatsaechlichen Skriptverzeichnis wechseln:

```powershell
Set-Location 'C:\Pfad\zum\Repository\Winget'
Get-Command winget
winget --version
Get-Help .\Install-Applications.ps1 -Full
Get-Help .\Update-Applications.ps1 -Full
```

Nur wenn die lokale Ausfuehrungsrichtlinie das Starten verhindert und eine
entsprechende Aenderung erlaubt ist, kann sie fuer diesen Prozess gesetzt werden:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Falls die Dateien aus dem Internet stammen, nach Pruefung ihrer Herkunft die
Windows-Dateisperre entfernen:

```powershell
$files = @(
    '.\Install-Applications.ps1'
    '.\Update-Applications.ps1'
    '.\Application-Management.ps1'
    '.\Application-VersionPolicy.ps1'
    '.\Application-VersionPolicies.psd1'
)
$files | ForEach-Object { Unblock-File -LiteralPath $_ }
```

Unternehmensrichtlinien nicht umgehen. Es sind keine permanenten
PowerShell-Umgebungsvariablen erforderlich. Ist `Get-Command winget` nicht
erfolgreich, App Installer bzw. App-Ausfuehrungsalias korrigieren, statt einen
unbekannten Ordner in `PATH` einzutragen.

Die Hauptskripte normal mit `.\...ps1` oder `&` aufrufen, **nicht dot-sourcen**.
Sie besitzen einen ausfuehrenden Hauptteil und beenden ihn mit einem Exitcode.

## 4. Aufrufe und Parameter

### Installation

```powershell
.\Install-Applications.ps1
$LASTEXITCODE
```

| Parameter | Typ | Standard | Wirkung |
|---|---|---|---|
| `-InstalledToolsRoot` | Zeichenfolge | `C:\Tools` | Absolutes Windows-Wurzelverzeichnis der installierten Werkzeuge. |
| `-PortableToolsRoot` | Zeichenfolge | `D:\Tools` | Absolutes Windows-Wurzelverzeichnis der Werkzeuge mit lokaler Konfiguration. |
| `-LogDirectory` | Zeichenfolge | `Logs` neben dem Skript | Ziel fuer Textlog und CSV-Ergebnisliste. |
| `-ApplicationId` | Liste von Zeichenfolgen | Alle konfigurierten Eintraege | Nur die angegebenen exakten Paket-IDs verarbeiten. Keine Namens- oder Wildcard-Suche. |
| `-CheckOnly` | Schalter | Aus | Nur Konfiguration, Ziele, installierte Versionen und Manifeste pruefen; keine Paket-/Konfigurationsaenderungen. |

Beispiel mit anderen Zielen:

```powershell
.\Install-Applications.ps1 `
    -InstalledToolsRoot 'C:\Tools' `
    -PortableToolsRoot 'E:\Tools' `
    -LogDirectory 'C:\InstallLogs'
```

Einzelne Pakete auswaehlen:

```powershell
.\Install-Applications.ps1 -ApplicationId 'Mozilla.Firefox.de', 'RARLab.WinRAR'
```

Eine unbekannte ausgewaehlte ID wird als Fehler protokolliert. Bekannte
ausgewaehlte Pakete werden trotzdem verarbeitet. Ein mit `Enabled = $false`
deaktiviertes Paket bleibt auch bei expliziter Auswahl deaktiviert.

### Updates

```powershell
.\Update-Applications.ps1
$LASTEXITCODE
```

Der Updater unterstuetzt **dieselben fuenf Parameter** aus der Tabelle.
Bei abweichenden Werkzeugzielen dieselben Werte wie bei der Installation angeben;
eine abweichende bestehende Installation wird nicht automatisch verschoben.

```powershell
.\Install-Applications.ps1 -CheckOnly -ApplicationId 'DominikReichl.KeePass'
.\Update-Applications.ps1 -CheckOnly -PortableToolsRoot 'E:\Tools'
.\Update-Applications.ps1 -ApplicationId 'Celsys.ClipStudioPaint' -LogDirectory 'C:\UpdateLogs'
```

`-CheckOnly` fuehrt tatsaechliche `winget list`-/`show`-Abfragen, Versionsregel-,
Zielpfad- und lesende Konfigurationspruefungen aus. Nur Logverzeichnis, Log und CSV
duerfen durch das Skript geschrieben werden. winget selbst kann seine eigenen
Quellenmetadaten/Caches und Diagnoseprotokolle aktualisieren.
Es gibt keine `install`-/`upgrade`-/`pin add`-Aufrufe, neuen Werkzeugordner,
Konfigurationsaenderungen, Backups oder Sprachdownloads.

Grenzen: keine Probeinstallation, keine garantierten Schreibrechte im spaeteren
Benutzerkontext, kein Download-/Hash-/Funktionstest der Installer oder Sprachdatei.
Fehlende Programme werden nicht als erfolgreich EXE-verifiziert gemeldet.
Internet und lesbare Konfigurationsdateien sind erforderlich. Aenderungen nach
der Vorschau sind moeglich; der Zustand wird vor der Ausfuehrung erneut geprueft.
`-WhatIf` ist nicht implementiert.

## 5. Installationsziele und Anwendungsauswahl

| Gruppe im Installationsskript | Standardziel | Verhalten |
|---|---|---|
| `$standardApplications` / `Standard` | Vom Paket festgelegtes Verzeichnis | Kein `--location`; zum Beispiel Windows-verwaltete MSIX-Ablage oder Herstellerstandard. |
| `$installedToolsApplications` / `InstalledTools` | `C:\Tools\<Directory>` | Installation mit angefordertem Ziel; Konfiguration kann im Benutzerprofil oder in der Registry liegen. |
| `$portableToolsApplications` / `PortableTools` | `D:\Tools\<Directory>` | Werkzeugdateien im Ziel plus gegebenenfalls lokale Konfigurationsschritte. |

Die folgende Uebersicht zeigt die **36 gemeinsam verwalteten Pakete**.
Updates betreffen nur bereits installierte Pakete. Die Pfade gelten fuer unveraenderte
Wurzelparameter. ZIP-Pakete koennen unterhalb des Ziels einen weiteren
Programmordner enthalten.

| Paket-ID | Standard-Installationsziel | In der Update-Liste? |
|---|---|---|
| `Adobe.Acrobat.Reader.64-bit` | Paketstandard | Ja |
| `Canva.Affinity` | Paketstandard / Windows-MSIX | Ja |
| `Celsys.ClipStudioPaint` | Paketstandard | Ja, nur erlaubte 5.0.x-Versionen |
| `DominikReichl.KeePass` | `D:\Tools\KeePass` | Ja, exakt 2.61.1 |
| `dotPDN.PaintDotNet` | Paketstandard | Ja |
| `eMClient.eMClient` | `C:\Tools\eMClient` | Ja |
| `enzo1982.freac` | `D:\Tools\FreAC` | Ja |
| `EPSON.EpsonScan2` | Paketstandard | Ja |
| `EPSON.SoftwareUpdater` | Paketstandard | Ja |
| `FlorianHeidenreich.Mp3tag` | `C:\Tools\MP3tag` | Ja |
| `GIMP.GIMP` | Paketstandard | Ja |
| `Governikus.AusweisApp` | Paketstandard | Ja |
| `KeePassXCTeam.KeePassXC` | `D:\Tools\KeepassXC` | Ja |
| `LibreCAD.LibreCAD` | `C:\Tools\LibreCAD` | Ja |
| `Logitech.OptionsPlus` | Paketstandard | Ja |
| `Microsoft.PowerShell` | Paketstandard | Ja |
| `Microsoft.PowerToys` | Paketstandard | Ja |
| `Microsoft.Sysinternals.PsTools` | `D:\Tools\PsTools` | Ja |
| `Microsoft.WSL` | Paketstandard | Ja |
| `Mozilla.Firefox.de` | Paketstandard | Ja |
| `Mozilla.Thunderbird.de` | Paketstandard | Ja |
| `MPC-BE.MPC-BE` | `D:\Tools\MPC` | Ja |
| `Obsidian.Obsidian` | Paketstandard | Ja |
| `PDFsam.PDFsam` | `C:\Tools\pdfSAM` | Ja |
| `PuTTY.PuTTY` | `C:\Tools\PuTTY` | Ja |
| `RARLab.WinRAR` | Paketstandard | Ja |
| `RaspberryPiFoundation.RaspberryPiImager` | Paketstandard | Ja |
| `REINERSCT.cyberJackDriverPackage` | Paketstandard | Ja |
| `Rufus.Rufus` | `D:\Tools\Rufus` | Ja |
| `TheDocumentFoundation.LibreOffice` | `D:\Tools\LibreOffice` | Ja, mit lokalem Konfigurationsschutz |
| `VideoLAN.VLC` | `D:\Tools\VLC` | Ja |
| `WinSCP.WinSCP` | `D:\Tools\WinSCP` | Ja |
| `XnSoft.XnConvert` | `C:\Tools\XnConvert` | Ja |
| `XnSoft.XnView.Classic` | `C:\Tools\XnView` | Ja |
| `Yubico.Authenticator` | Paketstandard | Ja |
| `Yubico.YubikeyManager` | Paketstandard | Ja |

**Portabilitaet ist keine Folge des Verzeichnisnamens.** `--location` steuert
nur das angeforderte Installationsziel. Ein Installer kann weiterhin Registry,
Dienste, Verknuepfungen oder Abhaengigkeiten benoetigen. Einige Programme
speichern zusaetzliche Einstellungen ausserhalb des Zielordners.

Ein bereits installiertes Programm wird durch einen anderen Zielparameter
nicht verschoben. Das Installationsskript meldet einen Fehler, wenn die
erwartete EXE nicht eindeutig im angeforderten Werkzeugziel gefunden wird.
Es nimmt dann keine lokale Konfiguration an einem anderen Installationsort vor.

## 6. Ablauf der Installation

1. Parameter, Paketgruppen und Hilfsfunktionen laden; Logdatei vorbereiten.
2. Umgebung und Ziele protokollieren; winget und im Normalbetrieb Administratorrechte pruefen.
3. Gruppen nacheinander verarbeiten; innerhalb jeder Gruppe automatisch nach ID
   sortieren, Auswahlfilter anwenden und doppelte IDs erkennen.
4. Je Paket Versionsregel, Eigenschaften, Laufwerk/Pfad, Installationsstand,
   vorhandene Konfiguration und passendes Manifest pruefen. Deaktivierte Pakete
   ueberspringen. Bei KeePass und LibreOffice auch laufende Instanzen pruefen.
5. Vollstaendige Tabelle mit installierter/angeforderter Version, Aktion und
   Ziel ausgeben; weitere Details zeigen Quelle, Installer, Scope, Architektur,
   Sprache, Zusatzargumente und lokale Konfiguration. Mit `-CheckOnly` danach
   nur noch Bericht schreiben, keine Ausfuehrung.
6. Vor jedem echten Auftrag Zustand erneut pruefen, vorhandene verwaltete
   Konfigurationsdateien sichern, erst jetzt Zielordner anlegen und winget mit
   exakter ID und der geprueften expliziten Version starten. Gesicherte
   Einstellungen auch bei einem Installerfehler wiederherstellen.
7. Exitcode auswerten. Bei Werkzeugen die EXE rekursiv suchen; genau ein Treffer
   ist erforderlich. Danach die konfigurierte lokale Nachbearbeitung ausfuehren.
8. Einen vorgesehenen Versions-Pin setzen. Ergebnisse sammeln, zusammenfassen
   und als CSV neben dem Log ablegen.

Typische gemeinsame winget-Optionen:

| Option | Bedeutung |
|---|---|
| `install` / `upgrade` | Installations- bzw. Update-Vorgang. |
| `--id` und `--exact` | Genau das angegebene Paket auswaehlen. |
| `--source winget` | Die benannte winget-Quelle verwenden. |
| `--silent` | Stillen Installerbetrieb anfordern. |
| `--accept-package-agreements` | Paketvereinbarungen automatisch akzeptieren. |
| `--accept-source-agreements` | Quellenvereinbarungen automatisch akzeptieren. |
| `--disable-interactivity` | Rueckfragen unterbinden; fehlende Voraussetzungen koennen zum Fehler fuehren. |
| `--location` | Bei Werkzeuggruppen: angefordertes bzw. vorab geprueftes bestehendes Ziel, auch fuer Updates. |

winget-Exitcode `0` und der Code fuer ein bereits aktuelles Paket
`-1978335189` (`0x8A15002B`) erlauben die weitere Verarbeitung.
Auch bei einem bereits aktuellen Werkzeug werden Ziel und Nachbearbeitung
geprueft. Andere Exitcodes werden als Paketfehler protokolliert.

## 7. Ablauf der Updates

Der Updater verwendet dieselben Gruppen und dieselbe Sortierung wie die
Installation. Zuerst werden **alle ausgewaehlten Pakete rein lesend geprueft**;
erst nach der vollstaendigen Vorschau beginnen Aenderungen. Keine zusaetzliche
Bestaetigung erforderlich. `-CheckOnly` beendet den Lauf nach dem Bericht.

Die Tabelle unterscheidet `Update`, `NoUpdate` (aktuell), `NotInstalled` (fehlt),
`Skipped` (deaktiviert) und `Error`. Fehlende Pakete werden **nicht installiert**.
Nur wingets eindeutiger No-Apps-Code `0x8A150014` zaehlt als nicht installiert;
Abfragefehler und unlesbare/mehrdeutige Tabellen sind Fehler, keine leere Auswahl.
Die Parser unterstuetzen deutsch-/englischsprachige winget-Ausgaben und melden
abweichende Formate explizit statt ein Update zu erraten.

Ohne Versionsvorgabe entscheidet die Available-Spalte der exakten `winget list`-
Abfrage, ob ein Update angeboten wird. Das passende Manifest wird geprueft und
die gezeigte Version explizit angefordert. Auch hier kein `--include-unknown`
oder `--force`; unbekannte installierte Versionen werden nicht uebersprungen.

Fuer ein Paket mit Versionsvorgabe gilt dagegen:

1. Gemeinsame oder direkt eingetragene Regel pruefen.
2. Verfuegbare Versionen mit `winget show --versions` abfragen.
3. Eine erlaubte Zielversion bestimmen: exakt `Version` oder die numerisch
   hoechste stabile Version innerhalb von `VersionPin`.
4. Installierte Version ueber `winget list --id ... --exact` ermitteln.
5. Falls erforderlich, mit ausdruecklichem `--version <Ziel>` aktualisieren.
6. Danach erneut die installierte Version abfragen und mit dem Ziel vergleichen.

Bei begrenzten Paketen gibt es **kein** `--include-unknown`, kein `--force`
und keinen Rueckfall auf ein unbegrenztes Update. Fehlende Versionen,
unlesbare Tabellen, mehrere passende Installationen oder Abfragefehler fuehren
zum Fehler fuer dieses Paket. Die weiteren Pakete werden weiterverarbeitet.

Eine bereits erlaubte aktuelle Version bleibt unveraendert. Eine bereits
installierte unzulaessige hoehere Version wird gemeldet, aber nicht
automatisch heruntergestuft. Eine aeltere Version darf auf das erlaubte
Ziel aktualisiert werden.

Bei Werkzeugen muss vor einem Update die EXE eindeutig im konfigurierten Ziel
vorhanden sein. Abweichende Ziele werden als Fehler gemeldet, nicht umgezogen.
Lokale Einstellungen werden wie bei der Installation gelesen, vor der
Ausfuehrung gesichert, nach dem Installer wiederhergestellt und nachbearbeitet.
KeePass bleibt bei 2.61.1/Inno mit deutschem Sprachpaket; LibreOffice behaelt
sein lokales Profil. Nach erfolgreichem LibreOffice-Update bleibt die neue
bootstrap.ini mit aktuellen Produktdaten erhalten; nur die Profilumleitung
wird erneut gesetzt. Bei `NoUpdate`,
`NotInstalled`, `Skipped` und `-CheckOnly` gibt es keine Nachbearbeitung.

## 8. Anwendungen konfigurieren

Die drei Paketarrays in `Get-ApplicationGroups` in `Application-Management.ps1`
werden **nur einmal fuer beide Skripte** bearbeitet. Die Versionsdaten stehen
bei benannten Regeln in der gemeinsamen PSD1-Datei.

| Eigenschaft | Installationsskript | Update-Skript |
|---|---|---|
| `Name` | Pflicht; Anzeigename. | Pflicht; Anzeigename. |
| `Id` | Pflicht; exakte winget-ID. | Pflicht; exakte winget-ID. |
| `Directory` | Pflicht fuer Werkzeuggruppen; einzelner Unterordnername ohne Pfadbestandteile oder `..`. | Dasselbe Ziel, keine Migration. |
| `Executable` | Pflicht fuer Werkzeuggruppen; EXE-Name oder Muster wie `rufus*.exe`. | Pruefung vor und nach Updates. |
| `InstallerType` | Optional; `--installer-type`. | Identische Auswahl und Manifestpruefung. |
| `Scope` | Optional; `user` oder `machine` ueber `--scope`. | Wird weitergereicht. |
| `Architecture` | Optional; `x86`, `x64`, `arm`, `arm64` oder `neutral`. | Wird weitergereicht. |
| `Version` | Konkrete Installationsversion. | Exaktes Update-Ziel, wenn kein `VersionPin` vorliegt. |
| `VersionPin` | Versionsreihe wie `5.0.*`; braucht eine passende explizite `Version`, setzt anschliessend einen winget-Pin. | Erlaubte Update-Reihe; neueste passende stabile Version wird ermittelt. |
| `VersionPolicy` | Laedt `Version` / `VersionPin` aus der gemeinsamen Datei. | Derselbe Mechanismus. |
| `Locale` | Installer-Auswahl mit `--locale`, etwa `de` oder `de-DE`. | Wird weitergereicht. |
| `CustomArguments` | Installerspezifische Optionen als ein Wert fuer `--custom`. | Wird weitergereicht. |
| `LocalConfig` | Vorpruefung und Nachbearbeitung, standardmaessig `None`. | Gleiche Schutzpruefungen, Sicherung/Wiederherstellung und Nachbearbeitung. |
| `Enabled` | Optional, standardmaessig `$true`; `$false` deaktiviert das Paket. | Deaktiviert auch das Update. |

Beispiel eines Werkzeugdatensatzes:

```powershell
[pscustomobject]@{
    Name = 'PuTTY'
    Id = 'PuTTY.PuTTY'
    Directory = 'PuTTY'
    Executable = 'putty.exe'
    InstallerType = 'wix'
    Scope = 'machine'
    Enabled = $true
}
```

Dieses Beispiel ersetzt gegebenenfalls den bestehenden Eintrag; nicht doppelt
hinzufuegen. Keine zweite Update-Konfiguration anlegen.

Das Installationsskript meldet unbekannte Eigenschaften als Fehler.
Optionale Eigenschaften duerfen dort weggelassen werden; boolesche Werte
als `$true` / `$false` und nicht als `'true'` / `'false'` schreiben.

Unterstuetzte InstallerType-Werte sind `inno`, `wix`, `msi`, `nullsoft`,
`zip`, `portable`, `exe`, `burn`, `msix` und `appx`. Der jeweilige
winget-Datensatz muss die Auswahl anbieten. `portable` wandelt einen
normalen Installer nicht in eine portable Distribution um.

`CustomArguments` nur mit dokumentierten Schaltern des konkreten Installers
verwenden. Beispielsweise gehoert `/LANG=de` zu dem ausgewaehlten
MPC-BE-Inno-Setup, nicht zu einer beliebigen MSI. Optionen duerfen nicht
ungeprueft von einer Anwendung auf eine andere kopiert werden.

Metadaten vor einer Aenderung ansehen:

```powershell
winget show --id PuTTY.PuTTY --exact --source winget
winget show --id Celsys.ClipStudioPaint --exact --source winget --versions
```

## 9. Gemeinsame Versionsvorgaben

Die aktuelle Datei `Application-VersionPolicies.psd1` enthaelt:

```powershell
@{
    'Celsys.ClipStudioPaint' = @{
        Version = '5.0.4'
        VersionPin = '5.0.*'
    }
    'DominikReichl.KeePass' = @{
        Version = '2.61.1'
    }
}
```

Ein Paket verweist mit `VersionPolicy = 'Celsys.ClipStudioPaint'` bzw.
`VersionPolicy = 'DominikReichl.KeePass'` darauf. Bei einem solchen Verweis
keine zusaetzlichen `Version`- oder `VersionPin`-Werte in denselben
Paketdatensatz schreiben; dieser Widerspruch wird zurueckgewiesen.

### CLIP STUDIO PAINT

Die Erstinstallation fordert **5.0.4** an. Der Updater darf spaetere
**5.0.x**-Patches auswaehlen, aber **keine 5.1.x oder neueren Reihen**.
Er waehlt beispielsweise `5.0.10` vor `5.0.9`, nicht alphabetisch.
Vorabversionen wie `5.0.12-beta` werden nicht automatisch ausgewaehlt.

Im Installationsskript setzt `winget pin add --version 5.0.* --force` die
Upgrade-Grenze und ersetzt dabei einen eventuell vorhandenen Pin dieses Pakets.
Der Updater selbst entfernt oder lockert keine Pins und begrenzt das
angeforderte Ziel zusaetzlich mit `--version`.

### KeePass und weitere Regeln

KeePass bleibt auf **2.61.1**, passend zum geprueften Sprachpaket und zur
EXE-Kompatibilitaetspruefung. Eine Aenderung nur der PSD1-Version reicht fuer
eine kuenftige KeePass-Version daher nicht aus: auch Sprachpaketdaten und
Versionspruefung in der gemeinsamen Bibliothek muessen dazu passen.

Fuer andere Pakete lassen sich weitere benannte Regeln anlegen. Eine
Versionsvorgabe allein fuegt kein neues Paket hinzu; dazu gehoert ein
Katalogeintrag in einer der drei Gruppen.

Versionsbegrenzte Pakete verwenden stabile numerische Versionen mit zwei bis vier
Komponenten und numerische Reihen wie `5.0.*`. Unbeschraenkte Pakete verwenden
die Versionstexte der eindeutigen winget-Tabelle. Bei unklaren Angaben wird
nicht auf Verdacht aktualisiert.

**Grenzen:** Herstellerinterne Updater, manuelle Installationen und das
bewusste Entfernen oder Uebergehen eines Pins liegen ausserhalb dieser
Skriptregel. Ein bereits unzulaessiger Versionsstand wird nicht automatisch
repariert. Es findet keine Pruefung von Lizenzschluesseln statt.

## 10. Sprache und lokale Konfiguration

### Deutsche Installationen

| Anwendung | Konfiguration |
|---|---|
| Firefox / Thunderbird | Eigene deutsche IDs `Mozilla.Firefox.de` und `Mozilla.Thunderbird.de`. |
| WinRAR | `Locale = 'de'`; nicht pauschal `de-DE`. |
| AusweisApp | `Locale = 'de-DE'`. |
| MPC-BE | `CustomArguments = '/LANG=de'` fuer die Setup-Sprache. |
| LibreOffice | `CustomArguments = 'UI_LANGS=de'` fuer deutsche UI-Ressourcen. |
| KeePass | Separates offizielles deutsches Sprachpaket und Auswahl in der lokalen Konfiguration. |

Andere Pakete enthalten teilweise mehrere Sprachen. Ein deutscher Installer
oder vorhandene deutsche Sprachdateien erzwingen nicht immer eine deutsche
Oberflaeche bei einem bestehenden Benutzerprofil.

Eine winget-Datei `locale.de-DE.yaml` uebersetzt nur die Paketbeschreibung;
sie ist kein Beleg fuer einen deutschen Installer. Ein pauschales
`--locale de-DE` kann die Installation verhindern. Die Sprachauswahl
muss deshalb fuer das konkrete Paket geprueft werden.
Den aktuellen Konfigurationsueberblick und die Grenzen beschreibt
[README.md](README.md).

### Dateien fuer lokale Einstellungen

Die Nachbearbeitung arbeitet neben der tatsaechlich gefundenen EXE:

| `LocalConfig` | Dateien / Wirkung |
|---|---|
| `None` | Keine zusaetzliche Konfigurationsaenderung. |
| `Rufus` | `rufus.ini` |
| `KeePassXC` | `.portable` und `config\` |
| `KeePassGerman` | `KeePass.config.xml` und `Languages\German.lngx`, mit besonderen Schutzpruefungen. |
| `LibreOffice` | Gezielte Aenderung von `program\bootstrap.ini`; lokaler Ordner `profile\`. |
| `MPC-BE` | INI entsprechend dem EXE-Namen, etwa `mpc-be64.ini` oder `mpc-be.ini`. |
| `WinSCP` | `WinSCP.ini` mit lokalen Pfaden und Ordner `temp\`. |
| `VLC` | `vlcrc` und `Start-VLC.cmd`. |

Vorhandene einfache Konfigurationsdateien werden nicht durch leere Vorlagen
ersetzt. Alte AppData-/Registry-Einstellungen werden nicht allgemein migriert.
Der normale Benutzer muss die lokalen Dateien schreiben koennen; die Skripte
aendern keine ACLs und garantieren keine Schreibrechte fuer andere Benutzer.

### Besonderheiten und Grenzen

**VLC:** Ueber die erzeugte `Start-VLC.cmd` neben `vlc.exe` starten.
Direkte EXE-Aufrufe, Aliase oder alte Dateizuordnungen umgehen den lokalen
`--config`-Parameter. Zusaetzliche Qt-Oberflaecheneinstellungen koennen
weiterhin im Benutzerprofil liegen.

**LibreOffice:** Der Standardwert `UserInstallation=$SYSUSERCONFIG/LibreOffice/4`
in `bootstrap.ini` wird nach Sicherung durch
`UserInstallation=$ORIGIN/../profile` ersetzt. Andere INI-Eintraege bleiben
erhalten. Ein bereits lokaler Wert bleibt unveraendert; ein anderer
benutzerdefinierter Profilpfad oder eine mehrdeutige Struktur fuehrt zum Fehler.
Eine eindeutige `.bak`-Sicherung bleibt im Programmverzeichnis. Vor Updates
wird die vorhandene INI gesichert. Bei einem Installerfehler wird sie
wiederhergestellt; nach Erfolg wird nur die lokale Profilumleitung in der
neuen INI eingerichtet, damit neue Produktdaten erhalten bleiben.
Laufendes LibreOffice oder eine sonst erforderliche Umstellung vorhandener
Benutzerprofile wird zurueckgewiesen. Fremde Updatewege koennen die INI
weiterhin zuruecksetzen; in diesem Fall zuerst Profil und Sicherung pruefen.

**KeePass:** Wird zusaetzlich zu KeePassXC installiert. Das winget-Paket
verwendet Inno, nicht eine portable ZIP-Distribution; die Einstellungen
werden dennoch lokal verwaltet. Vor dem Installer prueft das Skript laufende
Instanzen, eine erzwungene Konfigurationsdatei und vorhandene Einstellungen.
Eine vorhandene lokale Konfiguration muss bereits
`PreferUserConfiguration=false` und `LanguageFile=German.lngx` enthalten.
Abweichende Einstellungen oder andernfalls zu migrierende Einstellungen im
aktuellen Benutzerprofil stoppen dieses Paket.

Passende lokale KeePass-Einstellungen werden vor dem Installer in einer
eindeutigen `.bak`-Datei gesichert und auch bei einem Installerfehler
wiederhergestellt, weil der Installer die Konfigurationsdatei ersetzen kann.
Fremde Benutzerprofile werden nicht migriert.

Das offizielle `KeePass-2.61-German.zip` wird von SourceForge heruntergeladen,
anhand festgelegter Groesse und SHA-256 geprueft und ausschliesslich dessen
`German.lngx` akzeptiert. Die LNGX-Datei bleibt in ihrem komprimierten Format.
Der temporaere ZIP-Download wird wieder entfernt. Ein vorhandenes abweichendes
Sprachpaket wird nicht ueberschrieben. URL, Pruefsumme und technische Details
stehen in [README.md](README.md).

**Weitere Programme:** Auch lokal abgelegte Werkzeuge koennen Registrydaten
benoetigen, beispielsweise PsTools fuer die EULA-Zustimmung. Der Ordner
`D:\Tools` ist deshalb keine generelle Zusage vollstaendiger Registryfreiheit.

## 11. Protokolle, Ergebnisse und Rueckgabecodes

### Unterschiede der beiden Skripte

| Merkmal | Installation | Update |
|---|---|---|
| Standard-Logziel | `Winget\Logs` | `Winget\Logs` |
| Anderes Logziel per Parameter | Ja, `-LogDirectory`. | Ja, `-LogDirectory`. |
| Dateiname | `Install-Applications-<Datum-Zeit-Millisekunden>-<PID>.log` | `Update-Applications-<Datum-Zeit-Millisekunden>-<PID>.log` |
| Ergebnisdatei | Zusaetzliche CSV neben dem zuletzt verwendeten Log. | Ebenso. |
| Diagnoseumfang | Vorschau, Paketkontext, Phasen, Ausgabe, Exitcode, Dauer und PowerShell-Fehlerdetails. | Ebenso, einschliesslich installierter Version und Update-Ziel. |
| Nicht beschreibbares Logziel | Ersatzlog `<Laufname>-fallback.log` neben dem Skript; danach gegebenenfalls nur Konsole. | Identisches Verhalten. |

Das Log kann nach einem Wechsel zum Ersatzpfad auf zwei Dateien
verteilt sein. Fruehere Eintraege werden nicht automatisch zusammengefuehrt.
Sind beide Ziele unbeschreibbar, ist keine dauerhafte Protokollierung garantiert.
Beide Skripte melden einen solchen Lauf als fehlerhaft. Keine parallelen
Aenderungen derselben Anwendung starten.

Logs enthalten moeglicherweise Benutzernamen, lokale Pfade und Ausgaben fremder
Installer. Vor einer Weitergabe vertrauliche Angaben entfernen.

### Installationsstatus in der CSV

Beide CSVs enthalten `Group`, `Id`, `Name`, `Location`, `Status`, `Phase`,
`ExitCode`, `DurationSeconds`, `Message`, `InstalledVersion`, `TargetVersion`,
`Source`, `InstallerType`, `Scope`, `Architecture`, `Locale`, `CustomArguments`,
`LocalConfig` und `Action`.

| Status | Bedeutung |
|---|---|
| `Succeeded` | Installation und vorgesehene Nachbearbeitung erfolgreich. |
| `AlreadyCurrent` | winget meldete bereits aktuell; weitere Pruefungen trotzdem erfolgreich. |
| `Skipped` | Paket durch `Enabled = $false` deaktiviert. |
| `Failed` | Mindestens ein Schritt fuer dieses Paket fehlgeschlagen. |
| `CheckOnly` | Lesende Pruefung abgeschlossen; `Action` beschreibt nur den geplanten Vorgang, nicht eine erfolgte Installation. |
| `NotInstalled` | Im Update-Lauf nicht installiert; kein Installationsversuch. |
| `NoUpdate` | Im Update-Lauf kein Update noetig; keine Konfigurationsaenderung. |

`Planned` erscheint nur in der Vorschau vor der Ausfuehrung; die Ergebnis-CSV
enthaelt anschliessend den Endstatus. `Action` bleibt zur Nachvollziehbarkeit
`Install`, `Update`, `NoUpdate`, `NotInstalled`, `Skipped` oder `Error`.

Die Fehlerphase hilft bei der Einordnung: `Selection`, `Configuration`,
`ConfigurationPreflight`, `TargetDirectory`, `Winget`, `VerifyExecutable`,
`LocalConfiguration`, `VersionPin`, `Discovery`, `Manifest`, `Revalidate`
oder `VerifyVersion`.
Ein Fehler in der Nachbearbeitung kann trotz winget-Exitcode `0` auftreten.
Beim Versions-Pin bleibt der Installations-Exitcode in der CSV; der konkrete
Pin-Fehler steht in Meldung und Textlog.

Fehler aus der neuesten CSV anzeigen, wenn das Standard-Logziel verwendet wurde:

```powershell
$report = Get-ChildItem -LiteralPath .\Logs -Filter 'Install-Applications-*.csv' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $report) {
    Write-Warning 'Keine Installations-CSV gefunden. Logpfad auf der Konsole beachten.'
}
else {
    Import-Csv -LiteralPath $report.FullName |
        Where-Object Status -eq 'Failed' |
        Format-Table Id, Phase, ExitCode, Message -Wrap
}
```

### Exitcodes

`$LASTEXITCODE` unmittelbar nach dem Skriptaufruf lesen, bevor ein anderer
nativer Befehl den Wert ersetzt:

| Exitcode | Installation | Update |
|---|---|---|
| `0` | Ausgewaehlte aktive Pakete erfolgreich verarbeitet/geprueft; keine Log-/CSV-Schreibfehler. | Alle Pakete erfolgreich verarbeitet/geprueft; fehlend/aktuell/deaktiviert sind keine Fehler. |
| `1` | Globale Voraussetzung fehlt oder unerwarteter skriptweiter Fehler. | Globale Voraussetzung fehlt oder unerwarteter skriptweiter Fehler. |
| `2` | Paket-/Prueffehler oder Fehler beim Schreiben von Log/CSV. | Dasselbe. |

Dies gilt auch fuer `-CheckOnly`: ein Prueffehler liefert `2`, fehlendes winget
liefert `1`. CDrFE ist kein Katalogeintrag; es wird in keinem Skript pauschal
als Fehler gezaehlt. Erfolgreiche Updates koennen regulaer mit `0` enden.

## 12. Fehler beheben und sicher wiederholen

| Meldung / Situation | Vorgehen |
|---|---|
| winget fehlt | App Installer und Ausfuehrungsalias pruefen; `Get-Command winget` erneut ausfuehren. |
| Administratorrechte fehlen | Neue PowerShell als Administrator starten. |
| Hilfsdatei oder benannte Versionsregel fehlt | Vollstaendigen Dateisatz wiederherstellen; Regelname und PSD1-Inhalt pruefen. |
| Laufwerk oder Werkzeugziel fehlt | Laufwerk bereitstellen oder Installationsparameter bewusst aendern. Keine automatische Migration erwarten. |
| Keine passende Installer-Kombination | `winget show` aufrufen; Scope, Architektur, InstallerType und Locale mit dem konkreten Manifest abgleichen. |
| Anwendung ist bereits anderswo installiert | Vorhandene Installation und Einstellungen sichern; Zielwahl bzw. Migration manuell klaeren. |
| EXE fehlt oder wurde mehrfach gefunden | Tatsaechliche Verzeichnisstruktur und `Executable`-Muster pruefen; nicht blind `--force` verwenden. |
| Keine erlaubte Update-Version ermittelbar | Versionsregel und `winget show --versions` pruefen. Nicht zur Fehlerumgehung die Lizenzgrenze entfernen. |
| Bereits unzulaessige Version installiert | Lizenz- und Installationsstand manuell klaeren; kein automatisches Downgrade. |
| Update durch einen strengeren Pin verhindert | Bestehende Pins bewusst pruefen; Skript entfernt sie nicht automatisch. |
| Lokale Konfiguration gesperrt oder abweichend | Anwendung schliessen, Einstellungen und Sicherungsdateien pruefen, keine ungeprueften Dateien loeschen. |
| KeePass-Sprachdownload fehlgeschlagen | Netzwerk/Proxy/SourceForge und Integritaetsmeldung pruefen; Hashpruefung nicht deaktivieren. |
| Log nicht beschreibbar | `-LogDirectory` auf ein beschreibbares Ziel setzen; ausgegebenen Ersatzpfad beachten. |

Fehlgeschlagene Installationspakete lassen sich gezielt wiederholen:

```powershell
.\Install-Applications.ps1 -ApplicationId 'Celsys.ClipStudioPaint'
```

Fuer ein Paket mit speziellen lokalen Einstellungen entsprechend dessen ID:

```powershell
.\Install-Applications.ps1 -ApplicationId 'TheDocumentFoundation.LibreOffice'
.\Install-Applications.ps1 -ApplicationId 'DominikReichl.KeePass'
```

Die Aufrufe nicht ungeprueft als allgemeine Reparatur verstehen. Nach einer
frischen KeePass-Installation mit fehlgeschlagenem Sprachdownload kann etwa
die hinterlassene Standardkonfiguration beim naechsten Lauf als abweichend
erkannt werden. Dann erst sichern und bewusst korrigieren.

Fehlgeschlagene Updates koennen ebenso mit `-ApplicationId` gezielt erneut
geprueft werden, zum Beispiel zuerst `.\Update-Applications.ps1 -CheckOnly
-ApplicationId 'TheDocumentFoundation.LibreOffice'` (in einer Zeile).

Beide Skripte fuehren keine automatischen Wiederholungen oder bewusst
angeforderten Neustarts aus. Ein Installer kann einen Neustart verlangen;
seine Ausgabe beachten. Es gibt keinen allgemeinen Installer-Timeout und
keine automatische Beendigung haengender Installationsprozesse.
Syntaxfehler, Parameterbindungsfehler, Prozessabbruch und Stromausfall
koennen nicht durch die Paketfehlerbehandlung aufgefangen werden.

## 13. Pflege und weiterfuehrende Informationen

Bei einer Aenderung Paketlisten, Versionsregeln und Hilfe gemeinsam aktuell
halten. Vorhandene Einstellungen sichern; bei einem neuen Paket zuerst
Metadaten, Herstelleroptionen und den Umgang mit Benutzerprofilen klaeren.
Fuer eine echte Installationserprobung ein geeignetes Testsystem verwenden.

Die vorhandenen Pester-Tests laden die nebenwirkungsfreie gemeinsame Bibliothek und ersetzen
Paketbefehle; sie installieren oder aktualisieren keine echten Anwendungen.
Sie sind nicht fuer den normalen Skriptbetrieb erforderlich.

Mit vorhandenem Pester 3.4 und Windows PowerShell 5.1, aus dem Verzeichnis `Winget`:

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester -Script .\Tests -EnableExit"
```

Weiterfuehrende Dateien:

- [Einstieg, Dateiverweise und technische Pruefdaten](README.md)
- [Zentrale Versionsvorgaben](Application-VersionPolicies.psd1)
- [Gemeinsamer Katalog und Verarbeitung](Application-Management.ps1)
- [Gemeinsame Auswertung der Versionsvorgaben](Application-VersionPolicy.ps1)
- [Installationsskript](Install-Applications.ps1)
- [Update-Skript](Update-Applications.ps1)
