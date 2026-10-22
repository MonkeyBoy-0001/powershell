#requires -Version 5.1

<#
.SYNOPSIS
Prueft die portable VS-Code-Einrichtung mit isolierten Dateien und gemockter CLI.
.DESCRIPTION
Pester 3.4.0 verwenden. Keine echten Erweiterungsinstallationen.
.LINK
README.md
#>
$setupScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'Utilities\VSCode\Initialize-VSCodeWorkspaces.ps1'
. $setupScript -VSCodePath 'unused' -WorkspaceRoot 'unused'

Describe 'Portable VS Code workspace initialization' {
    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $code = Join-Path $base 'Apps\VS Code'
        $root = Join-Path $base 'Work spaces'
        $null = [IO.Directory]::CreateDirectory((Join-Path $code 'bin'))
        $null = [IO.Directory]::CreateDirectory((Join-Path $code 'resources\app'))
        foreach ($path in @('Code.exe','bin\code.cmd','resources\app\product.json')) {
            [IO.File]::WriteAllText((Join-Path $code $path), '{}')
        }
        $shell = (Get-Command pwsh.exe -CommandType Application | Select-Object -First 1).Source
        $script:installedExtensions = @()
        $script:cliArguments = @()
        $script:failedExtension = ''
        $script:omitExtension = ''
        $script:listFailure = $false
        $script:observedPortable = @()
        Mock Write-Host {}
        Mock Write-Warning {}
        Mock Invoke-VSCodeCli {
            param($Executable, $Arguments)
            $script:cliArguments += ,$Arguments
            $script:observedPortable += $env:VSCODE_PORTABLE
            if ($Arguments[0] -eq '--list-extensions') {
                if ($script:listFailure) { return [pscustomobject]@{ ExitCode = 9; Output = @('list failed') } }
                return [pscustomobject]@{ ExitCode = 0; Output = @($script:installedExtensions) }
            }
            if ($Arguments[0] -ne '--install-extension') { throw 'Unexpected CLI operation' }
            $id = $Arguments[1]
            if ($id -eq $script:failedExtension) { return [pscustomobject]@{ ExitCode = 7; Output = @('download failed') } }
            if ($id -ne $script:omitExtension) { $script:installedExtensions += $id }
            return [pscustomobject]@{ ExitCode = 0; Output = @('installed') }
        }
    }

    It 'generates valid JSON, complete relative workspaces and purpose-specific themes' {
        $result = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $result.ExitCode | Should Be 0
        foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File |
                Where-Object Extension -in '.json','.code-workspace','.code-snippets') {
            $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        $ps = Get-Content -LiteralPath (Join-Path $root 'PowerShell.code-workspace') -Raw | ConvertFrom-Json
        $web = Get-Content -LiteralPath (Join-Path $root 'Webdesign.code-workspace') -Raw | ConvertFrom-Json
        $ps.folders[0].path | Should Be 'PowerShell'
        $web.folders[0].path | Should Be 'Webdesign'
        $ps.settings.'workbench.colorTheme' | Should Be 'Default Dark Modern'
        $web.settings.'workbench.colorTheme' | Should Be 'Default Light Modern'
        $ps.settings.'powershell.codeFormatting.preset' | Should Be 'OTBS'
        $web.settings.'livePreview.hostIP' | Should Be '127.0.0.1'
        $web.settings.'livePreview.portNumber' | Should Be 3000
        foreach ($relative in @('PowerShell\Scripts','PowerShell\Modules','PowerShell\Tests',
                'PowerShell\Docs','PowerShell\Data','PowerShell\Logs','Webdesign\src\assets\images',
                'Webdesign\src\assets\fonts','Webdesign\Design','Webdesign\Docs','Webdesign\Tests','Webdesign\dist')) {
            (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Container) | Should Be $true
        }
        Assert-MockCalled Invoke-VSCodeCli -Times 0 -Exactly -Scope It
    }

    It 'uses real portable data locations and keeps trust protection enabled' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        (Test-Path -LiteralPath (Join-Path $code 'data\extensions')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $code 'data\tmp')) | Should Be $true
        $argv = Get-Content -LiteralPath (Join-Path $code 'data\argv.json') -Raw | ConvertFrom-Json
        $argv.locale | Should Be 'de'
        $settings = Get-Content -LiteralPath (Join-Path $code 'data\user-data\User\settings.json') -Raw | ConvertFrom-Json
        $settings.'security.workspace.trust.enabled' | Should Be $true
        $settings.'files.autoSave' | Should Be 'off'
        $settings.'terminal.integrated.profiles.windows'.'PowerShell 7'.path | Should Be $shell
        $settings.'powershell.powerShellAdditionalExePaths'.'PowerShell 7 (Setup)' | Should Be $shell
    }

    It 'keeps recommendation lists aligned with the automatic installation catalogue' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell
        $catalog = Get-VSCodeExtensionCatalog
        foreach ($kind in @('PowerShell','Webdesign')) {
            $folder = Get-Content -LiteralPath (Join-Path $root "$kind\.vscode\extensions.json") -Raw | ConvertFrom-Json
            $workspace = Get-Content -LiteralPath (Join-Path $root "$kind.code-workspace") -Raw | ConvertFrom-Json
            ($folder.recommendations -join ',') | Should Be ($catalog[$kind] -join ',')
            ($workspace.extensions.recommendations -join ',') | Should Be ($catalog[$kind] -join ',')
        }
        @($script:installedExtensions | Select-Object -Unique).Count | Should Be 12
        @($script:cliArguments | Where-Object { $_[0] -eq '--list-extensions' }).Count | Should Be 2
        foreach ($portable in $script:observedPortable) {
            $portable | Should Be ([IO.Path]::GetFullPath((Join-Path $code 'data')))
        }
    }

    It 'does not write files or invoke the CLI in WhatIf mode' {
        $result = Invoke-VSCodeWorkspaceSetup $code $root $shell -WhatIf
        $result.Status | Should Be 'Planned'
        (Test-Path -LiteralPath $root) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $code 'data')) | Should Be $false
        Assert-MockCalled Invoke-VSCodeCli -Times 0 -Exactly -Scope It
    }

    It 'preserves edited JSONC and starter files and reports preservation explicitly' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $settings = Join-Path $root 'PowerShell\.vscode\settings.json'
        $seed = Join-Path $root 'Webdesign\src\index.html'
        [IO.File]::WriteAllText($settings, "// my comments`n{ }")
        [IO.File]::WriteAllText($seed, '<p>my site</p>')
        $result = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $result.Status | Should Be 'PreservedExistingFiles'
        [IO.File]::ReadAllText($settings) | Should Be "// my comments`n{ }"
        [IO.File]::ReadAllText($seed) | Should Be '<p>my site</p>'
        @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.setup-backup-*').Count | Should Be 0
    }

    It 'backs up replaced configurations byte-for-byte but never overwrites source files' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $path = Join-Path $root 'PowerShell\.vscode\settings.json'
        $seed = Join-Path $root 'PowerShell\Scripts\Hello-Workspace.ps1'
        [IO.File]::WriteAllBytes($path, [byte[]]@(255,254,123,0,125,0))
        [IO.File]::WriteAllText($seed, "'user script'")
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall -OverwriteConfiguration
        $backup = @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter 'settings.json.setup-backup-*')
        $backup.Count | Should Be 1
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($backup[0].FullName)) | Should Be '//57AH0A'
        $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        [IO.File]::ReadAllText($seed) | Should Be "'user script'"
    }

    It 'does not replace unchanged files or reinstall existing extensions on a repeat run' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell
        $path = Join-Path $root 'Webdesign\.vscode\settings.json'
        $stamp = [IO.File]::GetLastWriteTimeUtc($path)
        $script:cliArguments = @()
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -OverwriteConfiguration
        [IO.File]::GetLastWriteTimeUtc($path) | Should Be $stamp
        @($script:cliArguments | Where-Object { $_[0] -eq '--install-extension' }).Count | Should Be 0
        @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.setup-backup-*').Count | Should Be 0
    }

    It 'reports installer failures, continues independent extensions and restores the environment' {
        $old = $env:VSCODE_PORTABLE
        try {
            $env:VSCODE_PORTABLE = 'previous portable value'
            $script:failedExtension = 'EditorConfig.EditorConfig'
            $result = Invoke-VSCodeWorkspaceSetup $code $root $shell
            $result.ExitCode | Should Be 2
            $env:VSCODE_PORTABLE | Should Be 'previous portable value'
            @($script:installedExtensions).Count | Should Be 11
            $report = Get-Content -LiteralPath $result.Report -Raw | ConvertFrom-Json
            @($report | Where-Object Status -eq 'Failed').Count | Should BeGreaterThan 0
        }
        finally { $env:VSCODE_PORTABLE = $old }
    }

    It 'detects a missing extension even if the installation command returned zero' {
        $script:omitExtension = 'ms-vscode.PowerShell'
        $result = Invoke-VSCodeWorkspaceSetup $code $root $shell
        $result.ExitCode | Should Be 2
        (Get-Content -LiteralPath $result.Report -Raw) | Should Match 'Abschlusspruefung'
    }

    It 'does not install extensions when listing fails' {
        $script:listFailure = $true
        $result = Invoke-VSCodeWorkspaceSetup $code $root $shell
        $result.ExitCode | Should Be 2
        @($script:cliArguments | Where-Object { $_[0] -eq '--install-extension' }).Count | Should Be 0
    }

    It 'rejects installer distributions before making any portable state' {
        [IO.File]::WriteAllText((Join-Path $code 'unins000.exe'), '')
        { Invoke-VSCodeWorkspaceSetup $code $root $shell } | Should Throw 'ZIP'
        (Test-Path -LiteralPath $root) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $code 'data')) | Should Be $false
    }

    It 'rejects incomplete VS Code, missing PowerShell and overlapping roots' {
        { Invoke-VSCodeWorkspaceSetup $code $root (Join-Path $base 'pwsh.exe') } | Should Throw 'pwsh.exe'
        { Invoke-VSCodeWorkspaceSetup $code (Join-Path $code 'work') $shell } | Should Throw 'getrennte'
        { Invoke-VSCodeWorkspaceSetup $code $base $shell } | Should Throw 'getrennte'
        [IO.File]::Delete((Join-Path $code 'bin\code.cmd'))
        { Invoke-VSCodeWorkspaceSetup $code $root $shell } | Should Throw 'unvollstaendig'
        (Test-Path -LiteralPath $root) | Should Be $false
    }

    It 'rejects conflicting file and directory shapes before writing any target files' {
        $null = [IO.Directory]::CreateDirectory((Join-Path $root 'PowerShell\.vscode\settings.json'))
        { Invoke-VSCodeWorkspaceSetup $code $root $shell } | Should Throw 'Ordner'
        (Test-Path -LiteralPath (Join-Path $code 'data')) | Should Be $false
    }

    It 'rejects invalid Windows destinations and file ancestors' {
        $blocked = Join-Path $base 'blocked'
        [IO.File]::WriteAllText($blocked, '')
        foreach ($path in @('relative','C:\', (Join-Path $base 'NUL'), (Join-Path $base 'trailing.'),
                (Join-Path $blocked 'child'), (Join-Path $base 'bad:stream'))) {
            $caught = $null
            try { $null = Get-VSCodeSafePath $path } catch { $caught = $_ }
            ($null -ne $caught) | Should Be $true
        }
    }

    It 'refuses redirected destination trees' {
        $target = Join-Path $base 'junction-target'
        $null = [IO.Directory]::CreateDirectory($target)
        $link = Join-Path $base 'junction'
        $null = New-Item -ItemType Junction -Path $link -Target $target
        try {
            { Invoke-VSCodeWorkspaceSetup $code (Join-Path $link 'work') $shell } | Should Throw 'Umgeleitete'
            (Test-Path -LiteralPath (Join-Path $code 'data')) | Should Be $false
        }
        finally { [IO.Directory]::Delete($link) }
    }

    It 'produces executable syntax tasks and a valid PowerShell starter script' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $folder = Join-Path $root 'PowerShell'
        $tasks = Get-Content -LiteralPath (Join-Path $folder '.vscode\tasks.json') -Raw | ConvertFrom-Json
        Push-Location $folder
        try {
            $marker = Join-Path $folder 'must-not-run.txt'
            [IO.File]::WriteAllText((Join-Path $folder 'Scripts\side-effect.ps1'),
                "[IO.File]::WriteAllText('$marker', 'executed')")
            $arguments = @($tasks.tasks[0].args)
            & $shell @arguments
            $LASTEXITCODE | Should Be 0
            (Test-Path -LiteralPath $marker) | Should Be $false
            [IO.File]::WriteAllText((Join-Path $folder 'Scripts\broken.ps1'), 'function {')
            $ErrorActionPreference = 'Continue'
            $diagnostic = @(& $shell @arguments 2>&1 | ForEach-Object { [string]$_ })
            $ErrorActionPreference = 'Stop'
            $LASTEXITCODE | Should Be 1
            ($diagnostic -join "`n") | Should Match 'broken.ps1:1:'
            ($diagnostic -join "`n") | Should Not Match 'WriteError'
        }
        finally { Pop-Location }
        $hello = Join-Path $folder 'Scripts\Hello-Workspace.ps1'
        (& $shell -NoProfile -File $hello -Name 'Test') | Should Be 'Hallo, Test!'
        $tasks.tasks[1].args[-1] | Should Match 'MinimumVersion 5'
    }

    It 'emits matching line endings encoding and escaped PowerShell snippet variables' {
        $files = @(Get-VSCodeSetupFiles $code $root $shell)
        foreach ($file in $files | Where-Object { $_.Path -notmatch '\.ps1$' }) {
            $file.Content.Contains("`r") | Should Be $false
        }
        $seed = $files | Where-Object { $_.Path -match '\\Scripts\\Hello-Workspace.ps1$' }
        $null = Write-VSCodeSetupFile $seed
        $bytes = [IO.File]::ReadAllBytes($seed.Path)
        ($bytes[0..2] -join ',') | Should Be '239,187,191'
        $seed.Content.Contains("`r`n") | Should Be $true
        $snippetFile = $files | Where-Object { $_.Path -match 'powershell.code-snippets$' }
        $snippet = $snippetFile.Content | ConvertFrom-Json
        $body = $snippet.'Skript mit ShouldProcess'.body -join "`n"
        $body.Contains('\$ErrorActionPreference') | Should Be $true
        $body = $body.Replace('\$', '$').Replace('${1:Aktion}', 'Aktion').Replace('$0', '')
        $tokens = $null; $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should Be 0
    }

    It 'keeps browser debug settings, server root and starter references consistent' {
        $null = Invoke-VSCodeWorkspaceSetup $code $root $shell -SkipExtensionInstall
        $web = Join-Path $root 'Webdesign'
        $launch = Get-Content -LiteralPath (Join-Path $web '.vscode\launch.json') -Raw | ConvertFrom-Json
        $launch.configurations[0].url | Should Be 'http://127.0.0.1:3000'
        $launch.configurations[0].webRoot | Should Be '${workspaceFolder}\src'
        $html = Get-Content -LiteralPath (Join-Path $web 'src\index.html') -Raw
        foreach ($match in [regex]::Matches($html, '(?:src|href)="([^"]+)"')) {
            (Test-Path -LiteralPath (Join-Path (Join-Path $web 'src') $match.Groups[1].Value)) | Should Be $true
        }
        $package = Get-Content -LiteralPath (Join-Path $web 'package.json') -Raw | ConvertFrom-Json
        $package.private | Should Be $true
        $package.scripts.'lint:js' | Should Be 'eslint src'
    }
}

Describe 'VS Code native command execution without installations' {
    It 'captures stdout stderr and a nonzero exit without treating stderr alone as failure' {
        foreach ($exitCode in @(0,7)) {
            $result = Invoke-VSCodeCli $env:ComSpec @('/d','/c',"echo output & echo diagnostic 1>&2 & exit /b $exitCode")
            $result.ExitCode | Should Be $exitCode
            ($result.Output -join "`n") | Should Match 'output'
            ($result.Output -join "`n") | Should Match 'diagnostic'
        }
    }
    It 'rejects a missing executable instead of using a stale successful exit code' {
        $global:LASTEXITCODE = 0
        $caught = $null
        try { $null = Invoke-VSCodeCli (Join-Path $TestDrive 'missing.exe') @('--list-extensions') }
        catch { $caught = $_ }
        ($null -ne $caught) | Should Be $true
        $caught.Exception.Message | Should Match 'Programm nicht gefunden'
    }
}
