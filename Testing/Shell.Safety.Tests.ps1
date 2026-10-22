#requires -Version 5.1

<#
.SYNOPSIS
Pester-Regressionen fuer Dateioperationen, Ordnersymbole und Backups.
.DESCRIPTION
Mit Pester 3.4.0 ausfuehren, nicht direkt starten. README.md dokumentiert
die isolierten Fixtures, Voraussetzungen und den aktuellen Verzeichnisaufbau.
.LINK
README.md
#>
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$fileOpsRoot = Join-Path $workspaceRoot 'Legacy\FileOps'
$folderRoot = Join-Path $workspaceRoot 'Legacy\Folder'
$backupRoot = Join-Path $workspaceRoot 'Utilities\Backup'
. (Join-Path $fileOpsRoot 'Shell.Common.ps1')
. (Join-Path $folderRoot 'Shell.Backup.ps1')

function New-TestContext {
    param([string]$Name = 'test')
    $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($base)
    $cmdlet = [pscustomobject]@{ Allowed = $true }
    $cmdlet | Add-Member ScriptMethod ShouldProcess { param($target, $action) return $this.Allowed }
    $ctx = New-ShellContext $Name (Join-Path $base 'logs') $cmdlet
    $ctx | Add-Member NoteProperty Fixture $base
    return $ctx
}

function New-TestDirectory {
    param([string]$Path)
    $null = [IO.Directory]::CreateDirectory($Path)
    return $Path
}

function Write-TestFile {
    param([string]$Path, [string]$Content = 'fixture')
    [IO.File]::WriteAllText($Path, $Content, [Text.Encoding]::UTF8)
}

function Test-Throws {
    param([scriptblock]$Operation)
    try { $null = & $Operation; return $false }
    catch { return $true }
}

function New-TestBackupOptions {
    param($Context)
    $options = @{
        RarExe = 'fake-rar'; UserArchivePrefix = 'User'; LocalArchivePrefix = 'Local'; CloudArchivePrefix = 'Cloud'
        UserFolderPaths = @{}; UserTempPath = ''; SecondaryTempPath = ''; StopOutlook = $false
        OutlookLocalPath = ''; OutlookDocumentsPath = ''
        LocalBookPath = ''; LocalPhotoPath = ''; LocalPicturesPath = ''; LocalMusicPath = ''; LocalIosPath = ''
        OneDrivePath = ''; DropboxPath = ''; CreativeCloudPath = ''; SynologyPath = ''; ICloudPath = ''
    }
    foreach ($name in @('Contacts','Favorites','Links','Documents','Desktop','Pictures','Music','Videos')) {
        $options.UserFolderPaths[$name] = New-TestDirectory (Join-Path $Context.Fixture $name)
        Write-TestFile (Join-Path $options.UserFolderPaths[$name] 'data.bin') $name
    }
    return $options
}

Describe 'Sammlungen, Grafiknamen und natürliche Sortierung' {
    BeforeEach { $ctx = New-TestContext }
    It 'liefert einen einzelnen ordinal-case-insensitiven HashSet, auch leer/einelementig' {
        $empty = New-StringHashSet @()
        $empty.GetType().FullName | Should Match 'HashSet'
        $empty.Count | Should Be 0
        $one = New-StringHashSet @('.jpg') -NormalizeExtensions
        $one.Count | Should Be 1
        $one.Contains('JPG') | Should Be $true
        (ConvertTo-FormattedWords 'rock_And_roll_by_artist' (New-StringHashSet @('and'))) | Should Be 'Rock and Roll by Artist'
        (ConvertTo-FormattedWords 'a_by_b' $empty) | Should Be 'A by B'
    }
    It 'sortiert 1,2,10 sowie sehr lange Ziffernfolgen ohne numerischen Überlauf' {
        Initialize-ShellNative
        [string[]]$names = @('10.jpg','2.jpg','100000000000000000000000000000000000000.jpg','1.jpg')
        [Array]::Sort($names, [ShellSafety.NaturalComparer]::new())
        ($names -join ',') | Should Be '1.jpg,2.jpg,10.jpg,100000000000000000000000000000000000000.jpg'
    }
    It 'verarbeitet JPG und And, bleibt beim zweiten Lauf stabil und behält Zahlen' {
        $dir = New-TestDirectory (Join-Path $ctx.Fixture 'images')
        Write-TestFile (Join-Path $dir 'rock_And_roll_by_artist_2024.JPG') 'identity'
        Invoke-GraphicsRename $ctx $dir -ProcessWithoutBy $true -ForceCaseChange $true -LowerWords @('and') -Extensions @('.jpg')
        $name = 'Rock and Roll by Artist 2024.JPG'
        [IO.File]::ReadAllText((Join-Path $dir $name)) | Should Be 'identity'
        Invoke-GraphicsRename $ctx $dir -ProcessWithoutBy $true -ForceCaseChange $true -LowerWords @('AND') -Extensions @('JPG')
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should Be 1
        (Get-ChildItem -LiteralPath $dir -File).Name | Should Be $name
    }
    It 'lehnt eine leere effektive Erweiterungsliste ab' {
        Test-Throws { Invoke-GraphicsRename $ctx $ctx.Fixture -Extensions @('.',' ') -LowerWords @() -ProcessWithoutBy $true -ForceCaseChange $true } | Should Be $true
    }
    It 'reserviert Kollisionen auch in der Vorschau ohne Dateiumbenennung' {
        $dir = New-TestDirectory (Join-Path $ctx.Fixture 'images')
        Write-TestFile (Join-Path $dir 'a__b.jpg') 'first'
        Write-TestFile (Join-Path $dir 'a_b.jpg') 'second'
        $ctx.Cmdlet.Allowed = $false; $ctx.DryRun = $true
        Invoke-GraphicsRename $ctx $dir -ProcessWithoutBy $true -ForceCaseChange $true -LowerWords @() -Extensions @('jpg')
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should Be 2
        [IO.File]::ReadAllText($ctx.LogFile) | Should Match 'A B \[1\]\.jpg'
        @($ctx.Results | Where-Object Status -eq Planned).Count | Should Be 2
    }
}

Describe 'Zweiphasige Umbenennung und Wiederherstellungsidentität' {
    $realMove = ${function:Move-RenameEntry}
    BeforeEach {
        $ctx = New-TestContext
        $dir = New-TestDirectory (Join-Path $ctx.Fixture 'comic')
        Write-TestFile (Join-Path $dir '0000.jpg') 'original-zero'
        Write-TestFile (Join-Path $dir '0001.jpg') 'original-one'
        $pairs = @(
            [pscustomobject]@{ Original = Join-Path $dir '0000.jpg'; Final = Join-Path $dir '0001.jpg' }
            [pscustomobject]@{ Original = Join-Path $dir '0001.jpg'; Final = Join-Path $dir '0002.jpg' }
        )
        $script:moveCount = 0
        $script:failMoves = @()
        Mock Move-RenameEntry {
            param($Entry, $Destination)
            $script:moveCount++
            if ($script:moveCount -in $script:failMoves) { throw "injected-move-$($script:moveCount)" }
            & $realMove $Entry $Destination
        }
    }
    It 'setzt bei Fehler vor erster Bewegung nichts Fremdes zurück' {
        $script:failMoves = @(1)
        { Invoke-RenameTransaction $ctx $pairs $dir } | Should Throw 'injected-move-1'
        [IO.File]::ReadAllText((Join-Path $dir '0000.jpg')) | Should Be 'original-zero'
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'original-one'
        $script:moveCount | Should Be 1
    }
    It 'bewahrt bytegenaue Originalzuordnung bei Fehler in Phase eins' {
        $script:failMoves = @(2)
        { Invoke-RenameTransaction $ctx $pairs $dir } | Should Throw 'injected-move-2'
        [IO.File]::ReadAllText((Join-Path $dir '0000.jpg')) | Should Be 'original-zero'
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'original-one'
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should Be 2
    }
    It 'bewahrt bytegenaue Originalzuordnung am Beginn der zweiten Phase' {
        $script:failMoves = @(3)
        { Invoke-RenameTransaction $ctx $pairs $dir } | Should Throw 'injected-move-3'
        [IO.File]::ReadAllText((Join-Path $dir '0000.jpg')) | Should Be 'original-zero'
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'original-one'
    }
    It 'setzt auch bereits endgültig nummerierte Dateien kollisionsfrei zurück' {
        $script:failMoves = @(4)
        { Invoke-RenameTransaction $ctx $pairs $dir } | Should Throw 'injected-move-4'
        [IO.File]::ReadAllText((Join-Path $dir '0000.jpg')) | Should Be 'original-zero'
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'original-one'
        $journal = Get-ChildItem -LiteralPath $ctx.LogDirectory -Filter 'Rename-*.csv' | Select-Object -First 1
        $rows = @(Import-Csv -LiteralPath $journal.FullName)
        @($rows | Where-Object State -ne Original).Count | Should Be 0
        $rows[0].Hash | Should Not BeNullOrEmpty
    }
    It 'bewahrt Ursprungsfehler, protokolliert jede fehlgeschlagene Rücksetzung' {
        $script:failMoves = @(4,5,7)
        { Invoke-RenameTransaction $ctx $pairs $dir } | Should Throw 'injected-move-4'
        @($ctx.Results | Where-Object { $_.Phase -eq 'Rollback' -and $_.Status -eq 'Failed' }).Count | Should Be 3
        $contents = @(Get-ChildItem -LiteralPath $dir -Force -File | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
        ($contents -contains 'original-zero') | Should Be $true
        ($contents -contains 'original-one') | Should Be $true
    }
    It 'persistiert vollständige Zuordnung bevor die erste Datei bewegt wird' {
        Mock Move-RenameEntry {
            param($Entry, $Destination)
            $journals = @(Get-ChildItem -LiteralPath $ctx.LogDirectory -Filter 'Rename-*.csv')
            if ($journals.Count -ne 1 -or @(Import-Csv $journals[0].FullName).Count -ne 2) { throw 'journal-missing' }
            & $realMove $Entry $Destination
        }
        Invoke-RenameTransaction $ctx $pairs $dir | Should Be $true
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'original-zero'
        [IO.File]::ReadAllText((Join-Path $dir '0002.jpg')) | Should Be 'original-one'
    }
}

Describe 'Geprüfte Archivveröffentlichung' {
    $realZip = ${function:New-ZipStage}
    $realTestZip = ${function:Test-ZipStage}
    $realPublish = ${function:Publish-ShellFile}
    BeforeEach {
        $ctx = New-TestContext
        $source = New-TestDirectory (Join-Path $ctx.Fixture 'source')
        Write-TestFile (Join-Path $source 'page.jpg') 'image-identity'
        Write-TestFile (Join-Path $source 'ComicInfo.xml') '<ComicInfo/>'
        $destination = Join-Path $ctx.Fixture 'comic.cbz'
        $script:zipFailure = ''
        Mock New-ZipStage {
            param($Source,$Stage)
            if ($script:zipFailure -eq 'create') { Write-TestFile $Stage 'partial'; throw 'create-failure' }
            & $realZip $Source $Stage
        }
        Mock Test-ZipStage {
            param($Stage,$Hashes)
            if ($script:zipFailure -eq 'validation') { throw 'validation-failure' }
            & $realTestZip $Stage $Hashes
        }
        Mock Publish-ShellFile {
            param($Stage,$Destination,[switch]$Overwrite,$Context)
            if ($script:zipFailure -eq 'publish') { throw 'publish-failure' }
            & $realPublish $Stage $Destination -Overwrite:$Overwrite -Context $Context
        }
    }
    It 'erstellt und prüft echte ZIP-Dateien samt unveränderter Metadaten' {
        New-SafeArchive $ctx $source $destination zip | Should Be $true
        $zip = [IO.Compression.ZipFile]::OpenRead($destination)
        try {
            (@($zip.Entries.FullName) -contains 'ComicInfo.xml') | Should Be $true
            (@($zip.Entries.FullName) -contains 'page.jpg') | Should Be $true
        }
        finally { $zip.Dispose() }
    }
    It 'erkennt Inhaltsänderung mit SHA256 auch wenn ZIP lesbar bleibt' {
        $stage = Join-Path $ctx.Fixture 'stage.zip'
        $hashes = & $realZip (Get-SafePath $source) $stage
        $hashes['page.jpg'] = 'wrong'
        { & $realTestZip $stage $hashes } | Should Throw 'beschädigt'
    }
    It 'behält vorheriges Archiv bei ZIP-Erstellfehler' {
        Write-TestFile $destination 'old-archive'
        $script:zipFailure = 'create'
        { New-SafeArchive $ctx $source $destination zip -Overwrite } | Should Throw 'create-failure'
        [IO.File]::ReadAllText($destination) | Should Be 'old-archive'
        @(Get-ChildItem $ctx.Fixture -Filter '.shell-stage-*' -Force).Count | Should Be 0
    }
    It 'behält vorheriges Archiv bei ZIP-Prüffehler' {
        Write-TestFile $destination 'old-archive'
        $script:zipFailure = 'validation'
        { New-SafeArchive $ctx $source $destination zip -Overwrite } | Should Throw 'validation-failure'
        [IO.File]::ReadAllText($destination) | Should Be 'old-archive'
    }
    It 'behält vorheriges Archiv bei Veröffentlichungsfehler' {
        Write-TestFile $destination 'old-archive'
        $script:zipFailure = 'publish'
        { New-SafeArchive $ctx $source $destination zip -Overwrite } | Should Throw 'publish-failure'
        [IO.File]::ReadAllText($destination) | Should Be 'old-archive'
    }
    It 'überschreibt auch ein nach der Planung entstandenes Ziel nicht' {
        $stage = Join-Path $ctx.Fixture 'stage'
        Write-TestFile $stage 'new'
        Write-TestFile $destination 'racing-writer'
        Test-Throws { Publish-ShellFile $stage $destination } | Should Be $true
        [IO.File]::ReadAllText($destination) | Should Be 'racing-writer'
        [IO.File]::ReadAllText($stage) | Should Be 'new'
    }
    It 'ersetzt atomar und bewahrt das vorherige Archiv als Recovery-Datei' {
        Write-TestFile $destination 'old-archive'
        New-SafeArchive $ctx $source $destination zip -Overwrite | Should Be $true
        $previous = @(Get-ChildItem $ctx.Fixture -Filter 'comic.cbz.previous-*')
        $previous.Count | Should Be 1
        [IO.File]::ReadAllText($previous[0].FullName) | Should Be 'old-archive'
    }
    It 'weist Quell-Ziel-Überlappung in beiden Richtungen zurück' {
        { New-SafeArchive $ctx $source (Join-Path $source 'backup.zip') zip } | Should Throw 'überlappen'
        { Assert-SeparatePaths $source $ctx.Fixture } | Should Throw 'überlappen'
        { Assert-SeparatePaths $source $source } | Should Throw 'überlappen'
    }
}

Describe 'RAR-Fehler und Native-Ausgabe' {
    BeforeEach {
        $ctx = New-TestContext
        $source = New-TestDirectory (Join-Path $ctx.Fixture 'source')
        Write-TestFile (Join-Path $source 'page.jpg')
        $destination = Join-Path $ctx.Fixture 'comic.cbr'
        Write-TestFile $destination 'old'
        $script:nativePhase = 'none'
        $script:nativeCalls = @()
        Mock Invoke-ShellNative {
            param($Context,$Executable,$Arguments)
            $script:nativeCalls += $Arguments[0]
            if ($Arguments[0] -eq 'a') { Write-TestFile $Arguments[5] 'new-rar' }
            if ($Arguments[0] -eq $script:nativePhase) { throw "rar-failure-$($Arguments[0])" }
        }
    }
    It 'prüft RAR mit t vor dem Publizieren' {
        New-SafeArchive $ctx $source $destination rar 'fake-rar' -Overwrite | Should Be $true
        ($script:nativeCalls -join ',') | Should Be 'a,t'
        [IO.File]::ReadAllText($destination) | Should Be 'new-rar'
    }
    It 'behält altes Archiv bei RAR-a-Fehler' {
        $script:nativePhase = 'a'
        { New-SafeArchive $ctx $source $destination rar 'fake-rar' -Overwrite } | Should Throw 'rar-failure-a'
        [IO.File]::ReadAllText($destination) | Should Be 'old'
    }
    It 'behält altes Archiv bei RAR-t-Fehler und räumt nur eigene Arbeitsdatei weg' {
        $script:nativePhase = 't'
        Write-TestFile (Join-Path $ctx.Fixture '.shell-stage-not-owned.rar') 'unrelated'
        { New-SafeArchive $ctx $source $destination rar 'fake-rar' -Overwrite } | Should Throw 'rar-failure-t'
        [IO.File]::ReadAllText($destination) | Should Be 'old'
        @(Get-ChildItem $ctx.Fixture -Filter '.shell-stage-*' -Force).Count | Should Be 1
    }
}

Describe 'Native-Ausgabe ohne Mocks' {
    It 'behandelt einen fehlgeschlagenen Programmstart niemals als Erfolg' {
        $ctx = New-TestContext
        $missingExe = Join-Path $ctx.Fixture 'missing-rar.exe'
        $global:LASTEXITCODE = 0
        (Test-Throws { Invoke-ShellNative $ctx $missingExe @('t','fixture.rar') }) | Should Be $true
        [IO.File]::ReadAllText($ctx.LogFile) | Should Match 'missing-rar.exe'
    }
    It 'erlaubt stderr bei einem erfolgreich beendeten nativen Programm' {
        $ctx = New-TestContext
        $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('[Console]::Error.WriteLine("native-warning"); exit 0'))
        { Invoke-ShellNative $ctx $exe @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) } | Should Not Throw
        $text = [IO.File]::ReadAllText($ctx.LogFile)
        $text | Should Match 'native-warning'
        $text | Should Match 'Exitcode=0'
    }
    It 'protokolliert stdout, stderr und Exitcode bei Stop-Fehlerpräferenz' {
        $ctx = New-TestContext
        $old = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('[Console]::Out.WriteLine("native-out"); [Console]::Error.WriteLine("native-err"); exit 7'))
            { Invoke-ShellNative $ctx $exe @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) } | Should Throw 'Exitcode=7'
            $ErrorActionPreference | Should Be 'Stop'
            $text = [IO.File]::ReadAllText($ctx.LogFile)
            $text | Should Match 'native-out'
            $text | Should Match 'native-err'
            $text | Should Match 'Exitcode=7'
        }
        finally { $ErrorActionPreference = $old }
    }
}

Describe 'Icon-Transaktionen' {
    BeforeEach {
        $ctx = New-TestContext
        $folder = New-TestDirectory (Join-Path $ctx.Fixture 'icon-folder')
        $ini = Join-Path $folder 'desktop.ini'
        $ico = Join-Path $folder 'desktop.ico'
        Write-TestFile $ini "[.ShellClassInfo]`r`nIconResource=.\desktop.ico,0`r`nInfoTip=Erhalten`r`n[Other]`r`nIconFile=other.ico`r`nKeep=yes"
        Write-TestFile $ico 'old-ico'
        [IO.File]::WriteAllBytes("$folder.ico", [byte[]]@(0,0,1,0,1,0,17,18))
    }
    It 'entfernt nur Symbolschlüssel im richtigen Abschnitt und eigenes Icon' {
        Invoke-IconTransaction $ctx $folder
        $text = [IO.File]::ReadAllText($ini)
        $text | Should Match 'InfoTip=Erhalten'
        $text | Should Match 'IconFile=other.ico'
        $text | Should Not Match 'IconResource'
        [IO.File]::Exists($ico) | Should Be $false
        @(Get-ChildItem $ctx.LogDirectory -Filter 'Icon-Recovery-*' -Directory).Count | Should Be 1
    }
    It 'behält unreferenzierte desktop.ico auch bei kompletter INI-Löschung' {
        Write-TestFile $ini "[.ShellClassInfo]`r`nIconResource=other.ico,0"
        Invoke-IconTransaction $ctx $folder -RemoveDesktopIni
        [IO.File]::Exists($ini) | Should Be $false
        [IO.File]::ReadAllText($ico) | Should Be 'old-ico'
    }
    It 'weist mehrere ShellClassInfo-Abschnitte vor Mutation zurück' {
        Write-TestFile $ini "[.ShellClassInfo]`r`nIconFile=desktop.ico`r`n[.ShellClassInfo]"
        $before = [IO.File]::ReadAllText($ini)
        { Invoke-IconTransaction $ctx $folder -Modify } | Should Throw 'Mehrere'
        [IO.File]::ReadAllText($ini) | Should Be $before
        [IO.File]::ReadAllText($ico) | Should Be 'old-ico'
    }
    It 'ändert Symbolkonfiguration, erhält andere Einstellungen und sichert fremdes Icon' {
        Invoke-IconTransaction $ctx $folder -Modify
        [IO.File]::ReadAllText($ini) | Should Match 'InfoTip=Erhalten'
        $backup = Get-ChildItem $ctx.LogDirectory -Directory -Filter 'Icon-Recovery-*' | Select-Object -First 1
        [IO.File]::ReadAllText((Join-Path $backup.FullName 'desktop.ico')) | Should Be 'old-ico'
        [int]([IO.File]::GetAttributes($folder) -band [IO.FileAttributes]::ReadOnly) | Should Not Be 0
    }
    It 'stellt Inhalte und alle Attribute bei nachfolgendem Fehler wieder her' {
        $iniBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ini))
        [IO.File]::SetAttributes($ini, [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)
        $iniAttrs = [IO.File]::GetAttributes($ini)
        $folderAttrs = [IO.File]::GetAttributes($folder)
        $realSet = ${function:Set-ShellAttributes}
        $script:attributeCalls = 0
        Mock Set-ShellAttributes {
            param($Path,$Add = 0,$Remove = 0)
            $script:attributeCalls++
            if ($script:attributeCalls -eq 4) { throw 'attribute-failure' }
            & $realSet $Path -Add $Add -Remove $Remove
        }
        { Invoke-IconTransaction $ctx $folder -Modify } | Should Throw 'attribute-failure'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($ini)) | Should Be $iniBytes
        [IO.File]::ReadAllText($ico) | Should Be 'old-ico'
        [IO.File]::GetAttributes($ini) | Should Be $iniAttrs
        [IO.File]::GetAttributes($folder) | Should Be $folderAttrs
    }
}

Describe 'Pfadschutz und abgesicherte Temp-Bereinigung' {
    BeforeEach {
        $ctx = New-TestContext
        $temp = New-TestDirectory (Join-Path $ctx.Fixture 'named-cleanup-fixture')
        $backup = Join-Path $ctx.Fixture 'backup'
    }
    It 'lehnt Laufwerkswurzel, Benutzerprofil, Windows und Überlappung ab' {
        Test-Throws { Assert-TempCleanupPath ([IO.Path]::GetPathRoot($ctx.Fixture)) $backup } | Should Be $true
        Test-Throws { Assert-TempCleanupPath $env:USERPROFILE $backup } | Should Be $true
        Test-Throws { Assert-TempCleanupPath $env:WINDIR $backup } | Should Be $true
        Test-Throws { Assert-TempCleanupPath $temp (Join-Path $temp 'backup') } | Should Be $true
        Test-Throws { Assert-TempCleanupPath $temp $backup @($ctx.Fixture) } | Should Be $true
        Test-Throws { Assert-TempCleanupPath $temp $backup @((Join-Path $temp 'source')) } | Should Be $true
    }
    It 'erfordert für benutzerdefiniertes Temp eine explizite Pfadfreigabe' {
        Test-Throws { Assert-TempCleanupPath $temp $backup } | Should Be $true
        Write-TestFile (Join-Path $temp '.shell-temp-cleanup-allowed') (Get-SafePath $temp)
        Assert-TempCleanupPath $temp $backup | Should Be (Get-SafePath $temp)
    }
    It 'löscht bei Vorschau/abgelehnter Bestätigung keinerlei Fixture-Inhalte' {
        Write-TestFile (Join-Path $temp '.shell-temp-cleanup-allowed') (Get-SafePath $temp)
        Write-TestFile (Join-Path $temp 'keep.bin') 'keep'
        $ctx.Cmdlet.Allowed = $false; $ctx.DryRun = $true
        Remove-ConfiguredTempContent $ctx @($temp) $backup
        [IO.File]::ReadAllText((Join-Path $temp 'keep.bin')) | Should Be 'keep'
        @($ctx.Results | Where-Object Status -eq Planned).Count | Should Be 1
    }
    It 'bereinigt nur eigens erstellte freigegebene Fixture-Inhalte und behält Marker' {
        Write-TestFile (Join-Path $temp '.shell-temp-cleanup-allowed') (Get-SafePath $temp)
        $sub = New-TestDirectory (Join-Path $temp 'sub')
        Write-TestFile (Join-Path $sub 'discard.bin')
        Remove-ConfiguredTempContent $ctx @($temp) $backup
        [IO.Directory]::Exists($sub) | Should Be $false
        [IO.File]::Exists((Join-Path $temp '.shell-temp-cleanup-allowed')) | Should Be $true
    }
    It 'schließt Junctions vor dem Abstieg aus und verweigert umgeleitete Wurzeln' {
        $outside = New-TestDirectory (Join-Path $ctx.Fixture 'junction-target')
        Write-TestFile (Join-Path $outside 'keep.bin') 'keep'
        $link = Join-Path $temp 'junction'
        $null = New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop
        try {
            @(Get-SafeTree $temp -Recurse -Context $ctx).Count | Should Be 0
            { Get-SafePath $link -Directory -MustExist } | Should Throw 'Analysepunkt'
            { Get-SafePath (Join-Path $link 'keep.bin') -MustExist } | Should Throw 'Analysepunkt'
            { Get-SafeTree $temp -Recurse -RejectReparse } | Should Throw 'Analysepunkt'
            [IO.File]::ReadAllText((Join-Path $outside 'keep.bin')) | Should Be 'keep'
        }
        finally { [IO.Directory]::Delete($link) }
    }
    It 'verweigert mehrfach verlinkte Dateien vor Einzeldateiänderungen' {
        $original = Join-Path $temp 'original.bin'
        Write-TestFile $original 'hardlink-identity'
        $link = Join-Path $temp 'hardlink.bin'
        $null = New-Item -ItemType HardLink -Path $link -Target $original -ErrorAction Stop
        { Get-SafePath $link -MustExist } | Should Throw 'Hardlinks'
        [IO.File]::ReadAllText($original) | Should Be 'hardlink-identity'
    }
}

Describe 'Backup-Auswahl, Versionierung und Erfolgsschranke' {
    BeforeEach {
        $ctx = New-TestContext
        $options = New-TestBackupOptions $ctx
        $backup = Join-Path $ctx.Fixture 'backup'
        $script:archiveCalls = @()
        $script:archiveOutcome = 'success'
        $script:cleanupCalled = $false
        Mock Resolve-RarExecutable { return 'fake-rar' }
        Mock New-SafeArchive {
            param($Context,$Source,$Destination,$Type,$RarExe)
            $script:archiveCalls += [pscustomobject]@{ Source=$Source; Destination=$Destination }
            switch ($script:archiveOutcome) {
                'failure' { throw 'archive-failure' }
                'skip' { Add-ShellResult $Context $Destination Skipped Archiv 'declined'; return $false }
                default { Add-ShellResult $Context $Destination Success Archiv 'created'; return $true }
            }
        }
        Mock Remove-ConfiguredTempContent { $script:cleanupCalled = $true }
    }
    It 'nutzt explizite Known-Folder-Überschreibung und sichert die gesamte Musikquelle' {
        Invoke-BackupAction $ctx '2' $backup $options
        $script:archiveCalls.Count | Should Be 1
        $script:archiveCalls[0].Source | Should Be (Get-SafePath $options.UserFolderPaths.Music)
    }
    It 'erzeugt auch bei erneutem Aufruf im gleichen Lauf eindeutige Archive' {
        Invoke-BackupAction $ctx '2' $backup $options
        Invoke-BackupAction $ctx '2' $backup $options
        $script:archiveCalls[0].Destination | Should Not Be $script:archiveCalls[1].Destination
    }
    It 'bereinigt A erst nach fünf erfolgreich erstellten Dokumentarchiven' {
        Invoke-BackupAction $ctx A $backup $options
        $script:archiveCalls.Count | Should Be 5
        $script:cleanupCalled | Should Be $true
    }
    It 'bereinigt A nicht nach fehlgeschlagenem Backup' {
        $script:archiveOutcome = 'failure'
        Invoke-BackupAction $ctx A $backup $options
        $script:cleanupCalled | Should Be $false
        Complete-ShellRun $ctx | Should Be 2
    }
    It 'bereinigt A nicht nach übersprungenem Backup' {
        $script:archiveOutcome = 'skip'
        Invoke-BackupAction $ctx A $backup $options
        $script:cleanupCalled | Should Be $false
        @($ctx.Results | Where-Object Status -eq Success).Count | Should Be 0
    }
    It 'führt B ohne Temp-Bereinigung aus und schützt überlappende Quelle/Ziel' {
        Invoke-BackupAction $ctx B (Join-Path $options.UserFolderPaths.Documents 'backup') $options
        $script:cleanupCalled | Should Be $false
        @($ctx.Results | Where-Object Status -eq Failed).Count | Should Be 1
    }
    It 'meldet ausgewählte fehlende Known-Folder-Quelle ausdrücklich als Fehler' {
        $options.UserFolderPaths.Music = ''
        Invoke-BackupAction $ctx '2' $backup $options
        $script:archiveCalls.Count | Should Be 0
        Complete-ShellRun $ctx | Should Be 2
    }
}

Describe 'Outlook-Einzelkopien ohne Prozessstopp' {
    It 'veröffentlicht eine geprüfte Kopie und überschreibt keine vorhandene Datei' {
        $ctx = New-TestContext
        $source = Join-Path $ctx.Fixture 'fixture.pst'
        Write-TestFile $source 'mail-fixture'
        $destination = Join-Path $ctx.Fixture 'backup\run\fixture.pst'
        Copy-OutlookSnapshotFile $ctx $source $destination
        [IO.File]::ReadAllText($destination) | Should Be 'mail-fixture'
        Write-TestFile $source 'new-mail-fixture'
        Test-Throws { Copy-OutlookSnapshotFile $ctx $source $destination } | Should Be $true
        [IO.File]::ReadAllText($destination) | Should Be 'mail-fixture'
        @(Get-ChildItem (Split-Path $destination) -Filter '*.partial-*').Count | Should Be 0
    }
    It 'lehnt überlappende Outlook-Quell- und Zielordner ab' {
        $ctx = New-TestContext
        $source = New-TestDirectory (Join-Path $ctx.Fixture 'outlook')
        Write-TestFile (Join-Path $source 'fixture.pst')
        Copy-OutlookData $ctx @($source) (Join-Path $source 'backup')
        @($ctx.Results | Where-Object Status -eq Failed).Count | Should Be 1
        [IO.Directory]::Exists((Join-Path $source 'backup')) | Should Be $false
    }
}

Describe 'Comic-Metadaten, unabhängige Fehler und Vorschau' {
    BeforeEach { $ctx = New-TestContext; $root = New-TestDirectory (Join-Path $ctx.Fixture 'comics') }
    It 'nummeriert nur direkte Bilder natürlich und archiviert Metadaten unverändert' {
        $dir = New-TestDirectory (Join-Path $root 'comic')
        Write-TestFile (Join-Path $dir '10.jpg') 'ten'
        Write-TestFile (Join-Path $dir '2.JPG') 'two'
        Write-TestFile (Join-Path $dir '1.jpg') 'one'
        Write-TestFile (Join-Path $dir 'ComicInfo.xml') 'metadata'
        Write-TestFile (Join-Path $dir 'readme.txt') 'companion'
        Write-TestFile (Join-Path $root 'unrelated.txt') 'root-data'
        Invoke-ComicProcessing $ctx $root zip '' -ImageExtensions @('jpg') -CleanupExtensions @('txt') -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        [IO.File]::ReadAllText((Join-Path $dir '0001.jpg')) | Should Be 'one'
        [IO.File]::ReadAllText((Join-Path $dir '0002.JPG')) | Should Be 'two'
        [IO.File]::ReadAllText((Join-Path $dir '0003.jpg')) | Should Be 'ten'
        [IO.File]::ReadAllText((Join-Path $dir 'ComicInfo.xml')) | Should Be 'metadata'
        [IO.File]::ReadAllText((Join-Path $dir 'readme.txt')) | Should Be 'companion'
        [IO.File]::ReadAllText((Join-Path $root 'unrelated.txt')) | Should Be 'root-data'
        [IO.File]::Exists((Join-Path $root 'comic.cbz')) | Should Be $true
    }
    It 'löscht optional nur ausgewählte Begleiter in Comic-Ordnern, nie XML oder Root-Dateien' {
        $dir = New-TestDirectory (Join-Path $root 'comic')
        Write-TestFile (Join-Path $dir '1.jpg') 'page'
        Write-TestFile (Join-Path $dir 'ComicInfo.xml') 'metadata'
        Write-TestFile (Join-Path $dir 'readme.txt') 'companion'
        Write-TestFile (Join-Path $root 'unrelated.txt') 'root-data'
        Invoke-ComicProcessing $ctx $root zip '' -ImageExtensions @('jpg') -Cleanup -CleanupExtensions @('txt','xml') -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        [IO.File]::Exists((Join-Path $dir 'readme.txt')) | Should Be $false
        [IO.File]::ReadAllText((Join-Path $dir 'ComicInfo.xml')) | Should Be 'metadata'
        [IO.File]::ReadAllText((Join-Path $root 'unrelated.txt')) | Should Be 'root-data'
    }
    It 'verarbeitet weitere Comics nach Fehler eines Quellordners' {
        $bad = New-TestDirectory (Join-Path $root 'bad')
        $good = New-TestDirectory (Join-Path $root 'good')
        Write-TestFile (Join-Path $good 'page.jpg')
        Invoke-ComicProcessing $ctx $root zip '' -ImageExtensions @('jpg') -CleanupExtensions @() -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        @($ctx.Results | Where-Object Status -eq Failed).Count | Should Be 1
        [IO.File]::Exists((Join-Path $root 'good.cbz')) | Should Be $true
    }
    It 'meldet abgelehntes Umbenennen nicht als vollständig verarbeitet und erstellt kein Archiv' {
        $dir = New-TestDirectory (Join-Path $root 'comic')
        Write-TestFile (Join-Path $dir 'page.jpg')
        $ctx.Cmdlet.Allowed = $false
        Invoke-ComicProcessing $ctx $root zip '' -ImageExtensions @('jpg') -CleanupExtensions @() -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        [IO.File]::Exists((Join-Path $root 'comic.cbz')) | Should Be $false
        @($ctx.Results | Where-Object Status -eq Success).Count | Should Be 0
        @($ctx.Results | Where-Object Status -eq Skipped).Count | Should Be 2
    }
    It 'bereinigt keinen Nicht-Comic-Ordner ohne Bilddateien' {
        $dir = New-TestDirectory (Join-Path $root 'unrelated')
        Write-TestFile (Join-Path $dir 'keep.txt') 'keep'
        Invoke-ComicProcessing $ctx $root zip '' -ImageExtensions @('jpg') -Cleanup -CleanupExtensions @('txt') -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        [IO.File]::ReadAllText((Join-Path $dir 'keep.txt')) | Should Be 'keep'
        @($ctx.Results | Where-Object Status -eq Failed).Count | Should Be 1
    }
    It 'beachtet direkte Ordnerauswahl und meldet fehlende ausgewählte Ordner' {
        $dir = New-TestDirectory (Join-Path $root 'not-selected')
        Write-TestFile (Join-Path $dir 'keep.jpg') 'keep'
        Invoke-ComicProcessing $ctx $root zip '' -DirectoryNames @('missing') -ImageExtensions @('jpg') -CleanupExtensions @() -CleanupNamePatterns @() -PreserveNames @('ComicInfo.xml')
        [IO.File]::ReadAllText((Join-Path $dir 'keep.jpg')) | Should Be 'keep'
        @($ctx.Results | Where-Object Status -eq Failed).Count | Should Be 1
    }
}

Describe 'Gemeinsame Protokollierung und Exitcodes' {
    It 'wechselt bei Schreibfehler in einen isolierten Fallback und meldet Code 2' {
        $ctx = New-TestContext
        $script:testFallback = New-TestDirectory (Join-Path $ctx.Fixture 'fallback-temp')
        Mock Get-ShellTempDirectory { return $script:testFallback }
        $lock = [IO.File]::Open($ctx.LogFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            Write-ShellLog $ctx 'locked-log-test'
            $ctx.LogFailed | Should Be $true
            $ctx.FallbackUsed | Should Be $true
            $ctx.LogFile.StartsWith((Get-SafePath $script:testFallback), [StringComparison]::OrdinalIgnoreCase) | Should Be $true
            Complete-ShellRun $ctx | Should Be 2
        }
        finally { $lock.Dispose() }
    }
    It 'bleibt nach wiederholtem Logfehler ohne rekursiven Logger funktionsfähig' {
        $ctx = New-TestContext
        $ctx.FallbackUsed = $true
        $lock = [IO.File]::Open($ctx.LogFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            { Write-ShellLog $ctx 'console-only'; Write-ShellLog $ctx 'still-alive' } | Should Not Throw
            $ctx.LogFile | Should BeNullOrEmpty
            Complete-ShellRun $ctx | Should Be 2
        }
        finally { $lock.Dispose() }
    }
    It 'unterscheidet globale Fehler, Elementfehler und übersprungene Aktionen' {
        $ctx = New-TestContext
        Add-ShellResult $ctx fixture Skipped Test 'declined'
        Complete-ShellRun $ctx | Should Be 0
        Add-ShellResult $ctx fixture Failed Test 'failed'
        Complete-ShellRun $ctx | Should Be 2
        Complete-ShellRun $ctx 1 | Should Be 1
    }
    It 'meldet echten Zielverzeichnisfehler statt fälschlich Exitcode 0' {
        $ctx = New-TestContext
        $source = New-TestDirectory (Join-Path $ctx.Fixture 'source')
        Write-TestFile (Join-Path $source 'data.txt')
        $blockingFile = Join-Path $ctx.Fixture 'not-a-directory'
        Write-TestFile $blockingFile
        Test-Throws { New-SafeArchive $ctx $source (Join-Path $blockingFile 'archive.zip') zip } | Should Be $true
    }
}

Describe 'Alle sieben Einstiegsskripte mit isolierten WhatIf-Fixtures' {
    BeforeEach {
        $ctx = New-TestContext 'entry-test'
        $folder = New-TestDirectory (Join-Path $ctx.Fixture 'folder')
        Write-TestFile (Join-Path $folder 'an_image.JPG') 'image'
        [IO.File]::WriteAllBytes("$folder.ico", [byte[]]@(0,0,1,0,1,0,17,18))
        $wrapperLogs = Join-Path $ctx.Fixture 'wrapper-logs'
    }
    It 'führt die vier Symbol-Wrapper ohne Datenänderung aus' {
        foreach ($name in @('Clear Folder.ps1','Clear Folders.ps1','Modify Folder.ps1','Modify Folders.ps1')) {
            & (Join-Path $folderRoot $name) -Path $folder -LogDirectory $wrapperLogs -WhatIf
            $LASTEXITCODE | Should Be 0
        }
        @(Get-ChildItem $folder -Force).Count | Should Be 1
        @(Get-ChildItem $wrapperLogs -Filter '*.log').Count | Should Be 4
        @(Get-ChildItem $wrapperLogs -Directory).Count | Should Be 0
    }
    It 'führt Grafik- und Comic-Wrapper ohne Umbenennung oder Archiv aus' {
        & (Join-Path $fileOpsRoot 'Rename Graphics.ps1') -Path $folder -LogDirectory $wrapperLogs -WhatIf
        $LASTEXITCODE | Should Be 0
        $comics = New-TestDirectory (Join-Path $ctx.Fixture 'comics')
        $comic = New-TestDirectory (Join-Path $comics 'comic')
        Write-TestFile (Join-Path $comic 'page.jpg')
        & (Join-Path $fileOpsRoot 'Make CBR or CBZ.ps1') -Root $comics -ArchiveType zip -NoPause -LogDirectory $wrapperLogs -WhatIf
        $LASTEXITCODE | Should Be 0
        $comicLog = Get-ChildItem $wrapperLogs -Filter 'Make-CBR-or-CBZ-*.log' | Select-Object -First 1
        [IO.File]::ReadAllText($comicLog.FullName) | Should Match 'page.jpg -> .*0001.jpg'
        [IO.File]::Exists((Join-Path $folder 'an_image.JPG')) | Should Be $true
        [IO.File]::Exists((Join-Path $comic 'page.jpg')) | Should Be $true
        @(Get-ChildItem $comics -File).Count | Should Be 0
    }
    It 'führt Backup-Outlook-Vorschau ohne Kopie und ohne Prozessstopp aus' {
        Write-TestFile (Join-Path $folder 'fixture.pst')
        $second = New-TestDirectory (Join-Path $ctx.Fixture 'second')
        Write-TestFile (Join-Path $second 'fixture.ost')
        $backup = Join-Path $ctx.Fixture 'backup'
        & (Join-Path $backupRoot 'Locale Backup.ps1') -BackupPath $backup -Action 8 -OutlookLocalPath $folder -OutlookDocumentsPath $second -LogDirectory $wrapperLogs -WhatIf -NoPause
        $LASTEXITCODE | Should Be 0
        [IO.Directory]::Exists($backup) | Should Be $false
    }
    It 'liefert beim Backup echte globale Ziel- und Abhängigkeitsfehler als Code 1' {
        $blocked = Join-Path $ctx.Fixture 'blocked'
        Write-TestFile $blocked
        & (Join-Path $backupRoot 'Locale Backup.ps1') -BackupPath $blocked -Action B -RarExe 'nonexistent-shell-test-rar.exe' -LogDirectory $wrapperLogs -WhatIf -NoPause
        $LASTEXITCODE | Should Be 1
        & (Join-Path $backupRoot 'Locale Backup.ps1') -BackupPath (Join-Path $ctx.Fixture 'backup') -Action B -RarExe 'nonexistent-shell-test-rar.exe' -LogDirectory $wrapperLogs -WhatIf -NoPause
        $LASTEXITCODE | Should Be 1
    }
    It 'meldet fehlende Zielordner der Mehrfachvariante, verarbeitet aber weitere Fixtures' {
        & (Join-Path $folderRoot 'Clear Folders.ps1') -Path @((Join-Path $ctx.Fixture 'missing'),$folder) -LogDirectory $wrapperLogs -WhatIf
        $LASTEXITCODE | Should Be 2
        $csv = Get-ChildItem $wrapperLogs -Filter '*.csv' | Select-Object -First 1
        $rows = @(Import-Csv $csv.FullName)
        @($rows | Where-Object Status -eq Failed).Count | Should Be 1
        @($rows | Where-Object Status -eq Planned).Count | Should Be 1
    }
    It 'führt beim Dot-Sourcing eines Einstiegsskripts keine Operation oder Protokollierung aus' {
        . (Join-Path $folderRoot 'Clear Folder.ps1') -Path $folder -LogDirectory $wrapperLogs
        [IO.Directory]::Exists($wrapperLogs) | Should Be $false
        [IO.File]::ReadAllText((Join-Path $folder 'an_image.JPG')) | Should Be 'image'
    }
    It 'liefert bei fehlender gemeinsamer Bibliothek einen klaren Fehlercode' {
        $isolated = New-TestDirectory (Join-Path $ctx.Fixture 'missing-dependency')
        $copy = Join-Path $isolated 'Clear Folder.ps1'
        [IO.File]::Copy((Join-Path $folderRoot 'Clear Folder.ps1'), $copy, $false)
        & $copy -Path $folder -LogDirectory $wrapperLogs -WhatIf 2>$null
        $LASTEXITCODE | Should Be 1
        [IO.Directory]::Exists($wrapperLogs) | Should Be $false
    }
}
