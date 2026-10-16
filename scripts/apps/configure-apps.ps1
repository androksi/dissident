#Requires -RunAsAdministrator
<#
    configure-apps.ps1 — pick apps from a list and install them with WinGet

    HOW TO RUN (Windows PowerShell as Administrator, in the regular console — not the ISE):
        powershell -ExecutionPolicy Bypass -File .\configure-apps.ps1

    In the TidyWin panel the apps show on one page, a tab per category, none selected (-Describe writes
    them for the panel, -Answers installs what was picked there). Run directly:
    1. If WinGet is missing (usually Windows 10), offers to install it.
    2. App list: ↑ ↓ move, Space selects, A selects the whole category, I toggles "interactive" install,
       / searches by name, Enter continues, Esc exits. Apps already installed are marked.
    3. Confirmation: "Back" (default) goes back to the list; "Install apps" installs them.
    Apps already installed are just skipped (or updated, if a newer version exists).

    To add an app: one line in $Apps (section 2). Find the ID with:  winget search <name>
    In the panel, the Search tab finds apps that are not in the list (-Search, section 3): only the app
    itself and others from its publisher show up, not the many apps that just mention it in their tags.

    FILE LAYOUT
        1. Helpers
        2. App list
        3. WinGet (detect / install)
        4. Selection screen
        5. Confirmation and installation
        6. Execution
#>
param(
    [string]$Describe,      # the panel: write the app list to this file and stop
    [string]$Answers,       # the panel: install the apps in this file, without asking
    [string]$Search,        # the panel's Search tab: look for this app in WinGet and the Microsoft Store...
    [string]$SearchOut      # ...and write the trusted matches to this file
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # WinGet prints UTF-8


#region ==================== PANEL ====================

# Run from the TidyWin panel ($env:TIDYWIN_PANEL = 1): the questions show up in the panel window. Each one
# goes out as a line "##TIDYWIN {json}" and the answer comes back as one JSON line on the standard input.
# Write-Host lines carry their color ([char]1 + color + [char]2 + text) so the panel can show it.
$script:Panel = $env:TIDYWIN_PANEL -eq '1'
$script:PanelLine = ''

function Write-PanelHost {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [switch]$NoNewline,
          [object]$Separator = ' ', [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor)
    $text  = (@($Object) | ForEach-Object { "$_" }) -join "$Separator"
    $color = if ($PSBoundParameters.ContainsKey('ForegroundColor')) { "$ForegroundColor" } else { '' }
    $parts = @($text -split "`r?`n")
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $script:PanelLine += [string][char]1 + $color + [char]2 + $parts[$i]
        if ($i -lt $parts.Count - 1 -or -not $NoNewline) { [Console]::Out.WriteLine($script:PanelLine); $script:PanelLine = '' }
    }
}

# Sends a question to the panel and returns the answer ($null when it was cancelled).
function Request-Panel([hashtable]$Request) {
    if ($script:PanelLine) { [Console]::Out.WriteLine($script:PanelLine); $script:PanelLine = '' }
    [Console]::Out.WriteLine('##TIDYWIN ' + (ConvertTo-Json $Request -Compress -Depth 6))
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { exit 1 }                       # the panel was closed
    return (ConvertFrom-Json $line.Trim([char]0xFEFF)).value
}

# While the panel reads the page (-Describe): what is being read now and how far (0-100; none = unknown),
# shown in the bar under its loading ring. Does nothing otherwise.
function Write-Loading([string]$Text, $Percent) {
    if (-not $script:Panel -or -not $Describe) { return }
    [Console]::Out.WriteLine('##TIDYWIN ' + (ConvertTo-Json @{ type = 'progress'; text = $Text; value = $Percent } -Compress))
}

if ($script:Panel) {
    function Write-Host {
        param([Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object, [switch]$NoNewline,
              [object]$Separator = ' ', [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor)
        Write-PanelHost @PSBoundParameters
    }
    # Typed answers: a "press Enter" pause, a folder, a file or text
    function Read-Host([Parameter(Position = 0)][object]$Prompt) {
        $q = "$Prompt".Trim()
        $type = if ($q -match '(?i)press Enter') { 'wait' } elseif ($q -match '(?i)^folder') { 'folder' } elseif ($q -match '(?i)\.json file') { 'file' } else { 'text' }
        return "$(Request-Panel @{ type = $type; question = $q })"
    }
}

# --- Options of a page in the panel (the same in every script). A field: tab, id, kind (toggle, choice,
# select, checklist, text, header), label, desc, default and more (options, items, warn, when...).
# -Describe writes the fields for the panel's page; Read-Options brings back what was chosen: the panel's
# answers file, or asked here when the script runs on its own. Nothing comes selected.
function Opt($Value, [string]$Label) { [ordered]@{ value = $Value; label = $Label } }

function New-Field([string]$Tab, [string]$Id, [string]$Kind, [string]$Label, [string]$Desc, $Default, [hashtable]$More) {
    $f = [ordered]@{ tab = $Tab; id = $Id; kind = $Kind; label = $Label; desc = $Desc; default = $Default }
    if ($More) { foreach ($k in $More.Keys) { $f[$k] = $More[$k] } }
    return $f
}

function Write-OptionsPage([string]$Path, [object[]]$Fields, [string[]]$Notes) {
    $page = [ordered]@{ tabs = @($Fields | ForEach-Object { $_.tab } | Select-Object -Unique); notes = @($Notes | Where-Object { $_ }); fields = @($Fields | Where-Object { $_ }) }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json $page -Depth 10), (New-Object Text.UTF8Encoding $false))
}

function Read-Options([object[]]$Fields, [string]$AnswersFile) {
    $values = @{}
    foreach ($f in $Fields) { if ($f.kind -ne 'header') { $values[$f.id] = $f.default } }
    if ($AnswersFile) {
        $json = [IO.File]::ReadAllText($AnswersFile) | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) { $values[$prop.Name] = $prop.Value }
        return $values
    }
    foreach ($f in $Fields) {
        if ($f.when -and "$($values[$f.when.field])" -ne "$($f.when.is)") { continue }
        switch ($f.kind) {
            'header'    { Write-Host "`n  $($f.label)" -ForegroundColor Cyan }
            'toggle'    { $values[$f.id] = Ask "$($f.label)?" $false }
            'info'      { Write-Host "  $($f.label): $($f.desc)" -ForegroundColor DarkGray }
            { $_ -in 'text', 'path' } { $values[$f.id] = "$(Read-Host "  $($f.label)")".Trim().Trim('"') }
            'checklist' { $values[$f.id] = @($f.items | Where-Object { Ask "$($f.label): $($_.label)?" $false } | ForEach-Object { $_.value }) }
            default {
                # choice and select; "Skip" leaves it as it is
                $options = @(Opt '' 'Skip') + @($f.options)
                $values[$f.id] = $options[(Choose "$($f.label):" @($options | ForEach-Object { $_.label }) 0)].value
            }
        }
    }
    return $values
}

# Yes / No (scripts that ask more define their own, the same)
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

#endregion

#region ==================== 1. HELPERS ====================


function Write-Step([string]$Text) { Write-Host "`n▸ $Text" -ForegroundColor Cyan }

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    if ($script:Panel) { return [int](Request-Panel @{ type = 'choose'; question = $Question; options = @($Options); default = $Default }) }
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

# Category, display name, WinGet ID, source ('winget' or 'msstore'; 'feature' for a Windows feature, like .NET
# Framework 3.5, turned on instead of downloaded), interactive by default (WinGet apps only), short description.
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
    New-App 'Browsers'   'Brave'                 'Brave.Brave'                       'winget'  $false 'Browser that blocks ads and trackers'
    New-App 'Browsers'   'Chrome'                'Google.Chrome'                     'winget'  $false 'Google''s browser'
    New-App 'Browsers'   "Firefox ($(if ($ffLocale) { $ffLocale } else { 'en-US' }))" "Mozilla.Firefox$(if ($ffLocale) { ".$ffLocale" })" 'winget' $false 'Mozilla''s browser, in the language of Windows'
    New-App 'Browsers'   'Opera GX'              'Opera.OperaGX'                     'winget'  $false 'Browser for gamers, with CPU and RAM limits'
    New-App 'Browsers'   'Zen Browser'           'Zen-Team.Zen-Browser'              'winget'  $false 'Firefox-based browser with a modern look'
    New-App 'Browsers'   'LibreWolf'             'LibreWolf.LibreWolf'               'winget'  $false 'Firefox focused on privacy'
    New-App 'Browsers'   'Vivaldi'               'Vivaldi.Vivaldi'                   'winget'  $false 'Browser you can customize in detail'

    New-App 'Communication'   'Discord'               'Discord.Discord'                   'winget'  $false 'Voice, video and text chat'
    New-App 'Communication'   'Telegram'              'Telegram.TelegramDesktop'          'winget'  $false 'Messenger with groups and channels'
    New-App 'Communication'   'Signal'                'OpenWhisperSystems.Signal'         'winget'  $false 'Messenger with end-to-end encryption'
    New-App 'Communication'   "Thunderbird ($(if ($tbLocale) { $tbLocale } else { 'en-US' }))" "Mozilla.Thunderbird$(if ($tbLocale) { ".$tbLocale" })" 'winget' $false 'Email client, in the language of Windows'
    New-App 'Communication'   'WhatsApp'              '9NKSQGP7F2NH'                      'msstore' $false 'WhatsApp on the desktop'
    New-App 'Communication'   'Zoom'                  'Zoom.Zoom'                         'winget'  $false 'Video calls and meetings'
    New-App 'Communication'   'Slack'                 'SlackTechnologies.Slack'           'winget'  $false 'Team chat for work'
    New-App 'Communication'   'Microsoft Teams'       'Microsoft.Teams'                   'winget'  $false 'Meetings and chat for work'

    New-App 'Media'         'Spotify'               '9NCBCSZSJRSB'                      'msstore' $false 'Music and podcasts'
    New-App 'Media'         'VLC'                   'VideoLAN.VLC'                      'winget'  $false 'Plays almost any video or audio file'
    New-App 'Media'         'OBS Studio'            'OBSProject.OBSStudio'              'winget'  $false 'Records and streams your screen'
    New-App 'Media'         'Audacity'              'Audacity.Audacity'                 'winget'  $false 'Records and edits audio'
    New-App 'Media'         'HandBrake'             'HandBrake.HandBrake'               'winget'  $false 'Converts and compresses videos'
    New-App 'Media'         'Kdenlive'              'KDE.Kdenlive'                      'winget'  $false 'Video editor'
    New-App 'Media'         'Shotcut'               'Meltytech.Shotcut'                 'winget'  $false 'Simple video editor'
    New-App 'Media'         'foobar2000'            'PeterPawlowski.foobar2000'         'winget'  $false 'Light music player'
    New-App 'Media'         'ImageGlass'            'DuongDieuPhap.ImageGlass'          'winget'  $false 'Fast image viewer'
    New-App 'Media'         'Stremio'               'Stremio.Stremio'                   'winget'  $false 'Organizes and plays movies and TV shows'

    New-App 'Games'         'Steam'                 'Valve.Steam'                       'winget'  $false 'Game store and library'
    New-App 'Games'         'Heroic Games Launcher' 'HeroicGamesLauncher.HeroicGamesLauncher' 'winget' $false 'Plays your Epic, GOG and Amazon games'
    New-App 'Games'         'NVIDIA App'            'XP8CLZL93F5Z4P'                    'msstore' $false 'Drivers and settings for NVIDIA graphics cards'
    New-App 'Games'         'Epic Games Launcher'   'EpicGames.EpicGamesLauncher'       'winget'  $false 'Epic Games store'
    New-App 'Games'         'EA app'                'ElectronicArts.EADesktop'          'winget'  $false 'EA games store'
    New-App 'Games'         'Ubisoft Connect'       'Ubisoft.Connect'                   'winget'  $false 'Ubisoft games store'
    New-App 'Games'         'Battle.net'            'Blizzard.BattleNet'                'winget'  $false 'Blizzard games store'
    New-App 'Games'         'GOG Galaxy'            'GOG.Galaxy'                        'winget'  $false 'GOG games store'
    New-App 'Games'         'MSI Afterburner'       'Guru3D.Afterburner'                'winget'  $false 'Shows FPS and temperatures in games'
    New-App 'Games'         'Playnite'              'Playnite.Playnite'                 'winget'  $false 'All your game libraries in one place'
    New-App 'Games'         'Prism Launcher'        'PrismLauncher.PrismLauncher'       'winget'  $false 'Minecraft launcher with mod support'
    New-App 'Games'         'RetroArch'             'Libretro.RetroArch'                'winget'  $false 'Emulator for old consoles'

    New-App 'Development'   'Git'                   'Git.Git'                           'winget'  $false 'Version control for code'
    New-App 'Development'   'GitHub Desktop'        'GitHub.GitHubDesktop'              'winget'  $false 'Git with buttons and windows, for GitHub'
    New-App 'Development'   'VS Code'               'Microsoft.VisualStudioCode'        'winget'  $true  'Code editor by Microsoft'
    New-App 'Development'   'Node.js LTS'           'OpenJS.NodeJS.LTS'                 'winget'  $false 'Runs JavaScript outside the browser'
    New-App 'Development'   'fnm'                   'Schniz.fnm'                        'winget'  $false 'Switches between Node.js versions'
    New-App 'Development'   'Python 3.14'           'Python.Python.3.14'                'winget'  $false 'Python programming language'
    New-App 'Development'   'PowerShell 7'          'Microsoft.PowerShell'              'winget'  $false 'Newest version of PowerShell'
    New-App 'Development'   'Windows Terminal'      'Microsoft.WindowsTerminal'         'winget'  $false 'Terminal with tabs; already in Windows 11'
    New-App 'Development'   'Notepad++'             'Notepad++.Notepad++'               'winget'  $false 'Text and code editor'
    New-App 'Development'   'WinMerge'              'WinMerge.WinMerge'                 'winget'  $false 'Compares files and folders'
    New-App 'Development'   'DBeaver'               'DBeaver.DBeaver.Community'         'winget'  $false 'Client for most databases'
    New-App 'Development'   'Bruno'                 'Bruno.Bruno'                       'winget'  $false 'Tests APIs; an alternative to Postman'
    New-App 'Development'   'Insomnia'              'Insomnia.Insomnia'                 'winget'  $false 'Tests APIs'
    New-App 'Development'   'Yaak'                  'Yaak.app'                          'winget'  $false 'Tests APIs'
    New-App 'Development'   'Postman'               'Postman.Postman'                   'winget'  $false 'Tests APIs'
    New-App 'Development'   'Dataflare'             'Dataflare.Dataflare'               'winget'  $false 'Database client'
    New-App 'Development'   'Cursor'                'Anysphere.Cursor'                  'winget'  $false 'Code editor with AI, based on VS Code'
    New-App 'Development'   'JetBrains Toolbox'     'JetBrains.Toolbox'                 'winget'  $false 'Installs and updates JetBrains IDEs'
    New-App 'Development'   'Docker Desktop'        'Docker.DockerDesktop'              'winget'  $false 'Runs apps in containers'
    New-App 'Development'   'Zed'                   'ZedIndustries.Zed'                 'winget'  $false 'Fast code editor'
    New-App 'Development'   'Go'                    'GoLang.Go'                         'winget'  $false 'Go programming language'
    New-App 'Development'   'Rustup'                'Rustlang.Rustup'                   'winget'  $false 'Installs the Rust programming language'
    New-App 'Development'   'Java (Temurin 25)'     'EclipseAdoptium.Temurin.25.JDK'    'winget'  $false 'Java development kit, version 25'
    New-App 'Development'   'Bun'                   'Oven-sh.Bun'                       'winget'  $false 'Fast JavaScript runtime'
    New-App 'Development'   'HeidiSQL'              'HeidiSQL.HeidiSQL'                 'winget'  $false 'Client for MySQL and MariaDB'
    New-App 'Development'   'MongoDB Compass'       'MongoDB.Compass.Full'              'winget'  $false 'Client for MongoDB'
    New-App 'Development'   'Ollama'                'Ollama.Ollama'                     'winget'  $false 'Runs AI models on your own PC'

    New-App 'Design'        'GIMP'                  'GIMP.GIMP.3'                       'winget'  $false 'Image editor'
    New-App 'Design'        'Inkscape'              'Inkscape.Inkscape'                 'winget'  $false 'Vector drawing'
    New-App 'Design'        'Krita'                 'KDE.Krita'                         'winget'  $false 'Digital painting'
    New-App 'Design'        'Blender'               'BlenderFoundation.Blender'         'winget'  $false '3D modeling and animation'
    New-App 'Design'        'Figma'                 'Figma.Figma'                       'winget'  $false 'Interface design'
    New-App 'Design'        'Paint.NET'             'dotPDN.PaintDotNet'                'winget'  $false 'Simple image editor'
    New-App 'Design'        'ScreenToGif'           'NickeManarin.ScreenToGif'          'winget'  $false 'Records the screen as a GIF'

    New-App 'Productivity' 'LibreOffice'           'TheDocumentFoundation.LibreOffice' 'winget'  $false 'Documents, spreadsheets and presentations'
    New-App 'Productivity' 'Joplin'                'Joplin.Joplin'                     'winget'  $false 'Notes that sync between devices'
    New-App 'Productivity' 'SumatraPDF'            'SumatraPDF.SumatraPDF'             'winget'  $false 'Light PDF reader'
    New-App 'Productivity' 'Claude'                'Anthropic.Claude'                  'winget'  $false 'Claude, the AI assistant, on the desktop'
    New-App 'Productivity' 'Obsidian'              'Obsidian.Obsidian'                 'winget'  $false 'Notes kept as plain text files'
    New-App 'Productivity' 'Notion'                'Notion.Notion'                     'winget'  $false 'Notes, tasks and wikis'
    New-App 'Productivity' 'Adobe Acrobat Reader'  'Adobe.Acrobat.Reader.64-bit'       'winget'  $false 'Adobe''s PDF reader'
    New-App 'Productivity' 'Google Drive'          'Google.GoogleDrive'                'winget'  $false 'Keeps your Google Drive files on the PC'
    New-App 'Productivity' 'ONLYOFFICE'            'ONLYOFFICE.DesktopEditors'         'winget'  $false 'Office suite that opens Word and Excel files well'
    New-App 'Productivity' 'Logseq'                'Logseq.Logseq'                     'winget'  $false 'Notes linked to each other'

    New-App 'Security'     'Bitwarden'             'Bitwarden.Bitwarden'               'winget'  $false 'Password manager'
    New-App 'Security'     'KeePassXC'             'KeePassXCTeam.KeePassXC'           'winget'  $false 'Password manager that works offline'
    New-App 'Security'     'Proton VPN'            'Proton.ProtonVPN'                  'winget'  $false 'VPN with a free plan'
    New-App 'Security'     'Cloudflare One'        'Cloudflare.Warp'                   'winget'  $false 'Free WARP VPN and 1.1.1.1 from Cloudflare'
    New-App 'Security'     'Malwarebytes'          'Malwarebytes.Malwarebytes'         'winget'  $false 'Second opinion next to Windows Security'

    New-App 'Utilities'   '7-Zip'                 '7zip.7zip'                         'winget'  $false 'Opens and creates ZIP, 7z and RAR files'
    New-App 'Utilities'   'WinRAR'                'RARLab.WinRAR'                     'winget'  $false 'Opens and creates RAR and ZIP files'
    New-App 'Utilities'   'Everything'            'voidtools.Everything'              'winget'  $false 'Finds any file on the PC instantly'
    New-App 'Utilities'   'AnyDesk'               'AnyDesk.AnyDesk'                   'winget'  $false 'Remote access to other PCs'
    New-App 'Utilities'   'HWiNFO'                'REALiX.HWiNFO'                     'winget'  $false 'Hardware details and sensors'
    New-App 'Utilities'   'CPU-Z'                 'CPUID.CPU-Z'                       'winget'  $false 'Processor and memory details'
    New-App 'Utilities'   'WizTree'               'AntibodySoftware.WizTree'          'winget'  $false 'Shows what takes up disk space'
    New-App 'Utilities'   'Flow Launcher'         'Flow-Launcher.Flow-Launcher'       'winget'  $false 'Opens apps and files from the keyboard'
    New-App 'Utilities'   'PowerToys'             'Microsoft.PowerToys'               'winget'  $false 'Extra tools from Microsoft for Windows'
    New-App 'Utilities'   'ShareX'                'ShareX.ShareX'                     'winget'  $false 'Screenshots and screen recordings'
    New-App 'Utilities'   'LocalSend'             'LocalSend.LocalSend'               'winget'  $false 'Sends files to devices on the same network'
    New-App 'Utilities'   'qBittorrent'           'qBittorrent.qBittorrent'           'winget'  $false 'Torrent client without ads'
    New-App 'Utilities'   'UniGetUI'              'Devolutions.UniGetUI'              'winget'  $false 'Updates all your apps in one window'
    New-App 'Utilities'   'Bulk Crap Uninstaller' 'Klocman.BulkCrapUninstaller'       'winget'  $false 'Uninstalls several programs and cleans up leftovers'
    New-App 'Utilities'   'CrystalDiskInfo'       'CrystalDewWorld.CrystalDiskInfo'   'winget'  $false 'Health of your SSDs and hard drives'
    New-App 'Utilities'   'Unified Remote'        'UnifiedIntents.UnifiedRemote'      'winget'  $false 'Controls the PC from your phone; the app goes on the phone'
    New-App 'Utilities'   'Lenovo Vantage'        '9WZDNCRFJ4MV'                      'msstore' $false 'Updates and settings for Lenovo PCs'
    New-App 'Utilities'   'Visual C++ 2015-2022'  $VcRedist                           'winget'  $false 'Needed by most programs and games'
    New-App 'Utilities'   'Visual C++ 2005-2013'  $VcRedistOld                        'winget'  $false 'Needed by older programs and games'
    New-App 'Utilities'   '.NET Framework 3.5'    'NetFx3'                            'feature' $false 'Needed by older programs and games'
)

#endregion


#region ==================== 3. WINGET ====================

function Test-WinGet { [bool](Get-Command winget -ErrorAction SilentlyContinue) }

# Installs WinGet the way Microsoft documents it:
#   1. register the "App Installer" package (often already on the PC, just not registered yet)
#   2. if that is not enough, the official Microsoft.WinGet.Client module downloads and repairs it
function Install-WinGet {
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    Write-Host '  Registering App Installer...'
    Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction SilentlyContinue
    if (Test-WinGet) { return $true }

    Write-Host '  Downloading WinGet with the official Microsoft module...'; Write-Host '  It may take a few minutes.' -ForegroundColor DarkGray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    return (Test-WinGet)
}

# --- Search: apps that are not in the list ---------------------------------------------------------------
# "winget search" also lists every app that only has the word in its tags (for "discord": Beeper, Rambox
# and 20 more), and others that just mention it ("Discord Media Loader"). Only trusted matches are kept:
#   the app itself ..... its name is the search ("Steam", "7-Zip"), its ID ends in it (Valve.Steam,
#                        Microsoft.VisualStudioCode), its name is the publisher plus the search ("Microsoft
#                        Visual Studio Code"), or its publisher is the search plus a generic word like Project
#                        or Team (OBSProject → "OBS Studio"; SteamDatabase is someone else)
#   its publisher's .... other packages of that publisher with the search in their name (Discord (x86),
#                        Steam Link, VLC Nightly)
# Everything else is left out. The Match column is not read: its words are translated.

# Display width of a character: WinGet's table gives East Asian wide characters two columns
function Get-CharWidth([char]$Char) {
    $n = [int]$Char
    if (($n -ge 0x1100 -and $n -le 0x115F) -or ($n -ge 0x2E80 -and $n -le 0xA4CF) -or ($n -ge 0xAC00 -and $n -le 0xD7A3) -or
        ($n -ge 0xF900 -and $n -le 0xFAFF) -or ($n -ge 0xFE30 -and $n -le 0xFE4F) -or ($n -ge 0xFF00 -and $n -le 0xFF60) -or
        ($n -ge 0xFFE0 -and $n -le 0xFFE6)) { return 2 }
    return 1
}

# The cells of a table row, cut at the columns where the header's words start (in display columns)
function Split-TableRow([string]$Line, [int[]]$Starts) {
    $cells = @(foreach ($s in $Starts) { New-Object Text.StringBuilder })
    $col = 0
    foreach ($ch in $Line.ToCharArray()) {
        $k = 0
        for ($i = $Starts.Count - 1; $i -ge 0; $i--) { if ($col -ge $Starts[$i]) { $k = $i; break } }
        [void]$cells[$k].Append($ch)
        $col += Get-CharWidth $ch
    }
    return @($cells | ForEach-Object { $_.ToString().Trim() })
}

# Name, Id and Version of what "winget search" finds in one source (with --source there is no Source column)
function Invoke-WinGetSearch([string]$Query, [string]$Source) {
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $lines = @(& winget search --query $Query --source $Source --count 40 --accept-source-agreements --disable-interactivity 2>$null |
                   ForEach-Object { ("$_" -split "`r")[-1] })
    } catch { $lines = @() } finally { [Console]::OutputEncoding = $encoding }
    $dash = [array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^-{10,}' })
    if ($dash -lt 1) { return @() }
    # Where each header word starts, in display columns
    $header = $lines[$dash - 1]
    $starts = @(foreach ($m in [regex]::Matches($header, '\S+')) {
        $w = 0; foreach ($ch in $header.Substring(0, $m.Index).ToCharArray()) { $w += Get-CharWidth $ch }; $w
    })
    if ($starts.Count -lt 3) { return @() }
    foreach ($line in $lines[($dash + 1)..($lines.Count - 1)]) {
        if (-not $line.Trim()) { continue }
        $cells = Split-TableRow $line $starts
        $id = $cells[1]
        if (-not $id -or $id -match '\s' -or $id.Contains([string][char]0x2026)) { continue }   # cut short ("…"): not safe to install
        [pscustomobject]@{ Name = $cells[0]; Id = $id; Version = $cells[2]; Source = $Source }
    }
}

# Lower-case words (letters, digits, + and #): "Notepad++" -> notepad++, "7-Zip" -> 7, zip
function Get-Words([string]$Text) { @([regex]::Matches("$Text".ToLowerInvariant(), '[\p{L}\p{Nd}+#]+') | ForEach-Object { $_.Value }) }

# Where the words of $Phrase start, together and in order, inside $Words; -1 when they are not there
function Find-Phrase([string[]]$Words, [string[]]$Phrase) {
    for ($i = 0; $i -le $Words.Count - $Phrase.Count; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Phrase.Count; $j++) { if ($Words[$i + $j] -ne $Phrase[$j]) { $ok = $false; break } }
        if ($ok) { return $i }
    }
    return -1
}

# Words a publisher adds to its own name: OBS + Project = OBSProject
$PublisherSuffixes = 'project', 'team', 'software', 'soft', 'inc', 'labs', 'lab', 'studio', 'studios', 'dev', 'devs', 'org',
                     'foundation', 'app', 'apps', 'hq', 'corp', 'corporation', 'ltd', 'llc', 'gmbh', 'official', 'community', 'io'

# The trusted matches, best first (at most 12)
function Find-TrustedApps([string]$Query) {
    $q = @(Get-Words $Query); $qJoined = $q -join ''
    if (-not $qJoined) { return @() }
    $found = @(Invoke-WinGetSearch $Query 'winget') + @(Invoke-WinGetSearch $Query 'msstore')
    # One package per language (Mozilla.Firefox.pt-BR): only the main one, when it is there too
    $ids = @($found | ForEach-Object Id)
    $found = @($found | Where-Object { -not ($_.Id -match '^(.+)\.([^.]+)$' -and $FirefoxLocales -ccontains $Matches[2] -and $ids -contains $Matches[1]) })
    $scored = foreach ($r in $found) {
        # Compared without what comes in parentheses at the end: "Mozilla Firefox (en-US)" is Mozilla Firefox
        $words = @(Get-Words ($r.Name -replace '\s*\([^()]*\)\s*$', '')); $joined = $words -join ''
        $at = Find-Phrase $words $q
        $parts = $r.Id.Split('.')
        $publisher = if ($r.Source -eq 'winget' -and $parts.Count -gt 1) { (Get-Words $parts[0]) -join '' } else { '' }
        $last = if ($publisher) { (Get-Words $parts[-1]) -join '' } else { '' }
        # The name starts with the search, or with the publisher and then the search ("Mozilla Firefox")
        $afterPublisher = $at -gt 0 -and $publisher -and (($words[0..($at - 1)]) -join '') -eq $publisher
        $exact = $joined -eq $qJoined -or ($publisher -and (
                    # VideoLAN.VLC "VLC media player", Mozilla.Firefox, Bilibili.Bilibili (not GreycLab.GMIC-Qt.GIMP, a plugin)
                    ($last -eq $qJoined -and ($at -eq 0 -or $afterPublisher -or $publisher -eq $qJoined)) -or
                    # Microsoft.VisualStudioCode "Microsoft Visual Studio Code"
                    ($afterPublisher -and $at + $q.Count -eq $words.Count) -or
                    # Telegram.TelegramDesktop "Telegram Desktop", OBSProject.OBSStudio "OBS Studio"
                    ($at -eq 0 -and $publisher.StartsWith($qJoined) -and ($publisher -eq $qJoined -or $PublisherSuffixes -contains $publisher.Substring($qJoined.Length)))))
        [pscustomobject]@{ App = $r; Exact = [bool]$exact; Related = $at -ge 0 -or $joined.Contains($qJoined); Publisher = $publisher }
    }
    $exactOnes = @($scored | Where-Object Exact)
    $publishers = @($exactOnes | Where-Object Publisher | ForEach-Object Publisher | Select-Object -Unique)
    $family = @($scored | Where-Object { -not $_.Exact -and $_.Related -and $_.Publisher -and $publishers -contains $_.Publisher })
    $seen = @{}
    @(@($exactOnes | Where-Object { $_.App.Source -eq 'winget' }) + @($exactOnes | Where-Object { $_.App.Source -ne 'winget' }) + $family |
        Where-Object { -not $seen.ContainsKey($_.App.Id) -and ($seen[$_.App.Id] = $true) } |
        Select-Object -First 12 | ForEach-Object { $_.App })
}

# --- Windows features (source 'feature'): .NET Framework 3.5 --------------------------------------------
# Not a WinGet package: a part of Windows that is turned on, and Windows downloads its files from Windows
# Update. Whether it is on: the key .NET 3.5 writes (no admin needed, and much faster than DISM).
$FeatureKeys = @{ NetFx3 = @{ Key = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5'; Value = 'Install' } }

function Test-WindowsFeature([string]$Name) {
    $k = $FeatureKeys[$Name]
    if ($k) { return (Get-ItemProperty -Path $k.Key -Name $k.Value -ErrorAction SilentlyContinue).($k.Value) -eq 1 }
    return "$((Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue).State)" -eq 'Enabled'
}

# Windows Update turned off (TidyWin → Updates → Off disables its service): features can't download
function Test-UpdatesOff { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -Name Start -ErrorAction SilentlyContinue).Start -eq 4 }

# Returns ok, already or failed, like a WinGet install
function Install-WindowsFeatureApp([string]$Name) {
    if (Test-WindowsFeature $Name) { return 'already' }
    if (Test-UpdatesOff) {
        Write-Host '  Windows Update is off (TidyWin → Updates), and Windows downloads this from it.' -ForegroundColor Yellow
        Write-Host '  Turn Windows Update back to Normal, then try again.' -ForegroundColor Yellow
        return 'failed'
    }
    Write-Host '  Turning it on: Windows downloads its files from Windows Update, it can take a few minutes.' -ForegroundColor DarkGray
    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart -ErrorAction Stop
        if ($r.RestartNeeded) { Write-Host '  Restart the PC to finish.' -ForegroundColor Yellow }
        return 'ok'
    } catch {
        Write-Host "  $($_.Exception.Message.Trim())" -ForegroundColor Red
        return 'failed'
    }
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
    if ($script:Panel) {
        $answer = Request-Panel @{ type = 'checklist'; title = 'Choose the apps to install'; search = $true
            flagLabel = 'Interactive'; flagHint = 'Opens the app''s own installer, so you choose its options'
            items = @($Apps | ForEach-Object {
                @{ label = $_.Name; group = $_.Category; checked = $_.Selected
                   note = $(if ($_.Installed) { "installed · $($_.Description)" } else { $_.Description })
                   flag = $(if ($_.Source -ne 'winget') { $null } else { $_.Interactive }) } }) }
        if ($null -eq $answer) { return $false }
        for ($i = 0; $i -lt $Apps.Count; $i++) {
            $Apps[$i].Selected = @($answer.checked) -contains $i
            if ($Apps[$i].Source -eq 'winget') { $Apps[$i].Interactive = @($answer.flags) -contains $i }
        }
        return $true
    }
    $rows =New-Object System.Collections.Generic.List[object]
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
                $interactive = if ($app.Source -ne 'winget') { '   ' } elseif ($app.Interactive) { '[I]' } else { '[ ]' }
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
                    if ($app.Source -eq 'winget') {
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
        if ($app.Source -eq 'feature') {                          # a Windows feature, not WinGet
            $status = Install-WindowsFeatureApp $app.Id
            $results += [pscustomobject]@{ Name = $app.Name; Status = $status; Code = $null }
            continue
        }
        foreach ($id in @($app.Id)) {
            if (@($app.Id).Count -gt 1) { Write-Host "  $id" -ForegroundColor DarkGray }
            $wingetArgs = @('install', '--id', $id, '--exact', '--source', $app.Source,
                            '--accept-package-agreements', '--accept-source-agreements')
            if ($app.Interactive -and $app.Source -eq 'winget') { $wingetArgs += '--interactive' }
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
            'failed'  { Write-Host ("  [ERROR]    {0}{1}" -f $r.Name, $(if ($null -ne $r.Code) { ' (code 0x{0:X8})' -f $r.Code })) -ForegroundColor Red }
        }
    }
    if ($results.Status -contains 'failed') {
        Write-Host "`n  To try again, run the script again and select only the ones that failed." -ForegroundColor Yellow
    }
}

#endregion


#region ==================== 6. EXECUTION ====================

# --- The panel's Search tab: the trusted matches, as rows to check, then stop. Each one's value is
# "source|id|name", so Apply knows how to install it; apps that are already in a tab say which.
if ($Search) {
    $result = [ordered]@{ items = @(); message = '' }
    if (-not (Test-WinGet)) {
        $result.message = 'WinGet is not on this PC yet: install an app from the list first, and WinGet comes with it.'
    } else {
        $listed = @{}
        foreach ($app in $Apps) { foreach ($id in @($app.Id)) { $listed[$id] = $app.Category } }
        $result.items = @(Find-TrustedApps $Search | ForEach-Object {
            $where = if ($_.Source -eq 'msstore') { 'Microsoft Store' } else { 'WinGet' }
            [ordered]@{
                value = "$($_.Source)|$($_.Id)|$($_.Name)"; label = $_.Name; group = ''
                note = (@($_.Id, $(if ($_.Version -and $_.Version -ne 'Unknown') { $_.Version }), $where) | Where-Object { $_ }) -join ' · '
                status = $(if ($listed.ContainsKey($_.Id)) { "Also in $($listed[$_.Id])" } else { '' })
            }
        })
        if (-not $result.items) { $result.message = "No trusted match for ""$Search"". Try the app's full name, the way its maker writes it." }
    }
    [IO.File]::WriteAllText($SearchOut, (ConvertTo-Json $result -Depth 5), (New-Object Text.UTF8Encoding $false))
    return
}

if (-not $script:Panel) { Write-Host "`nConfigure-Apps" -ForegroundColor Green }   # in the panel the page already has the title

# --- WinGet first (only if missing). The panel's page reads the list without it; Apply installs it.
Write-Loading 'Looking for WinGet' 5
$hasWinGet = Test-WinGet
if (-not $hasWinGet -and -not $Describe) {
    Write-Host "`n  WinGet, the official Microsoft app installer, is not on this PC." -ForegroundColor Yellow
    Write-Host '  It downloads and installs the apps on the list, always from the official sources.'
    if (-not $Answers -and -not (Ask 'Install WinGet now and go on to the app list?' $true)) {
        Write-Host 'Nothing was installed.'; return
    }
    Write-Step 'Installing WinGet'
    if (-not (Install-WinGet)) {
        Write-Host "`n  Could not install WinGet." -ForegroundColor Red
        Write-Host '  Install "App Installer" from the Microsoft Store and run the script again.'
        return
    }
    Write-Host '  WinGet installed.' -ForegroundColor Green
    $hasWinGet = $true
}

# --- Mark the apps that are already installed (Windows features don't need WinGet for it)
foreach ($app in @($Apps | Where-Object Source -eq 'feature')) { $app.Installed = Test-WindowsFeature $app.Id }
$updatesOff = Test-UpdatesOff
if ($hasWinGet) {
    if (-not $Describe) { Write-Host '  Checking which apps are already installed...' -ForegroundColor DarkGray }
    Write-Loading 'Checking which apps are already installed' 15
    $installedIds = Get-InstalledAppIds
    foreach ($app in $Apps) {
        if ($app.Source -eq 'feature') { continue }
        $app.Installed = @($app.Id | Where-Object { $installedIds -notcontains $_ }).Count -eq 0   # every package of the entry
        # Firefox/Thunderbird in any language counts as installed (ESR, Beta and MSIX are other packages)
        if (-not $app.Installed -and $app.Id -match '^Mozilla\.(Firefox|Thunderbird)') {
            $app.Installed = [bool]($installedIds -cmatch ('^Mozilla\.' + $Matches[1] + '(\.[a-z]{2,3}(-[A-Za-z]+)?)?$'))
        }
    }
}

# --- For the panel: a tab per category, nothing selected, then stop
# Each app by its first package ID; "Interactive" for the ones that can open their own installer.
if ($Describe) {
    $fields = foreach ($category in @($Apps | ForEach-Object Category | Select-Object -Unique)) {
        [ordered]@{
            tab = $category; id = "apps-$category"; kind = 'checklist'; label = ''; desc = ''; default = @()
            flagLabel = 'Interactive'; flagHint = 'Opens the app''s own installer, so you choose its options'
            items = @($Apps | Where-Object Category -eq $category | ForEach-Object {
                [ordered]@{
                    value = @($_.Id)[0]; label = $_.Name; note = $_.Description; group = ''
                    status = $(if ($_.Installed) { 'Installed' } else { '' })
                    flag = $(if ($_.Source -ne 'winget') { $null } else { $false })
                    # A Windows feature comes from Windows Update: say so when it is off
                    warn = $(if ($_.Source -eq 'feature' -and -not $_.Installed -and $updatesOff) { 'Windows Update is off (Updates page), and Windows downloads this from it. Turn it back to Normal first.' } else { '' })
                }
            })
        }
    }
    # Last tab: any other app, found with WinGet (the panel runs this script again with -Search)
    if ($hasWinGet) {
        $fields = @($fields) + [ordered]@{
            tab = 'Search'; id = 'found'; kind = 'search'; label = 'Find another app'; default = @()
            desc = 'Search WinGet and the Microsoft Store for an app that is not in the list. Only trusted matches show up: the app itself and others from its publisher, not the apps that just mention it.'
            placeholder = 'App name, like Telegram or GIMP'
        }
    }
    $notes = @(if (-not $hasWinGet) { 'WinGet, the Windows app installer, is not on this PC. It is installed first when you apply.' })
    $page = [ordered]@{ tabs = @($fields | ForEach-Object { $_.tab }); notes = $notes; fields = @($fields) }
    [IO.File]::WriteAllText($Describe, (ConvertTo-Json $page -Depth 10), (New-Object Text.UTF8Encoding $false))
    return
}

if ($Answers) {
    # --- From the panel: what was picked in each tab, and which ones open their own installer
    $json = [IO.File]::ReadAllText($Answers) | ConvertFrom-Json
    $picked = @(); $interactive = @(); $found = @()
    foreach ($prop in $json.PSObject.Properties) {
        if ($prop.Name -eq 'found') { $found += @($prop.Value | Where-Object { $_ }) }      # the Search tab: "source|id|name"
        elseif ($prop.Name -like '*.flags') { $interactive += @($prop.Value) } else { $picked += @($prop.Value) }
    }
    foreach ($app in $Apps) {
        $key = @($app.Id)[0]
        $app.Selected = $picked -contains $key
        $app.Interactive = $app.Source -eq 'winget' -and $interactive -contains $key
    }
    # What was found with Search: an app of the list is just checked there; the others join the list
    foreach ($f in $found) {
        $source, $id, $name = "$f" -split '\|', 3
        if ($source -notin 'winget', 'msstore' -or -not $id) { continue }
        $inList = @($Apps | Where-Object { @($_.Id) -contains $id })[0]
        if ($inList) { $inList.Selected = $true; continue }
        $app = New-App 'Search' $(if ($name) { $name } else { $id }) $id $source $false ''
        $app.Selected = $true
        $Apps += $app
    }
    if (-not @($Apps | Where-Object Selected)) { Write-Host 'Nothing was selected, so nothing was installed.'; return }
} else {
    # --- Selection ↔ confirmation loop
    while ($true) {
        if (-not (Show-AppSelection)) { Write-Host 'Nothing was installed.'; return }
        $action = Show-Confirmation
        if ($action -eq 'Quit')    { Write-Host 'Nothing was installed.'; return }
        if ($action -eq 'Install') { break }
    }
}

Install-Apps
Write-Host "`nDone." -ForegroundColor Green

#endregion