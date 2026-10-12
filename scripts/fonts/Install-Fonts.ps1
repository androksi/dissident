#Requires -RunAsAdministrator
<#
    Install-Fonts.ps1 — pick fonts from a list and install them for every user of this PC

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Install-Fonts.ps1
    Undo (removes only the fonts this script installed):
        powershell -ExecutionPolicy Bypass -File .\Install-Fonts.ps1 -Revert
    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

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
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Skip([string]$Text) { Write-Host "  [--] $Text" -ForegroundColor DarkGray }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
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

# Checklist: ↑ ↓ move, Space checks, Enter confirms. $Items: objects with Label, Checked, Note.
# Returns the checked items. Without a real console: numbers separated by commas.
function Select-Many([string]$Question, [object[]]$Items) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
            Write-Host "    $($i + 1)) $mark $($Items[$i].Label)  $($Items[$i].Note)"
        }
        $answer = "$(Read-Host (T '  Numbers separated by commas (Enter keeps the checked ones)' '  Números separados por vírgula (Enter mantém os marcados)'))".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }
    Write-Host (T '  (↑ ↓ move, Space checks/unchecks, Enter confirms)' '  (↑ ↓ navega, Espaço marca/desmarca, Enter confirma)') -ForegroundColor DarkGray
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning (T 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).')
    return
}

#endregion


#region ==================== 2. FONT LIST ====================

# Group: Code, Icons (Nerd Fonts: code font + terminal icons) or Text.
# Family: name Windows shows in font menus (used to detect whether it is already installed).
# Source 'release': $Repo's latest GitHub release, the asset matching $Asset, the files inside matching $Files.
# Source 'google':  the google/fonts repository folder $Repo, the files matching $Files.
function New-Font($Group, $Name, $Family, $Note, $Source, $Repo, $Asset, $Files) {
    [pscustomobject]@{ Group = $Group; Name = $Name; Family = $Family; Note = $Note; Source = $Source; Repo = $Repo; Asset = $Asset; Files = $Files }
}

$Fonts = @(
    New-Font Code  'JetBrains Mono'  'JetBrains Mono'  (T 'made for code, with ligatures (JetBrains IDEs)' 'feita para código, com ligaduras (IDEs da JetBrains)') release 'JetBrains/JetBrainsMono' '^JetBrainsMono-[\d.]+\.zip$' '^fonts/ttf/JetBrainsMono-[^/]+\.ttf$'
    New-Font Code  'Fira Code'       'Fira Code'       (T 'with ligatures (=> != ===)' 'com ligaduras (=> != ===)') release 'tonsky/FiraCode' '^Fira_Code_v[\d.]+\.zip$' '^ttf/[^/]+\.ttf$'
    New-Font Code  'Geist Mono'      'Geist Mono'      (T 'by Vercel, clean and modern' 'da Vercel, limpa e moderna') release 'vercel/geist-font' '^geist-font-v[\d.]+\.zip$' '/GeistMono/ttf/[^/]+\.ttf$'
    New-Font Code  'Source Code Pro' 'Source Code Pro' (T 'by Adobe, classic and very readable' 'da Adobe, clássica e muito legível') release 'adobe-fonts/source-code-pro' '^TTF-source-code-pro-.*\.zip$' '^TTF/[^/]+\.ttf$'
    New-Font Code  'IBM Plex Mono'   'IBM Plex Mono'   (T 'by IBM, slightly rounded' 'da IBM, levemente arredondada') google 'ofl/ibmplexmono' $null '\.ttf$'
    New-Font Code  'Hack'            'Hack'            (T 'simple, made for small sizes' 'simples, feita para tamanhos pequenos') release 'source-foundry/Hack' '^Hack-v[\d.]+-ttf\.zip$' '^ttf/[^/]+\.ttf$'
    New-Font Icons 'JetBrainsMono Nerd Font'  'JetBrainsMono Nerd Font'  (T 'JetBrains Mono + icons (download ~130 MB)' 'JetBrains Mono + ícones (download ~130 MB)') release 'ryanoasis/nerd-fonts' '^JetBrainsMono\.zip$' '^JetBrainsMonoNerdFont-[^/]+\.ttf$'
    New-Font Icons 'CaskaydiaCove Nerd Font'  'CaskaydiaCove Nerd Font'  (T 'Cascadia Code (Windows Terminal) + icons (download ~55 MB)' 'Cascadia Code (Windows Terminal) + ícones (download ~55 MB)') release 'ryanoasis/nerd-fonts' '^CascadiaCode\.zip$' '^CaskaydiaCoveNerdFont-[^/]+\.ttf$'
    New-Font Icons 'FiraCode Nerd Font'       'FiraCode Nerd Font'       (T 'Fira Code + icons (download ~30 MB)' 'Fira Code + ícones (download ~30 MB)') release 'ryanoasis/nerd-fonts' '^FiraCode\.zip$' '^FiraCodeNerdFont-[^/]+\.ttf$'
    New-Font Icons 'MesloLGS Nerd Font'       'MesloLGS Nerd Font'       (T 'the one Oh My Posh and Powerlevel10k recommend (download ~110 MB)' 'a que o Oh My Posh e o Powerlevel10k recomendam (download ~110 MB)') release 'ryanoasis/nerd-fonts' '^Meslo\.zip$' '^MesloLGSNerdFont-[^/]+\.ttf$'
    New-Font Text  'Inter'           'Inter Variable'  (T 'made for screens; popular in apps and websites' 'feita para telas; muito usada em apps e sites') release 'rsms/inter' '^Inter-[\d.]+\.zip$' '^InterVariable(-Italic)?\.ttf$'
    New-Font Text  'Geist'           'Geist'           (T 'by Vercel, pairs with Geist Mono' 'da Vercel, combina com a Geist Mono') release 'vercel/geist-font' '^geist-font-v[\d.]+\.zip$' '/Geist/ttf/[^/]+\.ttf$'
    New-Font Text  'IBM Plex Sans'   'IBM Plex Sans'   (T 'by IBM, pairs with IBM Plex Mono' 'da IBM, combina com a IBM Plex Mono') google 'ofl/ibmplexsans' $null '\.ttf$'
    New-Font Text  'Roboto'          'Roboto'          (T 'Android and Google' 'Android e Google') google 'ofl/roboto' $null '\.ttf$'
    New-Font Text  'Open Sans'       'Open Sans'       (T 'neutral, very readable' 'neutra, muito legível') google 'ofl/opensans' $null '\.ttf$'
    New-Font Text  'Noto Sans'       'Noto Sans'       (T 'covers almost every language' 'cobre quase todos os idiomas') google 'ofl/notosans' $null '\.ttf$'
    New-Font Text  'Lato'            'Lato'            (T 'warm, good for documents' 'calorosa, boa para documentos') google 'ofl/lato' $null '\.ttf$'
    New-Font Text  'Montserrat'      'Montserrat'      (T 'geometric, good for titles' 'geométrica, boa para títulos') google 'ofl/montserrat' $null '\.ttf$'
    New-Font Text  'Poppins'         'Poppins'         (T 'geometric and round, good for presentations' 'geométrica e redonda, boa para apresentações') google 'ofl/poppins' $null '\.ttf$'
)

#endregion


#region ==================== 3. DOWNLOAD AND INSTALL ====================

$FontsDir  = Join-Path $env:windir 'Fonts'
$FontsKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$UserKey   = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$StateFile = Join-Path $env:ProgramData 'TidyWin\fonts.json'
$Work      = Join-Path $env:TEMP 'tidywin-fonts'
$script:Zips = @{}      # download URL -> zip already downloaded in this run (Geist and Geist Mono share one)

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

# GitHub API call. Without a login GitHub allows 60 per hour; say so instead of a raw 403.
function Get-GitHub([string]$Path) {
    try { return Invoke-RestMethod "https://api.github.com/$Path" -UseBasicParsing -Headers @{ 'User-Agent' = 'TidyWin' } -ErrorAction Stop }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 403 -or $status -eq 429) { throw (T 'GitHub download limit reached; try again in an hour' 'limite de downloads do GitHub atingido; tente de novo daqui a uma hora') }
        throw
    }
}

# Downloads the font's package and returns its font files, extracted to their own folder.
function Get-FontFiles($Font) {
    $dir = Join-Path $Work ($Font.Name -replace '\W', '')
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    if ($Font.Source -eq 'google') {
        $list = @((Get-GitHub "repos/google/fonts/contents/$($Font.Repo)") | ForEach-Object { $_ })   # unroll the JSON array
        $files = @($list | Where-Object { $_.type -eq 'file' -and $_.name -match $Font.Files })
        if (-not $files) { throw (T 'no font files found' 'nenhum arquivo de fonte encontrado') }
        Write-Host (T "  downloading $($files.Count) file(s) ($(Format-Size ($files | Measure-Object size -Sum).Sum))..." "  baixando $($files.Count) arquivo(s) ($(Format-Size ($files | Measure-Object size -Sum).Sum))...")
        $i = 0
        foreach ($f in $files) {
            # Names like "Roboto[wdth,wght].ttf": download to a plain name, then rename (OutFile reads [] as a wildcard)
            $tmp = Join-Path $dir "download$i.tmp"; $i++
            Invoke-WebRequest $f.download_url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
            Move-Item -LiteralPath $tmp -Destination (Join-Path $dir $f.name) -Force
        }
    } else {
        $release = Get-GitHub "repos/$($Font.Repo)/releases/latest"
        $asset = @($release.assets | Where-Object { $_.name -match $Font.Asset })[0]
        if (-not $asset) { throw (T "package not found in the $($Font.Repo) release" "pacote não encontrado na versão do $($Font.Repo)") }
        $url = $asset.browser_download_url
        if (-not $script:Zips.ContainsKey($url)) {
            $zip = Join-Path $Work $asset.name
            Write-Host (T "  downloading $($asset.name) ($(Format-Size $asset.size))..." "  baixando $($asset.name) ($(Format-Size $asset.size))...")
            Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -ErrorAction Stop
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
    if (-not $result) { throw (T 'no font files in the package' 'nenhum arquivo de fonte no pacote') }
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

function Invoke-Revert {
    Write-Host "`nInstall-Fonts -Revert" -ForegroundColor Green
    $state = @(Get-State)
    if (-not $state) { Write-Host (T '  No fonts installed by TidyWin on this PC.' '  Nenhuma fonte instalada pelo TidyWin neste PC.'); return }

    $items = @($state | ForEach-Object {
        [pscustomobject]@{ Label = $_.Name; Note = (T "$(@($_.Files).Count) file(s)" "$(@($_.Files).Count) arquivo(s)"); Checked = $true; Entry = $_ }
    })
    Write-Host ''
    $chosen = @(Select-Many (T 'Which fonts to remove?' 'Quais fontes remover?') $items)
    if (-not $chosen) { Write-Host (T 'Nothing selected.' 'Nada selecionado.'); return }
    Write-Host (T '  Close the apps that use these fonts (editors, Word, the terminal...) so the files can be deleted.' '  Feche os apps que usam essas fontes (editores, Word, o terminal...) para os arquivos poderem ser apagados.') -ForegroundColor DarkYellow

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
            Write-Host (T "  [--] $($left.Count) file(s) in use, not deleted" "  [--] $($left.Count) arquivo(s) em uso, não apagado(s)") -ForegroundColor Yellow
        } else {
            Write-Ok (T 'removed' 'removida')
        }
        $c.Entry.Files = $left
    }
    Send-FontChange
    Save-State $state

    if ($locked) {
        Write-Host (T "`nSome files were in use. Restart the PC and run this again to finish." "`nAlguns arquivos estavam em uso. Reinicie o PC e rode de novo para terminar.") -ForegroundColor Yellow
    } else {
        Write-Host (T "`nDone." "`nPronto.") -ForegroundColor Green
    }
}

#endregion


#region ==================== 5. EXECUTION ====================

Initialize-FontApi
if ($Revert) { Invoke-Revert; return }

Write-Host "`nInstall-Fonts" -ForegroundColor Green
Write-Host (T '  Installed for every user of this PC, from each font''s official source.' '  Instaladas para todos os usuários do PC, da fonte oficial de cada uma.') -ForegroundColor DarkGray

$groups = @{ Code = (T 'code' 'código'); Icons = (T 'icons' 'ícones'); Text = (T 'text' 'texto') }
$width  = ($Fonts | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
$items = @($Fonts | ForEach-Object {
    $installed = Test-FontInstalled $_.Family
    $note = $groups[$_.Group].PadRight(8) + $_.Note + $(if ($installed) { T '  (installed)' '  (instalada)' } else { '' })
    [pscustomobject]@{ Label = $_.Name.PadRight($width); Note = $note; Checked = $false; Font = $_ }
})
Write-Host ''
$chosen = @(Select-Many (T 'Which fonts to install?' 'Quais fontes instalar?') $items)
if (-not $chosen) { Write-Host (T 'Nothing selected.' 'Nada selecionado.'); return }

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
                $extra = if ($skipped) { T " ($skipped already existed)" " ($skipped já existiam)" } else { '' }
                Write-Ok (T "$($done.Count) style(s) installed$extra" "$($done.Count) estilo(s) instalado(s)$extra")
            } else {
                Write-Skip (T 'already installed' 'já instalada')
            }
        } catch {
            $failures += $font.Name
            Write-Host (T "  [ERROR] $($_.Exception.Message)" "  [ERRO] $($_.Exception.Message)") -ForegroundColor Red
        }
    }
} finally {
    Send-FontChange
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()     # releases the files read for their names
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) {
    Write-Host (T "`nNot installed: $($failures -join ', '). Run again to retry." "`nNão instaladas: $($failures -join ', '). Rode de novo para tentar outra vez.") -ForegroundColor Yellow
}
Write-Host (T "`nDone. The fonts can be used now; apps that were already open may need to be reopened to see them." "`nPronto. As fontes já podem ser usadas; apps que já estavam abertos podem precisar ser reabertos para vê-las.") -ForegroundColor Green
Write-Host (T '  To remove them: irm androksi.github.io/tidywin/fonts-revert | iex' '  Para remover: irm androksi.github.io/tidywin/fonts-revert | iex') -ForegroundColor DarkGray

#endregion
