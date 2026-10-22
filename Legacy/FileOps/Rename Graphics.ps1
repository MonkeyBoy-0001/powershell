#requires -Version 5.1

<#
.SYNOPSIS
Vereinheitlicht Grafiknamen kollisionssicher mit persistentem Journal.
.DESCRIPTION
Unterstriche werden Leerzeichen, Wortanfänge groß, Verbindungswörter klein.
Numerische Suffixe werden NUR mit StripNumericSuffix entfernt. Siehe README.md.
.LINK
README.md
.EXAMPLE
& '.\Rename Graphics.ps1' -Path 'C:\Meine Bilder' -Recurse -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)][string]$Path,
    [switch]$Recurse,
    [bool]$ProcessWithoutBy = $true,
    [bool]$ForceCaseChange = $true,
    [AllowEmptyCollection()][string[]]$LowerWords = @('vs','x','feat','ft','und','oder','and','or','with'),
    [AllowEmptyCollection()][string[]]$Extensions = @('jpg','jpeg','png','gif','bmp','tif','tiff','webp','svg','ico','heic','heif','avif','raw','dng','cr2','nef','arw','raf','orf','rw2','pef','sr2'),
    [switch]$StripNumericSuffix,
    [string]$LogDirectory
)
if ($MyInvocation.InvocationName -eq '.') { return }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { . (Join-Path $PSScriptRoot 'Shell.Common.ps1') }
catch { Write-Error "Abhängigkeit Shell.Common.ps1 fehlt/ist nicht ladbar: $_" -ErrorAction Continue; exit 1 }
$code = Invoke-ShellEntry 'Rename-Graphics' $LogDirectory $PSCmdlet ([bool]$WhatIfPreference) {
    param($context)
    Invoke-GraphicsRename $context $Path -Recurse:$Recurse -ProcessWithoutBy $ProcessWithoutBy -ForceCaseChange $ForceCaseChange -LowerWords $LowerWords -Extensions $Extensions -StripNumericSuffix:$StripNumericSuffix
}
exit $code
