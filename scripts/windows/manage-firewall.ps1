#Requires -RunAsAdministrator
<#
    manage-firewall.ps1 — the Windows Firewall rules your apps added, and a few protections

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\manage-firewall.ps1

    One tab per task, in plain words:
        Delete rules .. the rules apps and their installers added, one row per app (Windows' own rules are
                        left out: their names point inside Windows, like "@FirewallAPI.dll,-28502"). Every
                        rule of each checked app is deleted for good; if it needs one again, Windows asks.
        Block an app .. a rule in the "TidyWin" group stops its .exe from reaching the internet; it shows
                        up in Delete rules, to undo it
        Networks ...... each connected network as Home (Private) or Public, extra protection on public
                        Wi-Fi (no incoming connections at all), and turning the firewall back on if it is off
        Backup ........ puts one of the saved copies back
    Before any change every rule is saved with "netsh advfirewall export" to %ProgramData%\TidyWin\firewall
    (the last 5 are kept); the page can put one back. Safe to run more than once.

    FILE LAYOUT
        1. Helpers ................... prompts, rules by program
        2. Changes
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
            'guide'     {
                # The explanation card: its title, each option in its color and a tip
                $colors = @{ Accent = 'Cyan'; Ok = 'Green'; Warn = 'Yellow'; Err = 'Red' }
                Write-Host "`n  $($f.label)" -ForegroundColor Cyan
                if ($f.desc) { Write-Host "  $($f.desc)" -ForegroundColor DarkGray }
                foreach ($g in @($f.items)) {
                    Write-Host "    $($g.label): " -ForegroundColor $(if ($colors[$g.brush]) { $colors[$g.brush] } else { 'Cyan' }) -NoNewline
                    Write-Host $g.text
                }
                if ($f.tip) { Write-Host "  $($f.tip)" }
            }
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

$BackupDir = Join-Path $env:ProgramData 'TidyWin\firewall'
$TidyGroup = 'TidyWin'

# Profiles: Domain = 1, Private = 2, Public = 4 (Any = 0: every one)
$ProfilePublic = 4

# The rules apps added, one entry per program. Left out: Windows' own rules (their group or name is a
# reference inside Windows, "@..."), the ones Windows keeps for Store apps (Owner), rules with no program,
# and programs inside the Windows folder.
function Get-AppRules {
    $system = $env:SystemRoot.TrimEnd('\')
    $programs = @{}
    foreach ($f in @(Get-NetFirewallApplicationFilter -All -ErrorAction SilentlyContinue)) {
        if ($f.Program -and $f.Program -ne 'Any') { $programs[$f.InstanceID] = $f.Program }
    }
    $byProgram = [ordered]@{}
    foreach ($r in @(Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
        $program = $programs[$r.Name]
        if (-not $program) { continue }
        if ("$($r.Group)".StartsWith('@') -or "$($r.DisplayName)".StartsWith('@') -or $r.Owner) { continue }
        $path = [Environment]::ExpandEnvironmentVariables($program)
        if ($path -like "$system\*") { continue }
        $key = $path.ToLowerInvariant()
        if (-not $byProgram.Contains($key)) { $byProgram[$key] = [pscustomobject]@{ Key = $key; Path = $path; Rules = New-Object Collections.Generic.List[object] } }
        $byProgram[$key].Rules.Add($r)
    }
    $list = foreach ($p in $byProgram.Values) {
        $rules = $p.Rules.ToArray()          # (@() on a List of these objects fails: "argument types do not match")
        $exists = Test-Path -LiteralPath $p.Path
        # Inbound "allow" rules that also count on public networks (Public, or Any)
        $open = @($rules | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' -and $_.Enabled -eq 'True' -and
                                         (([int]$_.Profile -eq 0) -or ([int]$_.Profile -band $ProfilePublic)) })
        [pscustomobject]@{
            Key = $p.Key; Path = $p.Path; Name = Get-ProgramName $p.Path $rules; Exists = $exists; Rules = $rules; PublicInbound = $open
            Blocked = [bool]($rules | Where-Object { $_.Group -eq $TidyGroup -and $_.Action -eq 'Block' })
        }
    }
    # Two programs with the same name (Edge and WebView2 both name their rule "Microsoft Edge"): each one's
    # own description, or file name, tells them apart
    foreach ($same in @($list | Group-Object Name | Where-Object Count -gt 1)) {
        foreach ($a in $same.Group) { $a.Name = Get-ProgramName $a.Path @() }
    }
    $list
}

# A readable name: the rules' own name (without a path in parentheses), else the program's description,
# else its file name. Store apps often name their rules "ms-resource:...", which says nothing.
function Get-ProgramName([string]$Path, $Rules) {
    # (what comes in parentheses at the end is a path or a detail: "Firefox (C:\Program Files\...)", "(mDNS-in)")
    $names = @($Rules | ForEach-Object { ("$($_.DisplayName)" -replace '^TidyWin: block ', '' -replace '\s*\([^()]*\)\s*$', '').Trim() } |
               Where-Object { $_ -and $_ -notlike 'ms-resource:*' -and $_ -notlike '{*' } | Group-Object | Sort-Object Count -Descending)
    if ($names) { return $names[0].Name }
    if (Test-Path -LiteralPath $Path) {
        $v = (Get-Item -LiteralPath $Path).VersionInfo
        foreach ($n in $v.FileDescription, $v.ProductName) { if ("$n".Trim()) { return "$n".Trim() } }
    }
    return [IO.Path]::GetFileNameWithoutExtension($Path)
}

# What the rules let the app do, in a few words: "Open to other devices, even on public Wi-Fi"
function Get-RuleDescription($App) {
    $rules = @($App.Rules)
    if ($App.Blocked) { return 'Blocked from the internet by TidyWin' }
    if ($rules | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' }) {
        if ($App.PublicInbound) { return 'Open to other devices, even on public Wi-Fi' } else { return 'Open to other devices at home' }
    }
    if ($rules | Where-Object Action -eq 'Block') { return 'Blocked from the internet' }
    return 'Allowed to use the internet'
}

# Saved copies of every rule, newest first
function Get-Backups { @(Get-ChildItem -LiteralPath $BackupDir -Filter '*.wfw' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) }


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. CHANGES ====================

# Every rule and setting of the firewall, before anything changes. Keeps the last 5.
function Save-FirewallBackup {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $file = Join-Path $BackupDir ('{0:yyyy-MM-dd HHmmss}.wfw' -f (Get-Date))
    $out = & netsh.exe advfirewall export "$file" 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "the backup failed: $(($out | Where-Object { "$_".Trim() }) -join ' ')" }
    Get-Backups | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Result 'OK' "Rules saved to $file"
}

function Restore-FirewallBackup([string]$File) {
    $out = & netsh.exe advfirewall import "$File" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Result 'ERROR' "Could not restore it: $(($out | Where-Object { "$_".Trim() }) -join ' ')"; return }
    Write-Result 'OK' "Firewall as it was on $((Get-Item -LiteralPath $File).LastWriteTime.ToString('g'))"
}

# Deletes every rule of the program for good (the backup made first has them)
function Remove-ProgramRules($Program) {
    $failed = 0
    foreach ($r in $Program.Rules) { try { Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop } catch { $failed++ } }
    $n = @($Program.Rules).Count
    if ($failed) { Write-Result 'WARN' "$($Program.Name): $($n - $failed) of $n rule(s) deleted; $failed could not be deleted" }
    else { Write-Result 'OK' "$($Program.Name): $n rule(s) deleted" }
}

function Block-Program([string]$Path) {
    $name = Get-ProgramName $Path @()
    New-NetFirewallRule -DisplayName "TidyWin: block $name" -Group $TidyGroup -Direction Outbound -Action Block -Program $Path -Profile Any -ErrorAction Stop | Out-Null
    Write-Result 'OK' "$name can no longer reach the internet"
}

#endregion


#region ==================== 3. EXECUTION ====================

if (-not $script:Panel) { Write-Host "`nManage-Firewall" -ForegroundColor Green }   # in the panel the page already has the title

Write-Loading 'Reading the firewall rules' 10
$apps = @(Get-AppRules | Sort-Object Name)
Write-Loading 'Reading the networks and the firewall profiles' 80
$profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
$off = @($profiles | Where-Object { -not $_.Enabled } | ForEach-Object { "$($_.Name)" })
$publicProfile = $profiles | Where-Object Name -eq 'Public'
$publicBlocksAll = $publicProfile -and "$($publicProfile.AllowInboundRules)" -eq 'False'
$networks = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -ne 'DomainAuthenticated' } | Sort-Object InterfaceAlias)
$backups = Get-Backups

# One tab per task, in plain words: delete rules, block an app, networks, backup
$TabDelete = 'Delete rules'; $TabBlock = 'Block an app'; $TabNetworks = 'Networks'; $TabBackup = 'Backup'
$fields = @(
    if ($apps) {
        New-Field $TabDelete 'Remove' 'checklist' 'Delete every rule of these apps' ('Some apps open the firewall so other devices can connect to them. Check an app to delete all of its rules for good.' +
            ' The app keeps working, and Windows asks you again if it needs access. A backup is saved first.') @() @{
            items = @($apps | ForEach-Object {
                $n = @($_.Rules).Count
                [ordered]@{ value = $_.Key; label = $_.Name; group = ''; note = Get-RuleDescription $_
                            status = "$n rule$(if ($n -ne 1) { 's' })"; statusBrush = 'Warn'
                            warn = $(if (-not $_.Exists) { 'No longer installed. Safe to delete.' } else { '' }) }
            }); search = $apps.Count -gt 15 }
    } else {
        New-Field $TabDelete 'NoRules' 'header' 'No app rules' 'No app added rules to the firewall on this PC. Windows'' own rules are not shown.' $null
    }

    New-Field $TabBlock 'Block' 'path' 'App to block' 'Choose the app''s .exe file and it can''t use the internet anymore. To undo it, delete its rule in the Delete rules tab.' '' @{
        pick = 'file'; filter = 'Programs (*.exe)|*.exe'; placeholder = 'Choose a program' }

    # What each choice does and when it fits, before the choices
    New-Field $TabNetworks 'Guide' 'guide' 'Which one fits you?' 'Each network you connect to is Home or Public. The extra protection is for when you want even more.' $null @{
        items = @(
            [ordered]@{ label = 'Home'; brush = 'Accent'
                        text = 'Your own Wi-Fi or cable. Your printer, TV, phone and other PCs can find this PC, and sharing files between them works.' }
            [ordered]@{ label = 'Public'; brush = 'Ok'
                        text = 'Cafés, hotels, airports, work or school. The other people on the network can''t see this PC. The internet works the same.' }
            [ordered]@{ label = 'Extra protection on public Wi-Fi'; brush = 'Warn'
                        text = 'For networks you don''t trust at all. On top of Public, it blocks everything that tries to reach this PC, even the apps in Delete rules, like games or torrents. What you open yourself still works: sites, downloads, online games and calls.' }
        )
        tip = 'Not sure? Choose Public. Switch to Home only on your own network.' }
    if ($off) {
        New-Field $TabNetworks 'TurnOn' 'toggle' 'Turn the firewall back on' "The firewall is off on $($off -join ', ') networks, so any app can be reached by other devices there." $false @{
            danger = $true; warn = 'Something turned it off. Keep it on, unless another security program replaced it.' }
    }
    $i = 0
    foreach ($net in $networks) {
        $i++
        $public = "$($net.NetworkCategory)" -eq 'Public'
        # The type it has now, in color next to the name
        New-Field $TabNetworks "Network$i" 'choice' "$($net.Name)" 'The network this PC is connected to now.' '' @{
            badge = "$($net.InterfaceAlias), set as $(if ($public) { 'Public' } else { 'Home' })"; badgeBrush = 'Accent'
            options = @((Opt 'Private' 'Home'), (Opt 'Public' 'Public')) }
    }
    if (-not $networks) { New-Field $TabNetworks 'NoNetwork' 'info' 'No network connected' '' $null }
    if ($publicBlocksAll) {
        New-Field $TabNetworks 'Relax' 'toggle' 'Turn off the extra protection on public Wi-Fi' 'It is on now. Turn it off to let the apps you allowed receive connections again.' $false @{ badge = 'On'; badgeBrush = 'Ok' }
    } else {
        New-Field $TabNetworks 'Strict' 'toggle' 'Extra protection on public Wi-Fi' 'Only on networks set as Public. See above what it blocks.' $false
    }

    if ($backups) {
        New-Field $TabBackup 'Restore' 'select' 'Put a backup back' 'Every rule goes back to how it was on that date, deleted ones included. Nothing else on this page is applied.' '' @{
            options = @($backups | ForEach-Object { Opt $_.FullName ($_.LastWriteTime.ToString('g')) }); warn = 'Rules added after that date are lost.' }
    } else {
        New-Field $TabBackup 'NoBackup' 'header' 'No backup yet' 'A backup is saved every time you apply this page. The last 5 show up here.' $null
    }
)
if ($Describe) { Write-OptionsPage $Describe $fields; return }

$v = Read-Options $fields $Answers
$restore = "$($v.Restore)"
$remove = @(@($v.Remove) | Where-Object { $_ })
$block = "$($v.Block)".Trim().Trim('"')
$netChanges = @(for ($k = 1; $k -le $networks.Count; $k++) {
    $want = "$($v["Network$k"])"; $n = $networks[$k - 1]
    $now = if ("$($n.NetworkCategory)" -eq 'Public') { 'Public' } else { 'Private' }
    if ($want -and $want -ne $now) { [pscustomobject]@{ Network = $n; Category = $want } }
})
$publicInbound = if ($v.Strict) { 'Block' } elseif ($v.Relax) { 'Allow' } else { '' }
if (-not ($restore -or $remove -or $block -or $netChanges -or $publicInbound -or $v.TurnOn)) { Write-Host 'Nothing was selected, so nothing was changed.'; return }

Write-Step 'Backup'
try { Save-FirewallBackup } catch { Write-Result 'ERROR' "$($_.Exception.Message). Nothing was changed."; return }

if ($restore) {
    Write-Step 'Putting the backup back'
    if (Test-Path -LiteralPath $restore) { Restore-FirewallBackup $restore } else { Write-Result 'ERROR' "The backup is no longer there: $restore" }
    Write-Host "`nDone." -ForegroundColor Green
    return
}

$byKey = @{}; foreach ($a in $apps) { $byKey[$a.Key] = $a }
if ($remove) {
    Write-Step 'Deleting app rules'
    foreach ($k in $remove) { if ($byKey[$k]) { Remove-ProgramRules $byKey[$k] } }
}
if ($block) {
    Write-Step 'Blocking a program'
    if (-not (Test-Path -LiteralPath $block -PathType Leaf)) { Write-Result 'ERROR' "Not found: $block" }
    else { try { Block-Program $block } catch { Write-Result 'ERROR' "$($_.Exception.Message)" } }
}
if ($v.TurnOn) {
    Write-Step 'Turning the firewall back on'
    try { Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -ErrorAction Stop; Write-Result 'OK' 'On for every network' }
    catch { Write-Result 'ERROR' "$($_.Exception.Message)" }
    $still = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
    if ($still) { Write-Result 'WARN' "Still off for $(($still.Name) -join ', '): a policy or another firewall controls it." }
}
foreach ($c in $netChanges) {
    Write-Step "Network: $($c.Network.Name)"
    try { Set-NetConnectionProfile -InterfaceIndex $c.Network.InterfaceIndex -NetworkCategory $c.Category -ErrorAction Stop; Write-Result 'OK' "Now $(if ($c.Category -eq 'Private') { 'Home' } else { 'Public' })" }
    catch { Write-Result 'ERROR' "$($_.Exception.Message)" }
}
if ($publicInbound) {
    Write-Step 'Extra protection on public Wi-Fi'
    $allow = if ($publicInbound -eq 'Block') { 'False' } else { 'True' }
    try { Set-NetFirewallProfile -Profile Public -AllowInboundRules $allow -ErrorAction Stop; Write-Result 'OK' $(if ($allow -eq 'False') { 'On: no app receives connections on public networks' } else { 'Off: back to the Windows default' }) }
    catch { Write-Result 'ERROR' "$($_.Exception.Message)" }
}
Write-Host "`nDone." -ForegroundColor Green
Write-Host "  To undo: Maintenance → Firewall → Backup tab (the copy from just now is the newest)." -ForegroundColor DarkGray

#endregion
