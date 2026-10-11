#Requires -RunAsAdministrator
<#
    Configure-Apps.ps1 — pick apps from a list and install them with WinGet

    HOW TO RUN (Windows PowerShell as Administrator, in the regular console — not the ISE):
        powershell -ExecutionPolicy Bypass -File .\Configure-Apps.ps1

    1. If WinGet is missing (usually Windows 10), offers to install it.
    2. App list: ↑ ↓ move, Space selects, A selects the whole category, I toggles "interactive" install,
       / searches by name, Enter continues, Esc exits. Apps already installed are marked.
    3. Confirmation: "Retornar" (default) goes back to the list; "Instalar apps" installs them.
    Apps already installed are just skipped (or updated, if a newer version exists).

    To add an app: one line in $Apps (section 2). Find the ID with:  winget search <name>

    FILE LAYOUT
        1. Helpers
        2. App list
        3. WinGet (detect / install)
        4. Selection screen
        5. Confirmation and installation
        6. Execution
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # WinGet prints UTF-8


#region ==================== 1. HELPERS ====================

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Sim / Não" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Sim', 'Não') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
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
    Write-Host ''
    return $selected
}

#endregion


#region ==================== 2. APP LIST ====================

# Category, display name, WinGet ID, source ('winget' or 'msstore'), interactive by default, short description.
# The list is shown in this order. Interactive = the app's own installer window opens so you can pick options
# (e.g. VS Code: "Open with Code" in the context menu). Microsoft Store apps can't be interactive.
function New-App($Category, $Name, $Id, $Source, $Interactive, $Description) {
    [pscustomobject]@{
        Category = $Category; Name = $Name; Id = $Id; Source = $Source
        Interactive = [bool]$Interactive; Description = $Description; Selected = $false; Installed = $false
    }
}

$Apps = @(
    New-App 'Navegadores'   'Brave'                 'Brave.Brave'                       'winget'  $false 'navegador com bloqueador de anúncios'
    New-App 'Navegadores'   'Chrome'                'Google.Chrome'                     'winget'  $false 'navegador do Google'
    New-App 'Navegadores'   'Firefox (pt-BR)'       'Mozilla.Firefox.pt-BR'             'winget'  $false 'navegador da Mozilla'
    New-App 'Navegadores'   'Opera GX'              'Opera.OperaGX'                     'winget'  $false 'navegador "gamer" da Opera'
    New-App 'Navegadores'   'Zen Browser'           'Zen-Team.Zen-Browser'              'winget'  $false 'navegador baseado no Firefox, visual moderno (open source)'
    New-App 'Navegadores'   'LibreWolf'             'LibreWolf.LibreWolf'               'winget'  $false 'Firefox focado em privacidade (open source)'
    New-App 'Navegadores'   'Vivaldi'               'Vivaldi.Vivaldi'                   'winget'  $false 'navegador cheio de personalização'

    New-App 'Comunicação'   'Discord'               'Discord.Discord'                   'winget'  $false 'chat de voz e texto'
    New-App 'Comunicação'   'Telegram'              'Telegram.TelegramDesktop'          'winget'  $false 'mensageiro'
    New-App 'Comunicação'   'Signal'                'OpenWhisperSystems.Signal'         'winget'  $false 'mensageiro com criptografia (open source)'
    New-App 'Comunicação'   'Thunderbird (pt-BR)'   'Mozilla.Thunderbird.pt-BR'         'winget'  $false 'cliente de e-mail (open source)'
    New-App 'Comunicação'   'WhatsApp'              '9NKSQGP7F2NH'                      'msstore' $false 'WhatsApp para desktop (Microsoft Store)'
    New-App 'Comunicação'   'Zoom'                  'Zoom.Zoom'                         'winget'  $false 'videochamadas'
    New-App 'Comunicação'   'Slack'                 'SlackTechnologies.Slack'           'winget'  $false 'chat de trabalho'
    New-App 'Comunicação'   'Microsoft Teams'       'Microsoft.Teams'                   'winget'  $false 'reuniões e chat de trabalho'

    New-App 'Mídia'         'Spotify'               '9NCBCSZSJRSB'                      'msstore' $false 'música (versão da Microsoft Store)'
    New-App 'Mídia'         'VLC'                   'VideoLAN.VLC'                      'winget'  $false 'toca qualquer vídeo ou áudio (open source)'
    New-App 'Mídia'         'OBS Studio'            'OBSProject.OBSStudio'              'winget'  $false 'gravar a tela e fazer live (open source)'
    New-App 'Mídia'         'Audacity'              'Audacity.Audacity'                 'winget'  $false 'editor de áudio (open source)'
    New-App 'Mídia'         'HandBrake'             'HandBrake.HandBrake'               'winget'  $false 'converter e comprimir vídeos (open source)'
    New-App 'Mídia'         'Kdenlive'              'KDE.Kdenlive'                      'winget'  $false 'editor de vídeo (open source)'
    New-App 'Mídia'         'Shotcut'               'Meltytech.Shotcut'                 'winget'  $false 'editor de vídeo simples (open source)'
    New-App 'Mídia'         'foobar2000'            'PeterPawlowski.foobar2000'         'winget'  $false 'player de música leve'
    New-App 'Mídia'         'ImageGlass'            'DuongDieuPhap.ImageGlass'          'winget'  $false 'visualizador de imagens rápido (open source)'
    New-App 'Mídia'         'Stremio'               'Stremio.Stremio'                   'winget'  $false 'central de filmes e séries'

    New-App 'Jogos'         'Steam'                 'Valve.Steam'                       'winget'  $false 'loja e biblioteca de jogos'
    New-App 'Jogos'         'Heroic Games Launcher' 'HeroicGamesLauncher.HeroicGamesLauncher' 'winget' $false 'jogos da Epic, GOG e Amazon (open source)'
    New-App 'Jogos'         'NVIDIA App'            'XP8CLZL93F5Z4P'                    'msstore' $false 'drivers e ajustes da placa NVIDIA'
    New-App 'Jogos'         'Epic Games Launcher'   'EpicGames.EpicGamesLauncher'       'winget'  $false 'loja da Epic'
    New-App 'Jogos'         'EA app'                'ElectronicArts.EADesktop'          'winget'  $false 'loja da EA'
    New-App 'Jogos'         'Ubisoft Connect'       'Ubisoft.Connect'                   'winget'  $false 'loja da Ubisoft'
    New-App 'Jogos'         'Battle.net'            'Blizzard.BattleNet'                'winget'  $false 'loja da Blizzard'
    New-App 'Jogos'         'GOG Galaxy'            'GOG.Galaxy'                        'winget'  $false 'loja da GOG'
    New-App 'Jogos'         'MSI Afterburner'       'Guru3D.Afterburner'                'winget'  $false 'FPS e temperaturas na tela dos jogos'
    New-App 'Jogos'         'Playnite'              'Playnite.Playnite'                 'winget'  $false 'junta todas as bibliotecas de jogos (open source)'
    New-App 'Jogos'         'Prism Launcher'        'PrismLauncher.PrismLauncher'       'winget'  $false 'launcher de Minecraft com mods (open source)'
    New-App 'Jogos'         'RetroArch'             'Libretro.RetroArch'                'winget'  $false 'emulador de consoles antigos (open source)'

    New-App 'Programação'   'Git'                   'Git.Git'                           'winget'  $false 'controle de versão (open source)'
    New-App 'Programação'   'GitHub Desktop'        'GitHub.GitHubDesktop'              'winget'  $false 'Git com interface gráfica'
    New-App 'Programação'   'VS Code'               'Microsoft.VisualStudioCode'        'winget'  $true  'editor de código'
    New-App 'Programação'   'Node.js LTS'           'OpenJS.NodeJS.LTS'                 'winget'  $false 'JavaScript fora do navegador (open source)'
    New-App 'Programação'   'fnm'                   'Schniz.fnm'                        'winget'  $false 'troca entre versões do Node.js (open source)'
    New-App 'Programação'   'Python 3.14'           'Python.Python.3.14'                'winget'  $false 'linguagem Python (open source)'
    New-App 'Programação'   'PowerShell 7'          'Microsoft.PowerShell'              'winget'  $false 'PowerShell moderno (open source)'
    New-App 'Programação'   'Windows Terminal'      'Microsoft.WindowsTerminal'         'winget'  $false 'terminal com abas (já vem no Windows 11)'
    New-App 'Programação'   'Notepad++'             'Notepad++.Notepad++'               'winget'  $false 'editor de texto (open source)'
    New-App 'Programação'   'WinMerge'              'WinMerge.WinMerge'                 'winget'  $false 'comparar arquivos e pastas (open source)'
    New-App 'Programação'   'DBeaver'               'DBeaver.DBeaver.Community'         'winget'  $false 'cliente de banco de dados (open source)'
    New-App 'Programação'   'Bruno'                 'Bruno.Bruno'                       'winget'  $false 'testar APIs, alternativa ao Postman (open source)'
    New-App 'Programação'   'Insomnia'              'Insomnia.Insomnia'                 'winget'  $false 'testar APIs (open source)'
    New-App 'Programação'   'Yaak'                  'Yaak.app'                          'winget'  $false 'testar APIs (open source)'
    New-App 'Programação'   'Postman'               'Postman.Postman'                   'winget'  $false 'testar APIs'
    New-App 'Programação'   'Dataflare'             'Dataflare.Dataflare'               'winget'  $false 'cliente de banco de dados'
    New-App 'Programação'   'Cursor'                'Anysphere.Cursor'                  'winget'  $false 'editor de código com IA (baseado no VS Code)'
    New-App 'Programação'   'JetBrains Toolbox'     'JetBrains.Toolbox'                 'winget'  $false 'instala as IDEs da JetBrains'
    New-App 'Programação'   'Docker Desktop'        'Docker.DockerDesktop'              'winget'  $false 'containers'
    New-App 'Programação'   'Zed'                   'ZedIndustries.Zed'                 'winget'  $false 'editor de código muito rápido (open source)'
    New-App 'Programação'   'Go'                    'GoLang.Go'                         'winget'  $false 'linguagem Go (open source)'
    New-App 'Programação'   'Rustup'                'Rustlang.Rustup'                   'winget'  $false 'instala a linguagem Rust (open source)'
    New-App 'Programação'   'Java (Temurin 25)'     'EclipseAdoptium.Temurin.25.JDK'    'winget'  $false 'Java JDK 25 LTS (open source)'
    New-App 'Programação'   'Bun'                   'Oven-sh.Bun'                       'winget'  $false 'runtime JavaScript rápido (open source)'
    New-App 'Programação'   'HeidiSQL'              'HeidiSQL.HeidiSQL'                 'winget'  $false 'cliente de MySQL/MariaDB (open source)'
    New-App 'Programação'   'MongoDB Compass'       'MongoDB.Compass.Full'              'winget'  $false 'cliente do MongoDB'
    New-App 'Programação'   'Ollama'                'Ollama.Ollama'                     'winget'  $false 'roda modelos de IA no próprio PC (open source)'

    New-App 'Design'        'GIMP'                  'GIMP.GIMP.3'                       'winget'  $false 'editor de imagens (open source)'
    New-App 'Design'        'Inkscape'              'Inkscape.Inkscape'                 'winget'  $false 'desenho vetorial (open source)'
    New-App 'Design'        'Krita'                 'KDE.Krita'                         'winget'  $false 'pintura digital (open source)'
    New-App 'Design'        'Blender'               'BlenderFoundation.Blender'         'winget'  $false 'modelagem 3D e animação (open source)'
    New-App 'Design'        'Figma'                 'Figma.Figma'                       'winget'  $false 'design de interfaces'
    New-App 'Design'        'Paint.NET'             'dotPDN.PaintDotNet'                'winget'  $false 'editor de imagens simples'
    New-App 'Design'        'ScreenToGif'           'NickeManarin.ScreenToGif'          'winget'  $false 'grava a tela em GIF (open source)'

    New-App 'Produtividade' 'LibreOffice'           'TheDocumentFoundation.LibreOffice' 'winget'  $false 'pacote de escritório (open source)'
    New-App 'Produtividade' 'Joplin'                'Joplin.Joplin'                     'winget'  $false 'notas em Markdown (open source)'
    New-App 'Produtividade' 'SumatraPDF'            'SumatraPDF.SumatraPDF'             'winget'  $false 'leitor de PDF leve (open source)'
    New-App 'Produtividade' 'Claude'                'Anthropic.Claude'                  'winget'  $false 'app do Claude para desktop'
    New-App 'Produtividade' 'Obsidian'              'Obsidian.Obsidian'                 'winget'  $false 'notas em Markdown'
    New-App 'Produtividade' 'Notion'                'Notion.Notion'                     'winget'  $false 'notas, tarefas e wikis'
    New-App 'Produtividade' 'Adobe Acrobat Reader'  'Adobe.Acrobat.Reader.64-bit'       'winget'  $false 'leitor de PDF da Adobe'
    New-App 'Produtividade' 'Google Drive'          'Google.GoogleDrive'                'winget'  $false 'sincroniza o Google Drive com o PC'
    New-App 'Produtividade' 'ONLYOFFICE'            'ONLYOFFICE.DesktopEditors'         'winget'  $false 'escritório compatível com Office (open source)'
    New-App 'Produtividade' 'Logseq'                'Logseq.Logseq'                     'winget'  $false 'notas conectadas (open source)'

    New-App 'Segurança'     'Bitwarden'             'Bitwarden.Bitwarden'               'winget'  $false 'gerenciador de senhas (open source)'
    New-App 'Segurança'     'KeePassXC'             'KeePassXCTeam.KeePassXC'           'winget'  $false 'gerenciador de senhas offline (open source)'
    New-App 'Segurança'     'Proton VPN'            'Proton.ProtonVPN'                  'winget'  $false 'VPN com plano grátis (open source)'
    New-App 'Segurança'     'Malwarebytes'          'Malwarebytes.Malwarebytes'         'winget'  $false 'antimalware (segunda opinião ao Defender)'

    New-App 'Utilitários'   '7-Zip'                 '7zip.7zip'                         'winget'  $false 'compactador de arquivos (open source)'
    New-App 'Utilitários'   'WinRAR'                'RARLab.WinRAR'                     'winget'  $false 'compactador de arquivos (RAR)'
    New-App 'Utilitários'   'Everything'            'voidtools.Everything'              'winget'  $false 'busca arquivos no PC na hora'
    New-App 'Utilitários'   'AnyDesk'               'AnyDesk.AnyDesk'                   'winget'  $false 'acesso remoto'
    New-App 'Utilitários'   'HWiNFO'                'REALiX.HWiNFO'                     'winget'  $false 'informações e sensores do hardware'
    New-App 'Utilitários'   'CPU-Z'                 'CPUID.CPU-Z'                       'winget'  $false 'informações do processador e da memória'
    New-App 'Utilitários'   'WizTree'               'AntibodySoftware.WizTree'          'winget'  $false 'mostra o que ocupa espaço no disco'
    New-App 'Utilitários'   'Flow Launcher'         'Flow-Launcher.Flow-Launcher'       'winget'  $false 'abre apps e arquivos pelo teclado (open source)'
    New-App 'Utilitários'   'PowerToys'             'Microsoft.PowerToys'               'winget'  $false 'utilitários da Microsoft (open source)'
    New-App 'Utilitários'   'ShareX'                'ShareX.ShareX'                     'winget'  $false 'capturas e gravação de tela (open source)'
    New-App 'Utilitários'   'LocalSend'             'LocalSend.LocalSend'               'winget'  $false 'enviar arquivos pela rede local (open source)'
    New-App 'Utilitários'   'qBittorrent'           'qBittorrent.qBittorrent'           'winget'  $false 'torrent sem anúncios (open source)'
    New-App 'Utilitários'   'UniGetUI'              'Devolutions.UniGetUI'              'winget'  $false 'interface para o WinGet; atualiza tudo (open source)'
    New-App 'Utilitários'   'Bulk Crap Uninstaller' 'Klocman.BulkCrapUninstaller'       'winget'  $false 'desinstala e limpa os restos (open source)'
    New-App 'Utilitários'   'CrystalDiskInfo'       'CrystalDewWorld.CrystalDiskInfo'   'winget'  $false 'saúde do SSD/HD (open source)'
)

#endregion


#region ==================== 3. WINGET ====================

function Test-WinGet { [bool](Get-Command winget -ErrorAction SilentlyContinue) }

# Installs WinGet the way Microsoft documents it:
#   1. register the "App Installer" package (often already on the PC, just not registered yet)
#   2. if that is not enough, the official Microsoft.WinGet.Client module downloads and repairs it
function Install-WinGet {
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    Write-Host '  registrando o Instalador de Aplicativo...'
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    if (Test-WinGet) { return $true }

    Write-Host '  baixando o WinGet pelo módulo oficial da Microsoft (pode levar alguns minutos)...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  (falhou: $($_.Exception.Message))" -ForegroundColor DarkYellow
    }
    return (Test-WinGet)
}

# IDs of the packages WinGet sees as installed (WinGet and Microsoft Store sources), via "winget export".
# One call for the whole list. If it fails, nothing is marked as installed.
function Get-InstalledAppIds {
    $file = Join-Path $env:TEMP "configure-apps-$PID.json"
    try {
        winget export --output $file --accept-source-agreements *> $null
        $json = Get-Content $file -Raw -ErrorAction Stop | ConvertFrom-Json
        return @($json.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
    } catch {
        return @()
    } finally {
        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

#endregion


#region ==================== 4. SELECTION SCREEN ====================

# Checkbox list with scrolling. Rows are category headers (not selectable) and apps.
# Returns $true to continue (Enter) or $false to quit (Esc). Selections are stored in $Apps.
function Show-AppSelection {
    $rows = New-Object System.Collections.Generic.List[object]
    $lastCategory = $null
    for ($i = 0; $i -lt $Apps.Count; $i++) {
        if ($Apps[$i].Category -ne $lastCategory) {
            $rows.Add([pscustomobject]@{ IsHeader = $true; Text = $Apps[$i].Category })
            $lastCategory = $Apps[$i].Category
        }
        $rows.Add([pscustomobject]@{ IsHeader = $false; App = $Apps[$i] })
    }
    $appRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if (-not $rows[$r].IsHeader) { $r } })
    $cursor = 0          # position inside $appRows
    $scroll = 0          # first visible row
    $lastSize = ''
    $searchMode = $false; $searchText = ''; $searchFound = $false; $searchOrigin = 0

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            if ("$width x $height" -ne $lastSize) { Clear-Host; $lastSize = "$width x $height" }
            $viewport = [Math]::Max(5, $height - 7)   # 4 header + 2 footer lines, last line left empty (no scrolling)

            # Keep the cursor row (and its category header right above it) on screen
            $row = $appRows[$cursor]
            $wanted = if ($row -gt 0 -and $rows[$row - 1].IsHeader) { $row - 1 } else { $row }
            if ($wanted -lt $scroll) { $scroll = $wanted }
            if ($row -ge $scroll + $viewport) { $scroll = $row - $viewport + 1 }

            $line = { param($text, $color) Write-Host ($text.PadRight($width - 1).Substring(0, $width - 1)) -ForegroundColor $color }
            [Console]::SetCursorPosition(0, 0)
            & $line '  Configure-Apps — escolha os apps para instalar' 'Green'
            & $line '  ↑ ↓ navegar   Espaço marcar   A marcar categoria   I interativo   / buscar   Enter continuar   Esc sair' 'DarkGray'
            & $line '  [x] = instalar   [I] = interativo (abre o instalador do app para você escolher as opções)' 'DarkGray'
            & $line '' 'Gray'

            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count) { & $line '' 'Gray'; continue }
                if ($rows[$r].IsHeader) { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $app = $rows[$r].App
                $check  = if ($app.Selected) { '[x]' } else { '[ ]' }
                $interactive = if ($app.Source -eq 'msstore') { '   ' } elseif ($app.Interactive) { '[I]' } else { '[ ]' }
                $marker = if ($r -eq $row) { '>' } else { ' ' }
                $installedTag = if ($app.Installed) { 'instalado · ' } else { '' }
                $text = "  $marker $check $interactive  $($app.Name.PadRight(24)) $installedTag$($app.Description)"
                $color = if ($r -eq $row) { 'Cyan' } elseif ($app.Selected) { 'Green' } elseif ($app.Installed) { 'DarkGray' } else { 'Gray' }
                & $line $text $color
            }

            & $line '' 'Gray'
            if ($searchMode) {
                $hint = if ($searchText -and -not $searchFound) { '   (nada encontrado)' } else { '   (Enter confirma, Esc cancela)' }
                & $line "  Buscar: $($searchText)_$hint" 'Cyan'
            } else {
                $count = @($Apps | Where-Object Selected).Count
                & $line "  $count selecionado(s)   ·   $($cursor + 1) de $($appRows.Count)" 'DarkGray'
            }

            $keyInfo = [Console]::ReadKey($true)
            $key = $keyInfo.Key

            # --- Search mode: typing jumps to the first app whose name contains the text
            if ($searchMode) {
                if     ($key -eq 'Escape')    { $cursor = $searchOrigin; $searchMode = $false; continue }
                elseif ($key -eq 'Enter')     { $searchMode = $false; continue }
                elseif ($key -eq 'Backspace') { if ($searchText) { $searchText = $searchText.Substring(0, $searchText.Length - 1) } }
                elseif (-not [char]::IsControl($keyInfo.KeyChar)) { $searchText += $keyInfo.KeyChar }
                $searchFound = $false
                if ($searchText) {
                    for ($c = 0; $c -lt $appRows.Count; $c++) {
                        if ($rows[$appRows[$c]].App.Name.IndexOf($searchText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $cursor = $c; $searchFound = $true; break
                        }
                    }
                }
                continue
            }
            if ($keyInfo.KeyChar -eq '/') {
                $searchMode = $true; $searchText = ''; $searchFound = $false; $searchOrigin = $cursor
                continue
            }

            switch ($key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($appRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - $viewport) }
                'PageDown'  { $cursor = [Math]::Min($appRows.Count - 1, $cursor + $viewport) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $appRows.Count - 1 }
                'Spacebar'  { $app = $rows[$appRows[$cursor]].App; $app.Selected = -not $app.Selected }
                'A' {
                    # Whole category: selects every app in it; if all are already selected, clears them
                    $category = @($Apps | Where-Object Category -eq $rows[$appRows[$cursor]].App.Category)
                    $selectAll = @($category | Where-Object { -not $_.Selected }).Count -gt 0
                    foreach ($app in $category) { $app.Selected = $selectAll }
                }
                'I' {
                    $app = $rows[$appRows[$cursor]].App
                    if ($app.Source -ne 'msstore') {
                        $app.Interactive = -not $app.Interactive
                        if ($app.Interactive) { $app.Selected = $true }   # turning interactive on also selects it
                    }
                }
                'Enter'     { return $true }
                'Escape'    { return $false }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        Clear-Host
    }
}

#endregion


#region ==================== 5. CONFIRMATION AND INSTALLATION ====================

# Shows the chosen apps. Returns 'Back', 'Install' or 'Quit'.
function Show-Confirmation {
    $chosen = @($Apps | Where-Object Selected)
    Write-Host "`n  Configure-Apps — confirmação" -ForegroundColor Green
    if (-not $chosen) {
        Write-Host "`n  Nenhum app selecionado.`n"
        $options = @('Retornar', 'Sair')
        return @('Back', 'Quit')[(Choose 'O que fazer?' $options 0)]
    }
    Write-Host "`n  $($chosen.Count) app(s) para instalar:`n"
    foreach ($app in $chosen) {
        $note = ''
        if ($app.Interactive) { $note += ' (interativo)' }
        if ($app.Installed)   { $note += ' (já instalado: só atualiza, se houver versão nova)' }
        Write-Host "    - $($app.Name)$note"
    }
    Write-Host ''
    $options = @('Retornar', 'Instalar apps')
    return @('Back', 'Install')[(Choose 'O que fazer?' $options 0)]
}

# WinGet exit codes that mean "already installed / nothing newer to install".
$AlreadyInstalledCodes = @(-1978335189, -1978335135)   # 0x8A15002B, 0x8A150061

function Install-Apps {
    $chosen = @($Apps | Where-Object Selected)
    $results = @()
    for ($i = 0; $i -lt $chosen.Count; $i++) {
        $app = $chosen[$i]
        Write-Step "[$($i + 1)/$($chosen.Count)] $($app.Name)"
        $wingetArgs = @('install', '--id', $app.Id, '--exact', '--source', $app.Source,
                        '--accept-package-agreements', '--accept-source-agreements')
        if ($app.Interactive -and $app.Source -ne 'msstore') { $wingetArgs += '--interactive' }
        & winget @wingetArgs
        $code = $LASTEXITCODE
        $status = if ($code -eq 0) { 'ok' } elseif ($code -in $AlreadyInstalledCodes) { 'already' } else { 'failed' }
        $results += [pscustomobject]@{ Name = $app.Name; Status = $status; Code = $code }
    }

    Write-Step 'Resumo'
    foreach ($r in $results) {
        switch ($r.Status) {
            'ok'      { Write-Host "  [OK]       $($r.Name)" -ForegroundColor Green }
            'already' { Write-Host "  [JÁ TINHA] $($r.Name)" -ForegroundColor DarkGray }
            'failed'  { Write-Host ("  [ERRO]     {0} (código 0x{1:X8})" -f $r.Name, $r.Code) -ForegroundColor Red }
        }
    }
    if ($results.Status -contains 'failed') {
        Write-Host "`n  Para tentar de novo, rode o script outra vez e marque só os que falharam." -ForegroundColor Yellow
    }
}

#endregion


#region ==================== 6. EXECUTION ====================

if ($Host.Name -ne 'ConsoleHost') {
    Write-Warning 'Rode no console do PowerShell (powershell.exe ou Terminal), não no PowerShell ISE.'
    return
}

Write-Host "`nConfigure-Apps" -ForegroundColor Green

# --- WinGet first (only if missing)
if (-not (Test-WinGet)) {
    Write-Host "`n  O WinGet, o instalador de apps oficial da Microsoft, não está neste PC." -ForegroundColor Yellow
    Write-Host '  É ele que baixa e instala os apps da lista, sempre das fontes oficiais.'
    if (-not (Ask 'Instalar o WinGet agora e seguir para a lista de apps?' $true)) {
        Write-Host 'Nada foi instalado.'; return
    }
    Write-Step 'Instalando o WinGet'
    if (-not (Install-WinGet)) {
        Write-Host "`n  Não foi possível instalar o WinGet." -ForegroundColor Red
        Write-Host '  Instale o "Instalador de Aplicativo" pela Microsoft Store e rode o script de novo.'
        return
    }
    Write-Host '  WinGet instalado.' -ForegroundColor Green
}

# --- Mark the apps that are already installed
Write-Host '  verificando os apps que já estão instalados...' -ForegroundColor DarkGray
$installedIds = Get-InstalledAppIds
foreach ($app in $Apps) { $app.Installed = $installedIds -contains $app.Id }

# --- Selection ↔ confirmation loop
while ($true) {
    if (-not (Show-AppSelection)) { Write-Host 'Nada foi instalado.'; return }
    $action = Show-Confirmation
    if ($action -eq 'Quit')    { Write-Host 'Nada foi instalado.'; return }
    if ($action -eq 'Install') { break }
}

Install-Apps
Write-Host "`nPronto." -ForegroundColor Green

#endregion
