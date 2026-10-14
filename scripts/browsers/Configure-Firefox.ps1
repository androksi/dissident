#Requires -RunAsAdministrator
<#
    Configure-Firefox.ps1 — a clean Firefox: no telemetry, sponsored content, recommendations or AI,
    with uBlock Origin and Bitwarden installed

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1 -Revert

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
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$F = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'


#region ==================== 1. HELPERS ====================

$script:Failures = 0


# Writes the policy (in $F or in a subkey) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$SubKey, [string]$Name, [object]$Value, [string]$Description, [string]$Type = 'DWord') {
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

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
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
    if ($KeepTranslations) {
        Set-Policy 'AIControls\Translations' 'Value' 'available' 'Page translation (local): kept' 'String'
    } else {
        Set-Policy 'AIControls\Translations' 'Value' 'blocked' 'Page translation: off'            'String'
    }
    Set-Policy 'GenerativeAI'   'Enabled'                    0 'AI features (older versions): off'
}

# Buttons that show up in the address bar when a site allows them. Set through the "Preferences" policy
# (locked, so Firefox cannot turn them back on):
#   browser.taskbarTabs.enabled                                   "Add to taskbar" (Windows, Firefox 142+)
#   media.videocontrols.picture-in-picture.urlbar-button.enabled  Picture-in-Picture button (PiP itself
#                                                                 keeps working from the video and right-click)
#   browser.translations.enable                                   translation icon, only if translation is off
function Set-AddressBarButtons([bool]$KeepTranslations) {
    $prefs = [ordered]@{
        'browser.taskbarTabs.enabled'                                  = '"Add to taskbar": off'
        'media.videocontrols.picture-in-picture.urlbar-button.enabled' = 'Picture-in-Picture button: off'
    }
    if (-not $KeepTranslations) { $prefs['browser.translations.enable'] = 'Translation icon: off' }
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
        Write-Host '  [removed] AutoConfig (Reader View icon is back)' -ForegroundColor DarkGray
    }
}

# Installed automatically from Mozilla's official store and kept up to date.
# "normal_installed" = you can disable them, but they can't be removed. Also allowed in private windows.
function Set-Extensions {
    $extensions = [ordered]@{
        'uBlock0@raymondhill.net'                = 'uBlock Origin'
        '{446900e4-71c2-419f-a6a7-df9c091e268b}' = 'Bitwarden'
    }
    $entries = foreach ($id in $extensions.Keys) {
        '"{0}":{{"installation_mode":"normal_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/{0}/latest.xpi","private_browsing":true}}' -f $id
    }
    $json = '{' + ($entries -join ',') + '}'
    Set-Policy '' 'ExtensionSettings' @($json) "Installed: $($extensions.Values -join ', ')" 'MultiString'
}

# Before turning it off: warns if Firefox itself has saved passwords (they are hidden, not deleted).
function Set-BitwardenOnly {
    $saved = 0
    Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $saved += @((Get-Content $_.FullName -Raw | ConvertFrom-Json).logins).Count } catch { }
    }
    if ($saved -gt 0) {
        Write-Host "  WARNING: Firefox has $saved saved password(s). They will not be deleted, only hidden." -ForegroundColor Yellow
        Write-Host '  To move them to Bitwarden: Firefox → about:logins → menu (...) → Export passwords;' -ForegroundColor Yellow
        Write-Host '  then, in the Bitwarden web vault: Tools → Import data → Firefox (csv). Delete the .csv afterwards.' -ForegroundColor Yellow
    }
    Set-Policy ''               'PasswordManagerEnabled'     0 'Firefox password manager: off'
    Set-Policy ''               'OfferToSaveLogins'          0 'Offer to save passwords: off'
    Set-Policy ''               'AutofillAddressEnabled'     0 'Save/fill addresses: off'
    Set-Policy ''               'AutofillCreditCardEnabled'  0 'Save/fill payment cards: off'
}

# The three optional choices asked at the start.
function Set-OptionalPrivacy([bool]$NoSearchSuggestions, [bool]$NoPrefetch, [bool]$HttpsOnly) {
    if ($NoSearchSuggestions) { Set-Policy '' 'SearchSuggestEnabled' 0 'Search suggestions: off' }
    if ($NoPrefetch)          { Set-Policy '' 'NetworkPrediction'    0 'Page preloading: off' }
    if ($HttpsOnly)           { Set-Policy '' 'HttpsOnlyMode' 'enabled' 'HTTPS-Only Mode: on' 'String' }
}


#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step 'Removing Firefox policies'
    Remove-ReaderViewButton (Get-FirefoxDir)
    if (Test-Path $F) {
        Get-ChildItem $F -Recurse | ForEach-Object {
            $sub = $_.Name -replace '^.*\\Mozilla\\Firefox\\?', ''
            $_.Property | ForEach-Object { Write-Host "  [removed] $sub\$_" -ForegroundColor DarkGray }
        }
        (Get-Item $F).Property | ForEach-Object { Write-Host "  [removed] $_" -ForegroundColor DarkGray }
        Remove-Item $F -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nDone. Close and reopen Firefox." -ForegroundColor Green
        Write-Host 'Note: uBlock Origin and Bitwarden remain installed; remove them in about:addons if you want.'
    } else {
        Write-Host '  No Firefox policies found; nothing to do.'
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$ffDir = Get-FirefoxDir
if (-not $ffDir) {
    Write-Host 'Firefox not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
}

Write-Host "`nConfigure-Firefox" -ForegroundColor Green

# --- Questions
Write-Host '  Five choices (arrows and Enter; the default is already selected):'
$noSearchSuggestions = Ask 'Turn off search suggestions while typing? (what you type goes to the search engine in real time)' $false
$noPrefetch          = Ask 'Turn off page preloading? (sites learn about links you never opened)' $true
$httpsOnly           = Ask 'Turn on HTTPS-Only Mode? (warns before opening sites without a secure connection)' $true
$keepTranslations    = Ask 'Keep page translation? (runs on your PC; if turned off, the translate icon disappears from the address bar)' $true
$noReaderView        = Ask 'Remove the Reader View icon from the address bar? (the "book" that shows up on articles)' $false

# --- Apply
Write-Step 'Telemetry';                   Set-Telemetry
Write-Step 'Sponsored content and recommendations'; Set-SponsoredAndRecommendations
Write-Step 'Artificial intelligence';      Set-AI $keepTranslations
Write-Step 'Address bar buttons';  Set-AddressBarButtons $keepTranslations
if ($noReaderView) { Set-ReaderViewButton $ffDir } else { Remove-ReaderViewButton $ffDir }
Write-Step 'Extensions';                    Set-Extensions
Write-Step 'Passwords (Bitwarden only)';      Set-BitwardenOnly
Write-Step 'Privacy choices';      Set-OptionalPrivacy $noSearchSuggestions $noPrefetch $httpsOnly

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Firefox (or check about:policies)." -ForegroundColor Green
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
