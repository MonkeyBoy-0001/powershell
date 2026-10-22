# Portable VS Code: PowerShell und Webdesign

[Initialize-VSCodeWorkspaces.ps1](Initialize-VSCodeWorkspaces.ps1) erzeugt
eine wiederverwendbare Grundausstattung fuer zwei getrennte Arbeitsbereiche.
**Nur VS Code ist portabel; PowerShell 7 wird normal installiert.**
Die empfohlenen VS-Code-Erweiterungen werden standardmaessig automatisch
installiert. Es werden keine vorhandenen Projekte verschoben.

## Voraussetzungen

- Windows mit Windows PowerShell 5.1 oder PowerShell 7 zum Starten des Setups.
- Installiertes **PowerShell 7**, dessen `pwsh.exe` ueber `PATH` erreichbar ist
  oder mit `-PowerShellPath` angegeben wird.
- Die passende **Windows-ZIP-Ausgabe von VS Code**, bereits entpackt.
  Den ZIP-Download auf der [Downloadseite](https://code.visualstudio.com/download)
  verwenden, nicht den User-/System-Installer.
- Schreibrechte in beiden Zielverzeichnissen. VS Code waehrend des Setups
  schliessen, damit es die bearbeiteten Einstellungen nicht gleichzeitig speichert.
- Internetzugang zum Marketplace fuer die automatische Erweiterungsinstallation.
  `-SkipExtensionInstall` erlaubt eine Einrichtung ohne Downloads.

VS Code, PowerShell, Git, Node.js und PowerShell-Module werden **nicht** durch
dieses Skript heruntergeladen oder installiert. Administratorrechte sind bei
benutzerbeschreibbaren Zielverzeichnissen normalerweise nicht erforderlich.
Ziele muessen absolute lokale Windows-Pfade und getrennte Verzeichnisbaeume
sein; keine Laufwerkswurzeln, Netzwerkpfade, Junctions oder symbolischen Links.

## Schnellstart

Aus dem Stammordner dieser Skriptsammlung, mit eigenen Zielpfaden:

```powershell
# Vorschau: keine Dateien, Downloads oder Erweiterungsinstallationen
.\Utilities\VSCode\Initialize-VSCodeWorkspaces.ps1 `
    -VSCodePath 'D:\Apps\VSCode' `
    -WorkspaceRoot 'D:\Entwicklung' `
    -WhatIf

# Einrichtung inklusive der empfohlenen Erweiterungen
.\Utilities\VSCode\Initialize-VSCodeWorkspaces.ps1 `
    -VSCodePath 'D:\Apps\VSCode' `
    -WorkspaceRoot 'D:\Entwicklung'
```

Alternative ohne Downloads und mit explizitem PowerShell-Pfad:

```powershell
.\Utilities\VSCode\Initialize-VSCodeWorkspaces.ps1 `
    -VSCodePath 'D:\Apps\VSCode' `
    -WorkspaceRoot 'D:\Entwicklung' `
    -PowerShellPath 'C:\Program Files\PowerShell\7\pwsh.exe' `
    -SkipExtensionInstall
```

Anschliessend gezielt **diese portable Instanz** starten:

```powershell
& 'D:\Apps\VSCode\bin\code.cmd' --new-window 'D:\Entwicklung\PowerShell.code-workspace'
& 'D:\Apps\VSCode\bin\code.cmd' --new-window 'D:\Entwicklung\Webdesign.code-workspace'
```

Ein Doppelklick auf eine Workspace-Datei kann stattdessen eine andere,
systemweit zugeordnete VS-Code-Installation oeffnen. Fuer selbst angelegte,
gepruefte Projekte die normale Workspace-Vertrauensabfrage beantworten;
das Setup deaktiviert oder umgeht sie nicht.

## Erzeugte Struktur

```text
D:\Apps\VSCode\
  Code.exe
  bin\code.cmd
  data\
    argv.json                    Deutsche Oberflaeche
    extensions\                  Gemeinsame Erweiterungen
    tmp\                         Temporaere Dateien der portablen Instanz
    user-data\User\
      settings.json              Allgemeine Einstellungen und PowerShell-Pfad
      keybindings.json           Zusaetzliche Tastenkombinationen

D:\Entwicklung\
  PowerShell.code-workspace
  Webdesign.code-workspace
  SetupLogs\                     JSON-Berichte je Einrichtungslauf
  PowerShell\
    .vscode\
      settings.json
      extensions.json
      tasks.json
      launch.json
      powershell.code-snippets
    .editorconfig
    .gitignore
    Scripts\Hello-Workspace.ps1
    Tests\Hello-Workspace.Tests.ps1
    Modules\
    Docs\
    Data\
    Logs\
  Webdesign\
    .vscode\
      settings.json
      extensions.json
      tasks.json
      launch.json
      web.code-snippets
    .editorconfig
    .gitignore
    .prettierrc.json
    .stylelintrc.json
    eslint.config.mjs
    package.json
    src\
      index.html
      assets\
        css\main.css
        js\main.js
        images\
        fonts\
    Docs\
    Design\
    Tests\
    dist\
```

Alle JSON-Dateien werden als gueltiges JSON erzeugt, nicht als JSONC.
Vorhandene JSONC-Dateien mit Kommentaren werden trotzdem respektiert.
Die Workspace-Dateien referenzieren ihre Projektordner **relativ**.

## Einstellungen und Aufgaben

| Bereich | Vorgaben |
|---|---|
| PowerShell | Eingebautes Theme **Dark Modern**, vier Leerzeichen, UTF-8 mit BOM und CRLF fuer PowerShell-Dateien, Formatieren beim Speichern, OTBS-Formatierung, ScriptAnalyzer aktiviert |
| Webdesign | Eingebautes Theme **Light Modern**, zwei Leerzeichen, UTF-8 ohne BOM und LF, Prettier je Websprache, ESLint fuer JavaScript und Stylelint fuer CSS |
| Beide | Material-Dateisymbole, Schrift Consolas, Klammerfuehrungen, Zeilenmarkierung bei 100 Zeichen, deutsche/englische Rechtschreibpruefung |
| Allgemein | Deutsche Oberflaeche, Telemetrie aus, kein automatisches Speichern, PowerShell 7 als Terminal ohne Profilskripte |

Die Themes sind eingebaute VS-Code-Themes; dafuer ist kein Theme-Download
notwendig. Die deutsche Oberflaeche benoetigt das Sprachpaket und gegebenenfalls
einen Neustart. Ohne Erweiterungsinstallation fehlen auch Material-Symbole,
Formatter und andere Erweiterungsfunktionen.

Die `.code-workspace`-Dateien enthalten die Einstellungen ebenfalls, damit
fensterbezogene Optionen wie Themes und Erweiterungseinstellungen beim Oeffnen
eines gespeicherten Workspaces wirken. `.vscode\settings.json` ermoeglicht auch
das direkte Oeffnen eines Projektordners. **Keine laufende Synchronisation:**
Bei spaeteren Aenderungen beide Varianten passend pflegen. In einem gespeicherten
Workspace haben unterstuetzte Ordnereinstellungen Vorrang vor
Workspace-Einstellungen; fensterbezogene Optionen dort in der
`.code-workspace`-Datei anpassen.

### PowerShell

Unter **Terminal > Aufgabe ausfuehren**:

- `PowerShell: Syntax pruefen` analysiert rekursiv `.ps1`, `.psm1` und `.psd1`
  in `Scripts`, `Modules` und `Tests`, ohne sie auszufuehren.
  Bei Syntaxfehlern liefert die Aufgabe Exitcode 1.
- `PowerShell: Pester 5` fuehrt Tests in `Tests` aus und benoetigt
  **Pester ab Version 5**. Optional einmalig in PowerShell 7 installieren:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
```

Die PowerShell-Erweiterung bringt ScriptAnalyzer fuer ihre Editoranalyse mit.
Das Setup installiert weder Pester noch zusaetzliche PowerShell-Module.
Die Syntaxaufgabe prueft mit PowerShell 7; sie ist kein Kompatibilitaetsnachweis
fuer Windows PowerShell 5.1.

Der Debugger **PowerShell: Aktuelle Datei** fuehrt die geoeffnete Datei
tatsaechlich aus. Er fuegt nicht automatisch `-WhatIf` hinzu.
Das Snippet `ps-safe-script` erzeugt dagegen ein Geruest mit
`SupportsShouldProcess`, StrictMode und expliziter Fehlerbehandlung.

### Webdesign

Der Ausgangspunkt ist **HTML, CSS und Browser-JavaScript** ohne Framework.
HTML-Unterstuetzung, Emmet, verknuepfte Tag-Bearbeitung und Browser-Debugging
sind bereits in VS Code enthalten. Fuer TypeScript, SCSS, React oder andere
Frameworks sind projektspezifische Build-/Lint-Konfigurationen zusaetzlich
erforderlich; die Vorlage richtet diese nicht ein.

Fuer die npm-Pruefaufgaben eine passende Node.js-Version installieren:
unterstuetzt sind **22 ab 22.13 oder 24 und neuer**, empfohlen ist eine
aktuell unterstuetzte LTS-Version. Danach:

```powershell
Set-Location 'D:\Entwicklung\Webdesign'
npm install
npm run format:check
npm run lint:js
npm run lint:css

# Optional: Quelldateien mit Prettier formatieren
npm run format
```

`package.json` enthaelt aufeinander abgestimmte Entwicklungsabhaengigkeiten
fuer Prettier 3, ESLint 10, Stylelint 17 und deren Konfigurationen.
Das Setup selbst fuehrt **kein npm install** aus. Das erstmalige `npm install`
erzeugt `package-lock.json`; diese Datei fuer reproduzierbare Folgeinstallationen
aufbewahren und spaeter `npm ci` verwenden. Die angegebenen Versionsbereiche
erlauben kompatible Updates; sie sind keine feste Paketkopie.

Im Aufgabenmenue entsprechen `Web: Format pruefen`, `Web: JavaScript pruefen`
und `Web: CSS pruefen` diesen Befehlen. `Web: Alles pruefen` startet sie
nacheinander. ESLint und Stylelint brauchen auch im Editor die lokalen
Projektabhaengigkeiten; reines Editieren und Live Preview funktionieren ohne npm.

Fuer die Vorschau `src\index.html` oeffnen und **Live Preview: Start Server**
ueber die Befehlspalette starten, alternativ die eingerichtete Taste
**Strg+Alt+P** im HTML-Editor. Der Server verwendet `src` als Wurzel und
`127.0.0.1:3000`; er wird nicht automatisch gestartet und nicht fuer das
Netzwerk freigegeben. Aenderungen erscheinen nach dem Speichern.
Microsoft kennzeichnet die Erweiterung als Preview.

Erst danach den Debugger **Web: Edge (Live Preview zuerst starten)** verwenden.
Microsoft Edge muss installiert sein. Bei belegtem Port den Vorschauport in
den Einstellungen und die URL in `.vscode\launch.json` gemeinsam anpassen.
Private Dateien nicht in den veroeffentlichten `src`-Ordner legen.
Das Snippet `web-section` erzeugt einen semantischen HTML-Abschnitt.

**Strg+Alt+T** blendet in beiden Arbeitsbereichen das integrierte Terminal ein.

## Erweiterungen

Die 12 eindeutigen Erweiterungen werden in `data\extensions` gemeinsam fuer
beide Workspaces installiert. Das sind **zwei Workspaces, keine getrennten
VS-Code-Profile**. Die jeweiligen Empfehlungslisten unterscheiden sich;
installierte Erweiterungen sind aber grundsaetzlich in beiden verfuegbar.

| Erweiterungs-ID | Bereich | Zweck |
|---|---|---|
| `MS-CEINTL.vscode-language-pack-de` | Beide | Deutsche Oberflaeche |
| `PKief.material-icon-theme` | Beide | Dateitypen und Ordner visuell unterscheiden |
| `EditorConfig.EditorConfig` | Beide | Einheitliche Einrueckung und Zeilenenden |
| `streetsidesoftware.code-spell-checker` | Beide | Rechtschreibpruefung in Text und Bezeichnern |
| `streetsidesoftware.code-spell-checker-german` | Beide | Deutsches Woerterbuch |
| `yzhang.markdown-all-in-one` | Beide | README- und Markdown-Bearbeitung |
| `DavidAnson.vscode-markdownlint` | Beide | Markdown-Regeln und Hinweise |
| `ms-vscode.PowerShell` | PowerShell | IntelliSense, Debugger, Formatter und ScriptAnalyzer |
| `esbenp.prettier-vscode` | Webdesign | Formatierung fuer HTML, CSS, JavaScript und weitere Webdateien |
| `dbaeumer.vscode-eslint` | Webdesign | JavaScript-Analyse mit Projektkonfiguration |
| `stylelint.vscode-stylelint` | Webdesign | CSS-Analyse mit Projektkonfiguration |
| `ms-vscode.live-server` | Webdesign | Microsoft Live Preview |

`extensions.json` allein installiert nichts. Das Skript erledigt dies
zusaetzlich per `bin\code.cmd --install-extension` und prueft danach die
installierten IDs. Bereits installierte IDs werden nicht zwangsaktualisiert.
Bei `-SkipExtensionInstall` bleiben nur Empfehlungen; ein spaeterer normaler
Skriptlauf holt fehlende Erweiterungen nach. Marketplace-Verfuegbarkeit,
Proxy-/Netzwerkeinstellungen und Kompatibilitaet mit der verwendeten
VS-Code-Version koennen die Installation beeinflussen.

## Wiederholte Ausfuehrung, Sicherungen und Umzug

| Parameter | Wirkung |
|---|---|
| `-VSCodePath` | Pflicht: entpacktes VS-Code-ZIP-Verzeichnis |
| `-WorkspaceRoot` | Pflicht: gemeinsamer Elternordner der beiden Workspaces |
| `-PowerShellPath` | Optional: absoluter Pfad zu installiertem `pwsh.exe` |
| `-SkipExtensionInstall` | Keine VS-Code-CLI-Aufrufe und keine Downloads |
| `-OverwriteConfiguration` | Abweichende generierte Konfigurationen mit Sicherung ersetzen |
| `-WhatIf` | Nur planen; Voraussetzungen und Pfade trotzdem pruefen |
| `-Confirm` | Bestaetigung vor der Einrichtung anfordern |

Identische Dateien bleiben unveraendert. Abweichende vorhandene Dateien
werden standardmaessig **weder ersetzt noch zusammengefuehrt**; das Skript
warnt und meldet `PreservedExistingFiles`. Ein solcher erfolgreicher Lauf
heisst nicht, dass alle neuen Vorgaben in bestehende Konfigurationen
uebernommen wurden.

Mit `-OverwriteConfiguration` werden abweichende Konfigurationen vollstaendig
auf die Vorlagen zurueckgesetzt, einschliesslich `settings.json`,
`keybindings.json`, `argv.json`, Workspace-, npm- und Lint-Konfigurationen.
Jede ersetzte Datei erhaelt eine bytegenaue Sicherung neben sich:
`<Dateiname>.setup-backup-<eindeutige ID>`.
Kommentare und individuelle Einstellungen bleiben dann nur in der Sicherung,
nicht in der neu erzeugten Datei.

Die Beispielquellen und Beispieltests werden **auch mit diesem Schalter
niemals ueberschrieben**. Neue Konfigurationsdateien werden ueber temporaere
Nachbardateien veroeffentlicht; vorhandene werden mit Sicherung atomar ersetzt.
Der gesamte Einrichtungslauf ist keine Transaktion: Bei Teilfehlern bleiben
bereits erstellte Dateien erhalten. Nicht parallel mehrfach ausfuehren.

Auf einen anderen Rechner den VS-Code-Ordner **einschliesslich `data`**
und den Workspace-Stamm kopieren. Relative Workspace-Pfade bleiben dabei
gueltig, die Pfade zum **installierten PowerShell** in User-Einstellungen und
PowerShell-Aufgaben aber nicht zwingend. Diese gezielt bearbeiten oder das
Setup mit neuem `-PowerShellPath` und bewusst gewaehltem
`-OverwriteConfiguration` erneut ausfuehren. Letzteres setzt auch andere
generierte Konfigurationen zurueck.

Die portable ZIP-Ausgabe von VS Code aktualisiert sich unter Windows nicht
automatisch. Fuer ein Update eine neue ZIP-Ausgabe verwenden und `data`
uebernehmen. Das Setup richtet kein Settings Sync ein, aendert keine
Ausfuehrungsrichtlinien und startet weder VS Code noch Vorschau-Server.
Gespeicherte Zugangsdaten einzelner Erweiterungen sind gegebenenfalls an das
Betriebssystemkonto gebunden; Portable Mode garantiert deren Umzug nicht.

## Berichte, Exitcodes und Tests

Jeder ausgefuehrte Lauf schreibt einen eigenen JSON-Bericht nach
`<WorkspaceRoot>\SetupLogs`. Er enthaelt Dateiaktionen, Erweiterungsergebnisse
und Fehlermeldungen. Im Ergebnisobjekt stehen Status, Berichtspfad,
Workspace-Pfade und `ExtensionInstallSkipped`.

| Exitcode | Bedeutung |
|---|---|
| `0` | Fertig, vorhandene Dateien bewusst erhalten, Vorschau oder Bestaetigung abgelehnt; Status beachten |
| `1` | Abbruch, etwa ungueltiger Pfad, fehlende Voraussetzung oder nicht schreibbarer Bericht |
| `2` | Fehler bei einzelnen Dateien oder Erweiterungen; Bericht pruefen |

`-WhatIf` liefert `Planned`, eine abgelehnte Bestaetigung `Skipped`;
beide schreiben keinen Bericht. Bei Fehlern vor der Berichterstellung
steht die Diagnose nur auf der Fehlerausgabe.

Die [Regressionstests](../../Testing/VSCode.Workspaces.Tests.ps1) mit
[Testdokumentation](../../Testing/README.md) verwenden **Pester 3.4.0**,
isolierte Dateibaeume und eine gemockte Installations-CLI. Das ist eine andere
Voraussetzung als **Pester 5 fuer die neu erzeugten Beispieltests**.
Sie installieren keine echten VS-Code-Erweiterungen. Aus dem Sammlungsstamm:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script '.\Testing\VSCode.Workspaces.Tests.ps1' -PassThru
if ($result.FailedCount) { throw "$($result.FailedCount) Tests fehlgeschlagen." }
```

Die Tests decken Struktur, JSON, Empfehlungen, Wiederholung, Sicherungen,
Pfadkonflikte, `-WhatIf`, native Exitcodes, Fehlerberichte, Snippets und die
generierte Syntaxaufgabe ab. Sie ersetzen keinen Test mit der konkret
verwendeten VS-Code-Ausgabe und ihrem Marketplace-Zugang.

## Quellen

- [VS Code Portable Mode](https://code.visualstudio.com/docs/setup/portable)
- [VS Code Kommandozeile](https://code.visualstudio.com/docs/configure/command-line)
- [Gespeicherte Workspaces und Einstellungsebenen](https://code.visualstudio.com/docs/editing/workspaces/multi-root-workspaces)
- [PowerShell-Erweiterung](https://github.com/PowerShell/vscode-powershell)
- [Microsoft Live Preview](https://github.com/microsoft/vscode-livepreview)
- [VS Code HTML-Unterstuetzung](https://code.visualstudio.com/docs/languages/html)
