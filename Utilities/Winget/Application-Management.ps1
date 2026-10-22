#requires -Version 5.1

<#
.SYNOPSIS
Gemeinsamer Anwendungskatalog und Installations-/Update-Verarbeitung.
.DESCRIPTION
Laden definiert Funktionen und laedt den Versionshelfer, ohne Paketaktionen.
README.md dokumentiert Einstiegsskripte, Konfiguration und Voraussetzungen.
.LINK
README.md
#>
. (Join-Path $PSScriptRoot 'Application-VersionPolicy.ps1')

function Get-ApplicationGroups {
    param(
        [string]$InstalledToolsRoot = 'C:\Tools',
        [string]$PortableToolsRoot = 'D:\Tools'
    )

# Gruppe 1: winget verwendet das vom jeweiligen Paket definierte Standardverzeichnis.
$standardApplications = @(
    [pscustomobject]@{ Name = 'Adobe Acrobat Reader';  Id = 'Adobe.Acrobat.Reader.64-bit' }
    [pscustomobject]@{ Name = 'Affinity';              Id = 'Canva.Affinity'; InstallerType = 'msix' }
    [pscustomobject]@{
        Name = 'CLIP STUDIO PAINT'; Id = 'Celsys.ClipStudioPaint'
        VersionPolicy = 'Celsys.ClipStudioPaint'; InstallerType = 'exe'
    }
    [pscustomobject]@{ Name = 'PaintDotNet';            Id = 'dotPDN.PaintDotNet' }
    [pscustomobject]@{ Name = 'Epson Scan 2';           Id = 'EPSON.EpsonScan2' }
    [pscustomobject]@{ Name = 'Epson Software Updater'; Id = 'EPSON.SoftwareUpdater' }
    [pscustomobject]@{ Name = 'Gimp';                   Id = 'GIMP.GIMP' }
    [pscustomobject]@{ Name = 'AusweisApp';             Id = 'Governikus.AusweisApp'; Locale = 'de-DE' }
    [pscustomobject]@{ Name = 'Logi Options+';          Id = 'Logitech.OptionsPlus' }
    [pscustomobject]@{ Name = 'PowerShell';             Id = 'Microsoft.PowerShell' }
    [pscustomobject]@{ Name = 'PowerToys';              Id = 'Microsoft.PowerToys' }
    [pscustomobject]@{ Name = 'WSL';                    Id = 'Microsoft.WSL' }
    [pscustomobject]@{ Name = 'Mozilla Firefox (Deutsch)';     Id = 'Mozilla.Firefox.de' }
    [pscustomobject]@{ Name = 'Mozilla Thunderbird (Deutsch)'; Id = 'Mozilla.Thunderbird.de' }
    [pscustomobject]@{ Name = 'Obsidian';               Id = 'Obsidian.Obsidian' }
    [pscustomobject]@{ Name = 'WinRAR (Deutsch)';       Id = 'RARLab.WinRAR'; Locale = 'de' }
    [pscustomobject]@{ Name = 'Raspberry Pi Imager';    Id = 'RaspberryPiFoundation.RaspberryPiImager' }
    [pscustomobject]@{ Name = 'cyberJack Driver';       Id = 'REINERSCT.cyberJackDriverPackage' }
    [pscustomobject]@{ Name = 'Yubico Authenticator';   Id = 'Yubico.Authenticator' }
    [pscustomobject]@{ Name = 'YubiKey Manager';        Id = 'Yubico.YubikeyManager' }
)

# Gruppe 2: Installierte Werkzeuge mit benutzerdefiniertem Zielverzeichnis.
# Ihre Konfiguration liegt weiterhin im Benutzerprofil oder in der Registry.
$installedToolsApplications = @(
    [pscustomobject]@{
        Name = 'eM Client'; Id = 'eMClient.eMClient'; Directory = 'eMClient'
        Executable = 'MailClient.exe'; InstallerType = 'wix'; Scope = 'machine'
    }
    [pscustomobject]@{
        Name = 'MP3tag'; Id = 'FlorianHeidenreich.Mp3tag'; Directory = 'MP3tag'
        Executable = 'Mp3tag.exe'; InstallerType = ''; Scope = ''
    }
    [pscustomobject]@{
        Name = 'LibreCAD'; Id = 'LibreCAD.LibreCAD'; Directory = 'LibreCAD'
        Executable = 'LibreCAD.exe'; InstallerType = 'nullsoft'; Scope = 'machine'
    }
    [pscustomobject]@{
        Name = 'pdfSAM'; Id = 'PDFsam.PDFsam'; Directory = 'pdfSAM'
        Executable = 'pdfsam.exe'; InstallerType = 'wix'; Scope = 'machine'
    }
    [pscustomobject]@{
        Name = 'PuTTY'; Id = 'PuTTY.PuTTY'; Directory = 'PuTTY'
        Executable = 'putty.exe'; InstallerType = 'wix'; Scope = 'machine'
    }
    [pscustomobject]@{
        Name = 'XnConvert'; Id = 'XnSoft.XnConvert'; Directory = 'XnConvert'
        Executable = 'xnconvert.exe'; InstallerType = ''; Scope = ''
    }
    [pscustomobject]@{
        Name = 'XnView'; Id = 'XnSoft.XnView.Classic'; Directory = 'XnView'
        Executable = 'xnview.exe'; InstallerType = ''; Scope = ''
    }
)

# Gruppe 3: Portable Werkzeuge mit Konfiguration im jeweiligen Programmverzeichnis.
$portableToolsApplications = @(
    [pscustomobject]@{
        Name = 'KeePass (Deutsch)'; Id = 'DominikReichl.KeePass'; Directory = 'KeePass'
        Executable = 'KeePass.exe'; InstallerType = 'inno'; Scope = 'machine'
        VersionPolicy = 'DominikReichl.KeePass'; LocalConfig = 'KeePassGerman'
    }
    [pscustomobject]@{
        Name = 'FreAC'; Id = 'enzo1982.freac'; Directory = 'FreAC'
        Executable = 'freac.exe'; InstallerType = 'portable'; Scope = ''; LocalConfig = 'None'
    }
    [pscustomobject]@{
        Name = 'KeepassXC'; Id = 'KeePassXCTeam.KeePassXC'; Directory = 'KeepassXC'
        Executable = 'KeePassXC.exe'; InstallerType = 'wix'; Scope = 'machine'
        LocalConfig = 'KeePassXC'
    }
    [pscustomobject]@{
        Name = 'PsTools'; Id = 'Microsoft.Sysinternals.PsTools'; Directory = 'PsTools'
        Executable = 'PsExec.exe'; InstallerType = 'portable'; Scope = ''; LocalConfig = 'None'
    }
    [pscustomobject]@{
        Name = 'MPC-BE'; Id = 'MPC-BE.MPC-BE'; Directory = 'MPC'
        Executable = 'mpc-be*.exe'; InstallerType = ''; Scope = ''; LocalConfig = 'MPC-BE'
        CustomArguments = '/LANG=de'
    }
    [pscustomobject]@{
        Name = 'Rufus'; Id = 'Rufus.Rufus'; Directory = 'Rufus'
        Executable = 'rufus*.exe'; InstallerType = 'portable'; Scope = ''; LocalConfig = 'Rufus'
    }
    [pscustomobject]@{
        Name = 'LibreOffice'; Id = 'TheDocumentFoundation.LibreOffice'; Directory = 'LibreOffice'
        Executable = 'soffice.exe'; InstallerType = 'msi'; Scope = 'machine'
        LocalConfig = 'LibreOffice'; CustomArguments = 'UI_LANGS=de'
    }
    [pscustomobject]@{
        Name = 'VLC'; Id = 'VideoLAN.VLC'; Directory = 'VLC'
        Executable = 'vlc.exe'; InstallerType = 'portable'; Scope = ''; LocalConfig = 'VLC'
    }
    [pscustomobject]@{
        Name = 'WinSCP'; Id = 'WinSCP.WinSCP'; Directory = 'WinSCP'
        Executable = 'WinSCP.exe'; InstallerType = 'wix'; Scope = 'machine'
        LocalConfig = 'WinSCP'
    }
)

return @(
    [pscustomobject]@{ Name = 'Standard'; Root = ''; Applications = $standardApplications }
    [pscustomobject]@{ Name = 'InstalledTools'; Root = $InstalledToolsRoot; Applications = $installedToolsApplications }
    [pscustomobject]@{ Name = 'PortableTools'; Root = $PortableToolsRoot; Applications = $portableToolsApplications }
)
}

function Write-Log {
    # Schreibt dieselbe Meldung auf die Konsole und in die aktuelle Logdatei.
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $ErrorActionPreference = 'Stop'
    $entry = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $script:logContext, $Message
    Write-Host $entry
    try {
        $directory = Split-Path -Path $script:logFile -Parent
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop
        }
        Add-Content -LiteralPath $script:logFile -Value $entry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Kein rekursiver Write-Log-Aufruf: Auch das Logziel selbst kann defekt sein.
        $script:loggingFailed = $true
        $diagnostic = "Logfehler bei '$($script:logFile)': $($_.Exception.Message)"
        Write-Host "[ERROR] $diagnostic"
        if ($script:logFile -ne $script:fallbackLogFile) {
            $previousLogFile = $script:logFile
            $script:logFile = $script:fallbackLogFile
            Write-Host "[WARN] Weitere Protokollierung in: $($script:logFile)"
            try {
                Add-Content -LiteralPath $script:logFile -Encoding UTF8 -ErrorAction Stop -Value @(
                    "[ERROR] $diagnostic"
                    "[WARN] Vorherige Einträge verbleiben gegebenenfalls in '$previousLogFile'."
                    $entry
                )
            }
            catch {
                Write-Host "[ERROR] Auch das Ersatzprotokoll ist nicht beschreibbar: $($_.Exception.Message). Ausgabe nur auf der Konsole."
            }
        }
    }
}

function Write-ErrorDetail {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$Record
    )

    Write-Log -Level 'ERROR' -Message (
        "Typ: $($Record.Exception.GetType().FullName); Fehler-ID: $($Record.FullyQualifiedErrorId); " +
        "Kategorie: $($Record.CategoryInfo); Ausnahme: $($Record.Exception)"
    )
    Write-Log -Level 'ERROR' -Message (
        "Position: $($Record.InvocationInfo.PositionMessage)`nStack: $($Record.ScriptStackTrace)"
    )
}

function Get-ApplicationOption {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Application,
        [Parameter(Mandatory)]
        [string]$Name,
        $Default = ''
    )

    $property = $Application.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function ConvertTo-UpdateVersion {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^\d+(?:\.\d+){1,3}$') {
        throw "Keine eindeutig numerische stabile Version: '$Value'."
    }
    $parsed = [version]::Parse($Value)
    return [version]::new($parsed.Major, $parsed.Minor, [Math]::Max(0, $parsed.Build), [Math]::Max(0, $parsed.Revision))
}

function Get-UpdateVersionConstraint {
    param([Parameter(Mandatory)][pscustomobject]$Application)
    $version = ''
    $pin = ''
    foreach ($name in @('Version', 'VersionPin')) {
        $property = $Application.PSObject.Properties[$name]
        if ($null -ne $property) {
            if ($property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value)) {
                throw "$name muss eine nicht leere Zeichenfolge sein."
            }
            if ($name -eq 'Version') { $version = $property.Value }
            else { $pin = $property.Value }
        }
    }
    if ($version) { $null = ConvertTo-UpdateVersion -Value $version }
    if ($pin) {
        if ($pin -notmatch '^\d+(?:\.\d+){0,2}\.\*$') {
            throw "VersionPin muss eine numerische Versionsreihe wie 5.0.* sein: '$pin'."
        }
        $null = ConvertTo-UpdateVersion -Value ($pin -replace '\*$', '0')
        if ($version -and $version -notlike $pin) {
            throw "Version '$version' liegt außerhalb von VersionPin '$pin'."
        }
    }
    return [pscustomobject]@{ Version = $version; VersionPin = $pin; IsLimited = [bool]($version -or $pin) }
}

function Test-ApplicationVersionEqual {
    param([string]$Left, [string]$Right)
    $leftText = $Left -replace '^[vV](?=\d)', ''
    $rightText = $Right -replace '^[vV](?=\d)', ''
    if ($leftText -match '^\d+(?:\.\d+){1,3}$' -and $rightText -match '^\d+(?:\.\d+){1,3}$') {
        return (ConvertTo-UpdateVersion $leftText) -eq (ConvertTo-UpdateVersion $rightText)
    }
    return $leftText -eq $rightText
}

function Get-AllowedUpdateVersion {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][pscustomobject]$Constraint
    )
    $response = Invoke-Winget -PassThru -Arguments @(
        'show', '--id', $Id, '--exact', '--source', 'winget', '--versions'
        '--accept-source-agreements', '--disable-interactivity'
    )
    if ($response.ExitCode -ne 0) {
        throw "Versionsabfrage für '$Id' fehlgeschlagen (Exitcode $($response.ExitCode)). Kein Update."
    }
    $inTable = $false
    $candidates = @(
        foreach ($line in $response.Output) {
            $text = ($line -replace '\x1B\[[0-?]*[ -/]*[@-~]', '').Trim()
            if ($text -match '^-{3,}$') { $inTable = $true; continue }
            if ($inTable -and $text -and $text -notmatch '^\d[\w.+()\-]*$') {
                throw "Unerwartete Daten in der Versionstabelle für '$Id': '$text'."
            }
            if (-not $inTable -or $text -notmatch '^\d+(?:\.\d+){1,3}$') { continue }
            if ($Constraint.VersionPin) {
                if ($text -notlike $Constraint.VersionPin) { continue }
            }
            elseif ($text -ne $Constraint.Version) { continue }
            [pscustomobject]@{ Text = $text; Numeric = (ConvertTo-UpdateVersion -Value $text) }
        }
    )
    if ($candidates.Count -eq 0) {
        throw "Keine eindeutig ermittelte erlaubte Version für '$Id'. Kein unbeschränktes Update."
    }
    return ($candidates | Sort-Object Numeric -Descending | Select-Object -First 1).Text
}

function Get-InstalledApplicationState {
    param([Parameter(Mandatory)][string]$Id)
    $response = Invoke-Winget -PassThru -Arguments @(
        'list', '--id', $Id, '--exact', '--source', 'winget'
        '--accept-source-agreements', '--disable-interactivity'
    )
    # APPINSTALLER_CLI_ERROR_NO_APPS_FOUND; andere Fehler sind niemals "nicht installiert".
    if (([long]$response.ExitCode -band 0xFFFFFFFFL) -eq 0x8A150014L) {
        return [pscustomobject]@{ IsInstalled = $false; Version = ''; AvailableVersion = '' }
    }
    if ($response.ExitCode -ne 0) {
        throw "Installierte Version von '$Id' nicht ermittelbar (Exitcode $($response.ExitCode))."
    }
    $inTable = $false
    $rows = @(
        foreach ($line in $response.Output) {
            $text = $line -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
            if ($text.Trim() -match '^-{3,}$') { $inTable = $true; continue }
            if ($inTable -and $text -match ('^.*?\s' + [regex]::Escape($Id) + '\s+(?<Rest>.+)$')) {
                $fields = @($Matches.Rest.Trim() -split '\s+')
                # Bei exakter Quelle blendet winget die Source-Spalte teilweise aus,
                # bei aktuellen Paketen zusätzlich Available. Der Aufruf bleibt quellengebunden.
                if ($fields.Count -gt 1 -and $fields[-1] -eq 'winget') {
                    $fields = @($fields[0..($fields.Count - 2)])
                }
                if ($fields.Count -notin @(1, 2) -or
                    $fields[0] -notmatch '^[vV]?\d[\w.+()\-]*$' -or
                    ($fields.Count -eq 2 -and $fields[1] -notmatch '^[vV]?\d[\w.+()\-]*$')) {
                    throw "Unbekannte/mehrdeutige Version oder unerwartete winget-Tabellenspalten für '$Id'."
                }
                [pscustomobject]@{
                    IsInstalled = $true; Version = $fields[0]
                    AvailableVersion = if ($fields.Count -eq 2) { $fields[1] } else { '' }
                }
            }
        }
    )
    if ($rows.Count -ne 1) {
        throw "Installierte Version von '$Id' ist unbekannt, mehrdeutig oder die winget-Ausgabe hat ein anderes Format."
    }
    return $rows[0]
}

function Get-InstalledUpdateVersion {
    param([Parameter(Mandatory)][string]$Id)
    $state = Get-InstalledApplicationState -Id $Id
    if (-not $state.IsInstalled) { throw "'$Id' ist nicht installiert." }
    return $state.Version
}

function Test-ApplicationManifest {
    param(
        [Parameter(Mandatory)][pscustomobject]$Application,
        [string]$Version,
        [switch]$PassThru
    )
    $arguments = @('show', '--id', $Application.Id, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--disable-interactivity')
    if ($Version) { $arguments += @('--version', $Version) }
    foreach ($option in @('InstallerType', 'Scope', 'Architecture', 'Locale')) {
        $value = Get-ApplicationOption -Application $Application -Name $option
        if ($value) {
            $switchName = if ($option -eq 'InstallerType') { '--installer-type' } else { "--$($option.ToLowerInvariant())" }
            $arguments += @($switchName, $value)
        }
    }
    $response = Invoke-Winget -PassThru -Arguments $arguments
    if ($response.ExitCode -ne 0) {
        throw "Manifestprüfung für '$($Application.Id)' fehlgeschlagen (Exitcode $($response.ExitCode))."
    }
    $text = ($response.Output -join "`n") -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
    $versions = [regex]::Matches($text, '(?m)^Version:\s*(\S+)\s*$')
    $types = [regex]::Matches($text, '(?m)^\s+(?:Installer Type|Installertyp):\s*([a-z]+)')
    if ($text -notmatch ('\[' + [regex]::Escape($Application.Id) + '\]') -or
        $versions.Count -ne 1 -or $types.Count -ne 1) {
        throw 'Manifest/Installer konnte nicht eindeutig gelesen werden (unterstützte winget-Ausgabe: Deutsch/Englisch).'
    }
    $selectedVersion = $versions[0].Groups[1].Value
    if ($selectedVersion -notmatch '^[vV]?\d[\w.+()\-]*$' -or ($Version -and $selectedVersion -ne $Version)) {
        throw "Unerwartete Manifestversion: '$selectedVersion', angefordert: '$Version'."
    }
    $installerType = Get-ApplicationOption -Application $Application -Name 'InstallerType'
    if ($installerType -and $types[0].Groups[1].Value -ne $installerType) {
        throw "Abweichender Installer-Typ: '$($types[0].Groups[1].Value)', erwartet '$installerType'."
    }
    if ($PassThru) {
        return [pscustomobject]@{ Version = $selectedVersion; InstallerType = $types[0].Groups[1].Value }
    }
    return $selectedVersion
}

function Test-ApplicationTarget {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0 -or $Path -match '[*?]' -or
        $Path -match '(?<!^[A-Za-z]):' -or $Path -match '(?:^|\\)\.\.?(?:\\|$)') {
        throw "Ungültiger Zielpfad: '$Path'."
    }
    foreach ($part in ($Path -split '\\' | Select-Object -Skip 1)) {
        if ($part -match '^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $part -match '[. ]$') {
            throw "Ungültiger Windows-Ordnername im Zielpfad: '$Path'."
        }
    }
    $root = [IO.Path]::GetPathRoot($Path)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Ziellaufwerk oder Netzwerkfreigabe nicht verfügbar: '$root'."
    }
    $parent = $Path
    while ($parent -and $parent -ne $root) {
        if (Test-Path -LiteralPath $parent) {
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                throw "Ziel oder übergeordneter Pfad ist kein Verzeichnis: '$parent'."
            }
            if ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Umgeleiteter Zielpfad wird nicht automatisch verwendet: '$parent'."
            }
        }
        $parent = Split-Path -Path $parent -Parent
    }
}

function Get-LibreOfficeProfile {
    param([Parameter(Mandatory)][string]$Path)
    $content = [IO.File]::ReadAllText($Path)
    $sections = [regex]::Matches($content, '(?ms)^\[Bootstrap\]\r?\n(?:(?!^\[).)*')
    if ($sections.Count -ne 1) { throw "Kein eindeutiger [Bootstrap]-Abschnitt in '$Path'." }
    $settings = [regex]::Matches($sections[0].Value, '(?m)^UserInstallation=([^\r\n]*)')
    if ($settings.Count -ne 1) { throw "Kein eindeutiger UserInstallation-Eintrag in '$Path'." }
    $profile = $settings[0].Groups[1].Value
    if ($profile -notin @('$ORIGIN/../profile', '$SYSUSERCONFIG/LibreOffice/4')) {
        throw "Ein benutzerdefiniertes LibreOffice-Profil wird nicht überschrieben: '$profile'."
    }
    return $profile
}

function Get-LocalConfigurationState {
    param(
        [Parameter(Mandatory)][pscustomobject]$Application,
        [string]$Location
    )
    $kind = Get-ApplicationOption -Application $Application -Name 'LocalConfig' -Default 'None'
    if ($kind -eq 'None') { return }
    if ($kind -eq 'KeePassGerman') {
        $state = Get-KeePassConfigurationState -Location $Location -ReadOnly
        if ($null -ne $state.ConfigBytes) {
            [pscustomobject]@{ Path = $state.ConfigPath; Bytes = $state.ConfigBytes }
        }
        return
    }
    $files = @()
    $directories = @()
    $executables = @()
    $applicationDirectory = $Location
    if (Test-Path -LiteralPath $Location -PathType Container) {
        $executables = @(Get-ChildItem -LiteralPath $Location -Filter $Application.Executable -File -Recurse)
        if ($executables.Count -gt 1) { throw "Mehrdeutige Programmdateien unter '$Location'." }
        if ($executables.Count -eq 1) { $applicationDirectory = $executables[0].DirectoryName }
    }
    switch ($kind) {
        'LibreOffice' {
            if (@(Get-Process | Where-Object ProcessName -in @('soffice', 'soffice.bin')).Count) {
                throw 'LibreOffice läuft noch. Vor Installation/Update alle Instanzen schließen.'
            }
            $bootstrapPath = Join-Path $applicationDirectory 'bootstrap.ini'
            $profile = '$SYSUSERCONFIG/LibreOffice/4'
            if (Test-Path -LiteralPath $bootstrapPath) {
                $profile = Get-LibreOfficeProfile -Path $bootstrapPath
                $files += $bootstrapPath
            }
            $userProfile = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LibreOffice\4'
            if ($profile -ne '$ORIGIN/../profile' -and (Test-Path -LiteralPath $userProfile)) {
                throw "Vorhandene LibreOffice-Benutzereinstellungen werden nicht automatisch umgestellt: '$userProfile'."
            }
            $directories += Join-Path $Location 'profile'
        }
        'KeePassXC' {
            $files += Join-Path $applicationDirectory '.portable'
            $files += Join-Path $applicationDirectory 'config\keepassxc.ini'
            $files += Join-Path $applicationDirectory 'config\keepassxc_local.ini'
            $directories += Join-Path $applicationDirectory 'config'
        }
        'MPC-BE' {
            if ($executables.Count -eq 1) { $files += [IO.Path]::ChangeExtension($executables[0].FullName, '.ini') }
        }
        'Rufus' { $files += Join-Path $applicationDirectory 'rufus.ini' }
        'VLC' {
            $files += Join-Path $applicationDirectory 'vlcrc'
            $files += Join-Path $applicationDirectory 'Start-VLC.cmd'
        }
        'WinSCP' {
            $files += Join-Path $applicationDirectory 'WinSCP.ini'
            $directories += Join-Path $applicationDirectory 'temp'
        }
        default { throw "Unbekannte lokale Konfiguration: '$kind'." }
    }
    foreach ($directory in $directories) {
        if ((Test-Path -LiteralPath $directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Konfigurationsverzeichnis ist durch eine Datei belegt: '$directory'."
        }
    }
    foreach ($file in $files) {
        if (Test-Path -LiteralPath $file) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Konfigurationsdatei ist durch ein Verzeichnis belegt: '$file'."
            }
            [pscustomobject]@{
                Path = $file
                Bytes = [IO.File]::ReadAllBytes($file)
                RestoreOnSuccess = ($kind -ne 'LibreOffice')
            }
        }
    }
}

function Write-ApplicationPreview {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plans)
    $script:logContext = 'Preview'
    Write-Log -Message 'Vollständige Vorschau – vor jeglicher Paketänderung:'
    $table = $Plans | Select-Object Id, InstalledVersion, TargetVersion, Action, Status, Location |
        Format-Table -AutoSize | Out-String -Width 260
    Write-Log -Message $table
    foreach ($plan in $Plans) {
        Write-Log -Message (($plan | Select-Object Id, Source, InstallerType, Scope, Architecture,
            Locale, CustomArguments, LocalConfig, Message | Format-List | Out-String -Width 260).TrimEnd())
    }
}

function Start-ApplicationRun {
    param(
        [ValidateSet('Install', 'Update')][string]$Mode,
        [string]$InstalledToolsRoot,
        [string]$PortableToolsRoot,
        [string]$LogDirectory,
        [string[]]$ApplicationId,
        [switch]$CheckOnly
    )
    $script:wingetNoUpdateExitCode = -1978335189
    $script:versionPolicyFile = Join-Path $PSScriptRoot 'Application-VersionPolicies.psd1'
    $runName = '{0}-Applications-{1}-{2}' -f $Mode, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID
    $script:logFile = [IO.Path]::Combine($LogDirectory, "$runName.log")
    $script:fallbackLogFile = Join-Path $PSScriptRoot "$runName-fallback.log"
    $script:loggingFailed = $false
    $script:logContext = 'Start'
    $scriptExitCode = 1
    try {
        $applicationGroups = @(Get-ApplicationGroups -InstalledToolsRoot $InstalledToolsRoot -PortableToolsRoot $PortableToolsRoot)
        $scriptExitCode = Invoke-Installation -Mode $Mode -CheckOnly:$CheckOnly
    }
    catch {
        Write-Log -Level ERROR -Message "Unerwarteter skriptweiter Fehler: $($_.Exception.Message)"
        Write-ErrorDetail -Record $_
    }
    finally {
        $script:logContext = 'End'
        Write-LogLocation
    }
    if ($scriptExitCode -eq 0 -and $script:loggingFailed) { $scriptExitCode = 2 }
    return $scriptExitCode
}

function Initialize-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Log -Message ("Erstelle Verzeichnis: $Path")
        $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
    }
    # Einige Provider-/Pfadkonflikte liefern trotz -Force kein Verzeichnis.
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Das Verzeichnis '$Path' konnte nicht erstellt werden. Überprüfen Sie übergeordnete Pfade und Berechtigungen."
    }
}

function Write-LogLocation {
    # Zeigt nach längeren Ausgaben erneut, wo das vollständige Protokoll gespeichert wurde.
    Write-Log -Message ("Vollständige Logdatei: $logFile")
}

function Test-Administrator {
    # Installationen in System- und benutzerdefinierte Verzeichnisse benötigen erhöhte Rechte.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Winget {
    # Führt winget zentral aus, damit Befehl, Ausgabe und Exitcode lückenlos protokolliert werden.
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$PassThru
    )

    Write-Log -Message ('Befehl: winget {0}' -f (($Arguments | ForEach-Object {
        '"{0}"' -f ($_ -replace '"', '\"')
    }) -join ' '))
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 behandelt natives stderr sonst als terminierenden Fehler.
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $global:LASTEXITCODE = $null
        $outputLines = @(& winget @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Log -Level 'WARN' -Message ([string]$_)
            }
            else {
                Write-Log -Message ([string]$_)
            }
            [string]$_
        })
        $exitCode = $global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    if ($null -eq $exitCode) {
        throw 'winget lieferte keinen Exitcode; der Prozess konnte möglicherweise nicht gestartet werden.'
    }
    $hexCode = '0x{0:X8}' -f ([long]$exitCode -band 0xFFFFFFFFL)
    Write-Log -Message ("winget wurde mit Exitcode $exitCode ($hexCode) beendet.")
    if ($PassThru) {
        return [pscustomobject]@{ ExitCode = $exitCode; Output = $outputLines }
    }
    return $exitCode
}

function Resolve-InstalledExecutable {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Application,

        [Parameter(Mandatory)]
        [string]$Location
    )

    if (-not (Test-Path -LiteralPath $Location -PathType Container)) {
        throw "Das konfigurierte Installationsziel '$Location' fehlt. Bestehende Installationen werden nicht automatisch verschoben."
    }
    $matches = @(
        Get-ChildItem -LiteralPath $Location -Filter $Application.Executable -File -Recurse |
            Select-Object -ExpandProperty FullName
    )

    if ($matches.Count -eq 0) {
        throw (
            "Die erwartete Programmdatei '$($Application.Executable)' wurde unter " +
            "'$Location' nicht gefunden. Das Paket wurde möglicherweise bereits an " +
            'einem anderen Ort installiert oder hat --location nicht berücksichtigt.'
        )
    }

    if ($matches.Count -gt 1) {
        throw (
            "Die Programmdatei '$($Application.Executable)' wurde unter '$Location' " +
            'mehrfach gefunden; die lokale Konfiguration kann nicht eindeutig eingerichtet werden.'
        )
    }
    if ((Get-ApplicationOption -Application $Application -Name 'LocalConfig') -eq 'KeePassGerman') {
        # Direkte Kinder prüfen statt kurze/lange Windows-Pfadnamen als Text zu vergleichen.
        $directMatches = @(Get-ChildItem -LiteralPath $Location -Filter $Application.Executable -File)
        if ($directMatches.Count -ne 1) {
            throw "KeePass.exe muss beim geprüften Inno-Installer direkt unter '$Location' liegen."
        }
    }

    return $matches[0]
}

function New-LocalConfigurationFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Content = @()
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Log -Message ("Lokale Konfigurationsdatei bereits vorhanden: $Path")
        return
    }

    # Ohne -Force bleiben vorhandene Dateien auch bei konkurrierenden Starts erhalten.
    $null = New-Item -ItemType File -Path $Path -Value ($Content -join "`r`n")
    Write-Log -Message ("Lokale Konfigurationsdatei erstellt: $Path")
}

function Read-KeePassConfiguration {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 4MB
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.PreserveWhitespace = $true
        $document.Load($reader)
        if ($document.DocumentElement.Name -ne 'Configuration') {
            throw "Ungültige KeePass-Konfiguration: $Path"
        }
        return ,$document
    }
    finally {
        $reader.Dispose()
    }
}

function Get-KeePassConfigurationState {
    param(
        [Parameter(Mandatory)]
        [string]$Location,
        [switch]$ReadOnly
    )

    if (@(Get-Process | Where-Object ProcessName -eq 'KeePass').Count -gt 0) {
        throw 'KeePass läuft noch. Vor Installation und Sprachkonfiguration alle KeePass-Instanzen schließen.'
    }
    $configPath = Join-Path -Path $Location -ChildPath 'KeePass.config.xml'
    $enforcedPath = Join-Path -Path $Location -ChildPath 'KeePass.config.enforced.xml'
    $userConfig = Join-Path -Path ([Environment]::GetFolderPath('ApplicationData')) -ChildPath 'KeePass\KeePass.config.xml'
    if (Test-Path -LiteralPath $enforcedPath) {
        throw "Erzwungene KeePass-Konfiguration gefunden; keine automatische Änderung: $enforcedPath"
    }
    $state = [pscustomobject]@{ ConfigPath = $configPath; ConfigBytes = $null; BackupPath = '' }
    $languageDirectory = Join-Path $Location 'Languages'
    $languagePath = Join-Path $languageDirectory 'German.lngx'
    if (((Test-Path -LiteralPath $languageDirectory) -and
            -not (Test-Path -LiteralPath $languageDirectory -PathType Container)) -or
        ((Test-Path -LiteralPath $languagePath) -and
            -not (Test-Path -LiteralPath $languagePath -PathType Leaf))) {
        throw 'Ein Datei-/Ordnerkonflikt verhindert das lokale KeePass-Sprachpaket.'
    }
    if (Test-Path -LiteralPath $configPath) {
        $document = Read-KeePassConfiguration -Path $configPath
        $preferences = $document.SelectNodes('/Configuration/Meta/PreferUserConfiguration')
        $languages = $document.SelectNodes('/Configuration/Application/LanguageFile')
        if ($preferences.Count -ne 1 -or $preferences[0].InnerText -ne 'false' -or
            $languages.Count -ne 1 -or $languages[0].InnerText -ne 'German.lngx') {
            throw "Abweichende KeePass-Konfiguration gefunden. Vor einer Umstellung manuell sichern und prüfen: $configPath"
        }
        $state.ConfigBytes = [IO.File]::ReadAllBytes($configPath)
        if (-not $ReadOnly) {
            $state.BackupPath = "$configPath.$([guid]::NewGuid().ToString('N')).bak"
            Copy-Item -LiteralPath $configPath -Destination $state.BackupPath
            Write-Log -Message "KeePass-Konfiguration vor dem Installer gesichert: $($state.BackupPath)"
        }
    }
    elseif (Test-Path -LiteralPath $userConfig) {
        throw "Vorhandene KeePass-Benutzereinstellungen werden nicht automatisch migriert: $userConfig"
    }
    return $state
}

function Install-KeePassGermanLanguage {
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath
    )

    $fileVersion = (Get-Item -LiteralPath $ExecutablePath).VersionInfo
    if ($fileVersion.FileMajorPart -ne 2 -or $fileVersion.FileMinorPart -ne 61 -or
        $fileVersion.FileBuildPart -ne 1 -or $fileVersion.FilePrivatePart -ne 0) {
        throw "Das geprüfte Sprachpaket ist für KeePass 2.61.1.0 vorgesehen; gefunden: $($fileVersion.FileVersion)"
    }

    $applicationDirectory = Split-Path -Path $ExecutablePath -Parent
    $languageDirectory = Join-Path -Path $applicationDirectory -ChildPath 'Languages'
    Initialize-Directory -Path $languageDirectory
    $languagePath = Join-Path -Path $languageDirectory -ChildPath 'German.lngx'
    $downloadPath = Join-Path -Path (Split-Path $script:logFile -Parent) -ChildPath (
        'KeePass-German-{0}.zip' -f [guid]::NewGuid().ToString('N')
    )
    $uri = 'https://downloads.sourceforge.net/project/keepass/Translations%202.x/2.61/KeePass-2.61-German.zip'
    # SHA-256 des am 10.09.2026 geprüften offiziellen Downloads, kein separat publizierter Hersteller-Hash.
    $expectedHash = 'A0EC490D2A7262A8D8ADEF53F87B5EDE70CB0BFEC522C998F7927444D72CFB40'
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Log -Message "Lade deutsches KeePass-Sprachpaket: $uri"
        # SourceForge liefert an Browser-User-Agents mitunter eine HTML-Downloadseite.
        Invoke-WebRequest -Uri $uri -OutFile $downloadPath -UseBasicParsing -TimeoutSec 60 `
            -UserAgent 'Wget (PowerShell KeePass language downloader)' -ErrorAction Stop
        if ((Get-Item -LiteralPath $downloadPath).Length -ne 45754 -or
            (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'Größe oder SHA-256 des KeePass-Sprachpakets stimmt nicht mit dem geprüften Download überein.'
        }
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($downloadPath)
        try {
            if ($archive.Entries.Count -ne 1 -or $archive.Entries[0].FullName -cne 'German.lngx' -or
                $archive.Entries[0].Length -ne 45598) {
                throw 'Das KeePass-Spracharchiv enthält nicht ausschließlich die erwartete German.lngx.'
            }
            $stream = $archive.Entries[0].Open()
            $memory = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($memory)
                $languageBytes = $memory.ToArray()
            }
            finally {
                $memory.Dispose()
                $stream.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
        # LNGX ist gzip-komprimiertes XML und muss unverändert gespeichert werden.
        if (Test-Path -LiteralPath $languagePath) {
            $existingBytes = [IO.File]::ReadAllBytes($languagePath)
            if ([Convert]::ToBase64String($existingBytes) -cne [Convert]::ToBase64String($languageBytes)) {
                throw "Vorhandenes abweichendes Sprachpaket wird nicht überschrieben: $languagePath"
            }
        }
        else {
            $output = [IO.File]::Open($languagePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            try {
                $output.Write($languageBytes, 0, $languageBytes.Length)
            }
            finally {
                $output.Dispose()
            }
        }
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        if (Test-Path -LiteralPath $downloadPath) {
            Remove-Item -LiteralPath $downloadPath -Force
        }
    }

    $configPath = Join-Path -Path $applicationDirectory -ChildPath 'KeePass.config.xml'
    if (Test-Path -LiteralPath $configPath) {
        $document = Read-KeePassConfiguration -Path $configPath
    }
    else {
        $document = [Xml.XmlDocument]::new()
        $document.LoadXml('<Configuration />')
    }
    foreach ($setting in @(
        @{ Section = 'Meta'; Name = 'PreferUserConfiguration'; Value = 'false' }
        @{ Section = 'Application'; Name = 'LanguageFile'; Value = 'German.lngx' }
    )) {
        $sections = $document.SelectNodes("/Configuration/$($setting.Section)")
        if ($sections.Count -gt 1) {
            throw "Mehrdeutige KeePass-Konfiguration: $($setting.Section)"
        }
        if ($sections.Count -eq 0) {
            $section = $document.CreateElement($setting.Section)
            $null = $document.DocumentElement.AppendChild($section)
        }
        else {
            $section = $sections[0]
        }
        $nodes = $section.SelectNodes($setting.Name)
        if ($nodes.Count -gt 1) {
            throw "Mehrdeutige KeePass-Einstellung: $($setting.Name)"
        }
        if ($nodes.Count -eq 0) {
            $node = $document.CreateElement($setting.Name)
            $null = $section.AppendChild($node)
        }
        else {
            $node = $nodes[0]
        }
        $node.InnerText = $setting.Value
    }
    $document.Save($configPath)
    Write-Log -Message 'KeePass verwendet German.lngx und KeePass.config.xml im eigenen Programmverzeichnis.'
}

function Initialize-LocalConfiguration {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Application,

        [Parameter(Mandatory)]
        [string]$ExecutablePath
    )

    $applicationDirectory = Split-Path -Path $ExecutablePath -Parent

    switch ($Application.LocalConfig) {
        'KeePassGerman' {
            Install-KeePassGermanLanguage -ExecutablePath $ExecutablePath
        }
        'LibreOffice' {
            $bootstrapPath = Join-Path -Path $applicationDirectory -ChildPath 'bootstrap.ini'
            $null = Get-LibreOfficeProfile -Path $bootstrapPath
            $content = [IO.File]::ReadAllText($bootstrapPath)
            $section = [regex]::Match($content, '(?ms)^\[Bootstrap\]\r?\n(?:(?!^\[).)*')
            $settings = [regex]::Matches($section.Value, '(?m)^UserInstallation=([^\r\n]*)')
            if ($settings.Count -ne 1) {
                throw "In '$bootstrapPath' wurde kein eindeutiger UserInstallation-Eintrag unter [Bootstrap] gefunden."
            }
            $localProfile = '$ORIGIN/../profile'
            $existingProfile = $settings[0].Groups[1].Value
            if ($existingProfile -ne $localProfile -and $existingProfile -ne '$SYSUSERCONFIG/LibreOffice/4') {
                throw "Ein benutzerdefiniertes LibreOffice-Profil wird nicht überschrieben: '$existingProfile'."
            }
            Initialize-Directory -Path (
                Join-Path -Path (Split-Path -Path $applicationDirectory -Parent) -ChildPath 'profile'
            )
            if ($existingProfile -ne $localProfile) {
                $backupPath = "$bootstrapPath.$([guid]::NewGuid().ToString('N')).bak"
                Copy-Item -LiteralPath $bootstrapPath -Destination $backupPath
                Write-Log -Message "Sicherung der LibreOffice-bootstrap.ini: $backupPath"
                $setting = $settings[0]
                $offset = $section.Index + $setting.Index
                $updatedContent = $content.Remove($offset, $setting.Length).Insert(
                    $offset, "UserInstallation=$localProfile"
                )
                [IO.File]::WriteAllText($bootstrapPath, $updatedContent, [Text.UTF8Encoding]::new($false))
                Write-Log -Message 'LibreOffice-Profil lokal eingerichtet.'
                Write-Log -Level 'WARN' -Message (
                    'Bestehende LibreOffice-Benutzerdaten wurden nicht importiert. ' +
                    'Das Update-Skript sichert und prüft diese lokale Einstellung ebenfalls.'
                )
            }
            else {
                Write-Log -Message 'LibreOffice verwendet bereits das lokale Profil.'
            }
        }
        'None' {
            Write-Log -Message (
                "$($Application.Name) benötigt keine zusätzliche lokale Konfigurationsdatei."
            )
        }
        'Rufus' {
            New-LocalConfigurationFile -Path (
                Join-Path -Path $applicationDirectory -ChildPath 'rufus.ini'
            )
        }
        'KeePassXC' {
            New-LocalConfigurationFile -Path (
                Join-Path -Path $applicationDirectory -ChildPath '.portable'
            )

            $configDirectory = Join-Path -Path $applicationDirectory -ChildPath 'config'
            Initialize-Directory -Path $configDirectory
        }
        'VLC' {
            New-LocalConfigurationFile -Path (
                Join-Path -Path $applicationDirectory -ChildPath 'vlcrc'
            )
            New-LocalConfigurationFile -Path (
                Join-Path -Path $applicationDirectory -ChildPath 'Start-VLC.cmd'
            ) -Content @(
                '@echo off'
                '"%~dp0vlc.exe" --config="%~dp0vlcrc" %*'
            )
            Write-Log -Level 'WARN' -Message (
                'VLC muss über Start-VLC.cmd gestartet werden, damit vlcrc lokal verwendet wird. ' +
                'Zusätzliche Oberflächeneinstellungen können weiterhin im Benutzerprofil liegen.'
            )
        }
        'MPC-BE' {
            New-LocalConfigurationFile -Path (
                [IO.Path]::ChangeExtension($ExecutablePath, '.ini')
            )
        }
        'WinSCP' {
            New-LocalConfigurationFile -Path (
                Join-Path -Path $applicationDirectory -ChildPath 'WinSCP.ini'
            ) -Content @(
                '[Configuration\Interface]'
                'RandomSeedFile=.\winscp.rnd'
                'DDTemporaryDirectory=.\temp\'
            )

            $tempDirectory = Join-Path -Path $applicationDirectory -ChildPath 'temp'
            Initialize-Directory -Path $tempDirectory
        }
        default {
            throw "Unbekannte lokale Konfigurationsart: $($Application.LocalConfig)"
        }
    }
}

function Get-ApplicationPlan {
    # Jeder Eintrag liefert ein Ergebnis, auch bei ungültiger Konfiguration.
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Application,

        [string]$Root,

        [string]$Group = 'Standard',
        [ValidateSet('Install', 'Update')][string]$Mode = 'Install'
    )

    $result = [pscustomobject]@{
        Group = $Group
        Id = [string](Get-ApplicationOption -Application $Application -Name 'Id')
        Name = [string](Get-ApplicationOption -Application $Application -Name 'Name')
        Location = ''
        Status = 'Failed'
        Phase = 'Configuration'
        ExitCode = $null
        DurationSeconds = 0
        Message = ''
        InstalledVersion = ''
        TargetVersion = ''
        Source = 'winget'
        InstallerType = ''
        Scope = ''
        Architecture = ''
        Locale = ''
        CustomArguments = ''
        LocalConfig = ''
        Action = 'Error'
        Application = $null
        Arguments = @()
    }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $script:logContext = "$Group/$($result.Id)"
    try {
        $Application = Resolve-ApplicationVersionPolicy -Application $Application -PolicyFile $script:versionPolicyFile
        $result.Application = $Application
        $allowedProperties = @(
            'Name', 'Id', 'Directory', 'Executable', 'InstallerType', 'Scope',
            'LocalConfig', 'Enabled', 'Version', 'Architecture', 'VersionPin',
            'Locale', 'CustomArguments', 'VersionPolicy'
        )
        foreach ($property in $Application.PSObject.Properties) {
            if ($property.Name -notin $allowedProperties) {
                throw "Unbekannte Anwendungseigenschaft '$($property.Name)'."
            }
        }
        if ([string]::IsNullOrWhiteSpace($result.Id) -or [string]::IsNullOrWhiteSpace($result.Name)) {
            throw 'Name und Id müssen angegeben werden.'
        }
        $enabled = Get-ApplicationOption -Application $Application -Name 'Enabled' -Default $true
        if ($enabled -isnot [bool]) {
            throw 'Enabled muss $true oder $false sein (keine Zeichenfolge).'
        }
        if (-not $enabled) {
            $result.Status = 'Skipped'
            $result.Action = 'Skipped'
            $result.Message = 'Durch Enabled = $false deaktiviert.'
            Write-Log -Message $result.Message
            return $result
        }

        $localConfig = Get-ApplicationOption -Application $Application -Name 'LocalConfig' -Default 'None'
        if ($localConfig -notin @('None', 'Rufus', 'KeePassGerman', 'KeePassXC', 'LibreOffice', 'VLC', 'MPC-BE', 'WinSCP')) {
            throw "Unbekannte lokale Konfigurationsart: $localConfig"
        }
        $versionPin = Get-ApplicationOption -Application $Application -Name 'VersionPin'
        $constraint = Get-UpdateVersionConstraint -Application $Application
        if ($versionPin) {
            $version = Get-ApplicationOption -Application $Application -Name 'Version'
            if ($versionPin -isnot [string] -or $versionPin -notmatch '^\d+(?:\.\d+)*\.\*$' -or
                ($Mode -eq 'Install' -and -not $version) -or ($version -and $version -notlike $versionPin)) {
                throw 'VersionPin muss eine Versionsreihe wie 5.0.* sein und zu einer expliziten Version passen.'
            }
        }
        $directory = Get-ApplicationOption -Application $Application -Name 'Directory'
        if (-not $Root -and ($directory -or $localConfig -ne 'None')) {
            throw 'Directory und LocalConfig benötigen eine Gruppe mit Zielverzeichnis.'
        }
        $arguments = @(
            'install'
            '--id', $Application.Id
            # --exact verhindert, dass winget ein ähnlich benanntes Paket auswählt.
            '--exact'
            '--source', 'winget'
            '--silent'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
        )

        foreach ($option in @('InstallerType', 'Scope', 'Architecture', 'Version', 'Locale', 'CustomArguments')) {
            $value = Get-ApplicationOption -Application $Application -Name $option
            if ($value) {
                if ($value -isnot [string]) {
                    throw "$option muss eine Zeichenfolge sein."
                }
                if ($option -eq 'Scope' -and $value -notin @('user', 'machine')) {
                    throw "Ungültiger Scope: $value"
                }
                if ($option -eq 'Architecture' -and $value -notin @('x86', 'x64', 'arm', 'arm64', 'neutral')) {
                    throw "Ungültige Architecture: $value"
                }
                if ($option -eq 'InstallerType' -and $value -notin @(
                    'inno', 'wix', 'msi', 'nullsoft', 'zip', 'portable', 'exe', 'burn', 'msix', 'appx'
                )) {
                    throw "Ungültiger InstallerType: $value"
                }
                if ($option -eq 'Locale' -and $value -notmatch '^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$') {
                    throw "Ungültige Locale: $value"
                }
                $switchName = switch ($option) {
                    'InstallerType' { '--installer-type' }
                    'CustomArguments' { '--custom' }
                    default { "--$($option.ToLowerInvariant())" }
                }
                $arguments += @($switchName, $value)
                if ($option -ne 'Version') { $result.$option = $value }
            }
        }

        if ($Root) {
            # Ein einzelner Ordnername verhindert versehentliche Ziele außerhalb der Gruppe.
            if ([string]::IsNullOrWhiteSpace($directory) -or $directory -in @('.', '..') -or
                $directory.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                $directory.EndsWith('.') -or $directory.EndsWith(' ')) {
                throw "Directory muss ein einzelner gültiger Ordnername sein: '$directory'."
            }
            $executable = Get-ApplicationOption -Application $Application -Name 'Executable'
            if ([string]::IsNullOrWhiteSpace($executable) -or $executable -match '[\\/:]' -or
                $executable -notlike '*.exe') {
                throw 'Executable muss ein EXE-Dateiname oder Dateimuster ohne Pfad sein.'
            }
            if (-not [IO.Path]::IsPathRooted($Root) -or $Root -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') {
                throw "Das Gruppenziel muss ein absoluter Windows-Pfad sein: '$Root'."
            }
            $result.Phase = 'TargetDirectory'
            $result.Location = [IO.Path]::Combine($Root, $directory)
            if ($Mode -eq 'Install') { Test-ApplicationTarget -Path $result.Location }
            $arguments += @('--location', $result.Location)
        }

        $result.LocalConfig = $localConfig
        $result.Phase = 'Discovery'
        $installed = Get-InstalledApplicationState -Id $Application.Id
        $result.InstalledVersion = $installed.Version
        if ($Mode -eq 'Update' -and -not $installed.IsInstalled) {
            $result.Action = 'NotInstalled'
            $result.Status = 'Planned'
            $result.Phase = 'Preflight'
            $result.Message = 'Nicht installiert; kein Update und keine Ziel-/Konfigurationsänderung vorgesehen.'
            return $result
        }
        if ($result.Location -and $Mode -eq 'Update') {
            $result.Phase = 'TargetDirectory'
            Test-ApplicationTarget -Path $result.Location
        }
        if ($result.Location -and $installed.IsInstalled) {
            $result.Phase = 'VerifyExecutable'
            $null = Resolve-InstalledExecutable -Application $Application -Location $result.Location
        }
        $result.Phase = 'ConfigurationPreflight'
        $null = Get-LocalConfigurationState -Application $Application -Location $result.Location
        if ($localConfig -eq 'KeePassGerman' -and
            ($result.InstallerType -ne 'inno' -or $constraint.Version -ne '2.61.1' -or $constraint.VersionPin)) {
            throw 'KeePassGerman benötigt den geprüften Inno-Installer mit exakter Version 2.61.1.'
        }
        $result.Phase = 'Manifest'
        $targetVersion = Get-ApplicationOption -Application $Application -Name 'Version'
        if ($Mode -eq 'Update') {
            $targetVersion = if ($constraint.IsLimited) {
                Get-AllowedUpdateVersion -Id $Application.Id -Constraint $constraint
            }
            else { $installed.AvailableVersion }
        }
        $manifest = Test-ApplicationManifest -Application $Application -Version $targetVersion -PassThru
        $result.TargetVersion = $manifest.Version
        $result.InstallerType = $manifest.InstallerType
        $result.Action = if ($Mode -eq 'Install') { 'Install' } else { 'Update' }
        if ($constraint.IsLimited -and $installed.IsInstalled) {
            $installedNumeric = ConvertTo-UpdateVersion -Value $installed.Version
            $targetNumeric = ConvertTo-UpdateVersion -Value $result.TargetVersion
            if ($installedNumeric -ge $targetNumeric) {
                if (($constraint.VersionPin -and $installed.Version -notlike $constraint.VersionPin) -or
                    (-not $constraint.VersionPin -and $installedNumeric -ne $targetNumeric)) {
                    throw "Installierte Version '$($installed.Version)' liegt außerhalb der Vorgabe. Kein automatisches Downgrade."
                }
                if ($Mode -eq 'Update') { $result.Action = 'NoUpdate' }
            }
        }
        elseif ($Mode -eq 'Update' -and -not $installed.AvailableVersion) {
            $result.Action = 'NoUpdate'
        }
        # Das geprüfte Ziel wird auch für unbeschränkte Pakete explizit angefordert.
        $arguments = @($arguments | Select-Object -Skip 1)
        $versionIndex = [array]::IndexOf($arguments, '--version')
        if ($versionIndex -ge 0) {
            $arguments[$versionIndex + 1] = $result.TargetVersion
        }
        else { $arguments += @('--version', $result.TargetVersion) }
        $verb = if ($Mode -eq 'Update') { 'upgrade' } else { 'install' }
        $result.Arguments = @($verb) + $arguments
        $result.Status = 'Planned'
        $result.Phase = 'Preflight'
        $result.Message = 'Lesende Prüfung erfolgreich; keine Installation/Installer-Ausführung getestet.'
    }
    catch {
        Write-Log -Level 'ERROR' -Message (
            "Verarbeitung von '$($result.Name)' in Phase '$($result.Phase)' fehlgeschlagen: $($_.Exception.Message)"
        )
        $result.Message = $_.Exception.Message
        $result.Status = 'Failed'
        $result.Action = 'Error'
        Write-ErrorDetail -Record $_
    }
    finally {
        $stopwatch.Stop()
        $result.DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    }
    return $result
}

function Invoke-ApplicationChange {
    param([Parameter(Mandatory)][pscustomobject]$Plan)

    $result = $Plan.PSObject.Copy()
    if ($result.Status -eq 'Failed' -or $result.Action -eq 'Skipped') { return $result }
    if ($result.Action -in @('NoUpdate', 'NotInstalled')) {
        $result.Status = $result.Action
        $result.Phase = 'Completed'
        return $result
    }
    $Application = $result.Application
    $script:logContext = "$($result.Group)/$($result.Id)"
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $savedFiles = @()
    try {
        # Nach der vollständigen Vorschau erneut prüfen: Programme können inzwischen gestartet sein.
        $result.Phase = 'Revalidate'
        $current = Get-InstalledApplicationState -Id $result.Id
        if ($current.Version -ne $result.InstalledVersion -or
            ($result.Action -eq 'Update' -and -not $current.IsInstalled)) {
            throw 'Installationszustand seit der Vorschau geändert; bitte neu prüfen.'
        }
        if ($result.Location -and $current.IsInstalled) {
            $null = Resolve-InstalledExecutable -Application $Application -Location $result.Location
        }
        $result.Phase = 'ConfigurationPreflight'
        $savedFiles = @(Get-LocalConfigurationState -Application $Application -Location $result.Location)
        foreach ($file in $savedFiles) {
            $backupPath = "$($file.Path).$([guid]::NewGuid().ToString('N')).bak"
            Copy-Item -LiteralPath $file.Path -Destination $backupPath -ErrorAction Stop
            Write-Log -Message "Lokale Konfiguration gesichert: $backupPath"
        }
        if ($result.Location) {
            $result.Phase = 'TargetDirectory'
            Initialize-Directory -Path $result.Location
        }
        $result.Phase = 'Winget'
        try {
            $result.ExitCode = Invoke-Winget -Arguments $result.Arguments
        }
        finally {
            # Installer (insbesondere KeePass Inno) ersetzen Einstellungen auch bei einem Fehler.
            # Alle Wiederherstellungen versuchen, selbst wenn eine davon fehlschlägt.
            $restoreErrors = @()
            foreach ($file in $savedFiles) {
                $restoreOnSuccess = Get-ApplicationOption -Application $file -Name 'RestoreOnSuccess' -Default $true
                if (-not $restoreOnSuccess -and $result.ExitCode -in @(0, $script:wingetNoUpdateExitCode)) {
                    # LibreOffice braucht die neue bootstrap.ini inklusive neuer Produktdaten.
                    # Die Profilumleitung muss auch vor einer später fehlgeschlagenen Versionsprüfung stimmen.
                    try {
                        Initialize-LocalConfiguration -Application $Application -ExecutablePath (
                            Join-Path (Split-Path $file.Path -Parent) 'soffice.exe'
                        )
                    }
                    catch { $restoreErrors += "$($file.Path): $($_.Exception.Message)" }
                    continue
                }
                try { [IO.File]::WriteAllBytes($file.Path, $file.Bytes) }
                catch { $restoreErrors += "$($file.Path): $($_.Exception.Message)" }
            }
            if ($restoreErrors.Count) { throw "Konfiguration nicht wiederhergestellt: $($restoreErrors -join '; ')" }
        }
        if ($result.ExitCode -ne 0 -and $result.ExitCode -ne $script:wingetNoUpdateExitCode) {
            throw "winget meldete Exitcode $($result.ExitCode)."
        }
        $constraint = Get-UpdateVersionConstraint -Application $Application
        if ($constraint.IsLimited -or $result.Action -eq 'Update') {
            $result.Phase = 'VerifyVersion'
            $actualVersion = Get-InstalledUpdateVersion -Id $result.Id
            $versionMatches = if ($constraint.IsLimited) {
                (ConvertTo-UpdateVersion $actualVersion) -eq (ConvertTo-UpdateVersion $result.TargetVersion)
            }
            else { Test-ApplicationVersionEqual -Left $actualVersion -Right $result.TargetVersion }
            if (-not $versionMatches) {
                throw "Versionsprüfung nach Update fehlgeschlagen: erwartet '$($result.TargetVersion)', gefunden '$actualVersion'."
            }
        }
        if ($result.Location) {
            $result.Phase = 'VerifyExecutable'
            $executablePath = Resolve-InstalledExecutable -Application $Application -Location $result.Location
            if ($result.LocalConfig -ne 'None') {
                $result.Phase = 'LocalConfiguration'
                Initialize-LocalConfiguration -Application $Application -ExecutablePath $executablePath
            }
        }
        if ($result.Action -eq 'Install' -and $constraint.VersionPin) {
            $result.Phase = 'VersionPin'
            $pinExitCode = Invoke-Winget -Arguments @(
                'pin', 'add', '--id', $result.Id, '--exact', '--source', 'winget'
                '--version', $constraint.VersionPin, '--force'
                '--accept-source-agreements', '--disable-interactivity'
            )
            if ($pinExitCode -ne 0) { throw "Versions-Pin konnte nicht gesetzt werden (Exitcode $pinExitCode)." }
        }
        $result.Status = if ($result.ExitCode -eq $script:wingetNoUpdateExitCode) { 'AlreadyCurrent' } else { 'Succeeded' }
        $result.Phase = 'Completed'
        $result.Message = 'Verarbeitung erfolgreich abgeschlossen.'
    }
    catch {
        $result.Status = 'Failed'
        $result.Message = $_.Exception.Message
        Write-Log -Level ERROR -Message "$($result.Id): $($result.Message)"
        Write-ErrorDetail -Record $_
    }
    finally {
        $stopwatch.Stop()
        $result.DurationSeconds += [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    }
    return $result
}

function Install-Application {
    param(
        [Parameter(Mandatory)][pscustomobject]$Application,
        [string]$Root,
        [string]$Group = 'Standard',
        [switch]$CheckOnly
    )
    $plan = Get-ApplicationPlan -Application $Application -Root $Root -Group $Group
    if ($CheckOnly) {
        if ($plan.Status -eq 'Planned') { $plan.Status = 'CheckOnly' }
        return $plan
    }
    return Invoke-ApplicationChange -Plan $plan
}

function Update-Application {
    param([Parameter(Mandatory)][pscustomobject]$Application, [string]$Root)
    $plan = Get-ApplicationPlan -Application $Application -Root $Root -Mode Update
    $result = Invoke-ApplicationChange -Plan $plan
    return ($result.Status -ne 'Failed')
}

function Invoke-ApplicationGroups {
    param(
        [Parameter(Mandatory)]
        [object[]]$Groups,
        [string[]]$SelectedId,
        [ValidateSet('Install', 'Update')][string]$Mode = 'Install',
        [switch]$CheckOnly
    )

    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $plans = @(
    foreach ($group in $Groups) {
        foreach ($application in ($group.Applications | Sort-Object {
            Get-ApplicationOption -Application $_ -Name 'Id'
        })) {
            $id = [string](Get-ApplicationOption -Application $application -Name 'Id')
            if ($SelectedId -and $id -notin $SelectedId) {
                continue
            }
            if (-not $seenIds.Add($id)) {
                $script:logContext = "$($group.Name)/$id"
                Write-Log -Level 'ERROR' -Message 'Doppelte Paket-ID; erneute Installation wird verhindert.'
                [pscustomobject]@{
                    Group = $group.Name; Id = $id; Name = ''; Location = ''
                    Status = 'Failed'; Phase = 'Configuration'; ExitCode = $null
                    DurationSeconds = 0; Message = 'Doppelte Paket-ID.'
                    Action = 'Error'; InstalledVersion = ''; TargetVersion = ''; Source = 'winget'
                    InstallerType = ''; Scope = ''; Architecture = ''; Locale = ''; CustomArguments = ''; LocalConfig = ''
                }
                continue
            }
            Get-ApplicationPlan -Application $application -Root $group.Root -Group $group.Name -Mode $Mode
        }
    }
    foreach ($id in ($SelectedId | Select-Object -Unique)) {
        if (-not $seenIds.Contains($id)) {
            $script:logContext = "Selection/$id"
            Write-Log -Level 'ERROR' -Message 'Die angeforderte Paket-ID ist nicht in der Konfiguration vorhanden.'
            [pscustomobject]@{
                Group = ''; Id = $id; Name = ''; Location = ''
                Status = 'Failed'; Phase = 'Selection'; ExitCode = $null
                DurationSeconds = 0; Message = 'Unbekannte ausgewählte Paket-ID.'
                Action = 'Error'; InstalledVersion = ''; TargetVersion = ''; Source = 'winget'
                InstallerType = ''; Scope = ''; Architecture = ''; Locale = ''; CustomArguments = ''; LocalConfig = ''
            }
        }
    }
    )
    Write-ApplicationPreview -Plans $plans
    foreach ($plan in $plans) {
        if ($CheckOnly) {
            if ($plan.Status -eq 'Planned') { $plan.Status = 'CheckOnly' }
            $plan
        }
        else { Invoke-ApplicationChange -Plan $plan }
    }
}

function Invoke-Installation {
    param(
        [ValidateSet('Install', 'Update')][string]$Mode = 'Install',
        [switch]$CheckOnly
    )
    Write-LogLocation
    Write-Log -Message (
        "PowerShell $($PSVersionTable.PSVersion); Betriebssystem: $([Environment]::OSVersion.VersionString); " +
        "Prozessarchitektur: $([IntPtr]::Size * 8) Bit; Benutzer: $([Environment]::UserName)"
    )
    Write-Log -Message "Ziele: InstalledTools='$InstalledToolsRoot'; PortableTools='$PortableToolsRoot'."
    if (-not $CheckOnly -and -not (Test-Administrator)) {
        Write-Log -Level 'ERROR' -Message (
            'Administratorrechte fehlen. Das Skript muss in einer als Administrator ' +
            'gestarteten PowerShell ausgeführt werden.'
        )
        return 1
    }
    $wingetCommand = Get-Command -Name 'winget' -CommandType Application -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        Write-Log -Level 'ERROR' -Message (
            'winget wurde nicht gefunden. Installieren oder aktualisieren Sie den Microsoft App Installer.'
        )
        return 1
    }
    Write-Log -Message "winget: $($wingetCommand.Source)"

    if ($CheckOnly) {
        Write-Log -Message 'CheckOnly: Nur lesende Prüfungen. Keine Pakete, Zielordner, Konfigurationen, Backups, Sprachdownloads oder Pins; nur Logs/CSV.'
    }
    $results = @(Invoke-ApplicationGroups -Groups $applicationGroups -SelectedId $ApplicationId -Mode $Mode -CheckOnly:$CheckOnly)
    $script:logContext = 'Summary'
    foreach ($result in $results) {
        Write-Log -Message (
            "$($result.Id): $($result.Status); Phase=$($result.Phase); Exitcode=$($result.ExitCode); " +
            "Dauer=$($result.DurationSeconds)s; Ziel='$($result.Location)'; $($result.Message)"
        )
    }
    $failedCount = @($results | Where-Object Status -eq 'Failed').Count
    $counts = @($results | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" })
    Write-Log -Message "Ergebnis ($Mode; CheckOnly=$CheckOnly): $($counts -join ', ')."
    try {
        $summaryFile = [IO.Path]::ChangeExtension($script:logFile, '.csv')
        $results | Select-Object * -ExcludeProperty Application, Arguments |
            Export-Csv -LiteralPath $summaryFile -NoTypeInformation -Encoding UTF8
        Write-Log -Message "Ergebnisliste: $summaryFile"
    }
    catch {
        $script:loggingFailed = $true
        Write-Log -Level 'ERROR' -Message (
            "CSV-Ergebnisliste konnte nicht geschrieben werden: $($_.Exception.Message)"
        )
        Write-ErrorDetail -Record $_
    }
    if ($failedCount -gt 0 -or $script:loggingFailed) {
        return 2
    }
    return 0
}
