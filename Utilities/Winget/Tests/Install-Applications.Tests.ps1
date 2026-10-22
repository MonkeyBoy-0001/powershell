#requires -Version 5.1

<#
.SYNOPSIS
Pester-Regressionen fuer Installation, Konfigurationsschutz und Diagnose.
.DESCRIPTION
Mit Pester 3.4.0 ausfuehren, nicht direkt starten. Aufrufe und Isolation:
README.md neben dieser Testsuite.
.LINK
README.md
#>

# The shared library has no installation entry point or initialization side effects.
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Application-Management.ps1'
$script:versionPolicyFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'Application-VersionPolicies.psd1'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Application-VersionPolicy.ps1')
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw ($parseErrors -join "`n")
}
. $scriptPath

Describe 'Application installation and isolation' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $script:logFile = Join-Path $TestDrive 'run.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'Test'
        $script:wingetNoUpdateExitCode = -1978335189
        $script:capturedArguments = @()
        Mock Invoke-Winget {
            $script:capturedArguments = $Arguments
            return 0
        }
        Mock Get-InstalledApplicationState {
            [pscustomobject]@{ IsInstalled = $false; Version = ''; AvailableVersion = '' }
        }
        Mock Get-InstalledUpdateVersion {
            if ($Id -eq 'Celsys.ClipStudioPaint') { return '5.0.4' }
            return $script:capturedArguments[[array]::IndexOf($script:capturedArguments, '--version') + 1]
        }
        Mock Test-ApplicationManifest {
            [pscustomobject]@{ Version = $(if ($Version) { $Version } else { '1.2' }); InstallerType = 'exe' }
        }
        Mock Write-Host {}
    }

    It 'installs a minimal standard entry and applies optional switches' {
        $app = [pscustomobject]@{
            Name = 'Example'; Id = 'Vendor.Example'
            Scope = 'user'; Architecture = 'x64'; Version = '1.2'; InstallerType = 'wix'
            Locale = 'de'; CustomArguments = 'UI_LANGS=de TRANSFORMS=:1031'
        }
        $result = Install-Application -Application $app
        $result.Status | Should Be 'Succeeded'
        ($script:capturedArguments -join '|') | Should Match '\-\-scope\|user'
        ($script:capturedArguments -join '|') | Should Match '\-\-installer-type\|wix'
        ($script:capturedArguments -join '|') | Should Match '\-\-architecture\|x64'
        ($script:capturedArguments -join '|') | Should Match '\-\-version\|1.2'
        ($script:capturedArguments -join '|') | Should Match '\-\-locale\|de'
        ($script:capturedArguments -contains 'UI_LANGS=de TRANSFORMS=:1031') | Should Be $true
        ($script:capturedArguments -join '|') | Should Match '\-\-custom\|'
        ($script:capturedArguments -join '|') | Should Not Match '\-\-location'
    }

    It 'sorts each group and continues after a native failure' {
        Mock Invoke-Winget {
            if ($Arguments -contains 'A.Failed') { return 123 }
            return 0
        }
        $groups = @([pscustomobject]@{
            Name = 'Standard'; Root = ''; Applications = @(
                [pscustomobject]@{ Name = 'Last'; Id = 'Z.Success' }
                [pscustomobject]@{ Name = 'First'; Id = 'A.Failed' }
            )
        })
        $results = @(Invoke-ApplicationGroups -Groups $groups)
        $results.Count | Should Be 2
        $results[0].Id | Should Be 'A.Failed'
        $results[0].Status | Should Be 'Failed'
        $results[0].ExitCode | Should Be 123
        $results[0].Phase | Should Be 'Winget'
        $results[1].Status | Should Be 'Succeeded'
        (Get-Content $script:logFile -Raw) | Should Match 'A.Failed'
        (Get-Content $script:logFile -Raw) | Should Match 'Stack:'
    }

    It 'does not let an inaccessible target prevent the next group' {
        $blocked = Join-Path $TestDrive 'blocked'
        New-Item -ItemType File -Path $blocked | Out-Null
        $groups = @(
            [pscustomobject]@{
                Name = 'Tools'; Root = $blocked; Applications = @(
                    [pscustomobject]@{ Name = 'Bad'; Id = 'A.Bad'; Directory = 'App'; Executable = 'app.exe' }
                )
            }
            [pscustomobject]@{
                Name = 'Standard'; Root = ''; Applications = @(
                    [pscustomobject]@{ Name = 'Good'; Id = 'B.Good' }
                )
            }
        )
        $results = @(Invoke-ApplicationGroups -Groups $groups)
        $results[0].Status | Should Be 'Failed'
        $results[0].Phase | Should Be 'TargetDirectory'
        $results[1].Status | Should Be 'Succeeded'
        Assert-MockCalled Invoke-Winget -Times 1 -Exactly -Scope It
    }

    It 'rejects unknown fields and invalid paths before invoking winget' {
        $badField = [pscustomobject]@{ Name = 'Bad'; Id = 'A.Bad'; Loaction = 'wrong' }
        (Install-Application -Application $badField).Phase | Should Be 'Configuration'
        $badPath = [pscustomobject]@{
            Name = 'Bad'; Id = 'B.Bad'; Directory = '..\Outside'; Executable = 'app.exe'
        }
        (Install-Application -Application $badPath -Root $TestDrive).Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'skips disabled entries without creating their target' {
        $app = [pscustomobject]@{ Name = 'Off'; Id = 'A.Off'; Enabled = $false }
        (Install-Application -Application $app -Root $TestDrive).Status | Should Be 'Skipped'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'rejects string booleans rather than installing a disabled application' {
        $app = [pscustomobject]@{ Name = 'Off'; Id = 'A.Off'; Enabled = 'false' }
        (Install-Application -Application $app).Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'rejects a malformed locale before running winget' {
        $app = [pscustomobject]@{ Name = 'Bad'; Id = 'A.Bad'; Locale = 'German --force' }
        (Install-Application -Application $app).Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'filters IDs and reports unknown selections' {
        $groups = @([pscustomobject]@{
            Name = 'Standard'; Root = ''; Applications = @(
                [pscustomobject]@{ Name = 'A'; Id = 'A.App' }
                [pscustomobject]@{ Name = 'B'; Id = 'B.App' }
            )
        })
        $results = @(Invoke-ApplicationGroups -Groups $groups -SelectedId 'B.App', 'Missing.App')
        $results.Count | Should Be 2
        $results[0].Id | Should Be 'B.App'
        $results[1].Phase | Should Be 'Selection'
        $results[1].Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 1 -Exactly -Scope It
    }

    It 'reports duplicate IDs instead of installing twice' {
        $groups = @([pscustomobject]@{
            Name = 'Standard'; Root = ''; Applications = @(
                [pscustomobject]@{ Name = 'A'; Id = 'A.App' }
                [pscustomobject]@{ Name = 'B'; Id = 'a.app' }
            )
        })
        $results = @(Invoke-ApplicationGroups -Groups $groups)
        $results[1].Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 1 -Exactly -Scope It
    }

    It 'fails verification even if winget says already current elsewhere' {
        Mock Invoke-Winget { return -1978335189 }
        $app = [pscustomobject]@{
            Name = 'Missing'; Id = 'A.Missing'; Directory = 'Missing'; Executable = 'missing.exe'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'VerifyExecutable'
        $result.ExitCode | Should Be -1978335189
    }

    It 'initializes local settings for an existing current installation' {
        Mock Invoke-Winget { return -1978335189 }
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'KeePassXC')
        New-Item -ItemType File -Path (Join-Path $dir.FullName 'KeePassXC.exe') | Out-Null
        $app = [pscustomobject]@{
            Name = 'KeePassXC'; Id = 'KeePassXCTeam.KeePassXC'; Directory = 'KeePassXC'
            Executable = 'KeePassXC.exe'; LocalConfig = 'KeePassXC'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'AlreadyCurrent'
        (Test-Path (Join-Path $dir.FullName '.portable')) | Should Be $true
        (Test-Path (Join-Path $dir.FullName 'config')) | Should Be $true
    }

    It 'rejects ambiguous executable matches' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Ambiguous')
        New-Item -ItemType File -Path (Join-Path $dir.FullName 'rufus-old.exe') | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir.FullName 'rufus-new.exe') | Out-Null
        $app = [pscustomobject]@{
            Name = 'Rufus'; Id = 'Rufus.Rufus'; Directory = 'Ambiguous'; Executable = 'rufus*.exe'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'VerifyExecutable'
        $result.Message | Should Match 'mehrfach'
    }

    It 'preserves existing configuration contents' {
        $path = Join-Path $TestDrive 'existing.ini'
        New-Item -ItemType File -Path $path -Value 'user settings' | Out-Null
        New-LocalConfigurationFile -Path $path -Content 'replacement'
        (Get-Content $path -Raw) | Should Be 'user settings'
    }

    It 'uses the actual MPC-BE executable name for x86 configuration' {
        $exe = Join-Path $TestDrive 'mpc-be.exe'
        New-Item -ItemType File -Path $exe | Out-Null
        Initialize-LocalConfiguration -Application ([pscustomobject]@{
            Name = 'MPC-BE'; LocalConfig = 'MPC-BE'
        }) -ExecutablePath $exe
        (Test-Path (Join-Path $TestDrive 'mpc-be.ini')) | Should Be $true
    }

    It 'records local configuration errors as package failures' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'App')
        New-Item -ItemType File -Path (Join-Path $dir.FullName 'app.exe') | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dir.FullName 'rufus.ini') | Out-Null
        $app = [pscustomobject]@{
            Name = 'App'; Id = 'A.App'; Directory = 'App'; Executable = 'app.exe'; LocalConfig = 'Rufus'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'ConfigurationPreflight'
        ($null -eq $result.ExitCode) | Should Be $true
    }

    It 'installs the selected Clip Studio version and sets its gated pin' {
        $script:wingetCalls = @()
        Mock Invoke-Winget {
            $script:wingetCalls += ,$Arguments
            return 0
        }
        $app = [pscustomobject]@{
            Name = 'CLIP STUDIO PAINT'; Id = 'Celsys.ClipStudioPaint'
            Version = '5.0.4'; VersionPin = '5.0.*'
        }
        (Install-Application -Application $app).Status | Should Be 'Succeeded'
        $script:wingetCalls.Count | Should Be 2
        ($script:wingetCalls[0] -join '|') | Should Match '--version\|5\.0\.4'
        ($script:wingetCalls[1] -join '|') | Should Match '^pin\|add\|--id\|Celsys\.ClipStudioPaint'
        ($script:wingetCalls[1] -join '|') | Should Match '--version\|5\.0\.\*'
    }

    It 'rejects an install version outside its pinned release series' {
        $app = [pscustomobject]@{
            Name = 'CLIP STUDIO PAINT'; Id = 'Celsys.ClipStudioPaint'
            Version = '5.1.1'; VersionPin = '5.0.*'
        }
        $result = Install-Application -Application $app
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'Configuration'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'reports a failed version pin instead of claiming complete success' {
        Mock Invoke-Winget {
            if ($Arguments[0] -eq 'pin') { return 123 }
            return 0
        }
        $app = [pscustomobject]@{
            Name = 'CLIP STUDIO PAINT'; Id = 'Celsys.ClipStudioPaint'
            Version = '5.0.4'; VersionPin = '5.0.*'
        }
        $result = Install-Application -Application $app
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'VersionPin'
        $result.Message | Should Match '123'
    }

    It 'configures LibreOffice locally while preserving other bootstrap settings' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'LibreOffice\program') -Force
        $bootstrap = Join-Path $dir.FullName 'bootstrap.ini'
        $original = "[Bootstrap]`r`nProductKey=LibreOffice`r`nUserInstallation=`$SYSUSERCONFIG/LibreOffice/4`r`n[Other]`r`nValue=unchanged`r`n"
        New-Item -ItemType File -Path $bootstrap -Value $original | Out-Null
        $app = [pscustomobject]@{ Name = 'LibreOffice'; LocalConfig = 'LibreOffice' }
        Initialize-LocalConfiguration -Application $app -ExecutablePath (Join-Path $dir.FullName 'soffice.exe')
        $expected = $original.Replace('$SYSUSERCONFIG/LibreOffice/4', '$ORIGIN/../profile')
        (Get-Content -LiteralPath $bootstrap -Raw) | Should Be $expected
        (Test-Path -LiteralPath (Join-Path $TestDrive 'LibreOffice\profile')) | Should Be $true
        $backup = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.bak')
        $backup.Count | Should Be 1
        (Get-Content -LiteralPath $backup[0].FullName -Raw) | Should Be $original
        Initialize-LocalConfiguration -Application $app -ExecutablePath (Join-Path $dir.FullName 'soffice.exe')
        @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.bak').Count | Should Be 1
    }

    It 'does not overwrite an existing custom LibreOffice profile' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'CustomLibreOffice\program') -Force
        $bootstrap = Join-Path $dir.FullName 'bootstrap.ini'
        $original = "[Bootstrap]`r`nUserInstallation=file:///E:/ExistingProfile`r`n"
        New-Item -ItemType File -Path $bootstrap -Value $original | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir.FullName 'soffice.exe') | Out-Null
        $app = [pscustomobject]@{
            Name = 'LibreOffice'; Id = 'TheDocumentFoundation.LibreOffice'
            Directory = 'CustomLibreOffice'; Executable = 'soffice.exe'; LocalConfig = 'LibreOffice'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'ConfigurationPreflight'
        (Get-Content -LiteralPath $bootstrap -Raw) | Should Be $original
        $result.Message | Should Match 'benutzerdefiniertes'
    }

    It 'falls back to a second log file and records the failed write' {
        $blocked = Join-Path $TestDrive 'log-blocked'
        New-Item -ItemType File -Path $blocked | Out-Null
        $script:logFile = Join-Path $blocked 'run.log'
        Write-Log -Message 'Important diagnostic'
        $script:loggingFailed | Should Be $true
        $script:logFile | Should Be $script:fallbackLogFile
        (Get-Content $script:logFile -Raw) | Should Match 'Important diagnostic'
        (Get-Content $script:logFile -Raw) | Should Match 'Logfehler'
    }

    It 'continues with console diagnostics when both log paths are unusable' {
        $blocked = Join-Path $TestDrive 'all-logs-blocked'
        New-Item -ItemType File -Path $blocked | Out-Null
        $script:logFile = Join-Path $blocked 'first.log'
        $script:fallbackLogFile = Join-Path $blocked 'second.log'
        { Write-Log -Level ERROR -Message 'Important failure' } | Should Not Throw
        $script:loggingFailed | Should Be $true
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Ausgabe nur auf der Konsole*' } -Times 1 -Scope It
    }
}

Describe 'Configured package requirements' {
    It 'contains all five new packages and only the German Mozilla IDs' {
        $catalogue = @{}
        $groups = @(Get-ApplicationGroups)
        $index = 0
        foreach ($name in @('standardApplications', 'installedToolsApplications', 'portableToolsApplications')) {
            $catalogue[$name] = @($groups[$index++].Applications)
            $ids = @($catalogue[$name] | ForEach-Object Id)
            ($ids -join '|') | Should Be (($ids | Sort-Object) -join '|')
        }
        $standardIds = @($catalogue.standardApplications | ForEach-Object Id)
        ($standardIds -contains 'Canva.Affinity') | Should Be $true
        ($standardIds -contains 'Celsys.ClipStudioPaint') | Should Be $true
        ($standardIds -contains 'Mozilla.Firefox.de') | Should Be $true
        ($standardIds -contains 'Mozilla.Thunderbird.de') | Should Be $true
        ($standardIds -contains 'Mozilla.Firefox') | Should Be $false
        ($standardIds -contains 'Mozilla.Thunderbird') | Should Be $false
        ($catalogue.installedToolsApplications.Id -contains 'eMClient.eMClient') | Should Be $true
        ($catalogue.installedToolsApplications.Id -contains 'LibreCAD.LibreCAD') | Should Be $true
        ($catalogue.portableToolsApplications.Id -contains 'TheDocumentFoundation.LibreOffice') | Should Be $true
        $clip = Resolve-ApplicationVersionPolicy -Application (
            $catalogue.standardApplications | Where-Object Id -eq 'Celsys.ClipStudioPaint'
        ) -PolicyFile $script:versionPolicyFile
        $clip.Version | Should Be '5.0.4'
        $clip.VersionPin | Should Be '5.0.*'
        ($catalogue.standardApplications | Where-Object Id -eq 'RARLab.WinRAR').Locale | Should Be 'de'
        ($catalogue.standardApplications | Where-Object Id -eq 'Governikus.AusweisApp').Locale | Should Be 'de-DE'
        ($catalogue.portableToolsApplications | Where-Object Id -eq 'TheDocumentFoundation.LibreOffice').CustomArguments | Should Be 'UI_LANGS=de'
        $keepass = Resolve-ApplicationVersionPolicy -Application (
            $catalogue.portableToolsApplications | Where-Object Id -eq 'DominikReichl.KeePass'
        ) -PolicyFile $script:versionPolicyFile
        $keepass.LocalConfig | Should Be 'KeePassGerman'
        $keepass.Version | Should Be '2.61.1'
    }
}

Describe 'KeePass configuration preflight' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $script:logFile = Join-Path $TestDrive 'keepass.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'keepass-fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'KeePassTest'
        $script:wingetNoUpdateExitCode = -1978335189
        $script:userConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'KeePass\KeePass.config.xml'
        Mock Get-Process { return @() }
        Mock Test-Path { return $false } -ParameterFilter { $LiteralPath -eq $script:userConfigPath }
        Mock Write-Host {}
        Mock Invoke-Winget { return 0 }
        Mock Get-InstalledApplicationState {
            [pscustomobject]@{ IsInstalled = $false; Version = ''; AvailableVersion = '' }
        }
        Mock Test-ApplicationManifest { [pscustomobject]@{ Version = '2.61.1'; InstallerType = 'inno' } }
    }

    It 'allows a fresh local installation' {
        $state = Get-KeePassConfigurationState -Location $TestDrive
        ($null -eq $state.ConfigBytes) | Should Be $true
    }

    It 'refuses running KeePass instances before installation' {
        Mock Get-Process { [pscustomobject]@{ ProcessName = 'KeePass' } }
        $app = [pscustomobject]@{
            Name = 'KeePass'; Id = 'DominikReichl.KeePass'; Directory = 'Running'
            Executable = 'KeePass.exe'; LocalConfig = 'KeePassGerman'
            InstallerType = 'inno'; Version = '2.61.1'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Phase | Should Be 'ConfigurationPreflight'
        $result.Status | Should Be 'Failed'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'does not migrate an existing user profile' {
        Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -eq $script:userConfigPath }
        $app = [pscustomobject]@{
            Name = 'KeePass'; Id = 'DominikReichl.KeePass'; Directory = 'UserProfile'
            Executable = 'KeePass.exe'; LocalConfig = 'KeePassGerman'
            InstallerType = 'inno'; Version = '2.61.1'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Message | Should Match 'Benutzereinstellungen'
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'refuses conflicting settings without invoking the installer' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Conflict')
        $path = Join-Path $dir.FullName 'KeePass.config.xml'
        $original = '<Configuration><Meta><PreferUserConfiguration>true</PreferUserConfiguration></Meta></Configuration>'
        New-Item -ItemType File -Path $path -Value $original | Out-Null
        $app = [pscustomobject]@{
            Name = 'KeePass'; Id = 'DominikReichl.KeePass'; Directory = 'Conflict'
            Executable = 'KeePass.exe'; LocalConfig = 'KeePassGerman'
            InstallerType = 'inno'; Version = '2.61.1'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'ConfigurationPreflight'
        (Get-Content -LiteralPath $path -Raw) | Should Be $original
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'restores valid local preferences even when the installer overwrites them and fails' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Preserve')
        $script:preservedConfigPath = Join-Path $dir.FullName 'KeePass.config.xml'
        $original = '<Configuration><Meta><PreferUserConfiguration>false</PreferUserConfiguration></Meta><Application><LanguageFile>German.lngx</LanguageFile></Application><UI><TrayIcon>true</TrayIcon></UI></Configuration>'
        New-Item -ItemType File -Path $script:preservedConfigPath -Value $original | Out-Null
        Mock Invoke-Winget {
            [IO.File]::WriteAllText($script:preservedConfigPath, '<Configuration />')
            return 42
        }
        $app = [pscustomobject]@{
            Name = 'KeePass'; Id = 'DominikReichl.KeePass'; Directory = 'Preserve'
            Executable = 'KeePass.exe'; LocalConfig = 'KeePassGerman'
            InstallerType = 'inno'; Version = '2.61.1'
        }
        $result = Install-Application -Application $app -Root $TestDrive
        $result.Status | Should Be 'Failed'
        $result.ExitCode | Should Be 42
        (Get-Content -LiteralPath $script:preservedConfigPath -Raw) | Should Be $original
        @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.bak').Count | Should Be 1
    }
}

Describe 'KeePass German language deployment' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $script:logFile = Join-Path $TestDrive 'language.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'language-fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'LanguageTest'
        $script:languageTestDirectory = (New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))).FullName
        $script:languageTestExecutable = Join-Path $script:languageTestDirectory 'KeePass.exe'
        $script:downloadedArchive = ''
        Mock Write-Host {}
        Mock Get-Item {
            [pscustomobject]@{ VersionInfo = [pscustomobject]@{
                FileMajorPart = 2; FileMinorPart = 61; FileBuildPart = 1
                FilePrivatePart = 0; FileVersion = '2.61.1.0'
            } }
        } -ParameterFilter { $LiteralPath -eq $script:languageTestExecutable }
        # A synthetic ZIP replaces the network artifact. Its metadata/hash are mocked
        # only in these tests; production checks the pinned official bytes.
        Mock Get-Item { [pscustomobject]@{ Length = 45754 } } -ParameterFilter {
            $LiteralPath -like '*KeePass-German-*.zip'
        }
        Mock Get-FileHash {
            [pscustomobject]@{ Hash = 'A0EC490D2A7262A8D8ADEF53F87B5EDE70CB0BFEC522C998F7927444D72CFB40' }
        }
        Mock Invoke-WebRequest {
            $script:downloadedArchive = $OutFile
            Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::Open($OutFile, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('German.lngx')
                $stream = $entry.Open()
                try {
                    $bytes = New-Object byte[] 45598
                    $bytes[0] = 31
                    $bytes[1] = 139
                    $stream.Write($bytes, 0, $bytes.Length)
                }
                finally { $stream.Dispose() }
            }
            finally { $archive.Dispose() }
        }
    }

    It 'deploys the original LNGX bytes and selects German locally' {
        $configPath = Join-Path $script:languageTestDirectory 'KeePass.config.xml'
        New-Item -ItemType File -Path $configPath -Value '<Configuration><UI><TrayIcon>true</TrayIcon></UI></Configuration>' | Out-Null
        Install-KeePassGermanLanguage -ExecutablePath $script:languageTestExecutable
        $document = Read-KeePassConfiguration -Path $configPath
        $document.SelectSingleNode('/Configuration/Meta/PreferUserConfiguration').InnerText | Should Be 'false'
        $document.SelectSingleNode('/Configuration/Application/LanguageFile').InnerText | Should Be 'German.lngx'
        $document.SelectSingleNode('/Configuration/UI/TrayIcon').InnerText | Should Be 'true'
        $languageBytes = [IO.File]::ReadAllBytes((Join-Path $script:languageTestDirectory 'Languages\German.lngx'))
        $languageBytes.Length | Should Be 45598
        $languageBytes[0] | Should Be 31
        $languageBytes[1] | Should Be 139
        (Test-Path -LiteralPath $script:downloadedArchive) | Should Be $false
    }

    It 'does not install a language file if the checksum is wrong' {
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'incorrect' } }
        $caught = $null
        try { Install-KeePassGermanLanguage -ExecutablePath $script:languageTestExecutable }
        catch { $caught = $_ }
        ($null -ne $caught) | Should Be $true
        $caught.Exception.Message | Should Match 'SHA-256'
        (Test-Path -LiteralPath (Join-Path $script:languageTestDirectory 'Languages\German.lngx')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $script:languageTestDirectory 'KeePass.config.xml')) | Should Be $false
        (Test-Path -LiteralPath $script:downloadedArchive) | Should Be $false
    }

    It 'refuses to overwrite an existing different German translation' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $script:languageTestDirectory 'Languages')
        $path = Join-Path $dir.FullName 'German.lngx'
        New-Item -ItemType File -Path $path -Value 'existing translation' | Out-Null
        $caught = $null
        try { Install-KeePassGermanLanguage -ExecutablePath $script:languageTestExecutable }
        catch { $caught = $_ }
        ($null -ne $caught) | Should Be $true
        $caught.Exception.Message | Should Match 'nicht .berschrieben'
        (Get-Content -LiteralPath $path -Raw) | Should Be 'existing translation'
    }
}

Describe 'Run summary and prerequisites' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $script:logFile = Join-Path $TestDrive 'summary.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'summary-fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'SummaryTest'
        $script:wingetNoUpdateExitCode = -1978335189
        $script:InstalledToolsRoot = 'C:\Tools'
        $script:PortableToolsRoot = 'D:\Tools'
        $script:ApplicationId = $null
        $script:applicationGroups = @([pscustomobject]@{
            Name = 'Standard'; Root = ''; Applications = @(
                [pscustomobject]@{ Name = 'Example'; Id = 'A.Example' }
            )
        })
        Mock Test-Administrator { return $true }
        Mock Get-Command { [pscustomobject]@{ Source = 'mock-winget.exe' } } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-Winget { return 0 }
        Mock Get-InstalledApplicationState {
            [pscustomobject]@{ IsInstalled = $false; Version = ''; AvailableVersion = '' }
        }
        Mock Test-ApplicationManifest { [pscustomobject]@{ Version = '1.2'; InstallerType = 'exe' } }
        Mock Write-Host {}
    }

    It 'writes one CSV record per package and returns success' {
        (Invoke-Installation) | Should Be 0
        $rows = @(Import-Csv (Join-Path $TestDrive 'summary.csv'))
        $rows.Count | Should Be 1
        $rows[0].Id | Should Be 'A.Example'
        $rows[0].Status | Should Be 'Succeeded'
        $rows[0].Phase | Should Be 'Completed'
        $rows[0].ExitCode | Should Be '0'
    }

    It 'returns partial failure for a package error' {
        Mock Invoke-Winget { return 42 }
        (Invoke-Installation) | Should Be 2
        (Import-Csv (Join-Path $TestDrive 'summary.csv')).ExitCode | Should Be '42'
    }

    It 'returns partial failure for CSV write errors without losing text results' {
        $csvPath = Join-Path $TestDrive 'summary.csv'
        if (Test-Path -LiteralPath $csvPath -PathType Leaf) {
            Remove-Item -LiteralPath $csvPath
        }
        New-Item -ItemType Directory -Path $csvPath | Out-Null
        (Invoke-Installation) | Should Be 2
        (Get-Content $script:logFile -Raw) | Should Match 'CSV-Ergebnisliste konnte nicht geschrieben werden'
        (Get-Content $script:logFile -Raw) | Should Match 'A.Example: Succeeded'
    }

    It 'returns a global failure without starting packages when admin rights are missing' {
        Mock Test-Administrator { return $false }
        (Invoke-Installation) | Should Be 1
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'returns a global failure without starting packages when winget is missing' {
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'winget' }
        (Invoke-Installation) | Should Be 1
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }
}

Describe 'Native process output' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $script:logFile = Join-Path $TestDrive 'native.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'native-fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'NativeTest'
        Mock Write-Host {}
    }

    It 'captures stderr and the real exit code without terminating on stderr' {
        # Resolve "winget" to a real native test process, never an installer.
        Set-Alias -Name winget -Value $env:ComSpec -Scope Script
        try {
            foreach ($expectedCode in @(0, 7, -1978335189)) {
                $code = Invoke-Winget -Arguments @(
                    '/d', '/c', "echo stdout-line & echo stderr-line 1>&2 & exit /b $expectedCode"
                )
                $code | Should Be $expectedCode
            }
        }
        finally {
            Remove-Item Alias:\winget -Force
        }
        (Get-Content $script:logFile -Raw) | Should Match 'stdout-line'
        (Get-Content $script:logFile -Raw) | Should Match 'stderr-line'
        (Get-Content $script:logFile -Raw) | Should Match '0x00000007'
        (Get-Content $script:logFile -Raw) | Should Match '0x8A15002B'
        $ErrorActionPreference | Should Be 'Stop'
    }
}
