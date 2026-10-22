#requires -Version 5.1

<#
.SYNOPSIS
Pester-Regressionen fuer versionsbegrenzte Updates.
.DESCRIPTION
Mit Pester 3.4.0 ausfuehren, nicht direkt starten. Aufrufe und Isolation:
README.md neben dieser Testsuite.
.LINK
README.md
#>

$wingetDirectory = Split-Path $PSScriptRoot -Parent
$script:versionPolicyFile = Join-Path $wingetDirectory 'Application-VersionPolicies.psd1'
. (Join-Path $wingetDirectory 'Application-VersionPolicy.ps1')
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $wingetDirectory 'Application-Management.ps1'), [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
. (Join-Path $wingetDirectory 'Application-Management.ps1')

Describe 'Version-constrained updates' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $script:wingetNoUpdateExitCode = -1978335189
        $script:availableVersions = @('5.1.1', '5.0.4', '5.0.2', '4.0.10')
        $script:installedVersion = '5.0.2'
        $script:upgradeCalls = @()
        $script:messages = @()
        $script:showExitCode = 0
        $script:showOutput = $null
        $script:listOutput = $null
        $script:upgradeExitCode = 0
        $script:forcedPostVersion = ''
        $script:clip = [pscustomobject]@{
            Name = 'CLIP STUDIO PAINT'; Id = 'Celsys.ClipStudioPaint'
            VersionPolicy = 'Celsys.ClipStudioPaint'
        }
        Mock Write-Log { $script:messages += $Message }
        Mock Invoke-Winget {
            switch ($Arguments[0]) {
                'show' {
                    if ($Arguments -notcontains '--versions') {
                        $id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
                        $version = $Arguments[[array]::IndexOf($Arguments, '--version') + 1]
                        return [pscustomobject]@{
                            ExitCode = $script:showExitCode
                            Output = @("Found package [$id]", "Version: $version", '  Installer Type: exe')
                        }
                    }
                    return [pscustomobject]@{
                        ExitCode = $script:showExitCode
                        Output = if ($null -ne $script:showOutput) { $script:showOutput } else {
                            @('Found package', 'Version', '-------') + $script:availableVersions
                        }
                    }
                }
                'list' {
                    $id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
                    return [pscustomobject]@{
                        ExitCode = 0
                        Output = if ($null -ne $script:listOutput) { $script:listOutput } else { @(
                            'Name                 Id                      Version Available Source'
                            '---------------------------------------------------------------------'
                            "Package    $id   $script:installedVersion 5.1.1 winget"
                        ) }
                    }
                }
                'upgrade' {
                    $script:upgradeCalls += ,$Arguments
                    $index = [array]::IndexOf($Arguments, '--version')
                    if ($script:forcedPostVersion) {
                        $script:installedVersion = $script:forcedPostVersion
                    }
                    elseif ($index -ge 0 -and $script:upgradeExitCode -eq 0) {
                        $script:installedVersion = $Arguments[$index + 1]
                    }
                    return $script:upgradeExitCode
                }
                default { throw "Unexpected command: $($Arguments[0])" }
            }
        }
    }

    It 'selects the highest licensed version, never the latest unrestricted release' {
        (Update-Application -Application $script:clip) | Should Be $true
        $script:upgradeCalls.Count | Should Be 1
        ($script:upgradeCalls[0] -join '|') | Should Match '--version\|5\.0\.4'
        ($script:upgradeCalls[0] -contains '5.1.1') | Should Be $false
        ($script:upgradeCalls[0] -contains '--include-unknown') | Should Be $false
        ($script:upgradeCalls[0] -contains '--force') | Should Be $false
    }

    It 'sorts patch versions numerically and excludes prereleases and other minor versions' {
        $script:availableVersions = @('5.1.1', '5.0.9', '5.0.12-beta', '5.0.10', '5.0.100-rc', '5.10.0')
        (Update-Application -Application $script:clip) | Should Be $true
        ($script:upgradeCalls[0] -join '|') | Should Match '--version\|5\.0\.10'
    }

    It 'does not invoke upgrade if already current within the licensed series' {
        $script:installedVersion = '5.0.4'
        (Update-Application -Application $script:clip) | Should Be $true
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'allows upgrading an older major version into the licensed series' {
        $script:installedVersion = '4.0.10'
        (Update-Application -Application $script:clip) | Should Be $true
        ($script:upgradeCalls[0] -join '|') | Should Match '--version\|5\.0\.4'
    }

    It 'reports an installed unlicensed newer version without downgrading' {
        $script:installedVersion = '5.1.1'
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
        ($script:messages -join "`n") | Should Match 'Downgrade'
    }

    It 'never falls back to an unbounded upgrade when no allowed version exists' {
        $script:availableVersions = @('6.0.0', '5.1.1', '4.0.10')
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'stops the package when source lookup fails' {
        $script:showExitCode = 123
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'refuses malformed source output even if it contains a version-like line' {
        $script:showOutput = @('Unexpected output', '5.0.4')
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'rejects unexpected text inside a version table rather than guessing from a valid row' {
        $script:showOutput = @('Version', '-------', '5.0.4', 'unparseable data')
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'refuses unknown installed versions instead of using include-unknown' {
        $script:installedVersion = 'Unknown'
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'rejects ambiguous installed package rows' {
        $script:listOutput = @(
            'CLIP Celsys.ClipStudioPaint 5.0.2 winget'
            'CLIP Celsys.ClipStudioPaint 5.1.1 winget'
        )
        (Update-Application -Application $script:clip) | Should Be $false
        $script:upgradeCalls.Count | Should Be 0
    }

    It 'detects a wrong installed version after an apparently successful upgrade' {
        $script:forcedPostVersion = '5.1.1'
        (Update-Application -Application $script:clip) | Should Be $false
        ($script:messages -join "`n") | Should Match 'Versionspr.fung nach Update fehlgeschlagen'
    }

    It 'does not report no-update as success if the selected target was not reached' {
        $script:upgradeExitCode = -1978335189
        (Update-Application -Application $script:clip) | Should Be $false
    }

    It 'honors an exact version when no version series is configured' {
        $app = [pscustomobject]@{ Name = 'CLIP'; Id = 'Celsys.ClipStudioPaint'; Version = '5.0.4' }
        $script:availableVersions = @('5.1.1', '5.0.9', '5.0.4')
        (Update-Application -Application $app) | Should Be $true
        ($script:upgradeCalls[0] -join '|') | Should Match '--version\|5\.0\.4'
    }

    It 'rejects incompatible version and series before any winget command' {
        $app = [pscustomobject]@{
            Name = 'CLIP'; Id = 'Celsys.ClipStudioPaint'; Version = '5.1.1'; VersionPin = '5.0.*'
        }
        (Update-Application -Application $app) | Should Be $false
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'rejects wildcard patterns that could include unlicensed versions' {
        $app = [pscustomobject]@{ Name = 'CLIP'; Id = 'Celsys.ClipStudioPaint'; VersionPin = '5.*.*' }
        (Update-Application -Application $app) | Should Be $false
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'preserves unrestricted updates and existing language arguments for other packages' {
        $app = [pscustomobject]@{ Name = 'WinRAR'; Id = 'RARLab.WinRAR'; Locale = 'de' }
        (Update-Application -Application $app) | Should Be $true
        $script:upgradeCalls.Count | Should Be 1
        ($script:upgradeCalls[0] -contains '--include-unknown') | Should Be $false
        ($script:upgradeCalls[0] -contains '--version') | Should Be $true
        ($script:upgradeCalls[0] -join '|') | Should Match '--locale\|de'
    }

    It 'continues to the next application after a version-policy failure' {
        $script:availableVersions = @('5.1.1')
        $results = @(
            foreach ($app in @($script:clip, [pscustomobject]@{ Name = 'Other'; Id = 'Vendor.Other' })) {
                Update-Application -Application $app
            }
        )
        $results[0] | Should Be $false
        $results[1] | Should Be $true
        $script:upgradeCalls.Count | Should Be 1
    }

    It 'rejects a missing named policy without falling back to unrestricted updates' {
        $app = [pscustomobject]@{ Name = 'CLIP'; Id = 'Celsys.ClipStudioPaint'; VersionPolicy = 'Missing' }
        (Update-Application -Application $app) | Should Be $false
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }

    It 'rejects inline settings that conflict with a shared policy' {
        $app = [pscustomobject]@{
            Name = 'CLIP'; Id = 'Celsys.ClipStudioPaint'
            VersionPolicy = 'Celsys.ClipStudioPaint'; VersionPin = '5.1.*'
        }
        (Update-Application -Application $app) | Should Be $false
        Assert-MockCalled Invoke-Winget -Times 0 -Exactly -Scope It
    }
}

Describe 'Updater policy configuration' {
    It 'references the same licensed policy as the installer' {
        $catalogue = @(Get-ApplicationGroups | ForEach-Object Applications)
        $clip = $catalogue | Where-Object Id -eq 'Celsys.ClipStudioPaint'
        $clip.VersionPolicy | Should Be 'Celsys.ClipStudioPaint'
        $resolved = Resolve-ApplicationVersionPolicy -Application $clip -PolicyFile $script:versionPolicyFile
        $resolved.VersionPin | Should Be '5.0.*'
        ($null -eq $clip.PSObject.Properties['VersionPin']) | Should Be $true
    }
}
