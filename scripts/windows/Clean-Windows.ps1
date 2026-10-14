#Requires -RunAsAdministrator
<#
    Clean-Windows.ps1 — frees disk space: temporary files, update caches, error reports and more

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Clean-Windows.ps1

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
)

$ErrorActionPreference = 'Continue'


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}


#region ==================== 1. HELPERS ====================


function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
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
        Name = 'Your user temporary files'; Default = $true
        Note = '%TEMP% folder. Apps recreate whatever they need.'
        Size = { Get-Size @($env:TEMP) }
        Clean = { Clear-Folder @($env:TEMP) }
    }
    @{
        Name = 'Windows temporary files'; Default = $true
        Note = 'C:\Windows\Temp folder.'
        Size = { Get-Size @("$WinDir\Temp") }
        Clean = { Clear-Folder @("$WinDir\Temp") }
    }
    @{
        Name = 'Windows Update downloads'; Default = $true
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
        Name = 'Delivery Optimization cache'; Default = $true
        Note = 'Copies of updates kept to share with other PCs.'
        Size = { Get-Size @($DOCache) }
        Clean = {
            try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }
            catch { Clear-Folder @($DOCache) }
        }
    }
    @{
        Name = 'Error reports and memory dumps'; Default = $true
        Note = 'Crash reports from apps and blue screens. Only useful to investigate a problem that already happened.'
        Size = { Get-Size ($Reports + "$WinDir\MEMORY.DMP") }
        Clean = {
            Clear-Folder $Reports
            Remove-Item "$WinDir\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
        }
    }
    @{
        Name = 'Thumbnail and icon cache'; Default = $false
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
        Name = 'Recycle Bin'; Default = $false
        Note = 'Permanently deletes what is in the Recycle Bin, on every drive.'
        Size = { Get-RecycleBinSize }
        Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
    }
    @{
        Name = 'Old Windows components'; Default = $false
        Note = 'Old versions of system files left behind by updates (DISM). Safe, but can take several minutes.'
        Blocked = { Get-UpdateBusyReason }
        Size = $null
        Clean = { & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null }
    }
    @{
        Name = 'Windows.old (previous installation)'; Default = $false
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

Write-Host "`nClean-Windows" -ForegroundColor Green

# --- Measure
Write-Step 'Measuring what can be cleaned'
$Items = @($Items | Where-Object { -not $_.Present -or (& $_.Present) })
foreach ($item in $Items) {
    $item.Bytes = if ($item.Size) { & $item.Size } else { $null }
    $shown = if ($null -eq $item.Bytes) { '?' } else { Format-Size $item.Bytes }
    Write-Host ('  {0,-44} {1,10}' -f $item.Name, $shown)
}

# --- Ask (items with nothing to clean are skipped)
Write-Step 'What to clean'
Write-Host '  The default answer comes selected.'
$chosen = @()
foreach ($item in $Items) {
    if ($null -ne $item.Bytes -and $item.Bytes -lt 1MB) { continue }
    $reason = if ($item.Blocked) { & $item.Blocked }
    if ($reason) {
        Write-Host ''
        Write-Host "  Skipped: $($item.Name) — $reason. Restart the PC and run again." -ForegroundColor DarkYellow
        continue
    }
    Write-Host ''
    Write-Host "  $($item.Note)" -ForegroundColor DarkGray
    $size = if ($null -eq $item.Bytes) { '' } else { " ($(Format-Size $item.Bytes))" }
    if (Ask "Clean: $($item.Name)$size?" $item.Default) { $chosen += $item }
}
if (-not $chosen) { Write-Host "`nNothing was deleted."; return }

# --- Clean
$freeBefore = Get-FreeSpace
foreach ($item in $chosen) {
    Write-Step $item.Name
    try { & $item.Clean; Write-Host '  done' }
    catch { Write-Warning "Failed: $($_.Exception.Message)" }
}

# --- Report
$freed = (Get-FreeSpace) - $freeBefore
Write-Host ''
if ($freed -gt 0) { Write-Host "Done. Space freed on $($env:SystemDrive): $(Format-Size $freed)." -ForegroundColor Green }
else              { Write-Host 'Done.' -ForegroundColor Green }
Write-Host 'Files in use were skipped; restart the PC and run again to get the rest.' -ForegroundColor DarkGray

#endregion
