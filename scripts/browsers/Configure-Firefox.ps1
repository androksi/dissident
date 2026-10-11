#Requires -RunAsAdministrator
<#
    Configure-Firefox.ps1 — a clean Firefox: no telemetry, sponsored content, recommendations or AI,
    with uBlock Origin and Bitwarden installed

    HOW TO RUN (Windows PowerShell as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1
    UNDO EVERYTHING:
        powershell -ExecutionPolicy Bypass -File .\Configure-Firefox.ps1 -Revert
    Add -Lang en or -Lang pt to skip the language question.

    Uses Firefox's official policies (github.com/mozilla/policy-templates). They apply even if
    Firefox is installed later. Close and reopen Firefox to apply. It will show
    "Your browser is being managed by your organization" — that's normal with policies.
    Works on Windows 10 and 11. Safe to run more than once.

    Passwords: turns off Firefox's own password manager, so only Bitwarden is used.
    Address bar: removes the "Add to taskbar" and Picture-in-Picture buttons.
    Four questions: search suggestions, page preloading, HTTPS-Only mode and page translation
    (Enter = default).

    Does NOT touch: site sign-ins (Google included), tracking protection (stays on the default,
    which already isolates cookies per site) and updates.

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
$F = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'


#region ==================== 1. HELPERS ====================

$script:Failures = 0

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

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
        Write-Host (T '  [ERROR] ' '  [ERRO] ') -ForegroundColor Red -NoNewline
        Write-Host "$Description ($label): $($_.Exception.Message)"
    }
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

function Set-Telemetry {
    Set-Policy ''               'DisableTelemetry'           1 (T 'Telemetry: off' 'Telemetria: off')
    Set-Policy ''               'DisableFirefoxStudies'      1 (T 'Studies and remote experiments: off' 'Estudos e experimentos remotos: off')
    Set-Policy ''               'DisableDefaultBrowserAgent' 1 (T 'Default browser agent (task): off' 'Agente de navegador padrão (tarefa): off')
    Set-Policy ''               'DontCheckDefaultBrowser'    1 (T '"Not your default browser" prompt: off' 'Aviso "não é o navegador padrão": off')
}

function Set-SponsoredAndRecommendations {
    Set-Policy 'FirefoxHome'    'SponsoredTopSites'          0 (T 'Sponsored shortcuts on the new tab: off' 'Atalhos patrocinados na nova aba: off')
    Set-Policy 'FirefoxHome'    'SponsoredStories'           0 (T 'Sponsored stories on the new tab: off' 'Matérias patrocinadas na nova aba: off')
    Set-Policy 'FirefoxHome'    'Stories'                    0 (T 'Recommended stories on the new tab: off' 'Matérias recomendadas na nova aba: off')
    Set-Policy 'FirefoxSuggest' 'SponsoredSuggestions'       0 (T 'Sponsored suggestions in the address bar: off' 'Sugestões patrocinadas na barra: off')
    Set-Policy 'FirefoxSuggest' 'WebSuggestions'             0 (T 'Suggestions from Mozilla in the address bar: off' 'Sugestões da Mozilla na barra: off')
    Set-Policy 'FirefoxSuggest' 'ImproveSuggest'             0 (T 'Send what you type to Mozilla: off' 'Enviar o que digita para a Mozilla: off')
    Set-Policy 'UserMessaging'  'ExtensionRecommendations'   0 (T 'Extension recommendations: off' 'Recomendação de extensões: off')
    Set-Policy 'UserMessaging'  'FeatureRecommendations'     0 (T 'Feature recommendations: off' 'Recomendação de recursos: off')
    Set-Policy 'UserMessaging'  'MoreFromMozilla'            0 (T '"More from Mozilla" in settings: off' '"Mais da Mozilla" nas configurações: off')
    Set-Policy 'UserMessaging'  'SkipOnboarding'             1 (T 'Welcome screens: off' 'Telas de boas-vindas: off')
    Set-Policy 'UserMessaging'  'UrlbarInterventions'        0 (T 'Address bar tips: off' 'Dicas na barra de endereço: off')
    Set-Policy 'UserMessaging'  'FirefoxLabs'                0 (T 'Invitations to experimental features: off' 'Convites para recursos experimentais: off')
    Set-Policy ''               'NoDefaultBookmarks'         1 (T 'Default bookmarks in new profiles: off' 'Favoritos de fábrica em perfis novos: off')
}

# Firefox 149+ (AIControls) and older versions (GenerativeAI). Page translation runs on your PC without
# sending anything out, so it stays available unless you choose to turn it off (that also hides its
# address bar icon; there is no way to hide only the icon).
function Set-AI([bool]$KeepTranslations) {
    Set-Policy 'AIControls\Default'      'Value' 'blocked'   (T 'AI features (general default): off' 'Recursos de IA (padrão geral): off')  'String'
    if ($KeepTranslations) {
        Set-Policy 'AIControls\Translations' 'Value' 'available' (T 'Page translation (local): kept' 'Tradução de páginas (local): mantida') 'String'
    } else {
        Set-Policy 'AIControls\Translations' 'Value' 'blocked' (T 'Page translation: off' 'Tradução de páginas: off')            'String'
    }
    Set-Policy 'GenerativeAI'   'Enabled'                    0 (T 'AI features (older versions): off' 'Recursos de IA (versões antigas): off')
}

# Buttons that show up in the address bar when a site allows them. Set through the "Preferences" policy
# (locked, so Firefox cannot turn them back on):
#   browser.taskbarTabs.enabled                                   "Add to taskbar" (Windows, Firefox 142+)
#   media.videocontrols.picture-in-picture.urlbar-button.enabled  Picture-in-Picture button (PiP itself
#                                                                 keeps working from the video and right-click)
#   browser.translations.enable                                   translation icon, only if translation is off
function Set-AddressBarButtons([bool]$KeepTranslations) {
    $prefs = [ordered]@{
        'browser.taskbarTabs.enabled'                                  = (T '"Add to taskbar": off' '"Adicionar à barra de tarefas": off')
        'media.videocontrols.picture-in-picture.urlbar-button.enabled' = (T 'Picture-in-Picture button: off' 'Botão de Picture-in-Picture: off')
    }
    if (-not $KeepTranslations) { $prefs['browser.translations.enable'] = (T 'Translation icon: off' 'Ícone de tradução: off') }
    $entries = foreach ($name in $prefs.Keys) { '"{0}":{{"Value":false,"Status":"locked"}}' -f $name }
    $json = '{' + ($entries -join ',') + '}'
    Set-Policy '' 'Preferences' @($json) ($prefs.Values -join '; ') 'MultiString'
}

# Reader View icon ("book" in the address bar). Its preference (reader.parse-on-load.enabled) is not
# accepted by the "Preferences" policy, so it goes through Firefox AutoConfig: two small files in the
# Firefox folder, kept across updates. If another AutoConfig already exists there, it is left alone.
function Get-FirefoxDir {
    $exe = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Split-Path $exe }
}

function Get-AutoConfigPaths([string]$Dir) {
    @{ Loader = Join-Path $Dir 'defaults\pref\autoconfig.js'; Config = Join-Path $Dir 'tidywin.cfg' }
}

function Set-ReaderViewButton([string]$Dir) {
    if (-not $Dir) { Write-Host (T '  [skipped] Firefox not installed: install it and run this again.' '  [pulado] Firefox não instalado: instale e rode de novo.') -ForegroundColor DarkYellow; return }
    $p = Get-AutoConfigPaths $Dir
    if ((Test-Path $p.Loader) -and -not (Select-String -Path $p.Loader -Pattern 'tidywin.cfg' -SimpleMatch -Quiet)) {
        Write-Host (T "  [skipped] Another AutoConfig already exists ($($p.Loader)); not touched." "  [pulado] Já existe outro AutoConfig ($($p.Loader)); não foi mexido.") -ForegroundColor DarkYellow
        return
    }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $p.Loader) | Out-Null
        $loader = "// TidyWin: loads tidywin.cfg from the Firefox folder`r`npref(`"general.config.filename`", `"tidywin.cfg`");`r`npref(`"general.config.obscure_value`", 0);`r`n"
        $config = "// TidyWin AutoConfig (Firefox skips this first line)`r`nlockPref(`"reader.parse-on-load.enabled`", false);`r`n"
        [IO.File]::WriteAllText($p.Loader, $loader, [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($p.Config, $config, [Text.Encoding]::ASCII)
        Write-Host (T '  [ok] Reader View icon: off' '  [ok] Ícone do modo leitura: off') -ForegroundColor Green
    } catch {
        $script:Failures++
        Write-Host (T "  [ERROR] Reader View icon: $($_.Exception.Message)" "  [ERRO] Ícone do modo leitura: $($_.Exception.Message)") -ForegroundColor Red
    }
}

# Removes only TidyWin's AutoConfig (the loader is checked first).
function Remove-ReaderViewButton([string]$Dir) {
    if (-not $Dir) { return }
    $p = Get-AutoConfigPaths $Dir
    if ((Test-Path $p.Loader) -and (Select-String -Path $p.Loader -Pattern 'tidywin.cfg' -SimpleMatch -Quiet)) {
        Remove-Item $p.Loader, $p.Config -Force -ErrorAction SilentlyContinue
        Write-Host (T '  [removed] AutoConfig (Reader View icon is back)' '  [removida] AutoConfig (o ícone do modo leitura voltou)') -ForegroundColor DarkGray
    }
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
    Set-Policy '' 'ExtensionSettings' @($json) (T "Installed: $($extensions.Values -join ', ')" "Instaladas: $($extensions.Values -join ', ')") 'MultiString'
}

# Before turning it off: warns if Firefox itself has saved passwords (they are hidden, not deleted).
function Set-BitwardenOnly {
    $saved = 0
    Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*\logins.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $saved += @((Get-Content $_.FullName -Raw | ConvertFrom-Json).logins).Count } catch { }
    }
    if ($saved -gt 0) {
        Write-Host (T "  WARNING: Firefox has $saved saved password(s). They will not be deleted, only hidden." "  ATENÇÃO: o Firefox tem $saved senha(s) salva(s). Elas não serão apagadas, só ficarão ocultas.") -ForegroundColor Yellow
        Write-Host (T '  To move them to Bitwarden: Firefox → about:logins → menu (...) → Export passwords;' '  Para levar ao Bitwarden: Firefox → about:logins → menu (...) → Exportar senhas;') -ForegroundColor Yellow
        Write-Host (T '  then, in the Bitwarden web vault: Tools → Import data → Firefox (csv). Delete the .csv afterwards.' '  depois, no cofre web do Bitwarden: Ferramentas → Importar dados → Firefox (csv). Apague o .csv depois.') -ForegroundColor Yellow
    }
    Set-Policy ''               'PasswordManagerEnabled'     0 (T 'Firefox password manager: off' 'Gerenciador de senhas do Firefox: off')
    Set-Policy ''               'OfferToSaveLogins'          0 (T 'Offer to save passwords: off' 'Oferecer para salvar senhas: off')
    Set-Policy ''               'AutofillAddressEnabled'     0 (T 'Save/fill addresses: off' 'Salvar/preencher endereços: off')
    Set-Policy ''               'AutofillCreditCardEnabled'  0 (T 'Save/fill payment cards: off' 'Salvar/preencher cartões: off')
}

# The three optional choices asked at the start.
function Set-OptionalPrivacy([bool]$NoSearchSuggestions, [bool]$NoPrefetch, [bool]$HttpsOnly) {
    if ($NoSearchSuggestions) { Set-Policy '' 'SearchSuggestEnabled' 0 (T 'Search suggestions: off' 'Sugestões de pesquisa: off') }
    if ($NoPrefetch)          { Set-Policy '' 'NetworkPrediction'    0 (T 'Page preloading: off' 'Pré-carregamento de páginas: off') }
    if ($HttpsOnly)           { Set-Policy '' 'HttpsOnlyMode' 'enabled' (T 'HTTPS-Only Mode: on' 'Modo somente HTTPS: ligado') 'String' }
}


#endregion


#region ==================== 3. REVERT ====================

function Remove-Policies {
    Write-Step (T 'Removing Firefox policies' 'Removendo as políticas do Firefox')
    Remove-ReaderViewButton (Get-FirefoxDir)
    if (Test-Path $F) {
        Get-ChildItem $F -Recurse | ForEach-Object {
            $sub = $_.Name -replace '^.*\\Mozilla\\Firefox\\?', ''
            $_.Property | ForEach-Object { Write-Host (T "  [removed] $sub\$_" "  [removida] $sub\$_") -ForegroundColor DarkGray }
        }
        (Get-Item $F).Property | ForEach-Object { Write-Host (T "  [removed] $_" "  [removida] $_") -ForegroundColor DarkGray }
        Remove-Item $F -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host (T "`nDone. Close and reopen Firefox." "`nPronto. Feche e abra o Firefox.") -ForegroundColor Green
        Write-Host (T 'Note: uBlock Origin and Bitwarden remain installed; remove them in about:addons if you want.' 'Obs.: o uBlock Origin e o Bitwarden continuam instalados; remova em about:addons se quiser.')
    } else {
        Write-Host (T '  No Firefox policies found; nothing to do.' '  Nenhuma política do Firefox encontrada; nada a fazer.')
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if ($Revert) { Remove-Policies; return }

$ffDir = Get-FirefoxDir
if (-not $ffDir) {
    Write-Host (T 'Firefox not found. The policies will be applied anyway and take effect when you install it.' 'Firefox não encontrado. As políticas serão aplicadas mesmo assim e valem quando você instalar.') -ForegroundColor DarkYellow
}

Write-Host "`nConfigure-Firefox" -ForegroundColor Green

# --- Questions
Write-Host (T '  Five choices (arrows and Enter; the default is already selected):' '  Cinco escolhas (setas e Enter; o padrão já vem selecionado):')
$noSearchSuggestions = Ask (T 'Turn off search suggestions while typing? (what you type goes to the search engine in real time)' 'Desativar as sugestões de pesquisa enquanto digita? (o que você digita vai ao buscador em tempo real)') $false
$noPrefetch          = Ask (T 'Turn off page preloading? (sites learn about links you never opened)' 'Desativar o pré-carregamento de páginas? (sites ficam sabendo de links que você nem abriu)') $true
$httpsOnly           = Ask (T 'Turn on HTTPS-Only Mode? (warns before opening sites without a secure connection)' 'Ligar o modo somente HTTPS? (avisa antes de abrir sites sem conexão segura)') $true
$keepTranslations    = Ask (T 'Keep page translation? (runs on your PC; if turned off, the translate icon disappears from the address bar)' 'Manter a tradução de páginas? (roda no seu PC; se desligar, o ícone de traduzir some da barra de endereço)') $true
$noReaderView        = Ask (T 'Remove the Reader View icon from the address bar? (the "book" that shows up on articles)' 'Remover o ícone do modo leitura da barra de endereço? (o "livro" que aparece em artigos)') $false

# --- Apply
Write-Step (T 'Telemetry' 'Telemetria');                   Set-Telemetry
Write-Step (T 'Sponsored content and recommendations' 'Patrocinados e recomendações'); Set-SponsoredAndRecommendations
Write-Step (T 'Artificial intelligence' 'Inteligência artificial');      Set-AI $keepTranslations
Write-Step (T 'Address bar buttons' 'Botões da barra de endereço');  Set-AddressBarButtons $keepTranslations
if ($noReaderView) { Set-ReaderViewButton $ffDir } else { Remove-ReaderViewButton $ffDir }
Write-Step (T 'Extensions' 'Extensões');                    Set-Extensions
Write-Step (T 'Passwords (Bitwarden only)' 'Senhas (só o Bitwarden)');      Set-BitwardenOnly
Write-Step (T 'Privacy choices' 'Escolhas de privacidade');      Set-OptionalPrivacy $noSearchSuggestions $noPrefetch $httpsOnly

# --- Done
if ($script:Failures) { Write-Host (T "`n$($script:Failures) policy(ies) failed — see the [ERROR] lines above." "`n$($script:Failures) política(s) falharam — veja as linhas [ERRO] acima.") -ForegroundColor Yellow }
Write-Host (T "`nDone. Close and reopen Firefox (or check about:policies)." "`nPronto. Feche e abra o Firefox (ou confira em about:policies).") -ForegroundColor Green
if (Get-Process firefox -ErrorAction SilentlyContinue) {
    Write-Host (T 'Firefox is open: close all of its windows for the changes to take effect.' 'O Firefox está aberto: feche todas as janelas dele para as mudanças valerem.') -ForegroundColor DarkYellow
}
if ($script:Lang -eq 'pt') {
Write-Host @'

Google só com links (sem IA e sem blocos extras) como pesquisa padrão — faça uma vez:
  1. Abra about:preferences#search
  2. Em "Atalhos de pesquisa", clique em "Adicionar"
       Nome:  Google Web
       URL:   https://www.google.com/search?q=%s&udm=14
       Atalho (opcional): @g
  3. No topo, em "Mecanismo de pesquisa padrão", escolha "Google Web"
'@
} else {
Write-Host @'

Google with links only (no AI and no extra blocks) as the default search — do this once:
  1. Open about:preferences#search
  2. Under "Search Shortcuts", click "Add"
       Name:  Google Web
       URL:   https://www.google.com/search?q=%s&udm=14
       Keyword (optional): @g
  3. At the top, under "Default Search Engine", choose "Google Web"
'@
}

#endregion
