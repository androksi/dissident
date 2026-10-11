<#
    Get-Wallpapers.ps1 — pick wallpapers from the TidyWin collection and download them

    HOW TO RUN (Windows PowerShell 5.1):
        powershell -ExecutionPolicy Bypass -File .\Get-Wallpapers.ps1
    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

    Shows the list of wallpapers (previews: github.com/androksi/tidywin/blob/main/docs/wallpapers.md),
    you check the ones you want, choose the folder (Pictures\Wallpapers by default) and they are
    downloaded at the end. Optionally sets one of them as the desktop background.
    Files that already exist in the folder are skipped. Nothing else is changed.
    To remove: delete the downloaded images (and the folder, if it was created).
#>
param(
    [ValidateSet('en', 'pt')]
    [string]$Lang,
    [string]$Base = 'https://androksi.github.io/tidywin'      # where the wallpapers are published (GitHub Pages)
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Gallery = 'https://github.com/androksi/tidywin/blob/main/docs/wallpapers.md'


#region ==================== 1. HELPERS ====================

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host (T "  Number [$($Default + 1)]" "  Número [$($Default + 1)]"))".Trim()
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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Desktop background through the same Windows call the Settings app uses. "Fill" style.
function Set-DesktopWallpaper([string]$Path) {
    $desktop = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'     # 10 = Fill
    Set-ItemProperty $desktop -Name TileWallpaper  -Value '0'
    $build = [Environment]::OSVersion.Version.Build
    if ($build -ge 22000) {                                         # Windows 11: leave Windows Spotlight
        $spot = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings'
        if (-not (Test-Path $spot)) { New-Item $spot -Force | Out-Null }
        Set-ItemProperty $spot -Name EnabledState -Value 0 -Type DWord
    }
    if (-not ('TidyWin.Wallpaper' -as [type])) {
        Add-Type -Namespace TidyWin -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
    }
    # SPI_SETDESKWALLPAPER = 0x14; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    if (-not [TidyWin.Wallpaper]::SystemParametersInfo(0x14, 0, $Path, 3)) { throw (T 'Windows did not accept the image' 'o Windows não aceitou a imagem') }
}

#endregion


#region ==================== 2. EXECUTION ====================

Write-Host "`nGet-Wallpapers" -ForegroundColor Green

# --- List (published with the site; new images in the repo show up here automatically)
try {
    $list = @((Invoke-RestMethod "$Base/assets/wallpapers/index.json" -UseBasicParsing -ErrorAction Stop) | ForEach-Object { $_ })   # unroll the JSON array
} catch {
    Write-Host (T "Could not get the list of wallpapers ($Base/assets/wallpapers/index.json)." "Não foi possível baixar a lista de papéis de parede ($Base/assets/wallpapers/index.json).") -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    return
}
if (-not $list) { Write-Host (T 'The list is empty.' 'A lista está vazia.'); return }

Write-Host (T "  Previews: $Gallery" "  Prévias: $Gallery") -ForegroundColor DarkGray
if (Ask (T 'Open the previews in the browser first?' 'Abrir as prévias no navegador antes?') $false) { Start-Process $Gallery }

$items = @($list | ForEach-Object {
    [pscustomobject]@{ Label = $_.name; Note = "$($_.width)x$($_.height), $(Format-Size $_.size)"; Checked = $false; File = $_.file; Size = $_.size }
})
Write-Host ''
$chosen = @(Select-Many (T 'Which ones to download?' 'Quais baixar?') $items)
if (-not $chosen) { Write-Host (T 'Nothing selected.' 'Nada selecionado.'); return }

# --- Destination
$pictures = [Environment]::GetFolderPath('MyPictures')
if (-not $pictures) { $pictures = Join-Path $HOME 'Pictures' }
$folders = @((Join-Path $pictures 'Wallpapers'), $pictures, (Join-Path $HOME 'Downloads'))
$labels  = @($folders) + (T 'Other folder (type the path)' 'Outra pasta (digitar o caminho)')
$pick = Choose (T 'Save to:' 'Salvar em:') $labels 0
if ($pick -eq $labels.Count - 1) {
    $dest = "$(Read-Host (T '  Folder' '  Pasta'))".Trim().Trim('"')
} else {
    $dest = $folders[$pick]
}
try { New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null }
catch { Write-Host (T "Could not use the folder: $dest" "Não foi possível usar a pasta: $dest") -ForegroundColor Red; return }

# --- Download
Write-Step (T "Downloading $($chosen.Count) wallpaper(s)" "Baixando $($chosen.Count) papel(éis) de parede")
$saved = @()
foreach ($w in $chosen) {
    $target = Join-Path $dest $w.File
    if (Test-Path -LiteralPath $target) {
        Write-Host (T "  [--] $($w.File) already exists, skipped" "  [--] $($w.File) já existe, pulado") -ForegroundColor DarkGray
        $saved += $target
        continue
    }
    try {
        Invoke-WebRequest "$Base/assets/wallpapers/$($w.File)" -OutFile $target -UseBasicParsing -ErrorAction Stop
        Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
        Write-Host "$($w.File)  ($(Format-Size $w.Size))"
        $saved += $target
    } catch {
        Write-Host (T "  [ERROR] $($w.File): $($_.Exception.Message)" "  [ERRO] $($w.File): $($_.Exception.Message)") -ForegroundColor Red
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    }
}
if (-not $saved) { return }

# --- Optional: use one as the desktop background
$noneLabel = T "Don't change the background" 'Não mudar o fundo'
$bgLabels = @($saved | ForEach-Object { Split-Path $_ -Leaf }) + $noneLabel
Write-Host ''
$bg = Choose (T 'Use one as the desktop background?' 'Usar um deles como fundo da área de trabalho?') $bgLabels ($bgLabels.Count - 1)
if ($bg -lt $saved.Count) {
    try { Set-DesktopWallpaper $saved[$bg]; Write-Host (T '  [OK] desktop background changed' '  [OK] fundo da área de trabalho trocado') -ForegroundColor Green }
    catch { Write-Host (T "  [ERROR] $($_.Exception.Message)" "  [ERRO] $($_.Exception.Message)") -ForegroundColor Red }
}

Write-Host (T "`nDone. Wallpapers in: $dest" "`nPronto. Papéis de parede em: $dest") -ForegroundColor Green

#endregion
