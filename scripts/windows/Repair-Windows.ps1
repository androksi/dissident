#Requires -RunAsAdministrator
<#
    Repair-Windows.ps1 — checks and repairs Windows system files and the disk, with Windows' own tools

    HOW TO RUN (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\Repair-Windows.ps1

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

$ErrorActionPreference = 'Continue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).'
    return
}


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

function Write-Result([string]$Status, [string]$Text) {
    $color = @{ OK = 'Green'; CORRIGIDO = 'Green'; ATENÇÃO = 'Yellow'; ERRO = 'Red' }[$Status]
    Write-Host ("  [{0}] " -f $Status) -ForegroundColor $color -NoNewline
    Write-Host $Text
}

function Test-PendingReboot {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

#endregion


#region ==================== 2. STEPS ====================

$script:Summary = @()

function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Antes do Repair-Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Result 'OK' 'ponto de restauração criado'
        return $true
    } catch {
        Write-Result 'ATENÇÃO' "não foi possível criar o ponto de restauração ($($_.Exception.Message.Trim()))"
        return (Ask 'Continuar mesmo assim? (os reparos só usam ferramentas do próprio Windows)' $false)
    }
}

# DISM through its PowerShell cmdlet: the result (Healthy / Repairable / NonRepairable) does not depend
# on the Windows language. ScanHealth only reads; RestoreHealth downloads clean copies from Windows Update.
function Repair-Image {
    Write-Host '  verificando (alguns minutos; a barra de progresso pode parar um tempo, é normal)...' -ForegroundColor DarkGray
    try { $scan = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop }
    catch { Write-Result 'ERRO' "a verificação falhou: $($_.Exception.Message.Trim())"; $script:Summary += 'Imagem do Windows: verificação falhou'; return }

    switch ("$($scan.ImageHealthState)") {
        'Healthy' {
            Write-Result 'OK' 'imagem do Windows sem problemas'
            $script:Summary += 'Imagem do Windows: OK'
        }
        'Repairable' {
            Write-Host '  problemas encontrados; reparando com cópias do Windows Update...' -ForegroundColor DarkGray
            try {
                $fix = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop
                if ("$($fix.ImageHealthState)" -eq 'Healthy') {
                    Write-Result 'CORRIGIDO' 'imagem do Windows reparada'
                    $script:Summary += 'Imagem do Windows: reparada'
                } else {
                    Write-Result 'ATENÇÃO' "o reparo terminou, mas o estado é: $($fix.ImageHealthState)"
                    $script:Summary += 'Imagem do Windows: reparo incompleto'
                }
            } catch {
                Write-Result 'ERRO' "o reparo falhou: $($_.Exception.Message.Trim()). Confira a internet e o Windows Update e tente de novo."
                $script:Summary += 'Imagem do Windows: reparo falhou'
            }
        }
        default {
            Write-Result 'ERRO' 'a imagem do Windows está danificada demais para reparar por aqui. O caminho é "Corrigir problemas usando o Windows Update" em Configurações > Sistema > Recuperação, que reinstala o Windows mantendo arquivos e apps.'
            $script:Summary += 'Imagem do Windows: não reparável por aqui'
        }
    }
}

# sfc prints in UTF-16, which Windows PowerShell shows with spaces between letters; the output
# encoding is switched while it runs. The final message is Windows' own, in its language.
# The result comes from the exit code and from the [SR] lines it writes in CBS.log (always in English).
function Repair-SystemFiles {
    Write-Host '  verificando (uns 10 minutos)...' -ForegroundColor DarkGray
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
        Write-Result 'ATENÇÃO' "$failed arquivo(s) não puderam ser reparados. Reinicie o PC e rode o repair de novo."
        $script:Summary += 'Arquivos do sistema: alguns não reparados'
    } elseif ($repaired) {
        Write-Result 'CORRIGIDO' 'arquivos do sistema danificados foram substituídos. Reinicie o PC.'
        $script:Summary += 'Arquivos do sistema: reparados'
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Result 'OK' 'arquivos do sistema sem problemas'
        $script:Summary += 'Arquivos do sistema: OK'
    } else {
        Write-Result 'ATENÇÃO' 'o sfc não terminou normalmente; veja a mensagem acima.'
        $script:Summary += 'Arquivos do sistema: verificação incompleta'
    }
}

# Online scan of the system drive: reads only, works while Windows runs. If errors show up, the fix
# (SpotFix) needs the drive offline, so it is only scheduled for the next restart if you agree.
function Repair-Disk {
    $letter = $env:SystemDrive.TrimEnd(':')
    Write-Host "  verificando o disco $($letter): (pode levar alguns minutos)..." -ForegroundColor DarkGray
    try { $result = "$(Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop)" }
    catch { Write-Result 'ERRO' "a verificação falhou: $($_.Exception.Message.Trim())"; $script:Summary += 'Disco: verificação falhou'; return }

    if ($result -eq 'NoErrorsFound') {
        Write-Result 'OK' "disco $($letter): sem erros"
        $script:Summary += 'Disco: OK'
        return
    }
    Write-Result 'ATENÇÃO' "foram encontrados erros no disco $($letter): ($result)"
    # SpotFixNeeded: quick fix at the next restart. Anything else: full offline check (can take a while at startup).
    $quick = $result -eq 'SpotFixNeeded'
    $how = if ($quick) { 'leva poucos segundos na inicialização' } else { 'a inicialização pode demorar vários minutos' }
    if (Ask "Agendar a correção para a próxima vez que o PC reiniciar? ($how)" $true) {
        try {
            if ($quick) { Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction Stop | Out-Null }
            else        { Repair-Volume -DriveLetter $letter -OfflineScanAndFix -ErrorAction Stop | Out-Null }
            Write-Result 'OK' 'correção agendada; reinicie o PC'
            $script:Summary += 'Disco: correção agendada para o próximo reinício'
        } catch {
            Write-Result 'ERRO' "não foi possível agendar: $($_.Exception.Message.Trim())"
            $script:Summary += 'Disco: erros encontrados, correção não agendada'
        }
    } else {
        $script:Summary += 'Disco: erros encontrados, correção não agendada'
    }
}

#endregion


#region ==================== 3. EXECUTION ====================

Write-Host "`nRepair-Windows" -ForegroundColor Green
Write-Host '  Verifica e repara a imagem do Windows, os arquivos do sistema e o disco, com as ferramentas do próprio Windows.'
Write-Host '  Leva de 10 a 30 minutos. Dá para usar o PC enquanto isso; deixe a janela aberta.' -ForegroundColor DarkGray

if (Test-PendingReboot) {
    Write-Host ''
    Write-Result 'ATENÇÃO' 'há uma atualização esperando o PC reiniciar; os reparos podem falhar até lá.'
    if (-not (Ask 'Continuar mesmo assim? (o recomendado é reiniciar antes)' $false)) { Write-Host 'Nada foi feito. Reinicie o PC e rode de novo.'; return }
}
Write-Host ''
if (-not (Ask 'Começar?' $true)) { Write-Host 'Nada foi feito.'; return }

Write-Step '1/4 Ponto de restauração'
if (-not (New-RestorePoint)) { Write-Host 'Nada foi feito.'; return }

Write-Step '2/4 Imagem do Windows (DISM)'
Repair-Image

Write-Step '3/4 Arquivos do sistema (sfc)'
Repair-SystemFiles

Write-Step '4/4 Disco'
Repair-Disk

Write-Step 'Resumo'
$script:Summary | ForEach-Object { Write-Host "  $_" }
$allOk = -not ($script:Summary | Where-Object { $_ -notmatch ': OK$' })
if ($allOk) { Write-Host "`nNenhum problema encontrado." -ForegroundColor Green }
elseif ($script:Summary -match ': (reparada|reparados|correção agendada)') { Write-Host "`nReinicie o computador para concluir." -ForegroundColor Yellow }
else { Write-Host "`nAlguns itens não foram resolvidos; veja as mensagens acima." -ForegroundColor Yellow }

#endregion
