# TidyWin - shortcut "__NAME__"
#   irm __BASE__/__NAME__ | iex
#
# Template: web/launcher.ps1. The Pages workflow replaces the __...__ placeholders and publishes
# one of these files per shortcut. ASCII and no BOM on purpose: a BOM breaks "irm | iex".
# Messages are in English: the scripts ask for the language right after.

& {
    $Name   = '__NAME__'      # shortcut name (last part of the URL)
    $Script = '__SCRIPT__'    # script path on the site, same as in the repository
    $Extra  = '__ARGS__'      # extra argument for the script (e.g. -Revert) or empty
    $Base   = '__BASE__'      # GitHub Pages site address

    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $elevated = [bool](Get-Variable -Name TidyWinElevated -ValueOnly -ErrorAction SilentlyContinue)
    function Wait-Close { if ($elevated) { Read-Host "`nPress Enter to close" | Out-Null } }

    # --- Administrator: if not, open an elevated window that runs this same shortcut
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host 'TidyWin: requesting administrator rights...' -ForegroundColor DarkYellow
        $cmd = "`$TidyWinElevated = `$true; irm '$Base/$Name' | iex"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
        } catch {
            Write-Host 'TidyWin: permission denied. Nothing was changed.' -ForegroundColor Red
        }
        return
    }

    # --- Download the script to a temp folder (bytes as-is: keeps the BOM that 5.1 needs)
    $temp = Join-Path $env:TEMP 'tidywin'
    $file = Join-Path $temp (Split-Path $Script -Leaf)
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Write-Host "TidyWin: downloading $Script" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri "$Base/$Script" -OutFile $file -UseBasicParsing
    } catch {
        Write-Host "TidyWin: could not download $Base/$Script" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
        Wait-Close
        return
    }

    # --- Run it in Windows PowerShell 5.1 (the scripts target it), with Bypass only for this process
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file)
    if ($Extra) { $argv += $Extra }
    & powershell.exe @argv

    # --- Clean up: nothing stays on the PC besides what the script configured
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    Wait-Close
}
