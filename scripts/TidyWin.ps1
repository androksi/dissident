#Requires -RunAsAdministrator
<#
    TidyWin.ps1 — the TidyWin menu: pick what to do and the matching script runs

    HOW TO RUN:
        irm androksi.github.io/tidywin/run | iex          (the launcher asks for administrator rights)
    or from a copy of the repository (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\scripts\TidyWin.ps1

    Each choice downloads its script from the site (or uses the local copy next to this file, when there
    is one), runs it, and comes back to the menu. Esc closes it.
    Every script asks before changing anything.

    To add an option: one line in $Menu (section 2), with the same name the site uses (web/index.html).

    FILE LAYOUT
        1. Helpers
        2. Menu items
        3. Menu screen
        4. Execution
#>
param(
    [string]$Base = 'https://androksi.github.io/tidywin'      # where the scripts are published (GitHub Pages)
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


#region ==================== 1. HELPERS ====================


# Windows name and version for the menu header.
function Get-WindowsLabel {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $name = "$($cv.ProductName)" -replace '^Microsoft\s+', ''
    if ([int]$cv.CurrentBuild -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }   # Windows 11 still says 10 here
    return "$name $($cv.DisplayVersion)".Trim()
}

# Splits a description into lines that fit the window (the menu shows two at most).
function Split-Text([string]$Text, [int]$Width) {
    $lines = @(); $line = ''
    foreach ($word in ($Text -split '\s+')) {
        if (($line.Length + $word.Length + 1) -gt $Width -and $line) { $lines += $line; $line = $word }
        else { $line = ("$line $word").Trim() }
    }
    if ($line) { $lines += $line }
    return $lines
}

#endregion


#region ==================== 2. MENU ITEMS ====================

# One script to run: path under scripts/, arguments, and a name (shown when an option has several steps).
function New-Step($Script, $ScriptArgs, $Name) {
    [pscustomobject]@{ Script = $Script; Args = @($ScriptArgs | Where-Object { $_ }); Name = $Name }
}

# Group, Id (the name used on the site), Script (path under scripts/), Args, Name and Desc in both languages.
function New-MenuItem($Group, $Id, $Script, $ScriptArgs, $Name, $Desc) {
    [pscustomobject]@{ Group = $Group; Id = $Id; Steps = @(New-Step $Script $ScriptArgs ''); Name = $Name; Desc = $Desc }
}

# An option that runs several scripts in order (each one can be skipped).
function New-MenuSequence($Group, $Id, [object[]]$Steps, $Name, $Desc) {
    [pscustomobject]@{ Group = $Group; Id = $Id; Steps = $Steps; Name = $Name; Desc = $Desc }
}

function Get-Menu {
    $setup = 'Set up'; $care = 'Maintenance'; $format = 'Formatting the PC'; $undo = 'Undo'
    @(
        New-MenuItem $setup  'windows'        'windows/Configure-Windows.ps1'        $null      'Windows'                       'Turns off telemetry, ads and suggestions, removes preinstalled apps and OneDrive, adjusts the taskbar, File Explorer, power and DNS. Asks before each change and creates a restore point.'
        New-MenuItem $setup  'apps'           'apps/Configure-Apps.ps1'              $null      'Install apps'            'Pick from 104 apps (browsers, games, development, utilities...) and install them with WinGet.'
        New-MenuItem $setup  'fonts'          'fonts/Install-Fonts.ps1'              $null      'Install fonts'         'Fonts for code (JetBrains Mono, Fira Code...), for the terminal with icons (Nerd Fonts) and for text (Inter, Roboto...).'
        New-MenuItem $setup  'chrome'         'browsers/Configure-Chrome.ps1'        $null      'Chrome'                                     'Privacy: turns off telemetry, Gemini and other AI features, third-party cookies and background mode. Google sign-in keeps working.'
        New-MenuItem $setup  'brave'          'browsers/Configure-Brave.ps1'         $null      'Brave'                                      'Turns off Wallet, VPN, Rewards, Leo (AI), News and usage reports. Ad blocking stays on.'
        New-MenuItem $setup  'firefox'        'browsers/Configure-Firefox.ps1'       $null      'Firefox'                                    'Turns off telemetry, sponsored content and AI features, and installs uBlock Origin and Bitwarden.'
        New-MenuItem $setup  'dev'            'dev/Configure-Dev.ps1'                $null      'Development'               'Editors, Git, SSH key sent to GitHub, signed commits, Windows Terminal with a Nerd Font, languages and WSL.'
        New-MenuItem $setup  'wallpapers'     'wallpapers/Get-Wallpapers.ps1'        $null      'Wallpapers'           'Pick wallpapers from the TidyWin collection and download them; can set one as the background.'

        New-MenuItem $care   'report'         'windows/Get-Report.ps1'               $null      'PC report'             'Only reads: activation, TPM and Secure Boot, disks, battery, drivers and crashes, in a page that opens in the browser. Good to send when asking for help.'
        New-MenuItem $care   'windows-check'  'windows/Configure-Windows.ps1'        '-Check'   'Check after a Windows update' 'Finds what a big Windows update brought back (telemetry, removed apps, OneDrive...) and offers to reapply only that.'
        New-MenuItem $care   'uninstall'      'apps/Uninstall-Apps.ps1'              $null      'Uninstall programs'  'Uninstalls the programs you pick with their official uninstaller, then shows the leftovers and deletes only what you confirm, with a backup.'
        New-MenuItem $care   'cleanup'        'windows/Clean-Windows.ps1'            $null      'Free up disk space'      'Temporary files, Windows Update downloads, error reports and more. Shows the size of each and asks before deleting.'
        New-MenuItem $care   'repair'         'windows/Repair-Windows.ps1'           $null      'Repair Windows'      'For when Windows acts strange: checks and repairs the system files and the disk with Windows'' own tools (DISM, sfc). 10 to 30 minutes.'
        New-MenuItem $care   'network-reset'  'windows/Reset-Network.ps1'            $null      'Reset the network'    'For "connected, no internet" or sites that don''t open. Quick or full, keeping your DNS.'

        # Backup: apps, then drivers. Restore: drivers first (network, video), then the apps, which need the internet.
        $apps    = 'App list'
        $drivers = 'Drivers'
        New-MenuSequence $format 'backup' @((New-Step 'apps/Backup-Apps.ps1' '-Export' $apps), (New-Step 'drivers/Backup-Drivers.ps1' '-Export' $drivers)) 'Back up apps and drivers' 'Before formatting: saves the list of installed apps and the drivers you pick, one after the other (each can be skipped). Keep them on a USB drive.'
        New-MenuSequence $format 'restore' @((New-Step 'drivers/Backup-Drivers.ps1' '-Import' $drivers), (New-Step 'apps/Backup-Apps.ps1' '-Import' $apps)) 'Restore apps and drivers' 'After formatting and Windows Update: installs the saved drivers Windows didn''t bring back, then the saved apps (each can be skipped).'

        New-MenuItem $undo   'windows-revert' 'windows/Revert-Configure-Windows.ps1' $null      'Windows'                                    'Undoes most of what Windows changed: telemetry, policies, suggestions, DNS. Removed apps come back from the Microsoft Store.'
        New-MenuItem $undo   'chrome-revert'  'browsers/Configure-Chrome.ps1'        '-Revert'  'Chrome'                                     'Removes every Chrome setting applied by TidyWin.'
        New-MenuItem $undo   'brave-revert'   'browsers/Configure-Brave.ps1'         '-Revert'  'Brave'                                      'Removes every Brave setting applied by TidyWin.'
        New-MenuItem $undo   'firefox-revert' 'browsers/Configure-Firefox.ps1'       '-Revert'  'Firefox'                                    'Removes every Firefox setting applied by TidyWin.'
        New-MenuItem $undo   'dev-revert'     'dev/Configure-Dev.ps1'                '-Revert'  'Development'               'Undoes the Windows settings changed by Development: Developer Mode, default terminal, Windows Terminal settings. Apps, Git and SSH keys stay.'
        New-MenuItem $undo   'fonts-revert'   'fonts/Install-Fonts.ps1'              '-Revert'  'Fonts'                          'Removes the fonts TidyWin installed. Fonts installed some other way stay.'
    )
}

#endregion


#region ==================== 3. MENU SCREEN ====================

# Full-screen menu with group headers and scrolling; the description of the selected item at the bottom.
# ↑ ↓ PgUp PgDn Home End move, Enter runs, Esc quits. Returns the item, or $null on Esc.
# $Start: index of the item selected when it opens (the last one run).
function Show-Menu([object[]]$Items, [int]$Start, [string]$Header) {
    $rows = New-Object System.Collections.Generic.List[object]
    $last = $null
    foreach ($it in $Items) {
        if ($it.Group -ne $last) { if ($rows.Count) { $rows.Add([pscustomobject]@{ Kind = 'Gap' }) }; $rows.Add([pscustomobject]@{ Kind = 'Header'; Text = $it.Group }); $last = $it.Group }
        $rows.Add([pscustomobject]@{ Kind = 'Item'; Item = $it })
    }
    $itemRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if ($rows[$r].Kind -eq 'Item') { $r } })
    $cursor = [Math]::Max(0, [Math]::Min($Start, $itemRows.Count - 1)); $scroll = 0; $lastSize = ''
    $nameWidth = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            if ("$width x $height" -ne $lastSize) { Clear-Host; $lastSize = "$width x $height" }
            $viewport = [Math]::Max(5, $height - 8)    # 3 header lines, 4 for the description and keys, last line left empty

            $row = $itemRows[$cursor]
            $wanted = if ($row -gt 0 -and $rows[$row - 1].Kind -eq 'Header') { $row - 1 } else { $row }
            if ($cursor -eq 0) { $wanted = 0 }
            if ($wanted -lt $scroll) { $scroll = $wanted }
            if ($row -ge $scroll + $viewport) { $scroll = $row - $viewport + 1 }

            $line = { param($text, $color) Write-Host ($text.PadRight($width - 1).Substring(0, $width - 1)) -ForegroundColor $color }
            [Console]::SetCursorPosition(0, 0)
            & $line "  TidyWin" 'Green'
            & $line "  $Header" 'DarkGray'
            & $line '' 'Gray'
            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count -or $rows[$r].Kind -eq 'Gap') { & $line '' 'Gray'; continue }
                if ($rows[$r].Kind -eq 'Header') { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $selected = $r -eq $row
                $marker = if ($selected) { '  > ' } else { '    ' }
                & $line "$marker$($rows[$r].Item.Name)" $(if ($selected) { 'Cyan' } else { 'Gray' })
            }

            # Description of the selected item (two lines at most), then the keys
            $desc = @(Split-Text $rows[$row].Item.Desc ($width - 5))
            & $line '' 'Gray'
            & $line "  $(if ($desc.Count -gt 0) { $desc[0] })" 'White'
            & $line "  $(if ($desc.Count -gt 1) { $desc[1] + $(if ($desc.Count -gt 2) { '…' }) })" 'White'
            & $line '  ↑ ↓ choose   Enter run   Esc quit' 'DarkGray'

            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - 5) }
                'PageDown'  { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 5) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $itemRows.Count - 1 }
                'Enter'     { return @{ Item = $rows[$row].Item; Index = $cursor } }
                'Escape'    { return $null }
            }
        }
    } finally {
        Clear-Host
        [Console]::CursorVisible = $true
    }
}

# Without a real console (e.g. PowerShell ISE): numbered list.
function Show-MenuPlain([object[]]$Items) {
    $last = $null
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Group -ne $last) { Write-Host "`n  $($Items[$i].Group)" -ForegroundColor Yellow; $last = $Items[$i].Group }
        Write-Host ("    {0,2}) {1}" -f ($i + 1), $Items[$i].Name)
    }
    $answer = "$(Read-Host "`n  Number (Enter quits)")".Trim()
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) { return @{ Item = $Items[$n - 1]; Index = $n - 1 } }
    return $null
}

# Runs one script: the local copy next to this file when there is one (a copy of the repository),
# otherwise downloaded from the site to this script's folder (the launcher deletes it afterwards).
function Invoke-Step($Step) {
    $file = Join-Path $PSScriptRoot $Step.Script
    if (-not (Test-Path -LiteralPath $file)) {
        $file = Join-Path $PSScriptRoot (Split-Path $Step.Script -Leaf)
        Write-Host "  downloading $($Step.Script)..." -ForegroundColor DarkGray
        try { Invoke-WebRequest "$Base/scripts/$($Step.Script)" -OutFile $file -UseBasicParsing -ErrorAction Stop }
        catch {
            Write-Host "  Could not download it: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    # A separate Windows PowerShell 5.1 process: the scripts expect a fresh session, and the menu survives their "return"s
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $Step.Args
    & powershell.exe @argv
}

# Enter = run the step, Esc = skip it. Without a real console: Enter or "s".
function Confirm-Step([string]$Text) {
    if (($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected) {
        return "$(Read-Host "  $Text — Enter runs, S skips")".Trim() -notmatch '^[sS]'
    }
    Write-Host "  $Text — Enter runs, Esc skips" -ForegroundColor Cyan
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    while ($true) {
        $key = [Console]::ReadKey($true).Key
        if ($key -eq 'Enter')  { return $true }
        if ($key -eq 'Escape') { return $false }
    }
}

# An option with one script runs it; one with several runs them in order, asking before each.
function Invoke-MenuItem($Item) {
    $steps = @($Item.Steps)
    if ($steps.Count -eq 1) { Invoke-Step $steps[0]; return }
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Write-Host "`n-- Step $($i + 1)/$($steps.Count): $($steps[$i].Name)" -ForegroundColor Green
        if (Confirm-Step $steps[$i].Name) { Invoke-Step $steps[$i] }
        else { Write-Host '  skipped' -ForegroundColor DarkGray }
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

$menu = @(Get-Menu)
$header = "$(Get-WindowsLabel) · every option asks before changing anything"
$plain = ($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected
$index = 0
while ($true) {
    $choice = if ($plain) { Show-MenuPlain $menu } else { Show-Menu $menu $index $header }
    if (-not $choice) { break }
    $index = $choice.Index
    Write-Host "`n== $($choice.Item.Group) · $($choice.Item.Name)" -ForegroundColor Green
    Invoke-MenuItem $choice.Item
    Write-Host ''
    [void](Read-Host '  Press Enter to go back to the menu')
}
Write-Host '  TidyWin closed.' -ForegroundColor DarkGray

#endregion
