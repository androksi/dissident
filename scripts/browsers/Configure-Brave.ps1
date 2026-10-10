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
        Write-Host '  [ERRO] ' -ForegroundColor Red -NoNewline
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
            $answer = "$(Read-Host "  Número [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host "  Digite um número de 1 a $($Options.Count)." -ForegroundColor DarkYellow
        }
    }
    Write-Host '  (use as setas ↑ ↓ e Enter)' -ForegroundColor DarkGray
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
    Set-Policy 'BraveWalletDisabled'        1 'Wallet (web3, DNS descentralizado): off'
    Set-Policy 'BraveVPNDisabled'           1 'VPN: off'
    Set-Policy 'BraveRewardsDisabled'       1 'Recompensas (BAT e anúncios): off'
    Set-Policy 'BraveAIChatEnabled'         0 'Leo (assistente de IA): off'
    Set-Policy 'BraveNewsDisabled'          1 'Brave News na nova guia: off'
    Set-Policy 'BraveTalkDisabled'          1 'Brave Talk (videochamadas): off'
    Set-Policy 'BravePlaylistEnabled'       0 'Playlist: off'
    Set-Policy 'BraveWaybackMachineEnabled' 0 'Aviso do Internet Archive em 404: off'
    Set-Policy 'TorDisabled'                1 'Janela privada com Tor: off'
    Set-Policy 'BraveSpeedreaderEnabled'    0 'Speedreader (modo leitura): off'
}

function Set-BraveTelemetry {
    Set-Policy 'BraveP3AEnabled'            0 'Análises de uso do produto (P3A): off'
    Set-Policy 'BraveStatsPingEnabled'      0 'Ping diário de uso: off'
    Set-Policy 'BraveWebDiscoveryEnabled'   0 'Web Discovery Project: off'
}

function Set-ChromiumPolicies {
    Set-Policy 'MetricsReportingEnabled'                 0 'Relatórios de uso e falhas: off'
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Coleta anônima de URLs: off'
    Set-Policy 'FeedbackSurveysEnabled'                  0 'Pesquisas de feedback: off'
    Set-Policy 'PromotionalTabsEnabled'                  0 'Guias promocionais/boas-vindas: off'
    Set-Policy 'BackgroundModeEnabled'                   0 'Rodar em segundo plano ao fechar: off'
    Set-Policy 'ShoppingListEnabled'                     0 'Lista de compras: off'
}

# Installing sites as apps (the "monitor with arrow" icon in the address bar), password saving
# (Bitwarden handles it) and saved payment cards. Chromium policies, also honored by Brave.
function Set-AppsAndAutofill {
    Set-Policy 'WebAppInstallByUserEnabled'              0 'Instalar sites como app (ícone na barra): off'
    Set-Policy 'PasswordManagerEnabled'                  0 'Gerenciador de senhas do Brave: off'
    Set-Policy 'AutofillCreditCardEnabled'               0 'Salvar/preencher cartões: off'
}

# "Cast" to TV (Chromecast). To find TVs, Brave listens on the local network (mDNS, UDP 5353) the first
# time a page with video opens, and Windows Firewall asks for permission. Chrome's installer adds a firewall
# rule for this ("Google Chrome (mDNS-In)"); Brave's does not. Either choice below avoids the prompt:
#   keep Cast    → the same rule Chrome uses is created for brave.exe
#   disable Cast → EnableMediaRouter = 0, Brave never listens (and the rule is removed, if present)
$FirewallRuleName = 'Brave (mDNS-In)'

function Set-CastToTv([bool]$Disable, [string]$BraveExe) {
    if ($Disable) {
        Set-Policy 'EnableMediaRouter' 0 'Transmitir para TV (Chromecast): off'
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
        Write-Host ("{0,-42}" -f 'Transmitir para TV: mantido; firewall liberado') -NoNewline
        Write-Host "regra '$FirewallRuleName' (UDP 5353)" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERRO] ' -ForegroundColor Red -NoNewline
        Write-Host "Regra do firewall ($FirewallRuleName): $($_.Exception.Message)"
    }
}

#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step 'Removendo as políticas do Brave'
    if (Test-Path $B) {
        (Get-Item $B).Property | ForEach-Object { Write-Host "  [removida] $_" -ForegroundColor DarkGray }
        Remove-Item $B -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nPronto. Feche e abra o Brave." -ForegroundColor Green
    } else {
        Write-Host '  Nenhuma política do Brave encontrada; nada a fazer.'
    }
    if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $FirewallRuleName
        Write-Host "  [removida] regra do firewall '$FirewallRuleName'" -ForegroundColor DarkGray
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
    Write-Host 'Brave não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.' -ForegroundColor DarkYellow
    $installed = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"   # default install path
}

Write-Host "`nConfigure-Brave" -ForegroundColor Green

# --- Question
$castOptions = @(
    'Manter "Transmitir para TV"',
    'Desligar "Transmitir para TV"'
)
$disableCast = (Choose 'Transmitir para TV (Chromecast):' $castOptions 0) -eq 1

# --- Apply
Write-Step 'Recursos do Brave';     Set-BraveFeatures
Write-Step 'Telemetria do Brave';   Set-BraveTelemetry
Write-Step 'Políticas do Chromium'; Set-ChromiumPolicies
Write-Step 'Apps, senhas e cartões'; Set-AppsAndAutofill
Write-Step 'Transmitir para TV';    Set-CastToTv $disableCast $installed

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima." -ForegroundColor Yellow }
Write-Host "`nPronto. Feche e abra o Brave (ou confira em brave://policy)." -ForegroundColor Green
if (Get-Process brave -ErrorAction SilentlyContinue) {
    Write-Host 'O Brave está aberto: feche todas as janelas dele para as mudanças valerem.' -ForegroundColor DarkYellow
}
Write-Host @'

Ajustes que não têm política (faça uma vez dentro do Brave):
  - brave://settings/newTab     -> desligue imagens patrocinadas, estatísticas e cartões
  - brave://settings/appearance -> "Mostrar barra lateral": Nunca; ligue "Mostrar URLs completos"
  - brave://settings/search     -> mecanismo de pesquisa padrão: Google
  - brave://settings/system     -> ligue "Economia de memória"
'@

#endregion
