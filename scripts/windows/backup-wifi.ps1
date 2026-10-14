#Requires -RunAsAdministrator
<#
    backup-wifi.ps1 — saves the Wi-Fi networks and their passwords, and adds them back after formatting

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\backup-wifi.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\backup-wifi.ps1 -Import     (after formatting)

    In the panel: Back up → Create and Back up → Restore, with the drivers and the apps.
    Export: netsh saves each network to the wifi folder of a tidywin-backup-<PC>-<date> folder, with the
    password readable (an encrypted one only works on the Windows install that saved it).
    Import: finds that backup and adds the networks for every user. Needs the Wi-Fi adapter's driver.


    FILE LAYOUT
        1. Helpers
        Backup folder ............... shared with backup-drivers.ps1 and backup-apps.ps1
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

function Write-Done([string]$Text) { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Skip([string]$Text) { Write-Host "  [--] $Text" -ForegroundColor DarkGray }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    if ($script:Panel) { return [int](Request-Panel @{ type = 'choose'; question = $Question; options = @($Options); default = $Default }) }
    Write-Host "  $Question"
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
    while ($true) {
        $answer = "$(Read-Host "  Number [$($Default + 1)]")".Trim()
        if ($answer -eq '') { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n - 1 }
        Write-Host "  Type a number from 1 to $($Options.Count)." -ForegroundColor DarkYellow
    }
}

# Name of the network in a profile file ($null when the file is not a Wi-Fi profile).
function Get-ProfileName([string]$File) {
    try { "$(([xml](Get-Content -LiteralPath $File -Raw -Encoding UTF8)).WLANProfile.name)" } catch { $null }
}

# The Wi-Fi networks saved on this PC, read from Windows' own profile files (the same in every language).
function Get-WifiNetworks {
    @(Get-ChildItem "$env:ProgramData\Microsoft\Wlansvc\Profiles\Interfaces\*\*.xml" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ProfileName $_.FullName } | Where-Object { $_ } | Sort-Object -Unique)
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

function Invoke-Export {
    $networks = @(Get-WifiNetworks)
    $fields = @(Get-PlaceFields)
    if ($networks) {
        $fields += New-SwitchField 'Create' 'WiFi' 'Wi-Fi networks' 'The saved networks and their passwords. Pick the ones to save.' $true @{
            badge = "$($networks.Count)"; warn = 'The passwords are saved readable in the backup folder: keep it safe, and delete it when you no longer need it.' }
        $fields += New-ListField 'Create' 'WifiList' 'Wi-Fi networks' @($networks | ForEach-Object { New-ListItem $_ $_ '' '' '' }) @(@{ field = 'WiFi'; is = 'True' })
    } else {
        $fields += New-Field 'Create' 'WiFi' 'info' 'Wi-Fi networks' 'No Wi-Fi network is saved on this PC.' $null
    }
    if ($Describe) { Write-OptionsPage $Describe $fields; return }

    $v = Read-Options $fields $Answers
    $picked = @(if ($v.WiFi) { @($v.WifiList) | Where-Object { $networks -contains $_ } })
    if (-not $picked) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $root = Get-BackupRoot $v
    if (-not $root) { Write-Host '  The place to save was not found. Plug in the drive and try again.' -ForegroundColor Red; return }
    $dir = Join-Path $root 'wifi'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # key=clear: the password goes in the file as text; encrypted, it only works on this Windows install
    foreach ($name in $picked) {
        $before = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count
        $out = & netsh wlan export profile name="$name" key=clear folder="$dir" 2>&1
        if (@(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count -gt $before) { Write-Done $name }
        else { Write-Host "  [ERROR] ${name}: $(($out | Where-Object { "$_".Trim() } | Select-Object -Last 1))" -ForegroundColor Red }
    }
}

#endregion


#region ==================== 3. RESTORE ====================

# The networks saved in a backup: Name and File.
function Get-SavedNetworks([string]$Root) {
    @(Get-ChildItem -LiteralPath (Join-Path $Root 'wifi') -Filter '*.xml' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $name = Get-ProfileName $_.FullName
        if ($name) { [pscustomobject]@{ Name = $name; File = $_.FullName } }
    } | Sort-Object Name)
}

function Invoke-Import {
    $found = @(Find-Backups)
    $here = @(Get-WifiNetworks)
    $fields = @(Get-RestoreFields) + @(
        New-SwitchField 'Restore' 'WiFi' 'Wi-Fi networks' 'Pick the ones to add, with their passwords, so the PC connects by itself. The ones marked Saved are already on this PC.' ($found.Count -gt 0)
    )
    for ($i = 0; $i -lt $found.Count; $i++) {
        $saved = @(Get-SavedNetworks $found[$i].FullName)
        if (-not $saved) { continue }
        $fields += New-ListField 'Restore' "WifiList$i" 'Wi-Fi networks' @($saved | ForEach-Object { New-ListItem $_.Name $_.Name '' '' $(if ($here -contains $_.Name) { 'Saved' } else { '' }) }) (Get-ListWhen $found[$i].FullName 'WiFi')
    }
    if ($Describe) { Write-OptionsPage $Describe $fields; return }

    $v = Read-Options $fields $Answers
    if (-not $v.WiFi) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $root = Get-RestoreRoot $v
    $saved = @(Get-SavedNetworks $root)
    if (-not $saved) { Write-Skip 'This backup has no Wi-Fi networks'; return }
    # A backup from the list: the networks checked there. Another folder: all of them.
    $index = Get-BackupIndex $found $root
    $chosen = if ($index -ge 0) { $picked = @($v["WifiList$index"]); @($saved | Where-Object { $picked -contains $_.Name }) } else { $saved }
    if (-not $chosen) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $service = Get-Service WlanSvc -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        Write-Host '  [ERROR] Wi-Fi is not available on this PC: it has no Wi-Fi adapter, or its driver is not installed yet.' -ForegroundColor Red
        return
    }
    foreach ($n in $chosen) {
        $out = & netsh wlan add profile filename="$($n.File)" user=all 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Done $n.Name }
        else { Write-Host "  [ERROR] $($n.Name): $(($out | Where-Object { "$_".Trim() } | Select-Object -Last 1))" -ForegroundColor Red }
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose 'What do you want to do?' @('Back up the Wi-Fi networks of this PC', 'Restore Wi-Fi networks from a backup') 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
