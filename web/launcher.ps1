# TidyWin launcher
#   irm __BASE__/__NAME__ | iex
#
# Template: web/launcher.ps1. The Pages workflow replaces the __...__ placeholders and publishes it
# as "run". Your terminal shows the logo and waits; a hidden PowerShell as administrator downloads the
# panel (scripts/TidyWin.ps1) and runs it. When the panel closes, the terminal says goodbye. ASCII and no BOM on purpose:
# a BOM breaks "irm | iex".

& {
    $Name   = '__NAME__'      # shortcut name (last part of the URL)
    $Script = '__SCRIPT__'    # script path on the site, same as in the repository
    $Extra  = '__ARGS__'      # extra argument for the script (e.g. -Revert) or empty
    $Base   = '__BASE__'      # GitHub Pages site address

    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $hidden = [bool](Get-Variable -Name TidyWinElevated -ValueOnly -ErrorAction SilentlyContinue)

    # --- From your terminal: the logo, then the hidden administrator process that runs this same shortcut.
    # This terminal waits for the panel and says goodbye when it closes.
    if (-not $hidden) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        $os = try {
            $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            # $product, not $name: PowerShell ignores case, and $Name is the shortcut this terminal starts
            $product = "$($cv.ProductName)"
            if ([int]$cv.CurrentBuild -ge 22000) { $product = $product -replace 'Windows 10', 'Windows 11' }   # 11 still says 10 there
            "$product $($cv.DisplayVersion) (build $($cv.CurrentBuild).$($cv.UBR))"
        } catch { 'Windows' }
        Clear-Host
        Write-Host ''
        Write-Host @'
  _____ _     _       __        ___
 |_   _(_) __| |_   _ \ \      / (_)_ __
   | | | |/ _` | | | | \ \ /\ / /| | '_ \
   | | | | (_| | |_| |  \ V  V / | | | | |
   |_| |_|\__,_|\__, |   \_/\_/  |_|_| |_|
                |___/
'@ -ForegroundColor Cyan
        Write-Host "  $os" -ForegroundColor Gray
        Write-Host "  $Base" -ForegroundColor DarkGray
        Write-Host ''
        if (-not $isAdmin) { Write-Host '  Allow the administrator prompt to open the panel.' -ForegroundColor DarkYellow }
        Write-Host '  The panel opens in its own window. Close it to come back here.' -ForegroundColor DarkGray
        # The administrator copy writes what happens to a log: if it ends right away, this terminal shows it
        $log = Join-Path $env:TEMP 'tidywin-launch.log'
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
        $cmd = "Start-Transcript -LiteralPath '$log' -Force | Out-Null; `$TidyWinElevated = `$true; irm '$Base/$Name' | iex"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $start = @{
            FilePath     = 'powershell.exe'
            WindowStyle  = 'Hidden'
            ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-EncodedCommand', $encoded)
            PassThru     = $true
        }
        if (-not $isAdmin) { $start.Verb = 'RunAs' }
        try { $proc = Start-Process @start }
        catch { Write-Host "`n  Permission denied. Nothing was changed." -ForegroundColor Red; return }
        # Waits by its id, not with -Wait: -Wait puts the elevated process in a job object, which can end it
        $started = Get-Date
        while (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }
        if (((Get-Date) - $started).TotalSeconds -lt 15) {
            Write-Host "`n  The panel closed right away. What happened:" -ForegroundColor Yellow
            if (Test-Path -LiteralPath $log) {
                # The transcript after its header (the block between the first two lines of asterisks)
                $lines = @(Get-Content -LiteralPath $log)
                $marks = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^[*]{5,}') { $i } })
                $from = if ($marks.Count -ge 2) { $marks[1] + 1 } else { 0 }
                $lines | Select-Object -Skip $from | Where-Object { $_ -and $_ -notmatch '^[*]{5,}' } |
                    Select-Object -Last 30 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            } else {
                Write-Host '  Nothing was written: the administrator PowerShell did not run the launcher.' -ForegroundColor Gray
            }
        }
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
        Write-Host "`n  Cya!`n" -ForegroundColor Cyan
        return
    }

    # --- Hidden, as administrator: errors show in a message box, since there is no console to read
    function Show-Error([string]$Text) {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show($Text, 'TidyWin', 'OK', 'Error')
    }

    # --- Download the script to a temp folder (bytes as-is: keeps the BOM that 5.1 needs)
    $temp = Join-Path $env:TEMP 'tidywin'
    $file = Join-Path $temp (Split-Path $Script -Leaf)
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Invoke-WebRequest -Uri "$Base/$Script" -OutFile $file -UseBasicParsing
    } catch {
        Show-Error "Could not download TidyWin from $Base/$Script`n`n$($_.Exception.Message)"
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    # --- Run it in Windows PowerShell 5.1 (the scripts target it), with Bypass only for this process
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$file`"")
    if ($Extra) { $argv += $Extra }
    # Its errors go to a file: when it stops with one, show it (PowerShell may write it as CLIXML).
    # Waits for the panel itself, not for its output to end: a program the scripts started (an app an
    # installer opened) can keep that output open long after the panel closed.
    $errFile = Join-Path $temp 'errors.txt'
    $panel = Start-Process powershell.exe -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardError $errFile
    $null = $panel.Handle          # keeps the process handle, or ExitCode comes back empty
    $panel.WaitForExit()
    $errors = try { [IO.File]::ReadAllText($errFile) } catch { '' }
    if ($panel.ExitCode -ne 0 -and $errors.Trim()) {
        if ($errors -match '<S S="Error">') {
            $errors = (([regex]::Matches($errors, '<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value }) -join '') -replace '_x000D__x000A_', "`n"
        }
        Show-Error "TidyWin stopped with an error:`n`n$($errors.Trim())"
    }
    # --- Clean up: nothing stays on the PC besides what the scripts configured
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
