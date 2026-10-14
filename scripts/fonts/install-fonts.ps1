#Requires -RunAsAdministrator
<#
    install-fonts.ps1 — pick fonts from a list and install them for every user of this PC

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\install-fonts.ps1
    Undo (removes only the fonts this script installed):
        powershell -ExecutionPolicy Bypass -File .\install-fonts.ps1 -Revert

    Each font comes from its official source: the project's latest GitHub release, or the
    Google Fonts repository. Installed in C:\Windows\Fonts and usable right away, no restart.
    Fonts already installed are marked in the list; files that already exist are never replaced.
    What was installed is recorded in %ProgramData%\TidyWin\fonts.json, so -Revert removes only that.

    FILE LAYOUT
        1. Helpers ................... prompts, checklist, Windows font calls
        2. Font list ................. name, family, source and which files of the package to install
        3. Download and install ...... GitHub release / Google Fonts, copy + registry, record
        4. Revert .................... removes what was recorded
        5. Execution
#>
param(
    [switch]$Revert,
    [string]$Describe,      # the panel: write the font list to this file and stop
    [string]$Answers        # the panel: install the fonts in this file, without asking
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


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
function Write-Ok([string]$Text)   { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Skip([string]$Text) { Write-Host "  [--] $Text" -ForegroundColor DarkGray }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    if ($script:Panel) { return [int](Request-Panel @{ type = 'choose'; question = $Question; options = @($Options); default = $Default }) }
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host "  Number [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host "  Type a number from 1 to $($Options.Count)." -ForegroundColor DarkYellow
        }
    }
    if (-not $script:ArrowHintShown) {
        Write-Host '  (use the arrows ↑ ↓ and Enter)' -ForegroundColor DarkGray
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
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Checklist: ↑ ↓ move, Space checks, Enter confirms. $Items: objects with Label, Checked, Note.
# Returns the checked items. Without a real console: numbers separated by commas.
function Select-Many([string]$Question, [object[]]$Items) {
    if ($script:Panel) {
        $answer = Request-Panel @{ type = 'checklist'; title = $Question; cancel = $false
            items = @($Items | ForEach-Object { @{ label = "$($_.Label)"; note = "$($_.Note)"; group = "$($_.Group)"; checked = [bool]$_.Checked } }) }
        if ($null -ne $answer) { for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = @($answer.checked) -contains $i } }
        return @($Items | Where-Object Checked)
    }
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
            Write-Host "    $($i + 1)) $mark $($Items[$i].Label)  $($Items[$i].Note)"
        }
        $answer = "$(Read-Host '  Numbers separated by commas (Enter keeps the checked ones)')".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }
    Write-Host '  (↑ ↓ move, Space checks/unchecks, Enter confirms)' -ForegroundColor DarkGray
    foreach ($it in $Items) { Write-Host '' }
    $top = [Console]::CursorTop - $Items.Count
    $sel = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Items.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                $box  = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
                $mark = if ($i -eq $sel) { '  > ' } else { '    ' }
                $line = ("$mark$box $($Items[$i].Label)  $($Items[$i].Note)")
                $line = $line.Substring(0, [Math]::Min($line.Length, [Console]::WindowWidth - 1)).PadRight([Console]::WindowWidth - 1)
                if ($i -eq $sel) { Write-Host $line -ForegroundColor Cyan -NoNewline } else { Write-Host $line -NoNewline }
            }
            $key = [Console]::ReadKey($true).Key
            if     ($key -eq 'UpArrow')   { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            elseif ($key -eq 'DownArrow') { $sel = ($sel + 1) % $Items.Count }
            elseif ($key -eq 'Spacebar')  { $Items[$sel].Checked = -not $Items[$sel].Checked }
            elseif ($key -eq 'Enter')     { break }
        }
    } finally {
        [Console]::SetCursorPosition(0, $top + $Items.Count)
        [Console]::CursorVisible = $true
    }
    return @($Items | Where-Object Checked)
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Windows font calls: load/unload a font in the current session and tell open apps the list changed.
# (The registry entry is what makes the font permanent; these make it usable without restarting.)
function Initialize-FontApi {
    if ('TidyWin.FontApi' -as [type]) { return }
    Add-Type -Namespace TidyWin -Name FontApi -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResource(string file);
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern bool RemoveFontResource(string file);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint msg, System.UIntPtr wParam, System.IntPtr lParam, uint flags, uint timeout, out System.UIntPtr result);
'@
}
function Send-FontChange {
    $r = [UIntPtr]::Zero
    # HWND_BROADCAST = 0xFFFF, WM_FONTCHANGE = 0x1D, SMTO_ABORTIFHUNG = 2 (a frozen app doesn't block us)
    [void][TidyWin.FontApi]::SendMessageTimeout([IntPtr]0xFFFF, 0x1D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$r)
}


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. FONT LIST ====================

# Group: Code, Icons (Nerd Fonts: code font + terminal icons) or Text.
# Family: name Windows shows in font menus (used to detect whether it is already installed).
# Source 'release': $Repo's latest GitHub release; $Asset is the .zip name ({v} = version, read from the
#                   release page) and $Files picks the files inside it.
# Source 'google':  $Files are file names in the google/fonts repository folder $Repo.
# No GitHub API on purpose: without a login it allows only 60 calls per hour per IP address.
function New-Font($Group, $Name, $Family, $Note, $Source, $Repo, $Asset, $Files) {
    [pscustomobject]@{ Group = $Group; Name = $Name; Family = $Family; Note = $Note; Source = $Source; Repo = $Repo; Asset = $Asset; Files = $Files }
}

# File names of a family with one file per style, upright and italic: Lato-Bold.ttf, Lato-BoldItalic.ttf...
function Get-StaticNames([string]$Prefix, [string[]]$Weights) {
    foreach ($w in $Weights) { "$Prefix-$w.ttf"; "$Prefix-$(if ($w -eq 'Regular') { 'Italic' } else { "${w}Italic" }).ttf" }
}
$AllWeights = 'Thin', 'ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black'

$Fonts = @(
    New-Font Code  'JetBrains Mono'  'JetBrains Mono'  'made for code, with ligatures (JetBrains IDEs)' release 'JetBrains/JetBrainsMono' 'JetBrainsMono-{v}.zip' '^fonts/ttf/JetBrainsMono-[^/]+\.ttf$'
    New-Font Code  'Fira Code'       'Fira Code'       'with ligatures (=> != ===)' release 'tonsky/FiraCode' 'Fira_Code_v{v}.zip' '^ttf/[^/]+\.ttf$'
    New-Font Code  'Geist Mono'      'Geist Mono'      'by Vercel, clean and modern' release 'vercel/geist-font' 'geist-font-v{v}.zip' '/GeistMono/ttf/[^/]+\.ttf$'
    New-Font Code  'Source Code Pro' 'Source Code Pro' 'by Adobe, classic and very readable' google 'ofl/sourcecodepro' $null @('SourceCodePro[wght].ttf', 'SourceCodePro-Italic[wght].ttf')
    New-Font Code  'IBM Plex Mono'   'IBM Plex Mono'   'by IBM, slightly rounded' google 'ofl/ibmplexmono' $null @(Get-StaticNames 'IBMPlexMono' ('Thin', 'ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold'))
    New-Font Code  'Hack'            'Hack'            'simple, made for small sizes' release 'source-foundry/Hack' 'Hack-v{v}-ttf.zip' '^ttf/[^/]+\.ttf$'
    New-Font Icons 'JetBrainsMono Nerd Font'  'JetBrainsMono Nerd Font'  'JetBrains Mono + icons (download ~130 MB)' release 'ryanoasis/nerd-fonts' 'JetBrainsMono.zip' '^JetBrainsMonoNerdFont-[^/]+\.ttf$'
    New-Font Icons 'CaskaydiaCove Nerd Font'  'CaskaydiaCove Nerd Font'  'Cascadia Code (Windows Terminal) + icons (download ~55 MB)' release 'ryanoasis/nerd-fonts' 'CascadiaCode.zip' '^CaskaydiaCoveNerdFont-[^/]+\.ttf$'
    New-Font Icons 'FiraCode Nerd Font'       'FiraCode Nerd Font'       'Fira Code + icons (download ~30 MB)' release 'ryanoasis/nerd-fonts' 'FiraCode.zip' '^FiraCodeNerdFont-[^/]+\.ttf$'
    New-Font Icons 'MesloLGS Nerd Font'       'MesloLGS Nerd Font'       'the one Oh My Posh and Powerlevel10k recommend (download ~110 MB)' release 'ryanoasis/nerd-fonts' 'Meslo.zip' '^MesloLGSNerdFont-[^/]+\.ttf$'
    New-Font Text  'Inter'           'Inter Variable'  'made for screens; popular in apps and websites' release 'rsms/inter' 'Inter-{v}.zip' '^InterVariable(-Italic)?\.ttf$'
    New-Font Text  'Geist'           'Geist'           'by Vercel, pairs with Geist Mono' release 'vercel/geist-font' 'geist-font-v{v}.zip' '/Geist/ttf/[^/]+\.ttf$'
    New-Font Text  'IBM Plex Sans'   'IBM Plex Sans'   'by IBM, pairs with IBM Plex Mono' google 'ofl/ibmplexsans' $null @('IBMPlexSans[wdth,wght].ttf', 'IBMPlexSans-Italic[wdth,wght].ttf')
    New-Font Text  'Roboto'          'Roboto'          'Android and Google' google 'ofl/roboto' $null @('Roboto[wdth,wght].ttf', 'Roboto-Italic[wdth,wght].ttf')
    New-Font Text  'Open Sans'       'Open Sans'       'neutral, very readable' google 'ofl/opensans' $null @('OpenSans[wdth,wght].ttf', 'OpenSans-Italic[wdth,wght].ttf')
    New-Font Text  'Noto Sans'       'Noto Sans'       'covers almost every language' google 'ofl/notosans' $null @('NotoSans[wdth,wght].ttf', 'NotoSans-Italic[wdth,wght].ttf')
    New-Font Text  'Lato'            'Lato'            'warm, good for documents' google 'ofl/lato' $null @(Get-StaticNames 'Lato' $AllWeights)
    New-Font Text  'Montserrat'      'Montserrat'      'geometric, good for titles' google 'ofl/montserrat' $null @('Montserrat[wght].ttf', 'Montserrat-Italic[wght].ttf')
    New-Font Text  'Poppins'         'Poppins'         'geometric and round, good for presentations' google 'ofl/poppins' $null @(Get-StaticNames 'Poppins' $AllWeights)
)

#endregion


#region ==================== 3. DOWNLOAD AND INSTALL ====================

$FontsDir  = Join-Path $env:windir 'Fonts'
$FontsKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$UserKey   = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$StateFile = Join-Path $env:ProgramData 'TidyWin\fonts.json'
$Work      = Join-Path $env:TEMP 'tidywin-fonts'
$script:Zips = @{}      # download URL -> zip already downloaded in this run (Geist and Geist Mono share one)
$script:Tags = @{}      # repository -> latest release tag

# Installed if the regular style is registered, for all users or only for this user
# ("JetBrains Mono (TrueType)" or "JetBrains Mono Regular (TrueType)").
function Test-FontInstalled([string]$Family) {
    $pattern = '^' + [regex]::Escape($Family) + '( Regular)? \((TrueType|OpenType)\)$'
    foreach ($key in $FontsKey, $UserKey) {
        $names = (Get-ItemProperty $key -ErrorAction SilentlyContinue).PSObject.Properties.Name
        if ($names -match $pattern) { return $true }
    }
    return $false
}

# Downloads a file, with readable errors. Saves to a plain name first and then renames:
# Invoke-WebRequest -OutFile reads "[" and "]" (Roboto[wdth,wght].ttf) as a wildcard.
function Save-Url([string]$Url, [string]$Path) {
    $tmp = Join-Path (Split-Path $Path) 'download.tmp'
    try { Invoke-WebRequest $Url -OutFile $tmp -UseBasicParsing -UserAgent 'TidyWin' -ErrorAction Stop }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 404) { throw "not found: $Url" }
        if ($status -eq 403 -or $status -eq 429) { throw 'GitHub is limiting downloads from this connection; try again later' }
        throw
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# Latest release tag, read from where github.com/<repo>/releases/latest redirects to (".../releases/tag/v2.304").
function Get-LatestTag([string]$Repo) {
    if ($script:Tags.ContainsKey($Repo)) { return $script:Tags[$Repo] }
    $req = [Net.HttpWebRequest]::Create("https://github.com/$Repo/releases/latest")
    $req.Method = 'HEAD'; $req.AllowAutoRedirect = $false; $req.UserAgent = 'TidyWin'
    $resp = $req.GetResponse()
    try { $location = $resp.Headers['Location'] } finally { $resp.Close() }
    if ($location -notmatch '/releases/tag/([^/?#]+)$') { throw "could not find the latest version of $Repo" }
    $script:Tags[$Repo] = [uri]::UnescapeDataString($Matches[1])
    return $script:Tags[$Repo]
}

# Downloads the font's package and returns its font files, extracted to their own folder.
function Get-FontFiles($Font) {
    $dir = Join-Path $Work ($Font.Name -replace '\W', '')
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    if ($Font.Source -eq 'google') {
        Write-Host "  Downloading $(@($Font.Files).Count) file(s) from Google Fonts..."
        foreach ($name in $Font.Files) {
            Save-Url "https://raw.githubusercontent.com/google/fonts/main/$($Font.Repo)/$([uri]::EscapeDataString($name))" (Join-Path $dir $name)
        }
    } else {
        if ($Font.Asset -match '\{v\}') {
            $tag = Get-LatestTag $Font.Repo
            $url = "https://github.com/$($Font.Repo)/releases/download/$tag/$($Font.Asset -replace '\{v\}', ($tag -replace '^v', ''))"
        } else {
            $url = "https://github.com/$($Font.Repo)/releases/latest/download/$($Font.Asset)"
        }
        if (-not $script:Zips.ContainsKey($url)) {
            $zip = Join-Path $Work (Split-Path $url -Leaf)
            Write-Host "  Downloading $(Split-Path $url -Leaf)..."
            Save-Url $url $zip
            $script:Zips[$url] = $zip
        }
        # Extract only the wanted files (faster than Expand-Archive on the big Nerd Font packages)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($script:Zips[$url])
        try {
            foreach ($e in $archive.Entries) {
                if ($e.Name -and $e.FullName -match $Font.Files) {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $dir $e.Name), $true)
                }
            }
        } finally { $archive.Dispose() }
    }

    $result = @(Get-ChildItem -LiteralPath $dir -File)
    if (-not $result) { throw 'no font files in the package' }
    return $result
}

# Variable font (one file with every weight): has an "fvar" table in the font's table directory.
function Test-VariableFont([string]$Path) {
    $s = [IO.File]::OpenRead($Path)
    try {
        $r = New-Object IO.BinaryReader $s
        [void]$r.ReadBytes(4)
        $b = $r.ReadBytes(2); $count = $b[0] * 256 + $b[1]     # numTables, big-endian
        [void]$r.ReadBytes(6)
        for ($i = 0; $i -lt $count; $i++) {
            if ([Text.Encoding]::ASCII.GetString($r.ReadBytes(4)) -eq 'fvar') { return $true }
            [void]$r.ReadBytes(12)
        }
        return $false
    } finally { $s.Dispose() }
}

# Registry name the way Windows writes it: "Family Style (TrueType)", without "Regular".
# A variable font gets only "Family" or "Family Italic" (its default style is just one of many).
# Read from the font itself; if that fails, the file name stands in.
function Get-FontRegName([string]$Path) {
    $kind = if ($Path -match '\.otf$') { 'OpenType' } else { 'TrueType' }
    try {
        Add-Type -AssemblyName PresentationCore
        $g  = New-Object Windows.Media.GlyphTypeface ([uri]$Path)
        $en = [Globalization.CultureInfo]'en-US'
        $family = if ($g.FamilyNames.ContainsKey($en)) { $g.FamilyNames[$en] } else { @($g.FamilyNames.Values)[0] }
        $face   = if ($g.FaceNames.ContainsKey($en))   { $g.FaceNames[$en] }   else { @($g.FaceNames.Values)[0] }
        if (Test-VariableFont $Path) { $face = if ("$($g.Style)" -eq 'Normal') { 'Regular' } else { 'Italic' } }
        $name = if (-not $face -or $face -eq 'Regular') { $family } else { "$family $face" }
    } catch {
        $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    }
    return "$name ($kind)"
}

# Copies one file to C:\Windows\Fonts, registers it and loads it. Returns what was done, or
# $null when the file or the name already exists (it may be another version: left untouched).
function Install-FontFile([IO.FileInfo]$File) {
    $dest = Join-Path $FontsDir $File.Name
    $reg  = Get-FontRegName $File.FullName
    if ((Test-Path -LiteralPath $dest) -or ($null -ne (Get-ItemProperty -Path $FontsKey -Name $reg -ErrorAction SilentlyContinue))) { return $null }
    [IO.File]::Copy($File.FullName, $dest)
    New-ItemProperty -Path $FontsKey -Name $reg -Value $File.Name -PropertyType String -Force | Out-Null
    [void][TidyWin.FontApi]::AddFontResource($dest)
    return [pscustomobject]@{ File = $File.Name; Reg = $reg }
}

# Record of what was installed: [{ Name, Files: [{ File, Reg }] }]
function Get-State {
    if (-not (Test-Path $StateFile)) { return @() }
    try { return @((Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ }) }
    catch { return @() }
}
function Save-State([object[]]$State) {
    $State = @($State | Where-Object { @($_.Files).Count -gt 0 })
    if (-not $State) { Remove-Item $StateFile -Force -ErrorAction SilentlyContinue; return }
    New-Item -ItemType Directory -Path (Split-Path $StateFile) -Force | Out-Null
    ConvertTo-Json -InputObject $State -Depth 4 | Set-Content $StateFile -Encoding UTF8
}

#endregion


#region ==================== 4. REVERT ====================

# The fonts TidyWin installed, nothing selected; only the ones picked are removed.
function Invoke-Revert {
    $state = @(Get-State)
    if ($Describe) {
        $field = if ($state) {
            [ordered]@{ tab = 'Fonts'; id = 'fonts'; kind = 'checklist'; label = ''; desc = ''; default = @()
                        items = @($state | ForEach-Object { [ordered]@{ value = $_.Name; label = $_.Name; note = ''; group = ''; status = '' } }) }
        } else {
            New-Field 'Fonts' 'Nothing' 'header' 'Nothing to undo' 'No fonts installed by TidyWin on this PC.' $null
        }
        Write-OptionsPage $Describe @($field) @('Close the apps that use these fonts, like editors, Word and the terminal, so the files can be deleted.')
        return
    }
    if (-not $script:Panel) { Write-Host "`nInstall-Fonts -Revert" -ForegroundColor Green }   # in the panel the page already has the title
    if (-not $state) { Write-Host 'No fonts installed by TidyWin on this PC, so there is nothing to undo.'; return }

    $items = @($state | ForEach-Object {
        [pscustomobject]@{ Label = $_.Name; Note = "$(@($_.Files).Count) file(s)"; Checked = $false; Entry = $_ }
    })
    if ($Answers) {
        $picked = @(([IO.File]::ReadAllText($Answers) | ConvertFrom-Json).fonts)
        $chosen = @($items | Where-Object { $picked -contains $_.Entry.Name })
    } else {
        Write-Host ''
        $chosen = @(Select-Many 'Which fonts to remove?' $items)
        Write-Host '  Close the apps that use these fonts, like editors, Word and the terminal, so the files can be deleted.' -ForegroundColor DarkYellow
    }
    if (-not $chosen) { Write-Host 'Nothing was selected, so nothing was changed.'; return }

    $locked = $false
    foreach ($c in $chosen) {
        Write-Step $c.Entry.Name
        $left = @()
        foreach ($f in @($c.Entry.Files)) {
            $path = Join-Path $FontsDir $f.File
            [void][TidyWin.FontApi]::RemoveFontResource($path)
            Remove-ItemProperty -Path $FontsKey -Name $f.Reg -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $path) {
                try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
                catch { $left += $f; continue }
            }
        }
        if ($left) {
            $locked = $true
            Write-Host "  [--] $($left.Count) file(s) in use, not deleted" -ForegroundColor Yellow
        } else {
            Write-Ok 'Removed'
        }
        $c.Entry.Files = $left
    }
    Send-FontChange
    Save-State $state

    if ($locked) {
        Write-Host "`nSome files were in use. Restart the PC and run this again to finish." -ForegroundColor Yellow
    } else {
        Write-Host "`nDone." -ForegroundColor Green
    }
}

#endregion


#region ==================== 5. EXECUTION ====================

Initialize-FontApi
if ($Revert) { Invoke-Revert; return }

if (-not $script:Panel) { Write-Host "`nInstall-Fonts" -ForegroundColor Green }   # in the panel the page already has the title
Write-Host '  Installed for every user of this PC, from each font''s official source.' -ForegroundColor DarkGray

# --- For the panel: every font, nothing selected, the installed ones marked; then stop
if ($Describe) {
    $groupNames = @{ Code = 'Code'; Icons = 'Code with terminal icons (Nerd Fonts)'; Text = 'Text' }
    $field = [ordered]@{
        tab = 'Fonts'; id = 'fonts'; kind = 'checklist'; label = ''; desc = ''; default = @()
        items = @($Fonts | ForEach-Object {
            [ordered]@{ value = $_.Name; label = $_.Name; note = ''; group = $groupNames[$_.Group]
                        status = $(if (Test-FontInstalled $_.Family) { 'Installed' } else { '' }) }
        })
    }
    $page = [ordered]@{ tabs = @('Fonts'); notes = @(); fields = @($field) }
    [IO.File]::WriteAllText($Describe, (ConvertTo-Json $page -Depth 10), (New-Object Text.UTF8Encoding $false))
    return
}

$groups = @{ Code = 'code'; Icons = 'icons'; Text = 'text' }
$width  = ($Fonts | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
$items = @($Fonts | ForEach-Object {
    $installed = Test-FontInstalled $_.Family
    $note = $groups[$_.Group].PadRight(8) + $_.Note + $(if ($installed) { '  (installed)' } else { '' })
    [pscustomobject]@{ Label = $_.Name.PadRight($width); Note = $note; Checked = $false; Font = $_ }
})
if ($Answers) {
    # --- From the panel: the fonts picked there
    $picked = @(([IO.File]::ReadAllText($Answers) | ConvertFrom-Json).fonts)
    $chosen = @($items | Where-Object { $picked -contains $_.Font.Name })
} else {
    Write-Host ''
    $chosen = @(Select-Many 'Which fonts to install?' $items)
}
if (-not $chosen) { Write-Host 'Nothing selected.'; return }

$state    = [Collections.ArrayList]@(Get-State)
$failures = @()
New-Item -ItemType Directory -Path $Work -Force | Out-Null
try {
    foreach ($c in $chosen) {
        $font = $c.Font
        Write-Step $font.Name
        try {
            $done = @()
            $skipped = 0
            foreach ($file in (Get-FontFiles $font)) {
                $r = Install-FontFile $file
                if ($r) { $done += $r } else { $skipped++ }
            }
            if ($done) {
                $entry = $state | Where-Object Name -eq $font.Name | Select-Object -First 1
                if ($entry) { $entry.Files = @($entry.Files) + $done }
                else { [void]$state.Add([pscustomobject]@{ Name = $font.Name; Files = $done }) }
                Save-State $state     # after each font: a later failure doesn't lose the record
                $extra = if ($skipped) { " ($skipped already existed)" } else { '' }
                Write-Ok "$($done.Count) style(s) installed$extra"
            } else {
                Write-Skip 'Already installed'
            }
        } catch {
            $failures += $font.Name
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} finally {
    Send-FontChange
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()     # releases the files read for their names
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    Write-Host "`nNot installed: $($failures -join ', '). Run again to retry." -ForegroundColor Yellow
}
Write-Host "`nDone. The fonts can be used now; apps that were already open may need to be reopened to see them." -ForegroundColor Green
Write-Host '  To remove them: TidyWin → Undo → Fonts' -ForegroundColor DarkGray

#endregion
