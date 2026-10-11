#Requires -RunAsAdministrator
<#
    Backup-Apps.ps1 — saves the list of installed apps and reinstalls them on another PC (or after formatting)

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Backup-Apps.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\Backup-Apps.ps1 -Import     (after formatting)

    Export: saves a tidywin-apps-<PC>-<date>.json file with every app WinGet knows (Microsoft Store
    apps included). Save it somewhere that survives the format: OneDrive, Google Drive, a USB drive.
    Import: finds that file (Desktop, Documents, Downloads, OneDrive), shows the apps and installs them.
    Apps that are already installed or no longer exist in WinGet are skipped.

    Only the apps are saved: not their settings, logins or files.
    Leaves nothing on the PC besides the .json you saved; delete it whenever you want.

    FILE LAYOUT
        1. Helpers
        2. Export
        3. Import
        4. Execution
#>
param(
    [switch]$Export,
    [switch]$Import
)

$ErrorActionPreference = 'Continue'


#region ==================== 1. HELPERS ====================

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host "  Número [$($Default + 1)]")".Trim()
            if ($answer -eq '') { return $Default }
            $n = 0
            if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
            Write-Host "  Digite um número de 1 a $($Options.Count)." -ForegroundColor DarkYellow
        }
    }
    if (-not $script:ArrowHintShown) {
        Write-Host '  (use as setas ↑ ↓ e Enter)' -ForegroundColor DarkGray
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

# Yes/no question shown as a "Sim / Não" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Sim', 'Não') $(if ($Default) { 0 } else { 1 })) -eq 0
}

# Folders where the file is saved and searched, in this order (only the ones that exist).
function Get-BackupFolders {
    $list = [ordered]@{
        'Área de Trabalho' = [Environment]::GetFolderPath('Desktop')
        'Documentos'       = [Environment]::GetFolderPath('MyDocuments')
        'Downloads'        = Join-Path $env:USERPROFILE 'Downloads'
        'OneDrive'         = $env:OneDrive
    }
    foreach ($name in @($list.Keys)) { if (-not $list[$name] -or -not (Test-Path $list[$name])) { $list.Remove($name) } }
    $list
}

# Package IDs inside an export file.
function Get-PackageIds([string]$File) {
    $json = Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json
    @($json.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
}

#endregion


#region ==================== 2. EXPORT ====================

function Invoke-Export {
    Write-Host "`nBackup-Apps -Export" -ForegroundColor Green
    $folders = Get-BackupFolders
    $names = @($folders.Keys) + 'Outra pasta (digitar o caminho)'
    $default = [math]::Max(0, [array]::IndexOf(@($folders.Keys), 'OneDrive'))
    $choice = Choose 'Onde salvar a lista de apps? (escolha um lugar que não some ao formatar)' $names $default
    if ($choice -eq $names.Count - 1) {
        $dir = "$(Read-Host '  Pasta')".Trim().Trim('"')
        if (-not (Test-Path $dir -PathType Container)) { Write-Host "  Pasta não encontrada: $dir" -ForegroundColor Red; return }
    } else {
        $dir = $folders[$names[$choice]]
    }
    $file = Join-Path $dir ("tidywin-apps-{0}-{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))

    Write-Step 'Gerando a lista com o WinGet'
    Write-Host '  (apps que não existem no WinGet aparecem como aviso e ficam de fora)' -ForegroundColor DarkGray
    & winget export -o $file --accept-source-agreements
    if (-not (Test-Path $file)) { Write-Host "`nNão foi possível criar o arquivo." -ForegroundColor Red; return }

    $ids = Get-PackageIds $file
    Write-Host "`nPronto: $($ids.Count) apps salvos em" -ForegroundColor Green
    Write-Host "  $file"
    Write-Host 'Depois de formatar, rode o apps-import para instalar tudo de volta.' -ForegroundColor DarkGray
}

#endregion


#region ==================== 3. IMPORT ====================

function Invoke-Import {
    Write-Host "`nBackup-Apps -Import" -ForegroundColor Green
    $found = @((Get-BackupFolders).Values | ForEach-Object {
        Get-ChildItem -Path $_ -Filter 'tidywin-apps-*.json' -File -ErrorAction SilentlyContinue
    } | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending)

    $labels = @($found | ForEach-Object { "$($_.Name)  ($(Split-Path $_.DirectoryName -Leaf))" }) + 'Outro arquivo (digitar o caminho)'
    if ($found) {
        $choice = Choose 'Qual lista instalar?' $labels 0
    } else {
        Write-Host '  Nenhuma lista encontrada na Área de Trabalho, Documentos, Downloads ou OneDrive.' -ForegroundColor DarkYellow
        $choice = $labels.Count - 1
    }
    if ($choice -eq $labels.Count - 1) {
        $file = "$(Read-Host '  Caminho do arquivo .json')".Trim().Trim('"')
        if (-not (Test-Path $file -PathType Leaf)) { Write-Host "  Arquivo não encontrado: $file" -ForegroundColor Red; return }
    } else {
        $file = $found[$choice].FullName
    }

    try { $ids = Get-PackageIds $file } catch { Write-Host '  Esse arquivo não é uma lista do WinGet.' -ForegroundColor Red; return }
    Write-Host "`n  $($ids.Count) apps na lista:"
    $ids | Sort-Object | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ''
    if (-not (Ask "Instalar os apps que ainda não estão neste PC?" $true)) { Write-Host 'Nada foi instalado.'; return }

    Write-Step 'Instalando com o WinGet (os que já estão instalados são pulados)'
    & winget import -i $file --ignore-unavailable --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Write-Host "`nPronto." -ForegroundColor Green }
    else { Write-Host "`nTerminou com avisos: veja acima os apps que não foram instalados." -ForegroundColor Yellow }
}

#endregion


#region ==================== 4. EXECUTION ====================

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'O WinGet não está instalado. Rode o apps (irm androksi.github.io/tidywin/apps | iex), que oferece instalar, e tente de novo.' -ForegroundColor Yellow
    return
}

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose 'O que fazer?' @('Salvar a lista de apps deste PC', 'Instalar apps de uma lista salva') 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
