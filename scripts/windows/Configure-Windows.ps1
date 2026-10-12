#Requires -RunAsAdministrator
<#
    Configure-Windows.ps1 — telemetry, junk apps and personalization for Windows 10 and 11

    HOW TO RUN (Windows PowerShell 5.1 as Administrator, NOT PowerShell 7):
        powershell -ExecutionPolicy Bypass -File .\Configure-Windows.ps1

    All questions are asked first (arrow-key menus; the default comes selected),
    then everything is applied at once. To use the defaults without any questions:
        powershell -ExecutionPolicy Bypass -File .\Configure-Windows.ps1 -NoPrompt

    Check later (e.g. after a big Windows update) whether anything came back, and reapply it:
        powershell -ExecutionPolicy Bypass -File .\Configure-Windows.ps1 -Check
    The answers are saved in %ProgramData%\TidyWin\windows.json for that (Revert deletes it).

    If a step fails, the script reports it and moves on to the next one.
    Undo: Revert-Configure-Windows.ps1 (removed apps come back through the Microsoft Store).
    Safe to run more than once. Restart the PC at the end.
    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

    FILE LAYOUT
        1. Helpers ................... registry, prompts, steps
        2. System detection .......... Windows version and available features
        3. Privacy and cleanup ....... telemetry, suggestions, apps, OneDrive, Edge, Windows Security, C:\ root folders, device apps
        4. Personalization ........... theme, taskbar (alignment, search, Task View, pins, battery %), File Explorer (hidden files, folder discovery, Home/Gallery), window border
        5. Everyday use .............. long paths, End task, sudo, Win+V, mouse, Sticky Keys, volume, verbose BSoD
        6. Network ................... DNS with DNS over HTTPS
        7. Check ..................... -Check: compares the PC with the saved answers
        8. Questions ................. what to apply
        9. Execution ................. applies the chosen options, in order
#>
param(
    [switch]$NoPrompt,
    [switch]$Check,
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

# Writes a registry value, creating the key if it doesn't exist.
function Set-Reg {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# Step title in the terminal.
function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
# With -NoPrompt, Choose returns the default right away.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @((T 'Yes' 'Sim'), (T 'No' 'Não')) $(if ($Default) { 0 } else { 1 })) -eq 0
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

# Reads and validates a typed IP address (IPv4 = InterNetwork, IPv6 = InterNetworkV6).
function Read-IP([string]$Question, [string]$Family, [bool]$Optional) {
    while ($true) {
        $answer = "$(Read-Host "    $Question")".Trim()
        if ($answer -eq '' -and $Optional) { return $null }
        $ip = $null
        # (TryParse accepts short forms like "1.1.1"; for IPv4 all 4 octets are required)
        $formatOk = if ($Family -eq 'InterNetwork') { $answer -match '^\d{1,3}(\.\d{1,3}){3}$' } else { $answer -match ':' }
        if ($formatOk -and [System.Net.IPAddress]::TryParse($answer, [ref]$ip) -and $ip.AddressFamily -eq $Family) { return $ip.ToString() }
        Write-Host "    $(T 'Invalid address. Example:' 'Endereço inválido. Exemplo:') $(if ($Family -eq 'InterNetwork') { '1.1.1.1' } else { '2606:4700:4700::1111' })" -ForegroundColor DarkYellow
    }
}

# Runs a step. If it fails, records the failure and moves on to the next one.
$script:Failures = @()
function Invoke-Step([string]$Title, [scriptblock]$Body) {
    Write-Step $Title
    try { & $Body }
    catch {
        $script:Failures += "${Title}: $($_.Exception.Message)"
        Write-Warning (T "This step failed ($($_.Exception.Message)). Moving on to the next one." "Esta etapa falhou ($($_.Exception.Message)). Seguindo para a próxima.")
    }
}

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = if ($NoPrompt) { 'en' } else { @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] } }
$script:Lang = $Lang

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning (T 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).')
    return
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
            Write-Host "  $(T 'disabled' 'desativado'): $svc"
        }
    }
}

# Disables (does not delete) the data collection tasks. The Compatibility Appraiser stays ON:
# it is what clears the yearly Windows feature update to install safely.
$TelemetryTasks = @(
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

function Disable-TelemetryTasks {
    foreach ($t in $TelemetryTasks) {
        if (Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue) {
            Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  $(T 'disabled' 'desativada'): $($t[1])"
        }
    }
    # (Older versions of this script disabled the Compatibility Appraiser; here it is re-enabled.)
    foreach ($name in 'Microsoft Compatibility Appraiser', 'Microsoft Compatibility Appraiser Exp') {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName $name -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Disabled') {
            Enable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue | Out-Null
            Write-Host (T "  re-enabled: $name (needed for the yearly feature update)" "  religada: $name (necessária para a atualização anual)")
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
    Write-Host (T '  policies applied' '  políticas aplicadas')
}

# Widgets (Windows 11) / News and interests (Windows 10).
# On recent Windows 11 builds Microsoft protects the Widgets key and not even an administrator
# can write to it. In that case, removes the Widgets package ("Windows Web Experience Pack").
function Disable-Widgets {
    if ($isWin11) {
        try {
            if (-not (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh')) { New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Host (T '  Widgets disabled by policy' '  Widgets desativados por política')
        } catch {
            Write-Host (T '  (Windows protects the Widgets policy; removing the Widgets package instead)' '  (o Windows protege a política dos Widgets; removendo o pacote dos Widgets em vez disso)') -ForegroundColor DarkYellow
            $widgets = Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience' -ErrorAction SilentlyContinue
            if (-not $widgets) { Write-Host (T '  Widgets are not installed anymore' '  Widgets já não estão instalados') }
            foreach ($pkg in $widgets) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Host (T '  Widgets removed' '  Widgets removidos')
                } catch {
                    Write-Host (T "  (could not remove Widgets: $($_.Exception.Message.Trim()). Turn them off in Settings → Personalization → Taskbar.)" "  (não foi possível remover os Widgets: $($_.Exception.Message.Trim()). Desligue em Configurações → Personalização → Barra de tarefas.)") -ForegroundColor DarkYellow
                }
            }
        }
    } else {
        try {
            if (-not (Test-Path "$P\Windows Feeds")) { New-Item "$P\Windows Feeds" -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty "$P\Windows Feeds" -Name 'EnableFeeds' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Host (T '  News and interests turned off' '  Notícias e interesses desativado')
        } catch {
            Write-Host (T '  (could not turn off News and interests by policy; right-click the taskbar → News and interests → Turn off)' '  (não foi possível desativar Notícias e interesses por política; clique com o direito na barra de tarefas → Notícias e interesses → Desativar)') -ForegroundColor DarkYellow
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
    Write-Host (T '  settings applied' '  ajustes aplicados')
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
# Everything Xbox. Separate question (default no): Store/Game Pass games and games that sign in with
# Xbox (Minecraft, Forza, Halo...) need these. Steam, Epic, Riot and Game Mode don't.
$XboxApps = @(
    'Microsoft.GamingApp',                     # Xbox app
    'Microsoft.XboxApp',                       # Xbox Console Companion (Windows 10)
    'Microsoft.XboxGamingOverlay',             # Xbox Game Bar (Win+G)
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.XboxIdentityProvider',          # Xbox sign-in inside games
    'Microsoft.Xbox.TCUI',
    'Microsoft.GamingServices'                 # Store / Game Pass games
)
function Remove-Apps([string[]]$List) {
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($app in $List) {
        foreach ($prov in ($provisioned | Where-Object DisplayName -eq $app)) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                Write-Host "  $(T 'deprovisioned' 'desprovisionado'): $($prov.DisplayName)"
            } catch {
                Write-Host (T "  (not deprovisioned: $($prov.DisplayName) — $($_.Exception.Message.Trim()))" "  (não desprovisionado: $($prov.DisplayName) — $($_.Exception.Message.Trim()))") -ForegroundColor DarkYellow
            }
        }
        foreach ($pkg in (Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue)) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Host "  $(T 'removed' 'removido'): $($pkg.Name)"
            } catch {
                Write-Host (T "  (not removed: $($pkg.Name) — $($_.Exception.Message.Trim()))" "  (não removido: $($pkg.Name) — $($_.Exception.Message.Trim()))") -ForegroundColor DarkYellow
            }
        }
    }
}

# Snipping Tool (Windows 10: Snip & Sketch). Separate question (default no), for whoever uses another
# screenshot app such as ShareX. Win+Shift+S stops working; the Print Screen key is freed (on Windows 11
# it opens the Snipping Tool by default) so the other app can take it over.
$SnippingApps = @('Microsoft.ScreenSketch')
function Remove-SnippingTool {
    Remove-Apps $SnippingApps
    Set-Reg 'HKCU:\Control Panel\Keyboard' 'PrintScreenKeyForSnippingEnabled' 0
    Write-Host (T '  Print Screen key: free for other apps (ShareX...)' '  tecla Print Screen: livre para outros apps (ShareX...)')
}

# Game DVR (background game recording) off. Without it, Windows doesn't try to open the removed
# Game Bar ("You'll need a new app to open this ms-gamingoverlay link").
function Disable-GameDvr {
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Reg "$P\GameDVR" 'AllowGameDVR' 0
    Write-Host (T '  game recording (Game DVR): off' '  gravação de jogos (Game DVR): desligada')
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
    Write-Host (T '  OneDrive removed' '  OneDrive removido')
}

# --- Edge ------------------------------------------------------------------

# Edge desktop shortcut: deletes it (your desktop and the shared one) and, through the official Edge
# Update policy, stops Edge installs and updates from creating it again.
function Get-EdgeShortcuts {
    foreach ($folder in 'CommonDesktopDirectory', 'Desktop') {
        $dir = [Environment]::GetFolderPath($folder)
        if ($dir) { Join-Path $dir 'Microsoft Edge.lnk' }
    }
}
function Remove-EdgeDesktopShortcut {
    $U = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    Set-Reg $U 'CreateDesktopShortcutDefault' 0
    Set-Reg $U 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0   # Edge (Stable)
    Get-EdgeShortcuts | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Remove-Item -LiteralPath $_ -Force }
    Write-Host (T '  Edge desktop shortcut: deleted, and Edge updates no longer create it' '  atalho do Edge na Área de Trabalho: apagado, e as atualizações do Edge não criam mais')
}

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
    Write-Host (T '  Edge policies applied' '  políticas do Edge aplicadas')
}

# --- Windows Security ------------------------------------------------------

function Set-WindowsSecurity {
    # Potentially unwanted app blocking (adware, installers bundling "extras")
    try {
        Set-MpPreference -PUAProtection Enabled -ErrorAction Stop
        Write-Host (T '  potentially unwanted app blocking: on' '  bloqueio de apps indesejados: ligado')
    } catch {
        Write-Host (T "  (could not turn on potentially unwanted app blocking: $($_.Exception.Message.Trim()). Another antivirus installed?)" "  (não foi possível ligar o bloqueio de apps indesejados: $($_.Exception.Message.Trim()). Outro antivírus instalado?)") -ForegroundColor DarkYellow
    }
    # Second half of the same setting: "Block downloads" (SmartScreen in Edge). Without it, Windows Security
    # keeps warning that potentially unwanted app blocking is off.
    # (the value is the key's default value; reg.exe /ve writes it reliably)
    reg.exe add 'HKCU\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled' /ve /t REG_DWORD /d 1 /f | Out-Null
    if ($LASTEXITCODE) { Write-Host (T '  (could not turn on unwanted download blocking)' '  (não foi possível ligar o bloqueio de downloads indesejados)') -ForegroundColor DarkYellow }
    else               { Write-Host (T '  unwanted download blocking: on' '  bloqueio de downloads indesejados: ligado') }

    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    # "Informational" notifications (suggestions, summaries). Important alerts — threat found,
    # protection turned off — keep showing up.
    Set-Reg "$WSC\Notifications" 'DisableEnhancedNotifications' 1
    Write-Host (T '  informational notifications: hidden (important alerts still show up)' '  avisos informativos: escondidos (alertas importantes continuam)')

    # "Set up OneDrive for ransomware recovery" card: without OneDrive it only causes the
    # exclamation mark on the icon. Hidden only when OneDrive is not installed.
    $hasOneDrive = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
                   (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
    if (-not $hasOneDrive) {
        Set-Reg "$WSC\Virus and threat protection" 'HideRansomwareRecovery' 1
        Write-Host (T '  OneDrive backup warning: hidden (OneDrive not installed)' '  aviso de backup do OneDrive: escondido (OneDrive não instalado)')
    } else {
        Write-Host (T '  OneDrive backup warning: kept (OneDrive installed)' '  aviso de backup do OneDrive: mantido (OneDrive instalado)')
    }
}

# Official option "Download manufacturers' apps and custom icons available for your devices"
# (System Properties → Hardware → Device Installation Settings). Drivers keep coming from Windows Update.
# Note: some vendor installers (e.g. Razer) ship inside the driver package itself and may still appear.
function Disable-DeviceMetadata {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Write-Host (T '  manufacturer apps and icons for devices: no longer downloaded (drivers still are)' '  apps e ícones de fabricante para periféricos: não são mais baixados (drivers continuam)')
}

# Recall (Copilot+ PCs only): official policies that remove it and stop it from being turned on, and
# stop it from saving snapshots. On other PCs they change nothing.
function Disable-Recall {
    Set-Reg "$P\WindowsAI" 'AllowRecallEnablement' 0
    Set-Reg "$P\WindowsAI" 'DisableAIDataAnalysis' 1
    Write-Host (T '  Recall: removed and blocked (after restarting; only exists on Copilot+ PCs)' '  Recall: removido e bloqueado (depois de reiniciar; só existe em PCs Copilot+)')
}

# WPBT (Windows Platform Binary Table): lets the PC's firmware hand Windows a program to run at every
# boot. Manufacturers use it to reinstall their apps (Armoury Crate, Vantage...) even after a clean install.
# This stops Windows from running it; the firmware itself is not touched.
function Disable-Wpbt {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
    Write-Host (T '  WPBT: Windows no longer runs programs provided by the firmware (after restarting)' '  WPBT: o Windows não executa mais programas fornecidos pelo firmware (depois de reiniciar)')
}

# Hides the "Account protection" and "Device security" areas of Windows Security (official policy).
# With a local account they only show "Sign in with a Microsoft account" warnings. Nothing is turned off:
# TPM, Secure Boot, Memory integrity and Windows Hello keep working as they are.
function Hide-SecurityAccountAreas {
    $WSC = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    Set-Reg "$WSC\Account protection" 'UILockdown' 1
    Set-Reg "$WSC\Device security"    'UILockdown' 1
    Write-Host (T '  "Account protection" and "Device security": hidden from Windows Security' '  "Proteção de contas" e "Segurança do dispositivo": escondidas da Segurança do Windows')
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
        Write-Host (T '  inetpub: hidden (not deleted: it is part of a security fix)' '  inetpub: escondida (não é apagada: faz parte de uma correção de segurança)')
    }
    if (Test-Path $perfLogs) {
        Remove-Item $perfLogs -Recurse -Force -ErrorAction Stop
        Write-Host (T '  PerfLogs: deleted' '  PerfLogs: apagada')
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
    if (-not (Test-Path $theme)) { throw (T "theme file not found: $theme" "arquivo de tema não encontrado: $theme") }

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
    if ($current -ine $theme) { Write-Warning (T 'Could not confirm the theme. Check Settings → Personalization → Themes.' 'Não deu para confirmar o tema. Confira em Configurações → Personalização → Temas.') }
    else { Write-Host "  $(T 'theme applied' 'tema aplicado'): $(Split-Path $theme -Leaf)" }
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
        Write-Host (T "  theme wallpaper: $(Split-Path $wallpaper -Leaf) (Windows Spotlight off)" "  papel de parede do tema: $(Split-Path $wallpaper -Leaf) (Destaques do Windows desligado)")
    } else {
        Write-Host (T '  (could not change the wallpaper; pick one in Settings → Personalization → Background)' '  (não foi possível trocar o papel de parede; escolha em Configurações → Personalização → Tela de fundo)') -ForegroundColor DarkYellow
    }
}

# Visible file extensions, frequent folders and recent files in File Explorer.
function Set-Explorer([bool]$ShowExtensions, [bool]$HideFrequent, [bool]$HideRecent) {
    $Exp = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    if ($ShowExtensions) { Set-Reg "$Exp\Advanced" 'HideFileExt' 0; Write-Host (T '  file extensions visible' '  extensões visíveis') }
    if ($HideFrequent)   { Set-Reg $Exp 'ShowFrequent' 0;          Write-Host (T '  frequent folders hidden (the ones you pinned stay)' '  pastas frequentes escondidas (as que você fixou continuam)') }
    if ($HideRecent) {
        Set-Reg $Exp 'ShowRecent' 0
        if ($isWin11) { Set-Reg $Exp 'ShowRecommendations' 0 }
        Write-Host (T '  recent files hidden' '  arquivos recentes escondidos')
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
    Write-Host (T '  Home and Gallery removed from the sidebar; File Explorer opens in "This PC"' '  Início e Galeria removidos da barra lateral; o Explorador abre em "Este Computador"')
    $script:RestartExplorer = $true
}

# Windows 11: the full right-click menu right away, without "Show more options" (the Windows 10 style menu).
# An empty InprocServer32 for this CLSID makes File Explorer skip the new menu. Undo: delete the key.
function Enable-ClassicContextMenu {
    reg.exe add 'HKCU\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' /ve /f | Out-Null   # /ve without /d = empty default value
    if ($LASTEXITCODE) { throw (T 'could not write the classic menu key' 'não foi possível gravar a chave do menu clássico') }
    Write-Host (T '  classic context menu: on (no "Show more options")' '  menu de contexto clássico: ligado (sem "Mostrar mais opções")')
    $script:RestartExplorer = $true
}

# Shows hidden files and folders (.git, AppData...). Protected system files stay hidden.
# Unpins the Music folder from Quick access (the folder itself and its files are not touched).
# Uses the same "Unpin from Quick access" action as the right-click menu.
function Unpin-QuickAccessMusic {
    $music = [Environment]::GetFolderPath('MyMusic')
    $quick = (New-Object -ComObject Shell.Application).Namespace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
    $item  = $quick.Items() | Where-Object { $_.Path -eq $music }
    if (-not $item) { Write-Host (T '  Music was not pinned to Quick access' '  Músicas já não estava fixada no Acesso rápido'); return }
    $item.InvokeVerb('unpinfromhome')
    Write-Host (T '  Music unpinned from Quick access (the folder stays where it is)' '  Músicas desafixada do Acesso rápido (a pasta continua onde está)')
}

function Show-HiddenFiles {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
    Write-Host (T '  hidden files and folders: visible (protected system files stay hidden)' '  arquivos e pastas ocultos: visíveis (arquivos protegidos do sistema continuam escondidos)')
    $script:RestartExplorer = $true
}

# Stops File Explorer from "sniffing" each folder's content to pick a template (Music, Pictures...),
# which makes folders with thousands of files slow to open. Every folder uses the generic template.
# The saved per-folder views (Bags/BagMRU) must be cleared for this to apply, so custom views are reset.
function Disable-FolderDiscovery {
    $shell = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell'
    Remove-Item "$shell\Bags", "$shell\BagMRU" -Recurse -Force -ErrorAction SilentlyContinue
    Set-Reg "$shell\Bags\AllFolders\Shell" 'FolderType' 'NotSpecified' 'String'
    Write-Host (T '  automatic folder type discovery: off (folder views reset)' '  descoberta automática de tipo de pasta: desligada (visualizações de pasta zeradas)')
    $script:RestartExplorer = $true
}

# Battery percentage next to the taskbar battery icon (Windows 11 24H2/25H2, builds from late 2025 on).
# On older builds the value is simply ignored.
function Enable-BatteryPercentage {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IsBatteryPercentageEnabled' 1
    Write-Host (T '  battery percentage on the taskbar: on (if your Windows version has the option)' '  porcentagem da bateria na barra de tarefas: ligada (se a sua versão do Windows tiver a opção)')
    $script:RestartExplorer = $true
}

# Invisible area around windows that "grabs" the mouse for resizing: from ~5 px down to ~1 px.
# Windows default: -60. Takes effect after signing out and back in.
function Set-ThinBorder {
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'PaddedBorderWidth' '0' 'String'
    Write-Host (T '  border thinned (takes effect after signing out and back in)' '  borda afinada (vale depois de sair da conta e entrar de novo)')
}

# Snap windows off (Settings → System → Multitasking): no snapping to screen edges, no Snap layouts.
# Saved in the registry and applied right away through the same Windows call Settings uses.
function Disable-SnapWindows {
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WindowArrangementActive' '0' 'String'
    if (-not ('CfgWin.Snap' -as [type])) {
        Add-Type -Namespace CfgWin -Name Snap -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, System.IntPtr pvParam, uint fWinIni);
'@
    }
    # SPI_SETWINARRANGEMENT = 0x0083; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    [void][CfgWin.Snap]::SystemParametersInfo(0x0083, 0, [IntPtr]::Zero, 3)
    Write-Host (T '  Snap windows: off' '  Ajustar janelas: desligado')
}

# Taskbar icon alignment (Windows 11 only): TaskbarAl 0 = left, 1 = center (Windows default).
function Set-TaskbarAlignment([bool]$Left) {
    $value = if ($Left) { 0 } else { 1 }
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' $value
    Write-Host "  $(T 'taskbar icons' 'ícones da barra de tarefas'): $(if ($Left) { T 'left' 'à esquerda' } else { T 'center' 'ao centro' })"
    $script:RestartExplorer = $true
}

# Taskbar search (Windows 10 and 11): SearchboxTaskbarMode 0 = hidden, 1 = icon only, 2 = search box.
function Set-TaskbarSearch([int]$Mode) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' $Mode
    Write-Host "  $(T 'taskbar search' 'pesquisa na barra de tarefas'): $(@((T 'hidden' 'oculta'), (T 'icon only' 'só o ícone'), (T 'search box' 'caixa de pesquisa'))[$Mode])"
    $script:RestartExplorer = $true
}

# "Task View" button on the taskbar (Windows 10 and 11): ShowTaskViewButton 0 = hidden, 1 = visible.
# Win+Tab keeps working either way.
function Set-TaskViewButton([bool]$Show) {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' ([int]$Show)
    Write-Host "  $(T 'Task View button' 'botão Visão de Tarefas'): $(if ($Show) { T 'visible' 'visível' } else { T 'hidden (Win+Tab still works)' 'oculto (Win+Tab continua funcionando)' })"
    $script:RestartExplorer = $true
}

# Unpins every app from the taskbar (Edge, Store, File Explorer and any you pinned yourself).
# The pin list lives in the Taskband key plus the shortcuts in the "User Pinned\TaskBar" folder.
# Apps are not uninstalled; pin them again with right-click → "Pin to taskbar".
function Clear-TaskbarPins {
    Remove-Item 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host (T '  pinned icons removed from the taskbar' '  ícones fixados removidos da barra de tarefas')
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
    Write-Host (T '  File Explorer restarted' '  Explorer reiniciado')
}

#endregion


#region ==================== 5. EVERYDAY USE ====================

function Enable-LongPaths {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
    Write-Host (T '  long paths: allowed' '  caminhos longos: permitidos')
}

function Enable-EndTask {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1
    Write-Host (T '  "End task" on the taskbar: on' '  "Finalizar tarefa" na barra de tarefas: ligado')
    $script:RestartExplorer = $true
}

# "Inline" mode: the command runs in the same terminal window, like on Linux.
function Enable-Sudo {
    & "$env:SystemRoot\System32\sudo.exe" config --enable normal | Out-Null
    Write-Host (T '  sudo: enabled (inline mode)' '  sudo: ativado (modo em linha)')
}

function Enable-ClipboardHistory {
    Set-Reg 'HKCU:\SOFTWARE\Microsoft\Clipboard' 'EnableClipboardHistory' 1
    Write-Host (T '  clipboard history (Win+V): on (this PC only, no sync)' '  histórico da área de transferência (Win+V): ligado (só neste PC, sem sincronizar)')
}

function Disable-MouseAcceleration {
    $mouse = 'HKCU:\Control Panel\Mouse'
    Set-Reg $mouse 'MouseSpeed'      '0' 'String'
    Set-Reg $mouse 'MouseThreshold1' '0' 'String'
    Set-Reg $mouse 'MouseThreshold2' '0' 'String'
    Write-Host (T '  Enhance pointer precision: off (takes effect after signing out and back in)' '  precisão do ponteiro aprimorada: desligada (vale depois de sair da conta e entrar de novo)')
}

# 506 = Sticky Keys off and WITHOUT the 5x Shift shortcut (Windows default is 510).
# The feature is still available in Settings → Accessibility → Keyboard.
function Disable-StickyKeysShortcut {
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Write-Host (T '  Sticky Keys shortcut (5x Shift): off' '  atalho das Teclas de Aderência (5x Shift): desligado')
}

# Num Lock on when Windows starts: on the sign-in screen (.DEFAULT) and for your user.
# Only bit 2 (Num Lock) is turned on; the other bits of the value are kept.
$NumLockKeys = @('Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard', 'HKCU:\Control Panel\Keyboard')
function Enable-NumLockAtStartup {
    foreach ($k in $NumLockKeys) {
        $n = [int64]0; [void][int64]::TryParse([string](Get-RegValue $k 'InitialKeyboardIndicators'), [ref]$n)
        Set-Reg $k 'InitialKeyboardIndicators' ([string]($n -bor 2)) 'String'
    }
    Write-Host (T '  Num Lock: on when Windows starts' '  Num Lock: ligado ao iniciar o Windows')
}

# Fast Startup makes "Shut down" a partial hibernation. Off = a real shutdown every time: drivers and
# updates load fresh and dual boot works. Startup gets a few seconds slower. Restart is not affected.
function Disable-FastStartup {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Write-Host (T '  Fast Startup: off ("Shut down" now really shuts down)' '  Inicialização rápida: desligada ("Desligar" agora desliga de verdade)')
}

# Blue screen (BSoD) also shows the technical parameters of the error, which helps to look up the cause.
function Enable-VerboseBsod {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 1
    Write-Host (T '  detailed blue screen: on (only shows up if the PC crashes)' '  tela azul detalhada: ligada (só aparece se o PC travar)')
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
    Write-Host "  $(T 'Windows volume' 'volume do Windows'): $([math]::Round([CfgWin.Audio]::GetVolume() * 100))%"
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
    if (-not $adapters) { throw (T 'no physical network adapter found' 'nenhum adaptador de rede físico encontrado') }
    foreach ($adapter in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $all -ErrorAction Stop
        if ($isWin11) {
            $doh = "$base\$($adapter.InterfaceGuid)\DohInterfaceSettings"
            Remove-Item "$doh\Doh", "$doh\Doh6" -Recurse -Force -ErrorAction SilentlyContinue   # clear old servers
            foreach ($ip in $V4) { Set-Reg "$doh\Doh\$ip"  'DohFlags' 1 'QWord' }
            foreach ($ip in $V6) { Set-Reg "$doh\Doh6\$ip" 'DohFlags' 1 'QWord' }
        }
        Write-Host "  $($adapter.Name): $($all -join ', ')$(if ($isWin11) { T ' (encrypted, automatic template)' ' (criptografado, modelo automático)' })"
    }
    Clear-DnsClientCache
    if (-not $V6) { Write-Host (T '  IPv6: kept automatic (from the router).' '  IPv6: mantido automático (do roteador).') -ForegroundColor DarkGray }
}

#endregion


#region ==================== 7. CHECK ====================

# Where the answers are saved, so -Check knows what you chose.
$StateFile = Join-Path $env:ProgramData 'TidyWin\windows.json'

function Save-State($Options, [string[]]$V4, [string[]]$V6) {
    New-Item -ItemType Directory -Path (Split-Path $StateFile) -Force | Out-Null
    [ordered]@{ Saved = (Get-Date).ToString('s'); Options = $Options; DnsV4 = @($V4); DnsV6 = @($V6) } |
        ConvertTo-Json -Depth 4 | Set-Content -Path $StateFile -Encoding UTF8
}

function Get-RegValue([string]$Path, [string]$Name) {
    (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

# Each Test-* returns a list of what is no longer as configured (empty = OK).
function Test-Telemetry {
    $bad = @()
    foreach ($svc in 'DiagTrack', 'dmwappushservice') {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.StartType -ne 'Disabled') { $bad += (T "service $svc on" "serviço $svc ligado") }
    }
    foreach ($t in $TelemetryTasks) {
        $task = Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne 'Disabled') { $bad += (T "task $($t[1]) on" "tarefa $($t[1]) ligada") }
    }
    if ((Get-RegValue "$P\DataCollection" 'AllowTelemetry') -ne 1)          { $bad += (T 'diagnostic data policy' 'política de dados de diagnóstico') }
    if ((Get-RegValue "$P\Windows Search" 'DisableWebSearch') -ne 1)       { $bad += (T 'Bing in search' 'Bing na pesquisa') }
    if ((Get-RegValue "$P\AdvertisingInfo" 'DisabledByGroupPolicy') -ne 1) { $bad += (T 'advertising ID' 'ID de anúncios') }
    if ($isWin11) {
        $widgetsOff = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests') -eq 0 -or
                      -not (Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience' -ErrorAction SilentlyContinue)
        if (-not $widgetsOff) { $bad += 'Widgets' }
    } elseif ((Get-RegValue "$P\Windows Feeds" 'EnableFeeds') -ne 0) { $bad += (T 'News and interests' 'Notícias e interesses') }
    $bad
}

function Test-Suggestions {
    $CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $bad = @()
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled') {
        if ((Get-RegValue $CDM $n) -ne 0) { $bad += $n }
    }
    if ((Get-RegValue "$P\CloudContent" 'DisableWindowsConsumerFeatures') -ne 1) { $bad += (T 'suggested app installs' 'instalação de apps sugeridos') }
    $bad
}

# Apps from the removal list that are installed again (names as Windows shows them in Get-AppxPackage).
function Get-ReturnedApps([string[]]$List) {
    @($List | Where-Object { Get-AppxPackage -AllUsers -Name $_ -ErrorAction SilentlyContinue })
}

function Test-OneDrive {
    $bad = @()
    if ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")) { $bad += (T 'OneDrive installed again' 'OneDrive instalado de novo') }
    if ((Get-RegValue "$P\OneDrive" 'DisableFileSyncNGSC') -ne 1) { $bad += (T 'policy that blocks OneDrive' 'política que bloqueia o OneDrive') }
    $bad
}

function Test-Edge {
    $E = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $bad = @()
    foreach ($n in 'StartupBoostEnabled', 'BackgroundModeEnabled', 'HubsSidebarEnabled', 'DiagnosticData', 'EdgeShoppingAssistantEnabled') {
        if ((Get-RegValue $E $n) -ne 0) { $bad += $n }
    }
    if ((Get-RegValue $E 'HideFirstRunExperience') -ne 1) { $bad += 'HideFirstRunExperience' }
    $bad
}

function Test-EdgeShortcut {
    $bad = @()
    if (@(Get-EdgeShortcuts | Where-Object { Test-Path -LiteralPath $_ }).Count) { $bad += (T 'shortcut is back on the desktop' 'atalho voltou para a Área de Trabalho') }
    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault') -ne 0) { $bad += (T 'policy that stops the shortcut' 'política que impede o atalho') }
    $bad
}

function Test-NumLock {
    $n = [int64]0; [void][int64]::TryParse([string](Get-RegValue $NumLockKeys[0] 'InitialKeyboardIndicators'), [ref]$n)
    if (-not ($n -band 2)) { T 'off when Windows starts' 'desligado ao iniciar' }
}

function Test-Security {
    $bad = @()
    try { if ((Get-MpPreference -ErrorAction Stop).PUAProtection -ne 1) { $bad += (T 'potentially unwanted app blocking' 'bloqueio de apps indesejados') } } catch { }
    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableEnhancedNotifications') -ne 1) { $bad += (T 'informational notifications' 'avisos informativos') }
    $bad
}

function Test-RootFolders {
    $bad = @()
    $inetpub = Get-Item "$env:SystemDrive\inetpub" -Force -ErrorAction SilentlyContinue
    if ($inetpub -and -not ($inetpub.Attributes -band [IO.FileAttributes]::Hidden)) { $bad += (T 'inetpub visible' 'inetpub visível') }
    if (Test-Path "$env:SystemDrive\PerfLogs") { $bad += (T 'PerfLogs is back' 'PerfLogs de volta') }
    $bad
}

function Test-Value([string]$Path, [string]$Name, $Expected, [string]$Label) {
    if ((Get-RegValue $Path $Name) -ne $Expected) { $Label }
}

function Test-DNS([string[]]$V4) {
    $bad = @()
    foreach ($adapter in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled')) {
        $current = @((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        if (($current -join ',') -ne ($V4 -join ',')) { $bad += "$($adapter.Name): $(if ($current) { $current -join ', ' } else { T 'automatic' 'automático' })" }
    }
    $bad
}

function Invoke-Check {
    Write-Host "`nConfigure-Windows -Check — $osLabel" -ForegroundColor Green
    if (-not (Test-Path $StateFile)) {
        Write-Host (T '  No saved answers. Run Configure-Windows first (older versions of it did not save the answers).' '  Nenhuma resposta salva. Rode o Configure-Windows primeiro (versões antigas dele não salvavam as respostas).') -ForegroundColor Yellow
        return
    }
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $o = $state.Options
    Write-Host (T "  Comparing with the answers from $(([datetime]$state.Saved).ToString('yyyy-MM-dd HH:mm'))." "  Comparando com as respostas de $(([datetime]$state.Saved).ToString('dd/MM/yyyy HH:mm')).")
    Write-Host (T '  Personalization is not checked: those are preferences you may have changed on purpose.' '  Personalização não é conferida: são preferências que você pode ter mudado de propósito.') -ForegroundColor DarkGray

    $appList = if ($o.OptionalApps) { $JunkApps + $OptionalApps } else { $JunkApps }
    $returnedApps = @()
    # Name shown, chosen?, test, fix
    $items = @(
        @{ Name = (T 'Telemetry' 'Telemetria');                    On = $o.Telemetry;    Test = { Test-Telemetry };   Fix = { Disable-TelemetryServices; Disable-TelemetryTasks; Set-TelemetryPolicies; Disable-Widgets } }
        @{ Name = (T 'Suggestions and ads' 'Sugestões e anúncios');          On = $o.Suggestions;  Test = { Test-Suggestions }; Fix = { Disable-Suggestions } }
        @{ Name = (T 'Removed apps' 'Apps removidos');                On = $o.Apps;         Test = { $script:returnedApps = Get-ReturnedApps $appList; $script:returnedApps }; Fix = { Remove-Apps $script:returnedApps } }
        @{ Name = 'Xbox';                                                    On = $o.NoXbox;       Test = { $script:returnedXbox = Get-ReturnedApps $XboxApps; $script:returnedXbox; if ((Get-RegValue "$P\GameDVR" 'AllowGameDVR') -ne 0) { 'Game DVR' } }; Fix = { if ($script:returnedXbox) { Remove-Apps $script:returnedXbox }; Disable-GameDvr } }
        @{ Name = (T 'Snipping Tool' 'Captura de Tela');               On = $o.NoSnipping;   Test = { Get-ReturnedApps $SnippingApps; if ((Get-RegValue 'HKCU:\Control Panel\Keyboard' 'PrintScreenKeyForSnippingEnabled') -ne 0) { 'Print Screen' } }; Fix = { Remove-SnippingTool } }
        @{ Name = 'OneDrive';                      On = $o.OneDrive;     Test = { Test-OneDrive };    Fix = { Remove-OneDrive } }
        @{ Name = (T 'Edge policies' 'Políticas do Edge');             On = $o.Edge;         Test = { Test-Edge };        Fix = { Set-EdgePolicies } }
        @{ Name = (T 'Edge shortcut' 'Atalho do Edge');                On = $o.NoEdgeShortcut; Test = { Test-EdgeShortcut }; Fix = { Remove-EdgeDesktopShortcut } }
        @{ Name = (T 'Windows Security' 'Segurança do Windows');          On = $o.Security;     Test = { Test-Security };    Fix = { Set-WindowsSecurity } }
        @{ Name = (T 'C: folders' 'Pastas do C:');                  On = $o.RootFolders;  Test = { Test-RootFolders }; Fix = { Clear-SystemDriveRoot } }
        @{ Name = (T 'Manufacturer apps' 'Apps de fabricante');            On = $o.NoDeviceApps; Test = { Test-Value 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 (T 'manufacturer app downloads' 'download de apps de fabricante') }; Fix = { Disable-DeviceMetadata } }
        @{ Name = 'Recall';                                                  On = $o.NoRecall;     Test = { Test-Value "$P\WindowsAI" 'AllowRecallEnablement' 0 (T 'allowed' 'permitido') }; Fix = { Disable-Recall } }
        @{ Name = 'WPBT';                                                    On = $o.NoWpbt;       Test = { Test-Value 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1 (T 'firmware programs (WPBT) allowed' 'programas do firmware (WPBT) permitidos') }; Fix = { Disable-Wpbt } }
        @{ Name = (T 'Hidden account areas' 'Áreas de conta escondidas');     On = $o.HideAreas;    Test = { Test-Value 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Account protection' 'UILockdown' 1 (T 'Account protection visible' 'Proteção de contas visível') }; Fix = { Hide-SecurityAccountAreas } }
        @{ Name = (T 'Long paths' 'Caminhos longos');               On = $o.LongPaths;    Test = { Test-Value 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 (T 'off' 'desligado') }; Fix = { Enable-LongPaths } }
        @{ Name = (T 'Detailed blue screen' 'Tela azul detalhada');           On = $o.VerboseBsod;  Test = { Test-Value 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 1 (T 'off' 'desligada') }; Fix = { Enable-VerboseBsod } }
        @{ Name = 'Num Lock';                                                On = $o.NumLock;      Test = { Test-NumLock }; Fix = { Enable-NumLockAtStartup } }
        @{ Name = (T 'Fast Startup' 'Inicialização rápida');             On = $o.NoFastStartup; Test = { Test-Value 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 (T 'on again' 'ligada de novo') }; Fix = { Disable-FastStartup } }
        @{ Name = 'DNS';                           On = [bool]@($state.DnsV4).Count; Test = { Test-DNS @($state.DnsV4) }; Fix = { Set-DNS @($state.DnsV4) @($state.DnsV6 | Where-Object { $_ }) } }
    )

    $drifted = @()
    Write-Host ''
    foreach ($item in $items) {
        if (-not $item.On) { continue }
        $problems = @(& $item.Test | Where-Object { $_ })
        if ($problems) {
            $drifted += $item
            Write-Host (T '  [BACK]   ' '  [VOLTOU] ') -ForegroundColor Yellow -NoNewline
            Write-Host $item.Name -NoNewline
            Write-Host "  ($($problems -join '; '))" -ForegroundColor DarkGray
        } else {
            Write-Host '  [OK]     ' -ForegroundColor Green -NoNewline
            Write-Host $item.Name
        }
    }

    if (-not $drifted) { Write-Host (T "`nEverything is still as you left it." "`nTudo continua como você deixou.") -ForegroundColor Green; return }
    Write-Host ''
    if (-not (Ask (T "Reapply what came back ($($drifted.Count) item(s))?" "Reaplicar o que voltou ($($drifted.Count) item(ns))?") $true)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }
    foreach ($item in $drifted) { Invoke-Step $item.Name $item.Fix }
    if ($script:Failures.Count) {
        Write-Host (T "`nSteps that failed:" "`nEtapas que falharam:") -ForegroundColor Yellow
        $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    Write-Step (T 'Done. Restart the computer.' 'Concluído. Reinicie o computador.')
}

if ($Check) { Invoke-Check; return }

#endregion


#region ==================== 8. QUESTIONS ====================

Write-Host "`nConfigure-Windows — $osLabel" -ForegroundColor Green
if ($cv.EditionID -match 'Core') {
    Write-Host (T '  Windows Home: some policies only work on Pro; the rest works normally.' '  Windows Home: algumas políticas valem só no Pro; o resto funciona normalmente.') -ForegroundColor DarkYellow
}
if (-not $NoPrompt) { Write-Host (T '  Choose with the arrows and Enter. The default answer comes selected.' '  Escolha com as setas e Enter. A resposta padrão já vem selecionada.') }

$opt = [ordered]@{}

# --- Privacy and cleanup
Write-Host (T "`n  Privacy and cleanup" "`n  Privacidade e limpeza") -ForegroundColor Cyan
$opt.Telemetry    = Ask (T 'Disable telemetry (service, tasks and policies)?' 'Desativar telemetria (serviço, tarefas e políticas)?') $true
$opt.Suggestions  = Ask (T 'Disable suggestions, ads and silent app installs?' 'Desativar sugestões, anúncios e instalação silenciosa de apps?') $true
$opt.Apps         = Ask (T 'Remove junk apps (Clipchamp, Bing, Solitaire, Teams, new Outlook...)?' 'Remover apps inúteis (Clipchamp, Bing, Solitaire, Teams, Outlook novo...)?') $true
$opt.OptionalApps = if ($opt.Apps) { Ask (T 'Also remove Phone Link, Sticky Notes, Sound Recorder, Clock, Quick Assist, Media Player and OneNote?' 'Remover também Vincular ao Celular, Sticky Notes, Gravador, Relógio, Assistência Rápida, Media Player e OneNote?') $false } else { $false }
$opt.NoXbox       = Ask (T 'Remove the Xbox apps (Xbox app, Game Bar, Xbox sign-in and Gaming Services)? Store/Game Pass games and games that use Xbox sign-in (Minecraft, Forza...) stop working. Steam, Epic and Riot are not affected.' 'Remover os apps do Xbox (app Xbox, Game Bar, login Xbox e Gaming Services)? Jogos da Store/Game Pass e jogos com login Xbox (Minecraft, Forza...) param de funcionar. Steam, Epic e Riot não são afetados.') $false
$opt.NoSnipping   = Ask (T 'Remove the Snipping Tool (Win+Shift+S stops working and the Print Screen key is freed)? Useful if you will install ShareX or another screenshot app.' 'Remover a Captura de Tela (o Win+Shift+S para de funcionar e a tecla Print Screen fica livre)? Útil se você vai instalar o ShareX ou outro app de captura.') $false
if ($foldersInOneDrive) {
    Write-Host (T "  WARNING: these folders are inside OneDrive: $($foldersInOneDrive -join ', ')" "  ATENÇÃO: estas pastas estão dentro do OneDrive: $($foldersInOneDrive -join ', ')") -ForegroundColor Yellow
    Write-Host (T '  Turn off folder backup in OneDrive before removing it.' '  Desligue o backup de pastas no OneDrive antes de removê-lo.') -ForegroundColor Yellow
}
$opt.OneDrive     = Ask (T 'Remove OneDrive?' 'Remover o OneDrive?') (-not $foldersInOneDrive)
$opt.Edge         = Ask (T 'Apply Edge policies (no telemetry, background mode, sidebar or shopping)?' 'Aplicar políticas do Edge (sem telemetria, segundo plano, barra lateral, compras)?') $true
$opt.NoRecall     = if ($isWin11) { Ask (T 'Remove and block Recall (screen snapshots; only exists on Copilot+ PCs)?' 'Remover e bloquear o Recall (fotos da tela; só existe em PCs Copilot+)?') $true } else { $false }
$opt.NoEdgeShortcut = Ask (T 'Delete the Edge shortcut from the desktop (and stop Edge updates from creating it again)?' 'Apagar o atalho do Edge da Área de Trabalho (e impedir que as atualizações do Edge criem de novo)?') $true
$opt.Security     = Ask (T 'Windows Security: block potentially unwanted apps and hide unimportant notifications?' 'Segurança do Windows: bloquear apps indesejados e esconder avisos sem importância?') $true
$opt.RootFolders  = Ask (T 'Hide the inetpub folder and delete PerfLogs (in the root of C:)?' 'Esconder a pasta inetpub e apagar a PerfLogs (na raiz do C:)?') $true
$opt.NoDeviceApps = Ask (T 'Do not download manufacturer apps and icons when connecting devices (Razer, Logitech...; drivers still come)?' 'Não baixar apps e ícones de fabricante ao conectar periféricos (Razer, Logitech...; drivers continuam vindo)?') $false
$opt.NoWpbt       = Ask (T 'Block programs the motherboard firmware installs on its own (WPBT: Armoury Crate, Vantage...)? Can stop a driver or utility from installing by itself after formatting.' 'Bloquear programas que o firmware da placa-mãe instala sozinho (WPBT: Armoury Crate, Vantage...)? Pode impedir que um driver ou utilitário se instale sozinho após formatar.') $false
$opt.HideAreas    = Ask (T 'Hide "Account protection" and "Device security" from Windows Security (they only ask you to sign in with a Microsoft account)?' 'Esconder "Proteção de contas" e "Segurança do dispositivo" da Segurança do Windows (só avisam para entrar com conta Microsoft)?') $isLocalAccount

# --- Personalization
Write-Host (T "`n  Personalization (your user only)" "`n  Personalização (só para o seu usuário)") -ForegroundColor Cyan
$themeNames = @((T 'Keep as is' 'Manter como está'), (T 'Windows (light)' 'Windows (claro)'), (T 'Windows (dark)' 'Windows (escuro)'))
$themeIds   = @('Keep', 'Light', 'Dark')
$opt.Theme          = $themeIds[(Choose (T 'Windows theme:' 'Tema do Windows:') $themeNames 1)]
$taskbarNames = @((T 'Keep as is' 'Manter como está'), (T 'Center' 'Ao centro'), (T 'Left' 'À esquerda'))
$taskbarIds   = @('Keep', 'Center', 'Left')
$opt.Taskbar        = if ($isWin11) { $taskbarIds[(Choose (T 'Taskbar icons:' 'Ícones da barra de tarefas:') $taskbarNames 0)] } else { 'Keep' }
$searchNames = @((T 'Keep as is' 'Manter como está'), (T 'Hidden' 'Oculta'), (T 'Icon only' 'Só o ícone'), (T 'Search box' 'Caixa de pesquisa'))
$searchIds   = @('Keep', 'Hidden', 'Icon', 'Box')
$opt.Search         = $searchIds[(Choose (T 'Taskbar search:' 'Pesquisa na barra de tarefas:') $searchNames 0)]
$taskViewNames = @((T 'Keep as is' 'Manter como está'), (T 'Show' 'Mostrar'), (T 'Hide' 'Ocultar'))
$taskViewIds   = @('Keep', 'Show', 'Hide')
$opt.TaskView       = $taskViewIds[(Choose (T '"Task View" button on the taskbar:' 'Botão "Visão de Tarefas" na barra de tarefas:') $taskViewNames 0)]
$opt.ClearPins      = Ask (T 'Remove the pinned icons from the taskbar (Edge, Store, File Explorer and the ones you pinned)?' 'Remover os ícones fixados na barra de tarefas (Edge, Store, Explorador e os que você fixou)?') $false
$opt.BatteryPercent = if ($isWin11 -and $hasBattery) { Ask (T 'Show the battery percentage on the taskbar?' 'Mostrar a porcentagem da bateria na barra de tarefas?') $false } else { $false }
$opt.ShowExtensions = Ask (T 'Show file extensions (.txt, .exe...)?' 'Mostrar as extensões dos arquivos (.txt, .exe...)?') $true
$opt.HideFrequent   = Ask (T 'Hide frequent folders from Quick access?' 'Esconder as pastas frequentes do Acesso rápido?') $true
$opt.UnpinMusic     = Ask (T 'Unpin "Music" from Quick access (the folder stays)?' 'Remover "Músicas" do Acesso rápido (a pasta continua existindo)?') $false
$opt.HideRecent     = Ask (T 'Also hide recent files in File Explorer?' 'Esconder também os arquivos recentes no Explorador?') $false
$opt.ShowHidden     = Ask (T 'Show hidden files and folders in File Explorer (.git, AppData...)?' 'Mostrar arquivos e pastas ocultos no Explorador (.git, AppData...)?') $false
$opt.NoFolderSniff  = Ask (T 'Turn off automatic folder type discovery (large folders open faster; resets custom folder views)?' 'Desligar a descoberta automática de tipo de pasta (pastas grandes abrem mais rápido; zera as visualizações personalizadas)?') $true
$opt.HideHomeGallery = if ($isWin11) { Ask (T 'Remove "Home" and "Gallery" from the File Explorer sidebar (it then opens in "This PC")?' 'Remover "Início" e "Galeria" da barra lateral do Explorador (ele passa a abrir em "Este Computador")?') $false } else { $false }
$opt.ClassicMenu    = if ($isWin11) { Ask (T 'Use the classic right-click menu (full, without clicking "Show more options")?' 'Usar o menu clássico do botão direito (completo, sem precisar clicar em "Mostrar mais opções")?') $false } else { $false }
$opt.NoSnap         = Ask (T 'Turn off "Snap windows" (windows no longer snap to the screen edges or into layouts)?' 'Desligar o "Ajustar janelas" (as janelas deixam de se encaixar nas bordas da tela e em layouts)?') $false
$opt.ThinBorder     = Ask (T 'Thin the window resize border (avoids resizing by accident)?' 'Afinar a borda de redimensionamento das janelas (evita redimensionar sem querer)?') $false

# --- Everyday use
Write-Host (T "`n  Everyday use" "`n  Uso no dia a dia") -ForegroundColor Cyan
$opt.LongPaths        = Ask (T 'Allow long paths (over 260 characters; avoids errors with node_modules)?' 'Permitir caminhos longos (mais de 260 caracteres; evita erros com node_modules)?') $true
$opt.EndTask          = if ($hasEndTask) { Ask (T 'Show "End task" when right-clicking an app on the taskbar?' 'Mostrar "Finalizar tarefa" ao clicar com o direito num app na barra de tarefas?') $true } else { $false }
$opt.Sudo             = if ($hasSudo)    { Ask (T 'Enable sudo in the terminal (run commands as admin without opening another window)?' 'Ativar o sudo no terminal (rodar comandos como admin sem abrir outra janela)?') $false } else { $false }
$opt.ClipboardHistory = Ask (T 'Turn on clipboard history (Win+V)?' 'Ativar o histórico da área de transferência (Win+V)?') $true
$opt.NoMouseAccel     = Ask (T 'Turn off "Enhance pointer precision" (mouse acceleration)?' 'Desligar a "precisão do ponteiro aprimorada" (aceleração do mouse)?') $false
$opt.NoStickyKeys     = Ask (T 'Turn off the Sticky Keys shortcut (prompt when pressing Shift 5 times)?' 'Desligar o atalho das Teclas de Aderência (aviso ao apertar Shift 5 vezes)?') $true
$opt.NumLock          = Ask (T 'Turn Num Lock on when Windows starts (also on the sign-in screen)?' 'Ligar o Num Lock ao iniciar o Windows (também na tela de login)?') $true
$opt.NoFastStartup    = Ask (T 'Turn off Fast Startup? ("Shut down" really shuts down; startup takes a few seconds longer)' 'Desligar a Inicialização rápida? ("Desligar" desliga de verdade; o PC demora alguns segundos a mais para ligar)') $false
$opt.MaxVolume        = Ask (T 'Set the Windows volume to 100% (on the speakers/headphones in use now)?' 'Deixar o volume do Windows em 100% (no alto-falante/fone em uso agora)?') $true
$opt.VerboseBsod      = Ask (T 'Show technical details on the blue screen if the PC crashes (helps find the cause)?' 'Mostrar detalhes técnicos na tela azul, se o PC travar (ajuda a descobrir a causa)?') $true

# --- Network
Write-Host (T "`n  Network" "`n  Rede") -ForegroundColor Cyan
$dnsV4 = @(); $dnsV6 = @()
if (Ask (T 'Set DNS manually (with DNS over HTTPS, automatic template)?' 'Configurar o DNS manualmente (com DNS por HTTPS, modelo automático)?') $false) {
    if (-not $isWin11) {
        Write-Host (T '    Note: Windows 10 has no system-wide DNS over HTTPS. DNS will be set, but unencrypted.' '    Aviso: o Windows 10 não tem DNS por HTTPS no sistema. O DNS será definido, mas sem criptografia.') -ForegroundColor Yellow
    }
    $dnsV4 += Read-IP (T 'Preferred DNS (IPv4):' 'DNS preferencial (IPv4):') 'InterNetwork' $false
    $altV4 = Read-IP (T 'Alternate DNS (IPv4, Enter to skip):' 'DNS alternativo (IPv4, Enter para pular):') 'InterNetwork' $true
    if ($altV4) { $dnsV4 += $altV4 }
    Write-Host (T '    IPv6: if left blank, IPv6 DNS stays the one from the router, unencrypted.' '    IPv6: se ficar em branco, o DNS IPv6 continua o do roteador, sem criptografia.') -ForegroundColor DarkGray
    $prefV6 = Read-IP (T 'Preferred DNS (IPv6, Enter to skip):' 'DNS preferencial (IPv6, Enter para pular):') 'InterNetworkV6' $true
    if ($prefV6) {
        $dnsV6 += $prefV6
        $altV6 = Read-IP (T 'Alternate DNS (IPv6, Enter to skip):' 'DNS alternativo (IPv6, Enter para pular):') 'InterNetworkV6' $true
        if ($altV6) { $dnsV6 += $altV6 }
    }
    # The "automatic template" only exists for servers Windows knows (Cloudflare, Google, Quad9...)
    if ($isWin11) {
        foreach ($ip in ($dnsV4 + $dnsV6)) {
            if (-not (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue)) {
                Write-Host (T "    Note: Windows has no automatic template for $ip. That server will be UNENCRYPTED." "    Aviso: o Windows não tem modelo automático para $ip. Esse servidor ficará SEM criptografia.") -ForegroundColor Yellow
            }
        }
    }
}
$opt.DNS = if ($dnsV4) { ($dnsV4 + $dnsV6) -join ', ' } else { 'Keep' }

# --- Summary and confirmation
# Labels shown on screen for each option (in the chosen language, like the questions).
$labels = @{
    Telemetry = (T 'Telemetry' 'Telemetria'); Suggestions = (T 'Suggestions' 'Sugestões'); Apps = 'Apps'; OptionalApps = (T 'Optional apps' 'Apps opcionais'); NoXbox = (T 'No Xbox' 'Sem Xbox'); NoSnipping = (T 'No Snipping Tool' 'Sem Captura de Tela')
    OneDrive = 'OneDrive'; Edge = 'Edge'; Security = (T 'Security' 'Segurança'); HideAreas = (T 'Hide areas' 'Esconder áreas'); RootFolders = (T 'C: folders' 'Pastas do C:'); Theme = (T 'Theme' 'Tema'); Taskbar = (T 'Taskbar' 'Barra de tarefas')
    Search = (T 'Search' 'Pesquisa'); TaskView = (T 'Task View' 'Visão de Tarefas'); ClearPins = (T 'No pins' 'Sem fixados')
    ShowExtensions = (T 'Extensions' 'Extensões'); HideFrequent = (T 'No frequent' 'Sem frequentes'); UnpinMusic = (T 'No Music in Quick access' 'Sem Músicas no Acesso rápido'); HideRecent = (T 'No recent' 'Sem recentes'); HideHomeGallery = (T 'No Home/Gallery' 'Sem Início/Galeria'); ClassicMenu = (T 'Classic menu' 'Menu clássico'); NoSnap = (T 'No Snap' 'Sem Ajustar janelas'); ThinBorder = (T 'Thin border' 'Borda fina')
    LongPaths = (T 'Long paths' 'Caminhos longos'); EndTask = (T 'End task' 'Finalizar tarefa'); Sudo = 'Sudo'; ClipboardHistory = (T 'Win+V history' 'Histórico Win+V')
    NoMouseAccel = (T 'No acceleration' 'Sem aceleração'); NoStickyKeys = (T 'No Sticky Keys' 'Sem aderência'); MaxVolume = 'Volume 100%'; DNS = 'DNS'
    NoDeviceApps = (T 'No device apps' 'Sem apps de periféricos'); NoWpbt = (T 'No WPBT' 'Sem WPBT'); NoRecall = (T 'No Recall' 'Sem Recall'); NoEdgeShortcut = (T 'No Edge shortcut' 'Sem atalho do Edge'); NumLock = 'Num Lock'; NoFastStartup = (T 'No Fast Startup' 'Sem inicialização rápida'); BatteryPercent = (T 'Battery %' 'Bateria em %'); ShowHidden = (T 'Hidden files' 'Arquivos ocultos')
    NoFolderSniff = (T 'No folder discovery' 'Sem descoberta pasta'); VerboseBsod = (T 'Detailed blue screen' 'Tela azul detalhada')
}
if (-not $NoPrompt) {
    Write-Host (T "`n  Summary:" "`n  Resumo:") -ForegroundColor Cyan
    foreach ($key in $opt.Keys) {
        $value = $opt[$key]
        $text = if ($value -is [bool]) { if ($value) { T 'yes' 'sim' } else { T 'no' 'não' } }
                elseif ($key -eq 'Theme')   { $themeNames[[array]::IndexOf($themeIds, $value)] }
                elseif ($key -eq 'Taskbar') { $taskbarNames[[array]::IndexOf($taskbarIds, $value)] }
                elseif ($key -eq 'Search')  { $searchNames[[array]::IndexOf($searchIds, $value)] }
                elseif ($key -eq 'TaskView') { $taskViewNames[[array]::IndexOf($taskViewIds, $value)] }
                elseif ($key -eq 'DNS' -and $value -eq 'Keep') { T 'keep' 'manter' }
                else { $value }
        Write-Host ("    {0,-24} {1}" -f $labels[$key], $text)
    }
    if (-not (Ask (T 'Apply now?' 'Aplicar agora?') $true)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }
}

#endregion


#region ==================== 9. EXECUTION ====================

# --- Save the answers for -Check
try { Save-State $opt $dnsV4 $dnsV6 } catch { Write-Warning (T "Could not save the answers for -Check: $($_.Exception.Message)" "Não foi possível salvar as respostas para o -Check: $($_.Exception.Message)") }

# --- Restore point (if there is already one from the last 24 h, Windows just warns and moves on)
Write-Step (T 'Creating restore point' 'Criando ponto de restauração')
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description (T 'Before Configure-Windows' 'Antes do Configure-Windows') -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
} catch {
    Write-Warning (T "Could not create the restore point: $($_.Exception.Message)" "Não foi possível criar o ponto de restauração: $($_.Exception.Message)")
    if (-not (Ask (T 'Continue anyway?' 'Continuar mesmo assim?') $false)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }
}

# --- Privacy and cleanup
if ($opt.Telemetry) {
    Invoke-Step (T 'Telemetry: services' 'Telemetria: serviços')                                { Disable-TelemetryServices }
    Invoke-Step (T 'Telemetry: scheduled tasks (disables, does not delete)' 'Telemetria: tarefas agendadas (desativa, não apaga)') { Disable-TelemetryTasks }
    Invoke-Step (T 'Telemetry: policies' 'Telemetria: políticas')                               { Set-TelemetryPolicies; Disable-Widgets }
}
if ($opt.Suggestions) { Invoke-Step (T 'Suggestions, ads and silent app installs' 'Sugestões, anúncios e instalação silenciosa de apps') { Disable-Suggestions } }
if ($opt.Apps) {
    $appList = if ($opt.OptionalApps) { $JunkApps + $OptionalApps } else { $JunkApps }
    Invoke-Step (T 'Removing apps (all users + provisioned package)' 'Removendo apps (todos os usuários + pacote provisionado)') { Remove-Apps $appList }
}
if ($opt.NoXbox) {
    Invoke-Step (T 'Removing the Xbox apps' 'Removendo os apps do Xbox') { Remove-Apps $XboxApps; Disable-GameDvr }
}
if ($opt.NoSnipping) { Invoke-Step (T 'Removing the Snipping Tool' 'Removendo a Captura de Tela') { Remove-SnippingTool } }
if ($opt.OneDrive) { Invoke-Step (T 'Removing OneDrive' 'Removendo OneDrive')                                          { Remove-OneDrive } }
if ($opt.Edge)     { Invoke-Step (T 'Edge: no telemetry, background mode, sidebar or shopping' 'Edge: sem telemetria, segundo plano, barra lateral e compras') { Set-EdgePolicies } }
if ($opt.NoRecall) { Invoke-Step 'Recall' { Disable-Recall } }
if ($opt.NoEdgeShortcut) { Invoke-Step (T 'Edge desktop shortcut' 'Atalho do Edge na Área de Trabalho') { Remove-EdgeDesktopShortcut } }
if ($opt.Security) { Invoke-Step (T 'Windows Security' 'Segurança do Windows')                                        { Set-WindowsSecurity } }
if ($opt.RootFolders) { Invoke-Step (T 'Folders in the drive root (inetpub and PerfLogs)' 'Pastas na raiz do disco (inetpub e PerfLogs)')          { Clear-SystemDriveRoot } }
if ($opt.NoDeviceApps) { Invoke-Step (T 'Manufacturer apps for devices' 'Apps de fabricante para periféricos')                   { Disable-DeviceMetadata } }
if ($opt.NoWpbt)       { Invoke-Step (T 'Firmware programs (WPBT)' 'Programas do firmware (WPBT)')                   { Disable-Wpbt } }
if ($opt.HideAreas) { Invoke-Step (T 'Windows Security: hiding Microsoft account areas' 'Segurança do Windows: escondendo áreas de conta Microsoft')  { Hide-SecurityAccountAreas } }

# --- Personalization
if ($opt.Theme -ne 'Keep') {
    Invoke-Step "$(T 'Theme' 'Tema') $($themeNames[[array]::IndexOf($themeIds, $opt.Theme)])" { Set-Theme ($opt.Theme -eq 'Light') }
}
if ($opt.Taskbar -ne 'Keep') {
    Invoke-Step (T 'Taskbar alignment' 'Alinhamento da barra de tarefas') { Set-TaskbarAlignment ($opt.Taskbar -eq 'Left') }
}
if ($opt.Search -ne 'Keep') {
    # Index in $searchIds minus 1 = SearchboxTaskbarMode value (Hidden = 0, Icon = 1, Box = 2)
    Invoke-Step (T 'Taskbar search' 'Pesquisa na barra de tarefas') { Set-TaskbarSearch ([array]::IndexOf($searchIds, $opt.Search) - 1) }
}
if ($opt.TaskView -ne 'Keep') {
    Invoke-Step (T 'Task View button' 'Botão Visão de Tarefas') { Set-TaskViewButton ($opt.TaskView -eq 'Show') }
}
if ($opt.ClearPins) { Invoke-Step (T 'Removing pinned icons from the taskbar' 'Removendo ícones fixados da barra de tarefas') { Clear-TaskbarPins } }
if ($opt.BatteryPercent) { Invoke-Step (T 'Battery percentage' 'Porcentagem da bateria') { Enable-BatteryPercentage } }
if ($opt.ShowExtensions -or $opt.HideFrequent -or $opt.HideRecent) {
    Invoke-Step (T 'File Explorer' 'Explorador de Arquivos') { Set-Explorer $opt.ShowExtensions $opt.HideFrequent $opt.HideRecent }
}
if ($opt.ShowHidden)    { Invoke-Step (T 'File Explorer: hidden files' 'Explorador: arquivos ocultos')               { Show-HiddenFiles } }
if ($opt.NoFolderSniff) { Invoke-Step (T 'File Explorer: automatic folder discovery' 'Explorador: descoberta automática de pasta') { Disable-FolderDiscovery } }
if ($opt.HideHomeGallery) { Invoke-Step (T 'File Explorer: removing Home and Gallery' 'Explorador: removendo Início e Galeria') { Hide-HomeAndGallery } }
if ($opt.UnpinMusic) { Invoke-Step (T 'Quick access: Music' 'Acesso rápido: Músicas') { Unpin-QuickAccessMusic } }
if ($opt.ClassicMenu) { Invoke-Step (T 'Classic context menu' 'Menu de contexto clássico') { Enable-ClassicContextMenu } }
if ($opt.NoSnap) { Invoke-Step (T 'Snap windows' 'Ajustar janelas') { Disable-SnapWindows } }
if ($opt.ThinBorder) { Invoke-Step (T 'Window resize border' 'Borda de redimensionamento das janelas') { Set-ThinBorder } }

# --- Everyday use
if ($opt.LongPaths -or $opt.EndTask -or $opt.Sudo -or $opt.ClipboardHistory -or $opt.NoMouseAccel -or $opt.NoStickyKeys) {
    Invoke-Step (T 'Everyday use tweaks' 'Ajustes de uso no dia a dia') {
        if ($opt.LongPaths)        { Enable-LongPaths }
        if ($opt.EndTask)          { Enable-EndTask }
        if ($opt.Sudo)             { Enable-Sudo }
        if ($opt.ClipboardHistory) { Enable-ClipboardHistory }
        if ($opt.NoMouseAccel)     { Disable-MouseAcceleration }
        if ($opt.NoStickyKeys)     { Disable-StickyKeysShortcut }
    }
}
if ($opt.MaxVolume) { Invoke-Step (T 'Windows volume at 100%' 'Volume do Windows em 100%') { Set-MaxVolume } }
if ($opt.NumLock)       { Invoke-Step 'Num Lock' { Enable-NumLockAtStartup } }
if ($opt.NoFastStartup) { Invoke-Step (T 'Fast Startup' 'Inicialização rápida') { Disable-FastStartup } }
if ($opt.VerboseBsod) { Invoke-Step (T 'Detailed blue screen' 'Tela azul detalhada') { Enable-VerboseBsod } }

# --- Network
if ($dnsV4) { Invoke-Step "DNS: $($opt.DNS)" { Set-DNS $dnsV4 $dnsV6 } }

# --- Apply visuals right away (no need to sign out)
if ($script:RestartExplorer) { Invoke-Step (T 'Applying visuals without signing out' 'Aplicando visual sem precisar sair da conta') { Restart-Explorer } }

# --- Done
if ($script:Failures.Count) {
    Write-Host (T "`nSteps that failed (the rest was applied):" "`nEtapas que falharam (o resto foi aplicado):") -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Step (T 'Done. Restart the computer.' 'Concluído. Reinicie o computador.')
Write-Host (T 'To undo: Revert-Configure-Windows.ps1' 'Para desfazer: Revert-Configure-Windows.ps1') -ForegroundColor Green
Write-Host (T 'After a big Windows update, check with: Configure-Windows.ps1 -Check' 'Depois de uma atualização grande do Windows, confira com: Configure-Windows.ps1 -Check') -ForegroundColor DarkGray

#endregion
