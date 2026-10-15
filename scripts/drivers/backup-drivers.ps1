#Requires -RunAsAdministrator
<#
    backup-drivers.ps1 — saves the PC's drivers before formatting and installs them back afterwards

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\backup-drivers.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\backup-drivers.ps1 -Import     (after formatting)

    In the panel: Back up → Create and Back up → Restore, with the apps and the Wi-Fi networks.
    Export: saves the third-party drivers some device uses now (the ones Windows didn't bring itself),
    and their add-ons, with pnputil to the drivers folder of a tidywin-backup-<PC>-<date> folder,
    preferably on a USB drive or another disk, with a drivers.json and a README.txt for installing by hand.
    Import: finds that backup (USB drives, other disks, Desktop, Documents, Downloads, OneDrive) and
    installs the drivers Windows doesn't have yet. pnputil only accepts signed drivers.


    FILE LAYOUT
        1. Helpers
        Backup folder ............... shared with backup-apps.ps1 and backup-wifi.ps1
        2. Back up
        3. Restore
        4. Execution
#>
param(
    [switch]$Export,
    [switch]$Import,
    [string]$Describe,      # the panel: writes the options of the page (with -Export or -Import) and stops
    [string]$Answers        # the panel: what was chosen there (nothing is asked)
)
$ErrorActionPreference = 'Continue'


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
        if (@($f.when | Where-Object { $_ -and "$($values[$_.field])" -ne "$($_.is)" }).Count) { continue }     # "when": one condition or a list
        switch ($f.kind) {
            'header'    { Write-Host "`n  $($f.label)" -ForegroundColor Cyan }
            'toggle'    { $values[$f.id] = Ask "$($f.label)?" $false }
            'info'      { Write-Host "  $($f.label): $($f.desc)" -ForegroundColor DarkGray }
            { $_ -in 'text', 'path' } { $values[$f.id] = "$(Read-Host "  $($f.label)")".Trim().Trim('"') }
            'checklist' { $values[$f.id] = @($f.items | Where-Object { Ask "$($f.label): $($_.label)?" $false } | ForEach-Object { $_.value }) }
            default {
                # choice and select; "Skip" leaves it as it is (a select that comes with a value has no Skip)
                $options = @(if (-not "$($f.default)") { Opt '' 'Skip' }) + @($f.options)
                $start = [Math]::Max(0, [array]::IndexOf(@($options | ForEach-Object { "$($_.value)" }), "$($f.default)"))
                $values[$f.id] = $options[(Choose "$($f.label):" @($options | ForEach-Object { $_.label }) $start)].value
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
function Write-Done([string]$Text) { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
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

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== BACKUP FOLDER ====================

# The same in the three backup scripts (drivers, apps, Wi-Fi): each saves its part in one
# tidywin-backup-<PC>-<date> folder, and Restore finds that folder again. The panel's pages run them
# together and show the shared fields (where to save, which backup) once.

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Places that survive formatting first (USB drives and other disks), then the user's folders.
# Label -> path, only the places that exist.
function Get-SavePlaces {
    $list = [ordered]@{}
    $system = $env:SystemDrive.TrimEnd('\')
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -ne $system -and $_.Size }) {
        $kind = if ($d.DriveType -eq 2) { 'USB drive' } else { 'disk' }
        $name = if ($d.VolumeName) { " $($d.VolumeName)" } else { '' }
        $list["$($d.DeviceID)\$name ($kind, $(Format-Size $d.FreeSpace) free)"] = "$($d.DeviceID)\"
    }
    $folders = [ordered]@{
        'Desktop'   = [Environment]::GetFolderPath('Desktop')
        'Documents' = [Environment]::GetFolderPath('MyDocuments')
        'Downloads' = Join-Path $env:USERPROFILE 'Downloads'
        'OneDrive'  = $env:OneDrive
    }
    foreach ($name in $folders.Keys) { if ($folders[$name] -and (Test-Path $folders[$name])) { $list[$name] = $folders[$name] } }
    return $list
}

# Back up: where to save, the first place (a USB drive or another disk, if there is one) already chosen.
# "setting": shown in Review, but not counted as something to do.
function Get-PlaceFields {
    $places = Get-SavePlaces
    @(
        New-Field 'Create' 'Place' 'select' 'Save to' 'A USB drive or another disk survives formatting. Everything goes in one tidywin-backup folder there.' "$(@($places.Values)[0])" @{
            options = @(@($places.Keys | ForEach-Object { Opt $places[$_] $_ }) + (Opt 'other' 'Another folder')); setting = $true }
        New-Field 'Create' 'Folder' 'path' 'Folder' 'Where to save.' '' @{ when = @{ field = 'Place'; is = 'other' }; required = $true; setting = $true }
    )
}

# Back up: today's backup folder in the place chosen ($null when that place doesn't exist).
function Get-BackupRoot($Values) {
    $dir = if ($Values.Place -eq 'other') { "$($Values.Folder)".Trim().Trim('"') } else { "$($Values.Place)" }
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $null }
    Join-Path $dir ("tidywin-backup-{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))
}

# Restore: the backups in the root of USB drives and other disks and in the user's folders, newest first.
function Find-Backups {
    @((Get-SavePlaces).Values | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Directory -Filter 'tidywin-backup-*' -ErrorAction SilentlyContinue
    } | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending)
}

# What a backup has, for its name in the list: "drivers, apps, Wi-Fi".
function Get-BackupContents([string]$Root) {
    $parts = @()
    if (Test-Path -LiteralPath (Join-Path $Root 'drivers\drivers.json')) { $parts += 'drivers' }
    if (Test-Path -LiteralPath (Join-Path $Root 'apps.json')) { $parts += 'apps' }
    if (@(Get-ChildItem -LiteralPath (Join-Path $Root 'wifi') -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count) { $parts += 'Wi-Fi' }
    if ($parts) { $parts -join ', ' } else { 'empty' }
}

# Restore: which backup, the newest one already chosen.
function Get-RestoreFields {
    $found = @(Find-Backups)
    @(
        New-Field 'Restore' 'Backup' 'select' 'Backup' 'Found on USB drives, other disks, Desktop, Documents, Downloads and OneDrive.' "$(if ($found) { $found[0].FullName })" @{
            options = @(@($found | ForEach-Object { Opt $_.FullName "$($_.FullName)  ·  $(Get-BackupContents $_.FullName)" }) + (Opt 'other' 'Another folder')); setting = $true }
        New-Field 'Restore' 'BackupOther' 'path' 'Folder' 'A tidywin-backup folder.' '' @{ when = @{ field = 'Backup'; is = 'other' }; required = $true; setting = $true }
    )
}

function Get-RestoreRoot($Values) {
    if ($Values.Backup -eq 'other') { "$($Values.BackupOther)".Trim().Trim('"') } else { "$($Values.Backup)" }
}

# A switch and, under it while it is on, the list to pick from, nothing checked ("Select all" on each
# group). Like the Browsers page: the switch only opens the list, the checked items are what counts
# ($Quiet), and Review lists them under the switch's name.
function New-SwitchField([string]$Tab, [string]$Id, [string]$Label, [string]$Desc, [bool]$Quiet, [hashtable]$More) {
    $m = @{ quiet = $Quiet }
    if ($More) { foreach ($k in $More.Keys) { $m[$k] = $More[$k] } }
    New-Field $Tab $Id 'toggle' $Label $Desc $false $m
}
function New-ListField([string]$Tab, [string]$Id, [string]$Group, [object[]]$Items, [object[]]$When) {
    New-Field $Tab $Id 'checklist' '' '' @() @{ items = @($Items); group = $Group; indent = $true; when = @($When) }
}
function New-ListItem([string]$Value, [string]$Label, [string]$Note, [string]$Group, [string]$Status) {
    [ordered]@{ value = $Value; label = $Label; note = $Note; group = $Group; status = $Status }
}

# Restore: the list of each backup found shows only while that backup is chosen and the switch is on.
function Get-ListWhen([string]$Backup, [string]$Switch) { @(@{ field = 'Backup'; is = $Backup }, @{ field = $Switch; is = 'True' }) }

# Restore: the index of the chosen backup among the ones found (-1: another folder, which has no list)
function Get-BackupIndex([object[]]$Found, [string]$Root) { [array]::IndexOf(@($Found | ForEach-Object { $_.FullName }), $Root) }

#endregion


#region ==================== 2. BACK UP ====================

# Third-party driver packages in the driver store, with the devices using each one right now.
# Folder: the package's folder in the store (nv_dispi.inf_amd64_<hash>): the same on any PC, so it
# also tells, when restoring, whether that exact package is already installed.
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

# Name of a driver: device name (or provider and .inf when no device uses it now).
function Get-DriverLabel($Driver) {
    $devs = @($Driver.Devices | Where-Object { $_ })
    if ($devs.Count) { "$($devs[0])" + $(if ($devs.Count -gt 1) { " (+$($devs.Count - 1))" }) } else { "$($Driver.Provider) · $($Driver.Inf)" }
}

# Row of the list: the name, then provider, version and size; the type is the group.
function Get-DriverRow($Driver, [string]$Value, [string]$Status) {
    $extra = if ($Driver.Devices.Count) { '' } elseif ($Driver.ClassName -eq 'Extension') { ' · add-on to another driver' } else { ' · not in use now' }
    New-ListItem $Value (Get-DriverLabel $Driver) "$($Driver.Provider) $($Driver.Version) · $(Format-Size $Driver.Size)$extra" $Driver.Class $Status
}

function Invoke-Export {
    Write-Loading 'Reading the drivers on this PC' 5
    # In use first in each type; old versions and drivers of unplugged devices last
    try { $drivers = @(Get-DriverList | Sort-Object Class, @{ Expression = { $_.Devices.Count -eq 0 -and $_.ClassName -ne 'Extension' } }, @{ Expression = { Get-DriverLabel $_ } }) }
    catch { $drivers = @(); $listError = $_.Exception.Message }
    Write-Loading 'Looking for drives to save to' 85
    $fields = @(Get-PlaceFields)
    if ($drivers) {
        $fields += New-SwitchField 'Create' 'Drivers' 'Drivers' 'The ones Windows doesn''t bring by itself: video, network, audio and others. Pick the ones to save.' $true @{ badge = "$($drivers.Count)" }
        $fields += New-ListField 'Create' 'DriverList' 'Drivers' @($drivers | ForEach-Object { Get-DriverRow $_ $_.Published '' }) @(@{ field = 'Drivers'; is = 'True' })
    } else {
        $fields += New-Field 'Create' 'Drivers' 'info' 'Drivers' $(if ($listError) { "Could not list them: $listError" } else { 'Nothing to save: Windows brought all of them.' }) $null
    }
    if ($Describe) { Write-OptionsPage $Describe $fields; return }

    $v = Read-Options $fields $Answers
    $picked = @($v.DriverList)
    $chosen = @(if ($v.Drivers) { $drivers | Where-Object { $picked -contains $_.Published } })
    if (-not $chosen) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $total = [int64]($chosen | Measure-Object Size -Sum).Sum
    $root = Get-BackupRoot $v
    if (-not $root) { Write-Host '  The place to save was not found. Plug in the drive and try again.' -ForegroundColor Red; return }
    $free = try { (Get-PSDrive -Name (Split-Path $root -Qualifier -ErrorAction Stop).TrimEnd(':') -ErrorAction Stop).Free } catch { $null }   # $null: network path
    if ($free -and $free -lt $total * 1.1) { Write-Host "  Not enough space there: $(Format-Size $free) free, $(Format-Size $total) needed." -ForegroundColor Red; return }

    $dir = Join-Path $root 'drivers'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "  Saving to $dir" -ForegroundColor DarkGray
    $saved = @(); $failed = @()
    foreach ($d in $chosen) {
        $target = New-Item -ItemType Directory -Path (Join-Path $dir $d.Folder) -Force
        $out = & pnputil /export-driver $d.Published $target.FullName 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Done "$($d.Class) · $(Get-DriverLabel $d)"; $saved += $d }
        else { Write-Host "  [ERROR] $(Get-DriverLabel $d): $(($out | Select-Object -Last 1))" -ForegroundColor Red; $failed += $d }
    }

    # drivers.json (read by Restore) and a README.txt for whoever opens the folder
    $manifest = [ordered]@{
        Computer = $env:COMPUTERNAME
        Date     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Windows  = "$((Get-CimInstance Win32_OperatingSystem).Caption) ($([Environment]::OSVersion.Version))"
        Drivers  = @($saved | Select-Object Folder, Inf, Class, ClassName, Provider, Version, Date, Devices, Size)
    }
    ConvertTo-Json -InputObject $manifest -Depth 4 | Set-Content (Join-Path $dir 'drivers.json') -Encoding UTF8
    $readme = @"
Drivers saved by TidyWin from $env:COMPUTERNAME on $(Get-Date -Format 'yyyy-MM-dd').

To install them back after formatting, in PowerShell:
    irm androksi.github.io/tidywin/run | iex
and in the menu choose Back up > Restore.

By hand: Device Manager > right-click the device > Update driver > Browse my computer >
pick this folder (with "Include subfolders" checked). Or right-click a .inf file > Install.
"@
    Set-Content (Join-Path $dir 'README.txt') $readme -Encoding UTF8
    $size = (Get-ChildItem -LiteralPath $dir -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host "  $($saved.Count) driver(s) saved, $(Format-Size $size)." -ForegroundColor DarkGray
    if ($failed) { Write-Host "  Not saved: $(@($failed | ForEach-Object { Get-DriverLabel $_ }) -join ', ')" -ForegroundColor Yellow }
}

#endregion


#region ==================== 3. RESTORE ====================

# $A newer than $B ("31.0.15.5222" style). Versions that don't parse count as not newer.
function Test-NewerVersion([string]$A, [string]$B) {
    $va = $null; $vb = $null
    return [version]::TryParse($A, [ref]$va) -and [version]::TryParse($B, [ref]$vb) -and $va -gt $vb
}

# The drivers saved in a backup, each with Installed: Windows has the same package (same store folder) or
# a newer version of it. $null when the backup has no drivers.
function Get-SavedDrivers([string]$Root) {
    $file = Join-Path $Root 'drivers\drivers.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { $manifest = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if (-not $script:InstalledDrivers) {
        $script:InstalledDrivers = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ Folder = Split-Path (Split-Path $_.OriginalFileName -Parent) -Leaf; Inf = Split-Path $_.OriginalFileName -Leaf; Provider = $_.ProviderName; Version = "$($_.Version)" }
        })
    }
    $drivers = @(@($manifest.Drivers) | Where-Object { Test-Path -LiteralPath (Join-Path $Root "drivers\$($_.Folder)") } | Sort-Object Class | ForEach-Object {
        $d = $_
        $installed = @($script:InstalledDrivers | Where-Object { $_.Folder -eq $d.Folder -or ($_.Inf -eq $d.Inf -and $_.Provider -eq $d.Provider -and (Test-NewerVersion $_.Version $d.Version)) }).Count -gt 0
        $d | Add-Member -NotePropertyName Installed -NotePropertyValue $installed -PassThru
    })
    return @{ Manifest = $manifest; Drivers = $drivers }
}

function Invoke-Import {
    # Restore runs drivers first, then Wi-Fi (its adapter may need a driver), then apps (they need the internet)
    Write-Loading 'Looking for backups on your drives' 5
    $found = @(Find-Backups)
    $fields = @(Get-RestoreFields) + @(
        New-SwitchField 'Restore' 'Drivers' 'Drivers' 'Pick the ones to install. The ones marked Installed are already on this PC. Some only work after restarting.' ($found.Count -gt 0)
    )
    Write-Loading 'Reading the saved drivers' 30
    for ($i = 0; $i -lt $found.Count; $i++) {
        $saved = Get-SavedDrivers $found[$i].FullName
        if (-not $saved -or -not $saved.Drivers) { continue }
        $fields += New-ListField 'Restore' "DriverList$i" 'Drivers' @($saved.Drivers | ForEach-Object { Get-DriverRow $_ $_.Folder $(if ($_.Installed) { 'Installed' } else { '' }) }) (Get-ListWhen $found[$i].FullName 'Drivers')
    }
    $notes = @('Runs in this order: drivers, then Wi-Fi networks, then apps, which need the internet.')
    if (-not $found) { $notes += 'No backup found on USB drives, other disks, Desktop, Documents, Downloads or OneDrive. Plug in the drive, or choose the folder.' }
    if ($Describe) { Write-OptionsPage $Describe $fields $notes; return }

    $v = Read-Options $fields $Answers
    if (-not $v.Drivers) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $root = Get-RestoreRoot $v
    $saved = Get-SavedDrivers $root
    if (-not $saved) { Write-Skip 'This backup has no drivers'; return }
    Write-Host "  Saved from $($saved.Manifest.Computer) on $($saved.Manifest.Date) · $($saved.Manifest.Windows)" -ForegroundColor DarkGray
    # A backup from the list: the drivers checked there. Another folder: the ones Windows doesn't have.
    $index = Get-BackupIndex $found $root
    $chosen = if ($index -ge 0) { $picked = @($v["DriverList$index"]); @($saved.Drivers | Where-Object { $picked -contains $_.Folder }) }
              else { @($saved.Drivers | Where-Object { -not $_.Installed }) }
    if (-not $chosen) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }

    $dir = Join-Path $root 'drivers'
    $restart = $false; $failed = @()
    foreach ($d in $chosen) {
        $label = "$($d.Class) · $(Get-DriverLabel $d)"
        $out = & pnputil /add-driver (Join-Path (Join-Path $dir $d.Folder) '*.inf') /subdirs /install 2>&1
        switch ($LASTEXITCODE) {
            0       { Write-Done $label }
            3010    { Write-Done "$label · after restarting"; $restart = $true }
            259     { Write-Skip "${label}: added; no device on this PC needs it now" }
            default { Write-Host "  [ERROR] ${label}: $(($out | Select-Object -Last 1))" -ForegroundColor Red; $failed += $label }
        }
    }
    if ($failed) { Write-Host "  Not installed: $($failed -join ', ')" -ForegroundColor Yellow }
    if ($restart) { Write-Host '  Restart the PC when everything is done: some drivers only start working after it.' -ForegroundColor Yellow }
}

#endregion


#region ==================== 4. EXECUTION ====================

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose 'What do you want to do?' @('Back up the drivers of this PC', 'Restore drivers from a backup') 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
