#Requires -RunAsAdministrator
<#
    clean-windows.ps1 — frees disk space: temporary files, update caches, error reports and more

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\clean-windows.ps1

    First measures how much each item takes, then asks item by item (arrow-key menus; the default
    comes selected) and only then deletes. At the end, shows how much space was freed on C:.
    Only deletes caches and leftovers that Windows and apps recreate when needed. Files in use are skipped.
    Safe to run as often as you want. Nothing here needs undoing.

    FILE LAYOUT
        1. Helpers ................... prompts, sizes, deleting
        2. Items ..................... what can be cleaned, with size and default answer
        3. Execution ................. measure, ask, clean, report
#>

param(
    [string]$Describe,   # for the panel: measures, writes the items as the page's options and stops
    [string]$Answers     # for the panel: the items turned on there (nothing is asked)
)

$ErrorActionPreference = 'Continue'


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}


#region ==================== PANEL ====================

# Run from the TidyWin panel ($env:TIDYWIN_PANEL = 1): the questions show up in the panel window. Each one
# goes out as a line "##TIDYWIN {json}" and the answer comes back as one JSON line on the standard input.
# Write-Host lines carry their color ([char]1 + color + [char]2 + text) so the panel can show it.
$script:Panel = $env:TIDYWIN_PANEL -eq '1'
$script:PanelLine = ''

function Write-PanelHost {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [switch]$NoNewline,
          [object]$Separator = ' ', [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor)
    $text  = (@($Object) | ForEach-Object { "$_" }) -join "$Separator"
    $color = if ($PSBoundParameters.ContainsKey('ForegroundColor')) { "$ForegroundColor" } else { '' }
    $parts = @($text -split "`r?`n")
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $script:PanelLine += [string][char]1 + $color + [char]2 + $parts[$i]
        if ($i -lt $parts.Count - 1 -or -not $NoNewline) { [Console]::Out.WriteLine($script:PanelLine); $script:PanelLine = '' }
    }
}

# Sends a question to the panel and returns the answer ($null when it was cancelled).
function Request-Panel([hashtable]$Request) {
    if ($script:PanelLine) { [Console]::Out.WriteLine($script:PanelLine); $script:PanelLine = '' }
    [Console]::Out.WriteLine('##TIDYWIN ' + (ConvertTo-Json $Request -Compress -Depth 6))
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { exit 1 }                       # the panel was closed
    return (ConvertFrom-Json $line.Trim([char]0xFEFF)).value
}

if ($script:Panel) {
    function Write-Host {
        param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [switch]$NoNewline,
              [object]$Separator = ' ', [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor)
        Write-PanelHost @PSBoundParameters
    }
    # Typed answers: a "press Enter" pause, a folder, a file or text
    function Read-Host([Parameter(Position = 0)][object]$Prompt) {
        $q = "$Prompt".Trim()
        $type = if ($q -match '(?i)press Enter') { 'wait' } elseif ($q -match '(?i)^folder') { 'folder' } elseif ($q -match '(?i)\.json file') { 'file' } else { 'text' }
        return "$(Request-Panel @{ type = $type; question = $q })"
    }
}

# --- Options of a page in the panel (the same in every script). A field: tab, id, kind (toggle, choice,
# select, checklist, text, header), label, desc, default and more (options, items, warn, when...).
# -Describe writes the fields for the panel's page; Read-Options brings back what was chosen: the panel's
# answers file, or asked here when the script runs on its own. Nothing comes selected.
function Opt($Value, [string]$Label) { [ordered]@{ value = $Value; label = $Label } }

function New-Field([string]$Tab, [string]$Id, [string]$Kind, [string]$Label, [string]$Desc, $Default, [hashtable]$More) {
    $f = [ordered]@{ tab = $Tab; id = $Id; kind = $Kind; label = $Label; desc = $Desc; default = $Default }
    if ($More) { foreach ($k in $More.Keys) { $f[$k] = $More[$k] } }
    return $f
}

function Write-OptionsPage([string]$Path, [object[]]$Fields, [string[]]$Notes) {
    $page = [ordered]@{ tabs = @($Fields | ForEach-Object { $_.tab } | Select-Object -Unique); notes = @($Notes | Where-Object { $_ }); fields = @($Fields | Where-Object { $_ }) }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json $page -Depth 10), (New-Object Text.UTF8Encoding $false))
}

function Read-Options([object[]]$Fields, [string]$AnswersFile) {
    $values = @{}
    foreach ($f in $Fields) { if ($f.kind -ne 'header') { $values[$f.id] = $f.default } }
    if ($AnswersFile) {
        $json = [IO.File]::ReadAllText($AnswersFile) | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) { $values[$prop.Name] = $prop.Value }
        return $values
    }
    foreach ($f in $Fields) {
        if ($f.when -and "$($values[$f.when.field])" -ne "$($f.when.is)") { continue }
        switch ($f.kind) {
            'header'    { Write-Host "`n  $($f.label)" -ForegroundColor Cyan }
            'toggle'    { $values[$f.id] = Ask "$($f.label)?" $false }
            'info'      { Write-Host "  $($f.label): $($f.desc)" -ForegroundColor DarkGray }
            { $_ -in 'text', 'path' } { $values[$f.id] = "$(Read-Host "  $($f.label)")".Trim().Trim('"') }
            'checklist' { $values[$f.id] = @($f.items | Where-Object { Ask "$($f.label): $($_.label)?" $false } | ForEach-Object { $_.value }) }
            default {
                # choice and select; "Skip" leaves it as it is
                $options = @(Opt '' 'Skip') + @($f.options)
                $values[$f.id] = $options[(Choose "$($f.label):" @($options | ForEach-Object { $_.label }) 0)].value
            }
        }
    }
    return $values
}

# Yes / No (scripts that ask more define their own, the same)
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

#endregion

#region ==================== 1. HELPERS ====================


function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    if ($script:Panel) { return [int](Request-Panel @{ type = 'choose'; question = $Question; options = @($Options); default = $Default }) }
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host "  Number [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host "  Type a number from 1 to $($Options.Count)." -ForegroundColor DarkYellow
        }
    }
    if (-not $script:ArrowHintShown) {
        Write-Host '  (use the arrows ↑ ↓ and Enter)' -ForegroundColor DarkGray
        $script:ArrowHintShown = $true
    }
    foreach ($o in $Options) { Write-Host '' }                # reserve the menu lines
    $top = [Console]::CursorTop - $Options.Count
    $selected = $Default
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Options.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                $marker = if ($i -eq $selected) { '  > ' } else { '    ' }
                $line = ($marker + $Options[$i]).PadRight([Console]::WindowWidth - 1)
                if ($i -eq $selected) { Write-Host $line -ForegroundColor Cyan -NoNewline } else { Write-Host $line -NoNewline }
            }
            $key = [Console]::ReadKey($true).Key
            if     ($key -eq 'UpArrow')   { $selected = ($selected - 1 + $Options.Count) % $Options.Count }
            elseif ($key -eq 'DownArrow') { $selected = ($selected + 1) % $Options.Count }
            elseif ($key -eq 'Enter')     { break }
        }
    } finally {
        [Console]::SetCursorPosition(0, $top + $Options.Count)
        [Console]::CursorVisible = $true
    }
    return $selected
}

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Asked here, before the items below are defined, because their names and notes are picked at load time.

# Bytes → "3,4 GB", "250 MB"... Sizes use 1024, like File Explorer.
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$([int]$Bytes) B"
}

# Total size of the files in these paths (folders are read recursively; wildcards allowed).
function Get-Size([string[]]$Paths) {
    $sum = 0
    foreach ($path in $Paths) {
        $sum += (Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
    }
    [double]$sum
}

# Deletes what is INSIDE each folder (the folder itself stays). Files in use are skipped.
function Clear-Folder([string[]]$Paths) {
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) { continue }
        Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-FreeSpace { [double](Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free }

#endregion


#region ==================== 2. ITEMS ====================

$WinDir  = $env:SystemRoot
$Thumbs  = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$DOCache = "$WinDir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
$WinOld  = "$env:SystemDrive\Windows.old"
$Reports = @(
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
    "$env:ProgramData\Microsoft\Windows\WER\Temp",
    "$env:LOCALAPPDATA\CrashDumps",
    "$WinDir\Minidump",
    "$WinDir\LiveKernelReports"
)

# Windows Update busy? Cleaning its downloads (or running DISM) in the middle of an install can make
# that update fail. Returns the reason, or nothing when it is safe.
function Get-UpdateBusyReason {
    $wu  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $cbs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if ((Test-Path $wu) -or (Test-Path $cbs))             { return 'an update is waiting for the PC to restart' }
    if (Get-Process TiWorker -ErrorAction SilentlyContinue) { return 'Windows is installing updates right now' }
}

# Recycle Bin size, from the shell (covers every drive).
function Get-RecycleBinSize {
    $sum = 0
    try { foreach ($item in (New-Object -ComObject Shell.Application).NameSpace(10).Items()) { $sum += $item.Size } } catch { }
    [double]$sum
}

# Name: shown in the menu. Size: scriptblock that measures (or $null when it can't be measured beforehand).
# Default: suggested answer. Note: shown under the question. Clean: what is done.
# Present: only listed when it returns true. Blocked: returns a reason to skip it right now.
$Items = @(
    @{
        Id = 'UserTemp'; Name = 'Your user temporary files'; Default = $true
        Note = '%TEMP% folder. Apps recreate whatever they need.'
        Size = { Get-Size @($env:TEMP) }
        Clean = { Clear-Folder @($env:TEMP) }
    }
    @{
        Id = 'WindowsTemp'; Name = 'Windows temporary files'; Default = $true
        Note = 'C:\Windows\Temp folder.'
        Size = { Get-Size @("$WinDir\Temp") }
        Clean = { Clear-Folder @("$WinDir\Temp") }
    }
    @{
        Id = 'UpdateDownloads'; Name = 'Windows Update downloads'; Default = $true
        Note = 'Updates already installed. If one is half done, Windows downloads it again.'
        Blocked = { Get-UpdateBusyReason }
        Size = { Get-Size @("$WinDir\SoftwareDistribution\Download") }
        Clean = {
            Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            Clear-Folder @("$WinDir\SoftwareDistribution\Download")
            Start-Service wuauserv, bits -ErrorAction SilentlyContinue
        }
    }
    @{
        Id = 'DeliveryCache'; Name = 'Delivery Optimization cache'; Default = $true
        Note = 'Copies of updates kept to share with other PCs.'
        Size = { Get-Size @($DOCache) }
        Clean = {
            try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }
            catch { Clear-Folder @($DOCache) }
        }
    }
    @{
        Id = 'Reports'; Name = 'Error reports and memory dumps'; Default = $true
        Note = 'Crash reports from apps and blue screens. Only useful to investigate a problem that already happened.'
        Size = { Get-Size ($Reports + "$WinDir\MEMORY.DMP") }
        Clean = {
            Clear-Folder $Reports
            Remove-Item "$WinDir\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
        }
    }
    @{
        Id = 'Thumbnails'; Name = 'Thumbnail and icon cache'; Default = $false
        Note = 'Windows recreates it; folders with many images open more slowly the first time. File Explorer restarts briefly.'
        Size = { Get-Size @("$Thumbs\thumbcache_*.db", "$Thumbs\iconcache_*.db") }
        Clean = {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Remove-Item "$Thumbs\thumbcache_*.db", "$Thumbs\iconcache_*.db" -Force -ErrorAction SilentlyContinue
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        }
    }
    @{
        Id = 'RecycleBin'; Name = 'Recycle Bin'; Default = $false
        Note = 'Permanently deletes what is in the Recycle Bin, on every drive.'
        Size = { Get-RecycleBinSize }
        Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
    }
    @{
        Id = 'Components'; Name = 'Old Windows components'; Default = $false
        Note = 'Old versions of system files left behind by updates (DISM). Safe, but can take several minutes.'
        Blocked = { Get-UpdateBusyReason }
        Size = $null
        Clean = { & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null }
    }
    @{
        Id = 'WindowsOld'; Name = 'Windows.old (previous installation)'; Default = $false
        Note = 'After deleting it, you can no longer go back to the previous version of Windows. Any of your files left there are gone too.'
        Present = { Test-Path $WinOld }
        Size = { Get-Size @($WinOld) }
        Clean = {
            & takeown.exe /F $WinOld /R /A /D Y 2>&1 | Out-Null
            & icacls.exe $WinOld /grant '*S-1-5-32-544:F' /T /C /Q 2>&1 | Out-Null   # Administrators, any language
            & cmd.exe /c rd /s /q `"$WinOld`" 2>&1 | Out-Null                       # handles long paths and links
        }
    }
)

#endregion


#region ==================== 3. EXECUTION ====================

if (-not $script:Panel) { Write-Host "`nClean-Windows" -ForegroundColor Green }   # in the panel the page already has the title

# --- Measure
Write-Step 'Measuring what can be cleaned'
$Items = @($Items | Where-Object { -not $_.Present -or (& $_.Present) })
foreach ($item in $Items) {
    $item.Bytes = if ($item.Size) { & $item.Size } else { $null }
    $shown = if ($null -eq $item.Bytes) { '?' } else { Format-Size $item.Bytes }
    Write-Host ('  {0,-44} {1,10}' -f $item.Name, $shown)
}

# --- Ask (items with nothing to clean are skipped). In the panel: a switch per item, all off
$Items = @($Items | Where-Object { $null -eq $_.Bytes -or $_.Bytes -ge 1MB })
foreach ($item in $Items) { $item.Reason = if ($item.Blocked) { & $item.Blocked } }
if ($Describe) {
    $fields = @(foreach ($item in $Items) {
        $badge = if ($null -eq $item.Bytes) { '' } else { Format-Size $item.Bytes }
        $warn  = if ($item.Reason) { "Not now: $($item.Reason). Restart the PC and try again." } else { '' }
        New-Field 'Clean' $item.Id 'toggle' $item.Name $item.Note $false @{ badge = $badge; warn = $warn }
    })
    if (-not $fields) { $fields = @(New-Field 'Clean' 'Nothing' 'header' 'Nothing to clean' 'There is nothing worth deleting on this PC right now.' $null) }
    Write-OptionsPage $Describe $fields
    return
}
$chosen = @()
if ($Answers) {
    $v = ([IO.File]::ReadAllText($Answers) | ConvertFrom-Json)
    foreach ($item in $Items) {
        if (-not $v.($item.Id)) { continue }
        if ($item.Reason) { Write-Host "  Skipped: $($item.Name) — $($item.Reason). Restart the PC and run again." -ForegroundColor DarkYellow; continue }
        $chosen += $item
    }
} else {
    Write-Step 'What to clean'
    Write-Host '  The default answer comes selected.'
    foreach ($item in $Items) {
        if ($item.Reason) {
            Write-Host ''
            Write-Host "  Skipped: $($item.Name) — $($item.Reason). Restart the PC and run again." -ForegroundColor DarkYellow
            continue
        }
        Write-Host ''
        Write-Host "  $($item.Note)" -ForegroundColor DarkGray
        $size = if ($null -eq $item.Bytes) { '' } else { " ($(Format-Size $item.Bytes))" }
        if (Ask "Clean: $($item.Name)$size?" $item.Default) { $chosen += $item }
    }
}
if (-not $chosen) { Write-Host "`nNothing was deleted."; return }
# --- Clean
$freeBefore = Get-FreeSpace
foreach ($item in $chosen) {
    Write-Step $item.Name
    try { & $item.Clean; Write-Host '  Done' }
    catch { Write-Warning "Failed: $($_.Exception.Message)" }
}

# --- Report
$freed = (Get-FreeSpace) - $freeBefore
Write-Host ''
if ($freed -gt 0) { Write-Host "Done. Space freed on $($env:SystemDrive): $(Format-Size $freed)." -ForegroundColor Green }
else              { Write-Host 'Done.' -ForegroundColor Green }
Write-Host 'Files in use were skipped; restart the PC and run again to get the rest.' -ForegroundColor DarkGray

#endregion
