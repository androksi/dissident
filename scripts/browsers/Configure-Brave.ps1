#Requires -RunAsAdministrator
<#
    Configure-Brave.ps1 — a clean Brave: no Wallet, VPN, Rewards, Leo, News, Talk, Playlist, Tor, Speedreader or telemetry

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Brave.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Brave.ps1 -Revert

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
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$B = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'


#region ==================== 1. HELPERS ====================

$script:Failures = 0


# Writes a policy (DWORD) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$Name, [int]$Value, [string]$Description) {
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

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
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

function Remove-Policies {
    Write-Step 'Removing Brave policies'
    if (Test-Path $B) {
        (Get-Item $B).Property | ForEach-Object { Write-Host "  [removed] $_" -ForegroundColor DarkGray }
        Remove-Item $B -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nDone. Close and reopen Brave." -ForegroundColor Green
    } else {
        Write-Host '  No Brave policies found; nothing to do.'
    }
    if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $FirewallRuleName
        Write-Host "  [removed] firewall rule '$FirewallRuleName'" -ForegroundColor DarkGray
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$installed = @(
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Brave not found. The policies will be applied anyway and take effect when you install it.' -ForegroundColor DarkYellow
    $installed = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"   # default install path
}

Write-Host "`nConfigure-Brave" -ForegroundColor Green

# --- Question
$castOptions = @(
    'Keep "Cast to TV"',
    'Turn off "Cast to TV"'
)
$disableCast = (Choose 'Cast to TV (Chromecast):' $castOptions 0) -eq 1

# --- Apply
Write-Step 'Brave features';     Set-BraveFeatures
Write-Step 'Brave telemetry';   Set-BraveTelemetry
Write-Step 'Chromium policies'; Set-ChromiumPolicies
Write-Step 'Apps, passwords and cards'; Set-AppsAndAutofill
Write-Step 'Cast to TV';    Set-CastToTv $disableCast $installed

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." -ForegroundColor Yellow }
Write-Host "`nDone. Close and reopen Brave (or check brave://policy)." -ForegroundColor Green
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
