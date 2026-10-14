#Requires -RunAsAdministrator
<#
    repair-windows.ps1 — checks and repairs Windows system files and the disk, with Windows' own tools

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\repair-windows.ps1

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
    [string]$Describe,   # for the panel: writes the options of the page to this file and stops
    [string]$Answers     # for the panel: what was turned on there (nothing is asked)
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
        # Windows creates at most one a day (otherwise it only warns): compare the newest point before and after
        $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
        Checkpoint-Computer -Description 'Before Repair-Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
        if ($after -and (-not $before -or $after.SequenceNumber -ne $before.SequenceNumber)) { Write-Result 'OK' 'Restore point created' }
        elseif ($after) {
            Write-Result 'OK' "Using the restore point from $($after.ConvertToDateTime($after.CreationTime).ToString('g'))."
            Write-Host '  Windows creates at most one restore point a day.' -ForegroundColor Yellow
        } else { throw 'System Restore did not create it' }
        return $true
    } catch {
        Write-Result 'WARN' "Could not create the restore point ($($_.Exception.Message.Trim()))"
        if ($script:Opt.Contains('NoRestorePoint')) { if (-not $script:Opt.NoRestorePoint) { Write-Host '  Nothing was done: turn on "Go on without a restore point" to repair anyway.' }; return [bool]$script:Opt.NoRestorePoint }
        return (Ask 'Continue anyway? (the repairs only use Windows'' own tools)' $false)
    }
}

# DISM through its PowerShell cmdlet: the result (Healthy / Repairable / NonRepairable) does not depend
# on the Windows language. ScanHealth only reads; RestoreHealth downloads clean copies from Windows Update.
function Repair-Image {
    Write-Host '  Checking...'; Write-Host '  It takes a few minutes. The progress bar may stall for a while; that is normal.' -ForegroundColor DarkGray
    try { $scan = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop }
    catch { Write-Result 'ERROR' "The check failed: $($_.Exception.Message.Trim())"; Add-Summary 'Windows image: check failed' 'Issue'; return }

    switch ("$($scan.ImageHealthState)") {
        'Healthy' {
            Write-Result 'OK' 'Windows image has no problems'
            Add-Summary 'Windows image: OK' 'Ok'
        }
        'Repairable' {
            Write-Host '  Problems found; repairing with copies from Windows Update...' -ForegroundColor DarkGray
            try {
                $fix = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
                if ("$($fix.ImageHealthState)" -eq 'Healthy') {
                    Write-Result 'FIXED' 'Windows image repaired'
                    Add-Summary 'Windows image: repaired' 'Fixed'
                } else {
                    Write-Result 'WARN' "The repair finished, but the state is: $($fix.ImageHealthState)"
                    Add-Summary 'Windows image: repair incomplete' 'Issue'
                }
            } catch {
                Write-Result 'ERROR' "The repair failed: $($_.Exception.Message.Trim()). Check the internet connection and Windows Update and try again."
                Add-Summary 'Windows image: repair failed' 'Issue'
            }
        }
        default {
            Write-Result 'ERROR' 'The Windows image is too damaged to repair from here. The way forward is "Fix problems using Windows Update" in Settings > System > Recovery, which reinstalls Windows keeping your files and apps.'
            Add-Summary 'Windows image: not repairable from here' 'Issue'
        }
    }
}

# sfc prints in UTF-16, which Windows PowerShell shows with spaces between letters; the output
# encoding is switched while it runs. The final message is Windows' own, in its language.
# The result comes from the exit code and from the [SR] lines it writes in CBS.log (always in English).
function Repair-SystemFiles {
    Write-Host '  Checking...'; Write-Host '  It takes about 10 minutes.' -ForegroundColor DarkGray
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
        Write-Result 'FIXED' 'Damaged system files were replaced. Restart the PC.'
        Add-Summary 'System files: repaired' 'Fixed'
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Result 'OK' 'System files have no problems'
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
    Write-Host "  Checking drive $($letter):..."; Write-Host '  It may take a few minutes.' -ForegroundColor DarkGray
    try { $result = "$(Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop)" }
    catch { Write-Result 'ERROR' "The check failed: $($_.Exception.Message.Trim())"; Add-Summary 'Disk: check failed' 'Issue'; return }

    if ($result -eq 'NoErrorsFound') {
        Write-Result 'OK' "Drive $($letter): no errors"
        Add-Summary 'Disk: OK' 'Ok'
        return
    }
    Write-Result 'WARN' "Errors were found on drive $($letter): ($result)"
    # SpotFixNeeded: quick fix at the next restart. Anything else: full offline check (can take a while at startup).
    $quick = $result -eq 'SpotFixNeeded'
    $how = if ($quick) { 'takes a few seconds at startup' } else { 'startup may take several minutes' }
    $schedule = if ($script:Opt.Contains('DiskFix')) { [bool]$script:Opt.DiskFix } else { Ask "Schedule the fix for the next time the PC restarts? ($how)" $true }
    if ($schedule) {
        try {
            if ($quick) { Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop | Out-Null }
            else        { Repair-Volume -DriveLetter $letter -OfflineScanAndFix -ErrorAction Stop | Out-Null }
            Write-Result 'OK' 'Fix scheduled; restart the PC'
            Add-Summary 'Disk: fix scheduled for the next restart' 'Fixed'
        } catch {
            Write-Result 'ERROR' "Could not schedule it: $($_.Exception.Message.Trim())"
            Add-Summary 'Disk: errors found, fix not scheduled' 'Issue'
        }
    } else {
        Add-Summary 'Disk: errors found, fix not scheduled' 'Issue'
    }
}

#endregion


#region ==================== 3. EXECUTION ====================

# --- Options: the panel's page, or asked here. Nothing comes selected.
$T = 'Repair'
$fields = @(
    New-Field $T 'Image' 'toggle' 'Repair the Windows image' 'Checks the copies Windows repairs itself from (DISM) and, if they are damaged, downloads clean ones from Windows Update. A few minutes.' $false
    New-Field $T 'SystemFiles' 'toggle' 'Repair the system files' 'Replaces damaged Windows files with clean copies (sfc). About 10 minutes; best together with the image repair.' $false
    New-Field $T 'Disk' 'toggle' 'Check the disk' "Looks for errors on drive $($env:SystemDrive) while Windows runs. A few minutes." $false
    New-Field $T 'DiskFix' 'toggle' 'Fix disk errors at the next restart' 'Only if the check finds errors. A quick fix takes seconds at startup; a full one can take several minutes.' $false @{ when = @{ field = 'Disk'; is = 'True' } }
    New-Field $T 'NoRestorePoint' 'toggle' 'Go on without a restore point' 'A restore point is created first. If Windows can''t create one, the repairs only run with this on. They only use Windows'' own tools.' $false
)
$notes = @(if (Test-PendingReboot) { 'An update is waiting for the PC to restart: restart first, the repairs may fail until then.' })
if ($Describe) { Write-OptionsPage $Describe $fields $notes; return }

if (-not $script:Panel) { Write-Host "`nRepair-Windows" -ForegroundColor Green }   # in the panel the page already has the title
if ($Answers) {
    $script:Opt = Read-Options $fields $Answers
} else {
    Write-Host '  Checks and repairs the Windows image, the system files and the disk, with Windows'' own tools.'
    Write-Host '  Takes 10 to 30 minutes. You can use the PC meanwhile; leave the window open.' -ForegroundColor DarkGray
    if (Test-PendingReboot) {
        Write-Host ''
        Write-Result 'WARN' 'An update is waiting for the PC to restart; the repairs may fail until then.'
        if (-not (Ask 'Continue anyway? (restarting first is recommended)' $false)) { Write-Host 'Nothing was done. Restart the PC and run again.'; return }
    }
    Write-Host ''
    if (-not (Ask 'Start?' $true)) { Write-Host 'Nothing was done.'; return }
    $script:Opt = @{ Image = $true; SystemFiles = $true; Disk = $true }      # on its own it does everything, asking as it goes
}
if (-not ($script:Opt.Image -or $script:Opt.SystemFiles -or $script:Opt.Disk)) { Write-Host 'Nothing was selected, so nothing was done.'; return }
if ($Answers -and (Test-PendingReboot)) { Write-Result 'WARN' 'An update is waiting for the PC to restart; the repairs may fail until then.' }

$steps = @('Restore point') + @(if ($script:Opt.Image) { 'Windows image (DISM)' }) + @(if ($script:Opt.SystemFiles) { 'System files (sfc)' }) + @(if ($script:Opt.Disk) { 'Disk' })
$n = 0
$n++; Write-Step "$n/$($steps.Count) Restore point"
if (-not (New-RestorePoint)) { Write-Host 'Nothing was done.'; return }
if ($script:Opt.Image)       { $n++; Write-Step "$n/$($steps.Count) Windows image (DISM)"; Repair-Image }
if ($script:Opt.SystemFiles) { $n++; Write-Step "$n/$($steps.Count) System files (sfc)"; Repair-SystemFiles }
if ($script:Opt.Disk)        { $n++; Write-Step "$n/$($steps.Count) Disk"; Repair-Disk }
Write-Step 'Summary'
$script:Summary | ForEach-Object { Write-Host "  $_" }
$allOk = -not ($script:SummaryStatus | Where-Object { $_ -ne 'Ok' })
if ($allOk) { Write-Host "`nNo problems found." -ForegroundColor Green }
elseif ($script:SummaryStatus -contains 'Fixed') { Write-Host "`nRestart the computer to finish." -ForegroundColor Yellow }
else { Write-Host "`nSome items were not resolved; see the messages above." -ForegroundColor Yellow }

#endregion
