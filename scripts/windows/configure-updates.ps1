#Requires -RunAsAdministrator
<#
    configure-updates.ps1 — how Windows Update works on this PC: normal, security only, or off

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\configure-updates.ps1

    Three modes, one at a time:
        Normal ......... the Windows default: removes what the other two set and puts the services back
        Security only .. security and quality fixes keep coming every month; the yearly feature update
                         (a new version of Windows, like 24H2 → 25H2) waits 365 days. Windows Update for
                         Business policy: Pro, Enterprise and Education (Windows Home ignores it)
        Off ............ UNSAFE. Policy NoAutoUpdate, and the Windows Update, Update Orchestrator and
                         Windows Update Medic services disabled and stopped. Their startup types are saved
                         first to %ProgramData%\TidyWin\updates.json, and Normal puts them back.
    Safe to run more than once.

    FILE LAYOUT
        1. Helpers ................... prompts, services, current mode
        2. Modes
        3. Execution
#>
param(
    [string]$Describe,   # for the panel: writes the options of the page to this file and stops
    [string]$Answers     # for the panel: what was chosen there (nothing is asked)
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

# Result line: [OK] text / [WARNING] text / [ERROR] text
function Write-Result([ValidateSet('OK', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $label, $color = switch ($Status) {
        'OK'    { '[OK]', 'Green' }
        'WARN'  { '[WARNING]', 'Yellow' }
        'ERROR' { '[ERROR]', 'Red' }
    }
    Write-Host "  $label " -ForegroundColor $color -NoNewline
    Write-Host $Text
}

$WU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$AU = "$WU\AU"
$StateFile = Join-Path $env:ProgramData 'TidyWin\updates.json'

# The services that look for and install updates, with their Windows default startup type
# (Start: 2 automatic, 3 manual, 4 disabled; Delayed: automatic, delayed start). The Medic service turns
# the other two back on when they stop working, so it is turned off too (Windows may not allow it).
$Services = [ordered]@{
    wuauserv     = @{ Name = 'Windows Update';       Start = 3; Delayed = 0 }
    UsoSvc       = @{ Name = 'Update Orchestrator';  Start = 2; Delayed = 1 }
    WaaSMedicSvc = @{ Name = 'Windows Update Medic'; Start = 3; Delayed = 0 }
}

function Get-RegValue([string]$Path, [string]$Name) {
    (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

function Get-ServiceKey([string]$Name) { "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" }

# Startup type of a service, from the registry (Get-Service can't tell delayed start apart)
function Get-ServiceStart([string]$Name) {
    $key = Get-ServiceKey $Name
    if (-not (Test-Path $key)) { return $null }
    @{ Start = [int](Get-RegValue $key 'Start'); Delayed = [int](Get-RegValue $key 'DelayedAutostart') }
}

# Sets the startup type in the registry, the same place services.msc writes it. Returns $false when
# Windows doesn't allow it (the Medic service's key is protected).
function Set-ServiceStart([string]$Name, [int]$Start, [int]$Delayed) {
    $key = Get-ServiceKey $Name
    if (-not (Test-Path $key)) { return $true }          # not on this Windows
    try {
        Set-ItemProperty -Path $key -Name Start -Value $Start -Type DWord -ErrorAction Stop
        if ($Start -eq 2) { Set-ItemProperty -Path $key -Name DelayedAutostart -Value $Delayed -Type DWord -ErrorAction Stop }
        return $true
    } catch { return $false }
}

# Normal, Security or Off, from what is set now. (No $wu here: PowerShell ignores case, so it would be $WU.)
function Get-UpdateMode {
    $service = Get-ServiceStart 'wuauserv'
    if (($service -and $service.Start -eq 4) -or (Get-RegValue $AU 'NoAutoUpdate') -eq 1) { return 'Off' }
    if ((Get-RegValue $WU 'DeferFeatureUpdates') -eq 1) { return 'Security' }
    return 'Normal'
}

# Removes policy values; the policy keys go too once they are empty
function Remove-Policy([string]$Path, [string[]]$Names) {
    foreach ($n in $Names) { Remove-ItemProperty -Path $Path -Name $n -ErrorAction SilentlyContinue }
    foreach ($k in @($AU, $WU)) {
        $item = Get-Item $k -ErrorAction SilentlyContinue
        if ($item -and -not $item.Property -and -not (Get-ChildItem $k -ErrorAction SilentlyContinue)) { Remove-Item $k -ErrorAction SilentlyContinue }
    }
}

function Set-Policy([string]$Path, [string]$Name, [int]$Value) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. MODES ====================

# Windows Update working again: NoAutoUpdate removed and the services back to how they were before Off
# (saved then), or to the Windows default.
function Enable-Updates {
    $saved = $null
    if (Test-Path $StateFile) { try { $saved = Get-Content $StateFile -Raw | ConvertFrom-Json } catch { } }
    if ((Get-RegValue $AU 'NoAutoUpdate') -eq 1) { Remove-Policy $AU 'NoAutoUpdate'; Write-Result 'OK' 'Automatic updates: allowed again' }
    foreach ($name in $Services.Keys) {
        $s = $Services[$name]
        $now = Get-ServiceStart $name
        if (-not $now -or $now.Start -ne 4) { continue }        # not disabled: left as it is
        $start = $s.Start; $delayed = $s.Delayed
        if ($saved -and $saved.$name -and [int]$saved.$name.Start -ne 4) { $start = [int]$saved.$name.Start; $delayed = [int]$saved.$name.Delayed }
        if (Set-ServiceStart $name $start $delayed) { Write-Result 'OK' "$($s.Name) service: back on" }
        else { Write-Result 'WARN' "$($s.Name) service: Windows did not allow the change; it turns itself back on." }
    }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    foreach ($name in 'wuauserv', 'UsoSvc') { Start-Service $name -ErrorAction SilentlyContinue }
}

function Set-NormalMode {
    Enable-Updates
    if ((Get-RegValue $WU 'DeferFeatureUpdates') -eq 1) {
        Remove-Policy $WU 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays'
        Write-Result 'OK' 'Feature updates: no longer delayed'
    }
    Write-Result 'OK' 'Windows Update: back to the Windows default'
}

# Windows Update for Business: the feature update waits 365 days (the most Windows allows);
# monthly security and quality updates are not delayed.
function Set-SecurityOnlyMode {
    Enable-Updates
    Set-Policy $WU 'DeferFeatureUpdates' 1
    Set-Policy $WU 'DeferFeatureUpdatesPeriodInDays' 365
    Write-Result 'OK' 'Feature updates: delayed 365 days'
    Write-Result 'OK' 'Security and quality updates: every month, as usual'
    if ($script:IsHome) { Write-Result 'WARN' 'Windows Home ignores this policy: feature updates may still arrive.' }
}

# Off: the startup types are saved first (only if they are not off already, so the originals are kept).
function Set-OffMode {
    if (-not (Test-Path $StateFile)) {
        $state = [ordered]@{}
        foreach ($name in $Services.Keys) { $now = Get-ServiceStart $name; if ($now -and $now.Start -ne 4) { $state[$name] = $now } }
        New-Item -ItemType Directory -Path (Split-Path $StateFile) -Force | Out-Null
        ConvertTo-Json $state | Set-Content $StateFile -Encoding UTF8
        Write-Result 'OK' "Services saved to $StateFile"
    }
    Set-Policy $AU 'NoAutoUpdate' 1
    Write-Result 'OK' 'Automatic updates: off (policy)'
    foreach ($name in $Services.Keys) {
        $s = $Services[$name]
        if (-not (Get-ServiceStart $name)) { continue }
        Stop-Service $name -Force -ErrorAction SilentlyContinue
        if (Set-ServiceStart $name 4 0) { Write-Result 'OK' "$($s.Name) service: disabled" }
        else { Write-Result 'WARN' "$($s.Name) service: Windows protects it, so it was left on. It may turn Windows Update back on after a while." }
    }
    Write-Host ''
    Write-Host '  This PC no longer gets security fixes. Turn it back to Normal as soon as you can.' -ForegroundColor Red
}

#endregion


#region ==================== 3. EXECUTION ====================

if (-not $script:Panel) { Write-Host "`nConfigure-Updates" -ForegroundColor Green }   # in the panel the page already has the title

Write-Loading 'Reading how Windows Update is set up'
$script:IsHome = (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID') -match 'Core'
$current = Get-UpdateMode
$modeNames = @{ Normal = 'Normal'; Security = 'Security only'; Off = 'Off' }

$T = 'Updates'
$fields = @(
    New-Field $T 'Mode' 'choice' 'Windows Update' "Now: $($modeNames[$current]). Pick a mode to change it." '' @{ options = @((Opt 'Normal' 'Normal'), (Opt 'Security' 'Security only'), (Opt 'Off' 'Off')) }
    New-Field $T 'AboutNormal' 'info' 'Normal' 'The Windows default, like a new PC: security fixes every month and the new version of Windows about once a year. Undoes Security only and Off.' $null @{ when = @{ field = 'Mode'; is = 'Normal' } }
    New-Field $T 'AboutSecurity' 'info' 'Security only' 'Security and quality fixes keep coming every month, as usual. The yearly feature update, a new version of Windows like 24H2 to 25H2, waits 365 days, so it arrives already tested and fixed. Drivers and Defender keep updating.' $null @{
        when = @{ field = 'Mode'; is = 'Security' }; warn = $(if ($script:IsHome) { 'Windows Home ignores this setting: it only works on Pro, Enterprise and Education.' } else { '' }) }
    New-Field $T 'AboutOff' 'info' 'Off: not safe' 'Windows stops looking for, downloading and installing every update, security fixes included. Its services are turned off, and Microsoft Store downloads can fail. Normal turns everything back on.' $null @{
        when = @{ field = 'Mode'; is = 'Off' }; danger = $true
        warn = 'UNSAFE. Without updates this PC no longer gets security fixes: every flaw found in Windows from now on stays open, and malware can use it through a website, a file or the network. Only for a short time and for a specific reason. Turn it back to Normal as soon as you can.' }
)
if ($Describe) { Write-OptionsPage $Describe $fields; return }

$v = Read-Options $fields $Answers
$mode = "$($v.Mode)"
if (-not $mode) { Write-Host 'Nothing was selected, so nothing was changed.'; return }
if (-not $Answers -and $mode -eq 'Off') {
    Write-Host ''
    Write-Host '  UNSAFE: this PC will no longer get security fixes until you turn Windows Update back to Normal.' -ForegroundColor Red
    if (-not (Ask 'Turn Windows Update off anyway?' $false)) { Write-Host 'Nothing was changed.'; return }
}

switch ($mode) {
    'Normal'   { Write-Step 'Windows Update: Normal';        Set-NormalMode }
    'Security' { Write-Step 'Windows Update: Security only'; Set-SecurityOnlyMode }
    'Off'      { Write-Step 'Windows Update: Off';           Set-OffMode }
}
Write-Host "`nDone. Now: $($modeNames[(Get-UpdateMode)])." -ForegroundColor Green

#endregion
