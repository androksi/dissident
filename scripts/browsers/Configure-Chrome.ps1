#Requires -RunAsAdministrator
<#
    Configure-Chrome.ps1 — a more private Chrome without breaking the Google account sign-in
    (Gmail, Drive and "Sign in with Google" on other sites keep working)

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1 -Revert

    Uses Chrome's official policies (chromeenterprise.google/policies). They apply to every
    profile, even if Chrome is installed later. Close and reopen Chrome to apply. It will show
    "Managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.

    Does NOT touch: Google account sign-in, Safe Browsing (stays on Standard),
    leaked password checks, password manager and updates.

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
$C = 'HKLM:\SOFTWARE\Policies\Google\Chrome'


#region ==================== 1. HELPERS ====================

$script:Failures = 0

# Writes a policy (DWORD) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$Name, [int]$Value, [string]$Description) {
    try {
        if (-not (Test-Path $C)) { New-Item -Path $C -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $C -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Ok $Description "$Name = $Value"
    } catch { Write-Fail $Description $Name $_ }
}

# List policies live in a subkey with values "1", "2", "3"... (recreated from scratch).
function Set-PolicyList([string]$Name, [string[]]$Items, [string]$Description) {
    try {
        $key = "$C\$Name"
        if (Test-Path $key) { Remove-Item $key -Recurse -Force -ErrorAction Stop }
        New-Item -Path $key -Force -ErrorAction Stop | Out-Null
        for ($i = 0; $i -lt $Items.Count; $i++) {
            New-ItemProperty -Path $key -Name ($i + 1) -Value $Items[$i] -PropertyType String -Force -ErrorAction Stop | Out-Null
        }
        Write-Ok $Description "$Name = $($Items -join ', ')"
    } catch { Write-Fail $Description $Name $_ }
}

function Write-Ok([string]$Description, [string]$Detail) {
    Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
    Write-Host ("{0,-46}" -f $Description) -NoNewline
    Write-Host $Detail -ForegroundColor DarkGray
}

function Write-Fail([string]$Description, [string]$Name, $ErrorRecord) {
    $script:Failures++
    Write-Host '  [ERRO] ' -ForegroundColor Red -NoNewline
    Write-Host "$Description ($Name): $($ErrorRecord.Exception.Message)"
}

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

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

# Yes/no question shown as a "Sim / Não" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Sim', 'Não') $(if ($Default) { 0 } else { 1 })) -eq 0
}

#endregion


#region ==================== 2. POLICIES ====================

function Set-Telemetry([bool]$NoSearchSuggestions, [bool]$NoPrefetch) {
    Set-Policy 'MetricsReportingEnabled'                 0 'Relatórios de uso e falhas: off'
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Envio das URLs visitadas: off'
    Set-Policy 'SpellCheckServiceEnabled'                0 'Correção ortográfica na nuvem: off (local fica)'
    Set-Policy 'AlternateErrorPagesEnabled'              0 'Sugestões em páginas de erro: off'
    Set-Policy 'FeedbackSurveysEnabled'                  0 'Pesquisas de satisfação: off'
    Set-Policy 'SafeBrowsingSurveysEnabled'              0 'Pesquisas da Navegação Segura: off'
    Set-Policy 'UserFeedbackAllowed'                     0 'Enviar feedback ao Google: off'
    if ($NoSearchSuggestions) { Set-Policy 'SearchSuggestEnabled'     0 'Sugestões de pesquisa: off' }
    if ($NoPrefetch)          { Set-Policy 'NetworkPredictionOptions' 2 'Pré-carregamento de páginas: off' }
}

function Set-AI {
    Set-Policy 'GenAiDefaultSettings'                    2 'Recursos de IA (padrão geral): off'
    Set-Policy 'GeminiSettings'                          1 'Gemini no Chrome: off'
    Set-Policy 'GeminiActOnWebSettings'                  1 'Gemini agindo nas páginas: off'
    Set-Policy 'GeminiSparkSettings'                     1 'Gemini Spark: off'
    Set-Policy 'AIModeSettings'                          1 'Modo IA na barra de endereço: off'
    Set-Policy 'ThirdPartyAiChatSettings'                1 'IA de terceiros na barra de endereço: off'
    Set-Policy 'SearchContentSharingSettings'            1 'Enviar conteúdo da página ao Modo IA: off'
    Set-Policy 'SmartTabSharingSettings'                 1 'Compartilhar abas com o Modo IA: off'
    Set-Policy 'HelpMeWriteSettings'                     2 '"Me ajude a escrever": off'
    Set-Policy 'TabCompareSettings'                      2 'Comparar abas com IA: off'
    Set-Policy 'HistorySearchSettings'                   2 'Busca no histórico com IA: off'
    Set-Policy 'CreateThemesSettings'                    2 'Criar temas com IA: off'
    Set-Policy 'AutofillPredictionSettings'              2 'Preenchimento automático com IA: off'
    Set-Policy 'GenAILocalFoundationalModelSettings'     1 'Baixar modelo de IA local (~GBs): off'
}

# Blocks third-party cookies, with an exception for Google so that "Sign in with Google"
# and Drive embedded in other sites keep working.
function Set-Cookies {
    Set-Policy 'BlockThirdPartyCookies' 1 'Cookies de terceiros: bloqueados'
    Set-PolicyList 'CookiesAllowedForUrls' @('https://[*.]google.com', 'https://[*.]google.com.br', 'https://[*.]googleusercontent.com') `
                                          'Exceção: domínios do Google liberados'
}

function Set-Extras {
    Set-Policy 'SyncDisabled'                            1 'Sincronização: bloqueada (login continua)'
    Set-Policy 'SafeBrowsingProtectionLevel'             1 'Navegação Segura: modo Padrão'
    Set-Policy 'BackgroundModeEnabled'                   0 'Rodar em segundo plano ao fechar: off'
    Set-Policy 'ShoppingListEnabled'                     0 'Lista de compras/preços: off'
    Set-Policy 'DefaultBrowserSettingEnabled'            0 'Aviso "não é o navegador padrão": off'
}

#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step 'Removendo as políticas do Chrome'
    if (Test-Path $C) {
        (Get-Item $C).Property | ForEach-Object { Write-Host "  [removida] $_" -ForegroundColor DarkGray }
        Get-ChildItem $C | ForEach-Object { Write-Host "  [removida] $($_.PSChildName)" -ForegroundColor DarkGray }
        Remove-Item $C -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nPronto. Feche e abra o Chrome." -ForegroundColor Green
    } else {
        Write-Host '  Nenhuma política do Chrome encontrada; nada a fazer.'
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$installed = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Chrome não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.' -ForegroundColor DarkYellow
}

# --- Questions
Write-Host "`nConfigure-Chrome" -ForegroundColor Green
Write-Host '  Duas escolhas (setas e Enter; o padrão já vem selecionado):'
$noSearchSuggestions = Ask 'Desativar as sugestões de pesquisa enquanto digita? (o que você digita na barra vai ao Google em tempo real)' $false
$noPrefetch          = Ask 'Desativar o pré-carregamento de páginas? (sites ficam sabendo de links que você nem abriu; abrir páginas fica um pouco mais lento)' $true

# --- Apply
Write-Step 'Telemetria e dados enviados ao Google';             Set-Telemetry $noSearchSuggestions $noPrefetch
Write-Step 'Inteligência artificial (Gemini e recursos de IA)'; Set-AI
Write-Step 'Cookies de terceiros (rastreamento entre sites)';   Set-Cookies
Write-Step 'Sincronização, segundo plano e extras';             Set-Extras

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima." -ForegroundColor Yellow }
Write-Host "`nPronto. Feche e abra o Chrome (ou confira em chrome://policy)." -ForegroundColor Green
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host 'O Chrome está aberto: feche todas as janelas dele para as mudanças valerem.' -ForegroundColor DarkYellow
}
Write-Host @'

Fora do Chrome, também vale revisar na sua conta Google (myaccount.google.com/data-and-privacy):
  - "Atividade na Web e de apps"  -> pausar ou ativar a exclusão automática
  - "Minha central de anúncios"   -> desligar anúncios personalizados
'@

#endregion
