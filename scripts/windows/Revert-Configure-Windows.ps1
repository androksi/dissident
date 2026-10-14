#Requires -RunAsAdministrator
<#
    Revert-Configure-Windows.ps1 — undoes what Configure-Windows.ps1 changed

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Revert-Configure-Windows.ps1

    What does NOT come back on its own:
        - removed apps .............. reinstall from the Microsoft Store
        - OneDrive .................. winget install Microsoft.OneDrive
        - theme, taskbar alignment, search and Task View, extensions, folders ... through Windows Settings
        - taskbar pins .............. right-click the app → "Pin to taskbar"
        - volume .................... on the taskbar volume icon
        - hidden files, battery % ... through Windows Settings
        - unwanted app and download blocking (Windows Security) stays on: it is only protection
    Restart the PC at the end.

    FILE LAYOUT
        1. Helpers
        2. Revert actions (one function per subject)
        3. Execution
#>

param(
)

$ErrorActionPreference = 'Continue'
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'


#region ==================== 1. HELPERS ====================


# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
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

# Deletes registry values (ignores the ones that don't exist).
function Remove-Reg([string]$Path, [string[]]$Names) {
    foreach ($n in $Names) { Remove-ItemProperty -Path $Path -Name $n -ErrorAction SilentlyContinue }
}

# Step title in the terminal.
function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }


#endregion


#region ==================== 2. REVERT ACTIONS ====================

function Restore-TelemetryServices {
    Set-Service DiagTrack -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service DiagTrack -ErrorAction SilentlyContinue
    Set-Service dmwappushservice -StartupType Manual -ErrorAction SilentlyContinue
}

function Restore-TelemetryTasks {
    $tasks = @(
        @('\Microsoft\Windows\Application Experience\',                 'Microsoft Compatibility Appraiser'),
        @('\Microsoft\Windows\Application Experience\',                 'Microsoft Compatibility Appraiser Exp'),
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
    foreach ($t in $tasks) {
        if (Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue) {
            Enable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] | Out-Null
        }
    }
}

function Remove-WindowsPolicies {
    # Telemetry, diagnostics, ads, activity history, search
    Remove-Reg "$P\DataCollection" 'AllowTelemetry','MaxTelemetryAllowed','DoNotShowFeedbackNotifications','LimitDiagnosticLogCollection','LimitDumpCollection','AllowDeviceNameInTelemetry','DisableOneSettingsDownloads'
    Remove-Reg "$P\Windows Error Reporting" 'Disabled'
    Remove-Reg "$P\AppCompat" 'DisableInventory','AITEnable'
    Remove-Reg "$P\AdvertisingInfo" 'DisabledByGroupPolicy'
    Remove-Reg "$P\System" 'EnableActivityFeed','PublishUserActivities','UploadUserActivities'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization'
    Remove-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData'
    Remove-Reg "$P\Windows Search" 'DisableWebSearch','ConnectedSearchUseWeb','EnableDynamicContentInWSB','AllowCortana'
    Remove-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
    # Game DVR (the Xbox apps themselves come back from the Microsoft Store)
    Remove-Reg "$P\GameDVR" 'AllowGameDVR'
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    if (Test-Path 'HKCU:\System\GameConfigStore') { Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -Value 1 -Type DWord }
    # Print Screen key back to opening the Snipping Tool (the app itself comes back from the Microsoft Store)
    Remove-Reg 'HKCU:\Control Panel\Keyboard' 'PrintScreenKeyForSnippingEnabled'
    # Recall
    Remove-Reg "$P\WindowsAI" 'AllowRecallEnablement','DisableAIDataAnalysis'
    # Widgets / News and interests
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests'
    Remove-Reg "$P\Windows Feeds" 'EnableFeeds'
    # Delivery Optimization, consumer apps, OneDrive
    Remove-Reg "$P\DeliveryOptimization" 'DODownloadMode'
    Remove-Reg "$P\CloudContent" 'DisableWindowsConsumerFeatures'
    Remove-Reg "$P\OneDrive" 'DisableFileSyncNGSC'
    # Windows Security (unwanted app blocking stays on: it is protection)
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableEnhancedNotifications'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Virus and threat protection' 'HideRansomwareRecovery'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Account protection' 'UILockdown'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' 'UILockdown'
}

function Restore-Suggestions {
    $CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled',
                   'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') {
        Set-ItemProperty -Path $CDM -Name $n -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled'
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations','ShowSyncProviderNotifications'
}

# Only touches the border if Configure-Windows made it thin (value 0). Windows default: -60.
function Restore-Border {
    $wm = 'HKCU:\Control Panel\Desktop\WindowMetrics'
    if ((Get-ItemProperty $wm -Name PaddedBorderWidth -ErrorAction SilentlyContinue).PaddedBorderWidth -eq '0') {
        Set-ItemProperty $wm -Name PaddedBorderWidth -Value '-60'
        Write-Host '  border restored (takes effect after signing out and back in)'
    }
}

# Pins back to Start the ad shortcuts Configure-Windows unpinned (it saved their names), with the same
# "Pin to Start" as the right-click menu (shell32 resource 51201, in the Windows language). A shortcut
# whose app was never installed can't be pinned again: Windows only shows it on new accounts.
function Restore-StartPins {
    $file = Join-Path $env:ProgramData 'TidyWin\start-unpinned.json'
    if (-not (Test-Path $file)) { Write-Host '  nothing was unpinned'; return }
    $names = @(Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json)
    if (-not ('RevWin.Res' -as [type])) {
        Add-Type -Namespace RevWin -Name Res -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr LoadLibrary(string name);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int LoadString(System.IntPtr module, uint id, System.Text.StringBuilder buffer, int size);
'@
    }
    $text = New-Object System.Text.StringBuilder 256
    [void][RevWin.Res]::LoadString([RevWin.Res]::LoadLibrary('shell32.dll'), 51201, $text, $text.Capacity)
    $pin = $text.ToString().Replace('&', '')
    $apps = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
    $done = @()
    foreach ($item in @($apps.Items())) {
        if ($names -notcontains $item.Name) { continue }
        $verb = @($item.Verbs()) | Where-Object { $n = $_.Name.Replace('&', ''); ($pin -and $n -eq $pin) -or $n -eq 'Pin to Start' } | Select-Object -First 1
        if ($verb) { $verb.DoIt(); $done += $item.Name }
    }
    $left = @($names | Where-Object { $done -notcontains $_ })
    if ($done) { Write-Host "  pinned back: $($done -join ', ')" }
    if ($left) { Write-Host "  not available to pin (app not installed): $($left -join ', ')" -ForegroundColor DarkGray }
    Remove-Item $file -Force -ErrorAction SilentlyContinue
}

# Snap windows back on (Windows default). Takes effect after signing out and back in.
function Restore-SnapWindows {
    $d = 'HKCU:\Control Panel\Desktop'
    if ((Get-ItemProperty $d -Name WindowArrangementActive -ErrorAction SilentlyContinue).WindowArrangementActive -eq '0') {
        Set-ItemProperty $d -Name WindowArrangementActive -Value '1'
        Write-Host '  Snap windows: on (after signing out and back in)'
    }
}

# Automatic DNS (from the router) and no DNS over HTTPS, on every physical adapter.
function Restore-DNS {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        Remove-Item "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  $($adapter.Name): automatic"
    }
    Clear-DnsClientCache
}

# Brings "Home" and "Gallery" back to the File Explorer sidebar and makes it open in Home again.
function Restore-HomeAndGallery {
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo'
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue   # classic right-click menu
    # Music back in Quick access (Windows default), if it is not pinned
    try {
        $music = [Environment]::GetFolderPath('MyMusic')
        $shell = New-Object -ComObject Shell.Application
        $pinned = $shell.Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}').Items() | Where-Object { $_.Path -eq $music }
        if (-not $pinned -and (Test-Path $music)) { $shell.Namespace($music).Self.InvokeVerb('pintohome') }
    } catch { }
    Write-Host '  Home, Gallery, Music in Quick access and the new right-click menu are back (some show up after restarting)'
}

# Folder type discovery, manufacturer apps for devices, WPBT, Fast Startup, Num Lock and verbose blue screen back to the Windows default.
function Restore-ExplorerAndDeviceDefaults {
    Remove-Item 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution'
    # Fast Startup back on (Windows default)
    $power = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    if ((Get-ItemProperty $power -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled -eq 0) {
        Set-ItemProperty $power -Name HiberbootEnabled -Value 1 -Type DWord
    }
    # Num Lock at startup back off (only bit 2; the other bits are kept)
    foreach ($k in 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard', 'HKCU:\Control Panel\Keyboard') {
        $n = [int64]0; [void][int64]::TryParse([string](Get-ItemProperty $k -Name InitialKeyboardIndicators -ErrorAction SilentlyContinue).InitialKeyboardIndicators, [ref]$n)
        if ($n -band 2) { Set-ItemProperty $k -Name InitialKeyboardIndicators -Value ([string]($n -band -bnot [int64]2)) -Type String }
    }
}

# Shows the inetpub folder again (PerfLogs is not recreated: Windows does it when it needs the folder).
function Show-Inetpub {
    $inetpub = "$env:SystemDrive\inetpub"
    if (Test-Path $inetpub) {
        $folder = Get-Item $inetpub -Force
        $folder.Attributes = $folder.Attributes -band -bnot [IO.FileAttributes]::Hidden
        Write-Host '  inetpub: visible again'
    }
}

function Remove-EdgePolicies {
    Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Recurse -Force -ErrorAction SilentlyContinue
    # Desktop shortcut policy (the shortcut itself is not recreated; Edge adds it again on its next update)
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' @('CreateDesktopShortcutDefault', 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}')
}

# Answers saved by Configure-Windows for -Check.
function Remove-SavedAnswers {
    # Only this file: the folder also holds fonts.json (Install-Fonts' record for fonts-revert)
    $dir = Join-Path $env:ProgramData 'TidyWin'
    Remove-Item (Join-Path $dir 'windows.json') -Force -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem $dir -Force -ErrorAction SilentlyContinue)) { Remove-Item $dir -Force -ErrorAction SilentlyContinue }
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Step 'Telemetry services back to default'; Restore-TelemetryServices
Write-Step 'Re-enabling scheduled tasks'; Restore-TelemetryTasks
Write-Step 'Removing policies'; Remove-WindowsPolicies
Write-Step 'Windows suggestions back to default'; Restore-Suggestions
Write-Step 'Window border back to default'; Restore-Border
Write-Step 'Snap windows back on'; Restore-SnapWindows
Write-Step 'DNS back to automatic (from the router)'; Restore-DNS
Write-Step 'Home and Gallery back in File Explorer'; Restore-HomeAndGallery
Write-Step 'Folders, devices, startup and blue screen back to default'; Restore-ExplorerAndDeviceDefaults
Write-Step 'inetpub folder visible again'; Show-Inetpub
Write-Step 'Removing Edge policies'; Remove-EdgePolicies
Write-Step 'Ad shortcuts back in Start'; Restore-StartPins
Write-Step 'Deleting the saved answers (TidyWin)'; Remove-SavedAnswers
Write-Step 'Done. Restart the computer.'

#endregion
