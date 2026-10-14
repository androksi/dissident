#Requires -RunAsAdministrator
<#
    Configure-Chrome.ps1 — a more private Chrome without breaking the Google account sign-in
    (Gmail, Drive and "Sign in with Google" on other sites keep working)

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1 -Revert

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
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$C = 'HKLM:\SOFTWARE\Policies\Google\Chrome'


#region ==================== 1. HELPERS ====================

$script:Failures = 0


# Writes a policy (DWORD) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$Name, [int]$Value, [string]$Description) {
    try {
        if (-not (Test-Path $C)) { New-Item -Path $C -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $C -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Ok $Description "$Name = $Value"
    } catch { Write-Fail $Description $Name $_ }
}

# List policies live in a subkey with values "1", "2", "3"... (recreated from scratch).
function Set-PolicyList([string]$Name, [string[]]$Items, [string]$Description) {
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

function Set-Telemetry([bool]$NoSearchSuggestions, [bool]$NoPrefetch) {
    Set-Policy 'MetricsReportingEnabled'                 0 'Usage and crash reports: off'
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Sending visited URLs: off'
    Set-Policy 'SpellCheckServiceEnabled'                0 'Cloud spell check: off (local stays)'
    Set-Policy 'AlternateErrorPagesEnabled'              0 'Suggestions on error pages: off'
    Set-Policy 'FeedbackSurveysEnabled'                  0 'Satisfaction surveys: off'
    Set-Policy 'SafeBrowsingSurveysEnabled'              0 'Safe Browsing surveys: off'
    Set-Policy 'UserFeedbackAllowed'                     0 'Send feedback to Google: off'
    if ($NoSearchSuggestions) { Set-Policy 'SearchSuggestEnabled'     0 'Search suggestions: off' }
    if ($NoPrefetch)          { Set-Policy 'NetworkPredictionOptions' 2 'Page preloading: off' }
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

function Remove-Policies {
    Write-Step 'Removing Chrome policies'
    if (Test-Path $C) {
        (Get-Item $C).Property | ForEach-Object { Write-Host "  [removed] $_" -ForegroundColor DarkGray }
        Get-ChildItem $C | ForEach-Object { Write-Host "  [removed] $($_.PSChildName)" -ForegroundColor DarkGray }
        Remove-Item $C -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nDone. Close and reopen Chrome." -ForegroundColor Green
    } else {
        Write-Host '  No Chrome policies found; nothing to do.'
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$installed = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Chrome not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
}

# --- Questions
Write-Host "`nConfigure-Chrome" -ForegroundColor Green
Write-Host '  Two choices (arrows and Enter; the default is already selected):'
$noSearchSuggestions = Ask 'Turn off search suggestions while typing? (what you type in the address bar goes to Google in real time)' $false
$noPrefetch          = Ask 'Turn off page preloading? (sites learn about links you never opened; pages open a little slower)' $true

# --- Apply
Write-Step 'Telemetry and data sent to Google';             Set-Telemetry $noSearchSuggestions $noPrefetch
Write-Step 'Artificial intelligence (Gemini and AI features)'; Set-AI
Write-Step 'Third-party cookies (cross-site tracking)';   Set-Cookies
Write-Step 'Sync, background and extras';             Set-Extras

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Chrome (or check chrome://policy)." -ForegroundColor Green
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host 'Chrome is open: close all of its windows for the changes to take effect.' -ForegroundColor DarkYellow
}
Write-Host @'

Outside Chrome, it is also worth reviewing your Google account (myaccount.google.com/data-and-privacy):
  - "Web & App Activity"  -> pause it or turn on auto-delete
  - "My Ad Center"        -> turn off personalized ads
'@

#endregion
