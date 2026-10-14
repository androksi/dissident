#Requires -RunAsAdministrator
<#
    backup-apps.ps1 — saves the list of installed apps and reinstalls them on another PC (or after formatting)

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\backup-apps.ps1 -Export     (before formatting)
        powershell -ExecutionPolicy Bypass -File .\backup-apps.ps1 -Import     (after formatting)

    Export: saves a tidywin-apps-<PC>-<date>.json file with every app WinGet knows (Microsoft Store
    apps included). Save it somewhere that survives the format: OneDrive, Google Drive, a USB drive.
    Import: finds that file (USB drives, other disks, Desktop, Documents, Downloads, OneDrive), shows the apps and installs them.
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

# Yes/no question shown as a "Yes / No" menu (same as Choose). The default comes selected.
function Ask([string]$Question, [bool]$Default) {
    return (Choose $Question @('Yes', 'No') $(if ($Default) { 0 } else { 1 })) -eq 0
}


# Folders where the file is saved and searched, in this order (only the ones that exist).
function Get-BackupFolders {
    $list = [ordered]@{
        'Desktop' = [Environment]::GetFolderPath('Desktop')
        'Documents'     = [Environment]::GetFolderPath('MyDocuments')
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

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    return '{0:N0} MB' -f ($Bytes / 1MB)
}

# Places that survive formatting first (USB drives and other disks), then the user's folders: the same
# list Backup-Drivers offers. Label -> path, only places that exist.
function Get-SavePlaces {
    $list = [ordered]@{}
    $system = $env:SystemDrive.TrimEnd('\')
    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -ne $system -and $_.Size }) {
        $kind = if ($d.DriveType -eq 2) { 'USB drive' } else { 'disk' }
        $name = if ($d.VolumeName) { " $($d.VolumeName)" } else { '' }
        $list["$($d.DeviceID)\$name ($kind, $(Format-Size $d.FreeSpace) free)"] = "$($d.DeviceID)\"
    }
    $folders = Get-BackupFolders
    foreach ($name in $folders.Keys) { $list[$name] = $folders[$name] }
    return $list
}

# For the panel's page: where to save. Backup-Drivers has the same two fields; the page shows them once.
function Get-PlaceFields {
    $places = Get-SavePlaces
    @(
        New-Field 'Backup' 'Place' 'select' 'Save to' 'Somewhere that survives formatting: a USB drive or another disk is best.' '' @{ options = @(@($places.Keys | ForEach-Object { Opt $places[$_] $_ }) + (Opt 'other' 'Another folder')) }
        New-Field 'Backup' 'Folder' 'path' 'Folder' 'Where to save.' '' @{ when = @{ field = 'Place'; is = 'other' }; required = $true }
    )
}

function Invoke-Export {
    if ($Describe) {
        $apps = New-Field 'Backup' 'Apps' 'toggle' 'Save the list of apps' 'Every app WinGet knows, Microsoft Store apps included. Only the apps: not their settings, logins or files.' $false
        Write-OptionsPage $Describe (@(Get-PlaceFields) + @($apps))
        return
    }
    Write-Host "`nBackup-Apps -Export" -ForegroundColor Green
    if ($Answers) {
        $answer = [IO.File]::ReadAllText($Answers) | ConvertFrom-Json
        if (-not $answer.Apps) { Write-Host 'The app list was not selected, so it was not saved.'; return }
        $dir = if ($answer.Place -eq 'other') { "$($answer.Folder)".Trim() } else { "$($answer.Place)" }
        if (-not $dir) { Write-Host '  Choose where to save.' -ForegroundColor Red; return }
    } else {
        $folders = Get-SavePlaces
        $names = @($folders.Keys) + 'Another folder (type the path)'
        $choice = Choose 'Where to save the app list? (pick a place that survives formatting)' $names 0
        $dir = if ($choice -eq $names.Count - 1) { "$(Read-Host '  Folder')".Trim().Trim('"') } else { $folders[$names[$choice]] }
    }
    if (-not (Test-Path $dir -PathType Container)) { Write-Host "  Folder not found: $dir" -ForegroundColor Red; return }
    $file = Join-Path $dir ("tidywin-apps-{0}-{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd'))

    Write-Step 'Creating the list with WinGet'
    Write-Host '  Apps that are not in WinGet show up as warnings and are left out.' -ForegroundColor DarkGray
    & winget export -o $file --accept-source-agreements
    if (-not (Test-Path $file)) { Write-Host "`nCould not create the file." -ForegroundColor Red; return }

    $ids = Get-PackageIds $file
    Write-Host "`nDone: $($ids.Count) apps saved to" -ForegroundColor Green
    Write-Host "  $file"
    Write-Host 'After formatting, choose "Restore apps and drivers" in TidyWin.' -ForegroundColor DarkGray
}

#endregion


#region ==================== 3. IMPORT ====================

function Invoke-Import {
    # Saved lists: in the root of USB drives and other disks, and in the user's folders; newest first
    $found = @((Get-SavePlaces).Values | ForEach-Object {
        Get-ChildItem -Path $_ -Filter 'tidywin-apps-*.json' -File -ErrorAction SilentlyContinue
    } | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending)

    # --- The panel's page: which list, nothing picked
    if ($Describe) {
        $options = @($found | ForEach-Object {
            $count = try { " · $(@(Get-PackageIds $_.FullName).Count) apps" } catch { '' }
            Opt $_.FullName "$($_.Name)  ($(Split-Path $_.DirectoryName -Leaf))$count"
        }) + (Opt 'other' 'Another file')
        $fields = @(
            New-Field 'Apps' 'AppList' 'select' 'Saved app list' 'The apps in it that are not on this PC yet are installed. Apps already installed are skipped.' '' @{ options = $options }
            New-Field 'Apps' 'AppListOther' 'path' 'File' 'A tidywin-apps .json file.' '' @{ when = @{ field = 'AppList'; is = 'other' }; required = $true; pick = 'file'; filter = 'App list (*.json)|*.json|All files (*.*)|*.*' }
        )
        $notes = @(if (-not $found) { 'No saved app list found on USB drives, other disks, Desktop, Documents, Downloads or OneDrive. Plug in the drive, or choose the file.' })
        Write-OptionsPage $Describe $fields $notes
        return
    }

    Write-Host "`nBackup-Apps -Import" -ForegroundColor Green
    if ($Answers) {
        $answer = [IO.File]::ReadAllText($Answers) | ConvertFrom-Json
        $file = if ($answer.AppList -eq 'other') { "$($answer.AppListOther)".Trim() } else { "$($answer.AppList)" }
        if (-not $file) { Write-Host 'No app list was chosen, so no apps were installed.'; return }
    } else {
        $labels = @($found | ForEach-Object { "$($_.Name)  ($(Split-Path $_.DirectoryName -Leaf))" }) + 'Another file (type the path)'
        if ($found) {
            $choice = Choose 'Which list to install?' $labels 0
        } else {
            Write-Host '  No list found on USB drives, other disks, Desktop, Documents, Downloads or OneDrive.' -ForegroundColor DarkYellow
            $choice = $labels.Count - 1
        }
        $file = if ($choice -eq $labels.Count - 1) { "$(Read-Host '  Path to the .json file')".Trim().Trim('"') } else { $found[$choice].FullName }
    }
    if (-not (Test-Path $file -PathType Leaf)) { Write-Host "  File not found: $file" -ForegroundColor Red; return }

    try { $ids = Get-PackageIds $file } catch { Write-Host '  This file is not a WinGet list.' -ForegroundColor Red; return }
    Write-Host "`n  $($ids.Count) apps in the list:"
    $ids | Sort-Object | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ''
    if (-not $Answers -and -not (Ask "Install the apps that are not on this PC yet?" $true)) { Write-Host 'Nothing was installed.'; return }

    Write-Step 'Installing with WinGet (apps already installed are skipped)'
    & winget import -i $file --ignore-unavailable --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Write-Host "`nDone." -ForegroundColor Green }
    else { Write-Host "`nFinished with warnings: see above for the apps that were not installed." -ForegroundColor Yellow }
}

#endregion


#region ==================== 4. EXECUTION ====================

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    if ($Describe) {
        Write-OptionsPage $Describe @(New-Field $(if ($Import) { 'Apps' } else { 'Backup' }) 'NoWinget' 'header' 'WinGet is not installed' 'Open Set up → Applications first: it installs WinGet. Then come back here.' $null)
        return
    }
    Write-Host 'WinGet is not installed. In TidyWin, choose "Applications", which installs it, and try again.' -ForegroundColor Yellow
    return
}

if     ($Export) { Invoke-Export }
elseif ($Import) { Invoke-Import }
else {
    $mode = Choose 'What do you want to do?' @('Save the list of apps on this PC', 'Install apps from a saved list') 0
    if ($mode -eq 0) { Invoke-Export } else { Invoke-Import }
}

#endregion
