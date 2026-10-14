#Requires -RunAsAdministrator
<#
    Repair-Windows.ps1 — checks and repairs Windows system files and the disk, with Windows' own tools

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Repair-Windows.ps1

    Use it when Windows acts strange: errors opening Settings or the Start menu, updates that keep
    failing, apps from Windows crashing. In order:
        1. Restore point ........ before anything
        2. Windows image ........ checks the component store (DISM) and, if it is damaged, repairs it
                                  with clean copies from Windows Update
        3. System files ......... sfc /scannow: replaces damaged system files with the copies from step 2
        4. Disk ................. online check of C: (no restart). If errors show up, asks before
                                  scheduling the fix for the next restart (a few seconds)
    Only Microsoft's own repair tools. Does not delete your files, apps or settings, does not clean
    the registry, does not use /ResetBase. Takes 10 to 30 minutes; the PC can be used meanwhile.
    Leaves nothing behind. Safe to run more than once.

    FILE LAYOUT
        1. Helpers
        2. Steps
        3. Execution
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


# $Status is a language-independent key (OK / FIXED / WARN / ERROR) that picks the color; the tag shown is translated.
function Write-Result([ValidateSet('OK', 'FIXED', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $color = @{ OK = 'Green'; FIXED = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }[$Status]
    $label = @{ OK = 'OK'; FIXED = 'FIXED'; WARN = 'WARNING'; ERROR = 'ERROR' }[$Status]
    Write-Host ("  [{0}] " -f $label) -ForegroundColor $color -NoNewline
    Write-Host $Text
}

function Test-PendingReboot {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

#endregion


#region ==================== 2. STEPS ====================

# Summary lines shown at the end, and a language-independent status per line for the final message:
# Ok = no problem, Fixed = repaired or fix scheduled (needs a restart), Issue = anything else.
$script:Summary = @()
$script:SummaryStatus = @()
function Add-Summary([string]$Text, [ValidateSet('Ok', 'Fixed', 'Issue')][string]$Status) {
    $script:Summary += $Text
    $script:SummaryStatus += $Status
}

function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Before Repair-Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Result 'OK' 'restore point created'
        return $true
    } catch {
        Write-Result 'WARN' "could not create the restore point ($($_.Exception.Message.Trim()))"
        return (Ask 'Continue anyway? (the repairs only use Windows'' own tools)' $false)
    }
}

# DISM through its PowerShell cmdlet: the result (Healthy / Repairable / NonRepairable) does not depend
# on the Windows language. ScanHealth only reads; RestoreHealth downloads clean copies from Windows Update.
function Repair-Image {
    Write-Host '  checking (a few minutes; the progress bar may stall for a while, that is normal)...' -ForegroundColor DarkGray
    try { $scan = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop }
    catch { Write-Result 'ERROR' "the check failed: $($_.Exception.Message.Trim())"; Add-Summary 'Windows image: check failed' 'Issue'; return }

    switch ("$($scan.ImageHealthState)") {
        'Healthy' {
            Write-Result 'OK' 'Windows image has no problems'
            Add-Summary 'Windows image: OK' 'Ok'
        }
        'Repairable' {
            Write-Host '  problems found; repairing with copies from Windows Update...' -ForegroundColor DarkGray
            try {
                $fix = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
                if ("$($fix.ImageHealthState)" -eq 'Healthy') {
                    Write-Result 'FIXED' 'Windows image repaired'
                    Add-Summary 'Windows image: repaired' 'Fixed'
                } else {
                    Write-Result 'WARN' "the repair finished, but the state is: $($fix.ImageHealthState)"
                    Add-Summary 'Windows image: repair incomplete' 'Issue'
                }
            } catch {
                Write-Result 'ERROR' "the repair failed: $($_.Exception.Message.Trim()). Check the internet connection and Windows Update and try again."
                Add-Summary 'Windows image: repair failed' 'Issue'
            }
        }
        default {
            Write-Result 'ERROR' 'the Windows image is too damaged to repair from here. The way forward is "Fix problems using Windows Update" in Settings > System > Recovery, which reinstalls Windows keeping your files and apps.'
            Add-Summary 'Windows image: not repairable from here' 'Issue'
        }
    }
}

# sfc prints in UTF-16, which Windows PowerShell shows with spaces between letters; the output
# encoding is switched while it runs. The final message is Windows' own, in its language.
# The result comes from the exit code and from the [SR] lines it writes in CBS.log (always in English).
function Repair-SystemFiles {
    Write-Host '  checking (about 10 minutes)...' -ForegroundColor DarkGray
    $start = Get-Date
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $output = & sfc.exe /scannow 2>&1 | Where-Object { "$_".Trim() }
    } finally {
        [Console]::OutputEncoding = $previous
    }
    $output | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

    $log = "$env:SystemRoot\Logs\CBS\CBS.log"
    $sr = @()
    if (Test-Path $log) {
        $sr = @(Select-String -Path $log -Pattern '[SR]' -SimpleMatch -ErrorAction SilentlyContinue | ForEach-Object { $_.Line } | Where-Object {
            $_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})' -and [datetime]$Matches[1] -ge $start.AddSeconds(-5)
        })
    }
    $repaired = @($sr | Where-Object { $_ -match 'Repair complete|Repairing corrupted file' }).Count
    $failed   = @($sr | Where-Object { $_ -match 'Cannot repair' }).Count

    if ($failed) {
        Write-Result 'WARN' "$failed file(s) could not be repaired. Restart the PC and run the repair again."
        Add-Summary 'System files: some not repaired' 'Issue'
    } elseif ($repaired) {
        Write-Result 'FIXED' 'damaged system files were replaced. Restart the PC.'
        Add-Summary 'System files: repaired' 'Fixed'
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Result 'OK' 'system files have no problems'
        Add-Summary 'System files: OK' 'Ok'
    } else {
        Write-Result 'WARN' 'sfc did not finish normally; see the message above.'
        Add-Summary 'System files: check incomplete' 'Issue'
    }
}

# Online scan of the system drive: reads only, works while Windows runs. If errors show up, the fix
# (SpotFix) needs the drive offline, so it is only scheduled for the next restart if you agree.
function Repair-Disk {
    $letter = $env:SystemDrive.TrimEnd(':')
    Write-Host "  checking drive $($letter): (may take a few minutes)..." -ForegroundColor DarkGray
    try { $result = "$(Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop)" }
    catch { Write-Result 'ERROR' "the check failed: $($_.Exception.Message.Trim())"; Add-Summary 'Disk: check failed' 'Issue'; return }

    if ($result -eq 'NoErrorsFound') {
        Write-Result 'OK' "drive $($letter): no errors"
        Add-Summary 'Disk: OK' 'Ok'
        return
    }
    Write-Result 'WARN' "errors were found on drive $($letter): ($result)"
    # SpotFixNeeded: quick fix at the next restart. Anything else: full offline check (can take a while at startup).
    $quick = $result -eq 'SpotFixNeeded'
    $how = if ($quick) { 'takes a few seconds at startup' } else { 'startup may take several minutes' }
    if (Ask "Schedule the fix for the next time the PC restarts? ($how)" $true) {
        try {
            if ($quick) { Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop | Out-Null }
            else        { Repair-Volume -DriveLetter $letter -OfflineScanAndFix -ErrorAction Stop | Out-Null }
            Write-Result 'OK' 'fix scheduled; restart the PC'
            Add-Summary 'Disk: fix scheduled for the next restart' 'Fixed'
        } catch {
            Write-Result 'ERROR' "could not schedule it: $($_.Exception.Message.Trim())"
            Add-Summary 'Disk: errors found, fix not scheduled' 'Issue'
        }
    } else {
        Add-Summary 'Disk: errors found, fix not scheduled' 'Issue'
    }
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Host "`nRepair-Windows" -ForegroundColor Green
Write-Host '  Checks and repairs the Windows image, the system files and the disk, with Windows'' own tools.'
Write-Host '  Takes 10 to 30 minutes. You can use the PC meanwhile; leave the window open.' -ForegroundColor DarkGray

if (Test-PendingReboot) {
    Write-Host ''
    Write-Result 'WARN' 'an update is waiting for the PC to restart; the repairs may fail until then.'
    if (-not (Ask 'Continue anyway? (restarting first is recommended)' $false)) { Write-Host 'Nothing was done. Restart the PC and run again.'; return }
}
Write-Host ''
if (-not (Ask 'Start?' $true)) { Write-Host 'Nothing was done.'; return }

Write-Step '1/4 Restore point'
if (-not (New-RestorePoint)) { Write-Host 'Nothing was done.'; return }

Write-Step '2/4 Windows image (DISM)'
Repair-Image

Write-Step '3/4 System files (sfc)'
Repair-SystemFiles

Write-Step '4/4 Disk'
Repair-Disk

Write-Step 'Summary'
$script:Summary | ForEach-Object { Write-Host "  $_" }
$allOk = -not ($script:SummaryStatus | Where-Object { $_ -ne 'Ok' })
if ($allOk) { Write-Host "`nNo problems found." -ForegroundColor Green }
elseif ($script:SummaryStatus -contains 'Fixed') { Write-Host "`nRestart the computer to finish." -ForegroundColor Yellow }
else { Write-Host "`nSome items were not resolved; see the messages above." -ForegroundColor Yellow }

#endregion
