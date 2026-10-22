#requires -Version 5.1

<#
.SYNOPSIS
Gemeinsame Hilfsfunktionen fuer Dateioperationen und Ordnersymbole.
.DESCRIPTION
Beim Dot-Sourcing werden nur Funktionen definiert. Bedienung, Abhaengigkeiten
und Wiederherstellung sind in README.md neben dieser Bibliothek dokumentiert.
.LINK
README.md
#>


function New-StringHashSet {
    param([AllowEmptyCollection()][string[]]$Values = @(), [switch]$NormalizeExtensions)
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $normalized = $value.Trim()
            if ($NormalizeExtensions) { $normalized = $normalized.TrimStart('.') }
            if ($normalized) { $null = $set.Add($normalized) }
        }
    }
    return ,$set
}

function Initialize-ShellNative {
    if ('ShellSafety.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace ShellSafety {
    public static class Native {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint GetLongPathName(string path, StringBuilder buffer, uint size);
        [StructLayout(LayoutKind.Sequential)]
        public struct FileInfo {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
        public static uint LinkCount(string path) {
            using(var stream = new System.IO.FileStream(path, System.IO.FileMode.Open,
                System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite | System.IO.FileShare.Delete)) {
                FileInfo info;
                if(!GetFileInformationByHandle(stream.SafeFileHandle, out info))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                return info.Links;
            }
        }
        [DllImport("shell32.dll")]
        static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);
        public static string KnownFolder(string id) {
            IntPtr p;
            int hr = SHGetKnownFolderPath(new Guid(id), 0, IntPtr.Zero, out p);
            if (hr != 0) Marshal.ThrowExceptionForHR(hr);
            try { return Marshal.PtrToStringUni(p); } finally { Marshal.FreeCoTaskMem(p); }
        }
    }
    public sealed class NaturalComparer : System.Collections.Generic.IComparer<string> {
        public int Compare(string a, string b) {
            int i=0, j=0;
            while(i<a.Length && j<b.Length) {
                if(a[i]>='0' && a[i]<='9' && b[j]>='0' && b[j]<='9') {
                    int ai=i, bj=j;
                    while(i<a.Length && a[i]>='0' && a[i]<='9') i++;
                    while(j<b.Length && b[j]>='0' && b[j]<='9') j++;
                    string x=a.Substring(ai,i-ai).TrimStart('0'), y=b.Substring(bj,j-bj).TrimStart('0');
                    int c=x.Length.CompareTo(y.Length);
                    if(c!=0) return c;
                    c=StringComparer.Ordinal.Compare(x,y);
                    if(c!=0) return c;
                } else {
                    int c=char.ToUpperInvariant(a[i]).CompareTo(char.ToUpperInvariant(b[j]));
                    if(c!=0) return c;
                    i++; j++;
                }
            }
            int end=(a.Length-i).CompareTo(b.Length-j);
            return end!=0 ? end : StringComparer.Ordinal.Compare(a,b);
        }
    }
}
'@ -ErrorAction Stop
}

function Get-SafePath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory, [switch]$MustExist)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Ein Pfad ist leer.' }
    $provider = $null; $drive = $null
    $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw "Nur Dateisystempfade sind zulässig: $Path" }
    $full = [IO.Path]::GetFullPath($providerPath)
    if ($full -match '^[\\]{2}[?.]\\' -or $full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')) {
        throw "Gerätepfade und Datenströme sind nicht zulässig: $Path"
    }
    $probe = $full
    $missing = [Collections.Generic.List[string]]::new()
    while (-not [IO.Directory]::Exists($probe) -and -not [IO.File]::Exists($probe)) {
        # Get-Item also detects some dangling reparse points that Exists does not report.
        $item = Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) { throw "Nicht regulärer Pfad: $probe" }
        $missing.Add([IO.Path]::GetFileName($probe))
        $parent = [IO.Path]::GetDirectoryName($probe)
        if (-not $parent -or $parent -eq $probe) { throw "Kein erreichbarer Pfad: $Path" }
        $probe = $parent
    }
    if ($MustExist -and $missing.Count) { throw "Pfad fehlt: $Path" }
    $ancestor = $probe
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Umgeleiteter Pfad/Analysepunkt nicht erlaubt: $ancestor" }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor.TrimEnd('\'))
    }
    Initialize-ShellNative
    $buffer = [Text.StringBuilder]::new(32768)
    $size = [ShellSafety.Native]::GetLongPathName($probe, $buffer, $buffer.Capacity)
    if ($size -eq 0 -or $size -ge $buffer.Capacity) { throw "Langpfad konnte nicht sicher aufgelöst werden: $probe" }
    $canonical = $buffer.ToString()
    for ($i = $missing.Count - 1; $i -ge 0; $i--) { $canonical = [IO.Path]::Combine($canonical, $missing[$i]) }
    if ([IO.File]::Exists($canonical) -and [ShellSafety.Native]::LinkCount($canonical) -gt 1) {
        throw "Datei mit mehreren Hardlinks wird nicht verändert/verarbeitet: $canonical"
    }
    if ($Directory -and [IO.File]::Exists($canonical)) { throw "Kein Ordner: $Path" }
    if ($Directory -and $MustExist -and -not [IO.Directory]::Exists($canonical)) { throw "Ordner fehlt: $Path" }
    if ($canonical.Length -gt [IO.Path]::GetPathRoot($canonical).Length) { $canonical = $canonical.TrimEnd('\') }
    return $canonical
}

function Test-PathOverlap {
    param([string]$First, [string]$Second)
    $a = (Get-SafePath $First).TrimEnd('\')
    $b = (Get-SafePath $Second).TrimEnd('\')
    return $a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or
        $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $b.StartsWith($a + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SeparatePaths {
    param([string]$Source, [string]$Destination)
    if (Test-PathOverlap $Source $Destination) { throw "Quelle und Ziel überlappen: '$Source' / '$Destination'." }
}

function New-ShellContext {
    param([string]$Name, [string]$LogDirectory, $Cmdlet, [bool]$DryRun = $false)
    $ctx = [pscustomobject]@{
        Name = $Name; RunId = ('{0}-{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID, [guid]::NewGuid().ToString('N'))
        LogDirectory = $null; LogFile = $null; LogFailed = $false; FallbackUsed = $false
        Cmdlet = $Cmdlet; DryRun = $DryRun
        Results = [Collections.Generic.List[object]]::new()
    }
    if (-not $LogDirectory) { $LogDirectory = Join-Path $PSScriptRoot 'Logs' }
    try {
        $ctx.LogDirectory = Get-SafePath $LogDirectory -Directory
        $null = [IO.Directory]::CreateDirectory($ctx.LogDirectory)
        $ctx.LogFile = Join-Path $ctx.LogDirectory "$Name-$($ctx.RunId).log"
        [IO.File]::WriteAllText($ctx.LogFile, '', [Text.Encoding]::UTF8)
    }
    catch {
        $ctx.LogFailed = $true
        Write-Warning "Protokollverzeichnis nicht verfügbar: $LogDirectory; $($_.Exception.Message)"
        Set-ShellFallbackLog $ctx
    }
    Write-ShellLog $ctx "Start; WhatIf=$DryRun; Log=$($ctx.LogFile)"
    return $ctx
}

function Set-ShellFallbackLog {
    param($Context)
    if ($Context.FallbackUsed) { $Context.LogFile = $null; return }
    $Context.FallbackUsed = $true
    try {
        $fallback = Get-SafePath (Join-Path (Get-ShellTempDirectory) 'PowerShell-Shell-Logs') -Directory
        $null = [IO.Directory]::CreateDirectory($fallback)
        $Context.LogDirectory = $fallback
        $Context.LogFile = Join-Path $fallback "$($Context.Name)-$($Context.RunId).log"
        [IO.File]::AppendAllText($Context.LogFile, "Fallback-Protokoll`r`n", [Text.Encoding]::UTF8)
        Write-Warning "Ersatzprotokoll: $($Context.LogFile)"
    }

    catch {
        $Context.LogDirectory = $null; $Context.LogFile = $null
        Write-Warning "Auch Ersatzprotokoll fehlgeschlagen; nur Konsole: $($_.Exception.Message)"
    }
}

function Get-ShellTempDirectory {
    return [IO.Path]::GetTempPath()
}

function Write-ShellLog {
    param($Context, [string]$Message, [string]$Level = 'INFO', $ErrorRecord, [string]$Phase, [string]$Path)
    $entry = '{0:O} [{1}] [{2}] [{3}] {4}' -f (Get-Date), $Level, $Phase, $Path, $Message
    if ($null -ne $ErrorRecord) {
        $entry += "`r`n" + ($ErrorRecord | Format-List * -Force | Out-String) +
            "`r`nStack: " + $ErrorRecord.ScriptStackTrace + "`r`nException: " + $ErrorRecord.Exception.ToString()
    }
    Write-Host $entry
    if (-not $Context.LogFile) { return }
    try { [IO.File]::AppendAllText($Context.LogFile, $entry + "`r`n", [Text.Encoding]::UTF8) }
    catch {
        $Context.LogFailed = $true
        Write-Warning "Protokollschreiben fehlgeschlagen: $($_.Exception.Message)"
        Set-ShellFallbackLog $Context
        if ($Context.LogFile) {
            try { [IO.File]::AppendAllText($Context.LogFile, $entry + "`r`n", [Text.Encoding]::UTF8) }
            catch { $Context.LogFile = $null; Write-Warning 'Ersatzprotokoll nicht beschreibbar; nur Konsole.' }
        }
    }
}

function Add-ShellResult {
    param($Context, [string]$Path, [ValidateSet('Success','Failed','Skipped','Planned')][string]$Status,
        [string]$Phase, [string]$Message, $ErrorRecord)
    $Context.Results.Add([pscustomobject]@{ Time = (Get-Date).ToString('O'); Path = $Path; Phase = $Phase; Status = $Status; Message = $Message })
    $level = if ($Status -eq 'Failed') { 'ERROR' } elseif ($Status -eq 'Skipped') { 'WARN' } else { 'INFO' }
    Write-ShellLog $Context "$Status : $Message" $level -ErrorRecord $ErrorRecord -Phase $Phase -Path $Path
}

function Confirm-ShellOperation {
    param($Context, [string]$Path, [string]$Action)
    if ($Context.Cmdlet.ShouldProcess($Path, $Action)) { return $true }
    $status = if ($Context.DryRun) { 'Planned' } else { 'Skipped' }
    Add-ShellResult $Context $Path $status $Action 'Nicht ausgeführt.'
    return $false
}

function Complete-ShellRun {
    param($Context, [int]$GlobalCode = 0)
    $counts = @($Context.Results | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '; '
    Write-ShellLog $Context "Zusammenfassung: $counts; Protokollfehler=$($Context.LogFailed)"
    if ($Context.LogDirectory) {
        try {
            $csv = @($Context.Results | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
            [IO.File]::WriteAllText((Join-Path $Context.LogDirectory "$($Context.Name)-$($Context.RunId).csv"), $csv, [Text.Encoding]::UTF8)
        }
        catch { $Context.LogFailed = $true; Write-ShellLog $Context 'Ergebnis-CSV fehlgeschlagen.' 'ERROR' -ErrorRecord $_ }
    }
    if ($GlobalCode) { return $GlobalCode }
    if ($Context.LogFailed -or @($Context.Results | Where-Object Status -eq 'Failed').Count) { return 2 }
    return 0
}

function Invoke-ShellEntry {
    param([string]$Name, [string]$LogDirectory, $Cmdlet, [bool]$DryRun, [scriptblock]$Operation)
    $context = New-ShellContext $Name $LogDirectory $Cmdlet $DryRun
    $code = 0
    try { & $Operation $context }
    catch {
        $code = 1
        Add-ShellResult $context $Name Failed Voraussetzung 'Grundlegende Voraussetzung/Aktion fehlgeschlagen.' $_
    }
    return Complete-ShellRun $context $code
}

function Get-SafeTree {
    param([string]$Root, [switch]$Recurse, [switch]$RejectReparse, $Context)
    $rootPath = Get-SafePath $Root -Directory -MustExist
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($rootPath)
    while ($queue.Count) {
        $current = $queue.Dequeue()
        try {
            $null = Get-SafePath $current -Directory -MustExist
            $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
            foreach ($child in $children) {
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    if ($RejectReparse) { throw "Analysepunkt im Quellbaum: $($child.FullName)" }
                    if ($Context) { Add-ShellResult $Context $child.FullName Skipped Suche 'Analysepunkt ausgeschlossen (kein Abstieg).' }
                    continue
                }
                $child
                if ($Recurse -and $child.PSIsContainer) { $queue.Enqueue($child.FullName) }
            }
        }
        catch {
            if ($RejectReparse -or -not $Context) { throw }
            Add-ShellResult $Context $current Failed Suche 'Verzeichnis konnte nicht gelesen werden.' $_
        }
    }
}

function Invoke-ShellNative {
    param($Context, [string]$Executable, [string[]]$Arguments)
    $oldError = $ErrorActionPreference
    $nativePreference = Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $output = @()
    $code = $null
    $launchError = $null
    try {
        $ErrorActionPreference = 'Continue'
        if ($null -ne $nativePreference) { $PSNativeCommandUseErrorActionPreference = $false }
        $global:LASTEXITCODE = $null
        $output = @(& $Executable @Arguments 2>&1)
        $code = $global:LASTEXITCODE
    }
    catch { $launchError = $_ }
    finally {
        $ErrorActionPreference = $oldError
        if ($null -ne $nativePreference) { $PSNativeCommandUseErrorActionPreference = $nativePreference.Value }
    }
    Write-ShellLog $Context ("Native: {0} {1}; Exitcode={2}`r`n{3}" -f $Executable, ($Arguments -join ' '), $code, ($output -join "`r`n")) -Phase Native -ErrorRecord $launchError
    if ($null -ne $launchError) { throw $launchError }
    if ($null -eq $code) { throw "Nativer Aufruf lieferte keinen Exitcode; Programmstart fehlgeschlagen: $Executable" }
    if ($code -ne 0) { throw "Nativer Aufruf fehlgeschlagen; Exitcode=$code; $Executable $($Arguments -join ' ')" }
}

function Resolve-RarExecutable {
    param([string]$Path)
    $command = Get-Command -Name $Path -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return $command.Source
}

function Get-StreamHash {
    param([IO.Stream]$Stream)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)) }
    finally { $sha.Dispose() }
}

function New-ZipStage {
    param([string]$Source, [string]$Stage)
    $Source = Get-SafePath $Source -Directory -MustExist
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $items = @(Get-SafeTree $Source -Recurse -RejectReparse)
    $hashes = @{}
    $zip = [IO.Compression.ZipFile]::Open($Stage, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in $items) {
            $name = $item.FullName.Substring($Source.TrimEnd('\').Length + 1).Replace('\','/')
            if ($item.PSIsContainer) { $null = $zip.CreateEntry($name + '/'); continue }
            $null = Get-SafePath $item.FullName -MustExist
            $input = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $hashes[$name] = Get-StreamHash $input
                $input.Position = 0
                $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $output = $entry.Open()
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            }
            finally { $input.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    return $hashes
}

function Test-ZipStage {
    param([string]$Stage, [hashtable]$Hashes)
    $zip = [IO.Compression.ZipFile]::OpenRead($Stage)
    try {
        $seen = New-StringHashSet
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            if (-not $Hashes.ContainsKey($entry.FullName) -or -not $seen.Add($entry.FullName)) { throw 'ZIP-Eintragsliste stimmt nicht überein.' }
            $stream = $entry.Open()
            try { $hash = Get-StreamHash $stream } finally { $stream.Dispose() }
            if ($hash -ne $Hashes[$entry.FullName]) { throw "ZIP-Inhalt beschädigt: $($entry.FullName)" }
        }
        if ($seen.Count -ne $Hashes.Count) { throw 'ZIP-Einträge fehlen.' }
    }
    finally { $zip.Dispose() }
}

function Publish-ShellFile {
    param([string]$Stage, [string]$Destination, [switch]$Overwrite, $Context)
    $null = Get-SafePath $Stage -MustExist
    $null = Get-SafePath $Destination
    if ($Overwrite -and [IO.File]::Exists($Destination)) {
        $previous = "$Destination.previous-$([guid]::NewGuid().ToString('N'))"
        # File.Replace ist atomar auf unterstützten Dateisystemen. Kein Delete+Move-Fallback.
        [IO.File]::Replace($Stage, $Destination, $previous)
        if ($Context) { Write-ShellLog $Context "Vorherige Datei bleibt zur Wiederherstellung: $previous" -Phase Publizieren }
    }
    else {
        # File.Move ohne overwrite schützt auch vor einem nach der Planung entstandenen Ziel.
        [IO.File]::Move($Stage, $Destination)
    }
}

function Remove-OwnedStage {
    param([string]$Path, $Context)
    try {
        if ([IO.File]::Exists($Path)) {
            $null = Get-SafePath $Path -MustExist
            [IO.File]::Delete($Path)
        }
    }
    catch { Add-ShellResult $Context $Path Failed Bereinigung 'Eigene Arbeitsdatei konnte nicht entfernt werden.' $_ }
}

function New-SafeArchive {
    param($Context, [string]$Source, [string]$Destination, [ValidateSet('rar','zip')][string]$Type,
        [string]$RarExe, [switch]$Overwrite)
    $sourcePath = Get-SafePath $Source -Directory -MustExist
    $destinationPath = Get-SafePath $Destination
    Assert-SeparatePaths $sourcePath $destinationPath
    if ($Context.LogDirectory -and (Test-PathOverlap $sourcePath $Context.LogDirectory)) {
        throw 'Archivquelle überlappt das aktive Protokollverzeichnis.'
    }
    $items = @(Get-SafeTree $sourcePath -Recurse -RejectReparse)
    if (@($items | Where-Object { -not $_.PSIsContainer }).Count -eq 0) { throw "Quelle enthält keine regulären Dateien: $sourcePath" }
    if (-not (Confirm-ShellOperation $Context $destinationPath "Neues $Type-Archiv erstellen, prüfen und veröffentlichen")) { return $false }
    $parent = Get-SafePath ([IO.Path]::GetDirectoryName($destinationPath)) -Directory
    $null = [IO.Directory]::CreateDirectory($parent)
    $stage = Join-Path $parent ('.shell-stage-' + [guid]::NewGuid().ToString('N') + '.' + $Type)
    try {
        if ($Type -eq 'rar') {
            Invoke-ShellNative $Context $RarExe @('a','-r','-ep1','-y','--',$stage, ($sourcePath.TrimEnd('\') + '\*'))
            if (-not [IO.File]::Exists($stage)) { throw "RAR hat keine Arbeitsdatei erstellt: $stage" }
            Invoke-ShellNative $Context $RarExe @('t','-y','--',$stage)
        }
        else {
            $hashes = New-ZipStage $sourcePath $stage
            Test-ZipStage $stage $hashes
        }
        Publish-ShellFile $stage $destinationPath -Overwrite:$Overwrite -Context $Context
        Add-ShellResult $Context $destinationPath Success Archiv 'Neues Archiv erfolgreich geprüft und veröffentlicht.'
        return $true
    }
    finally { Remove-OwnedStage $stage $Context }
}

function Save-RenameJournal {
    param([string]$Path, [AllowEmptyCollection()]$Map)
    $csv = @($Map | Select-Object Original, Temporary, Final, Rollback, Current, State, Hash | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    $stage = "$Path.writing"
    [IO.File]::WriteAllText($stage, $csv, [Text.Encoding]::UTF8)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($stage, $Path, "$Path.previous") }
    else { [IO.File]::Move($stage, $Path) }
}

function Move-RenameEntry {
    param($Entry, [string]$Destination)
    $null = Get-SafePath $Entry.Current -MustExist
    $null = Get-SafePath $Destination
    [IO.File]::Move($Entry.Current, $Destination)
    $Entry.Current = $Destination
}

function Undo-SequentialRename {
    param($Context, [AllowEmptyCollection()]$Map, [string]$Journal)
    # Nur tatsächlich bewegte Einträge: niemals aus der Existenz eines Zielnamens schließen.
    foreach ($entry in $Map) {
        if ($entry.State -eq 'Original') { continue }
        try {
            Move-RenameEntry $entry $entry.Rollback
            $entry.State = 'Rollback'
        }
        catch { Add-ShellResult $Context $entry.Current Failed Rollback 'Freistellen zur Rücksetzung fehlgeschlagen.' $_ }
    }
    foreach ($entry in $Map) {
        if ($entry.State -eq 'Original') { continue }
        try {
            Move-RenameEntry $entry $entry.Original
            $entry.State = 'Original'
        }
        catch { Add-ShellResult $Context $entry.Current Failed Rollback "Wiederherstellung nach '$($entry.Original)' fehlgeschlagen; Journal: $Journal" $_ }
    }
    try { Save-RenameJournal $Journal $Map }
    catch { Add-ShellResult $Context $Journal Failed Journal 'Rollback-Status konnte nicht gespeichert werden.' $_ }
}

function Invoke-RenameTransaction {
    param($Context, [AllowEmptyCollection()]$Pairs, [string]$Label)
    if (@($Pairs).Count -eq 0) { return $true }
    $map = [Collections.Generic.List[object]]::new()
    $originals = New-StringHashSet @($Pairs | ForEach-Object { Get-SafePath $_.Original -MustExist })
    $finals = New-StringHashSet
    foreach ($pair in $Pairs) {
        $original = Get-SafePath $pair.Original -MustExist
        $null = Get-SafePath $pair.Final
        $final = Join-Path (Get-SafePath ([IO.Path]::GetDirectoryName($pair.Final)) -Directory -MustExist) ([IO.Path]::GetFileName($pair.Final))
        if (-not $finals.Add($final)) { throw "Doppelter Zielname: $final" }
        if ([IO.Directory]::Exists($final) -or ([IO.File]::Exists($final) -and -not $originals.Contains($final))) { throw "Ziel bereits belegt: $final" }
        $id = [guid]::NewGuid().ToString('N')
        $parent = [IO.Path]::GetDirectoryName($original)
        $map.Add([pscustomobject]@{
            Original = $original; Final = $final
            Temporary = Join-Path $parent ".shell-rename-$id"
            Rollback = Join-Path $parent ".shell-rollback-$id"
            Current = $original; State = 'Original'; Hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
        })
        Write-ShellLog $Context "$original -> $final" -Phase Umbenennungsplan
    }
    if (@($map | Where-Object { $_.Original -cne $_.Final }).Count -eq 0) {
        Add-ShellResult $Context $Label Skipped Umbenennen 'Namen bereits unverändert korrekt.'
        return $true
    }
    if (-not (Confirm-ShellOperation $Context $Label 'Dateien zweiphasig umbenennen (mit Wiederherstellungsjournal)')) { return $false }
    if (-not $Context.LogDirectory) { throw 'Ohne persistentes Journal keine Umbenennung.' }
    $journal = Join-Path $Context.LogDirectory ("Rename-$([guid]::NewGuid().ToString('N')).csv")
    Save-RenameJournal $journal $map
    Write-ShellLog $Context "Wiederherstellungsjournal: $journal"
    try {
        foreach ($entry in $map) {
            Move-RenameEntry $entry $entry.Temporary
            $entry.State = 'Temporary'
            Save-RenameJournal $journal $map
        }
        foreach ($entry in $map) {
            Move-RenameEntry $entry $entry.Final
            $entry.State = 'Final'
            Save-RenameJournal $journal $map
        }
        Add-ShellResult $Context $Label Success Umbenennen "Abgeschlossen; Journal: $journal"
        return $true
    }
    catch {
        $originalError = $_
        Write-ShellLog $Context 'Umbenennen fehlgeschlagen; Rücksetzung beginnt.' ERROR -ErrorRecord $originalError -Phase Umbenennen -Path $Label
        Undo-SequentialRename $Context $map $journal
        throw $originalError
    }
}

function ConvertTo-FormattedWords {
    param([string]$Text, [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$LowerWordSet)
    $normalized = (($Text -replace '_',' ') -replace '\s+',' ').Trim()
    $parts = [regex]::Split($normalized, '([ \-/&])')
    return (($parts | ForEach-Object {
        if (-not $_ -or $_ -match '^[ \-/&]$') { $_ }
        elseif ($_ -ieq 'by' -or $LowerWordSet.Contains($_)) { $_.ToLowerInvariant() }
        else { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }
    }) -join '')
}

function Invoke-GraphicsRename {
    param($Context, [string]$Path, [switch]$Recurse, [bool]$ProcessWithoutBy, [bool]$ForceCaseChange,
        [AllowEmptyCollection()][string[]]$LowerWords, [AllowEmptyCollection()][string[]]$Extensions, [switch]$StripNumericSuffix)
    $root = Get-SafePath $Path -Directory -MustExist
    $extensionsSet = New-StringHashSet $Extensions -NormalizeExtensions
    $lowerSet = New-StringHashSet $LowerWords
    if ($extensionsSet.Count -eq 0) { throw 'Extensions enthält keine wirksame Erweiterung.' }
    Write-ShellLog $Context "Erweiterungen=$($extensionsSet -join ','); LowerWords=$($lowerSet -join ','); by bleibt immer klein."
    $reserved = New-StringHashSet
    $files = @(Get-SafeTree $root -Recurse:$Recurse -Context $Context | Where-Object { -not $_.PSIsContainer -and $extensionsSet.Contains($_.Extension.TrimStart('.')) } | Sort-Object FullName)
    foreach ($file in $files) {
        try {
            $base = $file.BaseName
            if (-not $ProcessWithoutBy -and $base -notmatch '(?i)_by_') {
                Add-ShellResult $Context $file.FullName Skipped Umbenennen 'Kein _by_ im Namen.'; continue
            }
            if ($StripNumericSuffix) { $base = $base -replace '(_(?=[A-Za-z0-9-]*\d)[A-Za-z0-9-]+)$','' }
            $formatted = ConvertTo-FormattedWords $base $lowerSet
            if (-not $formatted) { throw 'Der ermittelte Titel ist leer.' }
            $name = $formatted + $file.Extension
            $target = Join-Path $file.DirectoryName $name
            if ($file.FullName -ceq $target -or (-not $ForceCaseChange -and $file.FullName -ieq $target)) {
                $null = $reserved.Add($target)
                Add-ShellResult $Context $file.FullName Skipped Umbenennen 'Name unverändert / Großschreibungsänderung deaktiviert.'; continue
            }
            $n = 0
            while ($file.FullName -ine $target -and ((Test-Path -LiteralPath $target) -or $reserved.Contains($target))) {
                $n++; $target = Join-Path $file.DirectoryName ("$formatted [$n]" + $file.Extension)
            }
            $null = $reserved.Add($target)
            $null = Invoke-RenameTransaction $Context @([pscustomobject]@{ Original = $file.FullName; Final = $target }) $file.FullName
        }
        catch { Add-ShellResult $Context $file.FullName Failed Umbenennen 'Grafik konnte nicht umbenannt werden.' $_ }
    }
}

function Get-IconIniPlan {
    param([string]$Folder, [bool]$Modify)
    $ini = Join-Path $Folder 'desktop.ini'
    $lines = @()
    if ([IO.File]::Exists($ini)) {
        # BOM-Erkennung plus Windows-ANSI-Fallback für ältere desktop.ini-Dateien.
        $ansi = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        $reader = [IO.StreamReader]::new($ini, $ansi, $true)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $lines = @($text -split '\r\n|\n|\r')
        if ($lines.Count -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -SkipLast 1) }
    }
    $result = [Collections.Generic.List[string]]::new()
    $inShell = $false; $sections = 0; $ownsIcon = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:[;#].*)?$') {
            $inShell = $Matches[1].Trim() -ieq '.ShellClassInfo'
            if ($inShell) {
                $sections++
                if ($sections -gt 1) { throw "Mehrere [.ShellClassInfo]-Abschnitte: $ini" }
                $result.Add($line)
                if ($Modify) { $result.Add('IconResource=.\desktop.ico,0') }
                continue
            }
        }
        if ($inShell -and $line -match '^\s*(IconResource|IconFile|IconIndex)\s*=(.*)$') {
            $key = $Matches[1]; $value = $Matches[2].Trim()
            if ($key -ine 'IconIndex') {
                if ($key -ieq 'IconResource') { $value = $value -replace ',\s*-?\d+\s*$','' }
                $value = $value.Trim().Trim('"')
                if ($value -match '^(?i)(\.\\)?desktop\.ico$') { $ownsIcon = $true }
                elseif ([IO.Path]::IsPathRooted($value)) {
                    $candidate = Get-SafePath $value
                    if ($candidate -ieq (Join-Path $Folder 'desktop.ico')) { $ownsIcon = $true }
                }
            }
            continue
        }
        $result.Add($line)
    }
    if ($Modify -and $sections -eq 0) { $result.Add('[.ShellClassInfo]'); $result.Add('IconResource=.\desktop.ico,0') }
    return [pscustomobject]@{ Lines = $result.ToArray(); OwnsIcon = $ownsIcon; HasSection = ($sections -eq 1) }
}

function Set-ShellAttributes {
    param([string]$Path, [IO.FileAttributes]$Add = 0, [IO.FileAttributes]$Remove = 0)
    $safe = Get-SafePath $Path -MustExist
    [IO.File]::SetAttributes($safe, (([IO.File]::GetAttributes($safe) -band (-bnot $Remove)) -bor $Add))
}

function Invoke-IconTransaction {
    param($Context, [string]$Folder, [switch]$Modify, [switch]$ClearFolderReadOnly, [switch]$RemoveDesktopIni)
    $folderPath = Get-SafePath $Folder -Directory -MustExist
    $ini = Get-SafePath (Join-Path $folderPath 'desktop.ini')
    $ico = Get-SafePath (Join-Path $folderPath 'desktop.ico')
    foreach ($file in @($ini,$ico)) { if ([IO.Directory]::Exists($file)) { throw "Dateiname ist ein Ordner: $file" } }
    $source = "$folderPath.ico"
    if ($Modify) {
        $source = Get-SafePath $source -MustExist
        $header = New-Object byte[] 6
        $stream = [IO.File]::OpenRead($source)
        try { $read = $stream.Read($header, 0, 6) } finally { $stream.Dispose() }
        if ($read -lt 6 -or $header[0] -ne 0 -or $header[1] -ne 0 -or $header[2] -ne 1 -or $header[3] -ne 0 -or ($header[4] -eq 0 -and $header[5] -eq 0)) { throw "Keine gültige ICO-Kopfzeile: $source" }
    }
    $plan = Get-IconIniPlan $folderPath ([bool]$Modify)
    $action = if ($Modify) { 'Ordnersymbol transaktional einrichten' } else { 'Ordnersymbol-Konfiguration transaktional entfernen' }
    if (-not (Confirm-ShellOperation $Context $folderPath $action)) { return }
    if (-not $Context.LogDirectory) { throw 'Ohne persistente Sicherung keine Symboländerung.' }
    $backup = Join-Path $Context.LogDirectory ("Icon-Recovery-$([guid]::NewGuid().ToString('N'))")
    Assert-SeparatePaths $folderPath $backup
    $null = [IO.Directory]::CreateDirectory($backup)
    $folderAttributes = [IO.File]::GetAttributes($folderPath)
    $records = @(
        foreach ($file in @($ini,$ico)) {
            $exists = [IO.File]::Exists($file)
            $attributes = if ($exists) { [IO.File]::GetAttributes($file) } else { 0 }
            $copy = Join-Path $backup ([IO.Path]::GetFileName($file))
            if ($exists) { [IO.File]::Copy($file, $copy, $false) }
            [pscustomobject]@{ Path = $file; Exists = $exists; Attributes = [int]$attributes; Backup = $copy }
        }
    )
    $manifest = [pscustomobject]@{ Folder = $folderPath; FolderAttributes = [int]$folderAttributes; Files = $records }
    [IO.File]::WriteAllText((Join-Path $backup 'recovery.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
    Write-ShellLog $Context "Symbol-Sicherung (auch nach Erfolg erhalten): $backup"
    $blocked = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReadOnly
    try {
        if ($Modify) {
            foreach ($file in @($ini,$ico)) { if ([IO.File]::Exists($file)) { Set-ShellAttributes $file -Remove $blocked } }
            [IO.File]::Copy($source, $ico, $true)
            [IO.File]::WriteAllLines($ini, [string[]]$plan.Lines, [Text.Encoding]::Unicode)
            Set-ShellAttributes $ico -Add ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::ReadOnly)
            Set-ShellAttributes $ini -Add ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)
            Set-ShellAttributes $folderPath -Add ([IO.FileAttributes]::ReadOnly)
        }
        else {
            if ([IO.File]::Exists($ini) -and ($RemoveDesktopIni -or $plan.HasSection)) {
                Set-ShellAttributes $ini -Remove $blocked
                if ($RemoveDesktopIni) { [IO.File]::Delete($ini) }
                else {
                    [IO.File]::WriteAllLines($ini, [string[]]$plan.Lines, [Text.Encoding]::Unicode)
                    [IO.File]::SetAttributes($ini, [IO.FileAttributes]$records[0].Attributes)
                }
            }
            if ($plan.OwnsIcon -and [IO.File]::Exists($ico)) {
                Set-ShellAttributes $ico -Remove $blocked
                [IO.File]::Delete($ico)
            }
            if ($ClearFolderReadOnly) { Set-ShellAttributes $folderPath -Remove ([IO.FileAttributes]::ReadOnly) }
        }
        Add-ShellResult $Context $folderPath Success Symbol "Abgeschlossen; Sicherung: $backup"
    }
    catch {
        $originalError = $_
        foreach ($record in $records) {
            try {
                $null = Get-SafePath $record.Path
                if ([IO.File]::Exists($record.Path)) { [IO.File]::SetAttributes($record.Path, [IO.FileAttributes]::Normal) }
                if ($record.Exists) {
                    [IO.File]::Copy($record.Backup, $record.Path, $true)
                    [IO.File]::SetAttributes($record.Path, [IO.FileAttributes]$record.Attributes)
                }
                elseif ([IO.File]::Exists($record.Path)) { [IO.File]::Delete($record.Path) }
            }
            catch { Add-ShellResult $Context $record.Path Failed Rollback "Symbol-Wiederherstellung fehlgeschlagen; $backup" $_ }
        }
        try { $null = Get-SafePath $folderPath -MustExist; [IO.File]::SetAttributes($folderPath, $folderAttributes) }
        catch { Add-ShellResult $Context $folderPath Failed Rollback "Ordnerattribute nicht wiederhergestellt; $backup" $_ }
        throw $originalError
    }
}

function Invoke-FolderIcons {
    param($Context, [string[]]$Path, [switch]$Recurse, [switch]$Modify, [switch]$ClearFolderReadOnly, [switch]$RemoveDesktopIni)
    if (-not $Path -or -not @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count) {
        throw 'Mindestens einen Zielordner mit -Path angeben.'
    }
    $seen = New-StringHashSet
    foreach ($root in $Path) {
        try {
            $safe = Get-SafePath $root -Directory -MustExist
            $targets = @($safe)
            if ($Recurse) { $targets += @(Get-SafeTree $safe -Recurse -Context $Context | Where-Object PSIsContainer | ForEach-Object { $_.FullName }) }
            foreach ($target in $targets) {
                if (-not $seen.Add($target)) { continue }
                try { Invoke-IconTransaction $Context $target -Modify:$Modify -ClearFolderReadOnly:$ClearFolderReadOnly -RemoveDesktopIni:$RemoveDesktopIni }
                catch { Add-ShellResult $Context $target Failed Symbol 'Symboländerung fehlgeschlagen.' $_ }
            }
        }
        catch { Add-ShellResult $Context $root Failed Suche 'Ungültiger Ziel-/Suchpfad.' $_ }
    }
}

function Invoke-ComicProcessing {
    param($Context, [string]$Root, [string]$ArchiveType, [string]$RarExe, [switch]$Overwrite,
        [string[]]$ImageExtensions, [switch]$Cleanup, [AllowEmptyCollection()][string[]]$CleanupExtensions,
        [AllowEmptyCollection()][string[]]$CleanupNamePatterns, [string[]]$PreserveNames,
        [AllowEmptyCollection()][string[]]$DirectoryNames = @())
    $safeRoot = Get-SafePath $Root -Directory -MustExist
    $images = New-StringHashSet $ImageExtensions -NormalizeExtensions
    if ($images.Count -eq 0) { throw 'ImageExtensions enthält keine wirksame Erweiterung.' }
    $cleanupSet = New-StringHashSet $CleanupExtensions -NormalizeExtensions
    $preserved = New-StringHashSet $PreserveNames
    $null = $preserved.Add('ComicInfo.xml')
    if ($ArchiveType -eq 'rar') { $RarExe = Resolve-RarExecutable $RarExe }
    else {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
    Initialize-ShellNative
    $directories = @(Get-SafeTree $safeRoot -Context $Context | Where-Object PSIsContainer)
    foreach ($requested in $DirectoryNames) {
        if ($requested -notin @($directories | ForEach-Object { $_.Name })) {
            Add-ShellResult $Context $requested Failed Suche 'Ausgewählter direkter Comic-Unterordner fehlt oder ist nicht regulär.'
        }
    }
    foreach ($directory in $directories) {
        if ($DirectoryNames.Count -and $directory.Name -notin $DirectoryNames) { continue }
        try {
            if ($Context.LogDirectory -and (Test-PathOverlap $directory.FullName $Context.LogDirectory)) {
                throw 'Comic-Ordner überlappt das aktive Protokollverzeichnis; keine Änderung.'
            }
            $all = @(Get-SafeTree $directory.FullName -Recurse -RejectReparse)
            $directImages = @($all | Where-Object {
                -not $_.PSIsContainer -and $_.DirectoryName -ieq $directory.FullName -and
                $images.Contains($_.Extension.TrimStart('.')) -and -not $preserved.Contains($_.Name)
            })
            if (-not $directImages.Count) { throw 'Keine direkten Bilddateien aus der Bild-Whitelist vorhanden; keine Bereinigung.' }
            $candidates = @($all | Where-Object {
                if ($_.PSIsContainer -or $preserved.Contains($_.Name) -or $_.Extension -ieq '.xml') { return $false }
                if ($cleanupSet.Contains($_.Extension.TrimStart('.'))) { return $true }
                foreach ($pattern in $CleanupNamePatterns) { if ($_.Name -like $pattern) { return $true } }
                return $false
            })
            $cleanupSkipped = $false
            if ($Cleanup) {
                foreach ($file in $candidates) {
                    if (Confirm-ShellOperation $Context $file.FullName 'Ausgewählte Comic-Begleitdatei löschen') {
                        $null = Get-SafePath $file.FullName -MustExist
                        Remove-Item -LiteralPath $file.FullName -Force -Confirm:$false -ErrorAction Stop
                        Add-ShellResult $Context $file.FullName Success Bereinigung 'Begleitdatei gelöscht.'
                    }
                    else { $cleanupSkipped = $true }
                }
            }
            if ($cleanupSkipped -and -not $Context.DryRun) {
                Add-ShellResult $Context $directory.FullName Skipped Comic 'Bereinigung abgelehnt; keine Umbenennung/Archivierung.'; continue
            }
            $files = @($directImages | Where-Object { -not $Cleanup -or $_.FullName -notin @($candidates | ForEach-Object { $_.FullName }) })
            if ($files.Count -eq 0) { throw 'Keine direkten Bilddateien aus der Bild-Whitelist vorhanden.' }
            [string[]]$names = @($files | ForEach-Object { $_.Name })
            [Array]::Sort($names, [ShellSafety.NaturalComparer]::new())
            $pairs = @(
                for ($i = 0; $i -lt $names.Count; $i++) {
                    [pscustomobject]@{
                        Original = Join-Path $directory.FullName $names[$i]
                        Final = Join-Path $directory.FullName ('{0:D4}{1}' -f ($i+1), [IO.Path]::GetExtension($names[$i]))
                    }
                }
            )
            $renamed = Invoke-RenameTransaction $Context $pairs $directory.FullName
            if (-not $renamed -and -not $Context.DryRun) {
                Add-ShellResult $Context $directory.FullName Skipped Comic 'Umbenennen abgelehnt; Archivierung ausgelassen.'; continue
            }
            $extension = if ($ArchiveType -eq 'rar') { '.cbr' } else { '.cbz' }
            $archive = Join-Path $safeRoot ($directory.Name + $extension)
            if (-not $Overwrite) {
                $n = 0
                while (Test-Path -LiteralPath $archive) { $n++; $archive = Join-Path $safeRoot ("$($directory.Name) ($n)$extension") }
            }
            $null = New-SafeArchive $Context $directory.FullName $archive $ArchiveType $RarExe -Overwrite:$Overwrite
        }
        catch { Add-ShellResult $Context $directory.FullName Failed Comic 'Comic-Verarbeitung fehlgeschlagen; weitere Ordner werden verarbeitet.' $_ }
    }
}
