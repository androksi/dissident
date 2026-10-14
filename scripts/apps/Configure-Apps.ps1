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
param(
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # WinGet prints UTF-8


#region ==================== 1. HELPERS ====================


function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    Write-Host '  (use the arrows ↑ ↓ and Enter)' -ForegroundColor DarkGray
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
    Write-Warning 'Run this in the PowerShell console (powershell.exe or Terminal), not in PowerShell ISE.'
    return
}



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

# Firefox and Thunderbird have one WinGet package per language (Mozilla.Firefox.pt-BR, Mozilla.Firefox.de...);
# the ID without a suffix is English (US). Picks the Windows display language: exact match (pt-BR), then the
# language alone (de-DE -> de), then the same language in another region (es-CO -> es-AR). Otherwise English.
$FirefoxLocales     = 'ach af an ar ast az be bg bn br bs ca ca-valencia cak cs cy da de dsb el en-CA en-GB eo es-AR es-CL es-ES es-MX et eu fa ff fi fr fur fy-NL ga-IE gd gl gn gu-IN he hi-IN hr hsb hu hy-AM ia id is it ja ka kab kk km kn ko lij lt lv mk mr ms my nb-NO ne-NP nl nn-NO oc pa-IN pl pt-BR pt-PT rm ro ru sc sco si sk sl son sq sr sv-SE szl ta te tg th tl tr trs uk ur uz vi xh zh-CN zh-TW' -split ' '
$ThunderbirdLocales = 'af ar ast be bg br ca cak cs cy da de dsb el en-CA en-GB es-AR es-ES es-MX et eu fi fr fy-NL ga-IE gd gl he hr hsb hu hy-AM id is it ja ka kab kk ko lt lv ms nb-NO nl nn-NO pa-IN pl pt-BR pt-PT rm ro ru sk sl sq sr sv-SE th tr uk uz vi zh-CN zh-TW' -split ' '
function Get-MozillaLocale([string[]]$Locales) {
    $ui = [Globalization.CultureInfo]::CurrentUICulture.Name -replace '^zh-(HK|MO)$', 'zh-TW'   # Traditional Chinese
    $lang = ($ui -split '-')[0]
    $match = @($Locales | Where-Object { $_ -eq $ui })
    if (-not $match -and $lang -ne 'en') {
        $match = @($Locales | Where-Object { $_ -eq $lang }) + @($Locales | Where-Object { $_ -like "$lang-*" })
    }
    if ($match) { return $match[0] } else { return $null }
}
$ffLocale = Get-MozillaLocale $FirefoxLocales
$tbLocale = Get-MozillaLocale $ThunderbirdLocales

# Visual C++ Redistributables: one entry installs several packages. x86 always (32-bit programs need it,
# even on 64-bit Windows), x64 on 64-bit Windows, arm64 (2015+ only) on ARM PCs.
$is64  = [Environment]::Is64BitOperatingSystem
$isArm = ($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -contains 'ARM64'
$VcRedist     = @('Microsoft.VCRedist.2015+.x86') + @(if ($is64) { 'Microsoft.VCRedist.2015+.x64' }) + @(if ($isArm) { 'Microsoft.VCRedist.2015+.arm64' })
$VcRedistOld  = @(foreach ($year in 2005, 2008, 2010, 2012, 2013) { "Microsoft.VCRedist.$year.x86"; if ($is64) { "Microsoft.VCRedist.$year.x64" } })

$Apps = @(
    New-App 'Browsers'   'Brave'                 'Brave.Brave'                       'winget'  $false 'browser with an ad blocker'
    New-App 'Browsers'   'Chrome'                'Google.Chrome'                     'winget'  $false 'Google''s browser'
    New-App 'Browsers'   "Firefox ($(if ($ffLocale) { $ffLocale } else { 'en-US' }))" "Mozilla.Firefox$(if ($ffLocale) { ".$ffLocale" })" 'winget' $false 'Mozilla''s browser, in the Windows language'
    New-App 'Browsers'   'Opera GX'              'Opera.OperaGX'                     'winget'  $false 'Opera''s "gamer" browser'
    New-App 'Browsers'   'Zen Browser'           'Zen-Team.Zen-Browser'              'winget'  $false 'Firefox-based browser with a modern look (open source)'
    New-App 'Browsers'   'LibreWolf'             'LibreWolf.LibreWolf'               'winget'  $false 'privacy-focused Firefox (open source)'
    New-App 'Browsers'   'Vivaldi'               'Vivaldi.Vivaldi'                   'winget'  $false 'highly customizable browser'

    New-App 'Communication'   'Discord'               'Discord.Discord'                   'winget'  $false 'voice and text chat'
    New-App 'Communication'   'Telegram'              'Telegram.TelegramDesktop'          'winget'  $false 'messenger'
    New-App 'Communication'   'Signal'                'OpenWhisperSystems.Signal'         'winget'  $false 'encrypted messenger (open source)'
    New-App 'Communication'   "Thunderbird ($(if ($tbLocale) { $tbLocale } else { 'en-US' }))" "Mozilla.Thunderbird$(if ($tbLocale) { ".$tbLocale" })" 'winget' $false 'email client, in the Windows language (open source)'
    New-App 'Communication'   'WhatsApp'              '9NKSQGP7F2NH'                      'msstore' $false 'WhatsApp for desktop (Microsoft Store)'
    New-App 'Communication'   'Zoom'                  'Zoom.Zoom'                         'winget'  $false 'video calls'
    New-App 'Communication'   'Slack'                 'SlackTechnologies.Slack'           'winget'  $false 'work chat'
    New-App 'Communication'   'Microsoft Teams'       'Microsoft.Teams'                   'winget'  $false 'work meetings and chat'

    New-App 'Media'         'Spotify'               '9NCBCSZSJRSB'                      'msstore' $false 'music (Microsoft Store version)'
    New-App 'Media'         'VLC'                   'VideoLAN.VLC'                      'winget'  $false 'plays any video or audio (open source)'
    New-App 'Media'         'OBS Studio'            'OBSProject.OBSStudio'              'winget'  $false 'screen recording and streaming (open source)'
    New-App 'Media'         'Audacity'              'Audacity.Audacity'                 'winget'  $false 'audio editor (open source)'
    New-App 'Media'         'HandBrake'             'HandBrake.HandBrake'               'winget'  $false 'convert and compress videos (open source)'
    New-App 'Media'         'Kdenlive'              'KDE.Kdenlive'                      'winget'  $false 'video editor (open source)'
    New-App 'Media'         'Shotcut'               'Meltytech.Shotcut'                 'winget'  $false 'simple video editor (open source)'
    New-App 'Media'         'foobar2000'            'PeterPawlowski.foobar2000'         'winget'  $false 'lightweight music player'
    New-App 'Media'         'ImageGlass'            'DuongDieuPhap.ImageGlass'          'winget'  $false 'fast image viewer (open source)'
    New-App 'Media'         'Stremio'               'Stremio.Stremio'                   'winget'  $false 'movies and TV shows hub'

    New-App 'Games'         'Steam'                 'Valve.Steam'                       'winget'  $false 'game store and library'
    New-App 'Games'         'Heroic Games Launcher' 'HeroicGamesLauncher.HeroicGamesLauncher' 'winget' $false 'Epic, GOG and Amazon games (open source)'
    New-App 'Games'         'NVIDIA App'            'XP8CLZL93F5Z4P'                    'msstore' $false 'NVIDIA graphics drivers and settings'
    New-App 'Games'         'Epic Games Launcher'   'EpicGames.EpicGamesLauncher'       'winget'  $false 'Epic''s store'
    New-App 'Games'         'EA app'                'ElectronicArts.EADesktop'          'winget'  $false 'EA''s store'
    New-App 'Games'         'Ubisoft Connect'       'Ubisoft.Connect'                   'winget'  $false 'Ubisoft''s store'
    New-App 'Games'         'Battle.net'            'Blizzard.BattleNet'                'winget'  $false 'Blizzard''s store'
    New-App 'Games'         'GOG Galaxy'            'GOG.Galaxy'                        'winget'  $false 'GOG''s store'
    New-App 'Games'         'MSI Afterburner'       'Guru3D.Afterburner'                'winget'  $false 'FPS and temperatures on screen in games'
    New-App 'Games'         'Playnite'              'Playnite.Playnite'                 'winget'  $false 'brings every game library together (open source)'
    New-App 'Games'         'Prism Launcher'        'PrismLauncher.PrismLauncher'       'winget'  $false 'Minecraft launcher with mods (open source)'
    New-App 'Games'         'RetroArch'             'Libretro.RetroArch'                'winget'  $false 'retro console emulator (open source)'

    New-App 'Development'   'Git'                   'Git.Git'                           'winget'  $false 'version control (open source)'
    New-App 'Development'   'GitHub Desktop'        'GitHub.GitHubDesktop'              'winget'  $false 'Git with a graphical interface'
    New-App 'Development'   'VS Code'               'Microsoft.VisualStudioCode'        'winget'  $true  'code editor'
    New-App 'Development'   'Node.js LTS'           'OpenJS.NodeJS.LTS'                 'winget'  $false 'JavaScript outside the browser (open source)'
    New-App 'Development'   'fnm'                   'Schniz.fnm'                        'winget'  $false 'switches between Node.js versions (open source)'
    New-App 'Development'   'Python 3.14'           'Python.Python.3.14'                'winget'  $false 'Python language (open source)'
    New-App 'Development'   'PowerShell 7'          'Microsoft.PowerShell'              'winget'  $false 'modern PowerShell (open source)'
    New-App 'Development'   'Windows Terminal'      'Microsoft.WindowsTerminal'         'winget'  $false 'tabbed terminal (built into Windows 11)'
    New-App 'Development'   'Notepad++'             'Notepad++.Notepad++'               'winget'  $false 'text editor (open source)'
    New-App 'Development'   'WinMerge'              'WinMerge.WinMerge'                 'winget'  $false 'compare files and folders (open source)'
    New-App 'Development'   'DBeaver'               'DBeaver.DBeaver.Community'         'winget'  $false 'database client (open source)'
    New-App 'Development'   'Bruno'                 'Bruno.Bruno'                       'winget'  $false 'API testing, a Postman alternative (open source)'
    New-App 'Development'   'Insomnia'              'Insomnia.Insomnia'                 'winget'  $false 'API testing (open source)'
    New-App 'Development'   'Yaak'                  'Yaak.app'                          'winget'  $false 'API testing (open source)'
    New-App 'Development'   'Postman'               'Postman.Postman'                   'winget'  $false 'API testing'
    New-App 'Development'   'Dataflare'             'Dataflare.Dataflare'               'winget'  $false 'database client'
    New-App 'Development'   'Cursor'                'Anysphere.Cursor'                  'winget'  $false 'AI code editor (based on VS Code)'
    New-App 'Development'   'JetBrains Toolbox'     'JetBrains.Toolbox'                 'winget'  $false 'installs JetBrains IDEs'
    New-App 'Development'   'Docker Desktop'        'Docker.DockerDesktop'              'winget'  $false 'containers'
    New-App 'Development'   'Zed'                   'ZedIndustries.Zed'                 'winget'  $false 'very fast code editor (open source)'
    New-App 'Development'   'Go'                    'GoLang.Go'                         'winget'  $false 'Go language (open source)'
    New-App 'Development'   'Rustup'                'Rustlang.Rustup'                   'winget'  $false 'installs the Rust language (open source)'
    New-App 'Development'   'Java (Temurin 25)'     'EclipseAdoptium.Temurin.25.JDK'    'winget'  $false 'Java JDK 25 LTS (open source)'
    New-App 'Development'   'Bun'                   'Oven-sh.Bun'                       'winget'  $false 'fast JavaScript runtime (open source)'
    New-App 'Development'   'HeidiSQL'              'HeidiSQL.HeidiSQL'                 'winget'  $false 'MySQL/MariaDB client (open source)'
    New-App 'Development'   'MongoDB Compass'       'MongoDB.Compass.Full'              'winget'  $false 'MongoDB client'
    New-App 'Development'   'Ollama'                'Ollama.Ollama'                     'winget'  $false 'runs AI models on your own PC (open source)'

    New-App 'Design'        'GIMP'                  'GIMP.GIMP.3'                       'winget'  $false 'image editor (open source)'
    New-App 'Design'        'Inkscape'              'Inkscape.Inkscape'                 'winget'  $false 'vector drawing (open source)'
    New-App 'Design'        'Krita'                 'KDE.Krita'                         'winget'  $false 'digital painting (open source)'
    New-App 'Design'        'Blender'               'BlenderFoundation.Blender'         'winget'  $false '3D modeling and animation (open source)'
    New-App 'Design'        'Figma'                 'Figma.Figma'                       'winget'  $false 'interface design'
    New-App 'Design'        'Paint.NET'             'dotPDN.PaintDotNet'                'winget'  $false 'simple image editor'
    New-App 'Design'        'ScreenToGif'           'NickeManarin.ScreenToGif'          'winget'  $false 'records the screen as a GIF (open source)'

    New-App 'Productivity' 'LibreOffice'           'TheDocumentFoundation.LibreOffice' 'winget'  $false 'office suite (open source)'
    New-App 'Productivity' 'Joplin'                'Joplin.Joplin'                     'winget'  $false 'Markdown notes (open source)'
    New-App 'Productivity' 'SumatraPDF'            'SumatraPDF.SumatraPDF'             'winget'  $false 'lightweight PDF reader (open source)'
    New-App 'Productivity' 'Claude'                'Anthropic.Claude'                  'winget'  $false 'Claude desktop app'
    New-App 'Productivity' 'Obsidian'              'Obsidian.Obsidian'                 'winget'  $false 'Markdown notes'
    New-App 'Productivity' 'Notion'                'Notion.Notion'                     'winget'  $false 'notes, tasks and wikis'
    New-App 'Productivity' 'Adobe Acrobat Reader'  'Adobe.Acrobat.Reader.64-bit'       'winget'  $false 'Adobe''s PDF reader'
    New-App 'Productivity' 'Google Drive'          'Google.GoogleDrive'                'winget'  $false 'syncs Google Drive with the PC'
    New-App 'Productivity' 'ONLYOFFICE'            'ONLYOFFICE.DesktopEditors'         'winget'  $false 'Office-compatible suite (open source)'
    New-App 'Productivity' 'Logseq'                'Logseq.Logseq'                     'winget'  $false 'connected notes (open source)'

    New-App 'Security'     'Bitwarden'             'Bitwarden.Bitwarden'               'winget'  $false 'password manager (open source)'
    New-App 'Security'     'KeePassXC'             'KeePassXCTeam.KeePassXC'           'winget'  $false 'offline password manager (open source)'
    New-App 'Security'     'Proton VPN'            'Proton.ProtonVPN'                  'winget'  $false 'VPN with a free plan (open source)'
    New-App 'Security'     'Cloudflare One'        'Cloudflare.Warp'                   'winget'  $false 'Cloudflare''s WARP and 1.1.1.1 client; free VPN and Zero Trust access'
    New-App 'Security'     'Malwarebytes'          'Malwarebytes.Malwarebytes'         'winget'  $false 'anti-malware (second opinion to Defender)'

    New-App 'Utilities'   '7-Zip'                 '7zip.7zip'                         'winget'  $false 'file archiver (open source)'
    New-App 'Utilities'   'WinRAR'                'RARLab.WinRAR'                     'winget'  $false 'file archiver (RAR)'
    New-App 'Utilities'   'Everything'            'voidtools.Everything'              'winget'  $false 'finds files on the PC instantly'
    New-App 'Utilities'   'AnyDesk'               'AnyDesk.AnyDesk'                   'winget'  $false 'remote access'
    New-App 'Utilities'   'HWiNFO'                'REALiX.HWiNFO'                     'winget'  $false 'hardware information and sensors'
    New-App 'Utilities'   'CPU-Z'                 'CPUID.CPU-Z'                       'winget'  $false 'processor and memory information'
    New-App 'Utilities'   'WizTree'               'AntibodySoftware.WizTree'          'winget'  $false 'shows what takes up disk space'
    New-App 'Utilities'   'Flow Launcher'         'Flow-Launcher.Flow-Launcher'       'winget'  $false 'opens apps and files from the keyboard (open source)'
    New-App 'Utilities'   'PowerToys'             'Microsoft.PowerToys'               'winget'  $false 'Microsoft utilities (open source)'
    New-App 'Utilities'   'ShareX'                'ShareX.ShareX'                     'winget'  $false 'screenshots and screen recording (open source)'
    New-App 'Utilities'   'LocalSend'             'LocalSend.LocalSend'               'winget'  $false 'send files over the local network (open source)'
    New-App 'Utilities'   'qBittorrent'           'qBittorrent.qBittorrent'           'winget'  $false 'ad-free torrent client (open source)'
    New-App 'Utilities'   'UniGetUI'              'Devolutions.UniGetUI'              'winget'  $false 'interface for WinGet; updates everything (open source)'
    New-App 'Utilities'   'Bulk Crap Uninstaller' 'Klocman.BulkCrapUninstaller'       'winget'  $false 'uninstalls and cleans up leftovers (open source)'
    New-App 'Utilities'   'CrystalDiskInfo'       'CrystalDewWorld.CrystalDiskInfo'   'winget'  $false 'SSD/HDD health (open source)'
    New-App 'Utilities'   'Unified Remote'        'UnifiedIntents.UnifiedRemote'      'winget'  $false 'control the PC from your phone (server; the app goes on the phone)'
    New-App 'Utilities'   'Visual C++ 2015-2022'  $VcRedist                           'winget'  $false 'runtime most programs and games need (x64 + x86)'
    New-App 'Utilities'   'Visual C++ 2005-2013'  $VcRedistOld                        'winget'  $false 'older runtimes, for older games and programs (x64 + x86)'
)

#endregion


#region ==================== 3. WINGET ====================

function Test-WinGet { [bool](Get-Command winget -ErrorAction SilentlyContinue) }

# Installs WinGet the way Microsoft documents it:
#   1. register the "App Installer" package (often already on the PC, just not registered yet)
#   2. if that is not enough, the official Microsoft.WinGet.Client module downloads and repairs it
function Install-WinGet {
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    Write-Host '  registering App Installer...'
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    if (Test-WinGet) { return $true }

    Write-Host '  downloading WinGet with the official Microsoft module (this may take a few minutes)...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  (failed: $($_.Exception.Message))" -ForegroundColor DarkYellow
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
            & $line '  Configure-Apps — choose the apps to install' 'Green'
            & $line '  ↑ ↓ move   Space select   A select category   I interactive   / search   Enter continue   Esc quit' 'DarkGray'
            & $line '  [x] = install   [I] = interactive (opens the app''s own installer so you can choose the options)' 'DarkGray'
            & $line '' 'Gray'

            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count) { & $line '' 'Gray'; continue }
                if ($rows[$r].IsHeader) { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $app = $rows[$r].App
                $check  = if ($app.Selected) { '[x]' } else { '[ ]' }
                $interactive = if ($app.Source -eq 'msstore') { '   ' } elseif ($app.Interactive) { '[I]' } else { '[ ]' }
                $marker = if ($r -eq $row) { '>' } else { ' ' }
                $installedTag = if ($app.Installed) { 'installed · ' } else { '' }
                $text = "  $marker $check $interactive  $($app.Name.PadRight(24)) $installedTag$($app.Description)"
                $color = if ($r -eq $row) { 'Cyan' } elseif ($app.Selected) { 'Green' } elseif ($app.Installed) { 'DarkGray' } else { 'Gray' }
                & $line $text $color
            }

            & $line '' 'Gray'
            if ($searchMode) {
                $hint = if ($searchText -and -not $searchFound) { '   (nothing found)' } else { '   (Enter confirms, Esc cancels)' }
                & $line "  Search: $($searchText)_$hint" 'Cyan'
            } else {
                $count = @($Apps | Where-Object Selected).Count
                & $line "  $count selected   ·   $($cursor + 1) of $($appRows.Count)" 'DarkGray'
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
    Write-Host "`n  Configure-Apps — confirmation" -ForegroundColor Green
    if (-not $chosen) {
        Write-Host "`n  No apps selected.`n"
        $options = @('Back', 'Quit')
        return @('Back', 'Quit')[(Choose 'What do you want to do?' $options 0)]
    }
    Write-Host "`n  $($chosen.Count) app(s) to install:`n"
    foreach ($app in $chosen) {
        $note = ''
        if ($app.Interactive) { $note += ' (interactive)' }
        if ($app.Installed)   { $note += ' (already installed: only updates it if there is a newer version)' }
        Write-Host "    - $($app.Name)$note"
    }
    Write-Host ''
    $options = @('Back', 'Install apps')
    return @('Back', 'Install')[(Choose 'What do you want to do?' $options 0)]
}

# WinGet exit codes that mean "already installed / nothing newer to install".
$AlreadyInstalledCodes = @(-1978335189, -1978335135)   # 0x8A15002B, 0x8A150061

function Install-Apps {
    $chosen = @($Apps | Where-Object Selected)
    $results = @()
    for ($i = 0; $i -lt $chosen.Count; $i++) {
        $app = $chosen[$i]
        Write-Step "[$($i + 1)/$($chosen.Count)] $($app.Name)"
        # An entry may have several packages (Visual C++): failed if any failed, OK if any was installed
        $statuses = @(); $code = 0
        foreach ($id in @($app.Id)) {
            if (@($app.Id).Count -gt 1) { Write-Host "  $id" -ForegroundColor DarkGray }
            $wingetArgs = @('install', '--id', $id, '--exact', '--source', $app.Source,
                            '--accept-package-agreements', '--accept-source-agreements')
            if ($app.Interactive -and $app.Source -ne 'msstore') { $wingetArgs += '--interactive' }
            & winget @wingetArgs
            if ($LASTEXITCODE -eq 0) { $statuses += 'ok' }
            elseif ($LASTEXITCODE -in $AlreadyInstalledCodes) { $statuses += 'already' }
            else { $statuses += 'failed'; $code = $LASTEXITCODE }
        }
        $status = if ($statuses -contains 'failed') { 'failed' } elseif ($statuses -contains 'ok') { 'ok' } else { 'already' }
        $results += [pscustomobject]@{ Name = $app.Name; Status = $status; Code = $code }
    }

    Write-Step 'Summary'
    foreach ($r in $results) {
        switch ($r.Status) {
            'ok'      { Write-Host "  [OK]       $($r.Name)" -ForegroundColor Green }
            'already' { Write-Host "  [ALREADY]  $($r.Name)" -ForegroundColor DarkGray }
            'failed'  { Write-Host ("  [ERROR]    {0} (code 0x{1:X8})" -f $r.Name, $r.Code) -ForegroundColor Red }
        }
    }
    if ($results.Status -contains 'failed') {
        Write-Host "`n  To try again, run the script again and select only the ones that failed." -ForegroundColor Yellow
    }
}

#endregion


#region ==================== 6. EXECUTION ====================

Write-Host "`nConfigure-Apps" -ForegroundColor Green

# --- WinGet first (only if missing)
if (-not (Test-WinGet)) {
    Write-Host "`n  WinGet, the official Microsoft app installer, is not on this PC." -ForegroundColor Yellow
    Write-Host '  It downloads and installs the apps on the list, always from the official sources.'
    if (-not (Ask 'Install WinGet now and go on to the app list?' $true)) {
        Write-Host 'Nothing was installed.'; return
    }
    Write-Step 'Installing WinGet'
    if (-not (Install-WinGet)) {
        Write-Host "`n  Could not install WinGet." -ForegroundColor Red
        Write-Host '  Install "App Installer" from the Microsoft Store and run the script again.'
        return
    }
    Write-Host '  WinGet installed.' -ForegroundColor Green
}

# --- Mark the apps that are already installed
Write-Host '  checking which apps are already installed...' -ForegroundColor DarkGray
$installedIds = Get-InstalledAppIds
foreach ($app in $Apps) {
    $app.Installed = @($app.Id | Where-Object { $installedIds -notcontains $_ }).Count -eq 0   # every package of the entry
    # Firefox/Thunderbird in any language counts as installed (ESR, Beta and MSIX are other packages)
    if (-not $app.Installed -and $app.Id -match '^Mozilla\.(Firefox|Thunderbird)') {
        $app.Installed = [bool]($installedIds -cmatch ('^Mozilla\.' + $Matches[1] + '(\.[a-z]{2,3}(-[A-Za-z]+)?)?$'))
    }
}

# --- Selection ↔ confirmation loop
while ($true) {
    if (-not (Show-AppSelection)) { Write-Host 'Nothing was installed.'; return }
    $action = Show-Confirmation
    if ($action -eq 'Quit')    { Write-Host 'Nothing was installed.'; return }
    if ($action -eq 'Install') { break }
}

Install-Apps
Write-Host "`nDone." -ForegroundColor Green

#endregion
