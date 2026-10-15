#Requires -RunAsAdministrator
<#
    configure-windows.ps1 — telemetry, junk apps and personalization for Windows 10 and 11

    HOW TO RUN (Windows PowerShell 5.1 as Administrator, NOT PowerShell 7):
        powershell -ExecutionPolicy Bypass -File .\configure-windows.ps1

    Nothing comes selected: only what you turn on or pick is applied, the rest stays as it is.
    In the TidyWin panel every option shows on one page. Run directly, the options are asked one by one
    (arrow-key menus; "Skip" leaves a setting as it is), then everything is applied at once.

    Each change gets its own line: [OK] changed now, [--] it already was like that. Everything shown while
    applying is also saved to "TidyWin log <date>.txt" on the Desktop (with the answers; no user or PC name).
    If a step fails, the script reports it and moves on to the next one.
    Undo: revert-configure-windows.ps1 (removed apps come back through the Microsoft Store).
    Safe to run more than once. Restart the PC at the end.

    FILE LAYOUT
        1. Helpers ................... registry, prompts, steps
        2. System detection .......... Windows version and available features
        3. Privacy and cleanup ....... telemetry, suggestions, apps, OneDrive, Edge, Windows Security, C:\ root folders, device apps
        4. Personalization ........... theme, taskbar (alignment, search, Task View, pins, battery %), File Explorer (hidden files, folder discovery, Home/Gallery), window border
        5. System .................... long paths, End task, sudo, Win+V, mouse, Sticky Keys, verbose BSoD, screen/sleep times
        6. Network ................... DNS with DNS over HTTPS
        7. Options ................... every option (the panel's page) and what you chose
        8. Execution ................. applies the chosen options, in order
#>
param(
    [string]$Describe,      # the panel: write every option to this file and stop
    [string]$Answers        # the panel: apply the options in this file, without asking
)

$ErrorActionPreference = 'Continue'


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

# While the panel reads the page (-Describe): what is being read now and how far (0-100; none = unknown),
# shown in the bar under its loading ring. Does nothing otherwise.
function Write-Loading([string]$Text, $Percent) {
    if (-not $script:Panel -or -not $Describe) { return }
    [Console]::Out.WriteLine('##TIDYWIN ' + (ConvertTo-Json @{ type = 'progress'; text = $Text; value = $Percent } -Compress))
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


# Writes a registry value, creating the key if it doesn't exist.
function Set-Reg {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    # Only the registry: a broken path would otherwise create files in the current folder
    if ($Path -notmatch '^(HKLM|HKCU|HKCR|HKU|Registry):') { throw "not a registry path: $Path" }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# Step title in the terminal.
function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

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
        Write-Host '  Use the arrows ↑ ↓ and Enter' -ForegroundColor DarkGray
        $script:ArrowHintShown = $true
    }
    # Long lists (e.g. screen resolutions) scroll: only what fits in the window is drawn, plus a line
    # saying which part of the list is showing.
    $visible = [Math]::Max(3, [Math]::Min($Options.Count, [Console]::WindowHeight - 6))
    $scrolls = $visible -lt $Options.Count
    $height  = $visible + [int]$scrolls
    for ($i = 0; $i -lt $height; $i++) { Write-Host '' }       # reserve the menu lines
    $top = [Console]::CursorTop - $height
    $selected = $Default
    $first = [Math]::Max(0, $Default - $visible + 1)
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            if ($selected -lt $first) { $first = $selected }
            if ($selected -ge $first + $visible) { $first = $selected - $visible + 1 }
            for ($v = 0; $v -lt $visible; $v++) {
                $i = $first + $v
                [Console]::SetCursorPosition(0, $top + $v)
                $marker = if ($i -eq $selected) { '  > ' } else { '    ' }
                $line = ($marker + $Options[$i]).PadRight([Console]::WindowWidth - 1)
                if ($i -eq $selected) { Write-Host $line -ForegroundColor Cyan -NoNewline } else { Write-Host $line -NoNewline }
            }
            if ($scrolls) {
                [Console]::SetCursorPosition(0, $top + $visible)
                $range = "    showing $($first + 1)–$($first + $visible) of $($Options.Count) · ↑ ↓ for more"
                Write-Host $range.PadRight([Console]::WindowWidth - 1) -ForegroundColor DarkGray -NoNewline
            }
            $key = [Console]::ReadKey($true).Key
            if     ($key -eq 'UpArrow')   { $selected = ($selected - 1 + $Options.Count) % $Options.Count }
            elseif ($key -eq 'DownArrow') { $selected = ($selected + 1) % $Options.Count }
            elseif ($key -eq 'PageUp')    { $selected = [Math]::Max(0, $selected - $visible) }
            elseif ($key -eq 'PageDown')  { $selected = [Math]::Min($Options.Count - 1, $selected + $visible) }
            elseif ($key -eq 'Home')      { $selected = 0 }
            elseif ($key -eq 'End')       { $selected = $Options.Count - 1 }
            elseif ($key -eq 'Enter')     { break }
        }
    } finally {
        [Console]::SetCursorPosition(0, $top + $height)
        [Console]::CursorVisible = $true
    }
    return $selected
}

# Full-screen checklist with group headers and scrolling: ↑ ↓ move, Space checks, A checks/unchecks the
# whole group, Enter confirms. $Items: objects with Group, Label, Note, Checked. Returns the checked items.
# Without a real console: numbers separated by commas.
function Select-Many([string]$Title, [object[]]$Items) {
    if ($script:Panel) {
        $answer = Request-Panel @{ type = 'checklist'; title = $Title; cancel = $false
            items = @($Items | ForEach-Object { @{ label = "$($_.Label)"; note = "$($_.Note)"; group = "$($_.Group)"; checked = [bool]$_.Checked } }) }
        if ($null -ne $answer) { for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = @($answer.checked) -contains $i } }
        return @($Items | Where-Object Checked)
    }
    $arrows =($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        Write-Host "  $Title"
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
            Write-Host "    $($i + 1)) $mark $($Items[$i].Label) · $($Items[$i].Note)"
        }
        $answer = "$(Read-Host '  Numbers separated by commas, Enter keeps the checked ones')".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $lastGroup = $null
    foreach ($it in $Items) {
        if ($it.Group -ne $lastGroup) { $rows.Add([pscustomobject]@{ IsHeader = $true; Text = $it.Group }); $lastGroup = $it.Group }
        $rows.Add([pscustomobject]@{ IsHeader = $false; Item = $it })
    }
    $itemRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if (-not $rows[$r].IsHeader) { $r } })
    $labelWidth = ($Items | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    $cursor = 0; $scroll = 0; $lastSize = ''

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            if ("$width x $height" -ne $lastSize) { Clear-Host; $lastSize = "$width x $height" }
            $viewport = [Math]::Max(5, $height - 6)   # 3 header + 2 footer lines, last line left empty

            $row = $itemRows[$cursor]
            $wanted = if ($row -gt 0 -and $rows[$row - 1].IsHeader) { $row - 1 } else { $row }
            if ($wanted -lt $scroll) { $scroll = $wanted }
            if ($row -ge $scroll + $viewport) { $scroll = $row - $viewport + 1 }

            $line = { param($text, $color) Microsoft.PowerShell.Utility\Write-Host ($text.PadRight($width - 1).Substring(0, $width - 1)) -ForegroundColor $color }
            [Console]::SetCursorPosition(0, 0)
            & $line "  $Title" 'Green'
            & $line '  ↑ ↓ move   Space check   A check the whole group   Enter continue' 'DarkGray'
            & $line '' 'Gray'
            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count) { & $line '' 'Gray'; continue }
                if ($rows[$r].IsHeader) { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $it = $rows[$r].Item
                $check  = if ($it.Checked) { '[x]' } else { '[ ]' }
                $marker = if ($r -eq $row) { '>' } else { ' ' }
                $color  = if ($r -eq $row) { 'Cyan' } elseif ($it.Checked) { 'Green' } else { 'Gray' }
                & $line "  $marker $check $($it.Label.PadRight($labelWidth))  $($it.Note)" $color
            }
            & $line '' 'Gray'
            & $line "  $(@($Items | Where-Object Checked).Count) checked" 'DarkGray'

            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - $viewport) }
                'PageDown'  { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + $viewport) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $itemRows.Count - 1 }
                'Spacebar'  { $it = $rows[$itemRows[$cursor]].Item; $it.Checked = -not $it.Checked }
                'A' {
                    $group = @($Items | Where-Object Group -eq $rows[$itemRows[$cursor]].Item.Group)
                    $checkAll = @($group | Where-Object { -not $_.Checked }).Count -gt 0
                    foreach ($it in $group) { $it.Checked = $checkAll }
                }
                'Enter'     { return @($Items | Where-Object Checked) }
            }
        }
    } finally {
        Clear-Host
        [Console]::CursorVisible = $true
    }
}

# Reads and validates a typed IP address (IPv4 = InterNetwork, IPv6 = InterNetworkV6).
function Read-IP([string]$Question, [string]$Family, [bool]$Optional) {
    while ($true) {
        $answer = "$(Read-Host "    $Question")".Trim()
        if ($answer -eq '' -and $Optional) { return $null }
        $ip = $null
        # (TryParse accepts short forms like "1.1.1"; for IPv4 all 4 octets are required)
        $formatOk = if ($Family -eq 'InterNetwork') { $answer -match '^\d{1,3}(\.\d{1,3}){3}$' } else { $answer -match ':' }
        if ($formatOk -and [System.Net.IPAddress]::TryParse($answer, [ref]$ip) -and $ip.AddressFamily -eq $Family) { return $ip.ToString() }
        Write-Host "    Invalid address. Example: $(if ($Family -eq 'InterNetwork') { '1.1.1.1' } else { '2606:4700:4700::1111' })" -ForegroundColor DarkYellow
    }
}

# Runs a step. If it fails, records the failure and moves on to the next one.
$script:Failures = @()
$script:StepCount = 0
function Invoke-Step([string]$Title, [scriptblock]$Body) {
    Write-Step $Title
    $script:StepCount++
    try { & $Body }
    catch {
        $script:Failures += "${Title}: $($_.Exception.Message)"
        Write-Host "  [ERROR] This step failed ($($_.Exception.Message)). Moving on to the next one." -ForegroundColor Red
    }
}

# --- Detailed log: one line per setting, saying whether it changed
#   [OK] Activity history: off              (changed now)
#   [--] Activity history: off (already)    (it was already like this)
$script:ChangedCount = 0
$script:AlreadyCount = 0
function Write-Change([string]$Label, [string]$State, [bool]$Changed) {
    if ($Changed) {
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host "${Label}: $State"
        $script:ChangedCount++
    } else {
        Write-Host "  [--] ${Label}: $State (already)" -ForegroundColor DarkGray
        $script:AlreadyCount++
    }
}

# A step that did something without a registry value to compare: [OK]. One that found nothing to do: [--].
function Write-Done([string]$Text) {
    Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
    Write-Host $Text
    $script:ChangedCount++
}
function Write-Skip([string]$Text) {
    Write-Host "  [--] $Text" -ForegroundColor DarkGray
    $script:AlreadyCount++
}

# A registry value for Set-Option: RegValue <path> <name> <value> [type]
function RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    @{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }
}

# Writes the registry values that together make one visible setting, and logs one line for it.
function Set-Option([string]$Label, [string]$State, [object[]]$Values) {
    $changed = $false
    foreach ($v in $Values) {
        $current = (Get-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue).($v.Name)
        if ($null -eq $current -or "$current" -ne "$($v.Value)") { $changed = $true }
        Set-Reg $v.Path $v.Name $v.Value $v.Type
    }
    Write-Change $Label $State $changed
}

# --- Log file: everything shown while the changes are applied also goes to a text file on the
# Desktop, to read calmly afterwards or send when asking for help (no user or PC name in it).
# Write-Host is wrapped (same parameters), so every message is saved without changing each call.
# Turned on only for the execution: the arrow-key questions redraw the screen.
$script:LogFile = $null
$script:LogPending = ''
function Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [switch]$NoNewline,
          [object]$Separator = ' ', [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor)
    if ($script:Panel) { Write-PanelHost @PSBoundParameters } else { Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters }
    if (-not $script:LogFile) { return }
    $script:LogPending += ($Object -join "$Separator")
    if (-not $NoNewline) {
        try { Add-Content -LiteralPath $script:LogFile -Value $script:LogPending -Encoding UTF8 -ErrorAction Stop }
        catch { $script:LogFile = $null }      # can't write (Desktop full, synced...): keep going without the file
        $script:LogPending = ''
    }
}
function Start-Log {
    $name = '{0} {1}.txt' -f 'TidyWin log', (Get-Date -Format 'yyyy-MM-dd HHmm')
    $path = Join-Path ([Environment]::GetFolderPath('Desktop')) $name
    try {
        Set-Content -LiteralPath $path -Value "TidyWin · Windows · $(Get-Date -Format 'yyyy-MM-dd HH:mm') · $osLabel" -Encoding UTF8 -ErrorAction Stop
        $script:LogFile = $path
    } catch { }
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. SYSTEM DETECTION ====================

Write-Loading 'Reading the Windows version' 5
$build      = [Environment]::OSVersion.Version.Build
$isWin11    = $build -ge 22000
$cv         = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osLabel    = "Windows $(if ($isWin11) { '11' } else { '10' }) $($cv.EditionID) (build $build, $($cv.DisplayVersion))"
$hasEndTask = $isWin11 -and $build -ge 22631                      # "End task" on the taskbar: Windows 11 23H2+
$hasSudo    = Test-Path "$env:SystemRoot\System32\sudo.exe"     # Sudo: Windows 11 24H2+

# User folders inside OneDrive? (folder backup on) — then removing OneDrive needs care.
$foldersInOneDrive = @('Desktop', 'MyDocuments', 'MyPictures') |
    ForEach-Object { [Environment]::GetFolderPath($_) } |
    Where-Object { $_ -match '\\OneDrive' }

# Laptop (has a battery)? The battery percentage question only shows up on laptops.
Write-Loading 'Checking for a battery and the account type' 10
$hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

# Local account (not a Microsoft account)? Sets the default of the Windows Security areas question.
$isLocalAccount = (Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue).PrincipalSource -eq 'Local'

# Base key for Windows policies (used in several sections)
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'

#endregion


#region ==================== 3. PRIVACY AND CLEANUP ====================

# --- Telemetry -------------------------------------------------------------

# DiagTrack = "Connected User Experiences and Telemetry" (the service that sends the data).
function Disable-TelemetryServices {
    $labels = @{
        DiagTrack        = 'Telemetry service (DiagTrack)'
        dmwappushservice = 'Push message routing service (dmwappushservice)'
    }
    foreach ($svc in 'DiagTrack', 'dmwappushservice') {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        $already = $s.StartType -eq 'Disabled' -and $s.Status -eq 'Stopped'
        Stop-Service $svc -Force -ErrorAction SilentlyContinue
        Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Change $labels[$svc] 'disabled' (-not $already)
    }
}

# Disables (does not delete) the data collection tasks. The Compatibility Appraiser stays ON:
# it is what clears the yearly Windows feature update to install safely.
$TelemetryTasks = @(
    @('\Microsoft\Windows\Application Experience\',                 'ProgramDataUpdater'),
    @('\Microsoft\Windows\Application Experience\',                 'MareBackup'),
    @('\Microsoft\Windows\Autochk\',                                'Proxy'),
    @('\Microsoft\Windows\Customer Experience Improvement Program\', 'Consolidator'),
    @('\Microsoft\Windows\Customer Experience Improvement Program\', 'UsbCeip'),
    @('\Microsoft\Windows\DiskDiagnostic\',                         'Microsoft-Windows-DiskDiagnosticDataCollector'),
    @('\Microsoft\Windows\Feedback\Siuf\',                          'DmClient'),
    @('\Microsoft\Windows\Feedback\Siuf\',                          'DmClientOnScenarioDownload'),
    @('\Microsoft\Windows\Windows Error Reporting\',                'QueueReporting')
)

function Disable-TelemetryTasks {
    foreach ($t in $TelemetryTasks) {
        $task = Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        $already = $task.State -eq 'Disabled'
        Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue | Out-Null
        Write-Change "Task $($t[1])" 'disabled' (-not $already)
    }
    # (Older versions of this script disabled the Compatibility Appraiser; here it is re-enabled.)
    foreach ($name in 'Microsoft Compatibility Appraiser', 'Microsoft Compatibility Appraiser Exp') {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName $name -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Disabled') {
            Enable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue | Out-Null
            Write-Done "Re-enabled: $name"; Write-Host '  Needed for the yearly feature update.' -ForegroundColor DarkGray
        }
    }
}

# Diagnostics, ads, activity history, search and Delivery Optimization policies.
function Set-TelemetryPolicies {
    # Diagnostic data: on Home/Pro the real minimum is 1 ("Required"); 0 only works on Enterprise/Education.
    Set-Option 'Diagnostic data' 'minimum' (RegValue "$P\DataCollection" 'AllowTelemetry' 1),
        (RegValue "$P\DataCollection" 'MaxTelemetryAllowed' 1), (RegValue "$P\DataCollection" 'LimitDiagnosticLogCollection' 1),
        (RegValue "$P\DataCollection" 'LimitDumpCollection' 1), (RegValue "$P\DataCollection" 'AllowDeviceNameInTelemetry' 0),
        (RegValue "$P\DataCollection" 'DisableOneSettingsDownloads' 1)
    Set-Option 'Feedback requests' 'off' (RegValue "$P\DataCollection" 'DoNotShowFeedbackNotifications' 1)
    Set-Option 'Error reporting' 'off' (RegValue "$P\Windows Error Reporting" 'Disabled' 1)
    Set-Option 'Compatibility inventory' 'off' (RegValue "$P\AppCompat" 'DisableInventory' 1), (RegValue "$P\AppCompat" 'AITEnable' 0)
    Set-Option 'Advertising ID' 'off' (RegValue "$P\AdvertisingInfo" 'DisabledByGroupPolicy' 1)
    Set-Option 'Activity history' 'off' (RegValue "$P\System" 'EnableActivityFeed' 0),
        (RegValue "$P\System" 'PublishUserActivities' 0), (RegValue "$P\System" 'UploadUserActivities' 0)
    Set-Option 'Typing and inking personalization' 'off' (RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0)
    Set-Option 'Tailored experiences' 'off' (RegValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1)
    # Search: no Bing/web results, no "search highlights", no Cortana
    Set-Option 'Bing and web results in Start search' 'off' (RegValue "$P\Windows Search" 'DisableWebSearch' 1),
        (RegValue "$P\Windows Search" 'ConnectedSearchUseWeb' 0), (RegValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1)
    Set-Option 'Search highlights' 'off' (RegValue "$P\Windows Search" 'EnableDynamicContentInWSB' 0)
    Set-Option 'Cortana' 'off' (RegValue "$P\Windows Search" 'AllowCortana' 0)
    # Delivery Optimization: updates only from Microsoft, no sharing with other PCs
    Set-Option 'Updates' 'only from Microsoft, not shared with other PCs' (RegValue "$P\DeliveryOptimization" 'DODownloadMode' 0)
}

# Widgets (Windows 11) / News and interests (Windows 10).
# On recent Windows 11 builds Microsoft protects the Widgets key and not even an administrator
# can write to it. In that case, removes the Widgets package ("Windows Web Experience Pack").
function Disable-Widgets {
    if ($isWin11) {
        try {
            if (-not (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh')) { New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Done 'Widgets disabled by policy'
        } catch {
            Write-Host '  Windows protects the Widgets policy, so the Widgets package is removed instead.' -ForegroundColor DarkYellow
            $widgets = Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience' -ErrorAction SilentlyContinue
            if (-not $widgets) { Write-Skip 'Widgets are not installed anymore' }
            foreach ($pkg in $widgets) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Done 'Widgets removed'
                } catch {
                    Write-Host "  Could not remove Widgets: $($_.Exception.Message.Trim()). Turn them off in Settings → Personalization → Taskbar." -ForegroundColor DarkYellow
                }
            }
        }
    } else {
        try {
            if (-not (Test-Path "$P\Windows Feeds")) { New-Item "$P\Windows Feeds" -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty "$P\Windows Feeds" -Name 'EnableFeeds' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Done 'News and interests turned off'
        } catch {
            Write-Host '  Could not turn off News and interests by policy. Right-click the taskbar → News and interests → Turn off.' -ForegroundColor DarkYellow
        }
    }
}

# --- Suggestions and ads ---------------------------------------------------

function Disable-Suggestions {
    $CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $ADV = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    # Silent installs of "consumer apps" (Candy Crush etc.). DisableWindowsConsumerFeatures is officially
    # Enterprise/Education only; on Home/Pro SilentInstalledAppsEnabled=0 does the job.
    Set-Option 'Silent app installs (Candy Crush...)' 'off' (RegValue $CDM 'SilentInstalledAppsEnabled' 0),
        (RegValue $CDM 'PreInstalledAppsEnabled' 0), (RegValue $CDM 'OemPreInstalledAppsEnabled' 0), (RegValue "$P\CloudContent" 'DisableWindowsConsumerFeatures' 1)
    Set-Option 'Suggestions in Start' 'off' (RegValue $CDM 'SystemPaneSuggestionsEnabled' 0), (RegValue $CDM 'SubscribedContent-338388Enabled' 0)
    Set-Option 'Tips and tricks' 'off' (RegValue $CDM 'SoftLandingEnabled' 0), (RegValue $CDM 'SubscribedContent-338389Enabled' 0)
    Set-Option 'Suggested content in Settings' 'off' (RegValue $CDM 'SubscribedContent-338393Enabled' 0),
        (RegValue $CDM 'SubscribedContent-353694Enabled' 0), (RegValue $CDM 'SubscribedContent-353696Enabled' 0)
    Set-Option 'Welcome screen after updates' 'off' (RegValue $CDM 'SubscribedContent-310093Enabled' 0)
    Set-Option '"Let''s finish setting up"' 'off' (RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0)
    Set-Option 'OneDrive ads in File Explorer' 'off' (RegValue $ADV 'ShowSyncProviderNotifications' 0)
    if ($isWin11) {
        Set-Option 'Recommendations in Start' 'off' (RegValue $ADV 'Start_IrisRecommendations' 0)
    }
}

# --- Apps ------------------------------------------------------------------

$JunkApps = @(
    'Clipchamp.Clipchamp',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.BingSearch',
    'Microsoft.Copilot',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',                    # Tips
    'Microsoft.MicrosoftOfficeHub',            # "Microsoft 365" app
    'Microsoft.MicrosoftSolitaireCollection',
    '7EE7776C.LinkedInforWindows',             # LinkedIn
    'Microsoft.OutlookForWindows',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.Todos',
    'Microsoft.Windows.DevHome',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.MixedReality.Portal',
    'Microsoft.ZuneVideo',                     # Movies & TV
    'Microsoft.549981C3F5F10',                 # Cortana
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftTeams',
    'MSTeams',
    # More common on Windows 10
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MSPaint',                       # Paint 3D (the regular Paint is a different package and stays)
    'Microsoft.Print3D',
    'Microsoft.SkypeApp',
    'Microsoft.Wallet',
    'Microsoft.Messaging',
    'Microsoft.OneConnect'                     # Mobile Plans
)
$OptionalApps = @(
    'Microsoft.YourPhone',                     # Phone Link
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.WindowsAlarms',                 # Clock/alarms
    'MicrosoftCorporationII.QuickAssist',      # Quick Assist
    'Microsoft.ZuneMusic',                     # Media Player / Groove
    'Microsoft.Office.OneNote'                 # OneNote for Windows 10
)

# Everything Xbox. Store/Game Pass games and games that sign in with Xbox (Minecraft, Forza, Halo...)
# need these. Steam, Epic, Riot and Game Mode don't.
$XboxApps = @(
    'Microsoft.GamingApp',                     # Xbox app
    'Microsoft.XboxApp',                       # Xbox Console Companion (Windows 10)
    'Microsoft.XboxGamingOverlay',             # Xbox Game Bar (Win+G)
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.XboxIdentityProvider',          # Xbox sign-in inside games
    'Microsoft.Xbox.TCUI',
    'Microsoft.GamingServices'                 # Store / Game Pass games
)
# Snipping Tool (Windows 10: Snip & Sketch), for whoever uses another screenshot app such as ShareX.
$SnippingApps = @('Microsoft.ScreenSketch')

# The "apps to remove" checklist: one row per app (some apps are several packages), with a short note.
# Rarely used come checked; the ones some people use, Xbox and the Snipping Tool come unchecked.
# Only apps present on the PC are shown (installed for some user, or provisioned for new accounts).
function New-AppRow($Group, $Label, [string[]]$Packages, [bool]$Checked, $Note) {
    [pscustomobject]@{ Group = $Group; Label = $Label; Packages = $Packages; Checked = $Checked; Note = $Note }
}
function Get-AppCatalog {
    $rare = 'Rarely used'; $some = 'Used by some people'; $xbox = 'Xbox'
    @(
        New-AppRow $rare 'Clipchamp'                                   'Clipchamp.Clipchamp'                    $true 'Video editor'
        New-AppRow $rare 'Copilot'                                     'Microsoft.Copilot'                      $true 'AI assistant'
        New-AppRow $rare 'Bing News'               'Microsoft.BingNews'                     $true ''
        New-AppRow $rare 'Bing Weather'               'Microsoft.BingWeather'                  $true ''
        New-AppRow $rare 'Bing Search'             'Microsoft.BingSearch'                   $true ''
        New-AppRow $rare 'Get Help'                  'Microsoft.GetHelp'                      $true ''
        New-AppRow $rare 'Tips'                            'Microsoft.Getstarted'                   $true ''
        New-AppRow $rare 'Microsoft 365'                               'Microsoft.MicrosoftOfficeHub'           $true 'Office ad app; Office itself stays'
        New-AppRow $rare 'Solitaire'                   'Microsoft.MicrosoftSolitaireCollection' $true ''
        New-AppRow $rare 'LinkedIn'                                    '7EE7776C.LinkedInforWindows'            $true ''
        New-AppRow $rare 'Outlook, new'             'Microsoft.OutlookForWindows'            $true 'Classic Outlook stays'
        New-AppRow $rare 'Teams'                                       @('MicrosoftTeams', 'MSTeams')           $true ''
        New-AppRow $rare 'People'                        'Microsoft.People'                       $true ''
        New-AppRow $rare 'Power Automate'                              'Microsoft.PowerAutomateDesktop'         $true ''
        New-AppRow $rare 'To Do'                                       'Microsoft.Todos'                        $true ''
        New-AppRow $rare 'Dev Home'                                    'Microsoft.Windows.DevHome'              $true ''
        New-AppRow $rare 'Feedback Hub'       'Microsoft.WindowsFeedbackHub'           $true ''
        New-AppRow $rare 'Maps'                            'Microsoft.WindowsMaps'                  $true ''
        New-AppRow $rare 'Mixed Reality'     'Microsoft.MixedReality.Portal'          $true ''
        New-AppRow $rare 'Movies & TV'               'Microsoft.ZuneVideo'                    $true ''
        New-AppRow $rare 'Cortana'                                     'Microsoft.549981C3F5F10'                $true ''
        New-AppRow $rare 'Family'                        'MicrosoftCorporationII.MicrosoftFamily' $true ''
        New-AppRow $rare '3D Viewer'             'Microsoft.Microsoft3DViewer'            $true ''
        New-AppRow $rare 'Paint 3D'                                    'Microsoft.MSPaint'                      $true 'The regular Paint stays'
        New-AppRow $rare 'Print 3D'                                    'Microsoft.Print3D'                      $true ''
        New-AppRow $rare 'Skype'                                       'Microsoft.SkypeApp'                     $true ''
        New-AppRow $rare 'Wallet'                       'Microsoft.Wallet'                       $true ''
        New-AppRow $rare 'Messaging'                   'Microsoft.Messaging'                    $true ''
        New-AppRow $rare 'Mobile Plans'            'Microsoft.OneConnect'                   $true ''

        New-AppRow $some 'Phone Link'        'Microsoft.YourPhone'                    $false ''
        New-AppRow $some 'Sticky Notes'                                'Microsoft.MicrosoftStickyNotes'         $false ''
        New-AppRow $some 'Sound Recorder'        'Microsoft.WindowsSoundRecorder'         $false ''
        New-AppRow $some 'Clock'                         'Microsoft.WindowsAlarms'                $false 'Alarms and timer'
        New-AppRow $some 'Quick Assist'       'MicrosoftCorporationII.QuickAssist'     $false 'Remote help'
        New-AppRow $some 'Media Player'                                'Microsoft.ZuneMusic'                    $false ''
        New-AppRow $some 'OneNote'                                     'Microsoft.Office.OneNote'               $false 'OneNote for Windows 10'
        New-AppRow $some 'Snipping Tool'         $SnippingApps                            $false 'Win+Shift+S stops working; Print Screen is free for ShareX'

        New-AppRow $xbox 'Xbox'                                        @('Microsoft.GamingApp', 'Microsoft.XboxApp') $false 'Game Pass games stop working'
        New-AppRow $xbox 'Game Bar'                                    @('Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay') $false 'Win+G'
        New-AppRow $xbox 'Xbox sign-in'               @('Microsoft.XboxIdentityProvider', 'Microsoft.Xbox.TCUI') $false 'Minecraft, Forza and other games with Xbox sign-in stop working'
        New-AppRow $xbox 'Gaming Services'                             'Microsoft.GamingServices'               $false 'Store and Game Pass games stop working'
    )
}

# Package name -> name shown, for the removal log.
function Get-AppLabel([string]$Package) {
    $row = Get-AppCatalog | Where-Object { $_.Packages -contains $Package } | Select-Object -First 1
    if ($row) { return $row.Label } else { return $Package }
}

# Removes the apps for all users plus the provisioned package (so they don't return in new profiles).
# Deprovisions FIRST: Remove-AppxPackage -AllUsers deletes the package files.
# One line per app: [OK] removed, or [ERROR] with the reason. Packages not on the PC are skipped.
# Note: no $p here — PowerShell is case-insensitive and it would collide with $P.
function Remove-Apps([string[]]$List) {
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    $done = @{}
    foreach ($app in $List) {
        $label = Get-AppLabel $app
        $errors = @()
        $found = $false
        foreach ($prov in ($provisioned | Where-Object DisplayName -eq $app)) {
            $found = $true
            try { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null }
            catch { $errors += $_.Exception.Message.Trim() }
        }
        foreach ($pkg in (Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue)) {
            $found = $true
            try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop }
            catch { $errors += $_.Exception.Message.Trim() }
        }
        if (-not $found -or $done.ContainsKey($label)) { continue }      # one line per app, even with several packages
        $done[$label] = $true
        if ($errors) { Write-Host "  [ERROR] ${label}: $($errors[0])" -ForegroundColor Red }
        else { Write-Change $label 'removed' $true }
    }
}

# Print Screen key free for other apps (on Windows 11 it opens the Snipping Tool by default). Done when the
# Snipping Tool is removed, so ShareX or similar can take the key over.
function Set-PrintScreenFree {
    Set-Option 'Print Screen key' 'free for other apps' (RegValue 'HKCU:\Control Panel\Keyboard' 'PrintScreenKeyForSnippingEnabled' 0)
}

# Game DVR (background game recording) off. Without it, Windows doesn't try to open the removed
# Game Bar ("You'll need a new app to open this ms-gamingoverlay link").
function Disable-GameDvr {
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Reg "$P\GameDVR" 'AllowGameDVR' 0
    Write-Done 'Game recording (Game DVR): off'
}

# --- OneDrive --------------------------------------------------------------

function Remove-OneDrive {
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") |
             Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($setup) { Start-Process $setup -ArgumentList '/uninstall' -Wait }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements 2>$null | Out-Null
    }
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
    Set-Reg "$P\OneDrive" 'DisableFileSyncNGSC' 1
    Write-Done 'OneDrive removed'
}

# --- Edge ------------------------------------------------------------------

# Edge desktop shortcut: deletes it (your desktop and the shared one) and, through the official Edge
# Update policy, stops Edge installs and updates from creating it again.
function Get-EdgeShortcuts {
    foreach ($folder in 'CommonDesktopDirectory', 'Desktop') {
        $dir = [Environment]::GetFolderPath($folder)
        if ($dir) { Join-Path $dir 'Microsoft Edge.lnk' }
    }
}
function Remove-EdgeDesktopShortcut {
    $U = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    Set-Reg $U 'CreateDesktopShortcutDefault' 0
    Set-Reg $U 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0   # Edge (Stable)
    Get-EdgeShortcuts | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Remove-Item -LiteralPath $_ -Force }
    Write-Done 'Edge desktop shortcut: deleted, and Edge updates no longer create it'
}

function Set-EdgePolicies {
    $E = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Option 'Edge running in the background' 'off' (RegValue $E 'StartupBoostEnabled' 0), (RegValue $E 'BackgroundModeEnabled' 0)
    Set-Option 'Edge sidebar' 'off' (RegValue $E 'HubsSidebarEnabled' 0)
    Set-Option 'Copilot in Edge' 'off' (RegValue $E 'Microsoft365CopilotChatIconEnabled' 0), (RegValue $E 'CopilotPageContext' 0)
    Set-Option 'Edge telemetry' 'off' (RegValue $E 'DiagnosticData' 0), (RegValue $E 'PersonalizationReportingEnabled' 0)
    Set-Option 'Shopping and coupons in Edge' 'off' (RegValue $E 'EdgeShoppingAssistantEnabled' 0)
    Set-Option 'Edge recommendations' 'off' (RegValue $E 'ShowRecommendationsEnabled' 0), (RegValue $E 'SpotlightExperiencesAndRecommendationsEnabled' 0)
    Set-Option 'Edge first-run screen' 'hidden' (RegValue $E 'HideFirstRunExperience' 1)
    Set-Option 'Edge new tab' 'without news or sponsored links' (RegValue $E 'NewTabPageContentEnabled' 0),
        (RegValue $E 'NewTabPageQuickLinksEnabled' 0), (RegValue $E 'NewTabPageHideDefaultTopSites' 1)
}

# --- Windows Security ------------------------------------------------------

function Set-WindowsSecurity {
    # Potentially unwanted app blocking (adware, installers bundling "extras")
    try {
        Set-MpPreference -PUAProtection Enabled -ErrorAction Stop
        Write-Done 'Potentially unwanted app blocking: on'
    } catch {
        Write-Host "  Could not turn on potentially unwanted app blocking: $($_.Exception.Message.Trim()). Is another antivirus installed?" -ForegroundColor DarkYellow
    }
    # Second half of the same setting: "Block downloads" (SmartScreen in Edge). Without it, Windows Security
    # keeps warning that potentially unwanted app blocking is off.
    # (the value is the key's default value; reg.exe /ve writes it reliably)
    reg.exe add 'HKCU\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled' /ve /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE) { Write-Host '  Could not turn on unwanted download blocking.' -ForegroundColor DarkYellow }
    else               { Write-Done 'Unwanted download blocking: on' }

    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    # "Informational" notifications (suggestions, summaries). Important alerts — threat found,
    # protection turned off — keep showing up.
    Set-Reg "$WSC\Notifications" 'DisableEnhancedNotifications' 1
    Write-Done 'Informational notifications: hidden'; Write-Host '  Important alerts still show up.' -ForegroundColor DarkGray

    # "Set up OneDrive for ransomware recovery" card: without OneDrive it only causes the
    # exclamation mark on the icon. Hidden only when OneDrive is not installed.
    $hasOneDrive = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
                   (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
    if (-not $hasOneDrive) {
        Set-Reg "$WSC\Virus and threat protection" 'HideRansomwareRecovery' 1
        Write-Done 'OneDrive backup warning: hidden'; Write-Host '  OneDrive is not installed.' -ForegroundColor DarkGray
    } else {
        Write-Skip 'OneDrive backup warning: kept'; Write-Host '  OneDrive is installed.' -ForegroundColor DarkGray
    }
}

# Official option "Download manufacturers' apps and custom icons available for your devices"
# (System Properties → Hardware → Device Installation Settings). Drivers keep coming from Windows Update.
# Note: some vendor installers (e.g. Razer) ship inside the driver package itself and may still appear.
function Disable-DeviceMetadata {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Write-Done 'Manufacturer apps and icons for devices: no longer downloaded'; Write-Host '  Drivers still are.' -ForegroundColor DarkGray
}

# Recall (Copilot+ PCs only): official policies that remove it and stop it from being turned on, and
# stop it from saving snapshots. On other PCs they change nothing.
function Disable-Recall {
    Set-Reg "$P\WindowsAI" 'AllowRecallEnablement' 0
    Set-Reg "$P\WindowsAI" 'DisableAIDataAnalysis' 1
    Write-Done 'Recall: removed and blocked'; Write-Host '  After restarting. Recall only exists on Copilot+ PCs.' -ForegroundColor DarkGray
}

# WPBT (Windows Platform Binary Table): lets the PC's firmware hand Windows a program to run at every
# boot. Manufacturers use it to reinstall their apps (Armoury Crate, Vantage...) even after a clean install.
# This stops Windows from running it; the firmware itself is not touched.
function Disable-Wpbt {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
    Write-Done 'WPBT: Windows no longer runs programs provided by the firmware'; Write-Host '  After restarting.' -ForegroundColor DarkGray
}

# Hides the "Account protection" and "Device security" areas of Windows Security (official policy).
# With a local account they only show "Sign in with a Microsoft account" warnings. Nothing is turned off:
# TPM, Secure Boot, Memory integrity and Windows Hello keep working as they are.
function Hide-SecurityAccountAreas {
    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    Set-Reg "$WSC\Account protection" 'UILockdown' 1
    Set-Reg "$WSC\Device security"    'UILockdown' 1
    Write-Done '"Account protection" and "Device security": hidden from Windows Security'
}

# --- System drive root -------------------------------------------------------

# inetpub: created empty by the April 2025 security update (CVE-2025-21204 fix). Deleting it removes
#          that protection, so it is only HIDDEN.
# PerfLogs: Performance Monitor output, empty unless you run a data collector. Safe to delete;
#           Windows recreates it if it ever needs it.
function Clear-SystemDriveRoot {
    $inetpub  = "$env:SystemDrive\inetpub"
    $perfLogs = "$env:SystemDrive\PerfLogs"
    if (Test-Path $inetpub) {
        $folder = Get-Item $inetpub -Force
        $folder.Attributes = $folder.Attributes -bor [IO.FileAttributes]::Hidden   # -bor: safe if already hidden
        Write-Done 'inetpub: hidden'; Write-Host '  Not deleted: a Windows security fix needs it.' -ForegroundColor DarkGray
    }
    if (Test-Path $perfLogs) {
        Remove-Item $perfLogs -Recurse -Force -ErrorAction Stop
        Write-Done 'PerfLogs: deleted'
    }
}

#endregion


#region ==================== 4. PERSONALIZATION ====================

# Whether File Explorer must be restarted at the end so the visual changes show up right away.
$script:RestartExplorer = $false

# Applies the official theme file, just like clicking it in Settings → Personalization → Themes.
#   Windows 11: aero.theme = light, dark.theme = dark.
#   Windows 10: light.theme = light; there is no ready-made dark theme, so it uses "Windows"
#               (aero.theme) and then turns dark mode on.
# The accent color is not changed.
function Set-Theme([bool]$Light) {
    $script:RestartExplorer = $true
    $dir = "$env:WINDIR\Resources\Themes"
    $theme = if ($isWin11) { if ($Light) { "$dir\aero.theme" } else { "$dir\dark.theme" } }
             else          { if ($Light) { "$dir\light.theme" } else { "$dir\aero.theme" } }
    if (-not (Test-Path $theme)) { $theme = "$dir\aero.theme" }
    if (-not (Test-Path $theme)) { throw "theme file not found: $theme" }

    $Themes = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes'
    Start-Process $theme
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $current = (Get-ItemProperty $Themes -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
    } until (($current -and $current -ieq $theme) -or (Get-Date) -gt $deadline)
    Start-Sleep -Seconds 3                                                        # let Windows finish applying
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force # close the Settings window
    # (if a Control Panel window opens, it closes when File Explorer restarts at the end)

    # Make sure the system and app light/dark mode match
    $mode = if ($Light) { 1 } else { 0 }
    Set-Reg "$Themes\Personalize" 'SystemUsesLightTheme' $mode
    Set-Reg "$Themes\Personalize" 'AppsUseLightTheme'    $mode
    Set-ThemeWallpaper $theme
    if ($current -ine $theme) { Write-Warning 'Could not confirm the theme. Check Settings → Personalization → Themes.' }
    else { Write-Done "Theme applied: $(Split-Path $theme -Leaf)" }
}

# On Windows 11 the desktop background can stay on "Windows Spotlight" even after applying a theme
# (seen on a fresh install). So the theme's own wallpaper is set explicitly as a "Picture" background.
function Set-ThemeWallpaper([string]$ThemeFile) {
    # Wallpaper path from the .theme file, e.g. Wallpaper=%SystemRoot%\web\wallpaper\Windows\img19.jpg
    $line = Select-String -Path $ThemeFile -Pattern '^\s*Wallpaper\s*=' | Select-Object -First 1
    if (-not $line) { return }
    $wallpaper = [Environment]::ExpandEnvironmentVariables(($line.Line -split '=', 2)[1].Trim())
    if (-not (Test-Path $wallpaper)) { return }

    if ($isWin11) {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings' 'EnabledState' 0   # Spotlight off
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType' 0      # 0 = Picture
    }
    if (-not ('CfgWin.Wallpaper' -as [type])) {
        Add-Type -Namespace CfgWin -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
    }
    # SPI_SETDESKWALLPAPER = 0x14; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    if ([CfgWin.Wallpaper]::SystemParametersInfo(0x14, 0, $wallpaper, 3)) {
        Write-Done "Theme wallpaper: $(Split-Path $wallpaper -Leaf)"; Write-Host '  Windows Spotlight is off.' -ForegroundColor DarkGray
    } else {
        Write-Host '  Could not change the wallpaper. Pick one in Settings → Personalization → Background.' -ForegroundColor DarkYellow
    }
}

# Visible file extensions, frequent folders and recent files in File Explorer.
function Set-Explorer([bool]$ShowExtensions, [bool]$HideFrequent, [bool]$HideRecent) {
    $Exp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    if ($ShowExtensions) { Set-Reg "$Exp\Advanced" 'HideFileExt' 0; Write-Done 'File extensions visible' }
    if ($HideFrequent)   { Set-Reg $Exp 'ShowFrequent' 0;          Write-Done 'Frequent folders hidden'; Write-Host '  The ones you pinned stay.' -ForegroundColor DarkGray }
    if ($HideRecent) {
        Set-Reg $Exp 'ShowRecent' 0
        if ($isWin11) { Set-Reg $Exp 'ShowRecommendations' 0 }
        Write-Done 'Recent files hidden'
    }
    $script:RestartExplorer = $true
}

# Removes "Home" and "Gallery" from the File Explorer sidebar (Windows 11) and makes File Explorer
# open in "This PC" (otherwise it would keep opening in the hidden Home). Pinned folders are untouched.
function Hide-HomeAndGallery {
    $CLSID = 'HKCU:\SOFTWARE\Classes\CLSID'
    Set-Reg "$CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" 'System.IsPinnedToNameSpaceTree' 0   # Home
    Set-Reg "$CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" 'System.IsPinnedToNameSpaceTree' 0   # Gallery
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1      # open in This PC
    Write-Done 'Home and Gallery removed from the sidebar; File Explorer opens in "This PC"'
    $script:RestartExplorer = $true
}

# Windows 11: the full right-click menu right away, without "Show more options" (the Windows 10 style menu).
# An empty InprocServer32 for this CLSID makes File Explorer skip the new menu. Undo: delete the key.
function Enable-ClassicContextMenu {
    reg.exe add 'HKCU\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /ve /f | Out-Null   # /ve without /d = empty default value
    if ($LASTEXITCODE) { throw 'could not write the classic menu key' }
    Write-Done 'Classic context menu: on'; Write-Host '  No "Show more options".' -ForegroundColor DarkGray
    $script:RestartExplorer = $true
}

# Shows hidden files and folders (.git, AppData...). Protected system files stay hidden.
# Unpins the Music folder from Quick access (the folder itself and its files are not touched).
# Uses the same "Unpin from Quick access" action as the right-click menu.
function Unpin-QuickAccessMusic {
    $music = [Environment]::GetFolderPath('MyMusic')
    $quick = (New-Object -ComObject Shell.Application).Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
    $item  = $quick.Items() | Where-Object { $_.Path -eq $music }
    if (-not $item) { Write-Skip 'Music was not pinned to Quick access'; return }
    $item.InvokeVerb('unpinfromhome')
    Write-Done 'Music unpinned from Quick access'; Write-Host '  The folder stays where it is.' -ForegroundColor DarkGray
}

function Show-HiddenFiles {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
    Write-Done 'Hidden files and folders: visible'; Write-Host '  Protected system files stay hidden.' -ForegroundColor DarkGray
    $script:RestartExplorer = $true
}

# Stops File Explorer from "sniffing" each folder's content to pick a template (Music, Pictures...),
# which makes folders with thousands of files slow to open. Every folder uses the generic template.
# The saved per-folder views (Bags/BagMRU) must be cleared for this to apply, so custom views are reset.
function Disable-FolderDiscovery {
    $shell = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell'
    Remove-Item "$shell\Bags", "$shell\BagMRU" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Reg "$shell\Bags\AllFolders\Shell" 'FolderType' 'NotSpecified' 'String'
    Write-Done 'Automatic folder type discovery: off'; Write-Host '  Folder views were reset.' -ForegroundColor DarkGray
    $script:RestartExplorer = $true
}

# After installing an app that opens a file type, Windows asks "How do you want to open this file?" the
# next time you open one, to pick the new app. Group Policy "Do not show the 'new application installed'
# notification": the files keep opening with the app you already use; Open with still changes it.
function Disable-NewAppAlert {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'NoNewAppAlert' 1
    Write-Done '"New app installed" prompt: off'; Write-Host '  To use another app for a file type: right-click the file → Open with.' -ForegroundColor DarkGray
}

# Battery percentage next to the taskbar battery icon (Windows 11 24H2/25H2, builds from late 2025 on).
# On older builds the value is simply ignored.
function Enable-BatteryPercentage {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IsBatteryPercentageEnabled' 1
    Write-Done 'Battery percentage on the taskbar: on'; Write-Host '  If your Windows version has the option.' -ForegroundColor DarkGray
    $script:RestartExplorer = $true
}

# Invisible area around windows that "grabs" the mouse for resizing: from ~5 px down to ~1 px.
# Windows default: -60. Takes effect after signing out and back in.
function Set-ThinBorder {
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'PaddedBorderWidth' '0' 'String'
    Write-Done 'Border thinned'; Write-Host '  Takes effect after signing out and back in.' -ForegroundColor DarkGray
}

# Snap windows off (Settings → System → Multitasking): no snapping to screen edges, no Snap layouts.
# Saved in the registry and applied right away through the same Windows call Settings uses.
function Disable-SnapWindows {
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WindowArrangementActive' '0' 'String'
    if (-not ('CfgWin.Snap' -as [type])) {
        Add-Type -Namespace CfgWin -Name Snap -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, System.IntPtr pvParam, uint fWinIni);
'@
    }
    # SPI_SETWINARRANGEMENT = 0x0083; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    [void][CfgWin.Snap]::SystemParametersInfo(0x0083, 0, [IntPtr]::Zero, 3)
    Write-Done 'Snap windows: off'
}

# Taskbar icon alignment (Windows 11 only): TaskbarAl 0 = left, 1 = center (Windows default).
function Set-TaskbarAlignment([bool]$Left) {
    $value = if ($Left) { 0 } else { 1 }
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' $value
    Write-Done "Taskbar icons: $(if ($Left) { 'left' } else { 'center' })"
    $script:RestartExplorer = $true
}

# Taskbar search (Windows 10 and 11): SearchboxTaskbarMode 0 = hidden, 1 = icon only, 2 = search box.
function Set-TaskbarSearch([int]$Mode) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' $Mode
    Write-Done "Taskbar search: $(@('hidden', 'icon only', 'search box')[$Mode])"
    $script:RestartExplorer = $true
}

# "Task View" button on the taskbar (Windows 10 and 11): ShowTaskViewButton 0 = hidden, 1 = visible.
# Win+Tab keeps working either way.
function Set-TaskViewButton([bool]$Show) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' ([int]$Show)
    Write-Done "Task View button: $(if ($Show) { 'visible' } else { 'hidden (Win+Tab still works)' })"
    $script:RestartExplorer = $true
}

# Unpins every app from the taskbar (Edge, Store, File Explorer and any you pinned yourself).
# The pin list lives in the Taskband key plus the shortcuts in the "User Pinned\TaskBar" folder.
# Apps are not uninstalled; pin them again with right-click → "Pin to taskbar".
function Clear-TaskbarPins {
    Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Done 'Pinned icons removed from the taskbar'
    $script:RestartExplorer = $true
}

# Start menu pins that are ads: promoted apps, and shortcuts that only install the app when clicked.
# Only names on this list are unpinned; everything else pinned stays. Names as Windows shows them.
$StartAdPins = @('LinkedIn', 'Spotify', 'Instagram', 'Facebook', 'Messenger', 'TikTok', 'WhatsApp', 'Netflix',
                 'Prime Video', 'Disney+', 'Microsoft Solitaire Collection', 'Solitaire & Casual Games',
                 'Candy Crush Saga', 'Candy Crush Soda Saga', 'Picsart', 'Adobe Express', 'Luminar Neo', 'Outlook (new)')
# What was unpinned, so Revert-Configure-Windows can pin it back.
$StartUnpinnedFile = Join-Path $env:ProgramData 'TidyWin\start-unpinned.json'

# "Unpin from Start" in the Windows language: the text of the right-click menu entry, read from shell32
# (resource 51394), without the "&" of the keyboard shortcut.
function Get-UnpinFromStartName {
    if (-not ('CfgWin.Res' -as [type])) {
        Add-Type -Namespace CfgWin -Name Res -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr LoadLibrary(string name);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int LoadString(System.IntPtr module, uint id, System.Text.StringBuilder buffer, int size);
'@
    }
    $text = New-Object System.Text.StringBuilder 256
    [void][CfgWin.Res]::LoadString([CfgWin.Res]::LoadLibrary('shell32.dll'), 51394, $text, $text.Capacity)
    return $text.ToString().Replace('&', '')
}

# Unpins the ad shortcuts with the same "Unpin from Start" as the right-click menu, item by item.
function Remove-StartAdPins {
    $unpin = Get-UnpinFromStartName
    $apps = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')   # all apps
    $done = @()
    foreach ($item in @($apps.Items())) {
        if ($StartAdPins -notcontains $item.Name) { continue }
        # The entry only exists when the item is pinned
        $verb = @($item.Verbs()) | Where-Object { $n = $_.Name.Replace('&', ''); ($unpin -and $n -eq $unpin) -or $n -eq 'Unpin from Start' } | Select-Object -First 1
        if ($verb) { $verb.DoIt(); $done += $item.Name }
    }
    if ($done) {
        New-Item -ItemType Directory -Path (Split-Path $StartUnpinnedFile) -Force | Out-Null
        ConvertTo-Json -InputObject @($done) | Set-Content $StartUnpinnedFile -Encoding UTF8
        Write-Done "Unpinned from Start: $($done -join ', ')"
    } else {
        Write-Skip 'No ad shortcuts pinned to Start'
    }
}

# Notifies apps of the theme change and restarts File Explorer (Windows reopens it by itself).
function Restart-Explorer {
    if (-not ('CfgWin.Broadcast' -as [type])) {
        Add-Type -Namespace CfgWin -Name Broadcast -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    foreach ($area in 'ImmersiveColorSet', 'WindowsThemeElement') {
        [void][CfgWin.Broadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, $area, 2, 3000, [ref]$result)
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Done 'File Explorer restarted'
}

# --- Screen: resolution, refresh rate and scale ------------------------------
# Only modes the monitor itself reports are offered. "Recommended" is the monitor's preferred mode (what
# Settings marks as Recommended). After a resolution or refresh change: Enter keeps it, otherwise it goes
# back by itself after 15 seconds, like Settings does. Scale uses the same call as Settings (DisplayConfig,
# not documented by Microsoft), relative to the recommended scale.

$DisplayApiSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace CfgWin {
    // Displays: active monitors (DisplayConfig), their modes (EnumDisplaySettings) and scale.
    public static class DisplayApi {
        [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }

        // ---- GDI modes (resolution and refresh rate)
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields;
            public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string device, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr param);

        const int ENUM_CURRENT_SETTINGS = -1;
        const int DM_PELSWIDTH = 0x80000, DM_PELSHEIGHT = 0x100000, DM_DISPLAYFREQUENCY = 0x400000;
        const uint CDS_UPDATEREGISTRY = 1, CDS_TEST = 2;

        static DEVMODE NewDevMode() { var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return dm; }

        // Every mode the driver offers: { width, height, refresh, bitsPerPixel }
        public static List<int[]> GetModes(string device) {
            var list = new List<int[]>();
            var dm = NewDevMode();
            for (int i = 0; EnumDisplaySettings(device, i, ref dm); i++) {
                list.Add(new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency, dm.dmBitsPerPel });
                dm = NewDevMode();
            }
            return list;
        }
        public static int[] GetCurrentMode(string device) {
            var dm = NewDevMode();
            if (!EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref dm)) return null;
            return new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency, dm.dmBitsPerPel };
        }
        // 0 = OK. test: only asks the driver whether it would accept the mode.
        public static int SetMode(string device, int width, int height, int refresh, bool test) {
            var dm = NewDevMode();
            if (!EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref dm)) return -100;
            dm.dmPelsWidth = width; dm.dmPelsHeight = height; dm.dmDisplayFrequency = refresh;
            dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
            return ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, test ? CDS_TEST : CDS_UPDATEREGISTRY, IntPtr.Zero);
        }

        // ---- DisplayConfig: active monitors, their names, preferred mode and scale
        [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator, Denominator; }
        [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id, modeInfoIdx, statusFlags; }
        [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET_INFO {
            public LUID adapterId; public uint id, modeInfoIdx, outputTechnology, rotation, scaling;
            public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
        }
        [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }
        [StructLayout(LayoutKind.Sequential, Size = 64)] public struct MODE_INFO { public uint infoType, id; public LUID adapterId; }
        [StructLayout(LayoutKind.Sequential)] public struct HEADER { public int type; public uint size; public LUID adapterId; public uint id; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct SOURCE_NAME { public HEADER header; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct TARGET_NAME {
            public HEADER header; public uint flags, outputTechnology; public ushort edidManufactureId, edidProductCodeId; public uint connectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
        }
        // Preferred mode: width and height, then the target mode (48 bytes, starting at offset 32 because it
        // holds 64-bit values) that isn't needed here. Total 80 bytes.
        [StructLayout(LayoutKind.Sequential, Size = 80)] public struct PREFERRED_MODE { public HEADER header; public uint width, height; }
        // Scale, relative to the recommended one (0 = recommended)
        [StructLayout(LayoutKind.Sequential)] public struct DPI_GET { public HEADER header; public int minScaleRel, curScaleRel, maxScaleRel; }
        [StructLayout(LayoutKind.Sequential)] public struct DPI_SET { public HEADER header; public int scaleRel; }

        [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
        [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PATH_INFO[] paths, ref uint numModes, [Out] MODE_INFO[] modes, IntPtr topology);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME info);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME info);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref PREFERRED_MODE info);
        [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref DPI_GET info);
        [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref DPI_SET info);

        const uint QDC_ONLY_ACTIVE_PATHS = 2;

        public class Display {
            public string Device;            // \\.\DISPLAY1 (for the GDI calls)
            public string Name;              // monitor name, e.g. "DELL S2721DGF" (laptop panels usually have none)
            public bool Internal;            // the laptop's own screen
            public LUID Adapter; public uint SourceId;
            public int PreferredWidth, PreferredHeight;
            public bool HasScale; public int MinScaleRel, CurScaleRel, MaxScaleRel;
        }

        static HEADER Header(int type, Type t, LUID adapter, uint id) {
            var h = new HEADER(); h.type = type; h.size = (uint)Marshal.SizeOf(t); h.adapterId = adapter; h.id = id; return h;
        }

        public static List<Display> GetDisplays() {
            var list = new List<Display>();
            uint np, nm;
            if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm) != 0) return list;
            var paths = new PATH_INFO[np]; var modes = new MODE_INFO[nm];
            if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return list;
            for (int i = 0; i < np; i++) {
                var p = paths[i];
                var d = new Display();
                d.Adapter = p.sourceInfo.adapterId; d.SourceId = p.sourceInfo.id;

                var src = new SOURCE_NAME(); src.header = Header(1, typeof(SOURCE_NAME), p.sourceInfo.adapterId, p.sourceInfo.id);
                if (DisplayConfigGetDeviceInfo(ref src) != 0) continue;
                d.Device = src.viewGdiDeviceName;

                var tn = new TARGET_NAME(); tn.header = Header(2, typeof(TARGET_NAME), p.targetInfo.adapterId, p.targetInfo.id);
                if (DisplayConfigGetDeviceInfo(ref tn) == 0) d.Name = tn.monitorFriendlyDeviceName;
                d.Internal = p.targetInfo.outputTechnology == 0x80000000;   // DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL

                var pm = new PREFERRED_MODE(); pm.header = Header(3, typeof(PREFERRED_MODE), p.targetInfo.adapterId, p.targetInfo.id);
                if (DisplayConfigGetDeviceInfo(ref pm) == 0) { d.PreferredWidth = (int)pm.width; d.PreferredHeight = (int)pm.height; }

                var dpi = new DPI_GET(); dpi.header = Header(-3, typeof(DPI_GET), p.sourceInfo.adapterId, p.sourceInfo.id);
                if (DisplayConfigGetDeviceInfo(ref dpi) == 0) {
                    d.HasScale = true; d.MinScaleRel = dpi.minScaleRel; d.CurScaleRel = dpi.curScaleRel; d.MaxScaleRel = dpi.maxScaleRel;
                }
                list.Add(d);
            }
            return list;
        }

        // Scale steps Windows uses, in %. Index of the recommended one = -MinScaleRel.
        public static readonly int[] ScaleSteps = { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };

        // 0 = OK. scaleRel: steps relative to the recommended scale.
        public static int SetScale(LUID adapter, uint sourceId, int scaleRel) {
            var s = new DPI_SET(); s.header = Header(-4, typeof(DPI_SET), adapter, sourceId); s.scaleRel = scaleRel;
            return DisplayConfigSetDeviceInfo(ref s);
        }
    }
}
'@

function Initialize-DisplayApi { if (-not ('CfgWin.DisplayApi' -as [type])) { Add-Type -TypeDefinition $DisplayApiSource } }

function Format-Resolution([int]$Width, [int]$Height) { "$Width × $Height" }

# Enter keeps the new mode; with no key in 15 seconds, returns $false (the caller goes back).
function Confirm-DisplayKeep {
    if ($script:Panel) { return [bool](Request-Panel @{ type = 'keep'; question = 'Keep this screen setting?'; seconds = 15 }) }
    Write-Host '  Press Enter to keep it. It goes back by itself in 15 seconds.' -ForegroundColor Yellow
    if (($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected) { [void](Read-Host); return $true }
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Set-DisplayChoice($Change) {
    $label = if ($Change.Multi) { " — $($Change.Name)" } else { '' }
    if ($Change.ChangeMode) {
        $mode = "$(Format-Resolution $Change.Width $Change.Height), $($Change.Hz) Hz"
        if ([CfgWin.DisplayApi]::SetMode($Change.Device, $Change.Width, $Change.Height, $Change.Hz, $true) -ne 0) {
            Write-Host "  [ERROR] $("Windows did not accept $mode; nothing changed.")" -ForegroundColor Red
        } elseif ([CfgWin.DisplayApi]::SetMode($Change.Device, $Change.Width, $Change.Height, $Change.Hz, $false) -ne 0) {
            Write-Host "  [ERROR] $("could not change to $mode.")" -ForegroundColor Red
        } elseif (Confirm-DisplayKeep) {
            Write-Change ('Resolution and refresh rate' + $label) $mode $true
        } else {
            [void][CfgWin.DisplayApi]::SetMode($Change.Device, $Change.Old[0], $Change.Old[1], $Change.Old[2], $false)
            Write-Host "  [--] $("Back to $(Format-Resolution $Change.Old[0] $Change.Old[1]), $($Change.Old[2]) Hz")" -ForegroundColor DarkGray
        }
    }
    if ($null -ne $Change.ScaleRel) {
        if ([CfgWin.DisplayApi]::SetScale($Change.Adapter, $Change.SourceId, $Change.ScaleRel) -eq 0) {
            Write-Change ('Scale' + $label) "$($Change.ScalePct)%" $true
        } else {
            Write-Host "  [ERROR] Windows did not accept the scale; change it in Settings → System → Display." -ForegroundColor Red
        }
    }
}

#endregion


#region ==================== 5. SYSTEM ====================

function Enable-LongPaths {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
    Write-Done 'Long paths: allowed'
}

function Enable-EndTask {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
    Write-Done '"End task" on the taskbar: on'
    $script:RestartExplorer = $true
}

# "Inline" mode: the command runs in the same terminal window, like on Linux.
function Enable-Sudo {
    & "$env:SystemRoot\System32\sudo.exe" config --enable normal | Out-Null
    Write-Done 'Sudo: enabled, inline mode'
}

function Enable-ClipboardHistory {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Clipboard' 'EnableClipboardHistory' 1
    Write-Done 'Clipboard history (Win+V): on'; Write-Host '  This PC only, no sync.' -ForegroundColor DarkGray
}

function Disable-MouseAcceleration {
    $mouse = 'HKCU:\Control Panel\Mouse'
    Set-Reg $mouse 'MouseSpeed'      '0' 'String'
    Set-Reg $mouse 'MouseThreshold1' '0' 'String'
    Set-Reg $mouse 'MouseThreshold2' '0' 'String'
    Write-Done 'Enhance pointer precision: off'; Write-Host '  Takes effect after signing out and back in.' -ForegroundColor DarkGray
}

# 506 = Sticky Keys off and WITHOUT the 5x Shift shortcut (Windows default is 510).
# The feature is still available in Settings → Accessibility → Keyboard.
function Disable-StickyKeysShortcut {
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Write-Done 'Sticky Keys shortcut (5x Shift): off'
}

function Get-RegValue([string]$Path, [string]$Name) {
    (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

# Num Lock on when Windows starts: on the sign-in screen (.DEFAULT) and for your user.
# Only bit 2 (Num Lock) is turned on; the other bits of the value are kept.
# Windows saves your user's Num Lock state over this value when you sign out or shut down: with Num Lock
# off at that moment, it came back off after signing in. So it is also turned on now, and stays saved as on.
$NumLockKeys = @('Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard', 'HKCU:\Control Panel\Keyboard')
function Enable-NumLockAtStartup {
    foreach ($k in $NumLockKeys) {
        $n = [int64]0; [void][int64]::TryParse([string](Get-RegValue $k 'InitialKeyboardIndicators'), [ref]$n)
        Set-Reg $k 'InitialKeyboardIndicators' ([string]($n -bor 2)) 'String'
    }
    Add-Type -AssemblyName System.Windows.Forms
    if (-not [Windows.Forms.Control]::IsKeyLocked('NumLock')) {
        if (-not ('CfgWin.Keys' -as [type])) {
            Add-Type -Namespace CfgWin -Name Keys -MemberDefinition @'
[DllImport("user32.dll")]
public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
'@
        }
        # VK_NUMLOCK = 0x90 (scan code 0x45): pressed and released. KEYEVENTF_EXTENDEDKEY = 1, KEYUP = 2
        [CfgWin.Keys]::keybd_event(0x90, 0x45, 1, [UIntPtr]::Zero)
        [CfgWin.Keys]::keybd_event(0x90, 0x45, 3, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 100
    }
    $now = if ([Windows.Forms.Control]::IsKeyLocked('NumLock')) { 'on now too' } else { 'turn it on with the key once, so Windows saves it' }
    Write-Done "Num Lock: on when Windows starts ($now)"
}

# Fast Startup makes "Shut down" a partial hibernation. Off = a real shutdown every time: drivers and
# updates load fresh and dual boot works. Startup gets a few seconds slower. Restart is not affected.
function Disable-FastStartup {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Write-Done 'Fast Startup: off'; Write-Host '  "Shut down" now really shuts down.' -ForegroundColor DarkGray
}

# Blue screen (BSoD) also shows the technical parameters of the error, which helps to look up the cause.
# Hibernation off: Windows deletes hiberfil.sys (about 40% of the RAM, on drive C:). Fast Startup and the
# Hibernate option in the power menu need it, so they go away too. Sleep is not affected.
function Disable-Hibernation {
    & powercfg.exe /hibernate off
    if ($LASTEXITCODE -ne 0) { throw "powercfg ended with code $LASTEXITCODE" }
    Write-Done 'Hibernation: off'; Write-Host '  hiberfil.sys was deleted. Fast Startup and the Hibernate option are gone too.' -ForegroundColor DarkGray
}

function Enable-VerboseBsod {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 1
    Write-Done 'Detailed blue screen: on'; Write-Host '  Only shows up if the PC crashes.' -ForegroundColor DarkGray
}

# --- Power: screen and sleep times ------------------------------------------
# Same as Settings → System → Power, in the active power plan. Minutes; 0 = never.
# AC = plugged in, DC = on battery.

$ScreenChoices    = 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 0
$SleepChoices     = 5, 10, 15, 20, 30, 45, 60, 120, 180, 0
$HibernateChoices = 30, 60, 120, 180, 240, 360, 0

# Current value in minutes. "powercfg /q" is translated, but its numbers aren't: the last two are
# the AC and DC values, in seconds.
function Get-PowerTimeout([string]$Sub, [string]$Setting, [bool]$Battery) {
    $hex = @(powercfg /q SCHEME_CURRENT $Sub $Setting | Select-String '0x[0-9a-fA-F]+' -AllMatches | ForEach-Object { $_.Matches.Value })
    if ($hex.Count -lt 2) { return $null }
    return [int][math]::Round([Convert]::ToInt64($hex[$(if ($Battery) { -1 } else { -2 })], 16) / 60)
}

# Hibernation turned on in this PC (HibernateEnabled, or Windows' default when it was never changed).
function Test-HibernateEnabled {
    $power = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue
    $value = if ($null -ne $power.HibernateEnabled) { $power.HibernateEnabled } else { $power.HibernateEnabledDefault }
    return $value -eq 1
}

function Format-Minutes([int]$Minutes) {
    if ($Minutes -eq 0) { return 'never' }
    if ($Minutes % 60 -eq 0) { $h = $Minutes / 60; return "$h hour$(if ($h -gt 1) { 's' })" }
    return "$Minutes min"
}

# $Values: "powercfg /change" names (monitor-timeout-ac, standby-timeout-dc...) -> minutes.
function Set-PowerTimeouts($Values) {
    foreach ($name in $Values.Keys) {
        powercfg /change $name $Values[$name]
        if ($LASTEXITCODE -ne 0) { throw "powercfg /change $name" }
    }
    Write-Done 'Times set in the active power plan'
}

#endregion


#region ==================== 6. NETWORK ====================

# Sets DNS on every physical adapter (Wi-Fi and Ethernet, even disconnected ones; skips VPNs and
# virtual adapters). On Windows 11 turns on "On (automatic template)" for each server:
# DohFlags = 1 per adapter — Windows cmdlets don't write this; it is the same value the Settings page uses.
function Set-DNS([string[]]$V4, [string[]]$V6) {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
    $all = @($V4) + @($V6)
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled')
    if (-not $adapters) { throw 'no physical network adapter found' }
    foreach ($adapter in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $all -ErrorAction Stop
        if ($isWin11) {
            $doh = "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings"
            Remove-Item "$doh\Doh", "$doh\Doh6" -Recurse -Force -ErrorAction SilentlyContinue   # clear old servers
            foreach ($ip in $V4) { Set-Reg "$doh\Doh\$ip"  'DohFlags' 1 'QWord' }
            foreach ($ip in $V6) { Set-Reg "$doh\Doh6\$ip" 'DohFlags' 1 'QWord' }
        }
        Write-Done "$($adapter.Name): $($all -join ', ')$(if ($isWin11) { ' (encrypted, automatic template)' })"
    }
    Clear-DnsClientCache
    if (-not $V6) { Write-Host '  IPv6: kept automatic, from the router.' -ForegroundColor DarkGray }
}

#endregion


#region ==================== 7. OPTIONS ====================

# Every option, written once. The panel shows them all (-Describe writes them to a file), sends back what
# you chose (-Answers) and nothing is asked; without the panel they are asked here, one by one.
#   toggle     on or off                       choice     a few options side by side
#   select     a list; Parent + OptionsBy: the options depend on another select (refresh rate by resolution)
#   checklist  items to check                  text       typed (Validate = ipv4 or ipv6; Optional)
#   header     a title inside a tab
#   When = @{ field = <id>; is = <value> }: shown only while that field has that value.
# Label: what it is, short. Desc: what changes for you. Warn: a risk, when there is one.

# Opt and New-Field: in the PANEL region.

$themeIds    = @('Keep', 'Light', 'Dark');          $themeNames    = @('Default', 'Light', 'Dark')
$taskbarIds  = @('Keep', 'Center', 'Left');         $taskbarNames  = @('Default', 'Center', 'Left')
$searchIds   = @('Keep', 'Hidden', 'Icon', 'Box');  $searchNames   = @('Default', 'Hidden', 'Icon only', 'Search box')
$taskViewIds = @('Keep', 'Show', 'Hide');           $taskViewNames = @('Default', 'Show', 'Hide')
function Get-ChoiceOptions([string[]]$Ids, [string[]]$Names) { @(for ($i = 1; $i -lt $Ids.Count; $i++) { Opt $Ids[$i] $Names[$i] }) }   # without "Keep"

# Preinstalled apps on this PC (see Get-AppCatalog); in the list by their first package name
Write-Loading 'Listing the preinstalled apps' 20
$presentApps = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) +
               @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName)
$appRows = @(Get-AppCatalog | Where-Object { $row = $_; $row.Packages | Where-Object { $presentApps -contains $_ } })

# --- Screen: the same reading of each display for the options and for applying them
Write-Loading 'Reading the screens' 55
$script:Displays = @()
try { Initialize-DisplayApi; $script:Displays = @([CfgWin.DisplayApi]::GetDisplays()) } catch { }

function Get-DisplayInfo($Display, [int]$Number, [int]$Count) {
    $cur = [CfgWin.DisplayApi]::GetCurrentMode($Display.Device)
    if (-not $cur) { return $null }
    $modes = @([CfgWin.DisplayApi]::GetModes($Display.Device) | Where-Object { $_[3] -eq 32 -and $_[0] -ge 800 })
    if (-not $modes) { return $null }
    # Every resolution the monitor supports, from the largest to the smallest
    $all = @($modes | ForEach-Object { '{0}x{1}' -f $_[0], $_[1] } | Select-Object -Unique |
             Sort-Object { [int]($_ -split 'x')[0] * [int]($_ -split 'x')[1] }, { [int]($_ -split 'x')[0] } -Descending)
    $info = [pscustomobject]@{
        Name = $(if ($Display.Name) { $Display.Name } elseif ($Display.Internal) { 'Laptop screen' } else { "Screen $Number" })
        Cur = $cur; CurKey = ('{0}x{1}' -f $cur[0], $cur[1]); All = $all; Modes = $modes
        RecKey = $(if ($Display.PreferredWidth) { '{0}x{1}' -f $Display.PreferredWidth, $Display.PreferredHeight } else { $all[0] })
        Steps = [CfgWin.DisplayApi]::ScaleSteps; RecScale = -1; CurScale = -1; MaxScale = -1
    }
    if ($Display.HasScale) {
        $info.RecScale = -$Display.MinScaleRel
        $info.CurScale = $info.RecScale + $Display.CurScaleRel
        $info.MaxScale = [Math]::Min($info.Steps.Count - 1, $info.RecScale + $Display.MaxScaleRel)
    }
    return $info
}

function Get-DisplayRates($Info, [string]$Key) {
    $w = [int]($Key -split 'x')[0]; $h = [int]($Key -split 'x')[1]
    @($Info.Modes | Where-Object { $_[0] -eq $w -and $_[1] -eq $h } | ForEach-Object { $_[2] } | Where-Object { $_ -gt 1 } | Sort-Object -Unique -Descending)
}

function Get-DisplayFields {
    $count = $script:Displays.Count
    for ($i = 0; $i -lt $count; $i++) {
        $n = $i + 1
        $info = Get-DisplayInfo $script:Displays[$i] $n $count
        if (-not $info) { continue }
        $now = "Now: $(Format-Resolution $info.Cur[0] $info.Cur[1]), $($info.Cur[2]) Hz" + $(if ($info.CurScale -ge 0) { ", $($info.Steps[$info.CurScale])%" } else { '' })
        New-Field 'Screen' "Screen${n}" 'header' $info.Name $now $null

        $resOptions = @($info.All | ForEach-Object {
            $wh = $_ -split 'x'
            Opt $_ ((Format-Resolution $wh[0] $wh[1]) + $(if ($_ -eq $info.RecKey) { ' · recommended' } else { '' }) + $(if ($_ -eq $info.CurKey) { ' · current' } else { '' }))
        })
        New-Field 'Screen' "Screen${n}Res" 'select' 'Resolution' 'A new resolution goes back by itself after 15 seconds, unless you keep it.' '' @{ options = $resOptions }

        # Refresh rates of each resolution ("current" = no resolution picked: the current one)
        $byRes = [ordered]@{}
        foreach ($key in @('current') + $info.All) {
            $k = if ($key -eq 'current') { $info.CurKey } else { $key }
            $byRes[$key] = @(Get-DisplayRates $info $k | ForEach-Object {
                Opt "$_" ("$_ Hz" + $(if ($k -eq $info.CurKey -and $_ -eq $info.Cur[2]) { ' · current' } else { '' }))
            })
        }
        New-Field 'Screen' "Screen${n}Hz" 'select' 'Refresh rate' 'Higher is smoother, if the monitor supports it.' '' @{ options = $byRes['current']; parent = "Screen${n}Res"; optionsBy = $byRes }

        if ($info.MaxScale -ge 0) {
            $scaleOptions = @(for ($s = 0; $s -le $info.MaxScale; $s++) {
                Opt "$s" ("$($info.Steps[$s])%" + $(if ($s -eq $info.RecScale) { ' · recommended' } else { '' }) + $(if ($s -eq $info.CurScale) { ' · current' } else { '' }))
            })
            New-Field 'Screen' "Screen${n}Scale" 'select' 'Scale' 'Size of text and apps.' '' @{ options = $scaleOptions }
        }
    }
}

# What to change on one display, or $null when everything stays "Default".
function Get-DisplayChange([int]$Index, $Res, $Hz, $Scale) {
    $count = $script:Displays.Count
    $d = $script:Displays[$Index]
    $info = Get-DisplayInfo $d ($Index + 1) $count
    if (-not $info) { return $null }
    $cur = $info.Cur
    $newRes = $Res -and "$Res" -ne 'Keep' -and $info.All -contains "$Res"
    $key = if ($newRes) { "$Res" } else { $info.CurKey }
    $w = [int]($key -split 'x')[0]; $h = [int]($key -split 'x')[1]
    $rates = @(Get-DisplayRates $info $key)
    $hzValue = if ($Hz -and "$Hz" -ne 'Keep' -and $rates -contains [int]"$Hz") { [int]"$Hz" } else { $null }
    # A new resolution with the default rate: the current rate if it exists there, otherwise the highest
    if ($newRes -and -not $hzValue) { $hzValue = if ($rates -contains $cur[2]) { $cur[2] } else { $rates[0] } }
    $changeMode = ($key -ne $info.CurKey) -or ($hzValue -and $hzValue -ne $cur[2])

    $scaleRel = $null; $scalePct = $null
    if ($info.MaxScale -ge 0 -and $Scale -and "$Scale" -ne 'Keep') {
        $s = [int]"$Scale"
        if ($s -ge 0 -and $s -le $info.MaxScale -and $s -ne $info.CurScale) { $scaleRel = $s - $info.RecScale; $scalePct = $info.Steps[$s] }
    }
    if (-not $changeMode -and $null -eq $scaleRel) { return $null }
    if (-not $hzValue) { $hzValue = $cur[2] }
    $parts = @()
    if ($changeMode) { $parts += "$(Format-Resolution $w $h), $hzValue Hz" }
    if ($null -ne $scaleRel) { $parts += "scale $scalePct%" }
    [pscustomobject]@{
        Name = $info.Name; Multi = ($count -gt 1); Device = $d.Device; Adapter = $d.Adapter; SourceId = $d.SourceId
        ChangeMode = [bool]$changeMode; Width = $w; Height = $h; Hz = $hzValue; Old = $cur
        ScaleRel = $scaleRel; ScalePct = $scalePct
        Text = $(if ($count -gt 1) { "$($info.Name): " } else { '' }) + ($parts -join ', ')
    }
}

# --- Power: one select per time, starting at the current value
function Get-MinuteOptions([int[]]$Choices, $Current) {
    $values = @($Choices)
    if ($null -ne $Current -and $values -notcontains $Current) {
        $values = @($values + $Current | Sort-Object { if ($_ -eq 0) { [int]::MaxValue } else { $_ } })
    }
    @($values | ForEach-Object { Opt $_ ((Format-Minutes $_) + $(if ($_ -eq $Current) { ' · current' } else { '' })) })
}

Write-Loading 'Reading the power settings' 65
$canHibernate = Test-HibernateEnabled
$powerModes = @(@{ Key = 'ac'; Battery = $false; Label = 'Plugged in' })
if ($hasBattery) { $powerModes += @{ Key = 'dc'; Battery = $true; Label = 'On battery' } }

function Get-PowerFields {
    # Only when hibernation is on; while this is on, the "Hibernate after" times hide
    if ($canHibernate) {
        $warn = if ($hasBattery) { 'On a laptop, when the battery runs out the PC shuts down instead of hibernating: save your work before it does.' } else { '' }
        New-Field 'Power' 'NoHibernate' 'toggle' 'Turn off hibernation' 'Frees the space hiberfil.sys takes on drive C:, often several GB. Fast Startup and the Hibernate option go away too; sleep keeps working.' $false @{ warn = $warn }
    }
    $hibernateShown = @{ field = 'NoHibernate'; is = 'False' }
    foreach ($m in $powerModes) {
        if ($hasBattery) { New-Field 'Power' "power-$($m.Key)" 'header' $m.Label '' $null }
        $cur = Get-PowerTimeout SUB_VIDEO VIDEOIDLE $m.Battery
        New-Field 'Power' "monitor-timeout-$($m.Key)" 'select' 'Turn off the screen after' "Now: $(Format-Minutes $cur)" '' @{ options = (Get-MinuteOptions $ScreenChoices $cur) }
        $cur = Get-PowerTimeout SUB_SLEEP STANDBYIDLE $m.Battery
        New-Field 'Power' "standby-timeout-$($m.Key)" 'select' 'Sleep after' "Now: $(Format-Minutes $cur)" '' @{ options = (Get-MinuteOptions $SleepChoices $cur) }
        # Only when hibernation is on: turning it on (hiberfil.sys) is not this script's call
        if ($canHibernate) {
            $cur = Get-PowerTimeout SUB_SLEEP HIBERNATEIDLE $m.Battery
            New-Field 'Power' "hibernate-timeout-$($m.Key)" 'select' 'Hibernate after' "Now: $(Format-Minutes $cur)" '' @{ options = (Get-MinuteOptions $HibernateChoices $cur); when = $hibernateShown }
        }
    }
}

function Get-Fields {
    $T = 'Privacy'; $A = 'Apps'; $L = 'Appearance'; $E = 'File Explorer'; $U = 'System'; $N = 'Network'; $M = 'Misc'

    New-Field $T 'Telemetry' 'toggle' 'Turn off telemetry' 'Windows stops sending usage and diagnostic data to Microsoft. Widgets are turned off too.' $false
    New-Field $T 'Suggestions' 'toggle' 'Turn off ads and suggestions' 'No tips, no suggestions in Start and Settings, and no apps like Candy Crush installed without asking.' $false
    New-Field $T 'Edge' 'toggle' 'Quiet down Edge' 'Turns off Edge telemetry, running in the background, the sidebar, Copilot and shopping offers.' $false
    if ($isWin11) { New-Field $T 'NoRecall' 'toggle' 'Remove Recall' 'Recall saves screenshots of everything you do. It is removed and can''t be turned on again.' $false }
    New-Field $T 'Security' 'toggle' 'Block unwanted apps' 'Windows Security blocks potentially unwanted apps and downloads, like installers that bundle extras, and shows fewer minor notices.' $false
    New-Field $T 'HideAreas' 'toggle' 'Hide account areas in Windows Security' '"Account protection" and "Device security" go away. They only ask you to sign in with a Microsoft account; nothing is turned off.' $false
    New-Field $T 'NoDeviceApps' 'toggle' 'Don''t install device apps' 'Windows stops downloading manufacturer apps when you connect a mouse, keyboard or headset. Drivers still install.' $false
    New-Field $T 'NoWpbt' 'toggle' 'Block programs from the motherboard' 'Apps like Armoury Crate and Lenovo Vantage stop installing themselves at startup. Only a Windows setting: the BIOS is not touched, and formatting brings it back to on.' $false

    if ($appRows) {
        New-Field $A 'RemoveApps' 'checklist' 'Apps to remove' "$($appRows.Count) of the $(@(Get-AppCatalog).Count) preinstalled apps TidyWin knows are still on this PC; the ones already removed don't show up. They are removed for every user and can be installed again from the Microsoft Store." @() @{
            items = @($appRows | ForEach-Object { [ordered]@{ value = $_.Packages[0]; label = $_.Label; note = $_.Note; group = $_.Group; checked = $false } })
            warn  = 'Without the Xbox apps, Game Pass games and games that use Xbox sign-in stop working.'
        }
    } else {
        New-Field $A 'RemoveAppsDone' 'header' 'Apps to remove' 'All the preinstalled apps TidyWin knows are already removed from this PC.' $null
    }
    $oneDriveWarn = if ($foldersInOneDrive) { "Your $($foldersInOneDrive -join ', ') folders are inside OneDrive. Turn off folder backup in OneDrive before removing it." } else { '' }
    New-Field $A 'OneDrive' 'toggle' 'Remove OneDrive' 'Uninstalls OneDrive and keeps it from coming back. Files already in your OneDrive stay online.' $false @{ warn = $oneDriveWarn }
    New-Field $A 'NoEdgeShortcut' 'toggle' 'Delete the Edge shortcut from the Desktop' 'Edge updates stop putting it back.' $false
    New-Field $A 'NoStartAds' 'toggle' 'Unpin ads from Start' 'Unpins shortcuts like LinkedIn, Spotify and TikTok. Your other pins stay.' $false

    New-Field $L 'Theme' 'choice' 'Theme' 'Light or dark for Windows and apps, with the matching Windows wallpaper. Windows Spotlight is turned off.' '' @{ options = (Get-ChoiceOptions $themeIds $themeNames) }
    if ($isWin11) { New-Field $L 'Taskbar' 'choice' 'Taskbar icons' 'Where the Start button and the app icons sit.' '' @{ options = (Get-ChoiceOptions $taskbarIds $taskbarNames) } }
    New-Field $L 'Search' 'choice' 'Search on the taskbar' 'Hidden, just the icon, or the full search box.' '' @{ options = (Get-ChoiceOptions $searchIds $searchNames) }
    New-Field $L 'TaskView' 'choice' 'Task View button' 'Shows your open windows and desktops. Win+Tab works either way.' '' @{ options = (Get-ChoiceOptions $taskViewIds $taskViewNames) }
    New-Field $L 'ClearPins' 'toggle' 'Unpin everything from the taskbar' 'Removes every pinned icon, File Explorer and Edge included. Nothing is uninstalled.' $false
    if ($isWin11) { New-Field $L 'ClassicMenu' 'toggle' 'Classic right-click menu' 'The full menu opens right away, without "Show more options".' $false }
    New-Field $L 'NoSnap' 'toggle' 'Turn off Snap windows' 'Windows stop resizing when you drag them to the screen edges, and the Snap layouts menu goes away.' $false

    New-Field $E 'ShowExtensions' 'toggle' 'Show file extensions' 'File names show their end, like .txt and .exe, so you can tell files apart.' $false
    New-Field $E 'ShowHidden' 'toggle' 'Show hidden files' 'Hidden files and folders show up. Protected system files stay hidden.' $false
    New-Field $E 'HideFrequent' 'toggle' 'Hide frequent folders' 'Quick access stops listing the folders you open most.' $false
    New-Field $E 'HideRecent' 'toggle' 'Hide recent files' 'File Explorer stops listing the files you opened recently.' $false
    New-Field $E 'NoNewAppAlert' 'toggle' 'Don''t ask which app to use after installing one' 'No "How do you want to open this file?" after an install: files keep opening with the app you use now. Open with still lets you change it.' $false
    New-Field $E 'NoFolderSniff' 'toggle' 'Open large folders faster' 'File Explorer stops guessing each folder''s type. The views you saved for each folder are reset.' $false
    if ($isWin11) { New-Field $E 'HideHomeGallery' 'toggle' 'Remove Home and Gallery' 'File Explorer opens in This PC.' $false }

    Get-DisplayFields

    New-Field $U 'ClipboardHistory' 'toggle' 'Clipboard history' 'Win+V shows the things you copied before.' $false
    if ($hasEndTask) { New-Field $U 'EndTask' 'toggle' 'End task on the taskbar' 'Right-click a frozen app on the taskbar to close it.' $false }
    New-Field $U 'NoStickyKeys' 'toggle' 'Turn off the Sticky Keys prompt' 'No prompt when you press Shift five times. Sticky Keys is still in Settings.' $false
    New-Field $U 'NoMouseAccel' 'toggle' 'Turn off mouse acceleration' 'The pointer moves the same distance however fast you move the mouse. Applies after signing out.' $false
    New-Field $U 'LongPaths' 'toggle' 'Allow long file paths' 'Programs can use paths longer than 260 characters.' $false
    New-Field $U 'VerboseBsod' 'toggle' 'Error details on the blue screen' 'When Windows crashes, the blue screen shows the technical cause, which helps when asking for help.' $false
    New-Field $U 'NoFastStartup' 'toggle' 'Turn off Fast Startup' '"Shut down" fully shuts down, which avoids some driver and dual-boot problems. Startup takes a few seconds longer.' $false

    Get-PowerFields

    $dnsDesc = if ($isWin11) { 'Use DNS servers you choose on every Wi-Fi and Ethernet adapter, encrypted when Windows supports the server, like Cloudflare, Google and Quad9.' }
               else { 'Use DNS servers you choose on every Wi-Fi and Ethernet adapter.' }
    New-Field $N 'Dns' 'toggle' 'Set DNS servers' $dnsDesc $false @{ warn = $(if (-not $isWin11) { 'Windows 10 can''t encrypt DNS: the servers are set without encryption.' } else { '' }) }
    $dns = @{ field = 'Dns'; is = $true }
    New-Field $N 'Dns4a' 'text' 'Preferred IPv4 DNS' '' '' @{ placeholder = '1.1.1.1'; validate = 'ipv4'; optional = $false; when = $dns }
    New-Field $N 'Dns4b' 'text' 'Alternate IPv4 DNS' '' '' @{ placeholder = '1.0.0.1'; validate = 'ipv4'; optional = $true; when = $dns }
    New-Field $N 'Dns6a' 'text' 'Preferred IPv6 DNS' 'Leave it empty to keep the router''s IPv6 DNS.' '' @{ placeholder = '2606:4700:4700::1111'; validate = 'ipv6'; optional = $true; when = $dns }
    New-Field $N 'Dns6b' 'text' 'Alternate IPv6 DNS' '' '' @{ placeholder = '2606:4700:4700::1001'; validate = 'ipv6'; optional = $true; when = $dns }

    if ($isWin11 -and $hasBattery) { New-Field $M 'BatteryPercent' 'toggle' 'Show the battery percentage' 'Next to the battery icon on the taskbar.' $false }
    New-Field $M 'ThinBorder' 'toggle' 'Thinner resize border' 'The invisible edge used to resize windows gets smaller, so you resize less by accident. Applies after signing out.' $false
    New-Field $M 'UnpinMusic' 'toggle' 'Unpin Music from Quick access' 'The Music folder itself stays.' $false
    New-Field $M 'RootFolders' 'toggle' 'Tidy up drive C:' 'Hides the inetpub folder, which a Windows update needs, and deletes the empty PerfLogs folder.' $false
    New-Field $M 'NumLock' 'toggle' 'Num Lock on at startup' 'The number keys work right away, on the sign-in screen too.' $false
    if ($hasSudo) { New-Field $M 'Sudo' 'toggle' 'Turn on sudo' 'Run a command as administrator from a normal terminal.' $false }
}

function Test-FieldShown($Field, $Values) {
    if (-not $Field.when) { return $true }
    return "$($Values[$Field.when.field])" -eq "$($Field.when.is)"
}

# A typed IP address checked and written the standard way; $null when empty or wrong.
function ConvertTo-IPText($Text, [string]$Family) {
    $t = "$Text".Trim()
    if (-not $t) { return $null }
    $ip = $null
    $formatOk = if ($Family -eq 'InterNetwork') { $t -match '^\d{1,3}(\.\d{1,3}){3}$' } else { $t -match ':' }
    if ($formatOk -and [System.Net.IPAddress]::TryParse($t, [ref]$ip) -and $ip.AddressFamily -eq $Family) { return $ip.ToString() }
    Write-Host "  Not a valid address, skipped: $t" -ForegroundColor DarkYellow
    return $null
}

# Without the panel: each option as a question, in order.
function Read-FieldsFromConsole($Fields, $Values) {
    $tab = $null
    foreach ($f in $Fields) {
        if (-not (Test-FieldShown $f $Values)) { continue }
        if ($f.tab -ne $tab) { Write-Host "`n  $($f.tab)" -ForegroundColor Cyan; $tab = $f.tab }
        switch ($f.kind) {
            'header' { Write-Host "  $($f.label) · $($f.desc)" -ForegroundColor DarkCyan }
            'toggle' { $Values[$f.id] = Ask "$($f.label)?" ([bool]$f.default) }
            'checklist' {
                $rows = @($f.items | ForEach-Object { [pscustomobject]@{ Group = $_.group; Label = $_.label; Note = $_.note; Checked = $_.checked; Value = $_.value } })
                $Values[$f.id] = @(Select-Many $f.label $rows | ForEach-Object { $_.Value })
            }
            'text' {
                $family = if ($f.validate -eq 'ipv6') { 'InterNetworkV6' } else { 'InterNetwork' }
                $Values[$f.id] = "$(Read-IP "$($f.label)$(if ($f.optional) { ', Enter skips' }):" $family ([bool]$f.optional))"
            }
            default {
                # choice and select; "Skip" leaves the setting as it is
                $key = if ($f.parent -and "$($Values[$f.parent])") { "$($Values[$f.parent])" } else { 'current' }
                $options = @(Opt '' 'Skip') + @(if ($f.parent) { $f.optionsBy[$key] } else { $f.options })
                $Values[$f.id] = $options[(Choose "$($f.label):" @($options | ForEach-Object { $_.label }) 0)].value
            }
        }
    }
}

Write-Host "`n$osLabel" -ForegroundColor Green
if ($cv.EditionID -match 'Core' -and -not $Describe) {
    Write-Host '  Windows Home: some policies only work on Pro; the rest works normally.' -ForegroundColor DarkYellow
}

Write-Loading 'Reading the current settings' 75
$fields = @(Get-Fields)

# --- For the panel: every option and its default, then stop
if ($Describe) {
    $notes = @(if ($cv.EditionID -match 'Core') { 'Windows Home: some policies only work on Pro. The rest works normally.' })
    $page = [ordered]@{ tabs = @($fields | ForEach-Object { $_.tab } | Select-Object -Unique); notes = $notes; fields = $fields }
    [IO.File]::WriteAllText($Describe, (ConvertTo-Json $page -Depth 10), (New-Object Text.UTF8Encoding $false))
    return
}

# --- The answers: defaults, then the panel's file or the questions
$values = @{}
foreach ($f in $fields) { if ($f.kind -ne 'header') { $values[$f.id] = $f.default } }
if ($Answers) {
    $json = [IO.File]::ReadAllText($Answers) | ConvertFrom-Json
    foreach ($prop in $json.PSObject.Properties) { if ($values.ContainsKey($prop.Name)) { $values[$prop.Name] = $prop.Value } }   # not $p: it would overwrite $P
} else {
    Write-Host '  Use the arrows and Enter. Nothing comes selected: only what you turn on is applied.'
    Read-FieldsFromConsole $fields $values
}

# --- The answers as the steps below use them
$chosenApps = @($values.RemoveApps)
$displayChanges = @()
for ($i = 0; $i -lt $script:Displays.Count; $i++) {
    $n = $i + 1
    $change = Get-DisplayChange $i $values["Screen${n}Res"] $values["Screen${n}Hz"] $values["Screen${n}Scale"]
    if ($change) { $displayChanges += $change }
}
$power = [ordered]@{}
$parts = @()
foreach ($m in $powerModes) {
    $text = @()
    foreach ($kind in @('monitor', 'standby', 'hibernate')) {
        $id = "$kind-timeout-$($m.Key)"
        if ("$($values[$id])" -notmatch '^\d+$') { continue }        # nothing picked: stays as it is
        if ($kind -eq 'hibernate' -and $values.NoHibernate) { continue }   # hibernation is being turned off
        $power[$id] = [int]$values[$id]
        $text += @{ monitor = 'screen'; standby = 'sleep'; hibernate = 'hibernation' }[$kind] + ' ' + (Format-Minutes $power[$id])
    }
    if ($text) { $parts += $(if ($hasBattery) { "$($m.Label.ToLower()): " } else { '' }) + ($text -join ', ') }
}
$powerText = if ($parts) { $parts -join '; ' } else { 'Keep' }
$dnsV4 = @(); $dnsV6 = @()
if ($values.Dns) {
    foreach ($id in 'Dns4a', 'Dns4b') { $ip = ConvertTo-IPText $values[$id] 'InterNetwork'; if ($ip) { $dnsV4 += $ip } }
    if ($dnsV4) { foreach ($id in 'Dns6a', 'Dns6b') { $ip = ConvertTo-IPText $values[$id] 'InterNetworkV6'; if ($ip) { $dnsV6 += $ip } } }
}
$flag = { param($id) [bool]$values[$id] }
$opt = [ordered]@{
    Telemetry = & $flag 'Telemetry'; Suggestions = & $flag 'Suggestions'
    RemoveApps = @($appRows | Where-Object { $chosenApps -contains $_.Packages[0] } | ForEach-Object { $_.Packages })
    OneDrive = & $flag 'OneDrive'; Edge = & $flag 'Edge'; NoRecall = & $flag 'NoRecall'; NoEdgeShortcut = & $flag 'NoEdgeShortcut'
    Security = & $flag 'Security'; RootFolders = & $flag 'RootFolders'; NoDeviceApps = & $flag 'NoDeviceApps'; NoWpbt = & $flag 'NoWpbt'
    HideAreas = & $flag 'HideAreas'
    Theme = $(if ($themeIds -contains "$($values.Theme)") { "$($values.Theme)" } else { 'Keep' })
    Display = $(if ($displayChanges) { ($displayChanges | ForEach-Object { $_.Text }) -join '; ' } else { 'Keep' })
    Taskbar = $(if ($taskbarIds -contains "$($values.Taskbar)") { "$($values.Taskbar)" } else { 'Keep' })
    Search = $(if ($searchIds -contains "$($values.Search)") { "$($values.Search)" } else { 'Keep' })
    TaskView = $(if ($taskViewIds -contains "$($values.TaskView)") { "$($values.TaskView)" } else { 'Keep' })
    ClearPins = & $flag 'ClearPins'; NoStartAds = & $flag 'NoStartAds'; BatteryPercent = & $flag 'BatteryPercent'
    ShowExtensions = & $flag 'ShowExtensions'; HideFrequent = & $flag 'HideFrequent'; UnpinMusic = & $flag 'UnpinMusic'
    HideRecent = & $flag 'HideRecent'; ShowHidden = & $flag 'ShowHidden'; NoFolderSniff = & $flag 'NoFolderSniff'
    NoNewAppAlert = & $flag 'NoNewAppAlert'
    HideHomeGallery = & $flag 'HideHomeGallery'; ClassicMenu = & $flag 'ClassicMenu'; NoSnap = & $flag 'NoSnap'; ThinBorder = & $flag 'ThinBorder'
    LongPaths = & $flag 'LongPaths'; EndTask = & $flag 'EndTask'; Sudo = & $flag 'Sudo'; ClipboardHistory = & $flag 'ClipboardHistory'
    NoMouseAccel = & $flag 'NoMouseAccel'; NoStickyKeys = & $flag 'NoStickyKeys'; NumLock = & $flag 'NumLock'
    NoFastStartup = & $flag 'NoFastStartup'; VerboseBsod = & $flag 'VerboseBsod'
    NoHibernate = & $flag 'NoHibernate'
    Power = $powerText
    DNS = $(if ($dnsV4) { ($dnsV4 + $dnsV6) -join ', ' } else { 'Keep' })
}

$chosen = @($opt.Keys | Where-Object {
    $v = $opt[$_]
    if ($v -is [bool]) { $v } elseif ($_ -eq 'RemoveApps') { @($v).Count -gt 0 } else { "$v" -ne 'Keep' }
})
if (-not $chosen) { Write-Host "`n  Nothing was selected, so nothing was changed." -ForegroundColor DarkGray; return }

# --- Summary (and, without the panel, the confirmation)
$labels = @{
    Telemetry = 'Telemetry'; Suggestions = 'Suggestions'; RemoveApps = 'Apps to remove'; Display = 'Screen'
    OneDrive = 'OneDrive'; Edge = 'Edge'; Security = 'Security'; HideAreas = 'Hide areas'; RootFolders = 'C: folders'; Theme = 'Theme'; Taskbar = 'Taskbar'
    Search = 'Search'; TaskView = 'Task View'; ClearPins = 'No pins'; NoStartAds = 'No Start ads'
    ShowExtensions = 'Extensions'; HideFrequent = 'No frequent'; UnpinMusic = 'No Music in Quick access'; HideRecent = 'No recent'; HideHomeGallery = 'No Home/Gallery'; ClassicMenu = 'Classic menu'; NoSnap = 'No Snap'; ThinBorder = 'Thin border'
    LongPaths = 'Long paths'; EndTask = 'End task'; Sudo = 'Sudo'; ClipboardHistory = 'Win+V history'
    NoMouseAccel = 'No acceleration'; NoStickyKeys = 'No Sticky Keys'; DNS = 'DNS'
    NoDeviceApps = 'No device apps'; NoWpbt = 'No WPBT'; NoRecall = 'No Recall'; NoEdgeShortcut = 'No Edge shortcut'; NumLock = 'Num Lock'; NoFastStartup = 'No Fast Startup'; BatteryPercent = 'Battery %'; ShowHidden = 'Hidden files'
    NoFolderSniff = 'No folder discovery'; VerboseBsod = 'Detailed blue screen'; NoHibernate = 'No hibernation'; NoNewAppAlert = 'No "new app" prompt'; Power = 'Power'
}
$answerLines = @()      # also written to the log file
if ($chosen) {
    # Only what was chosen, with the names the panel shows
    $names = @{ Display = 'Screen'; Power = 'Screen and sleep times'; DNS = 'DNS servers' }
    foreach ($f in $fields) { if (-not $names.ContainsKey($f.id)) { $names[$f.id] = $f.label } }
    # From the panel you already reviewed them: only the log file gets the list
    if (-not $Answers) { Write-Host "`n  What will be done:" -ForegroundColor Cyan }
    foreach ($key in $chosen) {
        $value = $opt[$key]
        $name = if ($names[$key]) { $names[$key] } else { $labels[$key] }
        $text = if ($value -is [bool]) { '' }
                elseif ($key -eq 'Theme')    { $themeNames[[array]::IndexOf($themeIds, $value)] }
                elseif ($key -eq 'Taskbar')  { $taskbarNames[[array]::IndexOf($taskbarIds, $value)] }
                elseif ($key -eq 'Search')   { $searchNames[[array]::IndexOf($searchIds, $value)] }
                elseif ($key -eq 'TaskView') { $taskViewNames[[array]::IndexOf($taskViewIds, $value)] }
                elseif ($key -eq 'RemoveApps') { @($value | ForEach-Object { Get-AppLabel $_ } | Select-Object -Unique) -join ', ' }
                else { $value }
        $line = if ($text) { "    - ${name}: $text" } else { "    - $name" }
        if (-not $Answers) { Write-Host $line }
        $answerLines += $line
    }
    # The panel already showed what changes and you pressed Apply there
    if (-not $Answers -and -not (Ask 'Apply now?' $true)) { Write-Host 'Nothing was changed.'; return }
}

#endregion


#region ==================== 8. EXECUTION ====================

# --- Log file on the Desktop, starting with the answers
Start-Log
if ($script:LogFile -and $answerLines) {
    Add-Content -LiteralPath $script:LogFile -Value (@('', 'Chosen:') + $answerLines) -Encoding UTF8
}

# --- Older versions saved the answers to %ProgramData%\TidyWin\windows.json; nothing reads it anymore
Remove-Item (Join-Path $env:ProgramData 'TidyWin\windows.json') -Force -ErrorAction SilentlyContinue

# --- Restore point (if there is already one from the last 24 h, Windows just warns and moves on)
Write-Step 'Creating restore point'
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    # Windows creates at most one a day (otherwise it only warns): compare the newest point before and after
    $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
    Checkpoint-Computer -Description 'Before Configure-Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
    if ($after -and (-not $before -or $after.SequenceNumber -ne $before.SequenceNumber)) { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host 'Restore point created' }
    elseif ($after) {
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host "Using the restore point from $($after.ConvertToDateTime($after.CreationTime).ToString('g'))."
        Write-Host '  Windows creates at most one restore point a day.' -ForegroundColor Yellow
    }
    else { throw 'System Restore did not create it' }
} catch {
    Write-Warning "Could not create the restore point: $($_.Exception.Message)"
    if (-not (Ask 'Continue anyway?' $false)) { Write-Host 'Nothing was changed.'; return }
}

# --- Privacy and cleanup
if ($opt.Telemetry) {
    Invoke-Step 'Telemetry: services'                                { Disable-TelemetryServices }
    Invoke-Step 'Telemetry: scheduled tasks (disables, does not delete)' { Disable-TelemetryTasks }
    Invoke-Step 'Telemetry: policies'                               { Set-TelemetryPolicies; Disable-Widgets }
}
if ($opt.Suggestions) { Invoke-Step 'Suggestions, ads and silent app installs' { Disable-Suggestions } }
if ($opt.RemoveApps) {
    Invoke-Step 'Removing apps, for every user' { Remove-Apps $opt.RemoveApps }
    if ($opt.RemoveApps | Where-Object { $XboxApps -contains $_ }) { Invoke-Step 'Game DVR' { Disable-GameDvr } }
    if ($opt.RemoveApps -contains 'Microsoft.ScreenSketch') { Invoke-Step 'Print Screen key' { Set-PrintScreenFree } }
}
if ($opt.OneDrive) { Invoke-Step 'Removing OneDrive'                                          { Remove-OneDrive } }
if ($opt.Edge)     { Invoke-Step 'Edge: no telemetry, background mode, sidebar or shopping' { Set-EdgePolicies } }
if ($opt.NoRecall) { Invoke-Step 'Recall' { Disable-Recall } }
if ($opt.NoEdgeShortcut) { Invoke-Step 'Edge desktop shortcut' { Remove-EdgeDesktopShortcut } }
if ($opt.Security) { Invoke-Step 'Windows Security'                                        { Set-WindowsSecurity } }
if ($opt.RootFolders) { Invoke-Step 'Folders in the drive root (inetpub and PerfLogs)'          { Clear-SystemDriveRoot } }
if ($opt.NoDeviceApps) { Invoke-Step 'Manufacturer apps for devices'                   { Disable-DeviceMetadata } }
if ($opt.NoWpbt)       { Invoke-Step 'Firmware programs (WPBT)'                   { Disable-Wpbt } }
if ($opt.HideAreas) { Invoke-Step 'Windows Security: hiding Microsoft account areas'  { Hide-SecurityAccountAreas } }

# --- Personalization
if ($opt.Theme -ne 'Keep') {
    Invoke-Step "Theme $($themeNames[[array]::IndexOf($themeIds, $opt.Theme)])" { Set-Theme ($opt.Theme -eq 'Light') }
}
if ($displayChanges) { Invoke-Step 'Screen' { foreach ($change in $displayChanges) { Set-DisplayChoice $change } } }
if ($opt.Taskbar -ne 'Keep') {
    Invoke-Step 'Taskbar alignment' { Set-TaskbarAlignment ($opt.Taskbar -eq 'Left') }
}
if ($opt.Search -ne 'Keep') {
    # Index in $searchIds minus 1 = SearchboxTaskbarMode value (Hidden = 0, Icon = 1, Box = 2)
    Invoke-Step 'Taskbar search' { Set-TaskbarSearch ([array]::IndexOf($searchIds, $opt.Search) - 1) }
}
if ($opt.TaskView -ne 'Keep') {
    Invoke-Step 'Task View button' { Set-TaskViewButton ($opt.TaskView -eq 'Show') }
}
if ($opt.ClearPins) { Invoke-Step 'Removing pinned icons from the taskbar' { Clear-TaskbarPins } }
if ($opt.NoStartAds) { Invoke-Step 'Ad shortcuts in Start' { Remove-StartAdPins } }
if ($opt.BatteryPercent) { Invoke-Step 'Battery percentage' { Enable-BatteryPercentage } }
if ($opt.ShowExtensions -or $opt.HideFrequent -or $opt.HideRecent) {
    Invoke-Step 'File Explorer' { Set-Explorer $opt.ShowExtensions $opt.HideFrequent $opt.HideRecent }
}
if ($opt.ShowHidden)    { Invoke-Step 'File Explorer: hidden files'               { Show-HiddenFiles } }
if ($opt.NoFolderSniff) { Invoke-Step 'File Explorer: automatic folder discovery' { Disable-FolderDiscovery } }
if ($opt.NoNewAppAlert) { Invoke-Step 'File Explorer: "new app installed" prompt' { Disable-NewAppAlert } }
if ($opt.HideHomeGallery) { Invoke-Step 'File Explorer: removing Home and Gallery' { Hide-HomeAndGallery } }
if ($opt.UnpinMusic) { Invoke-Step 'Quick access: Music' { Unpin-QuickAccessMusic } }
if ($opt.ClassicMenu) { Invoke-Step 'Classic context menu' { Enable-ClassicContextMenu } }
if ($opt.NoSnap) { Invoke-Step 'Snap windows' { Disable-SnapWindows } }
if ($opt.ThinBorder) { Invoke-Step 'Window resize border' { Set-ThinBorder } }

# --- System
if ($opt.LongPaths -or $opt.EndTask -or $opt.Sudo -or $opt.ClipboardHistory -or $opt.NoMouseAccel -or $opt.NoStickyKeys) {
    Invoke-Step 'System tweaks' {
        if ($opt.LongPaths)        { Enable-LongPaths }
        if ($opt.EndTask)          { Enable-EndTask }
        if ($opt.Sudo)             { Enable-Sudo }
        if ($opt.ClipboardHistory) { Enable-ClipboardHistory }
        if ($opt.NoMouseAccel)     { Disable-MouseAcceleration }
        if ($opt.NoStickyKeys)     { Disable-StickyKeysShortcut }
    }
}
if ($opt.NumLock)       { Invoke-Step 'Num Lock' { Enable-NumLockAtStartup } }
if ($opt.NoFastStartup) { Invoke-Step 'Fast Startup' { Disable-FastStartup } }
if ($opt.VerboseBsod) { Invoke-Step 'Detailed blue screen' { Enable-VerboseBsod } }
if ($opt.NoHibernate) { Invoke-Step 'Hibernation' { Disable-Hibernation } }
if ($power.Count) { Invoke-Step 'Screen, sleep and hibernation times' { Set-PowerTimeouts $power } }

# --- Network
if ($dnsV4) {
    Invoke-Step "DNS: $($opt.DNS)" {
        # The "automatic template" only exists for servers Windows knows (Cloudflare, Google, Quad9...)
        if (-not $isWin11) { Write-Host '  Windows 10 has no system-wide DNS over HTTPS: DNS is set unencrypted.' -ForegroundColor Yellow }
        else {
            foreach ($ip in ($dnsV4 + $dnsV6)) {
                if (-not (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue)) {
                    Write-Host "  Windows has no encryption template for ${ip}: that server is UNENCRYPTED." -ForegroundColor Yellow
                }
            }
        }
        Set-DNS $dnsV4 $dnsV6
    }
}

# --- Apply visuals right away (no need to sign out)
if ($script:RestartExplorer) { Invoke-Step 'Applying visuals without signing out' { Restart-Explorer } }

# --- Done: what changed, what already was like that, what failed
Write-Step 'Summary'
Write-Host "  $($script:StepCount) step(s) run"
Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
Write-Host "$($script:ChangedCount) setting(s) changed now"
Write-Host "  [--] $($script:AlreadyCount) were already like that" -ForegroundColor DarkGray
if ($script:Failures.Count) {
    Write-Host "  [ERROR] $($script:Failures.Count) step(s) failed. The rest was applied:" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}
Write-Host "`nDone. Restart the computer." -ForegroundColor Green
Write-Host '  To undo: TidyWin → Undo → Windows.' -ForegroundColor DarkGray
if ($script:LogFile) {
    $file = $script:LogFile
    $script:LogFile = $null      # this last line only on screen
    Write-Host "  Everything above was saved to: $file" -ForegroundColor DarkGray
}

#endregion
