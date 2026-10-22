#requires -Version 5.1

<#
.SYNOPSIS
Verwendet die benachbarte Datei <Ordnername>.ico als Ordnersymbol.
.DESCRIPTION
Sichert vorhandene Symbol-Dateien und Attribute dauerhaft vor der Änderung.
Andere INI-Einstellungen bleiben erhalten. Siehe README.md.
.LINK
README.md
.EXAMPLE
& '.\Modify Folder.ps1' -Path 'C:\Daten\Beispiel' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot '..\FileOps\Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Modify-Folder' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-FolderIcons $context @($Path) -Modify
}
exit $code
