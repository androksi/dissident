#Requires -RunAsAdministrator
<#
    Configure-Chrome.ps1 — a more private Chrome without breaking the Google account sign-in
    (Gmail, Drive and "Sign in with Google" on other sites keep working)

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Chrome.ps1 -Revert
    Add -Lang en or -Lang pt to skip the language question.

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
    [switch]$Revert,
    [ValidateSet('en', 'pt')][string]$Lang
)

$ErrorActionPreference = 'Continue'
$C = 'HKLM:\SOFTWARE\Policies\Google\Chrome'


#region ==================== 1. HELPERS ====================

$script:Failures = 0

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

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
    Write-Host (T '  [ERROR] ' '  [ERRO] ') -ForegroundColor Red -NoNewline
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

#endregion


#region ==================== 2. POLICIES ====================

function Set-Telemetry([bool]$NoSearchSuggestions, [bool]$NoPrefetch) {
    Set-Policy 'MetricsReportingEnabled'                 0 (T 'Usage and crash reports: off' 'Relatórios de uso e falhas: off')
    Set-Policy 'UrlKeyedAnonymizedDataCollectionEnabled' 0 (T 'Sending visited URLs: off' 'Envio das URLs visitadas: off')
    Set-Policy 'SpellCheckServiceEnabled'                0 (T 'Cloud spell check: off (local stays)' 'Correção ortográfica na nuvem: off (local fica)')
    Set-Policy 'AlternateErrorPagesEnabled'              0 (T 'Suggestions on error pages: off' 'Sugestões em páginas de erro: off')
    Set-Policy 'FeedbackSurveysEnabled'                  0 (T 'Satisfaction surveys: off' 'Pesquisas de satisfação: off')
    Set-Policy 'SafeBrowsingSurveysEnabled'              0 (T 'Safe Browsing surveys: off' 'Pesquisas da Navegação Segura: off')
    Set-Policy 'UserFeedbackAllowed'                     0 (T 'Send feedback to Google: off' 'Enviar feedback ao Google: off')
    if ($NoSearchSuggestions) { Set-Policy 'SearchSuggestEnabled'     0 (T 'Search suggestions: off' 'Sugestões de pesquisa: off') }
    if ($NoPrefetch)          { Set-Policy 'NetworkPredictionOptions' 2 (T 'Page preloading: off' 'Pré-carregamento de páginas: off') }
}

function Set-AI {
    Set-Policy 'GenAiDefaultSettings'                    2 (T 'AI features (general default): off' 'Recursos de IA (padrão geral): off')
    Set-Policy 'GeminiSettings'                          1 (T 'Gemini in Chrome: off' 'Gemini no Chrome: off')
    Set-Policy 'GeminiActOnWebSettings'                  1 (T 'Gemini acting on pages: off' 'Gemini agindo nas páginas: off')
    Set-Policy 'GeminiSparkSettings'                     1 'Gemini Spark: off'
    Set-Policy 'AIModeSettings'                          1 (T 'AI Mode in the address bar: off' 'Modo IA na barra de endereço: off')
    Set-Policy 'ThirdPartyAiChatSettings'                1 (T 'Third-party AI in the address bar: off' 'IA de terceiros na barra de endereço: off')
    Set-Policy 'SearchContentSharingSettings'            1 (T 'Send page content to AI Mode: off' 'Enviar conteúdo da página ao Modo IA: off')
    Set-Policy 'SmartTabSharingSettings'                 1 (T 'Share tabs with AI Mode: off' 'Compartilhar abas com o Modo IA: off')
    Set-Policy 'HelpMeWriteSettings'                     2 (T '"Help me write": off' '"Me ajude a escrever": off')
    Set-Policy 'TabCompareSettings'                      2 (T 'Tab compare with AI: off' 'Comparar abas com IA: off')
    Set-Policy 'HistorySearchSettings'                   2 (T 'AI history search: off' 'Busca no histórico com IA: off')
    Set-Policy 'CreateThemesSettings'                    2 (T 'Create themes with AI: off' 'Criar temas com IA: off')
    Set-Policy 'AutofillPredictionSettings'              2 (T 'AI-powered autofill: off' 'Preenchimento automático com IA: off')
    Set-Policy 'GenAILocalFoundationalModelSettings'     1 (T 'Download local AI model (~GBs): off' 'Baixar modelo de IA local (~GBs): off')
}

# Blocks third-party cookies, with an exception for Google so that "Sign in with Google"
# and Drive embedded in other sites keep working.
function Set-Cookies {
    Set-Policy 'BlockThirdPartyCookies' 1 (T 'Third-party cookies: blocked' 'Cookies de terceiros: bloqueados')
    Set-PolicyList 'CookiesAllowedForUrls' @('https://[*.]google.com', 'https://[*.]google.com.br', 'https://[*.]googleusercontent.com') `
                                          (T 'Exception: Google domains allowed' 'Exceção: domínios do Google liberados')
}

function Set-Extras {
    Set-Policy 'SyncDisabled'                            1 (T 'Sync: blocked (sign-in still works)' 'Sincronização: bloqueada (login continua)')
    Set-Policy 'SafeBrowsingProtectionLevel'             1 (T 'Safe Browsing: Standard mode' 'Navegação Segura: modo Padrão')
    Set-Policy 'BackgroundModeEnabled'                   0 (T 'Run in background when closed: off' 'Rodar em segundo plano ao fechar: off')
    Set-Policy 'ShoppingListEnabled'                     0 (T 'Shopping list and price tracking: off' 'Lista de compras/preços: off')
    Set-Policy 'DefaultBrowserSettingEnabled'            0 (T '"Not your default browser" prompt: off' 'Aviso "não é o navegador padrão": off')
}

#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step (T 'Removing Chrome policies' 'Removendo as políticas do Chrome')
    if (Test-Path $C) {
        (Get-Item $C).Property | ForEach-Object { Write-Host (T "  [removed] $_" "  [removida] $_") -ForegroundColor DarkGray }
        Get-ChildItem $C | ForEach-Object { Write-Host (T "  [removed] $($_.PSChildName)" "  [removida] $($_.PSChildName)") -ForegroundColor DarkGray }
        Remove-Item $C -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host (T "`nDone. Close and reopen Chrome." "`nPronto. Feche e abra o Chrome.") -ForegroundColor Green
    } else {
        Write-Host (T '  No Chrome policies found; nothing to do.' '  Nenhuma política do Chrome encontrada; nada a fazer.')
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
    Write-Host (T 'Chrome not found. The policies will be applied anyway and take effect when you install it.' 'Chrome não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.') -ForegroundColor DarkYellow
}

# --- Questions
Write-Host "`nConfigure-Chrome" -ForegroundColor Green
Write-Host (T '  Two choices (arrows and Enter; the default is already selected):' '  Duas escolhas (setas e Enter; o padrão já vem selecionado):')
$noSearchSuggestions = Ask (T 'Turn off search suggestions while typing? (what you type in the address bar goes to Google in real time)' 'Desativar as sugestões de pesquisa enquanto digita? (o que você digita na barra vai ao Google em tempo real)') $false
$noPrefetch          = Ask (T 'Turn off page preloading? (sites learn about links you never opened; pages open a little slower)' 'Desativar o pré-carregamento de páginas? (sites ficam sabendo de links que você nem abriu; abrir páginas fica um pouco mais lento)') $true

# --- Apply
Write-Step (T 'Telemetry and data sent to Google' 'Telemetria e dados enviados ao Google');             Set-Telemetry $noSearchSuggestions $noPrefetch
Write-Step (T 'Artificial intelligence (Gemini and AI features)' 'Inteligência artificial (Gemini e recursos de IA)'); Set-AI
Write-Step (T 'Third-party cookies (cross-site tracking)' 'Cookies de terceiros (rastreamento entre sites)');   Set-Cookies
Write-Step (T 'Sync, background and extras' 'Sincronização, segundo plano e extras');             Set-Extras

# --- Done
if ($script:Failures) { Write-Host (T "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima.") -ForegroundColor Yellow }
Write-Host (T "`nDone. Close and reopen Chrome (or check chrome://policy)." "`nPronto. Feche e abra o Chrome (ou confira em chrome://policy).") -ForegroundColor Green
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host (T 'Chrome is open: close all of its windows for the changes to take effect.' 'O Chrome está aberto: feche todas as janelas dele para as mudanças valerem.') -ForegroundColor DarkYellow
}
if ($script:Lang -eq 'pt') {
Write-Host @'

Fora do Chrome, também vale revisar na sua conta Google (myaccount.google.com/data-and-privacy):
  - "Atividade na Web e de apps"  -> pausar ou ativar a exclusão automática
  - "Minha central de anúncios"   -> desligar anúncios personalizados
'@
} else {
Write-Host @'

Outside Chrome, it is also worth reviewing your Google account (myaccount.google.com/data-and-privacy):
  - "Web & App Activity"  -> pause it or turn on auto-delete
  - "My Ad Center"        -> turn off personalized ads
'@
}

#endregion
