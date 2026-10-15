#Requires -RunAsAdministrator
<#
    configure-chrome.ps1 — a more private Chrome without breaking the Google account sign-in
    (Gmail, Drive and "Sign in with Google" on other sites keep working)

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\configure-chrome.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\configure-chrome.ps1 -Revert

    Uses Chrome's official policies (chromeenterprise.google/policies). They apply to every
    profile, even if Chrome is installed later. Close and reopen Chrome to apply. It will show
    "Managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.

    Does NOT touch: Google account sign-in, Safe Browsing (stays on Standard),
    leaked password checks, password manager and updates.

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
$C = 'HKLM:\SOFTWARE\Policies\Google\Chrome'


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
        if (-not (Test-Path $C)) { New-Item -Path $C -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $C -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Ok $Description "$Name = $Value"
    } catch { Write-Fail $Description $Name $_ }
}

# List policies live in a subkey with values "1", "2", "3"... (recreated from scratch).
function Set-PolicyList([string]$Name, [string[]]$Items, [string]$Description) {
    if ($null -ne $script:Collect) { [void]$script:Collect.Add($Name); return }   # -Revert: only the names
    try {
        $key = "$C\$Name"
        if (Test-Path $key) { Remove-Item $key -Recurse -Force -ErrorAction Stop }
        New-Item -Path $key -Force -ErrorAction Stop | Out-Null
        for ($i = 0; $i -lt $Items.Count; $i++) {
            New-ItemProperty -Path $key -Name ($i + 1) -Value $Items[$i] -PropertyType String -Force -ErrorAction Stop | Out-Null
        }
        Write-Ok $Description "$Name = $($Items -join ', ')"
    } catch { Write-Fail $Description $Name $_ }
}

function Write-Ok([string]$Description, [string]$Detail) {
    Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
    Write-Host ("{0,-46}" -f $Description) -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
}

function Write-Fail([string]$Description, [string]$Name, $ErrorRecord) {
    $script:Failures++
    Write-Host '  [ERROR] ' -ForegroundColor Red -NoNewline
    Write-Host "$Description ($Name): $($ErrorRecord.Exception.Message)"
}

function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    if ($script:Panel) { return [int](Request-Panel @{ type = 'choose'; question = $Question; options = @($Options); default = $Default }) }
    if ($NoPrompt) { return $Default }
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


#endregion


#region ==================== 2. POLICIES ====================

function Set-Telemetry {
    Set-Policy 'MetricsReportingEnabled'                 0 'Usage and crash reports: off'
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Sending visited URLs: off'
    Set-Policy 'SpellCheckServiceEnabled'                0 'Cloud spell check: off (local stays)'
    Set-Policy 'AlternateErrorPagesEnabled'              0 'Suggestions on error pages: off'
    Set-Policy 'FeedbackSurveysEnabled'                  0 'Satisfaction surveys: off'
    Set-Policy 'SafeBrowsingSurveysEnabled'              0 'Safe Browsing surveys: off'
    Set-Policy 'UserFeedbackAllowed'                     0 'Send feedback to Google: off'
}

function Set-AI {
    Set-Policy 'GenAiDefaultSettings'                    2 'AI features (general default): off'
    Set-Policy 'GeminiSettings'                          1 'Gemini in Chrome: off'
    Set-Policy 'GeminiActOnWebSettings'                  1 'Gemini acting on pages: off'
    Set-Policy 'GeminiSparkSettings'                     1 'Gemini Spark: off'
    Set-Policy 'AIModeSettings'                          1 'AI Mode in the address bar: off'
    Set-Policy 'ThirdPartyAiChatSettings'                1 'Third-party AI in the address bar: off'
    Set-Policy 'SearchContentSharingSettings'            1 'Send page content to AI Mode: off'
    Set-Policy 'SmartTabSharingSettings'                 1 'Share tabs with AI Mode: off'
    Set-Policy 'HelpMeWriteSettings'                     2 '"Help me write": off'
    Set-Policy 'TabCompareSettings'                      2 'Tab compare with AI: off'
    Set-Policy 'HistorySearchSettings'                   2 'AI history search: off'
    Set-Policy 'CreateThemesSettings'                    2 'Create themes with AI: off'
    Set-Policy 'AutofillPredictionSettings'              2 'AI-powered autofill: off'
    Set-Policy 'GenAILocalFoundationalModelSettings'     1 'Download local AI model (~GBs): off'
}

# Blocks third-party cookies, with an exception for Google so that "Sign in with Google"
# and Drive embedded in other sites keep working.
function Set-Cookies {
    Set-Policy 'BlockThirdPartyCookies' 1 'Third-party cookies: blocked'
    Set-PolicyList 'CookiesAllowedForUrls' @('https://[*.]google.com', 'https://[*.]google.com.br', 'https://[*.]googleusercontent.com') `
                                          'Exception: Google domains allowed'
}

function Set-Extras {
    Set-Policy 'SyncDisabled'                            1 'Sync: blocked (sign-in still works)'
    Set-Policy 'SafeBrowsingProtectionLevel'             1 'Safe Browsing: Standard mode'
    Set-Policy 'BackgroundModeEnabled'                   0 'Run in background when closed: off'
    Set-Policy 'ShoppingListEnabled'                     0 'Shopping list and price tracking: off'
    Set-Policy 'DefaultBrowserSettingEnabled'            0 '"Not your default browser" prompt: off'
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
    Write-Loading 'Reading what TidyWin set in Chrome' 50
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
        @{ Id = 'Telemetry'; Label = 'Turn telemetry back on'; Desc = 'Chrome can send usage reports, the pages you visit and feedback to Google again.'; Names = Get-PolicyNames { Set-Telemetry } }
        @{ Id = 'NoSearchSuggestions'; Label = 'Turn search suggestions back on'; Desc = 'What you type in the address bar goes to Google while you type again.'; Names = @('SearchSuggestEnabled') }
        @{ Id = 'NoPrefetch'; Label = 'Turn page preloading back on'; Desc = 'Chrome preloads the pages it thinks you will open again.'; Names = @('NetworkPredictionOptions') }
        @{ Id = 'AI'; Label = 'Turn AI features back on'; Desc = 'Gemini, AI Mode, "Help me write" and the other AI features come back.'; Names = Get-PolicyNames { Set-AI } }
        @{ Id = 'Cookies'; Label = 'Allow third-party cookies again'; Desc = 'Chrome goes back to its own cookie settings.'; Names = Get-PolicyNames { Set-Cookies } }
        @{ Id = 'Extras'; Label = 'Turn sync and extras back on'; Desc = 'Sync, running in the background, the shopping list and the "not your default browser" prompt come back.'; Names = Get-PolicyNames { Set-Extras } }
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
if ($Revert) { Invoke-Undo $C (Get-UndoGroups) 'Chrome'; return }
if ($Answers) {
    $Answers = Get-BrowserAnswers $Answers 'Chrome'
    if (-not $Answers) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
}

$installed = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Chrome not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
}

# --- Options: the panel's page, or asked here. Nothing comes selected.
$T = 'Chrome'
$fields = @(
    New-Field $T 'Telemetry' 'toggle' 'Turn off telemetry' 'Chrome stops sending usage reports, the pages you visit and feedback to Google. Spell check keeps working on your PC.' $false
    New-Field $T 'NoSearchSuggestions' 'toggle' 'Turn off search suggestions' 'What you type in the address bar stops going to Google while you type.' $false
    New-Field $T 'NoPrefetch' 'toggle' 'Turn off page preloading' 'Sites stop learning about links you never opened. Pages open a little slower.' $false
    New-Field $T 'AI' 'toggle' 'Turn off AI features' 'Gemini, AI Mode, "Help me write" and the other AI features go away.' $false
    New-Field $T 'Cookies' 'toggle' 'Block third-party cookies' 'Sites can''t follow you across other sites. "Sign in with Google" keeps working.' $false
    New-Field $T 'Extras' 'toggle' 'Turn off sync and extras' 'No sync, no running in the background after closing, no shopping list and no "not your default browser" prompt. Safe Browsing stays on Standard.' $false
)
Write-Loading 'Reading the Chrome settings' 50
if ($Describe) { Write-OptionsPage $Describe (Get-BrowserFields $fields 'Chrome' 'Make Chrome more private, without breaking the Google sign-in.'); return }
if (-not $script:Panel) { Write-Host "`nConfigure-Chrome" -ForegroundColor Green }   # in the panel the page already has the title
$v = Read-Options $fields $Answers
if (-not @($v.Keys | Where-Object { $v[$_] })) { Write-Host 'Nothing was selected, so nothing was changed.'; return }
# --- Apply
if ($v.Telemetry) { Write-Step 'Telemetry and data sent to Google'; Set-Telemetry }
if ($v.NoSearchSuggestions -or $v.NoPrefetch) {
    Write-Step 'Search suggestions and preloading'
    if ($v.NoSearchSuggestions) { Set-Policy 'SearchSuggestEnabled'     0 'Search suggestions: off' }
    if ($v.NoPrefetch)          { Set-Policy 'NetworkPredictionOptions' 2 'Page preloading: off' }
}
if ($v.AI)      { Write-Step 'Artificial intelligence'; Set-AI }
if ($v.Cookies) { Write-Step 'Third-party cookies';     Set-Cookies }
if ($v.Extras)  { Write-Step 'Sync, background and extras'; Set-Extras }

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Chrome." -ForegroundColor Green; Write-Host '  To check: chrome://policy' -ForegroundColor DarkGray
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host 'Chrome is open: close all of its windows for the changes to take effect.' -ForegroundColor DarkYellow
}
Write-Host @'

Outside Chrome, it is also worth reviewing your Google account (myaccount.google.com/data-and-privacy):
  - "Web & App Activity"  -> pause it or turn on auto-delete
  - "My Ad Center"        -> turn off personalized ads
'@

#endregion
