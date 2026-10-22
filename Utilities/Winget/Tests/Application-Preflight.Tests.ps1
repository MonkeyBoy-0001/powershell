#requires -Version 5.1

<#
.SYNOPSIS
Pester-Regressionen fuer Katalog, Vorschau und lesende Vorpruefungen.
.DESCRIPTION
Mit Pester 3.4.0 ausfuehren, nicht direkt starten. Aufrufe und Isolation:
README.md neben dieser Testsuite.
.LINK
README.md
#>
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Application-Management.ps1')

Describe 'Shared catalogue and read-only application preflight' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $script:versionPolicyFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'Application-VersionPolicies.psd1'
        $script:wingetNoUpdateExitCode = -1978335189
        $script:logFile = Join-Path $TestDrive 'preflight.log'
        $script:fallbackLogFile = Join-Path $TestDrive 'fallback.log'
        $script:loggingFailed = $false
        $script:logContext = 'Test'
        $script:events = @()
        $script:commands = @()
        $script:preview = @()
        $script:states = @{}
        $script:versions = @('5.1.1', '5.0.10', '5.0.9', '5.0.12-beta', '2.61.1', '1.2')
        $script:listCode = 0
        $script:listText = $null
        $script:showCode = 0
        $script:showText = $null
        $script:mutationCode = 0
        $script:overwritePath = ''
        $script:overwriteContent = 'installer overwrite'
        $script:runningProcess = ''
        $script:userConfigPresent = $false
        $script:admin = $false
        $script:wingetPresent = $true
        $script:messages = @()
        $script:changeBeforeExecute = $false
        $script:userPaths = @(
            (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'KeePass\KeePass.config.xml')
            (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'LibreOffice\4')
        )
        Mock Test-Path { return $script:userConfigPresent } -ParameterFilter { $LiteralPath -in $script:userPaths }
        Mock Write-Log { $script:messages += $Message }
        Mock Write-Host {}
        Mock Write-ApplicationPreview {
            $script:preview = $Plans
            $script:events += 'Preview'
            if ($script:changeBeforeExecute) { $script:states['A.App'].Version = '9.0' }
        }
        Mock Get-Process {
            if ($script:runningProcess) { [pscustomobject]@{ ProcessName = $script:runningProcess } }
        }
        Mock Test-Administrator { return $script:admin }
        Mock Get-Command {
            if ($script:wingetPresent) { [pscustomobject]@{ Source = 'mock-winget.exe' } }
        } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-WebRequest { throw 'No network downloads permitted in preflight tests.' }
        Mock Install-KeePassGermanLanguage {}
        Mock Invoke-Winget {
            $script:commands += ,$Arguments
            $verb = $Arguments[0]
            $id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
            $script:events += "$verb|$id"
            switch ($verb) {
                'list' {
                    if ($script:listCode -ne 0) {
                        return [pscustomobject]@{ ExitCode = $script:listCode; Output = @('Query failed') }
                    }
                    if ($null -ne $script:listText) {
                        return [pscustomobject]@{ ExitCode = 0; Output = $script:listText }
                    }
                    if (-not $script:states.ContainsKey($id)) {
                        return [pscustomobject]@{ ExitCode = -1978335212; Output = @('No installed package found') }
                    }
                    $state = $script:states[$id]
                    return [pscustomobject]@{
                        ExitCode = 0
                        Output = @('Name Id Version Available Source', '------------------------------------------',
                            "Application  $id  $($state.Version) $($state.Available) winget")
                    }
                }
                'show' {
                    if ($script:showCode -ne 0) {
                        return [pscustomobject]@{ ExitCode = $script:showCode; Output = @('Source failure') }
                    }
                    if ($null -ne $script:showText) {
                        return [pscustomobject]@{ ExitCode = 0; Output = $script:showText }
                    }
                    if ($Arguments -contains '--versions') {
                        return [pscustomobject]@{ ExitCode = 0; Output = @('Version', '-------') + $script:versions }
                    }
                    $version = '1.2'
                    if ($Arguments -contains '--version') {
                        $version = $Arguments[[array]::IndexOf($Arguments, '--version') + 1]
                    }
                    $type = 'exe'
                    if ($Arguments -contains '--installer-type') {
                        $type = $Arguments[[array]::IndexOf($Arguments, '--installer-type') + 1]
                    }
                    return [pscustomobject]@{
                        ExitCode = 0; Output = @("Found Application [$id]", "Version: $version", "  Installer Type: $type")
                    }
                }
                { $_ -in @('install', 'upgrade') } {
                    if ($script:overwritePath) { [IO.File]::WriteAllText($script:overwritePath, $script:overwriteContent) }
                    if ($script:mutationCode -eq 0) {
                        $script:states[$id] = @{
                            Version = $Arguments[[array]::IndexOf($Arguments, '--version') + 1]; Available = ''
                        }
                    }
                    return $script:mutationCode
                }
                default { throw "Forbidden unexpected winget command: $verb" }
            }
        }
    }

    It 'uses one 36-entry catalogue with the original 20/7/9 groups and German options' {
        $groups = @(Get-ApplicationGroups)
        ($groups.Applications | Measure-Object).Count | Should Be 36
        $groups[0].Applications.Count | Should Be 20
        $groups[1].Applications.Count | Should Be 7
        $groups[2].Applications.Count | Should Be 9
        @($groups.Applications.Id | Select-Object -Unique).Count | Should Be 36
        foreach ($id in @('Canva.Affinity', 'eMClient.eMClient', 'LibreCAD.LibreCAD',
            'TheDocumentFoundation.LibreOffice', 'DominikReichl.KeePass')) {
            ($groups.Applications.Id -contains $id) | Should Be $true
        }
        ($groups.Applications.Id -contains 'CDrFE') | Should Be $false
        ($groups.Applications | Where-Object Id -eq 'MPC-BE.MPC-BE').CustomArguments | Should Be '/LANG=de'
        foreach ($scriptName in @('Install-Applications.ps1', 'Update-Applications.ps1')) {
            $content = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) $scriptName) -Raw
            $content | Should Match 'Application-Management.ps1'
            $content | Should Match 'Start-ApplicationRun'
        }
    }

    It 'completes discovery for every package and lists absent/current/errors before the first upgrade' {
        $script:states['A.App'] = @{ Version = '1.0'; Available = '1.2' }
        $script:states['B.Current'] = @{ Version = '1.2'; Available = '' }
        $groups = @([pscustomobject]@{ Name = 'Standard'; Root = ''; Applications = @(
            [pscustomobject]@{ Name = 'App'; Id = 'A.App'; Locale = 'de'; CustomArguments = '/LANG=de' }
            [pscustomobject]@{ Name = 'Current'; Id = 'B.Current' }
            [pscustomobject]@{ Name = 'Absent'; Id = 'C.Absent' }
            [pscustomobject]@{ Name = 'Error'; Id = 'D.Error'; Version = 'invalid' }
        ) })
        $results = @(Invoke-ApplicationGroups -Groups $groups -Mode Update)
        $script:preview.Count | Should Be 4
        ($script:preview.Action -join ',') | Should Be 'Update,NoUpdate,NotInstalled,Error'
        $firstUpgrade = [array]::IndexOf($script:events, 'upgrade|A.App')
        $firstUpgrade | Should BeGreaterThan ([array]::IndexOf($script:events, 'Preview'))
        ([array]::IndexOf($script:events, 'Preview')) | Should BeGreaterThan ([array]::IndexOf($script:events, 'show|C.Absent'))
        @($script:commands | Where-Object { $_[0] -eq 'install' }).Count | Should Be 0
        @($script:commands | Where-Object { $_[0] -eq 'upgrade' }).Count | Should Be 1
        ($results.Status -join ',') | Should Be 'Succeeded,NoUpdate,NotInstalled,Failed'
        $upgrade = $script:commands | Where-Object { $_[0] -eq 'upgrade' }
        ($upgrade -join '|') | Should Match '--locale\|de'
        ($upgrade -join '|') | Should Match '--custom\|/LANG=de'
    }

    It 'refuses missing drives and invalid roots without creating them' {
        $missingDrive = @('Z', 'Y', 'X', 'W') | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
        $app = [pscustomobject]@{ Name = 'Tool'; Id = 'A.Tool'; Directory = 'Tool'; Executable = 'tool.exe' }
        foreach ($root in @("$($missingDrive):\Tools", 'relative', "$TestDrive\..\Escape", "$TestDrive\bad:stream")) {
            $plan = Install-Application -Application $app -Root $root -CheckOnly
            $plan.Status | Should Be 'Failed'
        }
        $script:commands.Count | Should Be 0
    }

    It 'does not confuse native list failures, unknown versions or broken output with absence' {
        $app = [pscustomobject]@{ Name = 'App'; Id = 'A.App' }
        $script:listCode = 42
        (Get-ApplicationPlan -Application $app -Mode Update).Status | Should Be 'Failed'
        $script:listCode = 0
        foreach ($output in @('Unexpected output', "Name Id Version`n-----`nApplication A.App Unknown winget",
            "Application A.App 1.2 winget")) {
            $script:listText = @($output -split "`n")
            (Get-ApplicationPlan -Application $app -Mode Update).Status | Should Be 'Failed'
        }
        $script:listText = $null
        (Get-ApplicationPlan -Application $app -Mode Update).Action | Should Be 'NotInstalled'
        @($script:commands | Where-Object { $_[0] -in @('upgrade', 'install') }).Count | Should Be 0
    }

    It 'fails closed when manifest queries fail or cannot identify the selected installer' {
        $app = [pscustomobject]@{ Name = 'App'; Id = 'A.App'; InstallerType = 'inno' }
        $script:showCode = 123
        (Install-Application -Application $app -CheckOnly).Status | Should Be 'Failed'
        $script:showCode = 0
        foreach ($text in @('Version: 1.2', "Found [A.App]`nVersion: 1.2`n  Installer Type: wix")) {
            $script:showText = @($text -split "`n")
            (Install-Application -Application $app -CheckOnly).Status | Should Be 'Failed'
        }
    }

    It 'reads native exact-source tables with omitted Source or Available columns' {
        $script:listText = @('Name ID Version', '----------------',
            'KeePass Password Safe 2.61.1 DominikReichl.KeePass 2.61.1')
        $state = Get-InstalledApplicationState -Id 'DominikReichl.KeePass'
        $state.IsInstalled | Should Be $true
        $state.Version | Should Be '2.61.1'
        $state.AvailableVersion | Should Be ''
        $script:listText = @('Name ID Version Available', '----------------',
            'KeePass Password Safe 2.60 DominikReichl.KeePass 2.60 2.61.1')
        (Get-InstalledApplicationState -Id 'DominikReichl.KeePass').AvailableVersion | Should Be '2.61.1'
    }

    It 'handles the Raspberry Pi Imager v-prefix without weakening constrained version parsing' {
        $script:listText = @('Name ID Version', '----------------',
            'Raspberry Pi Imager RaspberryPiFoundation.RaspberryPiImager v2.0.8')
        (Get-InstalledApplicationState -Id 'RaspberryPiFoundation.RaspberryPiImager').Version | Should Be 'v2.0.8'
        (Test-ApplicationVersionEqual -Left 'v2.0.8' -Right '2.0.8.0') | Should Be $true
        (Test-ApplicationVersionEqual -Left 'v2.0.8' -Right '2.0.9') | Should Be $false
        $caught = $null
        try { $null = ConvertTo-UpdateVersion -Value 'v5.0.4' }
        catch { $caught = $_ }
        ($null -ne $caught) | Should Be $true
    }

    It 'checks existing executables only when installed and refuses mismatched update locations' {
        $app = [pscustomobject]@{ Name = 'Tool'; Id = 'A.Tool'; Directory = 'Tool'; Executable = 'tool.exe' }
        $absent = Install-Application -Application $app -Root $TestDrive -CheckOnly
        $absent.Status | Should Be 'CheckOnly'
        $absent.Message | Should Match 'keine Installation'
        $script:states['A.Tool'] = @{ Version = '1.0'; Available = '1.2' }
        $mismatch = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
        $mismatch.Status | Should Be 'Failed'
        $mismatch.Phase | Should Be 'VerifyExecutable'
        (Test-Path (Join-Path $TestDrive 'Tool')) | Should Be $false
    }

    It 'skips absent update packages before checking unused targets or user profiles' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'TheDocumentFoundation.LibreOffice'
        $blockedRoot = Join-Path $TestDrive 'not-a-directory'
        $null = New-Item -ItemType File -Path $blockedRoot
        $script:userConfigPresent = $true
        $script:runningProcess = 'soffice.bin'
        $plan = Get-ApplicationPlan -Application $app -Root $blockedRoot -Mode Update
        $plan.Action | Should Be 'NotInstalled'
        (Invoke-ApplicationChange -Plan $plan).Status | Should Be 'NotInstalled'
        @($script:commands | Where-Object { $_[0] -ne 'list' }).Count | Should Be 0
    }

    It 'rechecks the installation state after preview rather than applying a stale plan' {
        $script:states['A.App'] = @{ Version = '1.0'; Available = '1.2' }
        $script:changeBeforeExecute = $true
        $groups = @([pscustomobject]@{ Name = 'Standard'; Root = ''; Applications = @(
            [pscustomobject]@{ Name = 'App'; Id = 'A.App' }
        ) })
        $result = @(Invoke-ApplicationGroups -Groups $groups -Mode Update)[0]
        $result.Status | Should Be 'Failed'
        $result.Phase | Should Be 'Revalidate'
        @($script:commands | Where-Object { $_[0] -eq 'upgrade' }).Count | Should Be 0
    }

    It 'continues to subsequent installed packages after a native upgrade failure' {
        $script:states['A.App'] = @{ Version = '1.0'; Available = '1.2' }
        $script:states['B.App'] = @{ Version = '1.0'; Available = '1.2' }
        $script:mutationCode = 42
        $groups = @([pscustomobject]@{ Name = 'Standard'; Root = ''; Applications = @(
            [pscustomobject]@{ Name = 'First'; Id = 'A.App' }
            [pscustomobject]@{ Name = 'Second'; Id = 'B.App' }
        ) })
        $results = @(Invoke-ApplicationGroups -Groups $groups -Mode Update)
        @($script:commands | Where-Object { $_[0] -eq 'upgrade' }).Count | Should Be 2
        ($results.Status -join ',') | Should Be 'Failed,Failed'
        ($results.ExitCode -join ',') | Should Be '42,42'
    }

    It 'preserves an existing local INI when an updater overwrites it' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'Rufus.Rufus'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Rufus')
        $null = New-Item -ItemType File -Path (Join-Path $dir.FullName 'rufus.exe')
        $script:overwritePath = Join-Path $dir.FullName 'rufus.ini'
        [IO.File]::WriteAllText($script:overwritePath, 'existing preferences')
        $script:states[$app.Id] = @{ Version = '1.0'; Available = '1.2' }
        $plan = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
        (Invoke-ApplicationChange -Plan $plan).Status | Should Be 'Succeeded'
        [IO.File]::ReadAllText($script:overwritePath) | Should Be 'existing preferences'
        @(Get-ChildItem $dir.FullName -Filter '*.bak').Count | Should Be 1
    }

    It 'preserves both KeePassXC configuration files during upgrades' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'KeePassXCTeam.KeePassXC'
        $config = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'KeepassXC\config') -Force
        $null = New-Item -ItemType File -Path (Join-Path $config.Parent.FullName 'KeePassXC.exe')
        $mainConfig = Join-Path $config.FullName 'keepassxc.ini'
        [IO.File]::WriteAllText($mainConfig, 'main preferences')
        $script:overwritePath = Join-Path $config.FullName 'keepassxc_local.ini'
        [IO.File]::WriteAllText($script:overwritePath, 'local preferences')
        $script:states[$app.Id] = @{ Version = '1.0'; Available = '1.2' }
        $plan = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
        (Invoke-ApplicationChange -Plan $plan).Status | Should Be 'Succeeded'
        [IO.File]::ReadAllText($mainConfig) | Should Be 'main preferences'
        [IO.File]::ReadAllText($script:overwritePath) | Should Be 'local preferences'
        @(Get-ChildItem $config.FullName -Filter '*.bak').Count | Should Be 2
    }

    It 'filters exact IDs and keeps disabled and unknown selections explicit in update preview' {
        $groups = @([pscustomobject]@{ Name = 'Standard'; Root = ''; Applications = @(
            [pscustomobject]@{ Name = 'Disabled'; Id = 'A.App'; Enabled = $false }
            [pscustomobject]@{ Name = 'Other'; Id = 'A.App.More' }
        ) })
        $results = @(Invoke-ApplicationGroups -Groups $groups -Mode Update -CheckOnly -SelectedId 'A.App', 'Missing')
        $results.Count | Should Be 2
        ($results.Status -join ',') | Should Be 'Skipped,Failed'
        $script:commands.Count | Should Be 0
    }

    It 'restores LibreOffice on failure and retains new product metadata on success' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'TheDocumentFoundation.LibreOffice'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'LibreOffice\program') -Force
        $null = New-Item -ItemType File -Path (Join-Path $dir.FullName 'soffice.exe')
        $script:overwritePath = Join-Path $dir.FullName 'bootstrap.ini'
        $original = "[Bootstrap]`r`nUserInstallation=`$ORIGIN/../profile`r`nProductKey=Preserved`r`n[Other]`r`nCustom=retained`r`n"
        $script:overwriteContent = "[Bootstrap]`r`nUserInstallation=`$SYSUSERCONFIG/LibreOffice/4`r`nProductKey=NewVersion`r`n[Other]`r`nInstallerSetting=new`r`n"
        [IO.File]::WriteAllText($script:overwritePath, $original)
        foreach ($code in @(42, 0)) {
            $script:mutationCode = $code
            $script:states[$app.Id] = @{ Version = '1.0'; Available = '1.2' }
            $plan = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
            $plan.Status | Should Be 'Planned'
            $result = Invoke-ApplicationChange -Plan $plan
            $result.Status | Should Be $(if ($code) { 'Failed' } else { 'Succeeded' })
            $expected = if ($code) { $original } else {
                $script:overwriteContent.Replace('$SYSUSERCONFIG/LibreOffice/4', '$ORIGIN/../profile')
            }
            [IO.File]::ReadAllText($script:overwritePath) | Should Be $expected
        }
        @(Get-ChildItem $dir.FullName -Filter '*.bak').Count | Should Be 3
        $upgrade = @($script:commands | Where-Object { $_[0] -eq 'upgrade' })[0]
        ($upgrade -join '|') | Should Match '--custom\|UI_LANGS=de'
        ($upgrade -join '|') | Should Match '--installer-type\|msi'
        ($upgrade -join '|') | Should Match '--scope\|machine'
    }

    It 'blocks custom or running LibreOffice profiles before installer or backup creation' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'TheDocumentFoundation.LibreOffice'
        $app.Directory = 'BlockedLibreOffice'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'BlockedLibreOffice\program') -Force
        $null = New-Item -ItemType File -Path (Join-Path $dir.FullName 'soffice.exe')
        $bootstrap = Join-Path $dir.FullName 'bootstrap.ini'
        [IO.File]::WriteAllText($bootstrap, "[Bootstrap]`r`nUserInstallation=file:///custom`r`n")
        $script:states[$app.Id] = @{ Version = '1.0'; Available = '1.2' }
        (Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update).Status | Should Be 'Failed'
        [IO.File]::WriteAllText($bootstrap, "[Bootstrap]`r`nUserInstallation=`$ORIGIN/../profile`r`n")
        $script:runningProcess = 'soffice.bin'
        (Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update).Status | Should Be 'Failed'
        $script:runningProcess = ''
        $script:userConfigPresent = $true
        [IO.File]::WriteAllText($bootstrap, "[Bootstrap]`r`nUserInstallation=`$SYSUSERCONFIG/LibreOffice/4`r`n")
        (Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update).Status | Should Be 'Failed'
        @(Get-ChildItem $dir.FullName -Filter '*.bak').Count | Should Be 0
        @($script:commands | Where-Object { $_[0] -eq 'upgrade' }).Count | Should Be 0
    }

    It 'reads KeePass settings without backups then restores them even after a failing Inno upgrade' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'DominikReichl.KeePass'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'KeePass')
        $null = New-Item -ItemType File -Path (Join-Path $dir.FullName 'KeePass.exe')
        $script:overwritePath = Join-Path $dir.FullName 'KeePass.config.xml'
        $original = '<Configuration><Meta><PreferUserConfiguration>false</PreferUserConfiguration></Meta><Application><LanguageFile>German.lngx</LanguageFile></Application><UI><TrayIcon>true</TrayIcon></UI></Configuration>'
        [IO.File]::WriteAllText($script:overwritePath, $original)
        foreach ($code in @(42, 0)) {
            $script:states[$app.Id] = @{ Version = '2.60'; Available = '2.61.1' }
            $script:mutationCode = $code
            $before = @(Get-ChildItem $dir.FullName -Filter '*.bak').Count
            $plan = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
            if ($plan.Status -eq 'Failed') { throw "$($plan.Phase): $($plan.Message)" }
            $plan.Status | Should Be 'Planned'
            @(Get-ChildItem $dir.FullName -Filter '*.bak').Count | Should Be $before
            $result = Invoke-ApplicationChange -Plan $plan
            $result.Status | Should Be $(if ($code) { 'Failed' } else { 'Succeeded' })
            [IO.File]::ReadAllText($script:overwritePath) | Should Be $original
        }
        Assert-MockCalled Install-KeePassGermanLanguage -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
        $upgrade = @($script:commands | Where-Object { $_[0] -eq 'upgrade' })[0]
        ($upgrade -join '|') | Should Match '--version\|2\.61\.1'
        ($upgrade -join '|') | Should Match '--installer-type\|inno'
    }

    It 'refuses KeePass running/enforced/user/conflicting settings in read-only mode without backups' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'DominikReichl.KeePass'
        $app.Directory = 'ConflictingKeePass'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'ConflictingKeePass')
        $script:runningProcess = 'KeePass'
        (Install-Application -Application $app -Root $TestDrive -CheckOnly).Status | Should Be 'Failed'
        $script:runningProcess = ''
        $script:userConfigPresent = $true
        (Install-Application -Application $app -Root $TestDrive -CheckOnly).Status | Should Be 'Failed'
        $script:userConfigPresent = $false
        $enforced = Join-Path $dir.FullName 'KeePass.config.enforced.xml'
        [IO.File]::WriteAllText($enforced, '<Configuration/>')
        (Install-Application -Application $app -Root $TestDrive -CheckOnly).Status | Should Be 'Failed'
        Remove-Item -LiteralPath $enforced
        [IO.File]::WriteAllText((Join-Path $dir.FullName 'KeePass.config.xml'), '<Configuration/>')
        (Install-Application -Application $app -Root $TestDrive -CheckOnly).Status | Should Be 'Failed'
        @(Get-ChildItem $dir.FullName -Filter '*.bak').Count | Should Be 0
        @($script:commands | Where-Object { $_[0] -eq 'install' }).Count | Should Be 0
    }

    It 'refuses KeePass executables below a nested directory' {
        $app = Get-ApplicationGroups | ForEach-Object Applications | Where-Object Id -eq 'DominikReichl.KeePass'
        $app.Directory = 'NestedKeePass'
        $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'NestedKeePass\nested') -Force
        $null = New-Item -ItemType File -Path (Join-Path $dir.FullName 'KeePass.exe')
        $script:states[$app.Id] = @{ Version = '2.60'; Available = '2.61.1' }
        $plan = Get-ApplicationPlan -Application $app -Root $TestDrive -Mode Update
        $plan.Status | Should Be 'Failed'
        $plan.Phase | Should Be 'VerifyExecutable'
        $plan.Message | Should Match 'direkt unter'
        @($script:commands | Where-Object { $_[0] -eq 'upgrade' }).Count | Should Be 0
    }

    # Pester 3 keeps unfiltered mocks for the Describe lifetime; mutation traps go last.
    It 'runs both check-only entry modes without elevation or any application mutation' {
        Mock New-Item { throw 'Unexpected directory/file creation' }
        Mock Copy-Item { throw 'Unexpected backup' }
        Mock Initialize-Directory { throw 'Unexpected target creation' }
        Mock Initialize-LocalConfiguration { throw 'Unexpected configuration write' }
        $root = Join-Path $TestDrive 'Inspection'
        $script:InstalledToolsRoot = $root
        $script:PortableToolsRoot = $root
        $script:ApplicationId = $null
        $script:applicationGroups = @(Get-ApplicationGroups -InstalledToolsRoot $root -PortableToolsRoot $root)
        foreach ($mode in @('Install', 'Update')) {
            (Invoke-Installation -Mode $mode -CheckOnly) | Should Be 0
            $rows = @(Import-Csv (Join-Path $TestDrive 'preflight.csv'))
            $rows.Count | Should Be 36
            @($rows | Where-Object Status -ne 'CheckOnly').Count | Should Be 0
        }
        Assert-MockCalled Test-Administrator -Times 0 -Exactly -Scope It
        Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled Copy-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled Initialize-Directory -Times 0 -Exactly -Scope It
        Assert-MockCalled Initialize-LocalConfiguration -Times 0 -Exactly -Scope It
        Assert-MockCalled Install-KeePassGermanLanguage -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
        @($script:commands | Where-Object { $_[0] -notin @('show', 'list') }).Count | Should Be 0
        (Test-Path $root) | Should Be $false
    }
}
