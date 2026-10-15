#Requires -RunAsAdministrator
<#
    uninstall-apps.ps1 — uninstalls programs with their own official uninstaller, then cleans up what they left behind

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\uninstall-apps.ps1

    1. Lists the installed programs (the same list as Settings → Apps → Installed apps, without system
       components and updates). Check the ones to remove.
    2. Creates a restore point, then runs each program's official uninstaller, one at a time, with its
       own window: you see it and answer it. Nothing is forced.
    3. After you close the uninstaller windows, looks for what the removed programs left behind and
       shows everything before deleting:
         checked ..... the install folder that remained (under 1 GB, not named after the publisher),
                       broken shortcuts, empty Start menu folders, scheduled tasks of the program
         unchecked ... folders and registry keys with the program's name (likely theirs, not certain),
                       big install folders (usually your data), anything of a program whose uninstaller
                       was missing, and anything too big for the Recycle Bin
       Never touches Windows, Program Files/ProgramData/AppData themselves, Common Files, Microsoft folders,
       your Desktop/Documents/Downloads, links, or any folder an installed program still uses.
    4. Deletes only what you confirm: folders and shortcuts go to the Recycle Bin (what doesn't fit asks
       again, one by one, before being deleted for good); registry keys and scheduled tasks are exported
       first to %ProgramData%\TidyWin\uninstall-backup\<date>, with a deleted.txt listing everything
       (double-click a .reg file to put a key back).

    FILE LAYOUT
        1. Helpers ................... prompts, checklist with search
        2. Installed programs ........ list and official uninstaller
        3. Leftovers ................. search (with safety rules) and removal with backup
        4. Execution
#>
param(
    [string]$Describe,   # for the panel: writes the programs and options of the page to this file and stops
    [string]$Answers     # for the panel: what was chosen there (nothing is asked)
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

function Write-Result([ValidateSet('OK', 'SKIP', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $color = @{ OK = 'Green'; SKIP = 'DarkGray'; WARN = 'Yellow'; ERROR = 'Red' }[$Status]
    $label = @{ OK = 'OK'; SKIP = '--'; WARN = 'WARNING'; ERROR = 'ERROR' }[$Status]
    Write-Host ("  [{0}] " -f $label) -ForegroundColor $color -NoNewline
    Write-Host $Text
}

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

function Format-Size([double]$Bytes) {
    if ($Bytes -le 0)   { return '' }
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Full-screen checklist with scrolling, optional group headers and search (same keys as the apps list):
# ↑ ↓ PgUp PgDn move, Space checks, A checks/unchecks the whole group, / searches, Enter confirms, Esc quits.
# $Items: objects with Group ('' = no header), Label, Note, Checked, Size. Returns the checked items (none on Esc).
function Select-Items([string]$Title, [object[]]$Items, [switch]$Short) {
    if ($script:Panel) {
        # -Short: a short list (the leftovers to review), with no title or search in the panel; $Title goes to the log
        $answer = Request-Panel @{ type = 'checklist'; title = $(if ($Short) { '' } else { $Title }); question = $Title; search = -not $Short
            items = @($Items | ForEach-Object { @{ label = "$($_.Label)"; note = "$($_.Note)"; group = "$($_.Group)"; checked = [bool]$_.Checked } }) }
        if ($null -eq $answer) { return @() }
        for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = @($answer.checked) -contains $i }
        return @($Items | Where-Object Checked)
    }
    $arrows =($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console: numbered list, numbers separated by commas
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

    $rows = New-Object System.Collections.Generic.List[object]
    $lastGroup = $null
    foreach ($it in $Items) {
        if ($it.Group -and $it.Group -ne $lastGroup) { $rows.Add([pscustomobject]@{ IsHeader = $true; Text = $it.Group }) }
        $lastGroup = $it.Group
        $rows.Add([pscustomobject]@{ IsHeader = $false; Item = $it })
    }
    $itemRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if (-not $rows[$r].IsHeader) { $r } })
    $labelWidth = [Math]::Min(52, ($Items | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum)
    $grouped = [bool]($Items | Where-Object Group)       # "A" (check the whole group) only exists in lists with groups
    $help = if ($grouped) { '  ↑ ↓ move   Space check   A check the whole group   / search   Enter continue   Esc quit' }
            else          { '  ↑ ↓ move   Space check   / search   Enter continue   Esc quit' }
    $cursor = 0; $scroll = 0; $lastSize = ''
    $searchMode = $false; $searchText = ''; $searchFound = $false; $searchOrigin = 0

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
            & $line $help 'DarkGray'
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

            & $line '' 'Gray'
            if ($searchMode) {
                $hint = if ($searchText -and -not $searchFound) { '   (nothing found)' } else { '   (Enter confirms, Esc cancels)' }
                & $line "  Search: $($searchText)_$hint" 'Cyan'
            } else {
                $checked = @($Items | Where-Object Checked)
                $size = Format-Size ($checked | Measure-Object Size -Sum).Sum
                & $line "  $($checked.Count) checked$(if ($size) { " · $size" })   ·   $($cursor + 1) of $($itemRows.Count)" 'DarkGray'
            }

            $keyInfo = [Console]::ReadKey($true)
            $key = $keyInfo.Key

            # --- Search mode: typing jumps to the first item whose label contains the text
            if ($searchMode) {
                if     ($key -eq 'Escape')    { $cursor = $searchOrigin; $searchMode = $false; continue }
                elseif ($key -eq 'Enter')     { $searchMode = $false; continue }
                elseif ($key -eq 'Backspace') { if ($searchText) { $searchText = $searchText.Substring(0, $searchText.Length - 1) } }
                elseif (-not [char]::IsControl($keyInfo.KeyChar)) { $searchText += $keyInfo.KeyChar }
                $searchFound = $false
                if ($searchText) {
                    for ($c = 0; $c -lt $itemRows.Count; $c++) {
                        if ($rows[$itemRows[$c]].Item.Label.IndexOf($searchText, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $cursor = $c; $searchFound = $true; break }
                    }
                }
                continue
            }
            if ($keyInfo.KeyChar -eq '/') { $searchMode = $true; $searchText = ''; $searchFound = $false; $searchOrigin = $cursor; continue }

            switch ($key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - $viewport) }
                'PageDown'  { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + $viewport) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $itemRows.Count - 1 }
                'Spacebar'  { $it = $rows[$itemRows[$cursor]].Item; $it.Checked = -not $it.Checked }
                'A' {
                    # Whole group: checks everything in it; if all are already checked, unchecks them.
                    # Never in a list without groups: it would check every item (every installed program).
                    if (-not $rows[$itemRows[$cursor]].Item.Group) { continue }
                    $group = @($Items | Where-Object Group -eq $rows[$itemRows[$cursor]].Item.Group)
                    $checkAll = @($group | Where-Object { -not $_.Checked }).Count -gt 0
                    foreach ($it in $group) { $it.Checked = $checkAll }
                }
                'Enter'     { return @($Items | Where-Object Checked) }
                'Escape'    { return }
            }
        }
    } finally {
        Clear-Host
        [Console]::CursorVisible = $true
    }
}


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).'
    return
}

#endregion


#region ==================== 2. INSTALLED PROGRAMS ====================

$UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)

# Folder path without quotes, trailing backslash or a file at the end (some programs write "C:\App\app.exe,0").
function Get-CleanPath([string]$Path) {
    $p = ("$Path".Trim() -replace ',\s*-?\d+$', '').Trim().Trim('"')     # "C:\x\app.exe",0
    $p = [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\')
    if (-not (Test-FullPath $p)) { return '' }
    if ($p -match '\.(exe|dll|ico)$') { $p = Split-Path $p -Parent }
    return $p
}

# Programs as Settings lists them: with a name and an uninstaller, without system components, updates
# and driver packages. 32- and 64-bit entries of the same program are shown once.
function Get-InstalledPrograms {
    $list = foreach ($root in $UninstallRoots) {
        foreach ($key in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or -not $p.UninstallString -or $p.NoRemove -eq 1) { continue }   # NoRemove: Windows doesn't allow it either
            if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { continue }
            if ($p.DisplayName -match '^Windows Driver Package') { continue }
            $date = if ("$($p.InstallDate)" -match '^\d{8}$') { "$($p.InstallDate)".Insert(6, '-').Insert(4, '-') } else { '' }
            [pscustomobject]@{
                Name            = "$($p.DisplayName)".Trim()
                Publisher       = "$($p.Publisher)".Trim()
                Version         = "$($p.DisplayVersion)".Trim()
                Date            = $date
                Size            = [int64]$p.EstimatedSize * 1KB
                Key             = $key.PSPath
                KeyName         = $key.PSChildName
                UninstallString = "$($p.UninstallString)".Trim()
                Msi             = $p.WindowsInstaller -eq 1 -and $key.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$'
                InstallLocation = Get-CleanPath $p.InstallLocation
                Icon            = Get-CleanPath $p.DisplayIcon
            }
        }
    }
    return @($list | Sort-Object Name, Version -Unique | Sort-Object Name)
}

# True for a full path like C:\x\y.exe. Some programs register broken commands (stray quotes, < > |):
# those are not a path, and [IO.Path] would stop with "invalid characters in path".
function Test-FullPath($Path) {
    return [bool]($Path -and $Path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -lt 0 -and [IO.Path]::IsPathRooted($Path))
}

# Splits an uninstall command into program and arguments: "C:\x\unins000.exe" /SILENT -> exe + args.
# MSI programs always use msiexec /x {GUID} (some register /I, which opens "modify" instead).
function Split-UninstallCommand($Program) {
    if ($Program.Msi) { return @{ File = "$env:SystemRoot\System32\msiexec.exe"; Args = "/x $($Program.KeyName)" } }
    $cmd = [Environment]::ExpandEnvironmentVariables($Program.UninstallString)
    $c = if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') { @{ File = $Matches[1]; Args = $Matches[2] } }
         elseif ($cmd -match '^\s*(.+?\.exe)\s*(.*)$') { @{ File = $Matches[1]; Args = $Matches[2] } }
         elseif ((Test-FullPath $cmd.Trim()) -and (Test-Path -LiteralPath $cmd.Trim())) { @{ File = $cmd.Trim(); Args = '' } }   # C:\Program Files\x\uninstall.bat
         elseif ($cmd -match '^\s*(\S+)\s*(.*)$') { @{ File = $Matches[1]; Args = $Matches[2] } }   # cmd /c "...", without .exe
         else { @{ File = $cmd; Args = '' } }
    $c.File = $c.File.Trim().Trim('"')
    # "MsiExec.exe /I{...}", "rundll32.exe ...": a name without a folder is a Windows program
    if ($c.File -and -not (Test-FullPath $c.File)) {
        $found = Get-Command $c.File -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $c.File = $found.Source }
    }
    if ($c.File -match '(?i)(^|\\)msiexec(\.exe)?$') { $c.Args = $c.Args -replace '(?i)/I\s*(\{)', '/X$1' }   # /I opens "modify"
    return $c
}

# Runs the official uninstaller with its own window and waits. Some uninstallers (NSIS, Inno) start a
# copy of themselves and exit right away, so after the process ends the script also waits for the
# program to leave the list, until you press a key.
# Returns: Removed, Kept (still installed: cancelled or failed) or Restart (removed; restart to finish).
function Invoke-Uninstall($Program) {
    $c = Split-UninstallCommand $Program
    if (-not (Test-FullPath $c.File) -or -not (Test-Path -LiteralPath $c.File)) {
        Write-Result 'WARN' "The uninstaller is missing ($($c.File)): the program is already partly removed"
        return 'Orphan'
    }
    Write-Host "  Opening the uninstaller of $($Program.Name)..." -ForegroundColor DarkGray
    $start = @{ FilePath = $c.File; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
    if ($c.Args.Trim()) { $start.ArgumentList = $c.Args.Trim() }      # Start-Process rejects an empty argument list
    try {
        $proc = Start-Process @start
    } catch {
        Write-Result 'ERROR' "$($_.Exception.Message)"
        return 'Kept'
    }
    if (Test-Path -LiteralPath $Program.Key) {
        if ($script:Panel) {
            # The panel goes on by itself when the program leaves the list
            [void](Request-Panel @{ type = 'wait'; question = "Finish the uninstaller of $($Program.Name)"; button = 'I closed or cancelled it'; untilGone = $Program.Key })
        } elseif ([Console]::IsInputRedirected -or $Host.Name -ne 'ConsoleHost') {
            [void](Read-Host '  When the uninstaller is finished (or if you cancelled it), press Enter')
        } else {
            while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }    # keys typed before don't count
            Write-Host '  Waiting for the uninstaller to finish... (press any key if you closed or cancelled it)' -ForegroundColor DarkGray
            while ((Test-Path -LiteralPath $Program.Key) -and -not ([Console]::KeyAvailable)) { Start-Sleep -Milliseconds 700 }
            while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        }
    }
    if (Test-Path -LiteralPath $Program.Key) { return 'Kept' }
    if ($proc.ExitCode -in 1641, 3010) { return 'Restart' }
    return 'Removed'
}

# Some uninstallers keep deleting files after the program leaves the list (a copy of themselves in %TEMP%).
# Waits until no uninstaller and nothing from the programs' folders is running, for up to a minute.
function Wait-Uninstallers([string[]]$Folders) {
    Write-Host '  Waiting for the uninstallers to finish...' -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $until = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $until) {
        $busy = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $proc = $_
            $proc.ProcessName -match '^(un_?a|au_|unins\d*|uninst.*|uninstall.*)$' -or
            ($proc.Path -and ($Folders | Where-Object { $proc.Path -like "$_\*" }))
        })
        if (-not $busy) { return }
        Start-Sleep -Seconds 1
    }
    Write-Host '  Still running after a minute; looking for leftovers anyway. Files in use are skipped.' -ForegroundColor DarkGray
}

# Windows creates at most one restore point a day: when one exists from the last 24 hours, it only warns.
# So the result is checked by comparing the newest point before and after.
function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
        Checkpoint-Computer -Description 'Before Uninstall-Apps' -RestorePointType APPLICATION_UNINSTALL -ErrorAction Stop -WarningAction SilentlyContinue
        $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue) | Select-Object -Last 1
        if ($after -and (-not $before -or $after.SequenceNumber -ne $before.SequenceNumber)) {
            Write-Result 'OK' 'Restore point created'
        } elseif ($after) {
            $when = $after.ConvertToDateTime($after.CreationTime).ToString('g')
            Write-Result 'OK' "Using the restore point from $when."
            Write-Host '  Windows creates at most one restore point a day.' -ForegroundColor Yellow
        } else {
            throw 'System Restore did not create it'
        }
        return $true
    } catch {
        Write-Result 'WARN' "Could not create the restore point ($($_.Exception.Message.Trim()))"
        if ($script:Answer) { Write-Host '  Going on without it: only the programs'' own uninstallers are used.' -ForegroundColor DarkGray; return $true }
        return (Ask 'Continue anyway? (only the programs'' own uninstallers are used)' $false)
    }
}

#endregion


#region ==================== 3. LEFTOVERS ====================

# Places searched for folders with the program's name.
$FolderRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA,
                 (Join-Path $env:LOCALAPPDATA 'Programs'), (Join-Path $env:USERPROFILE 'AppData\LocalLow')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

# Registry places searched for keys with the program's name (Software\<name> and Software\<publisher>\<name>).
$RegistryRoots = @('HKCU:\SOFTWARE', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')

# Names never offered, as a folder or a key: they belong to Windows or are shared by many programs.
$ProtectedNames = @('microsoft', 'windows', 'common files', 'commonfiles', 'packages', 'programs', 'temp', 'classes',
                    'policies', 'wow6432node', 'intel', 'nvidia corporation', 'amd', 'realtek', 'google', 'mozilla',
                    'adobe', 'apple', 'oracle', 'java', 'installer', 'package cache', 'regid.1991-06.com.microsoft',
                    'windowsapps', 'windowspowershell', 'windows nt', 'windows defender', 'internet explorer',
                    'reference assemblies', 'msbuild', 'dotnet', 'microsoft.net', 'modifiablewindowsapps', 'clients',
                    'registeredapplications', 'odbc', 'crashdumps', 'd3dscache', 'fonts', 'history')

# Folders a program uses: the registered install folder, and the folders of its icon and of its uninstaller
# (many programs don't register the first). Windows' own folders are left out.
function Get-ProgramFolders($Program) {
    $list = @($Program.InstallLocation, $Program.Icon)
    $c = Split-UninstallCommand $Program
    if (Test-FullPath $c.File) { $list += Split-Path $c.File -Parent }
    # Drive roots and Program Files/AppData themselves are never a program's own folder (a stray icon there
    # would otherwise protect everything under it)
    $roots = @($FolderRoots | ForEach-Object { $_.TrimEnd('\') })
    return @($list | Where-Object { $_ -and $_ -notlike "$env:SystemRoot\*" -and $_ -match '^[A-Za-z]:\\.' -and $roots -notcontains $_.TrimEnd('\') } |
             Select-Object -Unique)
}

# Bytes the Recycle Bin of a drive takes in one item; 0 = no Recycle Bin there (removable/network drive,
# or set to delete at once). Windows deletes for good, WITHOUT asking, what doesn't fit, so those items
# are flagged and need a separate confirmation.
$script:RecycleCapacity = @{}
function Get-RecycleCapacity([string]$Path) {
    $drive = Split-Path $Path -Qualifier
    if ($script:RecycleCapacity.ContainsKey($drive)) { return $script:RecycleCapacity[$drive] }
    $bytes = 0
    $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter = '$drive'" -ErrorAction SilentlyContinue
    if ($vol -and $vol.DriveType -eq 3) {
        $guid = [regex]::Match("$($vol.DeviceID)", '\{[0-9a-fA-F-]+\}').Value
        $bb = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$guid" -ErrorAction SilentlyContinue
        if ($bb.NukeOnDelete -eq 1) { $bytes = 0 }
        elseif ($bb.MaxCapacity) { $bytes = [int64]$bb.MaxCapacity * 1MB }
        else { $bytes = [int64]($vol.Capacity * 0.05) }      # Windows' default: about 5% of the drive
    }
    $script:RecycleCapacity[$drive] = $bytes
    return $bytes
}
function Test-Recyclable([string]$Path, [int64]$Size) {
    $capacity = Get-RecycleCapacity $Path
    return $capacity -gt 0 -and $Size -lt $capacity * 0.9
}

# Name reduced for comparing: lower case, without "(x64)", versions and symbols.
#   "7-Zip 24.08 (x64)" -> "7zip", "VLC media player" -> "vlcmediaplayer"
function Get-NameKey([string]$Name) {
    $n = $Name.ToLowerInvariant() -replace '\(.*?\)', '' -replace '\b(x64|x86|64-bit|32-bit|amd64)\b', '' -replace '\bv?\d+(\.\d+)+\b', ''
    return ($n -replace '[^\p{L}\p{Nd}]', '')
}

# Folder that must never be offered: Windows, the roots themselves, profile folders, links, or a folder
# that holds (or is inside) a program that is still installed.
function Test-ProtectedPath([string]$Path, [string[]]$KeepLocations) {
    $full = $Path.TrimEnd('\')
    if ($full -match '^[A-Za-z]:$' -or $full -notmatch '^[A-Za-z]:\\') { return $true }      # a drive root, or not a local path
    $never = @($env:SystemRoot, $env:USERPROFILE, (Join-Path $env:USERPROFILE 'AppData'),
               [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
               (Join-Path $env:USERPROFILE 'Downloads'), [Environment]::GetFolderPath('CommonDesktopDirectory')) + $FolderRoots
    if ($never | Where-Object { $_ -and $full -ieq $_.TrimEnd('\') }) { return $true }
    if ($full -like "$env:SystemRoot\*" -or $full -like '*\Common Files' -or $full -like '*\Common Files\*' -or $full -like '*\WindowsApps*') { return $true }
    if ($ProtectedNames -contains (Split-Path $full -Leaf).ToLowerInvariant()) { return $true }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $true }
    foreach ($k in $KeepLocations) {
        if ($k -ieq $full -or $k -like "$full\*" -or $full -like "$k\*") { return $true }
    }
    return $false
}

function Get-FolderSize([string]$Path) {
    return [int64](Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# Target of a .lnk shortcut ('' if it can't be read).
$Shell = New-Object -ComObject WScript.Shell
function Get-ShortcutTarget([string]$Path) {
    try { return $Shell.CreateShortcut($Path).TargetPath } catch { return '' }
}

# What a removed program left behind. $KeepLocations: folders of programs still installed; $KeepNames:
# their names. $Trusted = $false (uninstaller was missing): nothing comes checked, since the program may
# not really be gone.
# Each item: Kind (Folder/Registry/Shortcut/Task), Path, Reason, Checked (high confidence), Size, Recyclable.
function Find-Leftovers($Program, [string[]]$KeepLocations, [string[]]$KeepNames, [bool]$Trusted) {
    $found = New-Object System.Collections.Generic.List[object]
    $add = {
        param($Kind, $Path, $Reason, $Checked, $Size)
        if ($found | Where-Object { $_.Path -ieq $Path }) { return }
        $sure = $Checked -and $Trusted
        $recyclable = $true
        if ($Kind -in 'Folder', 'Shortcut' -and -not (Test-Recyclable $Path $Size)) {
            $recyclable = $false; $Checked = $false
            $Reason += ' · too big for the Recycle Bin: would be deleted for good'
        }
        $found.Add([pscustomobject]@{ Kind = $Kind; Path = $Path; Reason = $Reason; Checked = ($Checked -and $Trusted); Sure = $sure; Size = [int64]$Size; Recyclable = $recyclable })
    }

    $names = @(Get-NameKey $Program.Name)
    # Install folder: the registered one (certain) or, without it, the folder of the program's icon (a guess)
    $fromIcon = -not $Program.InstallLocation
    $location = if ($Program.InstallLocation) { $Program.InstallLocation } elseif ($Program.Icon -and $Program.Icon -notlike "$env:SystemRoot\*") { $Program.Icon } else { '' }
    # The install folder's name also identifies it, unless it is generic ("bin", "App", "Client"...)
    $generic = @('bin', 'app', 'apps', 'application', 'program', 'client', 'data', 'common', 'shared', 'current', 'latest', 'x64', 'x86')
    if ($location) {
        $leaf = Get-NameKey (Split-Path $location -Leaf)
        if ($leaf.Length -ge 4 -and $generic -notcontains $leaf) { $names += $leaf }
    }
    $names = @($names | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
    # A name another installed program also uses (e.g. two Python versions) is not a reliable match
    $names = @($names | Where-Object { $KeepNames -notcontains $_ })
    $publisher = Get-NameKey $Program.Publisher

    # 1. The install folder, if it is still there. Checked only when it is clearly the program's own:
    #    registered, not named after the publisher (could hold its other programs) and under 1 GB
    #    (more than that after uninstalling is usually your data: saves, mods, downloads).
    if ($location -and (Test-Path -LiteralPath $location) -and -not (Test-ProtectedPath $location $KeepLocations)) {
        $size = Get-FolderSize $location
        $leafKey = Get-NameKey (Split-Path $location -Leaf)
        if ($fromIcon) { & $add 'Folder' $location 'folder of the program''s icon' $false $size }
        elseif ($publisher -and $leafKey -eq $publisher) { & $add 'Folder' $location 'install folder named after the publisher: may hold its other programs' $false $size }
        elseif ($size -gt 1GB) { & $add 'Folder' $location 'install folder that remained · large: look inside first' $false $size }
        else { & $add 'Folder' $location 'install folder that remained' $true $size }
    }

    # 2. Folders with the program's name, and <publisher>\<name> (unchecked: likely theirs, not certain)
    foreach ($root in $FolderRoots) {
        foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
            $key = Get-NameKey $dir.Name
            if ($names -contains $key -and -not (Test-ProtectedPath $dir.FullName $KeepLocations)) {
                & $add 'Folder' $dir.FullName 'folder with the program''s name' $false (Get-FolderSize $dir.FullName)
            }
            elseif ($publisher.Length -ge 3 -and $key -eq $publisher -and $ProtectedNames -notcontains $dir.Name.ToLowerInvariant()) {
                foreach ($sub in (Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                    if ($names -contains (Get-NameKey $sub.Name) -and -not (Test-ProtectedPath $sub.FullName $KeepLocations)) {
                        & $add 'Folder' $sub.FullName 'folder with the program''s name, inside the publisher''s' $false (Get-FolderSize $sub.FullName)
                    }
                }
            }
        }
    }

    # 3. Registry keys Software\<name> and Software\<publisher>\<name> (unchecked)
    foreach ($root in $RegistryRoots) {
        foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $leaf = $k.PSChildName
            if ($ProtectedNames -contains $leaf.ToLowerInvariant()) { continue }
            $key = Get-NameKey $leaf
            if ($names -contains $key) {
                & $add 'Registry' $k.Name 'registry key with the program''s name' $false 0
            } elseif ($publisher.Length -ge 3 -and $key -eq $publisher) {
                foreach ($sub in (Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue)) {
                    if ($names -contains (Get-NameKey $sub.PSChildName)) {
                        & $add 'Registry' $sub.Name 'registry key with the program''s name, inside the publisher''s' $false 0
                    }
                }
            }
        }
    }

    # 4. Broken shortcuts that pointed into the program's folder or have its name (checked):
    #    the whole Start menu, and only the desktop itself (not your folders on it)
    $menus = @([Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu')) | Where-Object { $_ }
    $desks = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ }
    $links = @(Get-ChildItem -LiteralPath $menus -Recurse -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath $desks -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue)
    foreach ($lnk in $links) {
        $target = Get-ShortcutTarget $lnk.FullName
        if (-not $target -or (Test-Path -LiteralPath $target)) { continue }
        $ours = ($location -and $target -like "$location\*") -or ($names -contains (Get-NameKey $lnk.BaseName))
        if ($ours) { & $add 'Shortcut' $lnk.FullName 'shortcut to a program that no longer exists' $true $lnk.Length }
    }
    # Start menu folders that became empty (checked)
    foreach ($menu in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))) {
        foreach ($dir in (Get-ChildItem -LiteralPath $menu -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($names -notcontains (Get-NameKey $dir.Name) -and $publisher -ne (Get-NameKey $dir.Name)) { continue }
            $rest = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' -and -not ($found | Where-Object Path -ieq $_.FullName) })
            if (-not $rest) { & $add 'Folder' $dir.FullName 'Start menu folder left empty' $true 0 }
        }
    }

    # 5. Scheduled tasks (updaters) whose program no longer exists and was in the program's folder or has its name (checked)
    foreach ($task in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($action in @($task.Actions | Where-Object { $_.Execute })) {
            $exe = [Environment]::ExpandEnvironmentVariables($action.Execute.Trim('"'))
            if (-not (Test-FullPath $exe) -or (Test-Path -LiteralPath $exe)) { continue }   # "powershell.exe": a Windows program
            $ours = ($location -and $exe -like "$location\*") -or ($names | Where-Object { (Get-NameKey $task.TaskName).Contains($_) })
            if ($ours) { & $add 'Task' "$($task.TaskPath)$($task.TaskName)" 'scheduled task of a program that no longer exists' $true 0; break }
        }
    }
    return $found
}

# Deletes what was confirmed: folders and shortcuts to the Recycle Bin; registry keys and tasks exported first.
# Everything done is listed in deleted.txt in the backup folder (Recycle Bin items included).
# Items that don't fit in the Recycle Bin are only deleted for good after their own confirmation.
function Remove-Leftovers([object[]]$Items, [string]$BackupDir) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $log = Join-Path $BackupDir 'deleted.txt'
    $n = 0
    foreach ($it in $Items) {
        $n++
        $exists = if ($it.Kind -eq 'Registry') { Test-Path -LiteralPath ('Registry::' + $it.Path) }
                  elseif ($it.Kind -eq 'Task') { [bool](Get-ScheduledTask -TaskPath ($it.Path -replace '[^\\]+$', '') -TaskName (Split-Path $it.Path -Leaf) -ErrorAction SilentlyContinue) }
                  else { Test-Path -LiteralPath $it.Path }
        if (-not $exists) { Write-Result 'SKIP' "$($it.Path): no longer there"; continue }
        $bin = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        $how = 'Recycle Bin'
        if ($it.Kind -in 'Folder', 'Shortcut' -and -not $it.Recyclable) {
            Write-Host "  $($it.Path) ($(Format-Size $it.Size)) doesn't fit in the Recycle Bin." -ForegroundColor Yellow
            $forGood = if ($script:Answer) { $true } else { Ask 'Delete it for good, with no way back?' $false }
            if (-not $forGood) { Write-Result 'SKIP' "$($it.Path): kept"; continue }
            $bin = [Microsoft.VisualBasic.FileIO.RecycleOption]::DeletePermanently
            $how = 'deleted for good'
        }
        try {
            switch ($it.Kind) {
                'Folder'   { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, $ui, $bin) }
                'Shortcut' { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Path, $ui, $bin) }
                'Registry' {
                    $reg = Join-Path $BackupDir ('{0:D2} {1}.reg' -f $n, ((Split-Path $it.Path -Leaf) -replace '[\\/:*?"<>|]', '_'))
                    & reg.exe export $it.Path $reg /y *> $null
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $reg)) { throw 'could not back it up, so it was not deleted' }
                    Remove-Item -LiteralPath ('Registry::' + $it.Path) -Recurse -Force -ErrorAction Stop
                    $how = "backup: $(Split-Path $reg -Leaf)"
                }
                'Task' {
                    $taskPath = ($it.Path -replace '[^\\]+$', ''); $taskName = Split-Path $it.Path -Leaf
                    $xml = Join-Path $BackupDir ('{0:D2} {1}.xml' -f $n, ($taskName -replace '[\\/:*?"<>|]', '_'))
                    Export-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Set-Content $xml -Encoding Unicode
                    Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction Stop
                    $how = "backup: $(Split-Path $xml -Leaf)"
                }
            }
            Write-Result 'OK' "$($it.Path)"; Write-Host "       $how" -ForegroundColor DarkGray
            Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $($it.Kind)  $($it.Path)  ($how)" -Encoding UTF8
        } catch {
            Write-Result 'ERROR' "$($it.Path): $($_.Exception.Message.Trim())"
        }
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if (-not $script:Panel) { Write-Host "`nUninstall-Apps" -ForegroundColor Green }   # in the panel the page already has the title
if (-not $Describe) {
    Write-Host '  Uninstalls programs with their own uninstaller, then shows what they left behind before deleting it.' -ForegroundColor DarkGray
    Write-Host '  Reading the installed programs...' -ForegroundColor DarkGray
}

Write-Loading 'Reading the installed programs' 10
$programs = @(Get-InstalledPrograms)
$items = @($programs | ForEach-Object {
    $note = (@($_.Publisher, $_.Version, (Format-Size $_.Size), $_.Date) | Where-Object { $_ }) -join ' · '
    [pscustomobject]@{ Group = ''; Label = $_.Name; Note = $note; Checked = $false; Size = $_.Size; Program = $_ }
})

# --- The panel's page: the programs (with search), then what to do with what they leave behind. Nothing on.
if ($Describe) {
    $T = 'Programs'
    $fields = @(
        if ($items) {
            New-Field $T 'programs' 'checklist' '' '' @() @{ search = $true
                items = @($items | ForEach-Object { [ordered]@{ value = $_.Program.Key; label = $_.Label; note = $_.Note; group = ''; status = '' } }) }
        } else {
            New-Field $T 'Nothing' 'header' 'No programs found' 'Nothing on this PC can be uninstalled from here.' $null
        }
        New-Field $T 'Leftovers' 'toggle' 'Remove leftovers' 'What is certainly theirs goes right away: the install folder that remained, broken shortcuts, empty Start menu folders and their scheduled tasks. What only might be theirs, like folders with their name or your data, is listed at the end for you to pick, nothing checked. Folders go to the Recycle Bin; registry keys and tasks are backed up first.' $false @{ footer = $true }
    )
    Write-OptionsPage $Describe $fields @('Each program opens its own uninstaller: follow its window. Close the programs before you start.')
    return
}
if (-not $programs) { Write-Host 'No programs found.'; return }

# --- Choose
if ($Answers) {
    $script:Answer = [IO.File]::ReadAllText($Answers) | ConvertFrom-Json
    $picked = @($script:Answer.programs)
    $chosen = @($items | Where-Object { $picked -contains $_.Program.Key })
} else {
    $chosen = @(Select-Items "Uninstall-Apps — choose the programs to uninstall ($($programs.Count) installed)" $items)
}
if (-not $chosen) { Write-Host 'Nothing was uninstalled.'; return }

Write-Host "`n  $($chosen.Count) program(s) to uninstall:"
$chosen | ForEach-Object { Write-Host "    - $($_.Label)" }
Write-Host '  Each one opens its own uninstaller: follow its window.' -ForegroundColor DarkGray

# Programs still open block their uninstaller (or leave files behind): name them so they can be closed
$chosenFolders = @($chosen | ForEach-Object { Get-ProgramFolders $_.Program })
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $proc = $_; $proc.Path -and ($chosenFolders | Where-Object { $proc.Path -like "$_\*" }) } |
             Select-Object -ExpandProperty ProcessName -Unique)
if ($running) {
    Write-Host "  Still open: $($running -join ', '). Close them before going on." -ForegroundColor Yellow
}
if (-not $Answers -and -not (Ask 'Uninstall now?' $true)) { Write-Host 'Nothing was uninstalled.'; return }

# --- Uninstall
Write-Step 'Restore point'
if (-not (New-RestorePoint)) { Write-Host 'Nothing was uninstalled.'; return }

$results = @()
for ($i = 0; $i -lt $chosen.Count; $i++) {
    $prog = $chosen[$i].Program
    Write-Step "[$($i + 1)/$($chosen.Count)] $($prog.Name)"
    $status = Invoke-Uninstall $prog
    switch ($status) {
        'Removed' { Write-Result 'OK' 'Uninstalled' }
        'Restart' { Write-Result 'OK' 'Uninstalled'; Write-Host '       Restart the PC to finish.' -ForegroundColor DarkGray }
        'Orphan'  { }
        'Kept'    { Write-Result 'SKIP' 'Still installed'; Write-Host '       The uninstaller was cancelled or failed.' -ForegroundColor DarkGray }
    }
    $results += [pscustomobject]@{ Program = $prog; Status = $status }
}

# --- Leftovers of what was removed (and of entries whose uninstaller was already gone)
$removed = @($results | Where-Object { $_.Status -in 'Removed', 'Restart', 'Orphan' })
$lookForLeftovers = -not $Answers -or $script:Answer.Leftovers
if ($removed -and $lookForLeftovers) {
    # Some uninstallers keep deleting files after they leave the list: wait for them first
    Write-Host ''
    if ($Answers) {
        Wait-Uninstallers $chosenFolders
    } else {
        [void](Read-Host '  Close any uninstaller window still open, then press Enter to look for leftovers')
    }
    Write-Step 'Looking for leftovers'
    $remaining  = @(Get-InstalledPrograms)
    $keepLocs   = @($remaining | ForEach-Object { Get-ProgramFolders $_ } | Select-Object -Unique)
    $keepNames  = @(@($remaining | ForEach-Object { Get-NameKey $_.Name }) + @($keepLocs | ForEach-Object { Get-NameKey (Split-Path $_ -Leaf) }) | Select-Object -Unique)
    $kindNames  = @{ Folder = 'folder'; Registry = 'registry'; Shortcut = 'shortcut'; Task = 'task' }
    $KindLabels = @{ Folder = 'Folder'; Registry = 'Registry key'; Shortcut = 'Shortcut'; Task = 'Scheduled task' }
    $leftItems = @()
    foreach ($r in $removed) {
        $found = @(Find-Leftovers $r.Program $keepLocs $keepNames ($r.Status -ne 'Orphan'))
        # An entry whose uninstaller is gone stays in Settings' list: offer its uninstall key (checked)
        if ($r.Status -eq 'Orphan' -and (Test-Path -LiteralPath $r.Program.Key)) {
            $found += [pscustomobject]@{ Kind = 'Registry'; Path = (Get-Item -LiteralPath $r.Program.Key).Name; Reason = 'entry left in the installed apps list'; Checked = $true; Sure = $true; Size = 0; Recyclable = $true }
        }
        foreach ($f in $found) {
            $leftItems += [pscustomobject]@{ Group = $r.Program.Name; Label = $f.Path; Checked = $f.Checked; Size = $f.Size; Leftover = $f
                                            Note = (@($kindNames[$f.Kind], $f.Reason, (Format-Size $f.Size)) | Where-Object { $_ }) -join ' · ' }
        }
    }

    if (-not $leftItems) {
        Write-Result 'OK' 'Nothing left behind'
    } else {
        $backup = Join-Path $env:ProgramData ("TidyWin\uninstall-backup\{0}" -f (Get-Date -Format 'yyyy-MM-dd HHmm'))
        if ($Answers) {
            # What is certainly theirs (and fits in the Recycle Bin) goes right away. The rest only might be
            # theirs, or would be deleted for good: listed for you to pick, nothing checked.
            $toDelete = @($leftItems | Where-Object { $_.Leftover.Sure -and $_.Leftover.Recyclable })
            $unsure = @($leftItems | Where-Object { $toDelete -notcontains $_ })
            if ($unsure) {
                foreach ($u in $unsure) { $u.Checked = $false }
                Write-Host "  $($unsure.Count) item(s) may be theirs: pick the ones to delete." -ForegroundColor DarkGray
                foreach ($u in $unsure) { $u.Note = (@($KindLabels[$u.Leftover.Kind], (Format-Size $u.Size)) | Where-Object { $_ }) -join ' • ' }
                $picked = @(Select-Items 'Leftovers to delete' $unsure -Short)
                $toDelete += $picked
                $kept = @($unsure | Where-Object { $picked -notcontains $_ })
                if ($kept) {
                    Write-Host '  Kept:' -ForegroundColor DarkGray
                    $kept | ForEach-Object { Write-Host "    - $($_.Label)" -ForegroundColor DarkGray }
                }
            }
            if ($toDelete) {
                Write-Step 'Deleting leftovers'
                Remove-Leftovers @($toDelete | ForEach-Object { $_.Leftover }) $backup
                Write-Host "  List of what was deleted, and the backups: $backup" -ForegroundColor DarkGray
                Write-Host '  To put a registry key back, double-click its .reg file. Folders: restore them from the Recycle Bin.' -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  $($leftItems.Count) item(s) found. Checked: certainly the program's. Unchecked: have its name; look before checking."
            [void](Read-Host '  Press Enter to see the list')
            $toDelete = @(Select-Items 'Uninstall-Apps — leftovers to delete (folders go to the Recycle Bin)' $leftItems)
            if (-not $toDelete) {
                Write-Host '  Nothing was deleted.'
            } else {
                Write-Host "`n  $($toDelete.Count) item(s) to delete:"
                $toDelete | ForEach-Object { Write-Host "    - $($_.Label)" -ForegroundColor DarkGray }
                Write-Host "  Folders and shortcuts go to the Recycle Bin. Registry keys and tasks are backed up first to:`n    $backup" -ForegroundColor DarkGray
                if ($toDelete | Where-Object { -not $_.Leftover.Recyclable }) {
                    Write-Host '  Items that don''t fit in the Recycle Bin will each ask again before being deleted for good.' -ForegroundColor Yellow
                }
                if (Ask 'Delete them?' $false) {
                    Write-Step 'Deleting leftovers'
                    Remove-Leftovers @($toDelete | ForEach-Object { $_.Leftover }) $backup
                    Write-Host "  List of what was deleted, and the backups: $backup" -ForegroundColor DarkGray
                    Write-Host '  To put a registry key back, double-click its .reg file. Folders: restore them from the Recycle Bin.' -ForegroundColor DarkGray
                } else {
                    Write-Host '  Nothing was deleted.'
                }
            }
        }
    }
}

# --- Summary
Write-Step 'Summary'
foreach ($r in $results) {
    $text = switch ($r.Status) {
        'Removed' { 'uninstalled' }
        'Restart' { 'uninstalled, restart to finish' }
        'Orphan'  { 'uninstaller was missing' }
        'Kept'    { 'still installed' }
    }
    Write-Host "  $($r.Program.Name): $text"
}
if ($results.Status -contains 'Restart') { Write-Host "`nRestart the PC to finish." -ForegroundColor Yellow }
else { Write-Host "`nDone." -ForegroundColor Green }

#endregion
