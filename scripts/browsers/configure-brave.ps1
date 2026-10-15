#Requires -RunAsAdministrator
<#
    configure-brave.ps1 — a clean Brave: no Wallet, VPN, Rewards, Leo, News, Talk, Playlist, Tor, Speedreader or telemetry

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\configure-brave.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\configure-brave.ps1 -Revert

    Uses Brave's official policies (support.brave.app → "Group Policy"). They apply even if Brave
    is installed later. Close and reopen Brave to apply. It will show
    "Managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.
    One question: keep "Cast to TV" (a firewall rule is created) or turn it off. Either way, no firewall prompt.

    FILE LAYOUT
        1. Helpers
        2. Policies (one function per category)
        3. Revert
        4. Execution
#>
param(
    [switch]$Revert,
    [string]$Describe,      # the panel: write the options to this file and stop
    [string]$Answers        # the panel: apply the options in this file, without asking
)

$ErrorActionPreference = 'Continue'
$B = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'


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

$script:Failures = 0


# Writes a policy (DWORD) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$Name, [int]$Value, [string]$Description) {
    if ($null -ne $script:Collect) { [void]$script:Collect.Add($Name); return }   # -Revert: only the names
    try {
        if (-not (Test-Path $B)) { New-Item -Path $B -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $B -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host ("{0,-42}" -f $Description) -NoNewline
        Write-Host "$Name = $Value" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERROR] ' -ForegroundColor Red -NoNewline
        Write-Host "$Description ($Name): $($_.Exception.Message)"
    }
}

function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
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
    Write-Host '  (use the arrows ↑ ↓ and Enter)' -ForegroundColor DarkGray
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


#endregion


#region ==================== 2. POLICIES ====================

function Set-BraveFeatures {
    Set-Policy 'BraveWalletDisabled'        1 'Wallet (web3, decentralized DNS): off'
    Set-Policy 'BraveVPNDisabled'           1 'VPN: off'
    Set-Policy 'BraveRewardsDisabled'       1 'Rewards (BAT and ads): off'
    Set-Policy 'BraveAIChatEnabled'         0 'Leo (AI assistant): off'
    Set-Policy 'BraveNewsDisabled'          1 'Brave News on the new tab: off'
    Set-Policy 'BraveTalkDisabled'          1 'Brave Talk (video calls): off'
    Set-Policy 'BravePlaylistEnabled'       0 'Playlist: off'
    Set-Policy 'BraveWaybackMachineEnabled' 0 'Internet Archive prompt on 404 pages: off'
    Set-Policy 'TorDisabled'                1 'Private window with Tor: off'
    Set-Policy 'BraveSpeedreaderEnabled'    0 'Speedreader (reader mode): off'
}

function Set-BraveTelemetry {
    Set-Policy 'BraveP3AEnabled'            0 'Product usage analytics (P3A): off'
    Set-Policy 'BraveStatsPingEnabled'      0 'Daily usage ping: off'
    Set-Policy 'BraveWebDiscoveryEnabled'   0 'Web Discovery Project: off'
}

function Set-ChromiumPolicies {
    Set-Policy 'MetricsReportingEnabled'                 0 'Usage and crash reports: off'
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Anonymous URL collection: off'
    Set-Policy 'FeedbackSurveysEnabled'                  0 'Feedback surveys: off'
    Set-Policy 'PromotionalTabsEnabled'                  0 'Promotional/welcome tabs: off'
    Set-Policy 'BackgroundModeEnabled'                   0 'Run in background when closed: off'
    Set-Policy 'ShoppingListEnabled'                     0 'Shopping list: off'
    Set-Policy 'DefaultBrowserSettingEnabled'            0 '"Not your default browser" prompt: off'
}

# Installing sites as apps (the "monitor with arrow" icon in the address bar), password saving
# (Bitwarden handles it) and saved payment cards. Chromium policies, also honored by Brave.
function Set-AppsAndAutofill {
    Set-Policy 'WebAppInstallByUserEnabled'              0 'Install sites as apps (address bar icon): off'
    Set-Policy 'PasswordManagerEnabled'                  0 'Brave password manager: off'
    Set-Policy 'AutofillCreditCardEnabled'               0 'Save/fill payment cards: off'
}

# "Cast" to TV (Chromecast). To find TVs, Brave listens on the local network (mDNS, UDP 5353) the first
# time a page with video opens, and Windows Firewall asks for permission. Chrome's installer adds a firewall
# rule for this ("Google Chrome (mDNS-In)"); Brave's does not. Either choice below avoids the prompt:
#   keep Cast    → the same rule Chrome uses is created for brave.exe
#   disable Cast → EnableMediaRouter = 0, Brave never listens (and the rule is removed, if present)
$FirewallRuleName = 'Brave (mDNS-In)'

function Set-CastToTv([bool]$Disable, [string]$BraveExe) {
    if ($Disable) {
        Set-Policy 'EnableMediaRouter' 0 'Cast to TV (Chromecast): off'
        Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
        return
    }
    # Keep Cast on: remove the policy in case an earlier run turned it off, then allow mDNS in the firewall
    Remove-ItemProperty -Path $B -Name 'EnableMediaRouter' -ErrorAction SilentlyContinue
    try {
        Remove-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue   # recreate (path may change)
        New-NetFirewallRule -DisplayName $FirewallRuleName -Direction Inbound -Action Allow `
            -Program $BraveExe -Protocol UDP -LocalPort 5353 -ErrorAction Stop | Out-Null
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host ("{0,-42}" -f 'Cast to TV: kept; firewall allowed') -NoNewline
        Write-Host "rule '$FirewallRuleName' (UDP 5353)" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERROR] ' -ForegroundColor Red -NoNewline
        Write-Host "Firewall rule ($FirewallRuleName): $($_.Exception.Message)"
    }
}

#endregion


#region ==================== 3. REVERT ====================

# -Revert: one switch per group of policies that is on this PC, nothing turned on; only what is turned on is
# removed. A group lists its policies as "Value", "Subkey\Value", "Subkey\Value=data" (only when it holds
# that data) or "pref:name" (an entry of the Preferences policy); a list policy is a subkey with the name.
# Test and Undo add what is not a policy (a file, a firewall rule). Policies TidyWin doesn't know about,
# from an older version or another program, get their own switch.
function Get-PolicyNames([scriptblock]$Set) {
    $script:Collect = New-Object Collections.ArrayList
    try { & $Set } finally { $names = @($script:Collect); $script:Collect = $null }
    return $names
}

function Split-PolicyName([string]$Root, [string]$Name) {
    $r = @{ Key = $Root; Value = $Name; Data = $null }
    if ($r.Value -match '^(.*)=(.*)$') { $r.Value = $Matches[1]; $r.Data = $Matches[2] }
    $i = $r.Value.LastIndexOf('\')
    if ($i -ge 0) { $r.Key = "$Root\$($r.Value.Substring(0, $i))"; $r.Value = $r.Value.Substring($i + 1) }
    return $r
}

function Get-PolicyPrefs([string]$Root) {
    $raw = (Get-ItemProperty $Root -Name Preferences -ErrorAction SilentlyContinue).Preferences
    if (-not $raw) { return $null }
    try { return (@($raw) -join '') | ConvertFrom-Json } catch { return $null }
}

function Test-PolicyName([string]$Root, [string]$Name) {
    if ($Name -like 'pref:*') { $prefs = Get-PolicyPrefs $Root; return [bool]($prefs -and $prefs.PSObject.Properties[$Name.Substring(5)]) }
    $p = Split-PolicyName $Root $Name
    if ($null -eq $p.Data -and (Test-Path "$($p.Key)\$($p.Value)")) { return $true }
    $item = Get-ItemProperty $p.Key -Name $p.Value -ErrorAction SilentlyContinue
    return [bool]$item -and ($null -eq $p.Data -or "$($item.($p.Value))" -eq $p.Data)
}

function Remove-PolicyName([string]$Root, [string]$Name) {
    if (-not (Test-PolicyName $Root $Name)) { return }
    if ($Name -like 'pref:*') {
        $prefs = Get-PolicyPrefs $Root
        $prefs.PSObject.Properties.Remove($Name.Substring(5))
        if (@($prefs.PSObject.Properties).Count) {
            New-ItemProperty $Root -Name Preferences -Value @($prefs | ConvertTo-Json -Compress -Depth 5) -PropertyType MultiString -Force | Out-Null
        } else {
            Remove-ItemProperty $Root -Name Preferences -ErrorAction SilentlyContinue
        }
    } else {
        $p = Split-PolicyName $Root $Name
        if ($null -eq $p.Data -and (Test-Path "$($p.Key)\$($p.Value)")) { Remove-Item "$($p.Key)\$($p.Value)" -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-ItemProperty $p.Key -Name $p.Value -ErrorAction SilentlyContinue
    }
    Write-Host "  [removed] $($Name -replace '^pref:', 'Preferences: ' -replace '=.*$', '')" -ForegroundColor DarkGray
}

# Every value under the policies key that no group knows about ("Subkey\Value").
function Get-OtherPolicies([string]$Root, [object[]]$Groups) {
    if (-not (Test-Path $Root)) { return @() }
    $known = @($Groups | ForEach-Object { $_.Names } | ForEach-Object { if ($_ -like 'pref:*') { 'Preferences' } else { $_ -replace '=.*$', '' } })
    $keys = @(Get-Item $Root) + @(Get-ChildItem $Root -Recurse)
    $prefix = (Get-Item $Root).Name
    @(foreach ($key in $keys) {
        $sub = $key.Name.Substring($prefix.Length).TrimStart('\')
        foreach ($value in $key.Property) {
            $name = if ($sub) { "$sub\$value" } else { $value }
            if (-not ($known | Where-Object { $name -eq $_ -or $name -like "$_\*" })) { $name }
        }
    })
}

# Removes the subkeys left empty, and the policies key itself if nothing is left.
function Remove-EmptyPolicyKeys([string]$Root) {
    if (-not (Test-Path $Root)) { return }
    $keys = @(Get-ChildItem $Root -Recurse | Sort-Object { $_.Name.Length } -Descending) + @(Get-Item $Root)
    foreach ($key in $keys) {
        if (-not $key.Property -and -not (Get-ChildItem $key.PSPath -ErrorAction SilentlyContinue)) { Remove-Item $key.PSPath -Force -ErrorAction SilentlyContinue }
    }
}

# The groups that are on this PC, as switches (and the policies of the others).
function Get-UndoFields([string]$Root, [object[]]$Groups, [string]$Browser) {
    $script:UndoGroups = @($Groups | Where-Object { @($_.Names | Where-Object { Test-PolicyName $Root $_ }).Count -or ($_.Test -and (& $_.Test)) })
    $other = @(Get-OtherPolicies $Root $Groups)
    if ($other) {
        $shown = ($other | Select-Object -First 4) -join ', '
        if ($other.Count -gt 4) { $shown += " and $($other.Count - 4) more" }
        $script:UndoGroups += @{ Id = 'Other'; Label = 'Remove the other policies'; Desc = "Set by an older TidyWin or another program: $shown."; Names = $other }
    }
    if (-not $script:UndoGroups) { return @(New-Field $Browser 'Nothing' 'header' 'Nothing to undo' "$Browser has no settings from TidyWin on this PC." $null) }
    return @($script:UndoGroups | ForEach-Object { New-Field $Browser $_.Id 'toggle' $_.Label $_.Desc $false })
}

function Invoke-Undo([string]$Root, [object[]]$Groups, [string]$Browser) {
    $fields = Get-UndoFields $Root $Groups $Browser
    # The panel's Undo → Browsers page: a switch for this browser and, under it, what can be undone
    Write-Loading 'Reading what TidyWin set in Brave' 50
    if ($Describe) {
        $page = if ($script:UndoGroups) { Get-BrowserFields $fields $Browser 'Only the TidyWin settings on this PC show up.' }
                else { @(New-Field 'Browsers' $Browser.ToLower() 'info' $Browser 'No settings from TidyWin on this PC.' $null) }
        Write-OptionsPage $Describe $page
        return
    }
    if ($Answers) {
        $Answers = Get-BrowserAnswers $Answers $Browser
        if (-not $Answers) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    }
    if (-not $script:UndoGroups) { Write-Host "$Browser has no settings from TidyWin on this PC, so there is nothing to undo."; return }
    $v = Read-Options $fields $Answers
    $chosen = @($script:UndoGroups | Where-Object { $v[$_.Id] })
    if (-not $chosen) { Write-Host 'Nothing was selected, so nothing was changed.'; return }
    foreach ($g in $chosen) {
        Write-Step $g.Label
        foreach ($name in $g.Names) { Remove-PolicyName $Root $name }
        if ($g.Undo) { & $g.Undo }
    }
    Remove-EmptyPolicyKeys $Root
    Write-Host "`nDone. Close and reopen $Browser." -ForegroundColor Green
}

function Get-UndoGroups {
    @(
        @{ Id = 'Features'; Label = 'Bring Brave extras back'; Desc = 'Wallet, VPN, Rewards, Leo, News, Talk, Playlist, private windows with Tor and Speedreader come back.'; Names = Get-PolicyNames { Set-BraveFeatures } }
        @{ Id = 'Telemetry'; Label = 'Turn telemetry back on'; Desc = 'Brave can send usage analytics, the daily usage ping and Web Discovery data again.'; Names = Get-PolicyNames { Set-BraveTelemetry } }
        @{ Id = 'Chromium'; Label = 'Turn reports and prompts back on'; Desc = 'Crash reports, surveys, welcome tabs, running in the background, the shopping list and the "not your default browser" prompt come back.'; Names = Get-PolicyNames { Set-ChromiumPolicies } }
        @{ Id = 'Autofill'; Label = 'Save passwords and cards again'; Desc = 'Brave can save passwords and cards and install sites as apps again.'; Names = Get-PolicyNames { Set-AppsAndAutofill } }
        @{ Id = 'Cast'; Label = 'Cast to TV back to default'; Desc = 'The Cast setting and its firewall rule go away. Windows may ask about the firewall the first time Brave looks for TVs.'; Names = @('EnableMediaRouter')
           Test = { [bool](Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) }
           Undo = {
               if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
                   Remove-NetFirewallRule -DisplayName $FirewallRuleName
                   Write-Host "  [removed] Firewall rule '$FirewallRuleName'" -ForegroundColor DarkGray
               }
           } }
    )
}

#endregion


#region ==================== 4. EXECUTION ====================

# --- The panel's Browsers page has the three browsers: a switch for this one (it counts for nothing by
# itself), then its options, shown only while it is on: the on/off ones as a list of boxes. Their ids get the browser in front (chrome.AI),
# so the three scripts share one page and one answers file; each reads back only its own.
function Get-BrowserFields([object[]]$Fields, [string]$Browser, [string]$Desc) {
    $key = $Browser.ToLower()
    $shown = @{ tab = 'Browsers'; group = $Browser; indent = $true; when = @{ field = $key; is = 'True' } }
    # The on/off options become one list of boxes, with "Select all" (key.items); the others stay as they are
    $toggles = @($Fields | Where-Object { $_.kind -eq 'toggle' })
    $list = if ($toggles) {
        New-Field 'Browsers' "$key.items" 'checklist' '' '' @() @{ items = @($toggles | ForEach-Object {
            [ordered]@{ value = $_.id; label = $_.label; note = $_.desc; warn = "$($_.warn)"; group = '' } }) }
    }
    @(New-Field 'Browsers' $key 'toggle' $Browser $Desc $false @{ quiet = $true }) + @(@($list) + @($Fields | Where-Object { $_.kind -ne 'toggle' }) | Where-Object { $_ } | ForEach-Object {
        $f = [ordered]@{}
        foreach ($k in $_.Keys) { $f[$k] = $_[$k] }
        if ($f.id -ne "$key.items") { $f.id = "$key.$($_.id)" }
        foreach ($k in $shown.Keys) { $f[$k] = $shown[$k] }
        $f
    })
}

# This browser's answers, without the prefix, in a file of their own; nothing when its switch was off.
function Get-BrowserAnswers([string]$File, [string]$Browser) {
    $key = $Browser.ToLower()
    $json = [IO.File]::ReadAllText($File) | ConvertFrom-Json
    if (-not $json.$key) { return $null }
    $own = [ordered]@{}
    foreach ($prop in $json.PSObject.Properties) {
        if ($prop.Name -eq "$key.items") { foreach ($id in @($prop.Value)) { $own["$id"] = $true } }      # each checked box is an option on
        elseif ($prop.Name.StartsWith("$key.")) { $own[$prop.Name.Substring($key.Length + 1)] = $prop.Value }
    }
    $path = Join-Path $env:TEMP "tidywin-$key-answers.json"
    [IO.File]::WriteAllText($path, (ConvertTo-Json $own -Depth 5), (New-Object Text.UTF8Encoding $false))
    return $path
}
if ($Revert) { Invoke-Undo $B (Get-UndoGroups) 'Brave'; return }
if ($Answers) {
    $Answers = Get-BrowserAnswers $Answers 'Brave'
    if (-not $Answers) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
}

$installed = @(
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Brave not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
    $installed = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"   # default install path
}

# --- Options: the panel's page, or asked here. Nothing comes selected.
$T = 'Brave'
$fields = @(
    New-Field $T 'Features' 'toggle' 'Turn off Brave extras' 'Wallet, VPN, Rewards, the Leo AI assistant, News, Talk, Playlist, private windows with Tor and Speedreader go away. Ad blocking stays on.' $false
    New-Field $T 'Telemetry' 'toggle' 'Turn off telemetry' 'Brave stops sending usage analytics, the daily usage ping and Web Discovery data.' $false
    New-Field $T 'Chromium' 'toggle' 'Turn off reports and prompts' 'No crash reports, surveys or welcome tabs, no running in the background after closing, no shopping list and no "not your default browser" prompt.' $false
    New-Field $T 'Autofill' 'toggle' 'Turn off saving passwords and cards' 'For when you use a password manager, like Bitwarden. Brave also stops offering to install sites as apps.' $false
    New-Field $T 'Cast' 'choice' 'Cast to TV' 'Keep: Brave finds TVs without a firewall prompt. Turn off: Brave stops looking for TVs on the network.' '' @{ options = @((Opt 'Keep' 'Keep'), (Opt 'Off' 'Turn off')) }
)
Write-Loading 'Reading the Brave settings' 50
if ($Describe) { Write-OptionsPage $Describe (Get-BrowserFields $fields 'Brave' 'Turn off the extras and the telemetry Brave adds.'); return }
if (-not $script:Panel) { Write-Host "`nConfigure-Brave" -ForegroundColor Green }   # in the panel the page already has the title
$v = Read-Options $fields $Answers
if (-not @($v.Keys | Where-Object { $v[$_] })) { Write-Host 'Nothing was selected, so nothing was changed.'; return }
# --- Apply
if ($v.Features)  { Write-Step 'Brave features';            Set-BraveFeatures }
if ($v.Telemetry) { Write-Step 'Brave telemetry';           Set-BraveTelemetry }
if ($v.Chromium)  { Write-Step 'Reports and prompts';       Set-ChromiumPolicies }
if ($v.Autofill)  { Write-Step 'Apps, passwords and cards'; Set-AppsAndAutofill }
if ($v.Cast)      { Write-Step 'Cast to TV';                Set-CastToTv ($v.Cast -eq 'Off') $installed }

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Brave." -ForegroundColor Green; Write-Host '  To check: brave://policy' -ForegroundColor DarkGray
if (Get-Process brave -ErrorAction SilentlyContinue) {
    Write-Host 'Brave is open: close all of its windows for the changes to take effect.' -ForegroundColor DarkYellow
}
Write-Host @'

Settings with no policy (do these once inside Brave):
  - brave://settings/newTab     -> turn off sponsored images, stats and cards
  - brave://settings/appearance -> "Show sidebar": Never; turn on "Always show full URLs"
  - brave://settings/search     -> default search engine: Google
  - brave://settings/system     -> turn on "Memory Saver"
'@

#endregion
