#Requires -RunAsAdministrator
<#
    backup-apps.ps1 — saves the list of installed apps and reinstalls them after formatting

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\backup-apps.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\backup-apps.ps1 -Import     (after formatting)

    In the panel: Back up → Create and Back up → Restore, with the drivers and the Wi-Fi networks.
    Export: saves apps.json, every app WinGet knows (Microsoft Store apps included), in a
    tidywin-backup-<PC>-<date> folder, preferably on a USB drive or another disk.
    Import: finds that backup and installs the apps that are not on the PC yet.
    Only the apps are saved: not their settings, logins or files.


    FILE LAYOUT
        1. Helpers
        Backup folder ............... shared with backup-drivers.ps1 and backup-wifi.ps1
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
            Write-Host "  Enter a number from 1 to $($Options.Count)." -ForegroundColor DarkYellow
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

# The apps WinGet knows on this PC: id -> name, from "winget list" (its columns, whatever the language;
# names cut short end in "…"). Empty when WinGet can't list them.
function Get-InstalledApps {
    $apps = @{}
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $lines = @(& winget list --accept-source-agreements 2>$null | ForEach-Object { ("$_" -split "`r")[-1] })
    } catch { $lines = @() } finally { [Console]::OutputEncoding = $encoding }
    $dash = [array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^-{10,}' })
    if ($dash -lt 1 -or $dash -ge $lines.Count - 1) { return $apps }
    $words = [regex]::Matches($lines[$dash - 1], '\S+')
    if ($words.Count -lt 2) { return $apps }
    $idAt = $words[1].Index
    foreach ($line in $lines[($dash + 1)..($lines.Count - 1)]) {
        if ($line.Length -le $idAt) { continue }
        $id = ($line.Substring($idAt).Trim() -split '\s+')[0]
        $name = $line.Substring(0, $idAt).Trim()
        if ($id -and $name -and -not $apps.ContainsKey($id)) { $apps[$id] = $name }
    }
    return $apps
}

# A readable name from an id, when WinGet gave none: Microsoft.VisualStudioCode -> Visual Studio Code.
function Get-NameFromId([string]$Id) {
    $parts = $Id.Split('.')
    $name = if ($parts.Count -gt 1) { ($parts | Select-Object -Skip 1) -join ' ' } else { $Id }
    ($name -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim()
}

# The packages of a WinGet export file: Id, Source (winget, msstore) and the source they come from.
function Get-ExportPackages([string]$File) {
    $json = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
    @(foreach ($s in @($json.Sources)) { foreach ($p in @($s.Packages)) { [pscustomobject]@{ Id = "$($p.PackageIdentifier)"; Source = "$($s.SourceDetails.Name)" } } })
}

# A copy of an export file with only some of its apps (winget import installs everything in the file).
function Save-ExportSubset([string]$File, [string[]]$Ids, [string]$Out) {
    $json = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in @($json.Sources)) { $s.Packages = @(@($s.Packages) | Where-Object { $Ids -contains "$($_.PackageIdentifier)" }) }
    $json.Sources = @(@($json.Sources) | Where-Object { @($_.Packages).Count })
    [IO.File]::WriteAllText($Out, (ConvertTo-Json $json -Depth 10), (New-Object Text.UTF8Encoding $false))
}

function Get-AppRow([string]$Id, [string]$Name, [string]$Source, [string]$Status) {
    New-ListItem $Id $(if ($Name) { $Name } else { Get-NameFromId $Id }) "$Id$(if ($Source -eq 'msstore') { ' · Microsoft Store' })" '' $Status
}

function Invoke-Export {
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    Write-Loading 'Looking for drives to save to' 5
    $fields = @(Get-PlaceFields)
    $packages = @(); $names = @{}
    if ($hasWinget) {
        Write-Loading 'Listing the apps WinGet can save' 20
        # What winget export would save, to show it (apps WinGet doesn't know are left out)
        $list = Join-Path $env:TEMP "tidywin-apps-$PID.json"
        & winget export -o $list --accept-source-agreements *> $null
        if (Test-Path -LiteralPath $list) { $packages = @(Get-ExportPackages $list | Sort-Object Id -Unique); Remove-Item -LiteralPath $list -Force -ErrorAction SilentlyContinue }
        Write-Loading 'Reading the app names' 65
        $names = Get-InstalledApps
        $packages = @($packages | Sort-Object { if ($names[$_.Id]) { $names[$_.Id] } else { Get-NameFromId $_.Id } })
    }
    if ($packages) {
        $fields += New-SwitchField 'Create' 'Apps' 'Apps' 'The apps WinGet can install again, Microsoft Store apps included. Only the apps: not their settings, logins or files.' $true @{ badge = "$($packages.Count)" }
        $fields += New-ListField 'Create' 'AppList' 'Apps' @($packages | ForEach-Object { Get-AppRow $_.Id $names[$_.Id] $_.Source '' }) @(@{ field = 'Apps'; is = 'True' })
    } else {
        $fields += New-Field 'Create' 'Apps' 'info' 'Apps' $(if (-not $hasWinget) { 'WinGet is not installed. Open Set up → Apps first: it installs WinGet. Then come back here.' } else { 'WinGet found no app it can install again.' }) $null
    }
    if ($Describe) { Write-OptionsPage $Describe $fields; return }

    $v = Read-Options $fields $Answers
    $picked = @(if ($v.Apps) { @($v.AppList) | Where-Object { $_ } })
    if (-not $picked) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $root = Get-BackupRoot $v
    if (-not $root) { Write-Host '  The place to save was not found. Plug in the drive and try again.' -ForegroundColor Red; return }
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $all = Join-Path $env:TEMP "tidywin-apps-$PID.json"
    & winget export -o $all --accept-source-agreements *> $null
    if (-not (Test-Path -LiteralPath $all)) { Write-Host '  [ERROR] WinGet could not list the apps.' -ForegroundColor Red; return }
    $file = Join-Path $root 'apps.json'
    Save-ExportSubset $all $picked $file
    Remove-Item -LiteralPath $all -Force -ErrorAction SilentlyContinue
    # The names, for Restore's list (apps.json itself only has ids)
    $saved = @(Get-ExportPackages $file)
    $nameMap = [ordered]@{}
    foreach ($p in $saved) { $nameMap[$p.Id] = $(if ($names[$p.Id]) { $names[$p.Id] } else { Get-NameFromId $p.Id }) }
    [IO.File]::WriteAllText((Join-Path $root 'apps-names.json'), (ConvertTo-Json $nameMap), (New-Object Text.UTF8Encoding $false))
    foreach ($p in $saved) { Write-Done $nameMap[$p.Id] }
    $missing = @($picked | Where-Object { @($saved.Id) -notcontains $_ })
    if ($missing) { Write-Host "  Not saved (WinGet no longer lists them): $($missing -join ', ')" -ForegroundColor Yellow }
}

#endregion


#region ==================== 3. RESTORE ====================

# The apps saved in a backup, with their names; $null when it has no app list.
function Get-SavedApps([string]$Root) {
    $file = Join-Path $Root 'apps.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try { $packages = @(Get-ExportPackages $file) } catch { return $null }
    $names = try { Get-Content -LiteralPath (Join-Path $Root 'apps-names.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    @($packages | ForEach-Object {
        $name = if ($names -and $names.PSObject.Properties[$_.Id]) { "$($names.($_.Id))" } else { Get-NameFromId $_.Id }
        $_ | Add-Member -NotePropertyName Name -NotePropertyValue $name -PassThru
    } | Sort-Object Name)
}

function Invoke-Import {
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    Write-Loading 'Looking for backups on your drives' 5
    $found = @(Find-Backups)
    $fields = @(Get-RestoreFields)
    if ($hasWinget) {
        $fields += New-SwitchField 'Restore' 'Apps' 'Apps' 'Pick the ones to install, with WinGet. The ones marked Installed are already on this PC.' ($found.Count -gt 0)
        Write-Loading 'Checking which apps are already installed' 40
        $installed = if ($found) { Get-InstalledApps } else { @{} }
        for ($i = 0; $i -lt $found.Count; $i++) {
            $apps = @(Get-SavedApps $found[$i].FullName)
            if (-not $apps) { continue }
            $fields += New-ListField 'Restore' "AppList$i" 'Apps' @($apps | ForEach-Object { Get-AppRow $_.Id $_.Name $_.Source $(if ($installed.ContainsKey($_.Id)) { 'Installed' } else { '' }) }) (Get-ListWhen $found[$i].FullName 'Apps')
        }
    } else {
        $fields += New-Field 'Restore' 'Apps' 'info' 'Apps' 'WinGet is not installed. Open Set up → Apps first: it installs WinGet. Then come back here.' $null
    }
    if ($Describe) { Write-OptionsPage $Describe $fields; return }

    $v = Read-Options $fields $Answers
    if (-not $v.Apps -or -not $hasWinget) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }
    $root = Get-RestoreRoot $v
    $apps = @(Get-SavedApps $root)
    if (-not $apps) { Write-Skip 'This backup has no app list'; return }
    # A backup from the list: the apps checked there. Another folder: all of them (installed ones are skipped).
    $index = Get-BackupIndex $found $root
    $ids = if ($index -ge 0) { @($v["AppList$index"] | Where-Object { $_ }) } else { @($apps.Id) }
    if (-not $ids) { Write-Host '  Not selected.' -ForegroundColor DarkGray; return }

    $file = Join-Path $env:TEMP "tidywin-restore-apps-$PID.json"
    Save-ExportSubset (Join-Path $root 'apps.json') $ids $file
    Write-Host "  Installing $($ids.Count) app(s). Apps already installed are skipped." -ForegroundColor DarkGray
    & winget import -i $file --ignore-unavailable --accept-package-agreements --accept-source-agreements
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if ($code -eq 0) { Write-Done 'Apps installed' }
    else { Write-Host '  Finished with warnings: see above for the apps that were not installed.' -ForegroundColor Yellow }
}

#endregion


#region ==================== 4. EXECUTION ====================

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose 'What do you want to do?' @('Back up the list of apps on this PC', 'Install the apps from a backup') 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
