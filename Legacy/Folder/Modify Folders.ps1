#requires -Version 5.1

<#
.SYNOPSIS
Richtet Symbole mehrerer Ordner ein; optional rekursiv ohne Analysepunkte.
.DESCRIPTION
Identische Symbol-Transaktion wie Modify Folder.ps1. Jeder Zielordner braucht
eine benachbarte Datei <Ordnername>.ico. Vollständige Hilfe: README.md.
.LINK
README.md
.EXAMPLE
& '.\Modify Folders.ps1' -Path 'C:\Daten\A','C:\Daten\B' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Path,
    [switch]$Recurse,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot '..\FileOps\Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Modify-Folders' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-FolderIcons $context $Path -Recurse:$Recurse -Modify
}
exit $code
