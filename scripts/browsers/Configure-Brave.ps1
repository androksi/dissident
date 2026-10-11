#Requires -RunAsAdministrator
<#
    Configure-Brave.ps1 — a clean Brave: no Wallet, VPN, Rewards, Leo, News, Talk, Playlist, Tor, Speedreader or telemetry

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Brave.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Brave.ps1 -Revert
    Add -Lang en or -Lang pt to skip the language question.

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
    [switch]$Revert,
    [ValidateSet('en', 'pt')][string]$Lang
)

$ErrorActionPreference = 'Continue'
$B = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'


#region ==================== 1. HELPERS ====================

$script:Failures = 0

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

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
        Write-Host (T '  [ERROR] ' '  [ERRO] ') -ForegroundColor Red -NoNewline
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
            $answer = "$(Read-Host "  $(T 'Number' 'Número') [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host (T "  Type a number from 1 to $($Options.Count)." "  Digite um número de 1 a $($Options.Count).") -ForegroundColor DarkYellow
        }
    }
    Write-Host (T '  (use the arrows ↑ ↓ and Enter)' '  (use as setas ↑ ↓ e Enter)') -ForegroundColor DarkGray
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

#endregion


#region ==================== 2. POLICIES ====================

function Set-BraveFeatures {
    Set-Policy 'BraveWalletDisabled'        1 (T 'Wallet (web3, decentralized DNS): off' 'Wallet (web3, DNS descentralizado): off')
    Set-Policy 'BraveVPNDisabled'           1 'VPN: off'
    Set-Policy 'BraveRewardsDisabled'       1 (T 'Rewards (BAT and ads): off' 'Recompensas (BAT e anúncios): off')
    Set-Policy 'BraveAIChatEnabled'         0 (T 'Leo (AI assistant): off' 'Leo (assistente de IA): off')
    Set-Policy 'BraveNewsDisabled'          1 (T 'Brave News on the new tab: off' 'Brave News na nova guia: off')
    Set-Policy 'BraveTalkDisabled'          1 (T 'Brave Talk (video calls): off' 'Brave Talk (videochamadas): off')
    Set-Policy 'BravePlaylistEnabled'       0 'Playlist: off'
    Set-Policy 'BraveWaybackMachineEnabled' 0 (T 'Internet Archive prompt on 404 pages: off' 'Aviso do Internet Archive em 404: off')
    Set-Policy 'TorDisabled'                1 (T 'Private window with Tor: off' 'Janela privada com Tor: off')
    Set-Policy 'BraveSpeedreaderEnabled'    0 (T 'Speedreader (reader mode): off' 'Speedreader (modo leitura): off')
}

function Set-BraveTelemetry {
    Set-Policy 'BraveP3AEnabled'            0 (T 'Product usage analytics (P3A): off' 'Análises de uso do produto (P3A): off')
    Set-Policy 'BraveStatsPingEnabled'      0 (T 'Daily usage ping: off' 'Ping diário de uso: off')
    Set-Policy 'BraveWebDiscoveryEnabled'   0 'Web Discovery Project: off'
}

function Set-ChromiumPolicies {
    Set-Policy 'MetricsReportingEnabled'                 0 (T 'Usage and crash reports: off' 'Relatórios de uso e falhas: off')
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 (T 'Anonymous URL collection: off' 'Coleta anônima de URLs: off')
    Set-Policy 'FeedbackSurveysEnabled'                  0 (T 'Feedback surveys: off' 'Pesquisas de feedback: off')
    Set-Policy 'PromotionalTabsEnabled'                  0 (T 'Promotional/welcome tabs: off' 'Guias promocionais/boas-vindas: off')
    Set-Policy 'BackgroundModeEnabled'                   0 (T 'Run in background when closed: off' 'Rodar em segundo plano ao fechar: off')
    Set-Policy 'ShoppingListEnabled'                     0 (T 'Shopping list: off' 'Lista de compras: off')
    Set-Policy 'DefaultBrowserSettingEnabled'            0 (T '"Not your default browser" prompt: off' 'Aviso "não é o navegador padrão": off')
}

# Installing sites as apps (the "monitor with arrow" icon in the address bar), password saving
# (Bitwarden handles it) and saved payment cards. Chromium policies, also honored by Brave.
function Set-AppsAndAutofill {
    Set-Policy 'WebAppInstallByUserEnabled'              0 (T 'Install sites as apps (address bar icon): off' 'Instalar sites como app (ícone na barra): off')
    Set-Policy 'PasswordManagerEnabled'                  0 (T 'Brave password manager: off' 'Gerenciador de senhas do Brave: off')
    Set-Policy 'AutofillCreditCardEnabled'               0 (T 'Save/fill payment cards: off' 'Salvar/preencher cartões: off')
}

# "Cast" to TV (Chromecast). To find TVs, Brave listens on the local network (mDNS, UDP 5353) the first
# time a page with video opens, and Windows Firewall asks for permission. Chrome's installer adds a firewall
# rule for this ("Google Chrome (mDNS-In)"); Brave's does not. Either choice below avoids the prompt:
#   keep Cast    → the same rule Chrome uses is created for brave.exe
#   disable Cast → EnableMediaRouter = 0, Brave never listens (and the rule is removed, if present)
$FirewallRuleName = 'Brave (mDNS-In)'

function Set-CastToTv([bool]$Disable, [string]$BraveExe) {
    if ($Disable) {
        Set-Policy 'EnableMediaRouter' 0 (T 'Cast to TV (Chromecast): off' 'Transmitir para TV (Chromecast): off')
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
        Write-Host ("{0,-42}" -f (T 'Cast to TV: kept; firewall allowed' 'Transmitir para TV: mantido; firewall liberado')) -NoNewline
        Write-Host (T "rule '$FirewallRuleName' (UDP 5353)" "regra '$FirewallRuleName' (UDP 5353)") -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host (T '  [ERROR] ' '  [ERRO] ') -ForegroundColor Red -NoNewline
        Write-Host (T "Firewall rule ($FirewallRuleName): $($_.Exception.Message)" "Regra do firewall ($FirewallRuleName): $($_.Exception.Message)")
    }
}

#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step (T 'Removing Brave policies' 'Removendo as políticas do Brave')
    if (Test-Path $B) {
        (Get-Item $B).Property | ForEach-Object { Write-Host (T "  [removed] $_" "  [removida] $_") -ForegroundColor DarkGray }
        Remove-Item $B -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host (T "`nDone. Close and reopen Brave." "`nPronto. Feche e abra o Brave.") -ForegroundColor Green
    } else {
        Write-Host (T '  No Brave policies found; nothing to do.' '  Nenhuma política do Brave encontrada; nada a fazer.')
    }
    if (Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $FirewallRuleName
        Write-Host (T "  [removed] firewall rule '$FirewallRuleName'" "  [removida] regra do firewall '$FirewallRuleName'") -ForegroundColor DarkGray
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
    Write-Host (T 'Brave not found. The policies will be applied anyway and take effect when you install it.' 'Brave não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.') -ForegroundColor DarkYellow
    $installed = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"   # default install path
}

Write-Host "`nConfigure-Brave" -ForegroundColor Green

# --- Question
$castOptions = @(
    (T 'Keep "Cast to TV"' 'Manter "Transmitir para TV"'),
    (T 'Turn off "Cast to TV"' 'Desligar "Transmitir para TV"')
)
$disableCast = (Choose (T 'Cast to TV (Chromecast):' 'Transmitir para TV (Chromecast):') $castOptions 0) -eq 1

# --- Apply
Write-Step (T 'Brave features' 'Recursos do Brave');     Set-BraveFeatures
Write-Step (T 'Brave telemetry' 'Telemetria do Brave');   Set-BraveTelemetry
Write-Step (T 'Chromium policies' 'Políticas do Chromium'); Set-ChromiumPolicies
Write-Step (T 'Apps, passwords and cards' 'Apps, senhas e cartões'); Set-AppsAndAutofill
Write-Step (T 'Cast to TV' 'Transmitir para TV');    Set-CastToTv $disableCast $installed

# --- Done
if ($script:Failures) { Write-Host (T "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima.") -ForegroundColor Yellow }
Write-Host (T "`nDone. Close and reopen Brave (or check brave://policy)." "`nPronto. Feche e abra o Brave (ou confira em brave://policy).") -ForegroundColor Green
if (Get-Process brave -ErrorAction SilentlyContinue) {
    Write-Host (T 'Brave is open: close all of its windows for the changes to take effect.' 'O Brave está aberto: feche todas as janelas dele para as mudanças valerem.') -ForegroundColor DarkYellow
}
if ($script:Lang -eq 'pt') {
Write-Host @'

Ajustes que não têm política (faça uma vez dentro do Brave):
  - brave://settings/newTab     -> desligue imagens patrocinadas, estatísticas e cartões
  - brave://settings/appearance -> "Mostrar barra lateral": Nunca; ligue "Mostrar URLs completos"
  - brave://settings/search     -> mecanismo de pesquisa padrão: Google
  - brave://settings/system     -> ligue "Economia de memória"
'@
} else {
Write-Host @'

Settings with no policy (do these once inside Brave):
  - brave://settings/newTab     -> turn off sponsored images, stats and cards
  - brave://settings/appearance -> "Show sidebar": Never; turn on "Always show full URLs"
  - brave://settings/search     -> default search engine: Google
  - brave://settings/system     -> turn on "Memory Saver"
'@
}

#endregion
