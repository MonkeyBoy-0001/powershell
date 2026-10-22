#requires -Version 5.1

<#
.SYNOPSIS
Entfernt Symbolangaben mehrerer Ordner, optional rekursiv ohne Analysepunkte.
.DESCRIPTION
Gleiche Transaktion wie Clear Folder.ps1. Andere INI-Einstellungen bleiben
erhalten; vollständiges Löschen nur mit RemoveDesktopIni. Siehe README.md.
.LINK
README.md
.EXAMPLE
& '.\Clear Folders.ps1' -Path 'C:\Daten\A','C:\Daten\B' -Recurse -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Path,
    [switch]$Recurse,
    [switch]$ClearFolderReadOnly,
    [switch]$RemoveDesktopIni,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot '..\FileOps\Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Clear-Folders' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-FolderIcons $context $Path -Recurse:$Recurse -ClearFolderReadOnly:$ClearFolderReadOnly -RemoveDesktopIni:$RemoveDesktopIni
}
exit $code
