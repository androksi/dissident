#Requires -RunAsAdministrator
<#
    Get-Report.ps1 — PC report in HTML: Windows, security for anti-cheats, hardware, disks, battery, updates

    HOW TO RUN (Windows PowerShell 5.1 as Administrator; some checks need it):
        powershell -ExecutionPolicy Bypass -File .\Get-Report.ps1
        powershell -ExecutionPolicy Bypass -File .\Get-Report.ps1 -OutFile D:\report.html

    Only reads: changes nothing on the PC. Saves "TidyWin report <date>.html" to the Desktop (or -OutFile)
    and opens it in the browser. Useful after formatting, and to send when asking for help: it has a
    "Copy as text" button and no personal data (no user or PC name, serial numbers, Windows key, IP or
    MAC addresses, or Wi-Fi names).

    Each item gets a status: OK, Attention, Problem or Info, with what to do when it isn't OK.
    The summary at the top lists what needs attention first.

    FILE LAYOUT
        1. Helpers ................... prompts, rows, HTML
        2. Checks .................... one function per section; a check that fails becomes an Info row
        3. Report .................... HTML page
        4. Execution
#>
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'


#region ==================== 1. HELPERS ====================


# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host "  Number [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
        }
    }
    Write-Host '  (↑ ↓ Enter)' -ForegroundColor DarkGray
    foreach ($o in $Options) { Write-Host '' }
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

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N0} GB' -f ($Bytes / 1GB) }
    return '{0:N0} MB' -f ($Bytes / 1MB)
}
function Format-Date($Date) { if ($Date) { ([datetime]$Date).ToString('yyyy-MM-dd') } else { '' } }

# One line of the report. Status: ok, warn (attention), bad (problem), info.
# Hint: what to do, shown when the status is not ok.
$script:Rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$Section, [string]$Label, [string]$Value, [ValidateSet('ok', 'warn', 'bad', 'info')][string]$Status = 'info', [string]$Hint = '') {
    $script:Rows.Add([pscustomobject]@{ Section = $Section; Label = $Label; Value = $Value; Status = $Status; Hint = $Hint })
}

# Runs a section's checks; if one breaks, the report still comes out with a note instead of it.
function Invoke-Section([string]$Section, [scriptblock]$Body) {
    Write-Host "  reading: $Section" -ForegroundColor DarkGray
    try { & $Body }
    catch { Add-Row $Section 'Could not read' "$($_.Exception.Message)".Trim() 'info' }
}


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. CHECKS ====================

$Sections = @{
    Windows  = 'Windows'
    Security = 'Security and anti-cheat (VALORANT, FACEIT...)'
    Hardware = 'Hardware'
    Storage  = 'Disks'
    Battery  = 'Battery'
    Health   = 'Updates and stability'
    Network  = 'Network'
}

function Get-WindowsInfo {
    $s = $Sections.Windows
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$cv.CurrentBuild
    $name = $os.Caption -replace '^Microsoft\s+', ''
    if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }     # some Windows 11 still say 10
    Add-Row $s 'Edition' $name
    Add-Row $s 'Version' "$($cv.DisplayVersion) (build $($cv.CurrentBuild).$($cv.UBR))"
    Add-Row $s 'Installed on' (Format-Date $os.InstallDate)

    # Activation: the Windows license (application id of Windows) with a key installed
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Select-Object -First 1
    $channel = if ($lic.ProductKeyChannel) { " · $($lic.ProductKeyChannel)" } else { '' }
    if (-not $lic) {
        Add-Row $s 'Activation' 'could not read' 'info'
    } elseif ($lic.LicenseStatus -eq 1) {
        Add-Row $s 'Activation' ('activated' + $channel) 'ok'
    } else {
        Add-Row $s 'Activation' ('not activated' + $channel) 'bad' 'Settings → System → Activation. A digital license comes back by itself on the same hardware after connecting to the internet.'
    }

    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    Add-Row $s 'Computer' "$($cs.Manufacturer) $($cs.Model)".Trim()
    Add-Row $s 'Motherboard' "$($board.Manufacturer) $($board.Product)".Trim()
    Add-Row $s 'BIOS' "$($bios.SMBIOSBIOSVersion) · $(Format-Date $bios.ReleaseDate)"
    $fw = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction SilentlyContinue).PEFirmwareType
    if ($fw -eq 2) { Add-Row $s 'Boot mode' 'UEFI' 'ok' }
    elseif ($fw -eq 1) { Add-Row $s 'Boot mode' 'Legacy BIOS' 'warn' 'Secure Boot and Windows 11 need UEFI. Converting needs a GPT disk (mbr2gpt) and a BIOS change.' }

    $boot = $os.LastBootUpTime
    $days = [int]((Get-Date) - $boot).TotalDays
    $up = if ($days -ge 1) { "$days day(s)" } else { 'less than a day' }
    Add-Row $s 'Running since' "$(Format-Date $boot) ($up)" $(if ($days -gt 30) { 'warn' } else { 'info' }) 'Use Restart (not Shut down) every few days: with Fast Startup, shutting down doesn''t clear Windows.'

    $plan = (powercfg /getactivescheme) -replace '^.*\(([^)]+)\).*$', '$1'
    Add-Row $s 'Power plan' "$plan".Trim()
}

function Get-SecurityInfo {
    $s = $Sections.Security
    # TPM 2.0
    $tpm = try { Get-Tpm -ErrorAction Stop } catch { $null }
    $spec = (Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue).SpecVersion
    $ver = if ($spec) { ($spec -split ',')[0].Trim() } else { '' }
    if (-not $tpm) { Add-Row $s 'TPM' 'could not read' 'info' }
    elseif (-not $tpm.TpmPresent) { Add-Row $s 'TPM' 'not found' 'bad' 'Turn on TPM in the BIOS: "fTPM" (AMD) or "PTT" (Intel).' }
    elseif ($ver -and $ver -notlike '2*') { Add-Row $s 'TPM' "$ver" 'warn' 'Windows 11 and VALORANT need TPM 2.0.' }
    elseif (-not $tpm.TpmReady) { Add-Row $s 'TPM' "$ver present, not ready".Trim() 'warn' 'Win + R → tpm.msc shows what is missing.' }
    else { Add-Row $s 'TPM' "$ver ready".Trim() 'ok' }

    # Secure Boot (throws on Legacy BIOS)
    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Row $s 'Secure Boot' 'on' 'ok' }
        else { Add-Row $s 'Secure Boot' 'off' 'bad' 'Turn it on in the BIOS (Boot or Security tab). VALORANT on Windows 11 requires it.' }
    } catch {
        Add-Row $s 'Secure Boot' 'not available (Legacy BIOS)' 'bad' 'Needs UEFI boot mode.'
    }

    # Memory integrity (HVCI): configured and actually running
    $hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $running = $dg -and (@($dg.SecurityServicesRunning) -contains 2)
    if ($running) { Add-Row $s 'Memory integrity' 'on' 'ok' }
    elseif ($hvci -eq 1) { Add-Row $s 'Memory integrity' 'on, waiting for a restart' 'warn' 'Restart the PC.' }
    else { Add-Row $s 'Memory integrity' 'off' 'warn' 'Windows Security → Device security → Core isolation. Some anti-cheats ask for it; an incompatible driver can block it (the page lists it).' }

    # Test signing / debug mode: anti-cheats refuse to run with it
    $start = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions)"
    if ($start -match 'TESTSIGNING|DEBUG') { Add-Row $s 'Test signing / debug' 'on' 'bad' 'Anti-cheats refuse it. As administrator: bcdedit /set testsigning off, and bcdedit /debug off, then restart.' }
    else { Add-Row $s 'Test signing / debug' 'off' 'ok' }

    # Antivirus (Windows Security Center: Defender or another one)
    $avs = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    $active = @($avs | Where-Object { ($_.productState -band 0x1000) -ne 0 })
    if ($active) {
        $old = @($active | Where-Object { ($_.productState -band 0x10) -ne 0 })
        Add-Row $s 'Antivirus' (($active.displayName | Select-Object -Unique) -join ', ') $(if ($old) { 'warn' } else { 'ok' }) 'Its definitions are out of date: update it.'
    } elseif ($avs) { Add-Row $s 'Antivirus' 'none active' 'bad' 'Turn on Windows Security → Virus & threat protection.' }

    $fw = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    if ($fw) {
        $off = @($fw | Where-Object { -not $_.Enabled })
        if ($off) { Add-Row $s 'Firewall' ('off in: ' + ($off.Name -join ', ')) 'warn' 'Windows Security → Firewall & network protection.' }
        else { Add-Row $s 'Firewall' 'on' 'ok' }
    }
    $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction SilentlyContinue).EnableLUA
    if ($uac -eq 0) { Add-Row $s 'User Account Control' 'off' 'bad' 'Every program runs as administrator. Turn it on: search "UAC" in Start.' }
    else { Add-Row $s 'User Account Control' 'on' 'ok' }
}

function Get-HardwareInfo {
    $s = $Sections.Hardware
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Add-Row $s 'CPU' "$($cpu.Name.Trim()) · $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"

    # RAM: total, type, speed, modules and channels
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $total = ($mods | Measure-Object Capacity -Sum).Sum
    $type = switch (($mods | Select-Object -First 1).SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } 35 { 'LPDDR5' } 30 { 'LPDDR4' } default { '' } }
    $now = ($mods | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
    $max = ($mods | Measure-Object Speed -Minimum).Minimum
    Add-Row $s 'RAM' ("$(Format-Size $total) $type".Trim() + $(if ($now) { " · $now MT/s" } else { '' }))
    $sizes = ($mods | ForEach-Object { Format-Size $_.Capacity }) -join ' + '
    $channels = @($mods | ForEach-Object {
        $txt = "$($_.BankLabel) $($_.DeviceLocator)"
        if ($txt -match 'CHANNEL\s*([A-H])\b' -or $txt -match 'Channel([A-H])' -or $txt -match '\bDIMM_?([A-H])\d') { $Matches[1].ToUpper() }
    } | Select-Object -Unique)
    $label = 'Memory channels'
    if ($mods.Count -le 1) { Add-Row $s $label ('1 module: single channel' + " ($sizes)") 'warn' 'Two matching modules (dual channel) give more performance, especially with integrated graphics. On a laptop with soldered memory this may not apply.' }
    elseif ($channels.Count -ge 2) { Add-Row $s $label ("dual channel · $sizes") 'ok' }
    elseif ($channels.Count -eq 1) { Add-Row $s $label ('modules on the same channel' + " · $sizes") 'warn' 'Move one module to the other channel''s slot (the motherboard manual shows which; usually slots 2 and 4).' }
    else { Add-Row $s $label ("$($mods.Count) modules (dual channel likely) · $sizes") 'info' }
    if ($now -and $max -and $now -lt $max) {
        Add-Row $s 'Memory speed' ("$now of $max MT/s") 'warn' 'The memory runs below what it supports: turn on XMP (Intel) or EXPO/DOCP (AMD) in the BIOS.'
    }

    # GPUs: driver installed, version (NVIDIA style when it is NVIDIA), age; screen mode
    foreach ($g in @(Get-CimInstance Win32_VideoController)) {
        # Windows' fallback driver; its .inf name is the same in every Windows language
        if ("$($g.InfFilename)" -match '^(basic)?display\.inf$' -or $g.Name -match 'Basic Display|Basic Render') {
            Add-Row $s 'Graphics' $g.Name 'bad' 'No graphics driver installed: install the one from NVIDIA, AMD or Intel (or run Windows Update).'
            continue
        }
        $ver = "$($g.DriverVersion)"
        if ($g.Name -match 'NVIDIA' -and $ver -match '(\d)\.(\d{2})(\d{2})$') {
            $digits = ($ver -replace '\.', '')
            $last5 = $digits.Substring($digits.Length - 5)
            $ver = "$($last5.Substring(0, 3)).$($last5.Substring(3)) ($($g.DriverVersion))"
        }
        $date = $g.DriverDate
        $old = $date -and ((Get-Date) - [datetime]$date).TotalDays -gt 365
        Add-Row $s $g.Name ('driver ' + "$ver · $(Format-Date $date)") $(if ($old) { 'warn' } else { 'ok' }) 'Driver over a year old: get the current one from the manufacturer (NVIDIA app, AMD Adrenalin, Intel).'
        if ($g.CurrentHorizontalResolution) {
            Add-Row $s ("  " + 'screen') "$($g.CurrentHorizontalResolution) × $($g.CurrentVerticalResolution) · $($g.CurrentRefreshRate) Hz" 'info'
        }
    }
}

function Get-StorageInfo {
    $s = $Sections.Storage
    $predict = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue | Where-Object PredictFailure)
    foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)) {
        $kind = @($d.BusType, $d.MediaType | Where-Object { $_ -and $_ -ne 'Unspecified' }) -join ' '
        $value = "$kind · $(Format-Size $d.Size)".Trim(' ·')
        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $extra = @()
        if ($null -ne $r.Wear)          { $extra += "$($r.Wear)% worn" }
        if ($r.Temperature)             { $extra += "$($r.Temperature) °C" }
        if ($r.PowerOnHours)            { $extra += "$($r.PowerOnHours) h on" }
        if ($extra) { $value += ' · ' + ($extra -join ' · ') }
        $status = 'ok'; $hint = ''
        if ("$($d.HealthStatus)" -eq 'Unhealthy' -or $predict.Count) { $status = 'bad'; $hint = 'The disk reports it may fail: back up your files now and plan to replace it.' }
        elseif ("$($d.HealthStatus)" -eq 'Warning' -or $r.Wear -ge 80) { $status = 'warn'; $hint = 'The disk is wearing out: keep backups up to date.' }
        elseif ($r.ReadErrorsUncorrected -gt 0) { $status = 'warn'; $hint = 'The disk had read errors: keep backups up to date and run "Repair Windows" in the TidyWin menu.' }
        Add-Row $s $d.FriendlyName $value $status $hint
    }
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size } | Sort-Object DriveLetter)) {
        $pct = [int](100 * $v.SizeRemaining / $v.Size)
        $status = if ($pct -lt 5) { 'bad' } elseif ($pct -lt 10) { 'warn' } else { 'ok' }
        $name = if ($v.FileSystemLabel) { " ($($v.FileSystemLabel))" } else { '' }
        Add-Row $s "$($v.DriveLetter):$name" ("$(Format-Size $v.SizeRemaining) free of $(Format-Size $v.Size) ($pct%)") $status 'Little free space slows Windows and blocks updates: use "Free up disk space" in the TidyWin menu.'
    }
}

function Get-BatteryInfo {
    if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { return }
    $s = $Sections.Battery
    # powercfg's XML report is not translated; it is written to %TEMP% and deleted right after
    $xmlFile = Join-Path $env:TEMP "tidywin-battery-$PID.xml"
    try {
        & powercfg /batteryreport /xml /output $xmlFile *> $null
        [xml]$xml = Get-Content -LiteralPath $xmlFile -Raw -ErrorAction Stop
    } finally { Remove-Item -LiteralPath $xmlFile -Force -ErrorAction SilentlyContinue }
    foreach ($b in @($xml.BatteryReport.Batteries.Battery)) {
        $design = [double]$b.DesignCapacity; $full = [double]$b.FullChargeCapacity
        if ($design -le 0) { continue }
        $health = [int](100 * $full / $design)
        $status = if ($health -lt 60) { 'bad' } elseif ($health -lt 80) { 'warn' } else { 'ok' }
        $cycles = if ($b.CycleCount -and [int]$b.CycleCount -gt 0) { " · $($b.CycleCount) cycles" } else { '' }
        Add-Row $s 'Health' ("$health% of the original capacity" + " ($([int]($full / 1000)) / $([int]($design / 1000)) Wh)$cycles") $status 'The battery holds noticeably less charge. Below 60%, consider replacing it.'
    }
}

function Get-HealthInfo {
    $s = $Sections.Health
    # Restart pending (updates or installers waiting)
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
               (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
               [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
    if ($pending) { Add-Row $s 'Restart pending' 'yes' 'warn' 'An update or installer is waiting: restart the PC.' }
    else { Add-Row $s 'Restart pending' 'no' 'ok' }

    # Last update installed
    $last = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($last) {
        $days = [int]((Get-Date) - $last.InstalledOn).TotalDays
        Add-Row $s 'Last update' "$(Format-Date $last.InstalledOn) · $($last.HotFixID)" $(if ($days -gt 45) { 'warn' } else { 'ok' }) 'No update in over 45 days: open Windows Update.'
    }

    # Devices with a problem (Device Manager's yellow sign)
    $codes = @{ 1 = 'not configured'; 10 = 'can''t start'; 22 = 'disabled'; 28 = 'no driver'; 31 = 'driver not loaded'; 43 = 'stopped with an error'; 45 = 'not connected' }
    $bad = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 45 })
    if (-not $bad) { Add-Row $s 'Devices' 'all working' 'ok' }
    foreach ($d in $bad) {
        $code = [int]$d.ConfigManagerErrorCode
        $why = if ($codes.ContainsKey($code)) { $codes[$code] } else { 'code ' + $code }
        $name = if ($d.Name) { $d.Name } else { $d.PNPClass }
        $status = if ($code -eq 22) { 'info' } else { 'bad' }
        Add-Row $s 'Device with a problem' "$name · $why" $status 'Install its driver (Windows Update → Advanced options → Optional updates, or the manufacturer''s site), or "Restore apps and drivers" in the TidyWin menu.'
    }

    # Crashes in the last 30 days: blue screens and unexpected shutdowns
    $since = (Get-Date).AddDays(-30)
    $bsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since } -ErrorAction SilentlyContinue)
    $power = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue)
    Add-Row $s 'Blue screens (30 days)' "$($bsod.Count)$(if ($bsod) { ' · ' + 'last ' + (Format-Date $bsod[0].TimeCreated) })" $(if ($bsod) { 'warn' } else { 'ok' }) 'Repeated blue screens usually come from a driver, RAM or overheating. Run "Repair Windows" in the TidyWin menu; send this report when asking for help.'
    Add-Row $s 'Unexpected shutdowns (30 days)' "$($power.Count)" $(if ($power.Count -ge 3) { 'warn' } else { 'ok' }) 'The PC turned off without shutting down: power supply, overheating, or a crash.'

    # Startup programs
    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique)
    Add-Row $s 'Programs at startup' ("$($startup.Count)" + $(if ($startup) { ': ' + ($startup -join ', ') } else { '' })) $(if ($startup.Count -gt 12) { 'warn' } else { 'info' }) 'Many programs at startup slow down the boot: Task Manager → Startup apps.'
}

function Get-NetworkInfo {
    $s = $Sections.Network
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
        $wifi = $a.PhysicalMediaType -match '802\.11' -or $a.InterfaceDescription -match 'Wi-?Fi|Wireless'
        $kind = if ($wifi) { 'Wi-Fi' } else { 'Ethernet' }
        $status = 'info'; $hint = ''
        if (-not $wifi -and $a.LinkSpeed -match '^100 Mbps') { $status = 'warn'; $hint = 'Cable connected at 100 Mbps instead of 1 Gbps: try another cable (Cat5e or better) or router port.' }
        Add-Row $s "$kind · $($a.InterfaceDescription)" "$($a.LinkSpeed)" $status $hint
        $dns = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        if ($dns) {
            $manual = "$((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" -Name NameServer -ErrorAction SilentlyContinue).NameServer)"
            $from = if ($manual) { 'set by hand' } else { 'from the router' }
            # Only public resolvers are shown by address; the router's own address stays out of the report
            $shown = if ($manual) { $dns -join ', ' } else { 'automatic' }
            Add-Row $s ("  DNS") "$shown ($from)" 'info'
        }
    }
    $ok = $false
    try { $ok = (Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop).Content -match 'Microsoft Connect Test' } catch { }
    if ($ok) { Add-Row $s 'Internet' 'working' 'ok' }
    else { Add-Row $s 'Internet' 'not working' 'bad' 'Try "Reset the network" in the TidyWin menu.' }
}

#endregion


#region ==================== 3. REPORT ====================

function ConvertTo-HtmlText([string]$Text) { return [System.Net.WebUtility]::HtmlEncode($Text) }

function New-ReportHtml([object[]]$Rows) {
    $labels = @{ ok = 'OK'; warn = 'Attention'; bad = 'Problem'; info = 'Info' }
    $issues = @($Rows | Where-Object { $_.Status -in 'bad', 'warn' } | Sort-Object { if ($_.Status -eq 'bad') { 0 } else { 1 } })
    $date = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $edition = ($Rows | Where-Object { $_.Section -eq $Sections.Windows -and $_.Label -eq 'Edition' }).Value
    $version = ($Rows | Where-Object { $_.Section -eq $Sections.Windows -and $_.Label -eq 'Version' }).Value
    $computer = ($Rows | Where-Object { $_.Section -eq $Sections.Windows -and $_.Label -eq 'Computer' }).Value

    # Plain text, for "Copy as text"
    $text = New-Object System.Text.StringBuilder
    [void]$text.AppendLine("TidyWin report · $date")
    [void]$text.AppendLine("$edition $version · $computer")
    foreach ($section in ($Rows | Select-Object -ExpandProperty Section -Unique)) {
        [void]$text.AppendLine("`n== $section")
        foreach ($r in ($Rows | Where-Object Section -eq $section)) {
            $mark = if ($r.Status -eq 'info') { '' } else { " [$($labels[$r.Status])]" }
            [void]$text.AppendLine("$($r.Label.Trim()): $($r.Value)$mark")
        }
    }

    # Summary
    if ($issues) {
        $title = "$($issues.Count) item(s) need attention"
        $cls = if ($issues | Where-Object Status -eq 'bad') { 'bad' } else { 'warn' }
        $list = ($issues | ForEach-Object {
            "<li><span class=`"pill $($_.Status)`">$($labels[$_.Status])</span><div><b>$(ConvertTo-HtmlText $_.Label.Trim())</b> · $(ConvertTo-HtmlText $_.Value)<div class=`"hint`">$(ConvertTo-HtmlText $_.Hint)</div></div></li>"
        }) -join "`n"
        $summary = "<section class=`"summary $cls`"><h2>$title</h2><ul class=`"issues`">$list</ul></section>"
    } else {
        $summary = "<section class=`"summary ok`"><h2>All good</h2><p>Nothing needs attention.</p></section>"
    }

    # Sections
    $cards = foreach ($section in ($Rows | Select-Object -ExpandProperty Section -Unique)) {
        $rowsHtml = ($Rows | Where-Object Section -eq $section | ForEach-Object {
            $hint = if ($_.Status -in 'warn', 'bad' -and $_.Hint) { "<div class=`"hint`">$(ConvertTo-HtmlText $_.Hint)</div>" } else { '' }
            $sub = if ($_.Label.StartsWith('  ')) { ' class="sub"' } else { '' }
            "<tr$sub><th>$(ConvertTo-HtmlText $_.Label.Trim())</th><td>$(ConvertTo-HtmlText $_.Value)$hint</td><td class=`"st`"><span class=`"pill $($_.Status)`">$($labels[$_.Status])</span></td></tr>"
        }) -join "`n"
        "<section class=`"card`"><h3>$(ConvertTo-HtmlText $section)</h3><table>$rowsHtml</table></section>"
    }

    $copy = 'Copy as text'
    $copied = 'Copied'
    $foot = 'Generated by TidyWin. Only reads the PC; has no user or PC name, serial numbers, Windows key, IP/MAC addresses or Wi-Fi names, so it can be shared.'

    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PC report · $date</title>
<style>
  :root { --bg:#f6f7f9; --card:#fff; --text:#1d2026; --muted:#5f6672; --line:#e3e6eb;
          --ok:#1f7a3f; --ok-bg:#e3f4e8; --warn:#8a5a00; --warn-bg:#fdf1d8; --bad:#b3261e; --bad-bg:#fbe3e1; --info:#4a5160; --info-bg:#eceef2; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#14161a; --card:#1d2026; --text:#e8eaee; --muted:#9aa1ad; --line:#2c3038;
            --ok:#7fd69b; --ok-bg:#1d3326; --warn:#f2c46b; --warn-bg:#3a2f17; --bad:#ff9a92; --bad-bg:#3d1f1d; --info:#b6bcc8; --info-bg:#2a2e36; }
  }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); font:15px/1.5 "Segoe UI", system-ui, sans-serif; }
  main { max-width:980px; margin:0 auto; padding:24px 16px 48px; }
  header { display:flex; flex-wrap:wrap; gap:12px; justify-content:space-between; align-items:flex-end; margin-bottom:16px; }
  h1 { margin:0; font-size:24px; } .meta { color:var(--muted); }
  button { font:inherit; padding:8px 14px; border-radius:8px; border:1px solid var(--line); background:var(--card); color:var(--text); cursor:pointer; }
  button:hover { border-color:var(--muted); }
  .summary { border-radius:12px; padding:16px 20px; margin-bottom:16px; border:1px solid var(--line); background:var(--card); }
  .summary h2 { margin:0 0 8px; font-size:19px; } .summary.ok h2 { color:var(--ok); } .summary.warn h2 { color:var(--warn); } .summary.bad h2 { color:var(--bad); }
  .summary p { margin:0; color:var(--muted); }
  .issues { list-style:none; margin:0; padding:0; } .issues li { display:flex; gap:10px; align-items:flex-start; padding:8px 0; border-top:1px solid var(--line); }
  .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:6px 20px 10px; margin-bottom:14px; }
  h3 { font-size:16px; margin:12px 0 6px; }
  table { width:100%; border-collapse:collapse; }
  th, td { text-align:left; vertical-align:top; padding:8px 0; border-top:1px solid var(--line); }
  th { width:32%; font-weight:600; padding-right:12px; } tr.sub th { font-weight:400; color:var(--muted); padding-left:14px; }
  td.st { width:1%; white-space:nowrap; text-align:right; padding-left:12px; }
  .hint { color:var(--muted); font-size:13.5px; margin-top:2px; }
  .pill { display:inline-block; font-size:12px; font-weight:600; padding:2px 9px; border-radius:999px; white-space:nowrap; }
  .pill.ok { color:var(--ok); background:var(--ok-bg); } .pill.warn { color:var(--warn); background:var(--warn-bg); }
  .pill.bad { color:var(--bad); background:var(--bad-bg); } .pill.info { color:var(--info); background:var(--info-bg); }
  footer { color:var(--muted); font-size:13px; margin-top:20px; }
  textarea { position:absolute; left:-9999px; }
  @media (max-width:640px) { th { width:auto; display:block; border:0; padding-bottom:0; } td { display:inline-block; border:0; } tr { display:block; border-top:1px solid var(--line); padding:6px 0; } td.st { float:right; } }
</style>
</head>
<body>
<main>
<header>
  <div><h1>PC report</h1><div class="meta">$(ConvertTo-HtmlText "$edition $version · $computer") · $date</div></div>
  <button id="copy">$copy</button>
</header>
$summary
$($cards -join "`n")
<footer>$foot</footer>
<textarea id="text" readonly>$(ConvertTo-HtmlText $text.ToString())</textarea>
</main>
<script>
  document.getElementById('copy').addEventListener('click', function () {
    var t = document.getElementById('text'), b = this;
    var done = function () { b.textContent = '$copied ✓'; setTimeout(function () { b.textContent = '$copy'; }, 2000); };
    if (navigator.clipboard) { navigator.clipboard.writeText(t.value).then(done, function () { t.select(); document.execCommand('copy'); done(); }); }
    else { t.select(); document.execCommand('copy'); done(); }
  });
</script>
</body>
</html>
"@
}

#endregion


#region ==================== 4. EXECUTION ====================

Write-Host "`nGet-Report" -ForegroundColor Green
Write-Host '  Only reads: nothing on the PC is changed. Takes up to a minute.' -ForegroundColor DarkGray

Invoke-Section $Sections.Windows  { Get-WindowsInfo }
Invoke-Section $Sections.Security { Get-SecurityInfo }
Invoke-Section $Sections.Hardware { Get-HardwareInfo }
Invoke-Section $Sections.Storage  { Get-StorageInfo }
Invoke-Section $Sections.Battery  { Get-BatteryInfo }
Invoke-Section $Sections.Health   { Get-HealthInfo }
Invoke-Section $Sections.Network  { Get-NetworkInfo }

if (-not $OutFile) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $OutFile = Join-Path $desktop ("{0} {1}.html" -f 'TidyWin report', (Get-Date -Format 'yyyy-MM-dd HHmm'))
}
try {
    # .ToArray(), not @(...): in Windows PowerShell 5.1, @(a List) bound to an [object[]] parameter fails
    # with "Argument types do not match"
    [IO.File]::WriteAllText($OutFile, (New-ReportHtml $script:Rows.ToArray()), (New-Object Text.UTF8Encoding $false))
} catch {
    Write-Host "  Could not save the report: $($_.Exception.Message)" -ForegroundColor Red
    return
}

$bad  = @($script:Rows | Where-Object Status -eq 'bad').Count
$warn = @($script:Rows | Where-Object Status -eq 'warn').Count
Write-Host ''
if ($bad -or $warn) { Write-Host "  $bad problem(s), $warn item(s) needing attention." -ForegroundColor Yellow }
else { Write-Host '  All good.' -ForegroundColor Green }
Write-Host "  Report saved to: $OutFile" -ForegroundColor Green
Start-Process $OutFile

#endregion
