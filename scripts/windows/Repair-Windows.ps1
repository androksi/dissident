#Requires -RunAsAdministrator
<#
    Repair-Windows.ps1 — checks and repairs Windows system files and the disk, with Windows' own tools

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Repair-Windows.ps1
    Add -Lang en or -Lang pt to skip the language question.

    Use it when Windows acts strange: errors opening Settings or the Start menu, updates that keep
    failing, apps from Windows crashing. In order:
        1. Restore point ........ before anything
        2. Windows image ........ checks the component store (DISM) and, if it is damaged, repairs it
                                  with clean copies from Windows Update
        3. System files ......... sfc /scannow: replaces damaged system files with the copies from step 2
        4. Disk ................. online check of C: (no restart). If errors show up, asks before
                                  scheduling the fix for the next restart (a few seconds)
    Only Microsoft's own repair tools. Does not delete your files, apps or settings, does not clean
    the registry, does not use /ResetBase. Takes 10 to 30 minutes; the PC can be used meanwhile.
    Leaves nothing behind. Safe to run more than once.

    FILE LAYOUT
        1. Helpers
        2. Steps
        3. Execution
#>

param(
    [ValidateSet('en', 'pt')]
    [string]$Lang
)

$ErrorActionPreference = 'Continue'


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning $(if ($Lang -eq 'pt') { 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).' } else { 'Run in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' })   # T is not defined yet
    return
}


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

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

# $Status is a language-independent key (OK / FIXED / WARN / ERROR) that picks the color; the tag shown is translated.
function Write-Result([ValidateSet('OK', 'FIXED', 'WARN', 'ERROR')][string]$Status, [string]$Text) {
    $color = @{ OK = 'Green'; FIXED = 'Green'; WARN = 'Yellow'; ERROR = 'Red' }[$Status]
    $label = @{ OK = 'OK'; FIXED = (T 'FIXED' 'CORRIGIDO'); WARN = (T 'WARNING' 'ATENÇÃO'); ERROR = (T 'ERROR' 'ERRO') }[$Status]
    Write-Host ("  [{0}] " -f $label) -ForegroundColor $color -NoNewline
    Write-Host $Text
}

function Test-PendingReboot {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

#endregion


#region ==================== 2. STEPS ====================

# Summary lines shown at the end, and a language-independent status per line for the final message:
# Ok = no problem, Fixed = repaired or fix scheduled (needs a restart), Issue = anything else.
$script:Summary = @()
$script:SummaryStatus = @()
function Add-Summary([string]$Text, [ValidateSet('Ok', 'Fixed', 'Issue')][string]$Status) {
    $script:Summary += $Text
    $script:SummaryStatus += $Status
}

function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description (T 'Before Repair-Windows' 'Antes do Repair-Windows') -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Result 'OK' (T 'restore point created' 'ponto de restauração criado')
        return $true
    } catch {
        Write-Result 'WARN' (T "could not create the restore point ($($_.Exception.Message.Trim()))" "não foi possível criar o ponto de restauração ($($_.Exception.Message.Trim()))")
        return (Ask (T 'Continue anyway? (the repairs only use Windows'' own tools)' 'Continuar mesmo assim? (os reparos só usam ferramentas do próprio Windows)') $false)
    }
}

# DISM through its PowerShell cmdlet: the result (Healthy / Repairable / NonRepairable) does not depend
# on the Windows language. ScanHealth only reads; RestoreHealth downloads clean copies from Windows Update.
function Repair-Image {
    Write-Host (T '  checking (a few minutes; the progress bar may stall for a while, that is normal)...' '  verificando (alguns minutos; a barra de progresso pode parar um tempo, é normal)...') -ForegroundColor DarkGray
    try { $scan = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop }
    catch { Write-Result 'ERROR' (T "the check failed: $($_.Exception.Message.Trim())" "a verificação falhou: $($_.Exception.Message.Trim())"); Add-Summary (T 'Windows image: check failed' 'Imagem do Windows: verificação falhou') 'Issue'; return }

    switch ("$($scan.ImageHealthState)") {
        'Healthy' {
            Write-Result 'OK' (T 'Windows image has no problems' 'imagem do Windows sem problemas')
            Add-Summary (T 'Windows image: OK' 'Imagem do Windows: OK') 'Ok'
        }
        'Repairable' {
            Write-Host (T '  problems found; repairing with copies from Windows Update...' '  problemas encontrados; reparando com cópias do Windows Update...') -ForegroundColor DarkGray
            try {
                $fix = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
                if ("$($fix.ImageHealthState)" -eq 'Healthy') {
                    Write-Result 'FIXED' (T 'Windows image repaired' 'imagem do Windows reparada')
                    Add-Summary (T 'Windows image: repaired' 'Imagem do Windows: reparada') 'Fixed'
                } else {
                    Write-Result 'WARN' (T "the repair finished, but the state is: $($fix.ImageHealthState)" "o reparo terminou, mas o estado é: $($fix.ImageHealthState)")
                    Add-Summary (T 'Windows image: repair incomplete' 'Imagem do Windows: reparo incompleto') 'Issue'
                }
            } catch {
                Write-Result 'ERROR' (T "the repair failed: $($_.Exception.Message.Trim()). Check the internet connection and Windows Update and try again." "o reparo falhou: $($_.Exception.Message.Trim()). Confira a internet e o Windows Update e tente de novo.")
                Add-Summary (T 'Windows image: repair failed' 'Imagem do Windows: reparo falhou') 'Issue'
            }
        }
        default {
            Write-Result 'ERROR' (T 'the Windows image is too damaged to repair from here. The way forward is "Fix problems using Windows Update" in Settings > System > Recovery, which reinstalls Windows keeping your files and apps.' 'a imagem do Windows está danificada demais para reparar por aqui. O caminho é "Corrigir problemas usando o Windows Update" em Configurações > Sistema > Recuperação, que reinstala o Windows mantendo arquivos e apps.')
            Add-Summary (T 'Windows image: not repairable from here' 'Imagem do Windows: não reparável por aqui') 'Issue'
        }
    }
}

# sfc prints in UTF-16, which Windows PowerShell shows with spaces between letters; the output
# encoding is switched while it runs. The final message is Windows' own, in its language.
# The result comes from the exit code and from the [SR] lines it writes in CBS.log (always in English).
function Repair-SystemFiles {
    Write-Host (T '  checking (about 10 minutes)...' '  verificando (uns 10 minutos)...') -ForegroundColor DarkGray
    $start = Get-Date
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $output = & sfc.exe /scannow 2>&1 | Where-Object { "$_".Trim() }
    } finally {
        [Console]::OutputEncoding = $previous
    }
    $output | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

    $log = "$env:SystemRoot\Logs\CBS\CBS.log"
    $sr = @()
    if (Test-Path $log) {
        $sr = @(Select-String -Path $log -Pattern '[SR]' -SimpleMatch -ErrorAction SilentlyContinue | ForEach-Object { $_.Line } | Where-Object {
            $_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})' -and [datetime]$Matches[1] -ge $start.AddSeconds(-5)
        })
    }
    $repaired = @($sr | Where-Object { $_ -match 'Repair complete|Repairing corrupted file' }).Count
    $failed   = @($sr | Where-Object { $_ -match 'Cannot repair' }).Count

    if ($failed) {
        Write-Result 'WARN' (T "$failed file(s) could not be repaired. Restart the PC and run the repair again." "$failed arquivo(s) não puderam ser reparados. Reinicie o PC e rode de novo.")
        Add-Summary (T 'System files: some not repaired' 'Arquivos do sistema: alguns não reparados') 'Issue'
    } elseif ($repaired) {
        Write-Result 'FIXED' (T 'damaged system files were replaced. Restart the PC.' 'arquivos do sistema danificados foram substituídos. Reinicie o PC.')
        Add-Summary (T 'System files: repaired' 'Arquivos do sistema: reparados') 'Fixed'
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Result 'OK' (T 'system files have no problems' 'arquivos do sistema sem problemas')
        Add-Summary (T 'System files: OK' 'Arquivos do sistema: OK') 'Ok'
    } else {
        Write-Result 'WARN' (T 'sfc did not finish normally; see the message above.' 'o sfc não terminou normalmente; veja a mensagem acima.')
        Add-Summary (T 'System files: check incomplete' 'Arquivos do sistema: verificação incompleta') 'Issue'
    }
}

# Online scan of the system drive: reads only, works while Windows runs. If errors show up, the fix
# (SpotFix) needs the drive offline, so it is only scheduled for the next restart if you agree.
function Repair-Disk {
    $letter = $env:SystemDrive.TrimEnd(':')
    Write-Host (T "  checking drive $($letter): (may take a few minutes)..." "  verificando o disco $($letter): (pode levar alguns minutos)...") -ForegroundColor DarkGray
    try { $result = "$(Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop)" }
    catch { Write-Result 'ERROR' (T "the check failed: $($_.Exception.Message.Trim())" "a verificação falhou: $($_.Exception.Message.Trim())"); Add-Summary (T 'Disk: check failed' 'Disco: verificação falhou') 'Issue'; return }

    if ($result -eq 'NoErrorsFound') {
        Write-Result 'OK' (T "drive $($letter): no errors" "disco $($letter): sem erros")
        Add-Summary (T 'Disk: OK' 'Disco: OK') 'Ok'
        return
    }
    Write-Result 'WARN' (T "errors were found on drive $($letter): ($result)" "foram encontrados erros no disco $($letter): ($result)")
    # SpotFixNeeded: quick fix at the next restart. Anything else: full offline check (can take a while at startup).
    $quick = $result -eq 'SpotFixNeeded'
    $how = if ($quick) { (T 'takes a few seconds at startup' 'leva poucos segundos na inicialização') } else { (T 'startup may take several minutes' 'a inicialização pode demorar vários minutos') }
    if (Ask (T "Schedule the fix for the next time the PC restarts? ($how)" "Agendar a correção para a próxima vez que o PC reiniciar? ($how)") $true) {
        try {
            if ($quick) { Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop | Out-Null }
            else        { Repair-Volume -DriveLetter $letter -OfflineScanAndFix -ErrorAction Stop | Out-Null }
            Write-Result 'OK' (T 'fix scheduled; restart the PC' 'correção agendada; reinicie o PC')
            Add-Summary (T 'Disk: fix scheduled for the next restart' 'Disco: correção agendada para o próximo reinício') 'Fixed'
        } catch {
            Write-Result 'ERROR' (T "could not schedule it: $($_.Exception.Message.Trim())" "não foi possível agendar: $($_.Exception.Message.Trim())")
            Add-Summary (T 'Disk: errors found, fix not scheduled' 'Disco: erros encontrados, correção não agendada') 'Issue'
        }
    } else {
        Add-Summary (T 'Disk: errors found, fix not scheduled' 'Disco: erros encontrados, correção não agendada') 'Issue'
    }
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Host "`nRepair-Windows" -ForegroundColor Green
Write-Host (T '  Checks and repairs the Windows image, the system files and the disk, with Windows'' own tools.' '  Verifica e repara a imagem do Windows, os arquivos do sistema e o disco, com as ferramentas do próprio Windows.')
Write-Host (T '  Takes 10 to 30 minutes. You can use the PC meanwhile; leave the window open.' '  Leva de 10 a 30 minutos. Dá para usar o PC enquanto isso; deixe a janela aberta.') -ForegroundColor DarkGray

if (Test-PendingReboot) {
    Write-Host ''
    Write-Result 'WARN' (T 'an update is waiting for the PC to restart; the repairs may fail until then.' 'há uma atualização esperando o PC reiniciar; os reparos podem falhar até lá.')
    if (-not (Ask (T 'Continue anyway? (restarting first is recommended)' 'Continuar mesmo assim? (o recomendado é reiniciar antes)') $false)) { Write-Host (T 'Nothing was done. Restart the PC and run again.' 'Nada foi feito. Reinicie o PC e rode de novo.'); return }
}
Write-Host ''
if (-not (Ask (T 'Start?' 'Começar?') $true)) { Write-Host (T 'Nothing was done.' 'Nada foi feito.'); return }

Write-Step (T '1/4 Restore point' '1/4 Ponto de restauração')
if (-not (New-RestorePoint)) { Write-Host (T 'Nothing was done.' 'Nada foi feito.'); return }

Write-Step (T '2/4 Windows image (DISM)' '2/4 Imagem do Windows (DISM)')
Repair-Image

Write-Step (T '3/4 System files (sfc)' '3/4 Arquivos do sistema (sfc)')
Repair-SystemFiles

Write-Step (T '4/4 Disk' '4/4 Disco')
Repair-Disk

Write-Step (T 'Summary' 'Resumo')
$script:Summary | ForEach-Object { Write-Host "  $_" }
$allOk = -not ($script:SummaryStatus | Where-Object { $_ -ne 'Ok' })
if ($allOk) { Write-Host (T "`nNo problems found." "`nNenhum problema encontrado.") -ForegroundColor Green }
elseif ($script:SummaryStatus -contains 'Fixed') { Write-Host (T "`nRestart the computer to finish." "`nReinicie o computador para concluir.") -ForegroundColor Yellow }
else { Write-Host (T "`nSome items were not resolved; see the messages above." "`nAlguns itens não foram resolvidos; veja as mensagens acima.") -ForegroundColor Yellow }

#endregion
