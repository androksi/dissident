#Requires -RunAsAdministrator
<#
    Reset-Network.ps1 — fixes common internet problems with Windows' own network commands, keeping your DNS

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Reset-Network.ps1
    Add -Lang en or -Lang pt to skip the language question.

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
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

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

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @((T 'Yes' 'Sim'), (T 'No' 'Não')) $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Result line: [OK] text / [WARNING] text / [ERROR] text
function Write-Result([ValidateSet('OK', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $label, $color = switch ($Status) {
        'OK'    { '[OK]', 'Green' }
        'WARN'  { (T '[WARNING]' '[ATENÇÃO]'), 'Yellow' }
        'ERROR' { (T '[ERROR]' '[ERRO]'), 'Red' }
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning (T 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).')
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
    Write-Result 'OK' (T "DNS saved to $BackupDir" "DNS salvo em $BackupDir")
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
    else { Write-Result 'WARN' (T 'TCP/IP: done, with some items Windows did not let it change (normal)' 'TCP/IP: feito, com alguns itens que o Windows não deixou mudar (normal)') }
    Remove-Item $log -Force -ErrorAction SilentlyContinue
}

function Restore-NetworkBackup($Dns) {
    Restore-ManualDns $Dns
    $doh = Join-Path $BackupDir 'doh.reg'
    if (Test-Path $doh) { & reg.exe import $doh *> $null }
    $now = @(Get-ManualDns)
    $missing = @($Dns | Where-Object { $s = $_; -not ($now | Where-Object { $_.Guid -eq $s.Guid -and $_.Family -eq $s.Family -and $_.Servers -eq $s.Servers }) })
    if ($missing) { Write-Result 'ERROR' (T "DNS not restored on $($missing.Count) interface(s); the backup is in $BackupDir" "DNS não restaurado em $($missing.Count) interface(s); o backup está em $BackupDir") }
    elseif ($Dns) { Write-Result 'OK' (T 'your DNS servers are back' 'seus servidores DNS estão de volta') }
}

function Clear-NetworkCaches {
    Clear-DnsClientCache
    & netsh interface ip delete arpcache *> $null
    Write-Result 'OK' (T 'DNS and ARP caches cleared' 'caches de DNS e ARP limpos')
}

# New IP from the router, only on adapters with an automatic IP (ipconfig skips the others).
function Update-IpAddress {
    Write-Host (T '  getting a new IP from the router (the connection drops for a few seconds)...' '  pedindo um IP novo ao roteador (a conexão cai por alguns segundos)...') -ForegroundColor DarkGray
    & ipconfig /release *> $null
    & ipconfig /renew *> $null
    Write-Result 'OK' (T 'new IP requested' 'IP novo pedido')
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Host "`nReset-Network" -ForegroundColor Green
Write-Host (T '  Fixes common internet problems with Windows'' own commands. Your DNS is kept.' '  Corrige problemas comuns de internet com os comandos do próprio Windows. Seu DNS é mantido.') -ForegroundColor DarkGray

# --- What is on this PC
$dns = @(Get-ManualDns)
$adapters = @(Get-AdapterInfo $dns)
Write-Host (T "`n  Network adapters:" "`n  Adaptadores de rede:")
if (-not $adapters) { Write-Host (T '    (no physical adapter found)' '    (nenhum adaptador físico encontrado)') -ForegroundColor DarkGray }
foreach ($a in $adapters) {
    $state = if ($a.Connected) { T 'connected' 'conectado' } else { T 'not connected' 'desconectado' }
    $ip    = if ($a.ManualIp) { T 'manual IP' 'IP manual' } else { T 'automatic IP' 'IP automático' }
    $dnsTx = if ($a.Dns) { (T 'DNS ' 'DNS ') + ($a.Dns -join ', ') + (T ' (kept)' ' (mantido)') } else { T 'DNS from the router' 'DNS do roteador' }
    Write-Host ("    {0,-22} {1,-14} {2,-14} {3}" -f $a.Name, $state, $ip, $dnsTx)
}
$hasManualIp = [bool]($adapters | Where-Object ManualIp)

# --- Questions
Write-Host ''
$levels = @(
    (T 'Quick: clear DNS/ARP caches and get a new IP (no restart)' 'Rápido: limpar caches de DNS/ARP e pegar um IP novo (sem reiniciar)'),
    (T 'Full: also reset Winsock and TCP/IP (needs a restart)' 'Completo: também redefinir o Winsock e o TCP/IP (precisa reiniciar)')
)
$full = (Choose (T 'What to do?' 'O que fazer?') $levels 0) -eq 1
if ($full -and $hasManualIp) {
    Write-Host (T '  A network adapter has a manual IP: the TCP/IP reset will be skipped so it is not erased.' '  Um adaptador tem IP manual: o reset do TCP/IP será pulado para não apagá-lo.') -ForegroundColor Yellow
}
if ($env:SESSIONNAME -like 'RDP*') {
    Write-Host (T '  You are connected through Remote Desktop: the session will drop and may not come back by itself.' '  Você está conectado pela Área de Trabalho Remota: a sessão vai cair e pode não voltar sozinha.') -ForegroundColor Yellow
    if (-not (Ask (T 'Continue anyway?' 'Continuar mesmo assim?') $false)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }
}
Write-Host (T '  Close downloads and calls first: the connection drops for a few seconds.' '  Feche downloads e chamadas antes: a conexão cai por alguns segundos.') -ForegroundColor DarkGray
if (-not (Ask (T 'Reset the network now?' 'Redefinir a rede agora?') $true)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }

# --- Steps (the quick ones don't touch the DNS settings, so only the full reset saves and restores them)
$total = if ($full) { 5 } else { 2 }; $n = 0
if ($full) {
    $n++; Write-Step (T "$n/$total Saving your DNS" "$n/$total Salvando seu DNS")
    Save-NetworkBackup $dns
    $n++; Write-Step (T "$n/$total Winsock and TCP/IP" "$n/$total Winsock e TCP/IP")
    Reset-Winsock
    if ($hasManualIp) { Write-Host (T '  [--] TCP/IP skipped (manual IP)' '  [--] TCP/IP pulado (IP manual)') -ForegroundColor DarkGray } else { Reset-TcpIp }
    $n++; Write-Step (T "$n/$total Putting your DNS back" "$n/$total Devolvendo seu DNS")
    Restore-NetworkBackup $dns
}
$n++; Write-Step (T "$n/$total Caches" "$n/$total Caches")
Clear-NetworkCaches
$n++; Write-Step (T "$n/$total IP address" "$n/$total Endereço IP")
Update-IpAddress

# --- Result
Write-Step (T 'Testing the internet' 'Testando a internet')
Start-Sleep -Seconds 3      # the renewed adapter takes a moment to be ready
if (Test-Internet) { Write-Result 'OK' (T 'internet is working' 'a internet está funcionando') }
else { Write-Result 'WARN' (T 'no internet yet' 'ainda sem internet') }

if ($full) {
    Write-Host (T "`nDone. Restart the PC to finish the reset." "`nPronto. Reinicie o PC para concluir a redefinição.") -ForegroundColor Green
    if (Ask (T 'Restart now?' 'Reiniciar agora?') $false) { Restart-Computer -Force }
} else {
    Write-Host (T "`nDone." "`nPronto.") -ForegroundColor Green
    Write-Host (T '  Still not working? Run it again and choose Full, or restart the router.' '  Ainda não funciona? Rode de novo e escolha Completo, ou reinicie o roteador.') -ForegroundColor DarkGray
}

#endregion
