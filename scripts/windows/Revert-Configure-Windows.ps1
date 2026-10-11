#Requires -RunAsAdministrator
<#
    Revert-Configure-Windows.ps1 — undoes what Configure-Windows.ps1 changed

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Revert-Configure-Windows.ps1

    What does NOT come back on its own:
        - removed apps .............. reinstall from the Microsoft Store
        - OneDrive .................. winget install Microsoft.OneDrive
        - theme, taskbar alignment, search and Task View, extensions, folders ... through Windows Settings
        - taskbar pins .............. right-click the app → "Fixar na barra de tarefas"
        - volume .................... on the taskbar volume icon
        - hidden files, battery % ... through Windows Settings
        - unwanted app and download blocking (Windows Security) stays on: it is only protection
    Restart the PC at the end.

    FILE LAYOUT
        1. Helpers
        2. Revert actions (one function per subject)
        3. Execution
#>

$ErrorActionPreference = 'Continue'
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'


#region ==================== 1. HELPERS ====================

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
        Write-Host '  borda restaurada (vale depois de sair da conta e entrar de novo)'
    }
}

# Automatic DNS (from the router) and no DNS over HTTPS, on every physical adapter.
function Restore-DNS {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        Remove-Item "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  $($adapter.Name): automático"
    }
    Clear-DnsClientCache
}

# Brings "Home" and "Gallery" back to the File Explorer sidebar and makes it open in Home again.
function Restore-HomeAndGallery {
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKCU:\SOFTWARE\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo'
    Write-Host '  Início e Galeria de volta (aparecem depois de reiniciar)'
}

# Folder type discovery, manufacturer apps for devices and verbose blue screen back to the Windows default.
function Restore-ExplorerAndDeviceDefaults {
    Remove-Item 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork'
    Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters'
}

# Shows the inetpub folder again (PerfLogs is not recreated: Windows does it when it needs the folder).
function Show-Inetpub {
    $inetpub = "$env:SystemDrive\inetpub"
    if (Test-Path $inetpub) {
        $folder = Get-Item $inetpub -Force
        $folder.Attributes = $folder.Attributes -band -bnot [IO.FileAttributes]::Hidden
        Write-Host '  inetpub: visível de novo'
    }
}

function Remove-EdgePolicies {
    Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Recurse -Force -ErrorAction SilentlyContinue
}

# Answers saved by Configure-Windows for -Check.
function Remove-SavedAnswers {
    Remove-Item (Join-Path $env:ProgramData 'TidyWin') -Recurse -Force -ErrorAction SilentlyContinue
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Step 'Serviços de telemetria de volta ao padrão'; Restore-TelemetryServices
Write-Step 'Reativando tarefas agendadas';             Restore-TelemetryTasks
Write-Step 'Removendo políticas';                      Remove-WindowsPolicies
Write-Step 'Sugestões do Windows de volta ao padrão';  Restore-Suggestions
Write-Step 'Borda das janelas de volta ao padrão';     Restore-Border
Write-Step 'DNS de volta ao automático (do roteador)'; Restore-DNS
Write-Step 'Início e Galeria de volta no Explorador';  Restore-HomeAndGallery
Write-Step 'Pastas, periféricos e tela azul no padrão'; Restore-ExplorerAndDeviceDefaults
Write-Step 'Pasta inetpub visível de novo';            Show-Inetpub
Write-Step 'Removendo políticas do Edge';              Remove-EdgePolicies
Write-Step 'Apagando as respostas salvas (TidyWin)';  Remove-SavedAnswers
Write-Step 'Concluído. Reinicie o computador.'

#endregion
