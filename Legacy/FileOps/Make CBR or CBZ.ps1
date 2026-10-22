#requires -Version 5.1

<#
.SYNOPSIS
Nummeriert Comic-Bilder natürlich sortiert und erstellt geprüfte CBR/CBZ.
.DESCRIPTION
Direkte Unterordner von Root werden unabhängig verarbeitet. Ohne Cleanup werden
keine Begleitdateien gelöscht. XML/ComicInfo.xml bleiben erhalten. Archive werden
separat erstellt/geprüft und erst dann veröffentlicht. Siehe README.md.
.LINK
README.md
.EXAMPLE
& '.\Make CBR or CBZ.ps1' -Root 'D:\Meine Comics' -ArchiveType zip -WhatIf -NoPause
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)][string]$Root = (Get-Location).Path,
    [ValidateSet('rar','zip')][string]$ArchiveType = 'rar',
    [string]$RarExe = 'rar.exe',
    [switch]$Overwrite,
    [switch]$NoPause,
    [AllowEmptyCollection()][string[]]$ImageExtensions = @('jpg','jpeg','png','gif','bmp','tif','tiff','webp','avif'),
    [switch]$Cleanup,
    [AllowEmptyCollection()][string[]]$CleanupExtensions = @('csv','url','txt','nfo'),
    [AllowEmptyCollection()][string[]]$CleanupNamePatterns = @('thumbs.db','*banner*.jpg','hentairulesbanner.*'),
    [string[]]$PreserveNames = @('ComicInfo.xml','metadata.json','metadata.opf'),
    [AllowEmptyCollection()][string[]]$DirectoryNames = @(),
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot 'Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Make-CBR-or-CBZ' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-ComicProcessing $context $Root $ArchiveType $RarExe -Overwrite:$Overwrite -ImageExtensions $ImageExtensions -Cleanup:$Cleanup -CleanupExtensions $CleanupExtensions -CleanupNamePatterns $CleanupNamePatterns -PreserveNames $PreserveNames -DirectoryNames $DirectoryNames
}
# NoPause bleibt als kompatibler Parameter; automatische Abschluss-Pausen entfallen.
exit $code
