#Requires -RunAsAdministrator
<#
    Reset-Network.ps1 — fixes common internet problems with Windows' own network commands, keeping your DNS

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Reset-Network.ps1

    For "connected, no internet", sites that don't open or a connection that keeps dropping.
    Shows the network adapters and asks how far to go:
        Quick (default, no restart) .. clears the DNS and ARP caches and gets a new IP from the router
        Full (needs a restart) ....... also resets Winsock and the TCP/IP settings
    Full: DNS servers you set by hand, and DNS over HTTPS, are saved first and put back after the reset
    (the quick steps don't touch them).
    On a PC with a manual IP address the TCP/IP reset is skipped, since it would erase that IP.
    Not used: Settings' "Network reset" (it removes the adapters and VPNs) or proxy resets.
    The connection drops for a few seconds. Safe to run more than once.

    FILE LAYOUT
        1. Helpers ................... prompts, adapters, DNS backup
        2. Steps
        3. Execution
#>
param(
)

$ErrorActionPreference = 'Continue'


#region ==================== 1. HELPERS ====================


function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

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

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Result line: [OK] text / [WARNING] text / [ERROR] text
function Write-Result([ValidateSet('OK', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $label, $color = switch ($Status) {
        'OK'    { '[OK]', 'Green' }
        'WARN'  { '[WARNING]', 'Yellow' }
        'ERROR' { '[ERROR]', 'Red' }
    }
    Write-Host "  $label " -ForegroundColor $color -NoNewline
    Write-Host $Text
}

$TcpipKeys = @{
    V4 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    V6 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces'
}
$DohKey     = 'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters'
$BackupDir  = Join-Path $env:ProgramData 'TidyWin\network-reset'

# DNS servers set by hand on each interface (NameServer; servers from the router are in DhcpNameServer).
# Every interface in the registry, connected or not, so nothing is lost.
function Get-ManualDns {
    $list = @()
    foreach ($family in 'V4', 'V6') {
        foreach ($key in (Get-ChildItem $TcpipKeys[$family] -ErrorAction SilentlyContinue)) {
            $servers = "$((Get-ItemProperty $key.PSPath -Name NameServer -ErrorAction SilentlyContinue).NameServer)".Trim()
            if ($servers) { $list += [pscustomobject]@{ Family = $family; Guid = $key.PSChildName; Servers = $servers } }
        }
    }
    return $list
}

# Puts the saved servers back in the registry (the same place Windows' own settings write them).
function Restore-ManualDns($Saved) {
    foreach ($s in $Saved) {
        $path = Join-Path $TcpipKeys[$s.Family] $s.Guid
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name NameServer -Value $s.Servers -Type String
    }
}

# Physical adapters with: connected?, manual IPv4?, DNS by hand (IPv4 + IPv6).
function Get-AdapterInfo($Dns) {
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -ne 'Disabled' | Sort-Object Name)) {
        $ipIf = Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $manualIp = $ipIf -and $ipIf.Dhcp -eq 'Disabled' -and [bool](Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object PrefixOrigin -eq 'Manual')
        [pscustomobject]@{
            Name      = $a.Name
            Connected = $a.Status -eq 'Up'
            ManualIp  = $manualIp
            Dns       = @($Dns | Where-Object Guid -eq "$($a.InterfaceGuid)" | ForEach-Object { $_.Servers -split '[,\s]+' } | Where-Object { $_ })
        }
    }
}

# Internet works: name resolution plus Windows' own connectivity test page.
function Test-Internet {
    try {
        $r = Invoke-WebRequest 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        return $r.Content -match 'Microsoft Connect Test'
    } catch { return $false }
}


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. STEPS ====================

# Saved to %ProgramData%\TidyWin\network-reset before anything: dns.json (servers by hand) and doh.reg
# (DNS over HTTPS per adapter). Kept afterwards, a few KB, in case something needs to be put back by hand.
function Save-NetworkBackup($Dns) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    ConvertTo-Json -InputObject @($Dns) | Set-Content (Join-Path $BackupDir 'dns.json') -Encoding UTF8
    $doh = Join-Path $BackupDir 'doh.reg'
    Remove-Item $doh -Force -ErrorAction SilentlyContinue
    & reg.exe export $DohKey $doh /y *> $null
    Write-Result 'OK' "DNS saved to $BackupDir"
}

function Reset-Winsock {
    $out = & netsh winsock reset 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Result 'OK' 'Winsock' } else { Write-Result 'WARN' "Winsock: $(($out | Where-Object { $_ } | Select-Object -Last 1))" }
}

# netsh lists every registry value it rewrote; a few "access denied" lines are normal and harmless.
function Reset-TcpIp {
    $log = Join-Path $env:TEMP 'tidywin-ip-reset.log'
    & netsh int ip reset $log *> $null
    $v4 = $LASTEXITCODE
    & netsh int ipv6 reset $log *> $null
    if ($v4 -eq 0 -and $LASTEXITCODE -eq 0) { Write-Result 'OK' 'TCP/IP (IPv4 + IPv6)' }
    else { Write-Result 'WARN' 'TCP/IP: done, with some items Windows did not let it change (normal)' }
    Remove-Item $log -Force -ErrorAction SilentlyContinue
}

function Restore-NetworkBackup($Dns) {
    Restore-ManualDns $Dns
    $doh = Join-Path $BackupDir 'doh.reg'
    if (Test-Path $doh) { & reg.exe import $doh *> $null }
    $now = @(Get-ManualDns)
    $missing = @($Dns | Where-Object { $s = $_; -not ($now | Where-Object { $_.Guid -eq $s.Guid -and $_.Family -eq $s.Family -and $_.Servers -eq $s.Servers }) })
    if ($missing) { Write-Result 'ERROR' "DNS not restored on $($missing.Count) interface(s); the backup is in $BackupDir" }
    elseif ($Dns) { Write-Result 'OK' 'your DNS servers are back' }
}

function Clear-NetworkCaches {
    Clear-DnsClientCache
    & netsh interface ip delete arpcache *> $null
    Write-Result 'OK' 'DNS and ARP caches cleared'
}

# New IP from the router, only on adapters with an automatic IP (ipconfig skips the others).
function Update-IpAddress {
    Write-Host '  getting a new IP from the router (the connection drops for a few seconds)...' -ForegroundColor DarkGray
    & ipconfig /release *> $null
    & ipconfig /renew *> $null
    Write-Result 'OK' 'new IP requested'
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Host "`nReset-Network" -ForegroundColor Green
Write-Host '  Fixes common internet problems with Windows'' own commands. Your DNS is kept.' -ForegroundColor DarkGray

# --- What is on this PC
$dns = @(Get-ManualDns)
$adapters = @(Get-AdapterInfo $dns)
Write-Host "`n  Network adapters:"
if (-not $adapters) { Write-Host '    (no physical adapter found)' -ForegroundColor DarkGray }
foreach ($a in $adapters) {
    $state = if ($a.Connected) { 'connected' } else { 'not connected' }
    $ip    = if ($a.ManualIp) { 'manual IP' } else { 'automatic IP' }
    $dnsTx = if ($a.Dns) { 'DNS ' + ($a.Dns -join ', ') + ' (kept)' } else { 'DNS from the router' }
    Write-Host ("    {0,-22} {1,-14} {2,-14} {3}" -f $a.Name, $state, $ip, $dnsTx)
}
$hasManualIp = [bool]($adapters | Where-Object ManualIp)

# --- Questions
Write-Host ''
$levels = @(
    'Quick: clear DNS/ARP caches and get a new IP (no restart)',
    'Full: also reset Winsock and TCP/IP (needs a restart)'
)
$full = (Choose 'What to do?' $levels 0) -eq 1
if ($full -and $hasManualIp) {
    Write-Host '  A network adapter has a manual IP: the TCP/IP reset will be skipped so it is not erased.' -ForegroundColor Yellow
}
if ($env:SESSIONNAME -like 'RDP*') {
    Write-Host '  You are connected through Remote Desktop: the session will drop and may not come back by itself.' -ForegroundColor Yellow
    if (-not (Ask 'Continue anyway?' $false)) { Write-Host 'Nothing was changed.'; return }
}
Write-Host '  Close downloads and calls first: the connection drops for a few seconds.' -ForegroundColor DarkGray
if (-not (Ask 'Reset the network now?' $true)) { Write-Host 'Nothing was changed.'; return }

# --- Steps (the quick ones don't touch the DNS settings, so only the full reset saves and restores them)
$total = if ($full) { 5 } else { 2 }; $n = 0
if ($full) {
    $n++; Write-Step "$n/$total Saving your DNS"
    Save-NetworkBackup $dns
    $n++; Write-Step "$n/$total Winsock and TCP/IP"
    Reset-Winsock
    if ($hasManualIp) { Write-Host '  [--] TCP/IP skipped (manual IP)' -ForegroundColor DarkGray } else { Reset-TcpIp }
    $n++; Write-Step "$n/$total Putting your DNS back"
    Restore-NetworkBackup $dns
}
$n++; Write-Step "$n/$total Caches"
Clear-NetworkCaches
$n++; Write-Step "$n/$total IP address"
Update-IpAddress

# --- Result
Write-Step 'Testing the internet'
Start-Sleep -Seconds 3      # the renewed adapter takes a moment to be ready
if (Test-Internet) { Write-Result 'OK' 'internet is working' }
else { Write-Result 'WARN' 'no internet yet' }

if ($full) {
    Write-Host "`nDone. Restart the PC to finish the reset." -ForegroundColor Green
    if (Ask 'Restart now?' $false) { Restart-Computer -Force }
} else {
    Write-Host "`nDone." -ForegroundColor Green
    Write-Host '  Still not working? Run it again and choose Full, or restart the router.' -ForegroundColor DarkGray
}

#endregion
