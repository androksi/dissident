#Requires -RunAsAdministrator
<#
    Configure-Windows.ps1 — telemetry, junk apps and personalization for Windows 10 and 11

    HOW TO RUN (Windows PowerShell 5.1 as Administrator, NOT PowerShell 7):
        powershell -ExecutionPolicy Bypass -File .\Configure-Windows.ps1

    All questions are asked first (Enter accepts the default, the uppercase letter),
    then everything is applied at once. To use the defaults without any questions:
        powershell -ExecutionPolicy Bypass -File .\Configure-Windows.ps1 -NoPrompt

    If a step fails, the script reports it and moves on to the next one.
    Undo: Revert-Configure-Windows.ps1 (removed apps come back through the Microsoft Store).
    Safe to run more than once. Restart the PC at the end.

    FILE LAYOUT
        1. Helpers ................... registry, prompts, steps
        2. System detection .......... Windows version and available features
        3. Privacy and cleanup ....... telemetry, suggestions, apps, OneDrive, Edge, Windows Security, C:\ root folders, device apps
        4. Personalization ........... theme, taskbar (alignment, search, Task View, pins, battery %), File Explorer (hidden files, folder discovery, Home/Gallery), window border
        5. Everyday use .............. long paths, End task, sudo, Win+V, mouse, Sticky Keys, volume, verbose BSoD
        6. Network ................... DNS with DNS over HTTPS
        7. Questions ................. what to apply
        8. Execution ................. applies the chosen options, in order
#>
param(
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).'
    return
}


#region ==================== 1. HELPERS ====================

# Writes a registry value, creating the key if it doesn't exist.
function Set-Reg {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# Step title in the terminal.
function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Sim / Não" menu (same as Choose). The default comes selected.
# With -NoPrompt, Choose returns the default right away.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Sim', 'Não') $(if ($Default) { 0 } else { 1 })) -eq 0
}

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
            $answer = "$(Read-Host "  Número [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host "  Digite um número de 1 a $($Options.Count)." -ForegroundColor DarkYellow
        }
    }
    if (-not $script:ArrowHintShown) {
        Write-Host '  (use as setas ↑ ↓ e Enter)' -ForegroundColor DarkGray
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

# Reads and validates a typed IP address (IPv4 = InterNetwork, IPv6 = InterNetworkV6).
function Read-IP([string]$Question, [string]$Family, [bool]$Optional) {
    while ($true) {
        $answer = "$(Read-Host "    $Question")".Trim()
        if ($answer -eq '' -and $Optional) { return $null }
        $ip = $null
        # (TryParse accepts short forms like "1.1.1"; for IPv4 all 4 octets are required)
        $formatOk = if ($Family -eq 'InterNetwork') { $answer -match '^\d{1,3}(\.\d{1,3}){3}$' } else { $answer -match ':' }
        if ($formatOk -and [System.Net.IPAddress]::TryParse($answer, [ref]$ip) -and $ip.AddressFamily -eq $Family) { return $ip.ToString() }
        Write-Host "    Endereço inválido. Exemplo: $(if ($Family -eq 'InterNetwork') { '1.1.1.1' } else { '2606:4700:4700::1111' })" -ForegroundColor DarkYellow
    }
}

# Runs a step. If it fails, records the failure and moves on to the next one.
$script:Failures = @()
function Invoke-Step([string]$Title, [scriptblock]$Body) {
    Write-Step $Title
    try { & $Body }
    catch {
        $script:Failures += "${Title}: $($_.Exception.Message)"
        Write-Warning "Esta etapa falhou ($($_.Exception.Message)). Seguindo para a próxima."
    }
}

#endregion


#region ==================== 2. SYSTEM DETECTION ====================

$build      = [Environment]::OSVersion.Version.Build
$isWin11    = $build -ge 22000
$cv         = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osLabel    = "Windows $(if ($isWin11) { '11' } else { '10' }) $($cv.EditionID) (build $build, $($cv.DisplayVersion))"
$hasEndTask = $isWin11 -and $build -ge 22631                      # "End task" on the taskbar: Windows 11 23H2+
$hasSudo    = Test-Path "$env:SystemRoot\System32\sudo.exe"     # Sudo: Windows 11 24H2+

# User folders inside OneDrive? (folder backup on) — then removing OneDrive needs care.
$foldersInOneDrive = @('Desktop', 'MyDocuments', 'MyPictures') |
    ForEach-Object { [Environment]::GetFolderPath($_) } |
    Where-Object { $_ -match '\\OneDrive' }

# Laptop (has a battery)? The battery percentage question only shows up on laptops.
$hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

# Local account (not a Microsoft account)? Sets the default of the Windows Security areas question.
$isLocalAccount = (Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue).PrincipalSource -eq 'Local'

# Base key for Windows policies (used in several sections)
$P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'

#endregion


#region ==================== 3. PRIVACY AND CLEANUP ====================

# --- Telemetry -------------------------------------------------------------

# DiagTrack = "Connected User Experiences and Telemetry" (the service that sends the data).
function Disable-TelemetryServices {
    foreach ($svc in 'DiagTrack', 'dmwappushservice') {
        if (Get-Service $svc -ErrorAction SilentlyContinue) {
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "  desativado: $svc"
        }
    }
}

# Disables (does not delete) the data collection tasks. The Compatibility Appraiser stays ON:
# it is what clears the yearly Windows feature update to install safely.
function Disable-TelemetryTasks {
    $tasks = @(
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
            Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  desativada: $($t[1])"
        }
    }
    # (Older versions of this script disabled the Compatibility Appraiser; here it is re-enabled.)
    foreach ($name in 'Microsoft Compatibility Appraiser', 'Microsoft Compatibility Appraiser Exp') {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName $name -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Disabled') {
            Enable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  religada: $name (necessária para a atualização anual)"
        }
    }
}

# Diagnostics, ads, activity history, search and Delivery Optimization policies.
function Set-TelemetryPolicies {
    # Diagnostic data: on Home/Pro the real minimum is 1 ("Required"); 0 only works on Enterprise/Education.
    Set-Reg "$P\DataCollection" 'AllowTelemetry' 1
    Set-Reg "$P\DataCollection" 'MaxTelemetryAllowed' 1
    Set-Reg "$P\DataCollection" 'DoNotShowFeedbackNotifications' 1
    Set-Reg "$P\DataCollection" 'LimitDiagnosticLogCollection' 1
    Set-Reg "$P\DataCollection" 'LimitDumpCollection' 1
    Set-Reg "$P\DataCollection" 'AllowDeviceNameInTelemetry' 0
    Set-Reg "$P\DataCollection" 'DisableOneSettingsDownloads' 1
    Set-Reg "$P\Windows Error Reporting" 'Disabled' 1                    # error reporting
    Set-Reg "$P\AppCompat" 'DisableInventory' 1                          # compatibility inventory
    Set-Reg "$P\AppCompat" 'AITEnable' 0
    Set-Reg "$P\AdvertisingInfo" 'DisabledByGroupPolicy' 1               # advertising ID
    Set-Reg "$P\System" 'EnableActivityFeed' 0                           # activity history
    Set-Reg "$P\System" 'PublishUserActivities' 0
    Set-Reg "$P\System" 'UploadUserActivities' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0
    Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    # Search: no Bing/web results, no "search highlights", no Cortana
    Set-Reg "$P\Windows Search" 'DisableWebSearch' 1
    Set-Reg "$P\Windows Search" 'ConnectedSearchUseWeb' 0
    Set-Reg "$P\Windows Search" 'EnableDynamicContentInWSB' 0
    Set-Reg "$P\Windows Search" 'AllowCortana' 0
    Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    # Delivery Optimization: updates only from Microsoft, no sharing with other PCs
    Set-Reg "$P\DeliveryOptimization" 'DODownloadMode' 0
    Write-Host '  políticas aplicadas'
}

# Widgets (Windows 11) / News and interests (Windows 10).
# On recent Windows 11 builds Microsoft protects the Widgets key and not even an administrator
# can write to it. In that case, removes the Widgets package ("Windows Web Experience Pack").
function Disable-Widgets {
    if ($isWin11) {
        try {
            if (-not (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh')) { New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Host '  Widgets desativados por política'
        } catch {
            Write-Host '  (o Windows protege a política dos Widgets; removendo o pacote dos Widgets em vez disso)' -ForegroundColor DarkYellow
            $widgets = Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience' -ErrorAction SilentlyContinue
            if (-not $widgets) { Write-Host '  Widgets já não estão instalados' }
            foreach ($pkg in $widgets) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Host '  Widgets removidos'
                } catch {
                    Write-Host "  (não foi possível remover os Widgets: $($_.Exception.Message.Trim()). Desligue em Configurações → Personalização → Barra de tarefas.)" -ForegroundColor DarkYellow
                }
            }
        }
    } else {
        try {
            if (-not (Test-Path "$P\Windows Feeds")) { New-Item "$P\Windows Feeds" -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty "$P\Windows Feeds" -Name 'EnableFeeds' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Host '  Notícias e interesses desativado'
        } catch {
            Write-Host '  (não foi possível desativar Notícias e interesses por política; clique com o direito na barra de tarefas → Notícias e interesses → Desativar)' -ForegroundColor DarkYellow
        }
    }
}

# --- Suggestions and ads ---------------------------------------------------

function Disable-Suggestions {
    $CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled',
                   'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                   'SubscribedContent-310093Enabled',   # welcome experience after updates
                   'SubscribedContent-338388Enabled',   # Start suggestions
                   'SubscribedContent-338389Enabled',   # tips and tricks
                   'SubscribedContent-338393Enabled',   # suggested content in Settings
                   'SubscribedContent-353694Enabled',
                   'SubscribedContent-353696Enabled') {
        Set-Reg $CDM $n 0
    }
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0  # "Let's finish setting up"
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0   # OneDrive ads in File Explorer
    if ($isWin11) {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0   # Start recommendations
    }
    # Blocks reinstalling "consumer apps" (Candy Crush etc.). Officially Enterprise/Education only;
    # on Home/Pro SilentInstalledAppsEnabled=0 above does the job.
    Set-Reg "$P\CloudContent" 'DisableWindowsConsumerFeatures' 1
    Write-Host '  ajustes aplicados'
}

# --- Apps ------------------------------------------------------------------

$JunkApps = @(
    'Clipchamp.Clipchamp',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.BingSearch',
    'Microsoft.Copilot',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',                    # Tips
    'Microsoft.MicrosoftOfficeHub',            # "Microsoft 365" app
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.OutlookForWindows',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.Todos',
    'Microsoft.Windows.DevHome',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.MixedReality.Portal',
    'Microsoft.ZuneVideo',                     # Movies & TV
    'Microsoft.549981C3F5F10',                 # Cortana
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftTeams',
    'MSTeams',
    # More common on Windows 10
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MSPaint',                       # Paint 3D (the regular Paint is a different package and stays)
    'Microsoft.Print3D',
    'Microsoft.SkypeApp',
    'Microsoft.Wallet',
    'Microsoft.Messaging',
    'Microsoft.OneConnect'                     # Mobile Plans
)
$OptionalApps = @(
    'Microsoft.YourPhone',                     # Phone Link
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.WindowsAlarms',                 # Clock/alarms
    'MicrosoftCorporationII.QuickAssist',      # Quick Assist
    'Microsoft.ZuneMusic',                     # Media Player / Groove
    'Microsoft.Office.OneNote'                 # OneNote for Windows 10
)

# Removes the apps for all users plus the provisioned package (so they don't return in new profiles).
# Deprovisions FIRST: Remove-AppxPackage -AllUsers deletes the package files.
# Note: no $p here — PowerShell is case-insensitive and it would collide with $P.
function Remove-Apps([string[]]$List) {
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($app in $List) {
        foreach ($prov in ($provisioned | Where-Object DisplayName -eq $app)) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                Write-Host "  desprovisionado: $($prov.DisplayName)"
            } catch {
                Write-Host "  (não desprovisionado: $($prov.DisplayName) — $($_.Exception.Message.Trim()))" -ForegroundColor DarkYellow
            }
        }
        foreach ($pkg in (Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue)) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Host "  removido: $($pkg.Name)"
            } catch {
                Write-Host "  (não removido: $($pkg.Name) — $($_.Exception.Message.Trim()))" -ForegroundColor DarkYellow
            }
        }
    }
}

# --- OneDrive --------------------------------------------------------------

function Remove-OneDrive {
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") |
             Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($setup) { Start-Process $setup -ArgumentList '/uninstall' -Wait }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements 2>$null | Out-Null
    }
    Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
    Set-Reg "$P\OneDrive" 'DisableFileSyncNGSC' 1
    Write-Host '  OneDrive removido'
}

# --- Edge ------------------------------------------------------------------

function Set-EdgePolicies {
    $E = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Reg $E 'StartupBoostEnabled' 0
    Set-Reg $E 'BackgroundModeEnabled' 0
    Set-Reg $E 'HubsSidebarEnabled' 0
    Set-Reg $E 'Microsoft365CopilotChatIconEnabled' 0
    Set-Reg $E 'CopilotPageContext' 0
    Set-Reg $E 'DiagnosticData' 0
    Set-Reg $E 'PersonalizationReportingEnabled' 0
    Set-Reg $E 'EdgeShoppingAssistantEnabled' 0
    Set-Reg $E 'ShowRecommendationsEnabled' 0
    Set-Reg $E 'SpotlightExperiencesAndRecommendationsEnabled' 0
    Set-Reg $E 'HideFirstRunExperience' 1
    Set-Reg $E 'NewTabPageContentEnabled' 0
    Set-Reg $E 'NewTabPageQuickLinksEnabled' 0
    Set-Reg $E 'NewTabPageHideDefaultTopSites' 1
    Write-Host '  políticas do Edge aplicadas'
}

# --- Windows Security ------------------------------------------------------

function Set-WindowsSecurity {
    # Potentially unwanted app blocking (adware, installers bundling "extras")
    try {
        Set-MpPreference -PUAProtection Enabled -ErrorAction Stop
        Write-Host '  bloqueio de apps indesejados: ligado'
    } catch {
        Write-Host "  (não foi possível ligar o bloqueio de apps indesejados: $($_.Exception.Message.Trim()). Outro antivírus instalado?)" -ForegroundColor DarkYellow
    }
    # Second half of the same setting: "Block downloads" (SmartScreen in Edge). Without it, Windows Security
    # keeps warning that potentially unwanted app blocking is off.
    # (the value is the key's default value; reg.exe /ve writes it reliably)
    reg.exe add 'HKCU\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled' /ve /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE) { Write-Host '  (não foi possível ligar o bloqueio de downloads indesejados)' -ForegroundColor DarkYellow }
    else               { Write-Host '  bloqueio de downloads indesejados: ligado' }

    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    # "Informational" notifications (suggestions, summaries). Important alerts — threat found,
    # protection turned off — keep showing up.
    Set-Reg "$WSC\Notifications" 'DisableEnhancedNotifications' 1
    Write-Host '  avisos informativos: escondidos (alertas importantes continuam)'

    # "Set up OneDrive for ransomware recovery" card: without OneDrive it only causes the
    # exclamation mark on the icon. Hidden only when OneDrive is not installed.
    $hasOneDrive = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
                   (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
    if (-not $hasOneDrive) {
        Set-Reg "$WSC\Virus and threat protection" 'HideRansomwareRecovery' 1
        Write-Host '  aviso de backup do OneDrive: escondido (OneDrive não instalado)'
    } else {
        Write-Host '  aviso de backup do OneDrive: mantido (OneDrive instalado)'
    }
}

# Official option "Download manufacturers' apps and custom icons available for your devices"
# (System Properties → Hardware → Device Installation Settings). Drivers keep coming from Windows Update.
# Note: some vendor installers (e.g. Razer) ship inside the driver package itself and may still appear.
function Disable-DeviceMetadata {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Write-Host '  apps e ícones de fabricante para periféricos: não são mais baixados (drivers continuam)'
}

# Hides the "Account protection" and "Device security" areas of Windows Security (official policy).
# With a local account they only show "Sign in with a Microsoft account" warnings. Nothing is turned off:
# TPM, Secure Boot, Memory integrity and Windows Hello keep working as they are.
function Hide-SecurityAccountAreas {
    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    Set-Reg "$WSC\Account protection" 'UILockdown' 1
    Set-Reg "$WSC\Device security"    'UILockdown' 1
    Write-Host '  "Proteção de contas" e "Segurança do dispositivo": escondidas da Segurança do Windows'
}

# --- System drive root -------------------------------------------------------

# inetpub: created empty by the April 2025 security update (CVE-2025-21204 fix). Deleting it removes
#          that protection, so it is only HIDDEN.
# PerfLogs: Performance Monitor output, empty unless you run a data collector. Safe to delete;
#           Windows recreates it if it ever needs it.
function Clear-SystemDriveRoot {
    $inetpub  = "$env:SystemDrive\inetpub"
    $perfLogs = "$env:SystemDrive\PerfLogs"
    if (Test-Path $inetpub) {
        $folder = Get-Item $inetpub -Force
        $folder.Attributes = $folder.Attributes -bor [IO.FileAttributes]::Hidden   # -bor: safe if already hidden
        Write-Host '  inetpub: escondida (não é apagada: faz parte de uma correção de segurança)'
    }
    if (Test-Path $perfLogs) {
        Remove-Item $perfLogs -Recurse -Force -ErrorAction Stop
        Write-Host '  PerfLogs: apagada'
    }
}

#endregion


#region ==================== 4. PERSONALIZATION ====================

# Whether File Explorer must be restarted at the end so the visual changes show up right away.
$script:RestartExplorer = $false

# Applies the official theme file, just like clicking it in Settings → Personalization → Themes.
#   Windows 11: aero.theme = light, dark.theme = dark.
#   Windows 10: light.theme = light; there is no ready-made dark theme, so it uses "Windows"
#               (aero.theme) and then turns dark mode on.
# The accent color is not changed.
function Set-Theme([bool]$Light) {
    $script:RestartExplorer = $true
    $dir = "$env:WINDIR\Resources\Themes"
    $theme = if ($isWin11) { if ($Light) { "$dir\aero.theme" } else { "$dir\dark.theme" } }
             else          { if ($Light) { "$dir\light.theme" } else { "$dir\aero.theme" } }
    if (-not (Test-Path $theme)) { $theme = "$dir\aero.theme" }
    if (-not (Test-Path $theme)) { throw "arquivo de tema não encontrado: $theme" }

    $Themes = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes'
    Start-Process $theme
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $current = (Get-ItemProperty $Themes -Name CurrentTheme -ErrorAction SilentlyContinue).CurrentTheme
    } until (($current -and $current -ieq $theme) -or (Get-Date) -gt $deadline)
    Start-Sleep -Seconds 3                                                        # let Windows finish applying
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force # close the Settings window
    # (if a Control Panel window opens, it closes when File Explorer restarts at the end)

    # Make sure the system and app light/dark mode match
    $mode = if ($Light) { 1 } else { 0 }
    Set-Reg "$Themes\Personalize" 'SystemUsesLightTheme' $mode
    Set-Reg "$Themes\Personalize" 'AppsUseLightTheme'    $mode
    Set-ThemeWallpaper $theme
    if ($current -ine $theme) { Write-Warning 'Não deu para confirmar o tema. Confira em Configurações → Personalização → Temas.' }
    else { Write-Host "  tema aplicado: $(Split-Path $theme -Leaf)" }
}

# On Windows 11 the desktop background can stay on "Windows Spotlight" even after applying a theme
# (seen on a fresh install). So the theme's own wallpaper is set explicitly as a "Picture" background.
function Set-ThemeWallpaper([string]$ThemeFile) {
    # Wallpaper path from the .theme file, e.g. Wallpaper=%SystemRoot%\web\wallpaper\Windows\img19.jpg
    $line = Select-String -Path $ThemeFile -Pattern '^\s*Wallpaper\s*=' | Select-Object -First 1
    if (-not $line) { return }
    $wallpaper = [Environment]::ExpandEnvironmentVariables(($line.Line -split '=', 2)[1].Trim())
    if (-not (Test-Path $wallpaper)) { return }

    if ($isWin11) {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings' 'EnabledState' 0   # Spotlight off
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' 'BackgroundType' 0      # 0 = Picture
    }
    if (-not ('CfgWin.Wallpaper' -as [type])) {
        Add-Type -Namespace CfgWin -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
    }
    # SPI_SETDESKWALLPAPER = 0x14; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    if ([CfgWin.Wallpaper]::SystemParametersInfo(0x14, 0, $wallpaper, 3)) {
        Write-Host "  papel de parede do tema: $(Split-Path $wallpaper -Leaf) (Destaques do Windows desligado)"
    } else {
        Write-Host '  (não foi possível trocar o papel de parede; escolha em Configurações → Personalização → Tela de fundo)' -ForegroundColor DarkYellow
    }
}

# Visible file extensions, frequent folders and recent files in File Explorer.
function Set-Explorer([bool]$ShowExtensions, [bool]$HideFrequent, [bool]$HideRecent) {
    $Exp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    if ($ShowExtensions) { Set-Reg "$Exp\Advanced" 'HideFileExt' 0; Write-Host '  extensões visíveis' }
    if ($HideFrequent)   { Set-Reg $Exp 'ShowFrequent' 0;          Write-Host '  pastas frequentes escondidas (as que você fixou continuam)' }
    if ($HideRecent) {
        Set-Reg $Exp 'ShowRecent' 0
        if ($isWin11) { Set-Reg $Exp 'ShowRecommendations' 0 }
        Write-Host '  arquivos recentes escondidos'
    }
    $script:RestartExplorer = $true
}

# Removes "Home" and "Gallery" from the File Explorer sidebar (Windows 11) and makes File Explorer
# open in "This PC" (otherwise it would keep opening in the hidden Home). Pinned folders are untouched.
function Hide-HomeAndGallery {
    $CLSID = 'HKCU:\SOFTWARE\Classes\CLSID'
    Set-Reg "$CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" 'System.IsPinnedToNameSpaceTree' 0   # Home
    Set-Reg "$CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" 'System.IsPinnedToNameSpaceTree' 0   # Gallery
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1      # open in This PC
    Write-Host '  Início e Galeria removidos da barra lateral; o Explorador abre em "Este Computador"'
    $script:RestartExplorer = $true
}

# Shows hidden files and folders (.git, AppData...). Protected system files stay hidden.
function Show-HiddenFiles {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
    Write-Host '  arquivos e pastas ocultos: visíveis (arquivos protegidos do sistema continuam escondidos)'
    $script:RestartExplorer = $true
}

# Stops File Explorer from "sniffing" each folder's content to pick a template (Music, Pictures...),
# which makes folders with thousands of files slow to open. Every folder uses the generic template.
# The saved per-folder views (Bags/BagMRU) must be cleared for this to apply, so custom views are reset.
function Disable-FolderDiscovery {
    $shell = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell'
    Remove-Item "$shell\Bags", "$shell\BagMRU" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Reg "$shell\Bags\AllFolders\Shell" 'FolderType' 'NotSpecified' 'String'
    Write-Host '  descoberta automática de tipo de pasta: desligada (visualizações de pasta zeradas)'
    $script:RestartExplorer = $true
}

# Battery percentage next to the taskbar battery icon (Windows 11 24H2/25H2, builds from late 2025 on).
# On older builds the value is simply ignored.
function Enable-BatteryPercentage {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IsBatteryPercentageEnabled' 1
    Write-Host '  porcentagem da bateria na barra de tarefas: ligada (se a sua versão do Windows tiver a opção)'
    $script:RestartExplorer = $true
}

# Invisible area around windows that "grabs" the mouse for resizing: from ~5 px down to ~1 px.
# Windows default: -60. Takes effect after signing out and back in.
function Set-ThinBorder {
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'PaddedBorderWidth' '0' 'String'
    Write-Host '  borda afinada (vale depois de sair da conta e entrar de novo)'
}

# Taskbar icon alignment (Windows 11 only): TaskbarAl 0 = left, 1 = center (Windows default).
function Set-TaskbarAlignment([bool]$Left) {
    $value = if ($Left) { 0 } else { 1 }
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' $value
    Write-Host "  ícones da barra de tarefas: $(if ($Left) { 'à esquerda' } else { 'ao centro' })"
    $script:RestartExplorer = $true
}

# Taskbar search (Windows 10 and 11): SearchboxTaskbarMode 0 = hidden, 1 = icon only, 2 = search box.
function Set-TaskbarSearch([int]$Mode) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' $Mode
    Write-Host "  pesquisa na barra de tarefas: $(@('oculta', 'só o ícone', 'caixa de pesquisa')[$Mode])"
    $script:RestartExplorer = $true
}

# "Task View" button on the taskbar (Windows 10 and 11): ShowTaskViewButton 0 = hidden, 1 = visible.
# Win+Tab keeps working either way.
function Set-TaskViewButton([bool]$Show) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' ([int]$Show)
    Write-Host "  botão Visão de Tarefas: $(if ($Show) { 'visível' } else { 'oculto (Win+Tab continua funcionando)' })"
    $script:RestartExplorer = $true
}

# Unpins every app from the taskbar (Edge, Store, File Explorer and any you pinned yourself).
# The pin list lives in the Taskband key plus the shortcuts in the "User Pinned\TaskBar" folder.
# Apps are not uninstalled; pin them again with right-click → "Fixar na barra de tarefas".
function Clear-TaskbarPins {
    Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host '  ícones fixados removidos da barra de tarefas'
    $script:RestartExplorer = $true
}

# Notifies apps of the theme change and restarts File Explorer (Windows reopens it by itself).
function Restart-Explorer {
    if (-not ('CfgWin.Broadcast' -as [type])) {
        Add-Type -Namespace CfgWin -Name Broadcast -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    foreach ($area in 'ImmersiveColorSet', 'WindowsThemeElement') {
        [void][CfgWin.Broadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, $area, 2, 3000, [ref]$result)
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Host '  Explorer reiniciado'
}

#endregion


#region ==================== 5. EVERYDAY USE ====================

function Enable-LongPaths {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
    Write-Host '  caminhos longos: permitidos'
}

function Enable-EndTask {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
    Write-Host '  "Finalizar tarefa" na barra de tarefas: ligado'
    $script:RestartExplorer = $true
}

# "Inline" mode: the command runs in the same terminal window, like on Linux.
function Enable-Sudo {
    & "$env:SystemRoot\System32\sudo.exe" config --enable normal | Out-Null
    Write-Host '  sudo: ativado (modo em linha)'
}

function Enable-ClipboardHistory {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Clipboard' 'EnableClipboardHistory' 1
    Write-Host '  histórico da área de transferência (Win+V): ligado (só neste PC, sem sincronizar)'
}

function Disable-MouseAcceleration {
    $mouse = 'HKCU:\Control Panel\Mouse'
    Set-Reg $mouse 'MouseSpeed'      '0' 'String'
    Set-Reg $mouse 'MouseThreshold1' '0' 'String'
    Set-Reg $mouse 'MouseThreshold2' '0' 'String'
    Write-Host '  precisão do ponteiro aprimorada: desligada (vale depois de sair da conta e entrar de novo)'
}

# 506 = Sticky Keys off and WITHOUT the 5x Shift shortcut (Windows default is 510).
# The feature is still available in Settings → Accessibility → Keyboard.
function Disable-StickyKeysShortcut {
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Write-Host '  atalho das Teclas de Aderência (5x Shift): desligado'
}

# Blue screen (BSoD) also shows the technical parameters of the error, which helps to look up the cause.
function Enable-VerboseBsod {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 1
    Write-Host '  tela azul detalhada: ligada (só aparece se o PC travar)'
}

# Sets the volume of the default playback device (speakers/headphones in use) through the Windows
# Core Audio API. Each device keeps its own volume, so a device plugged in later keeps its own level.
function Set-MaxVolume {
    if (-not ('CfgWin.Audio' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CfgWin {
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out uint count);
        int SetMasterVolumeLevel(float levelDb, ref Guid context);
        int SetMasterVolumeLevelScalar(float level, ref Guid context);
        int GetMasterVolumeLevel(out float levelDb);
        int GetMasterVolumeLevelScalar(out float level);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object target);
    }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumerator { }

    public static class Audio {
        static IAudioEndpointVolume Endpoint() {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));   // eRender, eMultimedia
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object volume;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out volume));  // CLSCTX_ALL
            return (IAudioEndpointVolume)volume;
        }
        public static void SetVolume(float level) {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(level, ref context));
        }
        public static float GetVolume() {
            float level;
            Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out level));
            return level;
        }
    }
}
'@
    }
    [CfgWin.Audio]::SetVolume(1.0)
    Write-Host "  volume do Windows: $([math]::Round([CfgWin.Audio]::GetVolume() * 100))%"
}

#endregion


#region ==================== 6. NETWORK ====================

# Sets DNS on every physical adapter (Wi-Fi and Ethernet, even disconnected ones; skips VPNs and
# virtual adapters). On Windows 11 turns on "On (automatic template)" for each server:
# DohFlags = 1 per adapter — Windows cmdlets don't write this; it is the same value the Settings page uses.
function Set-DNS([string[]]$V4, [string[]]$V6) {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
    $all = @($V4) + @($V6)
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled')
    if (-not $adapters) { throw 'nenhum adaptador de rede físico encontrado' }
    foreach ($adapter in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $all -ErrorAction Stop
        if ($isWin11) {
            $doh = "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings"
            Remove-Item "$doh\Doh", "$doh\Doh6" -Recurse -Force -ErrorAction SilentlyContinue   # clear old servers
            foreach ($ip in $V4) { Set-Reg "$doh\Doh\$ip"  'DohFlags' 1 'QWord' }
            foreach ($ip in $V6) { Set-Reg "$doh\Doh6\$ip" 'DohFlags' 1 'QWord' }
        }
        Write-Host "  $($adapter.Name): $($all -join ', ')$(if ($isWin11) { ' (criptografado, modelo automático)' })"
    }
    Clear-DnsClientCache
    if (-not $V6) { Write-Host '  IPv6: mantido automático (do roteador).' -ForegroundColor DarkGray }
}

#endregion


#region ==================== 7. QUESTIONS ====================

Write-Host "`nConfigure-Windows — $osLabel" -ForegroundColor Green
if ($cv.EditionID -match 'Core') {
    Write-Host '  Windows Home: algumas políticas valem só no Pro; o resto funciona normalmente.' -ForegroundColor DarkYellow
}
if (-not $NoPrompt) { Write-Host '  Escolha com as setas e Enter. A resposta padrão já vem selecionada.' }

$opt = [ordered]@{}

# --- Privacy and cleanup
Write-Host "`n  Privacidade e limpeza" -ForegroundColor Cyan
$opt.Telemetry    = Ask 'Desativar telemetria (serviço, tarefas e políticas)?' $true
$opt.Suggestions  = Ask 'Desativar sugestões, anúncios e instalação silenciosa de apps?' $true
$opt.Apps         = Ask 'Remover apps inúteis (Clipchamp, Bing, Solitaire, Teams, Outlook novo...)?' $true
$opt.OptionalApps = if ($opt.Apps) { Ask 'Remover também Vincular ao Celular, Sticky Notes, Gravador, Relógio, Assistência Rápida, Media Player e OneNote?' $false } else { $false }
if ($foldersInOneDrive) {
    Write-Host "  ATENÇÃO: estas pastas estão dentro do OneDrive: $($foldersInOneDrive -join ', ')" -ForegroundColor Yellow
    Write-Host '  Desligue o backup de pastas no OneDrive antes de removê-lo.' -ForegroundColor Yellow
}
$opt.OneDrive     = Ask 'Remover o OneDrive?' (-not $foldersInOneDrive)
$opt.Edge         = Ask 'Aplicar políticas do Edge (sem telemetria, segundo plano, barra lateral, compras)?' $true
$opt.Security     = Ask 'Segurança do Windows: bloquear apps indesejados e esconder avisos sem importância?' $true
$opt.RootFolders  = Ask 'Esconder a pasta inetpub e apagar a PerfLogs (na raiz do C:)?' $true
$opt.NoDeviceApps = Ask 'Não baixar apps e ícones de fabricante ao conectar periféricos (Razer, Logitech...; drivers continuam vindo)?' $false
$opt.HideAreas    = Ask 'Esconder "Proteção de contas" e "Segurança do dispositivo" da Segurança do Windows (só avisam para entrar com conta Microsoft)?' $isLocalAccount

# --- Personalization
Write-Host "`n  Personalização (só para o seu usuário)" -ForegroundColor Cyan
$themeNames = @('Manter como está', 'Windows (claro)', 'Windows (escuro)')
$themeIds   = @('Keep', 'Light', 'Dark')
$opt.Theme          = $themeIds[(Choose 'Tema do Windows:' $themeNames 1)]
$taskbarNames = @('Manter como está', 'Ao centro', 'À esquerda')
$taskbarIds   = @('Keep', 'Center', 'Left')
$opt.Taskbar        = if ($isWin11) { $taskbarIds[(Choose 'Ícones da barra de tarefas:' $taskbarNames 0)] } else { 'Keep' }
$searchNames = @('Manter como está', 'Oculta', 'Só o ícone', 'Caixa de pesquisa')
$searchIds   = @('Keep', 'Hidden', 'Icon', 'Box')
$opt.Search         = $searchIds[(Choose 'Pesquisa na barra de tarefas:' $searchNames 0)]
$taskViewNames = @('Manter como está', 'Mostrar', 'Ocultar')
$taskViewIds   = @('Keep', 'Show', 'Hide')
$opt.TaskView       = $taskViewIds[(Choose 'Botão "Visão de Tarefas" na barra de tarefas:' $taskViewNames 0)]
$opt.ClearPins      = Ask 'Remover os ícones fixados na barra de tarefas (Edge, Store, Explorador e os que você fixou)?' $false
$opt.BatteryPercent = if ($isWin11 -and $hasBattery) { Ask 'Mostrar a porcentagem da bateria na barra de tarefas?' $false } else { $false }
$opt.ShowExtensions = Ask 'Mostrar as extensões dos arquivos (.txt, .exe...)?' $true
$opt.HideFrequent   = Ask 'Esconder as pastas frequentes do Acesso rápido?' $true
$opt.HideRecent     = Ask 'Esconder também os arquivos recentes no Explorador?' $false
$opt.ShowHidden     = Ask 'Mostrar arquivos e pastas ocultos no Explorador (.git, AppData...)?' $false
$opt.NoFolderSniff  = Ask 'Desligar a descoberta automática de tipo de pasta (pastas grandes abrem mais rápido; zera as visualizações personalizadas)?' $true
$opt.HideHomeGallery = if ($isWin11) { Ask 'Remover "Início" e "Galeria" da barra lateral do Explorador (ele passa a abrir em "Este Computador")?' $false } else { $false }
$opt.ThinBorder     = Ask 'Afinar a borda de redimensionamento das janelas (evita redimensionar sem querer)?' $false

# --- Everyday use
Write-Host "`n  Uso no dia a dia" -ForegroundColor Cyan
$opt.LongPaths        = Ask 'Permitir caminhos longos (mais de 260 caracteres; evita erros com node_modules)?' $true
$opt.EndTask          = if ($hasEndTask) { Ask 'Mostrar "Finalizar tarefa" ao clicar com o direito num app na barra de tarefas?' $true } else { $false }
$opt.Sudo             = if ($hasSudo)    { Ask 'Ativar o sudo no terminal (rodar comandos como admin sem abrir outra janela)?' $false } else { $false }
$opt.ClipboardHistory = Ask 'Ativar o histórico da área de transferência (Win+V)?' $true
$opt.NoMouseAccel     = Ask 'Desligar a "precisão do ponteiro aprimorada" (aceleração do mouse)?' $false
$opt.NoStickyKeys     = Ask 'Desligar o atalho das Teclas de Aderência (aviso ao apertar Shift 5 vezes)?' $true
$opt.MaxVolume        = Ask 'Deixar o volume do Windows em 100% (no alto-falante/fone em uso agora)?' $true
$opt.VerboseBsod      = Ask 'Mostrar detalhes técnicos na tela azul, se o PC travar (ajuda a descobrir a causa)?' $true

# --- Network
Write-Host "`n  Rede" -ForegroundColor Cyan
$dnsV4 = @(); $dnsV6 = @()
if (Ask 'Configurar o DNS manualmente (com DNS por HTTPS, modelo automático)?' $false) {
    if (-not $isWin11) {
        Write-Host '    Aviso: o Windows 10 não tem DNS por HTTPS no sistema. O DNS será definido, mas sem criptografia.' -ForegroundColor Yellow
    }
    $dnsV4 += Read-IP 'DNS preferencial (IPv4):' 'InterNetwork' $false
    $altV4 = Read-IP 'DNS alternativo (IPv4, Enter para pular):' 'InterNetwork' $true
    if ($altV4) { $dnsV4 += $altV4 }
    Write-Host '    IPv6: se ficar em branco, o DNS IPv6 continua o do roteador, sem criptografia.' -ForegroundColor DarkGray
    $prefV6 = Read-IP 'DNS preferencial (IPv6, Enter para pular):' 'InterNetworkV6' $true
    if ($prefV6) {
        $dnsV6 += $prefV6
        $altV6 = Read-IP 'DNS alternativo (IPv6, Enter para pular):' 'InterNetworkV6' $true
        if ($altV6) { $dnsV6 += $altV6 }
    }
    # The "automatic template" only exists for servers Windows knows (Cloudflare, Google, Quad9...)
    if ($isWin11) {
        foreach ($ip in ($dnsV4 + $dnsV6)) {
            if (-not (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue)) {
                Write-Host "    Aviso: o Windows não tem modelo automático para $ip. Esse servidor ficará SEM criptografia." -ForegroundColor Yellow
            }
        }
    }
}
$opt.DNS = if ($dnsV4) { ($dnsV4 + $dnsV6) -join ', ' } else { 'manter' }

# --- Summary and confirmation
# Labels shown on screen for each option (in Portuguese, like the questions).
$labels = @{
    Telemetry = 'Telemetria'; Suggestions = 'Sugestões'; Apps = 'Apps'; OptionalApps = 'Apps opcionais'
    OneDrive = 'OneDrive'; Edge = 'Edge'; Security = 'Segurança'; HideAreas = 'Esconder áreas'; RootFolders = 'Pastas do C:'; Theme = 'Tema'; Taskbar = 'Barra de tarefas'
    Search = 'Pesquisa'; TaskView = 'Visão de Tarefas'; ClearPins = 'Sem fixados'
    ShowExtensions = 'Extensões'; HideFrequent = 'Sem frequentes'; HideRecent = 'Sem recentes'; HideHomeGallery = 'Sem Início/Galeria'; ThinBorder = 'Borda fina'
    LongPaths = 'Caminhos longos'; EndTask = 'Finalizar tarefa'; Sudo = 'Sudo'; ClipboardHistory = 'Histórico Win+V'
    NoMouseAccel = 'Sem aceleração'; NoStickyKeys = 'Sem aderência'; MaxVolume = 'Volume 100%'; DNS = 'DNS'
    NoDeviceApps = 'Sem apps de periféricos'; BatteryPercent = 'Bateria em %'; ShowHidden = 'Arquivos ocultos'
    NoFolderSniff = 'Sem descoberta pasta'; VerboseBsod = 'Tela azul detalhada'
}
if (-not $NoPrompt) {
    Write-Host "`n  Resumo:" -ForegroundColor Cyan
    foreach ($key in $opt.Keys) {
        $value = $opt[$key]
        $text = if ($value -is [bool]) { if ($value) { 'sim' } else { 'não' } }
                elseif ($key -eq 'Theme')   { $themeNames[[array]::IndexOf($themeIds, $value)] }
                elseif ($key -eq 'Taskbar') { $taskbarNames[[array]::IndexOf($taskbarIds, $value)] }
                elseif ($key -eq 'Search')  { $searchNames[[array]::IndexOf($searchIds, $value)] }
                elseif ($key -eq 'TaskView') { $taskViewNames[[array]::IndexOf($taskViewIds, $value)] }
                else { $value }
        Write-Host ("    {0,-24} {1}" -f $labels[$key], $text)
    }
    if (-not (Ask 'Aplicar agora?' $true)) { Write-Host 'Nada foi alterado.'; return }
}

#endregion


#region ==================== 8. EXECUTION ====================

# --- Restore point (if there is already one from the last 24 h, Windows just warns and moves on)
Write-Step 'Criando ponto de restauração'
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description 'Antes do Configure-Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
} catch {
    Write-Warning "Não foi possível criar o ponto de restauração: $($_.Exception.Message)"
    if (-not (Ask 'Continuar mesmo assim?' $false)) { Write-Host 'Nada foi alterado.'; return }
}

# --- Privacy and cleanup
if ($opt.Telemetry) {
    Invoke-Step 'Telemetria: serviços'                                { Disable-TelemetryServices }
    Invoke-Step 'Telemetria: tarefas agendadas (desativa, não apaga)' { Disable-TelemetryTasks }
    Invoke-Step 'Telemetria: políticas'                               { Set-TelemetryPolicies; Disable-Widgets }
}
if ($opt.Suggestions) { Invoke-Step 'Sugestões, anúncios e instalação silenciosa de apps' { Disable-Suggestions } }
if ($opt.Apps) {
    $appList = if ($opt.OptionalApps) { $JunkApps + $OptionalApps } else { $JunkApps }
    Invoke-Step 'Removendo apps (todos os usuários + pacote provisionado)' { Remove-Apps $appList }
}
if ($opt.OneDrive) { Invoke-Step 'Removendo OneDrive'                                          { Remove-OneDrive } }
if ($opt.Edge)     { Invoke-Step 'Edge: sem telemetria, segundo plano, barra lateral e compras' { Set-EdgePolicies } }
if ($opt.Security) { Invoke-Step 'Segurança do Windows'                                        { Set-WindowsSecurity } }
if ($opt.RootFolders) { Invoke-Step 'Pastas na raiz do disco (inetpub e PerfLogs)'          { Clear-SystemDriveRoot } }
if ($opt.NoDeviceApps) { Invoke-Step 'Apps de fabricante para periféricos'                   { Disable-DeviceMetadata } }
if ($opt.HideAreas) { Invoke-Step 'Segurança do Windows: escondendo áreas de conta Microsoft'  { Hide-SecurityAccountAreas } }

# --- Personalization
if ($opt.Theme -ne 'Keep') {
    Invoke-Step "Tema $($themeNames[[array]::IndexOf($themeIds, $opt.Theme)])" { Set-Theme ($opt.Theme -eq 'Light') }
}
if ($opt.Taskbar -ne 'Keep') {
    Invoke-Step 'Alinhamento da barra de tarefas' { Set-TaskbarAlignment ($opt.Taskbar -eq 'Left') }
}
if ($opt.Search -ne 'Keep') {
    # Index in $searchIds minus 1 = SearchboxTaskbarMode value (Hidden = 0, Icon = 1, Box = 2)
    Invoke-Step 'Pesquisa na barra de tarefas' { Set-TaskbarSearch ([array]::IndexOf($searchIds, $opt.Search) - 1) }
}
if ($opt.TaskView -ne 'Keep') {
    Invoke-Step 'Botão Visão de Tarefas' { Set-TaskViewButton ($opt.TaskView -eq 'Show') }
}
if ($opt.ClearPins) { Invoke-Step 'Removendo ícones fixados da barra de tarefas' { Clear-TaskbarPins } }
if ($opt.BatteryPercent) { Invoke-Step 'Porcentagem da bateria' { Enable-BatteryPercentage } }
if ($opt.ShowExtensions -or $opt.HideFrequent -or $opt.HideRecent) {
    Invoke-Step 'Explorador de Arquivos' { Set-Explorer $opt.ShowExtensions $opt.HideFrequent $opt.HideRecent }
}
if ($opt.ShowHidden)    { Invoke-Step 'Explorador: arquivos ocultos'               { Show-HiddenFiles } }
if ($opt.NoFolderSniff) { Invoke-Step 'Explorador: descoberta automática de pasta' { Disable-FolderDiscovery } }
if ($opt.HideHomeGallery) { Invoke-Step 'Explorador: removendo Início e Galeria' { Hide-HomeAndGallery } }
if ($opt.ThinBorder) { Invoke-Step 'Borda de redimensionamento das janelas' { Set-ThinBorder } }

# --- Everyday use
if ($opt.LongPaths -or $opt.EndTask -or $opt.Sudo -or $opt.ClipboardHistory -or $opt.NoMouseAccel -or $opt.NoStickyKeys) {
    Invoke-Step 'Ajustes de uso no dia a dia' {
        if ($opt.LongPaths)        { Enable-LongPaths }
        if ($opt.EndTask)          { Enable-EndTask }
        if ($opt.Sudo)             { Enable-Sudo }
        if ($opt.ClipboardHistory) { Enable-ClipboardHistory }
        if ($opt.NoMouseAccel)     { Disable-MouseAcceleration }
        if ($opt.NoStickyKeys)     { Disable-StickyKeysShortcut }
    }
}
if ($opt.MaxVolume) { Invoke-Step 'Volume do Windows em 100%' { Set-MaxVolume } }
if ($opt.VerboseBsod) { Invoke-Step 'Tela azul detalhada' { Enable-VerboseBsod } }

# --- Network
if ($dnsV4) { Invoke-Step "DNS: $($opt.DNS)" { Set-DNS $dnsV4 $dnsV6 } }

# --- Apply visuals right away (no need to sign out)
if ($script:RestartExplorer) { Invoke-Step 'Aplicando visual sem precisar sair da conta' { Restart-Explorer } }

# --- Done
if ($script:Failures.Count) {
    Write-Host "`nEtapas que falharam (o resto foi aplicado):" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Step 'Concluído. Reinicie o computador.'
Write-Host 'Para desfazer: Revert-Configure-Windows.ps1' -ForegroundColor Green

#endregion
