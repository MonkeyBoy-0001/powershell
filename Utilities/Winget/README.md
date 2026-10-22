# Anwendungen mit winget installieren und aktualisieren

Dokumentation aller PowerShell-Skripte und der Versionskonfiguration in
`Utilities\Winget`. Beispiele werden aus diesem Verzeichnis ausgefuehrt.

**Ohne `-CheckOnly` werden echte Systemaenderungen ausgefuehrt.** Zuerst Daten
und Anwendungseinstellungen sichern, betroffene Programme schliessen und die
lesende Vorschau pruefen. Beide Skripte verwenden denselben Katalog mit
36 Anwendungen.

## Dateien und Abhaengigkeiten

| Datei | Aufgabe |
|---|---|
| [Install-Applications.ps1](Install-Applications.ps1) | CLI-Einstieg fuer Installation und Installationsvorpruefung. |
| [Update-Applications.ps1](Update-Applications.ps1) | CLI-Einstieg fuer Updates bereits installierter Anwendungen und Update-Vorschau. |
| [Application-Management.ps1](Application-Management.ps1) | Gemeinsamer Anwendungskatalog, Planungs-/Ausfuehrungsfunktionen, Konfigurationsschutz und Protokollierung. |
| [Application-VersionPolicy.ps1](Application-VersionPolicy.ps1) | Funktion `Resolve-ApplicationVersionPolicy` zum sicheren Einlesen benannter Versionsregeln. |
| [Application-VersionPolicies.psd1](Application-VersionPolicies.psd1) | Gemeinsame Versionsdaten fuer CLIP STUDIO PAINT und KeePass. |
| [Install-and-Update-Help.md](Install-and-Update-Help.md) | Ausfuehrliche Benutzerhilfe. |
| [Tests\README.md](Tests/README.md) | Drei isolierte Pester-Testsuiten und ihre Aufrufe. |
| `Logs\` | Standardziel fuer erzeugte Logs und CSV; wird bei Bedarf angelegt. |

Die beiden Einstiege und alle drei Code-/Datenhelfer zusammenhalten.
Hilfsdateien werden relativ zum Skriptverzeichnis geladen, nicht relativ zum
Arbeitsverzeichnis oder Installationsziel. Pester ist nur fuer Tests erforderlich.

Die frueheren Verweise auf die nicht enthaltene `Install-Applications.md`
wurden auf diese README umgestellt. Eine weitere Datei dieses Namens ist
nicht erforderlich. Die erforderlichen Laufzeithelfer sind vorhanden.

## Voraussetzungen

- Windows mit Windows PowerShell 5.1 oder PowerShell 7.
- Funktionsfaehiges `winget` aus Microsoft App Installer in `PATH` bzw. per
  App-Ausfuehrungsalias, mit Unterstuetzung der verwendeten `show`, `list`,
  `install`, `upgrade` und `pin add`-Optionen.
- Administratorrechte fuer echte Installationen/Updates, nicht fuer `-CheckOnly`.
- Internetzugang zur winget-Quelle und den Herstellerdownloads; KeePass nutzt
  zusaetzlich SourceForge.
- Erreichbare Zielverzeichnisse, ausreichender Speicher und Schreibrechte.
  Die Standardwurzeln sind `C:\Tools` und `D:\Tools`.
- Eigene Lizenzen fuer lizenzpflichtige Anwendungen. Automatisch akzeptierte
  Paketvereinbarungen ersetzen keinen Lizenzerwerb.

```powershell
Get-Command winget
winget --version
Get-Help .\Install-Applications.ps1 -Full
Get-Help .\Update-Applications.ps1 -Full
```

Die Kommentarhilfe aller Skripte enthaelt einen `.LINK`-Verweis auf ihre
jeweilige README. Die Dateitabelle oben verlinkt umgekehrt den Quellcode.

Keine parallelen Skript-, winget- oder Herstellerupdates derselben Anwendungen.
Die Einstiegsskripte normal starten, **nicht dot-sourcen**: Sie besitzen einen
ausfuehrenden Hauptteil und beenden ihn mit einem Exitcode.

## Parameter beider Einstiegsskripte

| Parameter | Standard | Bedeutung |
|---|---|---|
| `InstalledToolsRoot` | `C:\Tools` | Absolute Windows-Wurzel fuer installierte Werkzeuge mit angefordertem Ziel. |
| `PortableToolsRoot` | `D:\Tools` | Absolute Windows-Wurzel fuer Werkzeuge mit gegebenenfalls lokaler Konfiguration. |
| `LogDirectory` | `Logs` neben dem Skript | Verzeichnis fuer Textlog und Ergebnis-CSV. |
| `ApplicationId` | Alle Katalogeintraege | Exakte Paket-IDs als Array, keine Wildcards oder Namenssuche. |
| `CheckOnly` | Aus | Lesende Pruefung und Vorschau, keine Installation oder Konfigurationsaenderung. |

`-WhatIf` ist nicht implementiert; hierfuer `-CheckOnly` verwenden.
Der Normalbetrieb besitzt keine zusaetzliche Bestaetigungsabfrage.
Unbekannte ausgewaehlte IDs werden als Fehler gemeldet, bekannte ausgewaehlte
Eintraege trotzdem verarbeitet. Deaktivierte Pakete bleiben deaktiviert.

## Install-Applications.ps1

```powershell
# Alle Installationsplaene pruefen, ohne Anwendungen zu veraendern
.\Install-Applications.ps1 -CheckOnly
$LASTEXITCODE

# Einzelne Anwendungen lesend pruefen
.\Install-Applications.ps1 -CheckOnly `
    -ApplicationId 'Mozilla.Firefox.de','RARLab.WinRAR'

# Echte Installation: erst nach erfolgreicher Pruefung, als Administrator
.\Install-Applications.ps1 -ApplicationId 'Mozilla.Firefox.de'
$LASTEXITCODE
```

Zuerst werden Konfiguration, Versionsregeln, Ziele, vorhandene Installationen,
verwaltete Einstellungen und passende Manifeste fuer die ganze Auswahl
geprueft. Die vollstaendige Vorschau erscheint vor der ersten Paketmutation.
Vor der Ausfuehrung wird der Installationszustand erneut geprueft.

Vorhandene verwaltete Konfigurationsdateien werden gesichert. Danach werden
Zielordner angelegt und `winget install` mit exakter ID, Quelle `winget`,
gepruefter Version, stillem Modus und automatischer Annahme der Vereinbarungen
aufgerufen. Bei Werkzeugen muss die erwartete EXE eindeutig im Ziel gefunden
werden. Es folgen lokale Konfiguration und gegebenenfalls ein Versions-Pin.

Bestehende Installationen werden durch andere Zielparameter **nicht verschoben**.
Ein fehlendes erwartetes Werkzeugziel ist ein Fehler und wird nicht als Anlass
fuer eine automatische Migration verwendet.

## Update-Applications.ps1

```powershell
.\Update-Applications.ps1 -CheckOnly
$LASTEXITCODE

# Abweichende Wurzeln bei Installation und Updates identisch verwenden
.\Update-Applications.ps1 -CheckOnly -InstalledToolsRoot 'C:\Tools' `
    -PortableToolsRoot 'E:\Tools' -LogDirectory 'C:\UpdateLogs'

# Echter Update-Auftrag fuer ein Paket, als Administrator
.\Update-Applications.ps1 -ApplicationId 'Celsys.ClipStudioPaint'
$LASTEXITCODE
```

Aktualisiert nur installierte Anwendungen; fehlende Pakete werden nicht
installiert. Fuer unbegrenzte Pakete bestimmt die Available-Spalte der exakten
`winget list`-Abfrage den Updatebedarf. Bei Versionsregeln wird die erlaubte
Version aus `winget show --versions` ermittelt. Das ausgewaehlte Manifest wird
geprueft und die Zielversion explizit an `winget upgrade` uebergeben.

Nach einem Update wird die installierte Version erneut verglichen.
Unbekannte/mehrdeutige Versionen und Abfragefehler werden nicht als "fehlt" oder
"aktuell" interpretiert. Es gibt keinen automatischen Downgrade und kein
`--include-unknown`. Bei fehlenden, aktuellen oder deaktivierten Paketen werden
keine Konfigurationen nachbearbeitet.

### Grenzen von CheckOnly

Es werden echte `winget list`-/`show`-Abfragen und lesende Konfigurationspruefungen
ausgefuehrt. Das Skript schreibt nur Logverzeichnis, Log und CSV. Es erzeugt
keine Werkzeugziele, Konfigurationsbackups, Sprachdownloads oder Pins.
Winget selbst kann eigene Caches, Quellenmetadaten und Diagnoseprotokolle
aktualisieren.

Eine erfolgreiche Vorpruefung ist kein Installertest und garantiert weder
spaetere Schreibrechte noch Speicherplatz, Downloadintegritaet oder einen
erfolgreichen Programmstart. Die Tabellenparser unterstuetzen die vorgesehenen
deutschen/englischen Ausgaben und verweigern unbekannte Formate.

## Anwendungskatalog und lokale Einstellungen

`Get-ApplicationGroups` in `Application-Management.ps1` definiert:

| Gruppe | Anzahl | Ziel / Bedeutung |
|---|---|---|
| `Standard` | 20 | Hersteller-/Paketstandard, ohne `--location`. |
| `InstalledTools` | 7 | `<InstalledToolsRoot>\<Directory>`; Einstellungen koennen weiterhin im Profil oder in der Registry liegen. |
| `PortableTools` | 9 | `<PortableToolsRoot>\<Directory>` plus konfigurierte lokale Nachbearbeitung. Keine Garantie vollstaendiger Portabilitaet. |

Den aktuellen Katalog ohne Paketaktionen anzeigen:

```powershell
. '.\Application-Management.ps1'
Get-ApplicationGroups | ForEach-Object {
    $group = $_
    $group.Applications | Select-Object @{Name='Group';Expression={$group.Name}}, Name, Id
}
```

Die vollstaendige Paket-/Zieltabelle steht in `Install-and-Update-Help.md`,
Abschnitt 5. Katalogeintraege nur in der gemeinsamen Bibliothek aendern, nicht
getrennte Installations- und Update-Listen anlegen.

| Eigenschaft | Bedeutung |
|---|---|
| `Name`, `Id` | Erforderlicher Anzeigename und exakte Paket-ID. |
| `Directory`, `Executable` | Bei Werkzeuggruppen einfacher Zielordnername und EXE-Name/-Muster ohne Pfad. |
| `InstallerType` | Optional: `inno`, `wix`, `msi`, `nullsoft`, `zip`, `portable`, `exe`, `burn`, `msix`, `appx`; muss im Manifest verfuegbar sein. |
| `Scope`, `Architecture` | Optional: `user`/`machine` bzw. `x86`, `x64`, `arm`, `arm64`, `neutral`. |
| `Locale`, `CustomArguments` | Sprache fuer Installer-Auswahl und herstellerspezifischer Zusatzwert fuer `--custom`. |
| `Version`, `VersionPin`, `VersionPolicy` | Direkte Versionsvorgabe, erlaubte Reihe oder Verweis auf die gemeinsame Regeldatei. |
| `LocalConfig` | Art der lokalen Konfiguration; Standard `None`. |
| `Enabled` | Boolean `$true`/`$false`, keine Zeichenfolge; Standard `$true`. |

Unbekannte Eigenschaften, ungueltige Ziele und doppelte IDs werden gemeldet.
`--location` erzwingt weder Portabilitaet noch Registryfreiheit.

| LocalConfig | Nachbearbeitung |
|---|---|
| `None` | Keine zusaetzliche Konfigurationsdatei. |
| `Rufus` | `rufus.ini` neben der EXE. |
| `KeePassXC` | `.portable` und `config`; vorhandene `keepassxc.ini` und `keepassxc_local.ini` werden bei Updates geschuetzt. |
| `MPC-BE` | INI passend zum tatsaechlichen EXE-Namen. |
| `VLC` | `vlcrc` und `Start-VLC.cmd`; ueber diese CMD starten, sonst wird die lokale Konfiguration nicht ausdruecklich ausgewaehlt. |
| `WinSCP` | `WinSCP.ini` mit lokalen Pfaden und `temp`. |
| `LibreOffice` | Lokales `profile` durch gezielte Anpassung von `program\bootstrap.ini`. |
| `KeePassGerman` | `KeePass.config.xml` und verifiziertes `Languages\German.lngx`. |

Einfache bestehende Konfigurationsdateien werden nicht durch leere Vorlagen
ersetzt. Vorhandene Benutzerprofile werden nicht allgemein migriert. ACLs
werden nicht angepasst; lokale Konfiguration muss fuer den Anwender schreibbar
sein. Fuer VLC koennen weitere Oberflaecheneinstellungen im Benutzerprofil bleiben.

KeePass und LibreOffice duerfen waehrend ihrer Verarbeitung nicht laufen.
Abweichende/erzwungene KeePass-Konfigurationen oder erforderliche
Benutzerprofilmigrationen werden abgewiesen. LibreOffice erhaelt nach
erfolgreichem Update die neue `bootstrap.ini` mit neuen Produktdaten und erneut
gesetzter lokaler Profilumleitung; bei Installerfehler wird die gesicherte
Konfiguration wiederhergestellt.

## Versionshelfer und Daten

`Application-VersionPolicy.ps1` definiert
`Resolve-ApplicationVersionPolicy -Application <PSCustomObject> -PolicyFile <Pfad>`.
Die Funktion liest Regeln mit `Import-PowerShellDataFile`, validiert sie und
liefert bei einem Regelverweis eine ergaenzte Kopie des Anwendungseintrags.
Unbekannte/leere Regeln und Konflikte mit direkten Versionswerten werden
abgewiesen. Die Bibliothek selbst startet keine Paketverarbeitung.

Aktuelle `Application-VersionPolicies.psd1`:

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

CLIP STUDIO PAINT wird mit 5.0.4 installiert; Updates waehlen den hoechsten
stabilen numerischen 5.0.x-Patch, nicht 5.1 oder neuer. Bei Installation wird
ein entsprechender winget-Pin gesetzt und ein vorhandener Pin dieses Pakets
gegebenenfalls ersetzt. Der Updater lockert keine Pins.

KeePass bleibt exakt auf 2.61.1/Inno. `Install-KeePassGermanLanguage` prueft
die EXE-Version 2.61.1.0 und verwendet:

- URL: `https://downloads.sourceforge.net/project/keepass/Translations%202.x/2.61/KeePass-2.61-German.zip`
- ZIP-Groesse: 45754 Bytes; einziger Eintrag `German.lngx`, 45598 Bytes.
- SHA256: `A0EC490D2A7262A8D8ADEF53F87B5EDE70CB0BFEC522C998F7927444D72CFB40`.

Dies sind die im Code festgelegten Pruefdaten, kein separat publizierter
Hersteller-Hash. Die LNGX-Datei wird unveraendert gespeichert; ein vorhandenes
abweichendes Sprachpaket wird nicht ueberschrieben. Eine kuenftige KeePass-Version
erfordert mehr als eine PSD1-Aenderung: EXE-Pruefung und Sprachdaten muessen
ebenfalls passen. Integritaetspruefungen nicht zur Fehlerumgehung abschalten.

## Application-Management.ps1 als Bibliothek

Das Laden definiert Funktionen und laedt den Versionshelfer, startet jedoch
keine Installation.

| Funktionsbereich | Zentrale Funktionen |
|---|---|
| Einstieg und Katalog | `Start-ApplicationRun`, `Get-ApplicationGroups`, `Invoke-Installation` |
| Planung und Auswahl | `Get-ApplicationPlan`, `Invoke-ApplicationGroups`, `Write-ApplicationPreview` |
| Ausfuehrung | `Invoke-ApplicationChange`, `Install-Application`, `Update-Application`, `Invoke-Winget` |
| Pruefungen | `Get-InstalledApplicationState`, `Test-ApplicationManifest`, `Test-ApplicationTarget`, `Resolve-InstalledExecutable` |
| Versionsvergleich | `Get-UpdateVersionConstraint`, `Get-AllowedUpdateVersion`, `ConvertTo-UpdateVersion`, `Test-ApplicationVersionEqual` |
| Konfigurationsschutz | `Get-LocalConfigurationState`, `Initialize-LocalConfiguration`, KeePass-/LibreOffice-Helfer |
| Diagnose | `Write-Log`, `Write-ErrorDetail`, `Write-LogLocation` |

Interne Ausfuehrungsfunktionen erwarten initialisierten Lauf-/Logzustand.
Fuer normale Aufgaben die beiden CLI-Einstiege verwenden.

## Logs, Exitcodes und Fehlerbehandlung

Textlog und gleichnamige CSV liegen standardmaessig in `Logs`.
Dateinamen beginnen mit `Install-Applications-` bzw. `Update-Applications-`
und enthalten Zeitstempel und PID. Bei Logfehlern wird auf ein
`<Laufname>-fallback.log` neben dem Skript ausgewichen, danach gegebenenfalls nur
auf Konsole. Auch mit erfolgreichem Fallback bleibt der Lauf fehlerhaft.

Die CSV enthaelt Paket, Gruppe, Ziel, Status, Phase, nativen Exitcode, Dauer,
Meldung, installierte/geplante Version und Installer-/Konfigurationsoptionen.

| Status | Bedeutung |
|---|---|
| `CheckOnly` | Vorpruefung erfolgreich, keine Paketaktion ausgefuehrt. |
| `Succeeded`, `AlreadyCurrent` | Paketverarbeitung und vorgesehene Folgepruefungen erfolgreich. |
| `NotInstalled`, `NoUpdate` | Im Update-Lauf fehlt das Paket bzw. ist kein Update vorgesehen. |
| `Skipped` | Durch `Enabled = $false` deaktiviert. |
| `Failed` | Konfiguration, Abfrage, Ausfuehrung oder Folgepruefung fehlgeschlagen. |

`Planned` ist ein Zwischenstatus der Vorschau. `Action` beschreibt die geplante
Aktion und ist kein Erfolgsnachweis.

| Skript-Exitcode | Bedeutung |
|---|---|
| `0` | Kein erkannter Paket-/Pruef-/Protokollfehler. |
| `1` | Globale Voraussetzung fehlt oder unerwarteter skriptweiter Fehler. |
| `2` | Mindestens ein Paket-, Pruef-, Log- oder CSV-Fehler. |

Erste Fehlerphase im Textlog und betroffene CSV-Zeilen pruefen. Unabhaengige
Pakete werden soweit moeglich weiterverarbeitet. Ein Fehler nach dem Installer
kann bedeuten, dass die Anwendung bereits veraendert wurde; es gibt keinen
allgemeinen Paket-Rollback, Installer-Timeout oder automatische Migration.

Beim lokalen Check vom 21.10.2026 scheiterten beide Vorpruefungen an zehn
fehlenden konfigurierten Werkzeugzielen und an der von winget als `Unknown`
gemeldeten Epson-Scan-2-Version. Dies sind zu klaerende Rechnerzustaende,
keine fehlenden Bibliotheksdateien. Aktuelle Ergebnisse immer neu mit
`-CheckOnly` ermitteln; Ziele und unbekannte Versionen nicht auf Verdacht umgehen.

## Weiterfuehrende Dokumentation

[Install-and-Update-Help.md](Install-and-Update-Help.md) beschreibt alle 36 Pakete,
Sprachoptionen und Fehlerphasen im Detail.
[Tests\README.md](Tests/README.md) dokumentiert jede Testsuite und
passende Pester-Aufrufe. Tests ersetzen keine echte Installationserprobung auf
einem geeigneten Testsystem.
