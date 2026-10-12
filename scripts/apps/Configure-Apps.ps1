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

    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

    To add an app: one line in $Apps (section 2). Find the ID with:  winget search <name>

    FILE LAYOUT
        1. Helpers
        2. App list
        3. WinGet (detect / install)
        4. Selection screen
        5. Confirmation and installation
        6. Execution
#>
param(
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # WinGet prints UTF-8


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Sim / Não" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @((T 'Yes' 'Sim'), (T 'No' 'Não')) $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
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
    Write-Host ''
    return $selected
}

#endregion


if ($Host.Name -ne 'ConsoleHost') {
    Write-Warning (T 'Run this in the PowerShell console (powershell.exe or Terminal), not in PowerShell ISE.' 'Rode no console do PowerShell (powershell.exe ou Terminal), não no PowerShell ISE.')
    return
}

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang


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
    New-App (T 'Browsers' 'Navegadores')   'Brave'                 'Brave.Brave'                       'winget'  $false (T 'browser with an ad blocker' 'navegador com bloqueador de anúncios')
    New-App (T 'Browsers' 'Navegadores')   'Chrome'                'Google.Chrome'                     'winget'  $false (T 'Google''s browser' 'navegador do Google')
    New-App (T 'Browsers' 'Navegadores')   'Firefox (pt-BR)'       'Mozilla.Firefox.pt-BR'             'winget'  $false (T 'Mozilla''s browser' 'navegador da Mozilla')
    New-App (T 'Browsers' 'Navegadores')   'Opera GX'              'Opera.OperaGX'                     'winget'  $false (T 'Opera''s "gamer" browser' 'navegador "gamer" da Opera')
    New-App (T 'Browsers' 'Navegadores')   'Zen Browser'           'Zen-Team.Zen-Browser'              'winget'  $false (T 'Firefox-based browser with a modern look (open source)' 'navegador baseado no Firefox, visual moderno (open source)')
    New-App (T 'Browsers' 'Navegadores')   'LibreWolf'             'LibreWolf.LibreWolf'               'winget'  $false (T 'privacy-focused Firefox (open source)' 'Firefox focado em privacidade (open source)')
    New-App (T 'Browsers' 'Navegadores')   'Vivaldi'               'Vivaldi.Vivaldi'                   'winget'  $false (T 'highly customizable browser' 'navegador cheio de personalização')

    New-App (T 'Communication' 'Comunicação')   'Discord'               'Discord.Discord'                   'winget'  $false (T 'voice and text chat' 'chat de voz e texto')
    New-App (T 'Communication' 'Comunicação')   'Telegram'              'Telegram.TelegramDesktop'          'winget'  $false (T 'messenger' 'mensageiro')
    New-App (T 'Communication' 'Comunicação')   'Signal'                'OpenWhisperSystems.Signal'         'winget'  $false (T 'encrypted messenger (open source)' 'mensageiro com criptografia (open source)')
    New-App (T 'Communication' 'Comunicação')   'Thunderbird (pt-BR)'   'Mozilla.Thunderbird.pt-BR'         'winget'  $false (T 'email client (open source)' 'cliente de e-mail (open source)')
    New-App (T 'Communication' 'Comunicação')   'WhatsApp'              '9NKSQGP7F2NH'                      'msstore' $false (T 'WhatsApp for desktop (Microsoft Store)' 'WhatsApp para desktop (Microsoft Store)')
    New-App (T 'Communication' 'Comunicação')   'Zoom'                  'Zoom.Zoom'                         'winget'  $false (T 'video calls' 'videochamadas')
    New-App (T 'Communication' 'Comunicação')   'Slack'                 'SlackTechnologies.Slack'           'winget'  $false (T 'work chat' 'chat de trabalho')
    New-App (T 'Communication' 'Comunicação')   'Microsoft Teams'       'Microsoft.Teams'                   'winget'  $false (T 'work meetings and chat' 'reuniões e chat de trabalho')

    New-App (T 'Media' 'Mídia')         'Spotify'               '9NCBCSZSJRSB'                      'msstore' $false (T 'music (Microsoft Store version)' 'música (versão da Microsoft Store)')
    New-App (T 'Media' 'Mídia')         'VLC'                   'VideoLAN.VLC'                      'winget'  $false (T 'plays any video or audio (open source)' 'toca qualquer vídeo ou áudio (open source)')
    New-App (T 'Media' 'Mídia')         'OBS Studio'            'OBSProject.OBSStudio'              'winget'  $false (T 'screen recording and streaming (open source)' 'gravar a tela e fazer live (open source)')
    New-App (T 'Media' 'Mídia')         'Audacity'              'Audacity.Audacity'                 'winget'  $false (T 'audio editor (open source)' 'editor de áudio (open source)')
    New-App (T 'Media' 'Mídia')         'HandBrake'             'HandBrake.HandBrake'               'winget'  $false (T 'convert and compress videos (open source)' 'converter e comprimir vídeos (open source)')
    New-App (T 'Media' 'Mídia')         'Kdenlive'              'KDE.Kdenlive'                      'winget'  $false (T 'video editor (open source)' 'editor de vídeo (open source)')
    New-App (T 'Media' 'Mídia')         'Shotcut'               'Meltytech.Shotcut'                 'winget'  $false (T 'simple video editor (open source)' 'editor de vídeo simples (open source)')
    New-App (T 'Media' 'Mídia')         'foobar2000'            'PeterPawlowski.foobar2000'         'winget'  $false (T 'lightweight music player' 'player de música leve')
    New-App (T 'Media' 'Mídia')         'ImageGlass'            'DuongDieuPhap.ImageGlass'          'winget'  $false (T 'fast image viewer (open source)' 'visualizador de imagens rápido (open source)')
    New-App (T 'Media' 'Mídia')         'Stremio'               'Stremio.Stremio'                   'winget'  $false (T 'movies and TV shows hub' 'central de filmes e séries')

    New-App (T 'Games' 'Jogos')         'Steam'                 'Valve.Steam'                       'winget'  $false (T 'game store and library' 'loja e biblioteca de jogos')
    New-App (T 'Games' 'Jogos')         'Heroic Games Launcher' 'HeroicGamesLauncher.HeroicGamesLauncher' 'winget' $false (T 'Epic, GOG and Amazon games (open source)' 'jogos da Epic, GOG e Amazon (open source)')
    New-App (T 'Games' 'Jogos')         'NVIDIA App'            'XP8CLZL93F5Z4P'                    'msstore' $false (T 'NVIDIA graphics drivers and settings' 'drivers e ajustes da placa NVIDIA')
    New-App (T 'Games' 'Jogos')         'Epic Games Launcher'   'EpicGames.EpicGamesLauncher'       'winget'  $false (T 'Epic''s store' 'loja da Epic')
    New-App (T 'Games' 'Jogos')         'EA app'                'ElectronicArts.EADesktop'          'winget'  $false (T 'EA''s store' 'loja da EA')
    New-App (T 'Games' 'Jogos')         'Ubisoft Connect'       'Ubisoft.Connect'                   'winget'  $false (T 'Ubisoft''s store' 'loja da Ubisoft')
    New-App (T 'Games' 'Jogos')         'Battle.net'            'Blizzard.BattleNet'                'winget'  $false (T 'Blizzard''s store' 'loja da Blizzard')
    New-App (T 'Games' 'Jogos')         'GOG Galaxy'            'GOG.Galaxy'                        'winget'  $false (T 'GOG''s store' 'loja da GOG')
    New-App (T 'Games' 'Jogos')         'MSI Afterburner'       'Guru3D.Afterburner'                'winget'  $false (T 'FPS and temperatures on screen in games' 'FPS e temperaturas na tela dos jogos')
    New-App (T 'Games' 'Jogos')         'Playnite'              'Playnite.Playnite'                 'winget'  $false (T 'brings every game library together (open source)' 'junta todas as bibliotecas de jogos (open source)')
    New-App (T 'Games' 'Jogos')         'Prism Launcher'        'PrismLauncher.PrismLauncher'       'winget'  $false (T 'Minecraft launcher with mods (open source)' 'launcher de Minecraft com mods (open source)')
    New-App (T 'Games' 'Jogos')         'RetroArch'             'Libretro.RetroArch'                'winget'  $false (T 'retro console emulator (open source)' 'emulador de consoles antigos (open source)')

    New-App (T 'Development' 'Programação')   'Git'                   'Git.Git'                           'winget'  $false (T 'version control (open source)' 'controle de versão (open source)')
    New-App (T 'Development' 'Programação')   'GitHub Desktop'        'GitHub.GitHubDesktop'              'winget'  $false (T 'Git with a graphical interface' 'Git com interface gráfica')
    New-App (T 'Development' 'Programação')   'VS Code'               'Microsoft.VisualStudioCode'        'winget'  $true  (T 'code editor' 'editor de código')
    New-App (T 'Development' 'Programação')   'Node.js LTS'           'OpenJS.NodeJS.LTS'                 'winget'  $false (T 'JavaScript outside the browser (open source)' 'JavaScript fora do navegador (open source)')
    New-App (T 'Development' 'Programação')   'fnm'                   'Schniz.fnm'                        'winget'  $false (T 'switches between Node.js versions (open source)' 'troca entre versões do Node.js (open source)')
    New-App (T 'Development' 'Programação')   'Python 3.14'           'Python.Python.3.14'                'winget'  $false (T 'Python language (open source)' 'linguagem Python (open source)')
    New-App (T 'Development' 'Programação')   'PowerShell 7'          'Microsoft.PowerShell'              'winget'  $false (T 'modern PowerShell (open source)' 'PowerShell moderno (open source)')
    New-App (T 'Development' 'Programação')   'Windows Terminal'      'Microsoft.WindowsTerminal'         'winget'  $false (T 'tabbed terminal (built into Windows 11)' 'terminal com abas (já vem no Windows 11)')
    New-App (T 'Development' 'Programação')   'Notepad++'             'Notepad++.Notepad++'               'winget'  $false (T 'text editor (open source)' 'editor de texto (open source)')
    New-App (T 'Development' 'Programação')   'WinMerge'              'WinMerge.WinMerge'                 'winget'  $false (T 'compare files and folders (open source)' 'comparar arquivos e pastas (open source)')
    New-App (T 'Development' 'Programação')   'DBeaver'               'DBeaver.DBeaver.Community'         'winget'  $false (T 'database client (open source)' 'cliente de banco de dados (open source)')
    New-App (T 'Development' 'Programação')   'Bruno'                 'Bruno.Bruno'                       'winget'  $false (T 'API testing, a Postman alternative (open source)' 'testar APIs, alternativa ao Postman (open source)')
    New-App (T 'Development' 'Programação')   'Insomnia'              'Insomnia.Insomnia'                 'winget'  $false (T 'API testing (open source)' 'testar APIs (open source)')
    New-App (T 'Development' 'Programação')   'Yaak'                  'Yaak.app'                          'winget'  $false (T 'API testing (open source)' 'testar APIs (open source)')
    New-App (T 'Development' 'Programação')   'Postman'               'Postman.Postman'                   'winget'  $false (T 'API testing' 'testar APIs')
    New-App (T 'Development' 'Programação')   'Dataflare'             'Dataflare.Dataflare'               'winget'  $false (T 'database client' 'cliente de banco de dados')
    New-App (T 'Development' 'Programação')   'Cursor'                'Anysphere.Cursor'                  'winget'  $false (T 'AI code editor (based on VS Code)' 'editor de código com IA (baseado no VS Code)')
    New-App (T 'Development' 'Programação')   'JetBrains Toolbox'     'JetBrains.Toolbox'                 'winget'  $false (T 'installs JetBrains IDEs' 'instala as IDEs da JetBrains')
    New-App (T 'Development' 'Programação')   'Docker Desktop'        'Docker.DockerDesktop'              'winget'  $false (T 'containers' 'containers')
    New-App (T 'Development' 'Programação')   'Zed'                   'ZedIndustries.Zed'                 'winget'  $false (T 'very fast code editor (open source)' 'editor de código muito rápido (open source)')
    New-App (T 'Development' 'Programação')   'Go'                    'GoLang.Go'                         'winget'  $false (T 'Go language (open source)' 'linguagem Go (open source)')
    New-App (T 'Development' 'Programação')   'Rustup'                'Rustlang.Rustup'                   'winget'  $false (T 'installs the Rust language (open source)' 'instala a linguagem Rust (open source)')
    New-App (T 'Development' 'Programação')   'Java (Temurin 25)'     'EclipseAdoptium.Temurin.25.JDK'    'winget'  $false (T 'Java JDK 25 LTS (open source)' 'Java JDK 25 LTS (open source)')
    New-App (T 'Development' 'Programação')   'Bun'                   'Oven-sh.Bun'                       'winget'  $false (T 'fast JavaScript runtime (open source)' 'runtime JavaScript rápido (open source)')
    New-App (T 'Development' 'Programação')   'HeidiSQL'              'HeidiSQL.HeidiSQL'                 'winget'  $false (T 'MySQL/MariaDB client (open source)' 'cliente de MySQL/MariaDB (open source)')
    New-App (T 'Development' 'Programação')   'MongoDB Compass'       'MongoDB.Compass.Full'              'winget'  $false (T 'MongoDB client' 'cliente do MongoDB')
    New-App (T 'Development' 'Programação')   'Ollama'                'Ollama.Ollama'                     'winget'  $false (T 'runs AI models on your own PC (open source)' 'roda modelos de IA no próprio PC (open source)')

    New-App (T 'Design' 'Design')        'GIMP'                  'GIMP.GIMP.3'                       'winget'  $false (T 'image editor (open source)' 'editor de imagens (open source)')
    New-App (T 'Design' 'Design')        'Inkscape'              'Inkscape.Inkscape'                 'winget'  $false (T 'vector drawing (open source)' 'desenho vetorial (open source)')
    New-App (T 'Design' 'Design')        'Krita'                 'KDE.Krita'                         'winget'  $false (T 'digital painting (open source)' 'pintura digital (open source)')
    New-App (T 'Design' 'Design')        'Blender'               'BlenderFoundation.Blender'         'winget'  $false (T '3D modeling and animation (open source)' 'modelagem 3D e animação (open source)')
    New-App (T 'Design' 'Design')        'Figma'                 'Figma.Figma'                       'winget'  $false (T 'interface design' 'design de interfaces')
    New-App (T 'Design' 'Design')        'Paint.NET'             'dotPDN.PaintDotNet'                'winget'  $false (T 'simple image editor' 'editor de imagens simples')
    New-App (T 'Design' 'Design')        'ScreenToGif'           'NickeManarin.ScreenToGif'          'winget'  $false (T 'records the screen as a GIF (open source)' 'grava a tela em GIF (open source)')

    New-App (T 'Productivity' 'Produtividade') 'LibreOffice'           'TheDocumentFoundation.LibreOffice' 'winget'  $false (T 'office suite (open source)' 'pacote de escritório (open source)')
    New-App (T 'Productivity' 'Produtividade') 'Joplin'                'Joplin.Joplin'                     'winget'  $false (T 'Markdown notes (open source)' 'notas em Markdown (open source)')
    New-App (T 'Productivity' 'Produtividade') 'SumatraPDF'            'SumatraPDF.SumatraPDF'             'winget'  $false (T 'lightweight PDF reader (open source)' 'leitor de PDF leve (open source)')
    New-App (T 'Productivity' 'Produtividade') 'Claude'                'Anthropic.Claude'                  'winget'  $false (T 'Claude desktop app' 'app do Claude para desktop')
    New-App (T 'Productivity' 'Produtividade') 'Obsidian'              'Obsidian.Obsidian'                 'winget'  $false (T 'Markdown notes' 'notas em Markdown')
    New-App (T 'Productivity' 'Produtividade') 'Notion'                'Notion.Notion'                     'winget'  $false (T 'notes, tasks and wikis' 'notas, tarefas e wikis')
    New-App (T 'Productivity' 'Produtividade') 'Adobe Acrobat Reader'  'Adobe.Acrobat.Reader.64-bit'       'winget'  $false (T 'Adobe''s PDF reader' 'leitor de PDF da Adobe')
    New-App (T 'Productivity' 'Produtividade') 'Google Drive'          'Google.GoogleDrive'                'winget'  $false (T 'syncs Google Drive with the PC' 'sincroniza o Google Drive com o PC')
    New-App (T 'Productivity' 'Produtividade') 'ONLYOFFICE'            'ONLYOFFICE.DesktopEditors'         'winget'  $false (T 'Office-compatible suite (open source)' 'escritório compatível com Office (open source)')
    New-App (T 'Productivity' 'Produtividade') 'Logseq'                'Logseq.Logseq'                     'winget'  $false (T 'connected notes (open source)' 'notas conectadas (open source)')

    New-App (T 'Security' 'Segurança')     'Bitwarden'             'Bitwarden.Bitwarden'               'winget'  $false (T 'password manager (open source)' 'gerenciador de senhas (open source)')
    New-App (T 'Security' 'Segurança')     'KeePassXC'             'KeePassXCTeam.KeePassXC'           'winget'  $false (T 'offline password manager (open source)' 'gerenciador de senhas offline (open source)')
    New-App (T 'Security' 'Segurança')     'Proton VPN'            'Proton.ProtonVPN'                  'winget'  $false (T 'VPN with a free plan (open source)' 'VPN com plano grátis (open source)')
    New-App (T 'Security' 'Segurança')     'Cloudflare One'        'Cloudflare.Warp'                   'winget'  $false (T 'Cloudflare''s WARP and 1.1.1.1 client; free VPN and Zero Trust access' 'cliente WARP e 1.1.1.1 da Cloudflare; VPN grátis e acesso Zero Trust')
    New-App (T 'Security' 'Segurança')     'Malwarebytes'          'Malwarebytes.Malwarebytes'         'winget'  $false (T 'anti-malware (second opinion to Defender)' 'antimalware (segunda opinião ao Defender)')

    New-App (T 'Utilities' 'Utilitários')   '7-Zip'                 '7zip.7zip'                         'winget'  $false (T 'file archiver (open source)' 'compactador de arquivos (open source)')
    New-App (T 'Utilities' 'Utilitários')   'WinRAR'                'RARLab.WinRAR'                     'winget'  $false (T 'file archiver (RAR)' 'compactador de arquivos (RAR)')
    New-App (T 'Utilities' 'Utilitários')   'Everything'            'voidtools.Everything'              'winget'  $false (T 'finds files on the PC instantly' 'busca arquivos no PC na hora')
    New-App (T 'Utilities' 'Utilitários')   'AnyDesk'               'AnyDesk.AnyDesk'                   'winget'  $false (T 'remote access' 'acesso remoto')
    New-App (T 'Utilities' 'Utilitários')   'HWiNFO'                'REALiX.HWiNFO'                     'winget'  $false (T 'hardware information and sensors' 'informações e sensores do hardware')
    New-App (T 'Utilities' 'Utilitários')   'CPU-Z'                 'CPUID.CPU-Z'                       'winget'  $false (T 'processor and memory information' 'informações do processador e da memória')
    New-App (T 'Utilities' 'Utilitários')   'WizTree'               'AntibodySoftware.WizTree'          'winget'  $false (T 'shows what takes up disk space' 'mostra o que ocupa espaço no disco')
    New-App (T 'Utilities' 'Utilitários')   'Flow Launcher'         'Flow-Launcher.Flow-Launcher'       'winget'  $false (T 'opens apps and files from the keyboard (open source)' 'abre apps e arquivos pelo teclado (open source)')
    New-App (T 'Utilities' 'Utilitários')   'PowerToys'             'Microsoft.PowerToys'               'winget'  $false (T 'Microsoft utilities (open source)' 'utilitários da Microsoft (open source)')
    New-App (T 'Utilities' 'Utilitários')   'ShareX'                'ShareX.ShareX'                     'winget'  $false (T 'screenshots and screen recording (open source)' 'capturas e gravação de tela (open source)')
    New-App (T 'Utilities' 'Utilitários')   'LocalSend'             'LocalSend.LocalSend'               'winget'  $false (T 'send files over the local network (open source)' 'enviar arquivos pela rede local (open source)')
    New-App (T 'Utilities' 'Utilitários')   'qBittorrent'           'qBittorrent.qBittorrent'           'winget'  $false (T 'ad-free torrent client (open source)' 'torrent sem anúncios (open source)')
    New-App (T 'Utilities' 'Utilitários')   'UniGetUI'              'Devolutions.UniGetUI'              'winget'  $false (T 'interface for WinGet; updates everything (open source)' 'interface para o WinGet; atualiza tudo (open source)')
    New-App (T 'Utilities' 'Utilitários')   'Bulk Crap Uninstaller' 'Klocman.BulkCrapUninstaller'       'winget'  $false (T 'uninstalls and cleans up leftovers (open source)' 'desinstala e limpa os restos (open source)')
    New-App (T 'Utilities' 'Utilitários')   'CrystalDiskInfo'       'CrystalDewWorld.CrystalDiskInfo'   'winget'  $false (T 'SSD/HDD health (open source)' 'saúde do SSD/HD (open source)')
)

#endregion


#region ==================== 3. WINGET ====================

function Test-WinGet { [bool](Get-Command winget -ErrorAction SilentlyContinue) }

# Installs WinGet the way Microsoft documents it:
#   1. register the "App Installer" package (often already on the PC, just not registered yet)
#   2. if that is not enough, the official Microsoft.WinGet.Client module downloads and repairs it
function Install-WinGet {
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    Write-Host (T '  registering App Installer...' '  registrando o Instalador de Aplicativo...')
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    if (Test-WinGet) { return $true }

    Write-Host (T '  downloading WinGet with the official Microsoft module (this may take a few minutes)...' '  baixando o WinGet pelo módulo oficial da Microsoft (pode levar alguns minutos)...')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Write-Host (T "  (failed: $($_.Exception.Message))" "  (falhou: $($_.Exception.Message))") -ForegroundColor DarkYellow
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
            & $line (T '  Configure-Apps — choose the apps to install' '  Configure-Apps — escolha os apps para instalar') 'Green'
            & $line (T '  ↑ ↓ move   Space select   A select category   I interactive   / search   Enter continue   Esc quit' '  ↑ ↓ navegar   Espaço marcar   A marcar categoria   I interativo   / buscar   Enter continuar   Esc sair') 'DarkGray'
            & $line (T '  [x] = install   [I] = interactive (opens the app''s own installer so you can choose the options)' '  [x] = instalar   [I] = interativo (abre o instalador do app para você escolher as opções)') 'DarkGray'
            & $line '' 'Gray'

            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count) { & $line '' 'Gray'; continue }
                if ($rows[$r].IsHeader) { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $app = $rows[$r].App
                $check  = if ($app.Selected) { '[x]' } else { '[ ]' }
                $interactive = if ($app.Source -eq 'msstore') { '   ' } elseif ($app.Interactive) { '[I]' } else { '[ ]' }
                $marker = if ($r -eq $row) { '>' } else { ' ' }
                $installedTag = if ($app.Installed) { (T 'installed · ' 'instalado · ') } else { '' }
                $text = "  $marker $check $interactive  $($app.Name.PadRight(24)) $installedTag$($app.Description)"
                $color = if ($r -eq $row) { 'Cyan' } elseif ($app.Selected) { 'Green' } elseif ($app.Installed) { 'DarkGray' } else { 'Gray' }
                & $line $text $color
            }

            & $line '' 'Gray'
            if ($searchMode) {
                $hint = if ($searchText -and -not $searchFound) { (T '   (nothing found)' '   (nada encontrado)') } else { (T '   (Enter confirms, Esc cancels)' '   (Enter confirma, Esc cancela)') }
                & $line (T "  Search: $($searchText)_$hint" "  Buscar: $($searchText)_$hint") 'Cyan'
            } else {
                $count = @($Apps | Where-Object Selected).Count
                & $line (T "  $count selected   ·   $($cursor + 1) of $($appRows.Count)" "  $count selecionado(s)   ·   $($cursor + 1) de $($appRows.Count)") 'DarkGray'
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
    Write-Host (T "`n  Configure-Apps — confirmation" "`n  Configure-Apps — confirmação") -ForegroundColor Green
    if (-not $chosen) {
        Write-Host (T "`n  No apps selected.`n" "`n  Nenhum app selecionado.`n")
        $options = @((T 'Back' 'Retornar'), (T 'Quit' 'Sair'))
        return @('Back', 'Quit')[(Choose (T 'What do you want to do?' 'O que fazer?') $options 0)]
    }
    Write-Host (T "`n  $($chosen.Count) app(s) to install:`n" "`n  $($chosen.Count) app(s) para instalar:`n")
    foreach ($app in $chosen) {
        $note = ''
        if ($app.Interactive) { $note += (T ' (interactive)' ' (interativo)') }
        if ($app.Installed)   { $note += (T ' (already installed: only updates it if there is a newer version)' ' (já instalado: só atualiza, se houver versão nova)') }
        Write-Host "    - $($app.Name)$note"
    }
    Write-Host ''
    $options = @((T 'Back' 'Retornar'), (T 'Install apps' 'Instalar apps'))
    return @('Back', 'Install')[(Choose (T 'What do you want to do?' 'O que fazer?') $options 0)]
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

    Write-Step (T 'Summary' 'Resumo')
    foreach ($r in $results) {
        switch ($r.Status) {
            'ok'      { Write-Host "  [OK]       $($r.Name)" -ForegroundColor Green }
            'already' { Write-Host (T "  [ALREADY]  $($r.Name)" "  [JÁ TINHA] $($r.Name)") -ForegroundColor DarkGray }
            'failed'  { Write-Host ((T "  [ERROR]    {0} (code 0x{1:X8})" "  [ERRO]     {0} (código 0x{1:X8})") -f $r.Name, $r.Code) -ForegroundColor Red }
        }
    }
    if ($results.Status -contains 'failed') {
        Write-Host (T "`n  To try again, run the script again and select only the ones that failed." "`n  Para tentar de novo, rode o script outra vez e marque só os que falharam.") -ForegroundColor Yellow
    }
}

#endregion


#region ==================== 6. EXECUTION ====================

Write-Host "`nConfigure-Apps" -ForegroundColor Green

# --- WinGet first (only if missing)
if (-not (Test-WinGet)) {
    Write-Host (T "`n  WinGet, the official Microsoft app installer, is not on this PC." "`n  O WinGet, o instalador de apps oficial da Microsoft, não está neste PC.") -ForegroundColor Yellow
    Write-Host (T '  It downloads and installs the apps on the list, always from the official sources.' '  É ele que baixa e instala os apps da lista, sempre das fontes oficiais.')
    if (-not (Ask (T 'Install WinGet now and go on to the app list?' 'Instalar o WinGet agora e seguir para a lista de apps?') $true)) {
        Write-Host (T 'Nothing was installed.' 'Nada foi instalado.'); return
    }
    Write-Step (T 'Installing WinGet' 'Instalando o WinGet')
    if (-not (Install-WinGet)) {
        Write-Host (T "`n  Could not install WinGet." "`n  Não foi possível instalar o WinGet.") -ForegroundColor Red
        Write-Host (T '  Install "App Installer" from the Microsoft Store and run the script again.' '  Instale o "Instalador de Aplicativo" pela Microsoft Store e rode o script de novo.')
        return
    }
    Write-Host (T '  WinGet installed.' '  WinGet instalado.') -ForegroundColor Green
}

# --- Mark the apps that are already installed
Write-Host (T '  checking which apps are already installed...' '  verificando os apps que já estão instalados...') -ForegroundColor DarkGray
$installedIds = Get-InstalledAppIds
foreach ($app in $Apps) { $app.Installed = $installedIds -contains $app.Id }

# --- Selection ↔ confirmation loop
while ($true) {
    if (-not (Show-AppSelection)) { Write-Host (T 'Nothing was installed.' 'Nada foi instalado.'); return }
    $action = Show-Confirmation
    if ($action -eq 'Quit')    { Write-Host (T 'Nothing was installed.' 'Nada foi instalado.'); return }
    if ($action -eq 'Install') { break }
}

Install-Apps
Write-Host (T "`nDone." "`nPronto.") -ForegroundColor Green

#endregion
