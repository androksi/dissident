#Requires -RunAsAdministrator
<#
    Backup-Drivers.ps1 — saves the PC's drivers before formatting and installs them back afterwards

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Backup-Drivers.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\Backup-Drivers.ps1 -Import     (after formatting)

    Export: lists the third-party drivers (the ones Windows didn't bring itself) by type, with the
    devices using each one. The ones in use come checked. Saves them with pnputil to a
    tidywin-drivers-<PC>-<date> folder, preferably on a USB drive or another disk, with a drivers.json
    describing them and a README.txt explaining how to install them by hand.
    Import: finds that folder (USB drives, other disks, Desktop, Documents, Downloads, OneDrive), shows
    the same list with what Windows already installed after formatting, and installs the checked ones.
    pnputil only accepts signed drivers; nothing else on the PC is changed.

    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

    FILE LAYOUT
        1. Helpers ................... prompts, grouped checklist, where to save / look
        2. Export
        3. Import
        4. Execution
#>
param(
    [switch]$Export,
    [switch]$Import,
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

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

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Full-screen checklist with group headers and scrolling (same keys as the apps list):
# ↑ ↓ PgUp PgDn move, Space checks, A checks/unchecks the whole group, Enter confirms, Esc cancels.
# $Items: objects with Group, Label, Note, Checked, Size. Returns the checked items (none on Esc).
function Select-Drivers([string]$Title, [object[]]$Items) {
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console: numbered list, numbers separated by commas
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
            Write-Host "    $($i + 1)) $mark $($Items[$i].Group) · $($Items[$i].Label)  $($Items[$i].Note)"
        }
        $answer = "$(Read-Host (T '  Numbers separated by commas (Enter keeps the checked ones)' '  Números separados por vírgula (Enter mantém os marcados)'))".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $lastGroup = $null
    foreach ($it in $Items) {
        if ($it.Group -ne $lastGroup) { $rows.Add([pscustomobject]@{ IsHeader = $true; Text = $it.Group }); $lastGroup = $it.Group }
        $rows.Add([pscustomobject]@{ IsHeader = $false; Item = $it })
    }
    $itemRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if (-not $rows[$r].IsHeader) { $r } })
    $labelWidth = [Math]::Min(48, ($Items | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum)
    $cursor = 0; $scroll = 0; $lastSize = ''

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            if ("$width x $height" -ne $lastSize) { Clear-Host; $lastSize = "$width x $height" }
            $viewport = [Math]::Max(5, $height - 6)   # 3 header + 2 footer lines, last line left empty (no scrolling)

            # Keep the cursor row (and its group header right above it) on screen
            $row = $itemRows[$cursor]
            $wanted = if ($row -gt 0 -and $rows[$row - 1].IsHeader) { $row - 1 } else { $row }
            if ($wanted -lt $scroll) { $scroll = $wanted }
            if ($row -ge $scroll + $viewport) { $scroll = $row - $viewport + 1 }

            $line = { param($text, $color) Write-Host ($text.PadRight($width - 1).Substring(0, $width - 1)) -ForegroundColor $color }
            [Console]::SetCursorPosition(0, 0)
            & $line "  $Title" 'Green'
            & $line (T '  ↑ ↓ move   Space check   A check the whole type   Enter continue   Esc quit' '  ↑ ↓ navegar   Espaço marcar   A marcar o tipo inteiro   Enter continuar   Esc sair') 'DarkGray'
            & $line '' 'Gray'

            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count) { & $line '' 'Gray'; continue }
                if ($rows[$r].IsHeader) { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $it = $rows[$r].Item
                $check  = if ($it.Checked) { '[x]' } else { '[ ]' }
                $marker = if ($r -eq $row) { '>' } else { ' ' }
                $label  = if ($it.Label.Length -gt $labelWidth) { $it.Label.Substring(0, $labelWidth - 1) + '…' } else { $it.Label.PadRight($labelWidth) }
                $color  = if ($r -eq $row) { 'Cyan' } elseif ($it.Checked) { 'Green' } else { 'Gray' }
                & $line "  $marker $check $label  $($it.Note)" $color
            }

            $checked = @($Items | Where-Object Checked)
            & $line '' 'Gray'
            & $line (T "  $($checked.Count) checked · $(Format-Size ($checked | Measure-Object Size -Sum).Sum)   ·   $($cursor + 1) of $($itemRows.Count)" "  $($checked.Count) marcado(s) · $(Format-Size ($checked | Measure-Object Size -Sum).Sum)   ·   $($cursor + 1) de $($itemRows.Count)") 'DarkGray'

            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - $viewport) }
                'PageDown'  { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + $viewport) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $itemRows.Count - 1 }
                'Spacebar'  { $it = $rows[$itemRows[$cursor]].Item; $it.Checked = -not $it.Checked }
                'A' {
                    # Whole group: checks everything in it; if all are already checked, unchecks them
                    $group = @($Items | Where-Object Group -eq $rows[$itemRows[$cursor]].Item.Group)
                    $checkAll = @($group | Where-Object { -not $_.Checked }).Count -gt 0
                    foreach ($it in $group) { $it.Checked = $checkAll }
                }
                'Enter'     { return @($Items | Where-Object Checked) }
                'Escape'    { return $null }
            }
        }
    } finally {
        Clear-Host
        [Console]::CursorVisible = $true
    }
}

# Places that survive formatting first (USB drives and other disks), then the user's folders.
# Returns an ordered table: label -> path (only places that exist).
function Get-BackupPlaces {
    $list = [ordered]@{}
    $system = $env:SystemDrive.TrimEnd('\')
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -ne $system -and $_.Size }) {
        $kind = if ($d.DriveType -eq 2) { T 'USB drive' 'pendrive' } else { T 'disk' 'disco' }
        $name = if ($d.VolumeName) { " $($d.VolumeName)" } else { '' }
        $list["$($d.DeviceID)\$name ($kind, $(Format-Size $d.FreeSpace) $(T 'free' 'livres'))"] = "$($d.DeviceID)\"
    }
    $folders = [ordered]@{
        (T 'Desktop' 'Área de Trabalho') = [Environment]::GetFolderPath('Desktop')
        (T 'Documents' 'Documentos')     = [Environment]::GetFolderPath('MyDocuments')
        'Downloads'                      = Join-Path $env:USERPROFILE 'Downloads'
        'OneDrive'                       = $env:OneDrive
    }
    foreach ($name in $folders.Keys) { if ($folders[$name] -and (Test-Path $folders[$name])) { $list[$name] = $folders[$name] } }
    return $list
}

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning (T 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).')
    return
}

#endregion


#region ==================== 2. EXPORT ====================

# Third-party driver packages in the driver store, with the devices using each one right now.
# Folder: the package's folder in the store (nv_dispi.inf_amd64_<hash>): the same on any PC, so it
# also tells, when importing, whether that exact package is already installed.
function Get-DriverList {
    $devices = @{}
    foreach ($d in (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object InfName -like 'oem*.inf')) {
        if (-not $devices.ContainsKey($d.InfName)) { $devices[$d.InfName] = New-Object Collections.Generic.List[string] }
        if ($d.DeviceName -and -not $devices[$d.InfName].Contains($d.DeviceName)) { $devices[$d.InfName].Add($d.DeviceName) }
    }
    foreach ($drv in (Get-WindowsDriver -Online -ErrorAction Stop)) {
        $store = Split-Path $drv.OriginalFileName -Parent
        [string[]]$names = @()      # typed: an "if" expression would turn a one-item list into a plain string
        if ($devices.ContainsKey($drv.Driver)) { $names = $devices[$drv.Driver].ToArray() }
        [pscustomobject]@{
            Published = $drv.Driver                          # oem12.inf: the name on this PC only
            Folder    = Split-Path $store -Leaf
            Inf       = Split-Path $drv.OriginalFileName -Leaf
            Class     = $(if ($drv.ClassDescription) { $drv.ClassDescription } else { $drv.ClassName })
            ClassName = $drv.ClassName                       # not translated: Display, Extension...
            Provider  = $drv.ProviderName
            Version   = "$($drv.Version)"
            Date      = $(if ($drv.Date) { $drv.Date.ToString('yyyy-MM-dd') } else { '' })
            Devices   = $names
            Size      = [int64](Get-ChildItem -LiteralPath $store -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        }
    }
}

# Checklist row of a driver: device name (or provider and .inf when no device uses it now).
function New-DriverItem($Driver, [bool]$Checked, [string]$Extra) {
    $devs  = @($Driver.Devices | Where-Object { $_ })
    $label = if ($devs.Count) { "$($devs[0])" + $(if ($devs.Count -gt 1) { " (+$($devs.Count - 1))" }) } else { "$($Driver.Provider) · $($Driver.Inf)" }
    $note  = "$($Driver.Provider) $($Driver.Version) · $(Format-Size $Driver.Size)$Extra"
    [pscustomobject]@{ Group = $Driver.Class; Label = $label; Note = $note; Checked = $Checked; Size = $Driver.Size; Driver = $Driver }
}

function Invoke-Export {
    Write-Host "`nBackup-Drivers -Export" -ForegroundColor Green
    Write-Host (T '  reading the drivers on this PC...' '  lendo os drivers deste PC...') -ForegroundColor DarkGray
    try { $drivers = @(Get-DriverList) } catch { Write-Host (T "  Could not list the drivers: $($_.Exception.Message)" "  Não foi possível listar os drivers: $($_.Exception.Message)") -ForegroundColor Red; return }
    if (-not $drivers) { Write-Host (T '  This PC has no third-party drivers: Windows brought all of them.' '  Este PC não tem drivers de terceiros: o Windows trouxe todos.'); return }

    # In use first; drivers no device uses now (old versions, unplugged devices) come unchecked.
    # Extension drivers add to another driver (audio effects, OEM settings) and are never listed as
    # in use by a device, so they come checked.
    $notInUse  = T ' · not in use now' ' · sem uso agora'
    $extension = T ' · add-on to another driver' ' · complemento de outro driver'
    $items = @($drivers | Sort-Object Class, @{ Expression = { $_.Devices.Count -eq 0 } }, @{ Expression = { "$(@($_.Devices)[0])" } } | ForEach-Object {
        $isExtension = $_.ClassName -eq 'Extension'
        New-DriverItem $_ ($_.Devices.Count -or $isExtension) $(if ($_.Devices.Count) { '' } elseif ($isExtension) { $extension } else { $notInUse })
    })
    $chosen = @(Select-Drivers (T 'Backup-Drivers — choose the drivers to save' 'Backup-Drivers — escolha os drivers para salvar') $items)
    if (-not $chosen) { Write-Host (T 'Nothing was saved.' 'Nada foi salvo.'); return }
    $total = ($chosen | Measure-Object Size -Sum).Sum
    Write-Host (T "`n  $($chosen.Count) driver(s), $(Format-Size $total)." "`n  $($chosen.Count) driver(s), $(Format-Size $total).")

    # Where: USB drives and other disks first (OneDrive is not a good place for gigabytes of drivers)
    $places = Get-BackupPlaces
    $names = @($places.Keys) + (T 'Another folder (type the path)' 'Outra pasta (digitar o caminho)')
    $choice = Choose (T 'Where to save? (pick a place that survives formatting: a USB drive or another disk)' 'Onde salvar? (escolha um lugar que não some ao formatar: um pendrive ou outro disco)') $names 0
    $dir = if ($choice -eq $names.Count - 1) { "$(Read-Host (T '  Folder' '  Pasta'))".Trim().Trim('"') } else { $places[$names[$choice]] }
    if (-not (Test-Path $dir -PathType Container)) { Write-Host (T "  Folder not found: $dir" "  Pasta não encontrada: $dir") -ForegroundColor Red; return }
    $free = try { (Get-PSDrive -Name (Split-Path $dir -Qualifier -ErrorAction Stop).TrimEnd(':') -ErrorAction Stop).Free } catch { $null }   # $null: network path
    if ($free -and $free -lt $total * 1.1) { Write-Host (T "  Not enough space there ($(Format-Size $free) free)." "  Não há espaço suficiente lá ($(Format-Size $free) livres).") -ForegroundColor Red; return }

    $root = Join-Path $dir ("tidywin-drivers-{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    Write-Step (T "Saving to $root" "Salvando em $root")
    $saved = @(); $failed = @()
    foreach ($c in $chosen) {
        $d = $c.Driver
        $target = New-Item -ItemType Directory -Path (Join-Path $root $d.Folder) -Force
        $out = & pnputil /export-driver $d.Published $target.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host "$($d.Class) · $($c.Label)"
            $saved += $d
        } else {
            Write-Host (T "  [ERROR] $($c.Label): $(($out | Select-Object -Last 1))" "  [ERRO] $($c.Label): $(($out | Select-Object -Last 1))") -ForegroundColor Red
            $failed += $c.Label
        }
    }

    # drivers.json (read by -Import) and a README.txt for whoever opens the folder
    $manifest = [ordered]@{
        Computer = $env:COMPUTERNAME
        Date     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Windows  = "$((Get-CimInstance Win32_OperatingSystem).Caption) ($([Environment]::OSVersion.Version))"
        Drivers  = @($saved | Select-Object Folder, Inf, Class, Provider, Version, Date, Devices, Size)
    }
    ConvertTo-Json -InputObject $manifest -Depth 4 | Set-Content (Join-Path $root 'drivers.json') -Encoding UTF8
    $readme = T @"
Drivers saved by TidyWin from $env:COMPUTERNAME on $(Get-Date -Format 'yyyy-MM-dd').

To install them back after formatting, in PowerShell:
    irm androksi.github.io/tidywin/drivers-import | iex

By hand: Device Manager > right-click the device > Update driver > Browse my computer >
pick this folder (with "Include subfolders" checked). Or right-click a .inf file > Install.
"@ @"
Drivers salvos pelo TidyWin de $env:COMPUTERNAME em $(Get-Date -Format 'yyyy-MM-dd').

Para instalar de volta depois de formatar, no PowerShell:
    irm androksi.github.io/tidywin/drivers-import | iex

À mão: Gerenciador de Dispositivos > botão direito no dispositivo > Atualizar driver > Procurar no
computador > escolha esta pasta (com "Incluir subpastas" marcado). Ou botão direito num .inf > Instalar.
"@
    Set-Content (Join-Path $root 'README.txt') $readme -Encoding UTF8

    $size = (Get-ChildItem -LiteralPath $root -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host (T "`nDone: $($saved.Count) driver(s), $(Format-Size $size), saved to" "`nPronto: $($saved.Count) driver(s), $(Format-Size $size), salvos em") -ForegroundColor Green
    Write-Host "  $root"
    if ($failed) { Write-Host (T "  Not saved: $($failed -join ', ')" "  Não salvos: $($failed -join ', ')") -ForegroundColor Yellow }
    Write-Host (T 'After formatting, run drivers-import to install them back.' 'Depois de formatar, rode o drivers-import para instalar de volta.') -ForegroundColor DarkGray
}

#endregion


#region ==================== 3. IMPORT ====================

# $A newer than $B ("31.0.15.5222" style). Versions that don't parse count as not newer.
function Test-NewerVersion([string]$A, [string]$B) {
    $va = $null; $vb = $null
    return [version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb) -and $va -gt $vb
}

function Invoke-Import {
    Write-Host "`nBackup-Drivers -Import" -ForegroundColor Green

    # Saved folders: in the root of USB drives and other disks, and in the user's folders; newest first
    $found = @((Get-BackupPlaces).Values | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Directory -Filter 'tidywin-drivers-*' -ErrorAction SilentlyContinue
    } | Where-Object { Test-Path (Join-Path $_.FullName 'drivers.json') } | Sort-Object FullName -Unique | Sort-Object Name -Descending)

    $labels = @($found | ForEach-Object { $_.FullName }) + (T 'Another folder (type the path)' 'Outra pasta (digitar o caminho)')
    if ($found) {
        $choice = Choose (T 'Which saved drivers to install?' 'Quais drivers salvos instalar?') $labels 0
    } else {
        Write-Host (T '  No tidywin-drivers folder found on USB drives, other disks, Desktop, Documents, Downloads or OneDrive.' '  Nenhuma pasta tidywin-drivers encontrada em pendrives, outros discos, Área de Trabalho, Documentos, Downloads ou OneDrive.') -ForegroundColor DarkYellow
        $choice = $labels.Count - 1
    }
    $root = if ($choice -eq $labels.Count - 1) { "$(Read-Host (T '  Folder' '  Pasta'))".Trim().Trim('"') } else { $found[$choice].FullName }
    $manifestFile = Join-Path $root 'drivers.json'
    if (-not (Test-Path -LiteralPath $manifestFile)) { Write-Host (T "  This is not a folder saved by drivers-export: $root" "  Essa não é uma pasta salva pelo drivers-export: $root") -ForegroundColor Red; return }
    try { $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Host (T '  Could not read drivers.json.' '  Não foi possível ler o drivers.json.') -ForegroundColor Red; return }
    Write-Host (T "  Saved from $($manifest.Computer) on $($manifest.Date) · $($manifest.Windows)" "  Salvos de $($manifest.Computer) em $($manifest.Date) · $($manifest.Windows)") -ForegroundColor DarkGray

    # What Windows already has: the same package (same store folder), or a newer version of it
    Write-Host (T '  checking what Windows already installed...' '  conferindo o que o Windows já instalou...') -ForegroundColor DarkGray
    $installed = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ Folder = Split-Path (Split-Path $_.OriginalFileName -Parent) -Leaf; Inf = Split-Path $_.OriginalFileName -Leaf; Provider = $_.ProviderName; Version = "$($_.Version)" }
    })
    $items = @(@($manifest.Drivers) | Where-Object { Test-Path -LiteralPath (Join-Path $root $_.Folder) } | Sort-Object Class | ForEach-Object {
        $d = $_
        $same  = @($installed | Where-Object Folder -eq $d.Folder)
        $newer = @($installed | Where-Object { $_.Inf -eq $d.Inf -and $_.Provider -eq $d.Provider -and (Test-NewerVersion $_.Version $d.Version) })
        $extra = if ($same) { T ' · already installed' ' · já instalado' } elseif ($newer) { T " · newer installed ($($newer[0].Version))" " · mais novo instalado ($($newer[0].Version))" } else { '' }
        New-DriverItem $d (-not $same -and -not $newer) $extra
    })
    if (-not $items) { Write-Host (T '  The folder has no drivers.' '  A pasta não tem drivers.'); return }

    $chosen = @(Select-Drivers (T 'Backup-Drivers — choose the drivers to install' 'Backup-Drivers — escolha os drivers para instalar') $items)
    if (-not $chosen) { Write-Host (T 'Nothing was installed.' 'Nada foi instalado.'); return }

    Write-Step (T "Installing $($chosen.Count) driver(s)" "Instalando $($chosen.Count) driver(s)")
    $restart = $false; $failed = @()
    foreach ($c in $chosen) {
        $out = & pnputil /add-driver (Join-Path (Join-Path $root $c.Driver.Folder) '*.inf') /subdirs /install 2>&1
        switch ($LASTEXITCODE) {
            0       { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host "$($c.Group) · $($c.Label)" }
            3010    { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host "$($c.Group) · $($c.Label) $(T '(after restarting)' '(depois de reiniciar)')"; $restart = $true }
            259     { Write-Host '  [--] ' -ForegroundColor DarkGray -NoNewline; Write-Host (T "$($c.Label): added; no device on this PC needs it now" "$($c.Label): adicionado; nenhum dispositivo deste PC precisa dele agora") -ForegroundColor DarkGray }
            default { Write-Host (T "  [ERROR] $($c.Label): $(($out | Select-Object -Last 1))" "  [ERRO] $($c.Label): $(($out | Select-Object -Last 1))") -ForegroundColor Red; $failed += $c.Label }
        }
    }

    if ($failed) { Write-Host (T "`nNot installed: $($failed -join ', ')" "`nNão instalados: $($failed -join ', ')") -ForegroundColor Yellow }
    Write-Host (T "`nDone." "`nPronto.") -ForegroundColor Green
    if ($restart -and (Ask (T 'Some drivers need a restart. Restart now?' 'Alguns drivers precisam reiniciar o PC. Reiniciar agora?') $false)) { Restart-Computer -Force }
}

#endregion


#region ==================== 4. EXECUTION ====================

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose (T 'What do you want to do?' 'O que fazer?') @((T 'Save the drivers of this PC' 'Salvar os drivers deste PC'), (T 'Install drivers from a saved folder' 'Instalar drivers de uma pasta salva')) 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
