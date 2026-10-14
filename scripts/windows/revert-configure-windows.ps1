#Requires -RunAsAdministrator
<#
    revert-configure-windows.ps1 — undoes what configure-windows.ps1 changed

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\revert-configure-windows.ps1

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
        3. Options and execution (only what is turned on is undone)
#>

param(
    [string]$Describe,   # for the panel: writes the options of the page to this file and stops
    [string]$Answers     # for the panel: what was turned on there (nothing is asked)
)

$ErrorActionPreference = 'Continue'
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'


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

# Deletes registry values (ignores the ones that don't exist).
function Remove-Reg([string]$Path, [string[]]$Names) {
    foreach ($n in $Names) { Remove-ItemProperty -Path $Path -Name $n -ErrorAction SilentlyContinue }
}

# Step title in the terminal.
function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }


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

# Telemetry, diagnostics and error reports
function Remove-TelemetryPolicies {
    Remove-Reg "$P\DataCollection" 'AllowTelemetry','MaxTelemetryAllowed','DoNotShowFeedbackNotifications','LimitDiagnosticLogCollection','LimitDumpCollection','AllowDeviceNameInTelemetry','DisableOneSettingsDownloads'
    Remove-Reg "$P\Windows Error Reporting" 'Disabled'
    Remove-Reg "$P\AppCompat" 'DisableInventory','AITEnable'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization'
    Remove-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData'
}

function Remove-ActivityPolicies { Remove-Reg "$P\System" 'EnableActivityFeed','PublishUserActivities','UploadUserActivities' }

function Remove-SearchPolicies {
    Remove-Reg "$P\Windows Search" 'DisableWebSearch','ConnectedSearchUseWeb','EnableDynamicContentInWSB','AllowCortana'
    Remove-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
}

function Remove-RecallPolicies { Remove-Reg "$P\WindowsAI" 'AllowRecallEnablement','DisableAIDataAnalysis' }

function Remove-WidgetsPolicies {
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests'
    Remove-Reg "$P\Windows Feeds" 'EnableFeeds'
}

function Remove-OneDrivePolicy { Remove-Reg "$P\OneDrive" 'DisableFileSyncNGSC' }

# Game DVR (the Xbox apps themselves come back from the Microsoft Store)
function Restore-GameDVR {
    Remove-Reg "$P\GameDVR" 'AllowGameDVR'
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    if (Test-Path 'HKCU:\System\GameConfigStore') { Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -Value 1 -Type DWord }
}

# Print Screen key back to opening the Snipping Tool (the app itself comes back from the Microsoft Store)
function Restore-PrintScreen { Remove-Reg 'HKCU:\Control Panel\Keyboard' 'PrintScreenKeyForSnippingEnabled' }

function Remove-DeliveryOptimizationPolicy { Remove-Reg "$P\DeliveryOptimization" 'DODownloadMode' }

# Windows Security (unwanted app blocking stays on: it is protection)
function Remove-SecurityPolicies {
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableEnhancedNotifications'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Virus and threat protection' 'HideRansomwareRecovery'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Account protection' 'UILockdown'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' 'UILockdown'
}

# Suggestions, tips, suggested apps and the advertising ID
function Restore-Suggestions {
    Remove-Reg "$P\AdvertisingInfo" 'DisabledByGroupPolicy'
    Remove-Reg "$P\CloudContent" 'DisableWindowsConsumerFeatures'
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
        Write-Host '  Border restored'; Write-Host '  Takes effect after signing out and back in.' -ForegroundColor DarkGray
    }
}

# Pins back to Start the ad shortcuts Configure-Windows unpinned (it saved their names), with the same
# "Pin to Start" as the right-click menu (shell32 resource 51201, in the Windows language). A shortcut
# whose app was never installed can't be pinned again: Windows only shows it on new accounts.
function Restore-StartPins {
    $file = Join-Path $env:ProgramData 'TidyWin\start-unpinned.json'
    if (-not (Test-Path $file)) { Write-Host '  Nothing was unpinned'; return }
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
    if ($done) { Write-Host "  Pinned back: $($done -join ', ')" }
    if ($left) { Write-Host "  Not pinned back, the app is not installed: $($left -join ', ')" -ForegroundColor DarkGray }
    Remove-Item $file -Force -ErrorAction SilentlyContinue
}

# Snap windows back on (Windows default). Takes effect after signing out and back in.
function Restore-SnapWindows {
    $d = 'HKCU:\Control Panel\Desktop'
    if ((Get-ItemProperty $d -Name WindowArrangementActive -ErrorAction SilentlyContinue).WindowArrangementActive -eq '0') {
        Set-ItemProperty $d -Name WindowArrangementActive -Value '1'
        Write-Host '  Snap windows: on'; Write-Host '  Takes effect after signing out and back in.' -ForegroundColor DarkGray
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
    # Music back in Quick access (Windows default), if it is not pinned
    try {
        $music = [Environment]::GetFolderPath('MyMusic')
        $shell = New-Object -ComObject Shell.Application
        $pinned = $shell.Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}').Items() | Where-Object { $_.Path -eq $music }
        if (-not $pinned -and (Test-Path $music)) { $shell.Namespace($music).Self.InvokeVerb('pintohome') }
    } catch { }
    Write-Host '  Home, Gallery and Music in Quick access are back'; Write-Host '  Some show up after restarting.' -ForegroundColor DarkGray
}

# Windows 11's own right-click menu (the classic one was turned on by Configure-Windows)
function Restore-ContextMenu {
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  New right-click menu: back'; Write-Host '  Shows up after restarting File Explorer or the PC.' -ForegroundColor DarkGray
}

# Folder type discovery: File Explorer picks a view for each folder from its contents again.
function Restore-FolderTypes { Remove-Item 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders' -Recurse -Force -ErrorAction SilentlyContinue }

function Restore-DeviceApps { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' }

function Restore-BlueScreen { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' }

function Restore-Wpbt { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' }

# Fast Startup back on (Windows default)
function Restore-FastStartup {
    $power = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    if ((Get-ItemProperty $power -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled -eq 0) {
        Set-ItemProperty $power -Name HiberbootEnabled -Value 1 -Type DWord
    }
}

# Num Lock at startup back off (only bit 2; the other bits are kept)
function Restore-NumLock {
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
        Write-Host '  Inetpub: visible again'
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

# --- Options: the panel's page, or asked here. Nothing comes selected: only what is turned on is undone.
$tidyDir = Join-Path $env:ProgramData 'TidyWin'
$Pv = 'Privacy'; $Ap = 'Apps'; $Fe = 'File Explorer'; $Lk = 'Appearance'; $Sy = 'System'; $Nw = 'Network'
$fields = @(
    New-Field $Pv 'Telemetry' 'toggle' 'Turn telemetry back on' 'Diagnostic data, error reports and their services and scheduled tasks go back to the Windows default.' $false
    New-Field $Pv 'Suggestions' 'toggle' 'Bring suggestions and ads back' 'Tips, suggested apps in Start, the advertising ID and the setup reminders come back.' $false
    New-Field $Pv 'Activity' 'toggle' 'Turn activity history back on' 'Windows can keep a history of the apps and files you use again.' $false
    New-Field $Pv 'WebSearch' 'toggle' 'Bring web results back to search' 'The Start search shows Bing results and search highlights again.' $false
    New-Field $Pv 'Recall' 'toggle' 'Allow Recall again' 'Recall can be turned on again in Settings, on PCs that support it.' $false
    New-Field $Ap 'Widgets' 'toggle' 'Bring Widgets back' 'Widgets and the news on the taskbar can be turned on again.' $false
    New-Field $Ap 'OneDrive' 'toggle' 'Allow OneDrive again' 'OneDrive can run and sync again. To install it back: winget install Microsoft.OneDrive.' $false
    New-Field $Ap 'GameDVR' 'toggle' 'Turn game recording back on' 'The Game Bar can record games again. The Xbox apps come back from the Microsoft Store.' $false
    New-Field $Ap 'PrintScreen' 'toggle' 'Print Screen opens the Snipping Tool' 'The key opens the Snipping Tool again. The app comes back from the Microsoft Store.' $false
    New-Field $Ap 'Edge' 'toggle' 'Remove the Edge settings' 'Every Edge policy goes away. Edge may add its desktop shortcut again on its next update.' $false
    New-Field $Ap 'Security' 'toggle' 'Show all of Windows Security again' 'Its notifications and the hidden areas, like ransomware recovery and account protection, come back.' $false
)
if (Test-Path (Join-Path $tidyDir 'start-unpinned.json')) {
    $fields += New-Field $Ap 'StartPins' 'toggle' 'Pin the ad shortcuts back to Start' 'The shortcuts that were unpinned go back to Start, if their apps are installed.' $false
}
$fields += @(
    New-Field $Fe 'HomeGallery' 'toggle' 'Bring Home and Gallery back' 'They return to the sidebar, File Explorer opens in Home again and Music goes back to Quick access.' $false
    New-Field $Fe 'ContextMenu' 'toggle' 'Bring the new right-click menu back' 'Windows 11 shows its own right-click menu again, with "Show more options".' $false
    New-Field $Fe 'FolderTypes' 'toggle' 'Let each folder pick its view' 'File Explorer chooses the view of each folder from what is in it again.' $false
    New-Field $Fe 'Inetpub' 'toggle' 'Show the inetpub folder' 'The folder on drive C: becomes visible again.' $false
    New-Field $Lk 'Border' 'toggle' 'Bring the window border back' 'The default border around windows comes back after signing out.' $false
    New-Field $Lk 'Snap' 'toggle' 'Turn Snap windows back on' 'Dragging a window to the edge of the screen arranges it again, after signing out.' $false
    New-Field $Sy 'FastStartup' 'toggle' 'Turn Fast Startup back on' 'Windows starts faster after being shut down, the Windows default.' $false
    New-Field $Sy 'NumLock' 'toggle' 'Num Lock off at startup' 'Num Lock starts off again, the Windows default.' $false
    New-Field $Sy 'BlueScreen' 'toggle' 'Simple blue screen' 'The blue screen stops showing the technical details of the error.' $false
    New-Field $Sy 'DeviceApps' 'toggle' 'Download device apps again' 'Windows can download the manufacturer''s apps and icons for your devices again.' $false
    New-Field $Sy 'Wpbt' 'toggle' 'Allow programs from the firmware' 'Windows runs again the programs some PCs install from the firmware (WPBT).' $false
)
if (Test-Path (Join-Path $tidyDir 'windows.json')) {
    $fields += New-Field $Sy 'SavedAnswers' 'toggle' 'Forget the saved choices' 'Check after an update stops finding and reapplying what you chose in Windows.' $false
}
$fields += @(
    New-Field $Nw 'DNS' 'toggle' 'DNS back to automatic' 'The DNS servers come from the router again and DNS over HTTPS is turned off, on every adapter.' $false
    New-Field $Nw 'DeliveryOptimization' 'toggle' 'Share updates with other PCs again' 'Windows can get and send updates through other PCs on your network again, the Windows default.' $false
)
$notes = @('Removed apps come back from the Microsoft Store. Theme, taskbar and the other settings you chose change back in Windows Settings.')

if ($Describe) { Write-OptionsPage $Describe $fields $notes; return }
if (-not $script:Panel) { Write-Host "`nRevert-Configure-Windows" -ForegroundColor Green }   # in the panel the page already has the title
$v = Read-Options $fields $Answers
if (-not @($v.Keys | Where-Object { $v[$_] })) { Write-Host 'Nothing was selected, so nothing was changed.'; return }

# --- Undo what was turned on
if ($v.Telemetry)            { Write-Step 'Telemetry back to default';              Restore-TelemetryServices; Restore-TelemetryTasks; Remove-TelemetryPolicies }
if ($v.Suggestions)          { Write-Step 'Suggestions and ads back';               Restore-Suggestions }
if ($v.Activity)             { Write-Step 'Activity history back on';               Remove-ActivityPolicies }
if ($v.WebSearch)            { Write-Step 'Web results back in search';             Remove-SearchPolicies }
if ($v.Recall)               { Write-Step 'Recall allowed again';                   Remove-RecallPolicies }
if ($v.Widgets)              { Write-Step 'Widgets back';                           Remove-WidgetsPolicies }
if ($v.OneDrive)             { Write-Step 'OneDrive allowed again';                 Remove-OneDrivePolicy }
if ($v.GameDVR)              { Write-Step 'Game recording back on';                 Restore-GameDVR }
if ($v.PrintScreen)          { Write-Step 'Print Screen opens the Snipping Tool';   Restore-PrintScreen }
if ($v.Edge)                 { Write-Step 'Removing Edge policies';                 Remove-EdgePolicies }
if ($v.Security)             { Write-Step 'Windows Security back to default';       Remove-SecurityPolicies }
if ($v.StartPins)            { Write-Step 'Ad shortcuts back in Start';             Restore-StartPins }
if ($v.HomeGallery)          { Write-Step 'Home and Gallery back in File Explorer'; Restore-HomeAndGallery }
if ($v.ContextMenu)          { Write-Step 'New right-click menu back';              Restore-ContextMenu }
if ($v.FolderTypes)          { Write-Step 'Folder views back to default';           Restore-FolderTypes }
if ($v.Inetpub)              { Write-Step 'Inetpub folder visible again';           Show-Inetpub }
if ($v.Border)               { Write-Step 'Window border back to default';          Restore-Border }
if ($v.Snap)                 { Write-Step 'Snap windows back on';                   Restore-SnapWindows }
if ($v.FastStartup)          { Write-Step 'Fast Startup back on';                   Restore-FastStartup }
if ($v.NumLock)              { Write-Step 'Num Lock off at startup';                Restore-NumLock }
if ($v.BlueScreen)           { Write-Step 'Simple blue screen';                     Restore-BlueScreen }
if ($v.DeviceApps)           { Write-Step 'Device apps download again';             Restore-DeviceApps }
if ($v.Wpbt)                 { Write-Step 'Programs from the firmware allowed';     Restore-Wpbt }
if ($v.SavedAnswers)         { Write-Step 'Forgetting the saved choices';           Remove-SavedAnswers }
if ($v.DNS)                  { Write-Step 'DNS back to automatic';                  Restore-DNS }
if ($v.DeliveryOptimization) { Write-Step 'Update sharing back to default';         Remove-DeliveryOptimizationPolicy }
Write-Host "`nDone." -ForegroundColor Green; Write-Host '  Restart the PC so every change takes effect.' -ForegroundColor DarkGray

#endregion
