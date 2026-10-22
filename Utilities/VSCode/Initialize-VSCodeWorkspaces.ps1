#requires -Version 5.1

<#
.SYNOPSIS
Richtet portables VS Code fuer PowerShell und Webdesign ein.
.DESCRIPTION
Erwartet die entpackte Windows-ZIP-Ausgabe von VS Code und installiertes
PowerShell 7. Erstellt zwei Workspaces und installiert standardmaessig
empfohlene Erweiterungen. Bestehende Dateien bleiben standardmaessig erhalten.
.PARAMETER VSCodePath
Ordner der entpackten VS-Code-ZIP-Ausgabe mit Code.exe und bin\code.cmd.
.PARAMETER WorkspaceRoot
Ziel fuer die Workspaces PowerShell und Webdesign samt Unterordnern.
.PARAMETER PowerShellPath
Optionaler absoluter Pfad zu installiertem pwsh.exe. Sonst Suche ueber PATH.
.PARAMETER SkipExtensionInstall
Nur Struktur und Konfiguration erzeugen, ohne CLI-Aufrufe oder Downloads.
.PARAMETER OverwriteConfiguration
Abweichende Konfigurationen nach bytegenauer Sicherung ersetzen.
Beispieldateien werden niemals ueberschrieben.
.LINK
README.md
.EXAMPLE
.\Initialize-VSCodeWorkspaces.ps1 -VSCodePath 'D:\Apps\VSCode' -WorkspaceRoot 'D:\Entwicklung' -WhatIf
.EXAMPLE
.\Initialize-VSCodeWorkspaces.ps1 -VSCodePath 'D:\Apps\VSCode' -WorkspaceRoot 'D:\Entwicklung'
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VSCodePath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WorkspaceRoot,
    [string]$PowerShellPath,
    [switch]$SkipExtensionInstall,
    [switch]$OverwriteConfiguration
)

function Get-VSCodeSafePath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[*?]' -or
        $Path.Substring(2).Contains(':')) {
        throw "Ein absoluter lokaler Windows-Pfad ist erforderlich: $Path"
    }
    foreach ($name in ($Path.Substring(3) -split '\\')) {
        if ($name -in '', '.', '..') { continue }
        if ($name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
            $name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' -or $name -match '[. ]$') {
            throw "Ungueltiger Windows-Pfadbestandteil: $name"
        }
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) {
        throw "Keine Laufwerkswurzel als Ziel verwenden: $Path"
    }
    $probe = $full
    while ($probe) {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Umgeleitete Pfade werden nicht verwendet: $probe"
            }
            if ($probe -ne $full -and -not $item.PSIsContainer) {
                throw "Uebergeordneter Pfad ist eine Datei: $probe"
            }
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
    return $full
}

function Invoke-VSCodeCli {
    param([string]$Executable, [string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Programm nicht gefunden: $Executable"
    }
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $global:LASTEXITCODE = $null
    $output = @(& $Executable @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $global:LASTEXITCODE
    if ($null -eq $code) { throw "Programmstart ohne Exitcode: $Executable" }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Get-VSCodeExtensionCatalog {
    $common = @(
        'MS-CEINTL.vscode-language-pack-de'
        'PKief.material-icon-theme'
        'EditorConfig.EditorConfig'
        'streetsidesoftware.code-spell-checker'
        'streetsidesoftware.code-spell-checker-german'
        'yzhang.markdown-all-in-one'
        'DavidAnson.vscode-markdownlint'
    )
    return @{
        PowerShell = @($common) + @('ms-vscode.PowerShell')
        Webdesign = @($common) + @(
            'esbenp.prettier-vscode'
            'dbaeumer.vscode-eslint'
            'stylelint.vscode-stylelint'
            'ms-vscode.live-server'
        )
    }
}

function Get-VSCodeSetupFiles {
    param([string]$CodeRoot, [string]$Root, [string]$ShellPath)
    $catalog = Get-VSCodeExtensionCatalog
    $files = [Collections.Generic.List[object]]::new()
    function Add-SetupFile {
        param([string]$Path, $Value, [switch]$Text, [switch]$Seed)
        $content = if ($Text) { [string]$Value } else { ConvertTo-Json -InputObject $Value -Depth 20 }
        $content = ($content -replace "`r`n?", "`n").TrimEnd() + "`n"
        if ([IO.Path]::GetExtension($Path) -in '.ps1','.psm1','.psd1') {
            $content = $content.Replace("`n", "`r`n")
        }
        $files.Add([pscustomobject]@{
            Path = $Path; Content = $content; Seed = [bool]$Seed
        })
    }
    $user = Join-Path $CodeRoot 'data\user-data\User'
    Add-SetupFile (Join-Path $user 'settings.json') ([ordered]@{
        'security.workspace.trust.enabled' = $true
        'telemetry.telemetryLevel' = 'off'
        'extensions.ignoreRecommendations' = $false
        'files.autoSave' = 'off'
        'editor.minimap.enabled' = $false
        'editor.renderWhitespace' = 'selection'
        'editor.bracketPairColorization.enabled' = $true
        'editor.guides.bracketPairs' = $true
        'editor.fontFamily' = "Consolas, 'Courier New', monospace"
        'editor.fontSize' = 14
        'workbench.startupEditor' = 'welcomePage'
        'workbench.iconTheme' = 'material-icon-theme'
        'window.autoDetectColorScheme' = $false
        'terminal.integrated.defaultProfile.windows' = 'PowerShell 7'
        'terminal.integrated.profiles.windows' = @{
            'PowerShell 7' = @{ path = $ShellPath; args = @('-NoLogo','-NoProfile') }
        }
        'powershell.powerShellAdditionalExePaths' = @{ 'PowerShell 7 (Setup)' = $ShellPath }
        'powershell.powerShellDefaultVersion' = 'PowerShell 7 (Setup)'
        'cSpell.language' = 'en,de'
    })
    Add-SetupFile (Join-Path $user 'keybindings.json') @(
        @{ key = 'ctrl+alt+t'; command = 'workbench.action.terminal.toggleTerminal' }
        @{ key = 'ctrl+alt+p'; command = 'livePreview.start'; when = "editorLangId == html" }
    )
    Add-SetupFile (Join-Path $CodeRoot 'data\argv.json') @{ locale = 'de' }

    foreach ($kind in @('PowerShell','Webdesign')) {
        $folder = Join-Path $Root $kind
        $settings = [ordered]@{
            'files.encoding' = 'utf8'
            'files.eol' = "`n"
            'files.insertFinalNewline' = $true
            'files.trimTrailingWhitespace' = $true
            'editor.insertSpaces' = $true
            'editor.detectIndentation' = $false
            'editor.tabSize' = 2
            'editor.rulers' = @(100)
            'cSpell.language' = 'en,de'
            'search.exclude' = @{ '**/node_modules' = $true; '**/dist' = $true; '**/Logs' = $true }
            'files.watcherExclude' = @{ '**/node_modules/**' = $true; '**/dist/**' = $true }
        }
        $theme = if ($kind -eq 'PowerShell') { 'Default Dark Modern' } else { 'Default Light Modern' }
        $settings['workbench.colorTheme'] = $theme
        if ($kind -eq 'PowerShell') {
            $settings['[powershell]'] = @{
                'editor.defaultFormatter' = 'ms-vscode.PowerShell'
                'editor.formatOnSave' = $true
                'editor.tabSize' = 4
                'files.encoding' = 'utf8bom'
                'files.eol' = "`r`n"
            }
            $settings['powershell.scriptAnalysis.enable'] = $true
            $settings['powershell.codeFormatting.preset'] = 'OTBS'
            $settings['powershell.enableProfileLoading'] = $false
            $settings['files.associations'] = @{ '*.ps1' = 'powershell'; '*.psm1' = 'powershell'; '*.psd1' = 'powershell' }
            $syntax = @'
$ErrorActionPreference = 'Stop'
$failed = $false
foreach ($file in Get-ChildItem -LiteralPath .\Scripts,.\Modules,.\Tests -Recurse -File | Where-Object Extension -in '.ps1','.psm1','.psd1') {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in $errors) {
        [Console]::Error.WriteLine(('{0}:{1}: {2}' -f $file.FullName, $parseError.Extent.StartLineNumber, $parseError.Message))
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Host 'Syntaxpruefung erfolgreich.'
'@
            Add-SetupFile (Join-Path $folder '.vscode\tasks.json') @{
                version = '2.0.0'
                tasks = @(
                    @{
                        label = 'PowerShell: Syntax pruefen'; type = 'process'; command = $ShellPath
                        args = @('-NoProfile','-NonInteractive','-Command',$syntax)
                        options = @{ cwd = '${workspaceFolder}' }; problemMatcher = @()
                        group = @{ kind = 'test'; isDefault = $true }
                    }
                    @{
                        label = 'PowerShell: Pester 5'; type = 'process'; command = $ShellPath
                        args = @('-NoProfile','-NonInteractive','-Command',
                            '$ErrorActionPreference = ''Stop''; Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop; Invoke-Pester -Path .\Tests -CI')
                        options = @{ cwd = '${workspaceFolder}' }; problemMatcher = @()
                    }
                )
            }
            Add-SetupFile (Join-Path $folder '.vscode\launch.json') @{
                version = '0.2.0'
                configurations = @(@{
                    type = 'PowerShell'; request = 'launch'; name = 'PowerShell: Aktuelle Datei'
                    script = '${file}'; args = @(); cwd = '${workspaceFolder}'
                })
            }
            Add-SetupFile (Join-Path $folder '.vscode\powershell.code-snippets') @{
                'Skript mit ShouldProcess' = @{
                    prefix = 'ps-safe-script'; scope = 'powershell'
                    description = 'Skriptgeruest mit WhatIf-Unterstuetzung'
                    body = @(
                        '[CmdletBinding(SupportsShouldProcess)]'
                        'param([Parameter(Mandatory)][string]\$Path)'
                        ''
                        'Set-StrictMode -Version Latest'
                        "\`$ErrorActionPreference = 'Stop'"
                        ''
                        'if (\$PSCmdlet.ShouldProcess(\$Path, "${1:Aktion}")) {'
                        '    $0'
                        '}'
                    )
                }
            }
            Add-SetupFile (Join-Path $folder 'Scripts\Hello-Workspace.ps1') -Seed -Text @'
#requires -Version 7.0
[CmdletBinding()]
param([string]$Name = 'Welt')
Write-Output "Hallo, $Name!"
'@
            Add-SetupFile (Join-Path $folder 'Tests\Hello-Workspace.Tests.ps1') -Seed -Text @'
Describe 'Hello-Workspace' {
    It 'begruesst den angegebenen Namen' {
        & (Join-Path $PSScriptRoot '..\Scripts\Hello-Workspace.ps1') -Name 'VS Code' |
            Should -Be 'Hallo, VS Code!'
    }
}
'@
            Add-SetupFile (Join-Path $folder '.editorconfig') -Text @'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.{ps1,psm1,psd1}]
charset = utf-8-bom
end_of_line = crlf
indent_size = 4
'@
        }
        else {
            foreach ($language in @('html','css','scss','javascript','javascriptreact','typescript','typescriptreact','json','jsonc','markdown')) {
                $settings["[$language]"] = @{
                    'editor.defaultFormatter' = 'esbenp.prettier-vscode'
                    'editor.formatOnSave' = $true
                }
            }
            $settings['editor.linkedEditing'] = $true
            $settings['emmet.triggerExpansionOnTab'] = $true
            $settings['prettier.requireConfig'] = $true
            $settings['eslint.validate'] = @('javascript')
            $settings['stylelint.validate'] = @('css')
            $settings['livePreview.hostIP'] = '127.0.0.1'
            $settings['livePreview.portNumber'] = 3000
            $settings['livePreview.serverRoot'] = 'src'
            $settings['livePreview.defaultPreviewPath'] = '/index.html'
            $settings['livePreview.autoRefreshPreview'] = 'On Changes to Saved Files'
            Add-SetupFile (Join-Path $folder '.vscode\tasks.json') @{
                version = '2.0.0'
                tasks = @(
                    @{ label = 'Web: Format pruefen'; type = 'npm'; script = 'format:check'; problemMatcher = @() }
                    @{ label = 'Web: JavaScript pruefen'; type = 'npm'; script = 'lint:js'; problemMatcher = @('$eslint-stylish') }
                    @{ label = 'Web: CSS pruefen'; type = 'npm'; script = 'lint:css'; problemMatcher = @() }
                    @{
                        label = 'Web: Alles pruefen'
                        dependsOn = @('Web: Format pruefen','Web: JavaScript pruefen','Web: CSS pruefen')
                        dependsOrder = 'sequence'; problemMatcher = @()
                        group = @{ kind = 'test'; isDefault = $true }
                    }
                )
            }
            Add-SetupFile (Join-Path $folder '.vscode\launch.json') @{
                version = '0.2.0'
                configurations = @(@{
                    name = 'Web: Edge (Live Preview zuerst starten)'; type = 'msedge'; request = 'launch'
                    url = 'http://127.0.0.1:3000'; webRoot = '${workspaceFolder}\src'
                })
            }
            Add-SetupFile (Join-Path $folder '.vscode\web.code-snippets') @{
                'Semantischer Abschnitt' = @{
                    prefix = 'web-section'; scope = 'html'; description = 'Abschnitt mit beschrifteter Ueberschrift'
                    body = @('<section aria-labelledby="${1:section}-title">','  <h2 id="${1:section}-title">${2:Titel}</h2>','  $0','</section>')
                }
            }
            Add-SetupFile (Join-Path $folder '.prettierrc.json') @{
                semi = $true; singleQuote = $true; tabWidth = 2; trailingComma = 'all'; printWidth = 100; endOfLine = 'lf'
            }
            Add-SetupFile (Join-Path $folder '.stylelintrc.json') @{ extends = @('stylelint-config-standard') }
            Add-SetupFile (Join-Path $folder 'package.json') @{
                name = 'webdesign-workspace'; version = '1.0.0'; private = $true; type = 'module'
                engines = @{ node = '^22.13.0 || >=24.0.0' }
                scripts = @{
                    'format:check' = 'prettier --check "src/**/*.{html,css,js,json}"'
                    format = 'prettier --write "src/**/*.{html,css,js,json}"'
                    'lint:js' = 'eslint src'
                    'lint:css' = 'stylelint "src/**/*.css"'
                }
                devDependencies = @{
                    prettier = '^3.9.10'; eslint = '^10.13.0'; '@eslint/js' = '^10.0.1'
                    globals = '^17.13.0'; stylelint = '^17.16.0'; 'stylelint-config-standard' = '^40.0.0'
                }
            }
            Add-SetupFile (Join-Path $folder 'eslint.config.mjs') -Text @'
import js from '@eslint/js';
import globals from 'globals';

export default [
  { ignores: ['node_modules/**', 'dist/**'] },
  {
    files: ['src/**/*.js'],
    ...js.configs.recommended,
    languageOptions: { ecmaVersion: 'latest', sourceType: 'module', globals: globals.browser },
  },
];
'@
            Add-SetupFile (Join-Path $folder '.editorconfig') -Text @'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2
'@
            Add-SetupFile (Join-Path $folder 'src\index.html') -Seed -Text @'
<!doctype html>
<html lang="de">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Webdesign</title>
    <link rel="stylesheet" href="assets/css/main.css" />
    <script type="module" src="assets/js/main.js"></script>
  </head>
  <body>
    <main>
      <h1>Mein Webprojekt</h1>
      <p id="status" role="status">Bereit fuer die Gestaltung.</p>
      <button type="button" id="hello">Beispiel testen</button>
    </main>
  </body>
</html>
'@
            Add-SetupFile (Join-Path $folder 'src\assets\css\main.css') -Seed -Text @'
:root {
  font-family: system-ui, sans-serif;
  color: #172033;
  background: #f4f6fa;
}

main {
  max-width: 60rem;
  margin: 4rem auto;
  padding: 2rem;
}

button {
  padding: 0.75rem 1rem;
  font: inherit;
  cursor: pointer;
}

button:focus-visible {
  outline: 3px solid #1257bd;
  outline-offset: 3px;
}
'@
            Add-SetupFile (Join-Path $folder 'src\assets\js\main.js') -Seed -Text @'
document.querySelector('#hello').addEventListener('click', () => {
  document.querySelector('#status').textContent = 'HTML, CSS und JavaScript sind verbunden.';
});
'@
        }
        Add-SetupFile (Join-Path $folder '.vscode\settings.json') $settings
        Add-SetupFile (Join-Path $folder '.vscode\extensions.json') @{ recommendations = @($catalog[$kind]) }
        # Folder settings cannot supply window-scoped options in a saved workspace.
        $workspaceSettings = [ordered]@{}
        foreach ($key in $settings.Keys) { $workspaceSettings[$key] = $settings[$key] }
        $workspaceSettings['workbench.iconTheme'] = 'material-icon-theme'
        Add-SetupFile (Join-Path $Root "$kind.code-workspace") @{
            folders = @(@{ name = $kind; path = $kind })
            settings = $workspaceSettings
            extensions = @{ recommendations = @($catalog[$kind]) }
        }
        Add-SetupFile (Join-Path $folder '.gitignore') -Text @'
node_modules/
dist/
Logs/
*.bak
*.setup-backup-*
'@
    }
    return $files.ToArray()
}

function Write-VSCodeSetupFile {
    param($File, [switch]$Overwrite)
    $path = Get-VSCodeSafePath $File.Path
    $content = $File.Content
    $existed = [IO.File]::Exists($path)
    if ([IO.Directory]::Exists($path)) { throw "Dateiziel ist ein Verzeichnis: $path" }
    if ($existed) {
        if ([IO.File]::ReadAllText($path) -ceq $content) { return 'Unchanged' }
        if ($File.Seed -or -not $Overwrite) {
            Write-Warning "Bestehende Datei bleibt unveraendert: $path"
            return 'Preserved'
        }
    }
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    $stage = "$path.setup-stage-$([guid]::NewGuid().ToString('N'))"
    try {
        $bom = [IO.Path]::GetExtension($path) -in '.ps1','.psm1','.psd1'
        [IO.File]::WriteAllText($stage, $content, [Text.UTF8Encoding]::new($bom))
        if ($existed) {
            $backup = "$path.setup-backup-$([guid]::NewGuid().ToString('N'))"
            [IO.File]::Replace($stage, $path, $backup)
            Write-Host "Sicherung: $backup"
            return 'Replaced'
        }
        [IO.File]::Move($stage, $path)
        return 'Created'
    }
    finally {
        if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) }
    }
}

function Invoke-VSCodeWorkspaceSetup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$VSCodePath, [string]$WorkspaceRoot, [string]$PowerShellPath,
        [switch]$SkipExtensionInstall, [switch]$OverwriteConfiguration
    )
    $ErrorActionPreference = 'Stop'
    $codeRoot = Get-VSCodeSafePath $VSCodePath
    $root = Get-VSCodeSafePath $WorkspaceRoot
    if ($root -ieq $codeRoot -or $root.StartsWith($codeRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $codeRoot.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'VS-Code-Verzeichnis und WorkspaceRoot muessen getrennte Verzeichnisbaeume sein.'
    }
    foreach ($required in @('Code.exe','bin\code.cmd','resources\app\product.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $codeRoot $required) -PathType Leaf)) {
            throw "VS-Code-ZIP-Ausgabe unvollstaendig: $required fehlt in $codeRoot"
        }
    }
    if (@(Get-ChildItem -LiteralPath $codeRoot -Filter 'unins*.exe' -File).Count) {
        throw 'VS-Code-Installer-Ausgabe erkannt. Portable Mode benoetigt die Windows-ZIP-Ausgabe.'
    }
    if (-not $PowerShellPath) {
        $command = Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $PowerShellPath = $command.Source
    }
    $shellPath = Get-VSCodeSafePath $PowerShellPath
    if (-not (Test-Path -LiteralPath $shellPath -PathType Leaf) -or [IO.Path]::GetFileName($shellPath) -ine 'pwsh.exe') {
        throw "PowerShell 7 (pwsh.exe) nicht gefunden: $shellPath"
    }
    $files = @(Get-VSCodeSetupFiles $codeRoot $root $shellPath)
    $directories = @(
        (Join-Path $codeRoot 'data\extensions')
        (Join-Path $codeRoot 'data\tmp')
        (Join-Path $root 'SetupLogs')
    )
    foreach ($relative in @('Scripts','Modules','Tests','Docs','Data','Logs')) {
        $directories += Join-Path $root "PowerShell\$relative"
    }
    foreach ($relative in @('src\assets\images','src\assets\fonts','Docs','Design','Tests','dist')) {
        $directories += Join-Path $root "Webdesign\$relative"
    }
    foreach ($path in $directories + @($files.Path)) {
        $null = Get-VSCodeSafePath $path
        if ($path -in $directories -and [IO.File]::Exists($path)) { throw "Ordnerziel ist eine Datei: $path" }
        if ($path -in $files.Path -and [IO.Directory]::Exists($path)) { throw "Dateiziel ist ein Ordner: $path" }
    }
    $catalog = Get-VSCodeExtensionCatalog
    $extensions = @($catalog.PowerShell + $catalog.Webdesign | Sort-Object -Unique)
    if (-not $PSCmdlet.ShouldProcess("$codeRoot; $root",
            "Portable Daten und $($files.Count) Dateien initialisieren; Erweiterungen installieren=$(-not $SkipExtensionInstall)")) {
        $status = if ($WhatIfPreference) { 'Planned' } else { 'Skipped' }
        return [pscustomobject]@{ Status = $status; ExitCode = 0; Files = $files.Path; Extensions = $extensions }
    }
    $results = [Collections.Generic.List[object]]::new()
    $failed = $false
    foreach ($directory in $directories) { $null = [IO.Directory]::CreateDirectory($directory) }
    foreach ($file in $files) {
        try {
            $status = Write-VSCodeSetupFile $file -Overwrite:$OverwriteConfiguration
            $results.Add([pscustomobject]@{ Kind = 'File'; Target = $file.Path; Status = $status; Message = '' })
        }
        catch {
            $failed = $true
            Write-Warning "$($file.Path): $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Kind = 'File'; Target = $file.Path; Status = 'Failed'; Message = $_.Exception.Message })
        }
    }
    if (-not $SkipExtensionInstall -and -not $failed) {
        $oldPortable = $env:VSCODE_PORTABLE
        try {
            $env:VSCODE_PORTABLE = Join-Path $codeRoot 'data'
            $cli = Join-Path $codeRoot 'bin\code.cmd'
            $listed = Invoke-VSCodeCli $cli @('--list-extensions')
            if ($listed.ExitCode -ne 0) { throw "Erweiterungsabfrage fehlgeschlagen: $($listed.Output -join '; ')" }
            $installed = @($listed.Output | ForEach-Object { $_.Trim() })
            foreach ($id in $extensions) {
                $response = if ($id -in $installed) {
                    [pscustomobject]@{ ExitCode = 0; Output = @('Bereits installiert; kein erzwungenes Update.') }
                }
                else { Invoke-VSCodeCli $cli @('--install-extension',$id,'--force') }
                $status = if ($response.ExitCode -eq 0) { 'Installed' } else { 'Failed' }
                if ($status -eq 'Failed') { $failed = $true; Write-Warning "Installation fehlgeschlagen: $id" }
                $results.Add([pscustomobject]@{ Kind = 'Extension'; Target = $id; Status = $status; Message = ($response.Output -join "`n") })
            }
            $verified = Invoke-VSCodeCli $cli @('--list-extensions')
            if ($verified.ExitCode -ne 0) { throw "Abschlusspruefung fehlgeschlagen: $($verified.Output -join '; ')" }
            foreach ($id in $extensions) {
                if ($id -notin @($verified.Output | ForEach-Object { $_.Trim() })) {
                    $failed = $true
                    Write-Warning "Erweiterung fehlt nach Installation: $id"
                    $results.Add([pscustomobject]@{ Kind = 'Extension'; Target = $id; Status = 'Failed'; Message = 'In Abschlusspruefung nicht vorhanden.' })
                }
            }
        }
        catch {
            $failed = $true
            Write-Warning $_.Exception.Message
            $results.Add([pscustomobject]@{ Kind = 'CLI'; Target = $codeRoot; Status = 'Failed'; Message = $_.Exception.Message })
        }
        finally { $env:VSCODE_PORTABLE = $oldPortable }
    }
    $report = Join-Path $root ("SetupLogs\Setup-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
    $null = Write-VSCodeSetupFile ([pscustomobject]@{
        Path = $report; Content = (ConvertTo-Json -InputObject @($results.ToArray()) -Depth 5); Seed = $false
    })
    Write-Host "Bericht: $report"
    $status = if ($failed) { 'Failed' } elseif (@($results | Where-Object Status -eq 'Preserved').Count) { 'PreservedExistingFiles' } else { 'Completed' }
    return [pscustomobject]@{
        Status = $status; ExitCode = $(if ($failed) { 2 } else { 0 }); Report = $report
        Workspaces = @((Join-Path $root 'PowerShell.code-workspace'), (Join-Path $root 'Webdesign.code-workspace'))
        ExtensionInstallSkipped = [bool]$SkipExtensionInstall
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    $result = Invoke-VSCodeWorkspaceSetup -VSCodePath $VSCodePath -WorkspaceRoot $WorkspaceRoot `
        -PowerShellPath $PowerShellPath -SkipExtensionInstall:$SkipExtensionInstall `
        -OverwriteConfiguration:$OverwriteConfiguration -WhatIf:$WhatIfPreference
    $result
    exit $result.ExitCode
}
catch {
    Write-Error "Einrichtung abgebrochen: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
