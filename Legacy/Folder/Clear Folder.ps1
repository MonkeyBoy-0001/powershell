#requires -Version 5.1

<#
.SYNOPSIS
Entfernt Symbolangaben eines Ordners mit Sicherung und Rücksetzung.
.DESCRIPTION
Nur IconResource/IconFile/IconIndex in [.ShellClassInfo] werden entfernt.
desktop.ico wird nur bei passender Referenz gelöscht. Vollständige Hilfe:
README.md neben diesem Skript. -WhatIf schreibt weiterhin Protokolle.
.LINK
README.md
.EXAMPLE
& '.\Clear Folder.ps1' -Path 'C:\Daten\Beispiel' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)][string]$Path,
    [switch]$ClearFolderReadOnly,
    [switch]$RemoveDesktopIni,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot '..\FileOps\Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Clear-Folder' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-FolderIcons $context @($Path) -ClearFolderReadOnly:$ClearFolderReadOnly -RemoveDesktopIni:$RemoveDesktopIni
}
exit $code
