#Requires -RunAsAdministrator
<#
    configure-firefox.ps1 — a clean Firefox: no telemetry, sponsored content, recommendations or AI,
    with uBlock Origin and Bitwarden installed

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\configure-firefox.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\configure-firefox.ps1 -Revert

    Uses Firefox's official policies (github.com/mozilla/policy-templates). They apply even if
    Firefox is installed later. Close and reopen Firefox to apply. It will show
    "Your browser is being managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.

    Passwords: turns off Firefox's own password manager, so only Bitwarden is used.
    Address bar: removes the "Add to taskbar" and Picture-in-Picture buttons.
    Four questions: search suggestions, page preloading, HTTPS-Only mode and page translation
    (Enter = default).

    Does NOT touch: site sign-ins (Google included), tracking protection (stays on the default,
    which already isolates cookies per site) and updates.

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
$F = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'


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


# Writes the policy (in $F or in a subkey) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$SubKey, [string]$Name, [object]$Value, [string]$Description, [string]$Type = 'DWord') {
    if ($null -ne $script:Collect) { [void]$script:Collect.Add($(if ($SubKey) { "$SubKey\$Name" } else { $Name })); return }   # -Revert: only the names
    $key = if ($SubKey) { "$F\$SubKey" } else { $F }
    $label = if ($SubKey) { "$SubKey\$Name" } else { $Name }
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $key -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $shown = if ($Type -eq 'MultiString') { '(JSON)' } else { $Value }
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host ("{0,-46}" -f $Description) -NoNewline
        Write-Host "$label = $shown" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERROR] ' -ForegroundColor Red -NoNewline
        Write-Host "$Description ($label): $($_.Exception.Message)"
    }
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
    Set-Policy ''               'DisableTelemetry'           1 'Telemetry: off'
    Set-Policy ''               'DisableFirefoxStudies'      1 'Studies and remote experiments: off'
    Set-Policy ''               'DisableDefaultBrowserAgent' 1 'Default browser agent (task): off'
    Set-Policy ''               'DontCheckDefaultBrowser'    1 '"Not your default browser" prompt: off'
}

function Set-SponsoredAndRecommendations {
    Set-Policy 'FirefoxHome'    'SponsoredTopSites'          0 'Sponsored shortcuts on the new tab: off'
    Set-Policy 'FirefoxHome'    'SponsoredStories'           0 'Sponsored stories on the new tab: off'
    Set-Policy 'FirefoxHome'    'Stories'                    0 'Recommended stories on the new tab: off'
    Set-Policy 'FirefoxSuggest' 'SponsoredSuggestions'       0 'Sponsored suggestions in the address bar: off'
    Set-Policy 'FirefoxSuggest' 'WebSuggestions'             0 'Suggestions from Mozilla in the address bar: off'
    Set-Policy 'FirefoxSuggest' 'ImproveSuggest'             0 'Send what you type to Mozilla: off'
    Set-Policy 'UserMessaging'  'ExtensionRecommendations'   0 'Extension recommendations: off'
    Set-Policy 'UserMessaging'  'FeatureRecommendations'     0 'Feature recommendations: off'
    Set-Policy 'UserMessaging'  'MoreFromMozilla'            0 '"More from Mozilla" in settings: off'
    Set-Policy 'UserMessaging'  'SkipOnboarding'             1 'Welcome screens: off'
    Set-Policy 'UserMessaging'  'UrlbarInterventions'        0 'Address bar tips: off'
    Set-Policy 'UserMessaging'  'FirefoxLabs'                0 'Invitations to experimental features: off'
    Set-Policy ''               'NoDefaultBookmarks'         1 'Default bookmarks in new profiles: off'
}

# Firefox 149+ (AIControls) and older versions (GenerativeAI). Page translation runs on your PC without
# sending anything out, so it stays available unless you choose to turn it off (that also hides its
# address bar icon; there is no way to hide only the icon).
function Set-AI([bool]$KeepTranslations) {
    Set-Policy 'AIControls\Default'      'Value' 'blocked'   'AI features (general default): off'  'String'
    if ($KeepTranslations) { Set-Policy 'AIControls\Translations' 'Value' 'available' 'Page translation (local): kept' 'String' }
    Set-Policy 'GenerativeAI'   'Enabled'                    0 'AI features (older versions): off'
}

function Set-NoTranslation {
    Set-Policy 'AIControls\Translations' 'Value' 'blocked' 'Page translation: off' 'String'
}

# Buttons that show up in the address bar when a site allows them. Set through the "Preferences" policy
# (locked, so Firefox cannot turn them back on):
#   browser.taskbarTabs.enabled                                   "Add to taskbar" (Windows, Firefox 142+)
#   media.videocontrols.picture-in-picture.urlbar-button.enabled  Picture-in-Picture button (PiP itself
#                                                                 keeps working from the video and right-click)
#   browser.translations.enable                                   translation icon, only if translation is off
function Set-AddressBarButtons([bool]$Buttons, [bool]$NoTranslation) {
    $prefs = [ordered]@{}
    if ($Buttons) {
        $prefs['browser.taskbarTabs.enabled']                                  = '"Add to taskbar": off'
        $prefs['media.videocontrols.picture-in-picture.urlbar-button.enabled'] = 'Picture-in-Picture button: off'
    }
    if ($NoTranslation) { $prefs['browser.translations.enable'] = 'Translation icon: off' }
    $entries = foreach ($name in $prefs.Keys) { '"{0}":{{"Value":false,"Status":"locked"}}' -f $name }
    $json = '{' + ($entries -join ',') + '}'
    Set-Policy '' 'Preferences' @($json) ($prefs.Values -join '; ') 'MultiString'
}

# Reader View icon ("book" in the address bar). Its preference (reader.parse-on-load.enabled) is not
# accepted by the "Preferences" policy, so it goes through Firefox AutoConfig: two small files in the
# Firefox folder, kept across updates. If another AutoConfig already exists there, it is left alone.
function Get-FirefoxDir {
    $exe = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Split-Path $exe }
}

function Get-AutoConfigPaths([string]$Dir) {
    @{ Loader = Join-Path $Dir 'defaults\pref\autoconfig.js'; Config = Join-Path $Dir 'tidywin.cfg' }
}

function Set-ReaderViewButton([string]$Dir) {
    if (-not $Dir) { Write-Host '  [skipped] Firefox not installed: install it and run this again.' -ForegroundColor DarkYellow; return }
    $p = Get-AutoConfigPaths $Dir
    if ((Test-Path $p.Loader) -and -not (Select-String -Path $p.Loader -Pattern 'tidywin.cfg' -SimpleMatch -Quiet)) {
        Write-Host "  [skipped] Another AutoConfig already exists ($($p.Loader)); not touched." -ForegroundColor DarkYellow
        return
    }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $p.Loader) | Out-Null
        $loader = "// TidyWin: loads tidywin.cfg from the Firefox folder`r`npref(`"general.config.filename`", `"tidywin.cfg`");`r`npref(`"general.config.obscure_value`", 0);`r`n"
        $config = "// TidyWin AutoConfig (Firefox skips this first line)`r`nlockPref(`"reader.parse-on-load.enabled`", false);`r`n"
        [IO.File]::WriteAllText($p.Loader, $loader, [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($p.Config, $config, [Text.Encoding]::ASCII)
        Write-Host '  [ok] Reader View icon: off' -ForegroundColor Green
    } catch {
        $script:Failures++
        Write-Host "  [ERROR] Reader View icon: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Removes only TidyWin's AutoConfig (the loader is checked first).
function Remove-ReaderViewButton([string]$Dir) {
    if (-not $Dir) { return }
    $p = Get-AutoConfigPaths $Dir
    if ((Test-Path $p.Loader) -and (Select-String -Path $p.Loader -Pattern 'tidywin.cfg' -SimpleMatch -Quiet)) {
        Remove-Item $p.Loader, $p.Config -Force -ErrorAction SilentlyContinue
        Write-Host '  [removed] AutoConfig'; Write-Host '            The Reader View icon is back.' -ForegroundColor DarkGray
    }
}

# Installed automatically from Mozilla's official store and kept up to date, each one its own entry of
# ExtensionSettings (the other entries stay). "normal_installed" = you can disable it, but it can't be
# removed. Also allowed in private windows.
$UBlockId    = 'uBlock0@raymondhill.net'
$BitwardenId = '{446900e4-71c2-419f-a6a7-df9c091e268b}'
$Extras      = 'Extensions and passwords'      # their title in the panel's list

function Set-Extension([string]$Id, [string]$Name) {
    if ($null -ne $script:Collect) { [void]$script:Collect.Add("ext:$Id"); return }   # -Revert: only the names
    try {
        $all = Get-PolicyJson $F 'ExtensionSettings'
        if (-not $all) { $all = New-Object psobject }
        $entry = [pscustomobject]@{ installation_mode = 'normal_installed'; install_url = "https://addons.mozilla.org/firefox/downloads/latest/$Id/latest.xpi"; private_browsing = $true }
        $all | Add-Member -NotePropertyName $Id -NotePropertyValue $entry -Force
        Save-PolicyJson $F 'ExtensionSettings' $all 'MultiString'
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host ("{0,-46}" -f "Installed: $Name") -NoNewline
        Write-Host "ExtensionSettings = $Id" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERROR] ' -ForegroundColor Red -NoNewline
        Write-Host "$Name (ExtensionSettings): $($_.Exception.Message)"
    }
}

# Before turning it off: warns if Firefox itself has saved passwords (they are hidden, not deleted).
function Set-BitwardenOnly {
    $saved = 0
    Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $saved += @((Get-Content $_.FullName -Raw | ConvertFrom-Json).logins).Count } catch { }
    }
    if ($saved -gt 0 -and $null -eq $script:Collect) {
        Write-Host "  WARNING: Firefox has $saved saved password(s). They will not be deleted, only hidden." -ForegroundColor Yellow
        Write-Host '  To move them to Bitwarden: Firefox → about:logins → menu (...) → Export passwords;' -ForegroundColor Yellow
        Write-Host '  Then, in the Bitwarden web vault: Tools → Import data → Firefox (csv). Delete the .csv afterwards.' -ForegroundColor Yellow
    }
    Set-Policy ''               'PasswordManagerEnabled'     0 'Firefox password manager: off'
    Set-Policy ''               'OfferToSaveLogins'          0 'Offer to save passwords: off'
    Set-Policy ''               'AutofillAddressEnabled'     0 'Save/fill addresses: off'
    Set-Policy ''               'AutofillCreditCardEnabled'  0 'Save/fill payment cards: off'
}

# Search suggestions, preloading and HTTPS-Only Mode, each on its own switch.
function Set-OptionalPrivacy([bool]$NoSearchSuggestions, [bool]$NoPrefetch, [bool]$HttpsOnly) {
    if ($NoSearchSuggestions) { Set-Policy '' 'SearchSuggestEnabled' 0 'Search suggestions: off' }
    if ($NoPrefetch)          { Set-Policy '' 'NetworkPrediction'    0 'Page preloading: off' }
    if ($HttpsOnly)           { Set-Policy '' 'HttpsOnlyMode' 'enabled' 'HTTPS-Only Mode: on' 'String' }
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

# Policies that hold a JSON object, one entry per name: "pref:name" is an entry of Preferences,
# "ext:id" an extension of ExtensionSettings. Each entry is added and undone on its own.
$JsonPolicies = @{ pref = 'Preferences'; ext = 'ExtensionSettings' }

function Get-PolicyJson([string]$Root, [string]$Value) {
    $raw = (Get-ItemProperty $Root -Name $Value -ErrorAction SilentlyContinue).$Value
    if (-not $raw) { return $null }
    try { return (@($raw) -join '') | ConvertFrom-Json } catch { return $null }
}

# Writes the object back as $Kind (MultiString or String), or removes the value when nothing is left in it.
function Save-PolicyJson([string]$Root, [string]$Value, $Object, [string]$Kind) {
    if ($Object -and @($Object.PSObject.Properties).Count) {
        if (-not (Test-Path $Root)) { New-Item -Path $Root -Force -ErrorAction Stop | Out-Null }
        $json = $Object | ConvertTo-Json -Compress -Depth 5
        New-ItemProperty $Root -Name $Value -Value $(if ($Kind -eq 'MultiString') { @($json) } else { $json }) -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    } else {
        Remove-ItemProperty $Root -Name $Value -ErrorAction SilentlyContinue
    }
}

function Test-PolicyName([string]$Root, [string]$Name) {
    if ($Name -match '^(pref|ext):(.+)$') { $obj = Get-PolicyJson $Root $JsonPolicies[$Matches[1]]; return [bool]($obj -and $obj.PSObject.Properties[$Matches[2]]) }
    $p = Split-PolicyName $Root $Name
    if ($null -eq $p.Data -and (Test-Path "$($p.Key)\$($p.Value)")) { return $true }
    $item = Get-ItemProperty $p.Key -Name $p.Value -ErrorAction SilentlyContinue
    return [bool]$item -and ($null -eq $p.Data -or "$($item.($p.Value))" -eq $p.Data)
}

function Remove-PolicyName([string]$Root, [string]$Name) {
    if (-not (Test-PolicyName $Root $Name)) { return }
    if ($Name -match '^(pref|ext):(.+)$') {
        $value = $JsonPolicies[$Matches[1]]; $entry = $Matches[2]
        $kind = try { "$((Get-Item $Root).GetValueKind($value))" } catch { 'MultiString' }      # kept as it was
        $obj = Get-PolicyJson $Root $value
        $obj.PSObject.Properties.Remove($entry)
        Save-PolicyJson $Root $value $obj $kind
    } else {
        $p = Split-PolicyName $Root $Name
        if ($null -eq $p.Data -and (Test-Path "$($p.Key)\$($p.Value)")) { Remove-Item "$($p.Key)\$($p.Value)" -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-ItemProperty $p.Key -Name $p.Value -ErrorAction SilentlyContinue
    }
    Write-Host "  [removed] $($Name -replace '^pref:', 'Preferences: ' -replace '^ext:', 'ExtensionSettings: ' -replace '=.*$', '')" -ForegroundColor DarkGray
}

# Every value under the policies key that no group knows about ("Subkey\Value").
function Get-OtherPolicies([string]$Root, [object[]]$Groups) {
    if (-not (Test-Path $Root)) { return @() }
    $known = @($Groups | ForEach-Object { $_.Names } | ForEach-Object { if ($_ -match '^(pref|ext):') { $JsonPolicies[$Matches[1]] } else { $_ -replace '=.*$', '' } })
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
    $script:UndoGroups = @($script:UndoGroups | Where-Object { -not $_.Section }) + @($script:UndoGroups | Where-Object { $_.Section })   # the extensions last, under their title
    if (-not $script:UndoGroups) { return @(New-Field $Browser 'Nothing' 'header' 'Nothing to undo' "$Browser has no settings from TidyWin on this PC." $null) }
    return @($script:UndoGroups | ForEach-Object { New-Field $Browser $_.Id 'toggle' $_.Label $_.Desc $false @{ section = "$($_.Section)" } })
}

function Invoke-Undo([string]$Root, [object[]]$Groups, [string]$Browser) {
    $fields = Get-UndoFields $Root $Groups $Browser
    # The panel's Undo → Browsers page: a switch for this browser and, under it, what can be undone
    Write-Loading 'Reading what TidyWin set in Firefox' 50
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
        @{ Id = 'Telemetry'; Label = 'Turn telemetry back on'; Desc = 'Firefox can send usage data, join studies and ask to be the default browser again.'; Names = Get-PolicyNames { Set-Telemetry } }
        @{ Id = 'Sponsored'; Label = 'Bring sponsored content back'; Desc = 'Sponsored shortcuts and stories, Mozilla suggestions, feature tips and the default bookmarks come back.'; Names = Get-PolicyNames { Set-SponsoredAndRecommendations } }
        @{ Id = 'AI'; Label = 'Turn AI features back on'; Desc = 'The chatbot and the other AI features come back.'; Names = @('AIControls\Default\Value', 'GenerativeAI\Enabled', 'AIControls\Translations\Value=available') }
        @{ Id = 'NoTranslation'; Label = 'Turn page translation back on'; Desc = 'Translation and its icon in the address bar come back.'; Names = @('AIControls\Translations\Value=blocked', 'pref:browser.translations.enable') }
        @{ Id = 'Buttons'; Label = 'Bring the address bar buttons back'; Desc = '"Add to taskbar" and the Picture-in-Picture button come back.'; Names = @('pref:browser.taskbarTabs.enabled', 'pref:media.videocontrols.picture-in-picture.urlbar-button.enabled') }
        @{ Id = 'NoReaderView'; Label = 'Bring the Reader View icon back'; Desc = 'The book icon shows up on articles again.'; Names = @()
           Test = { $dir = Get-FirefoxDir; if ($dir) { $p = Get-AutoConfigPaths $dir; (Test-Path $p.Loader) -and (Select-String -Path $p.Loader -Pattern 'tidywin.cfg' -SimpleMatch -Quiet) } }
           Undo = { Remove-ReaderViewButton (Get-FirefoxDir) } }
        @{ Id = 'UBlock'; Label = 'Stop managing uBlock Origin'; Desc = 'It stays installed, and can then be removed in about:addons.'; Names = @("ext:$UBlockId"); Section = $Extras }
        @{ Id = 'BitwardenExtension'; Label = 'Stop managing Bitwarden'; Desc = 'It stays installed, and can then be removed in about:addons.'; Names = @("ext:$BitwardenId"); Section = $Extras }
        @{ Id = 'Bitwarden'; Label = 'Save passwords in Firefox again'; Desc = 'Firefox can save passwords, addresses and cards again, and shows the passwords it already had.'; Names = Get-PolicyNames { Set-BitwardenOnly }; Section = $Extras }
        @{ Id = 'NoSearchSuggestions'; Label = 'Turn search suggestions back on'; Desc = 'What you type in the address bar goes to the search engine while you type again.'; Names = @('SearchSuggestEnabled') }
        @{ Id = 'NoPrefetch'; Label = 'Turn page preloading back on'; Desc = 'Firefox preloads the pages it thinks you will open again.'; Names = @('NetworkPrediction') }
        @{ Id = 'HttpsOnly'; Label = 'Turn HTTPS-Only Mode off'; Desc = 'Firefox opens sites without a secure connection without warning again.'; Names = @('HttpsOnlyMode') }
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
            [ordered]@{ value = $_.id; label = $_.label; note = $_.desc; warn = "$($_.warn)"; group = "$($_.section)" } }) }
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
if ($Revert) { Invoke-Undo $F (Get-UndoGroups) 'Firefox'; return }
if ($Answers) {
    $Answers = Get-BrowserAnswers $Answers 'Firefox'
    if (-not $Answers) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
}

$ffDir = Get-FirefoxDir
if (-not $ffDir) {
    Write-Host 'Firefox not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
}

if (-not $script:Panel) { Write-Host "`nConfigure-Firefox" -ForegroundColor Green }   # in the panel the page already has the title

# --- Options: the panel's page, or asked here. Nothing comes selected.
$saved = 0
Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" -ErrorAction SilentlyContinue | ForEach-Object {
    try { $saved += @((Get-Content $_.FullName -Raw | ConvertFrom-Json).logins).Count } catch { }
}
$T = 'Firefox'
$fields = @(
    New-Field $T 'Telemetry' 'toggle' 'Turn off telemetry' 'Firefox stops sending usage data and joining studies, and stops asking to be the default browser.' $false
    New-Field $T 'Sponsored' 'toggle' 'Turn off sponsored content' 'No sponsored shortcuts or stories on the new tab, no Mozilla suggestions in the address bar and no feature tips.' $false
    New-Field $T 'AI' 'toggle' 'Turn off AI features' 'The chatbot and the other AI features go away. Page translation stays, unless you turn it off too.' $false
    New-Field $T 'NoTranslation' 'toggle' 'Turn off page translation' 'Translation runs on your PC. Turning it off also removes its icon from the address bar.' $false
    New-Field $T 'Buttons' 'toggle' 'Remove extra address bar buttons' '"Add to taskbar" and the Picture-in-Picture button go away. Picture-in-Picture still works from the video.' $false
    New-Field $T 'NoReaderView' 'toggle' 'Remove the Reader View icon' 'The book icon that shows up on articles goes away.' $false
    New-Field $T 'NoSearchSuggestions' 'toggle' 'Turn off search suggestions' 'What you type in the address bar stops going to the search engine while you type.' $false
    New-Field $T 'NoPrefetch' 'toggle' 'Turn off page preloading' 'Sites stop learning about links you never opened.' $false
    New-Field $T 'HttpsOnly' 'toggle' 'Turn on HTTPS-Only Mode' 'Firefox warns before opening a site without a secure connection.' $false
    # Last, under their own title
    New-Field $T 'UBlock' 'toggle' 'Add uBlock Origin' 'Blocks ads and trackers. From Mozilla''s add-on store, kept up to date. It can be turned off, not removed.' $false @{ section = $Extras }
    New-Field $T 'BitwardenExtension' 'toggle' 'Add Bitwarden' 'The password manager. From Mozilla''s add-on store, kept up to date. It can be turned off, not removed.' $false @{ section = $Extras }
    New-Field $T 'Bitwarden' 'toggle' 'Use Bitwarden for passwords' 'Firefox stops saving passwords, addresses and cards. Saved passwords are hidden, not deleted.' $false @{ section = $Extras; warn = $(if ($saved) { "Firefox has $saved saved password(s). Export them to Bitwarden first: about:logins, menu, Export passwords." } else { '' }) }
)
Write-Loading 'Reading the Firefox settings' 50
if ($Describe) { Write-OptionsPage $Describe (Get-BrowserFields $fields 'Firefox' 'Turn off telemetry, sponsored content and AI, and add uBlock Origin.'); return }
$v = Read-Options $fields $Answers
if (-not @($v.Keys | Where-Object { $v[$_] })) { Write-Host 'Nothing was selected, so nothing was changed.'; return }
# --- Apply
if ($v.Telemetry) { Write-Step 'Telemetry';                             Set-Telemetry }
if ($v.Sponsored) { Write-Step 'Sponsored content and recommendations'; Set-SponsoredAndRecommendations }
if ($v.AI)        { Write-Step 'Artificial intelligence';               Set-AI (-not $v.NoTranslation) }
if ($v.NoTranslation -or $v.Buttons) {
    Write-Step 'Address bar'
    if ($v.NoTranslation) { Set-NoTranslation }
    Set-AddressBarButtons ([bool]$v.Buttons) ([bool]$v.NoTranslation)
}
if ($v.NoReaderView) { Write-Step 'Reader View icon'; Set-ReaderViewButton $ffDir }
if ($v.UBlock -or $v.BitwardenExtension) {
    Write-Step 'Extensions'
    if ($v.UBlock)             { Set-Extension $UBlockId 'uBlock Origin' }
    if ($v.BitwardenExtension) { Set-Extension $BitwardenId 'Bitwarden' }
}
if ($v.Bitwarden)    { Write-Step 'Passwords: Bitwarden only'; Set-BitwardenOnly }
if ($v.NoSearchSuggestions -or $v.NoPrefetch -or $v.HttpsOnly) {
    Write-Step 'Privacy'; Set-OptionalPrivacy ([bool]$v.NoSearchSuggestions) ([bool]$v.NoPrefetch) ([bool]$v.HttpsOnly)
}

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Firefox." -ForegroundColor Green; Write-Host '  To check: about:policies' -ForegroundColor DarkGray
if (Get-Process firefox -ErrorAction SilentlyContinue) {
    Write-Host 'Firefox is open: close all of its windows for the changes to take effect.' -ForegroundColor DarkYellow
}
Write-Host @'

Google with links only (no AI and no extra blocks) as the default search — do this once:
  1. Open about:preferences#search
  2. Under "Search Shortcuts", click "Add"
   Name:  Google Web
   URL:   https://www.google.com/search?q=%s&udm=14
   Keyword (optional): @g
  3. At the top, under "Default Search Engine", choose "Google Web"
'@

#endregion
