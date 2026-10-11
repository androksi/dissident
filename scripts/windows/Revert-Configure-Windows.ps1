#Requires -RunAsAdministrator
<#
    Revert-Configure-Windows.ps1 — undoes what Configure-Windows.ps1 changed

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Revert-Configure-Windows.ps1
    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

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
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host "  $(T 'Number' 'Número') [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host (T "  Type a number from 1 to $($Options.Count)." "  Digite um número de 1 a $($Options.Count).") -ForegroundColor DarkYellow
        }
    }
    if (-not $script:ArrowHintShown) {
        Write-Host (T '  (use the arrows ↑ ↓ and Enter)' '  (use as setas ↑ ↓ e Enter)') -ForegroundColor DarkGray
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

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
        Write-Host (T '  border restored (takes effect after signing out and back in)' '  borda restaurada (vale depois de sair da conta e entrar de novo)')
    }
}

# Automatic DNS (from the router) and no DNS over HTTPS, on every physical adapter.
function Restore-DNS {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        Remove-Item "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host (T "  $($adapter.Name): automatic" "  $($adapter.Name): automático")
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
    Write-Host (T '  Home, Gallery, Music in Quick access and the new right-click menu are back (some show up after restarting)' '  Início, Galeria, Músicas no Acesso rápido e o menu novo do botão direito de volta (alguns aparecem depois de reiniciar)')
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
        Write-Host (T '  inetpub: visible again' '  inetpub: visível de novo')
    }
}

function Remove-EdgePolicies {
    Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Recurse -Force -ErrorAction SilentlyContinue
    # Desktop shortcut policy (the shortcut itself is not recreated; Edge adds it again on its next update)
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' @('CreateDesktopShortcutDefault', 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}')
}

# Answers saved by Configure-Windows for -Check.
function Remove-SavedAnswers {
    Remove-Item (Join-Path $env:ProgramData 'TidyWin') -Recurse -Force -ErrorAction SilentlyContinue
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Step (T 'Telemetry services back to default' 'Serviços de telemetria de volta ao padrão'); Restore-TelemetryServices
Write-Step (T 'Re-enabling scheduled tasks' 'Reativando tarefas agendadas'); Restore-TelemetryTasks
Write-Step (T 'Removing policies' 'Removendo políticas'); Remove-WindowsPolicies
Write-Step (T 'Windows suggestions back to default' 'Sugestões do Windows de volta ao padrão'); Restore-Suggestions
Write-Step (T 'Window border back to default' 'Borda das janelas de volta ao padrão'); Restore-Border
Write-Step (T 'DNS back to automatic (from the router)' 'DNS de volta ao automático (do roteador)'); Restore-DNS
Write-Step (T 'Home and Gallery back in File Explorer' 'Início e Galeria de volta no Explorador'); Restore-HomeAndGallery
Write-Step (T 'Folders, devices, startup and blue screen back to default' 'Pastas, periféricos, inicialização e tela azul no padrão'); Restore-ExplorerAndDeviceDefaults
Write-Step (T 'inetpub folder visible again' 'Pasta inetpub visível de novo'); Show-Inetpub
Write-Step (T 'Removing Edge policies' 'Removendo políticas do Edge'); Remove-EdgePolicies
Write-Step (T 'Deleting the saved answers (TidyWin)' 'Apagando as respostas salvas (TidyWin)'); Remove-SavedAnswers
Write-Step (T 'Done. Restart the computer.' 'Concluído. Reinicie o computador.')

#endregion
