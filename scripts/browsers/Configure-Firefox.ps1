#Requires -RunAsAdministrator
<#
    Configure-Firefox.ps1 — a clean Firefox: no telemetry, sponsored content, recommendations or AI,
    with uBlock Origin and Bitwarden installed

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1 -Revert

    Uses Firefox's official policies (github.com/mozilla/policy-templates). They apply even if
    Firefox is installed later. Close and reopen Firefox to apply. It will show
    "Your browser is being managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.

    Passwords: turns off Firefox's own password manager, so only Bitwarden is used.
    Three questions: search suggestions, page preloading and HTTPS-Only mode (Enter = default).

    Does NOT touch: site sign-ins (Google included), tracking protection (stays on the default,
    which already isolates cookies per site), page translation (runs on your PC) and updates.

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
$F = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'


#region ==================== 1. HELPERS ====================

$script:Failures = 0

# Writes the policy (in $F or in a subkey) and prints the result: [OK] or [ERRO].
function Set-Policy([string]$SubKey, [string]$Name, [object]$Value, [string]$Description, [string]$Type = 'DWord') {
    $key = if ($SubKey) { "$F\$SubKey" } else { $F }
    $label = if ($SubKey) { "$SubKey\$Name" } else { $Name }
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $key -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        $shown = if ($Type -eq 'MultiString') { '(JSON)' } else { $Value }
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host ("{0,-46}" -f $Description) -NoNewline
        Write-Host "$label = $shown" -ForegroundColor DarkGray
    } catch {
        $script:Failures++
        Write-Host '  [ERRO] ' -ForegroundColor Red -NoNewline
        Write-Host "$Description ($label): $($_.Exception.Message)"
    }
}

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question. Enter = default.
function Ask([string]$Question, [bool]$Default) {
    $hint = if ($Default) { 'S/n' } else { 's/N' }
    while ($true) {
        $answer = "$(Read-Host "  $Question [$hint]")".Trim().ToLower()
        if ($answer -eq '')                      { return $Default }
        if ($answer -in 's', 'sim', 'y', 'yes')  { return $true }
        if ($answer -in 'n', 'nao', 'não', 'no') { return $false }
        Write-Host '  Responda s ou n.' -ForegroundColor DarkYellow
    }
}

#endregion


#region ==================== 2. POLICIES ====================

function Set-Telemetry {
    Set-Policy ''               'DisableTelemetry'           1 'Telemetria: off'
    Set-Policy ''               'DisableFirefoxStudies'      1 'Estudos e experimentos remotos: off'
    Set-Policy ''               'DisableDefaultBrowserAgent' 1 'Agente de navegador padrão (tarefa): off'
}

function Set-SponsoredAndRecommendations {
    Set-Policy 'FirefoxHome'    'SponsoredTopSites'          0 'Atalhos patrocinados na nova aba: off'
    Set-Policy 'FirefoxHome'    'SponsoredStories'           0 'Matérias patrocinadas na nova aba: off'
    Set-Policy 'FirefoxHome'    'Stories'                    0 'Matérias recomendadas na nova aba: off'
    Set-Policy 'FirefoxSuggest' 'SponsoredSuggestions'       0 'Sugestões patrocinadas na barra: off'
    Set-Policy 'FirefoxSuggest' 'WebSuggestions'             0 'Sugestões da Mozilla na barra: off'
    Set-Policy 'FirefoxSuggest' 'ImproveSuggest'             0 'Enviar o que digita para a Mozilla: off'
    Set-Policy 'UserMessaging'  'ExtensionRecommendations'   0 'Recomendação de extensões: off'
    Set-Policy 'UserMessaging'  'FeatureRecommendations'     0 'Recomendação de recursos: off'
    Set-Policy 'UserMessaging'  'MoreFromMozilla'            0 '"Mais da Mozilla" nas configurações: off'
    Set-Policy 'UserMessaging'  'SkipOnboarding'             1 'Telas de boas-vindas: off'
    Set-Policy 'UserMessaging'  'UrlbarInterventions'        0 'Dicas na barra de endereço: off'
    Set-Policy 'UserMessaging'  'FirefoxLabs'                0 'Convites para recursos experimentais: off'
    Set-Policy ''               'NoDefaultBookmarks'         1 'Favoritos de fábrica em perfis novos: off'
}

# Firefox 149+ (AIControls) and older versions (GenerativeAI). Page translation stays:
# it runs on your PC without sending anything out.
function Set-AI {
    Set-Policy 'AIControls\Default'      'Value' 'blocked'   'Recursos de IA (padrão geral): off'  'String'
    Set-Policy 'AIControls\Translations' 'Value' 'available' 'Tradução de páginas (local): mantida' 'String'
    Set-Policy 'GenerativeAI'   'Enabled'                    0 'Recursos de IA (versões antigas): off'
}

# Installed automatically from Mozilla's official store and kept up to date.
# "normal_installed" = you can disable them, but they can't be removed. Also allowed in private windows.
function Set-Extensions {
    $extensions = [ordered]@{
        'uBlock0@raymondhill.net'                = 'uBlock Origin'
        '{446900e4-71c2-419f-a6a7-df9c091e268b}' = 'Bitwarden'
    }
    $entries = foreach ($id in $extensions.Keys) {
        '"{0}":{{"installation_mode":"normal_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/{0}/latest.xpi","private_browsing":true}}' -f $id
    }
    $json = '{' + ($entries -join ',') + '}'
    Set-Policy '' 'ExtensionSettings' @($json) "Instaladas: $($extensions.Values -join ', ')" 'MultiString'
}

# Before turning it off: warns if Firefox itself has saved passwords (they are hidden, not deleted).
function Set-BitwardenOnly {
    $saved = 0
    Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $saved += @((Get-Content $_.FullName -Raw | ConvertFrom-Json).logins).Count } catch { }
    }
    if ($saved -gt 0) {
        Write-Host "  ATENÇÃO: o Firefox tem $saved senha(s) salva(s). Elas não serão apagadas, só ficarão ocultas." -ForegroundColor Yellow
        Write-Host '  Para levar ao Bitwarden: Firefox → about:logins → menu (...) → Exportar senhas;' -ForegroundColor Yellow
        Write-Host '  depois, no cofre web do Bitwarden: Ferramentas → Importar dados → Firefox (csv). Apague o .csv depois.' -ForegroundColor Yellow
    }
    Set-Policy ''               'PasswordManagerEnabled'     0 'Gerenciador de senhas do Firefox: off'
    Set-Policy ''               'OfferToSaveLogins'          0 'Oferecer para salvar senhas: off'
    Set-Policy ''               'AutofillAddressEnabled'     0 'Salvar/preencher endereços: off'
    Set-Policy ''               'AutofillCreditCardEnabled'  0 'Salvar/preencher cartões: off'
}

# The three optional choices asked at the start.
function Set-OptionalPrivacy([bool]$NoSearchSuggestions, [bool]$NoPrefetch, [bool]$HttpsOnly) {
    if ($NoSearchSuggestions) { Set-Policy '' 'SearchSuggestEnabled' 0 'Sugestões de pesquisa: off' }
    if ($NoPrefetch)          { Set-Policy '' 'NetworkPrediction'    0 'Pré-carregamento de páginas: off' }
    if ($HttpsOnly)           { Set-Policy '' 'HttpsOnlyMode' 'enabled' 'Modo somente HTTPS: ligado' 'String' }
}


#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step 'Removendo as políticas do Firefox'
    if (Test-Path $F) {
        Get-ChildItem $F -Recurse | ForEach-Object {
            $sub = $_.Name -replace '^.*\\Mozilla\\Firefox\\?', ''
            $_.Property | ForEach-Object { Write-Host "  [removida] $sub\$_" -ForegroundColor DarkGray }
        }
        (Get-Item $F).Property | ForEach-Object { Write-Host "  [removida] $_" -ForegroundColor DarkGray }
        Remove-Item $F -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "`nPronto. Feche e abra o Firefox." -ForegroundColor Green
        Write-Host 'Obs.: o uBlock Origin e o Bitwarden continuam instalados; remova em about:addons se quiser.'
    } else {
        Write-Host '  Nenhuma política do Firefox encontrada; nada a fazer.'
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$installed = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
    "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installed) {
    Write-Host 'Firefox não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.' -ForegroundColor DarkYellow
}

Write-Host "`nConfigure-Firefox" -ForegroundColor Green

# --- Questions
Write-Host '  Três escolhas (Enter aceita o padrão):'
$noSearchSuggestions = Ask 'Desativar as sugestões de pesquisa enquanto digita? (o que você digita vai ao buscador em tempo real)' $false
$noPrefetch          = Ask 'Desativar o pré-carregamento de páginas? (sites ficam sabendo de links que você nem abriu)' $true
$httpsOnly           = Ask 'Ligar o modo somente HTTPS? (avisa antes de abrir sites sem conexão segura)' $true

# --- Apply
Write-Step 'Telemetria';                   Set-Telemetry
Write-Step 'Patrocinados e recomendações'; Set-SponsoredAndRecommendations
Write-Step 'Inteligência artificial';      Set-AI
Write-Step 'Extensões';                    Set-Extensions
Write-Step 'Senhas (só o Bitwarden)';      Set-BitwardenOnly
Write-Step 'Escolhas de privacidade';      Set-OptionalPrivacy $noSearchSuggestions $noPrefetch $httpsOnly

# --- Done
if ($script:Failures) { Write-Host "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima." -ForegroundColor Yellow }
Write-Host "`nPronto. Feche e abra o Firefox (ou confira em about:policies)." -ForegroundColor Green
if (Get-Process firefox -ErrorAction SilentlyContinue) {
    Write-Host 'O Firefox está aberto: feche todas as janelas dele para as mudanças valerem.' -ForegroundColor DarkYellow
}
Write-Host @'

Google só com links (sem IA e sem blocos extras) como pesquisa padrão — faça uma vez:
  1. Abra about:preferences#search
  2. Em "Atalhos de pesquisa", clique em "Adicionar"
       Nome:  Google Web
       URL:   https://www.google.com/search?q=%s&udm=14
       Atalho (opcional): @g
  3. No topo, em "Mecanismo de pesquisa padrão", escolha "Google Web"
'@

#endregion
