#Requires -RunAsAdministrator
<#
    TidyWin.ps1 — the TidyWin menu: pick what to do and the matching script runs

    HOW TO RUN:
        irm androksi.github.io/tidywin/run | iex          (the launcher asks for administrator rights)
    or from a copy of the repository (Windows PowerShell 5.1 as Administrator):
        powershell -ExecutionPolicy Bypass -File .\scripts\TidyWin.ps1

    Asks for the language once and passes it on (-Lang), so the scripts don't ask again.
    Each choice downloads its script from the site (or uses the local copy next to this file, when there
    is one), runs it, and comes back to the menu. Esc closes it.
    Every script asks before changing anything.

    To add an option: one line in $Menu (section 2), with the same name the site uses (web/index.html).

    FILE LAYOUT
        1. Helpers
        2. Menu items
        3. Menu screen
        4. Execution
#>
param(
    [ValidateSet('en', 'pt')]
    [string]$Lang,
    [string]$Base = 'https://androksi.github.io/tidywin'      # where the scripts are published (GitHub Pages)
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'    # the progress bar makes downloads slow on PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

# Language menu (the only question this script asks): ↑ ↓ and Enter, or a number without a real console.
function Select-Language {
    $options = @('English', 'Português (Brasil)')
    Write-Host '  Language / Idioma:'
    if (($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected) {
        Write-Host '    1) English'; Write-Host '    2) Português (Brasil)'
        return @('en', 'pt')[[int]("$(Read-Host '  Number / Número [1]')".Trim() -eq '2')]
    }
    Write-Host '  (↑ ↓ Enter)' -ForegroundColor DarkGray
    foreach ($o in $options) { Write-Host '' }
    $top = [Console]::CursorTop - $options.Count
    $sel = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $options.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                $line = $(if ($i -eq $sel) { '  > ' } else { '    ' }) + $options[$i]
                if ($i -eq $sel) { Write-Host $line.PadRight([Console]::WindowWidth - 1) -ForegroundColor Cyan -NoNewline } else { Write-Host $line.PadRight([Console]::WindowWidth - 1) -NoNewline }
            }
            $key = [Console]::ReadKey($true).Key
            if ($key -in 'UpArrow', 'DownArrow') { $sel = 1 - $sel }
            elseif ($key -eq 'Enter') { break }
        }
    } finally {
        [Console]::SetCursorPosition(0, $top + $options.Count)
        [Console]::CursorVisible = $true
    }
    return @('en', 'pt')[$sel]
}

# Windows name and version for the menu header.
function Get-WindowsLabel {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $name = "$($cv.ProductName)" -replace '^Microsoft\s+', ''
    if ([int]$cv.CurrentBuild -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }   # Windows 11 still says 10 here
    return "$name $($cv.DisplayVersion)".Trim()
}

# Splits a description into lines that fit the window (the menu shows two at most).
function Split-Text([string]$Text, [int]$Width) {
    $lines = @(); $line = ''
    foreach ($word in ($Text -split '\s+')) {
        if (($line.Length + $word.Length + 1) -gt $Width -and $line) { $lines += $line; $line = $word }
        else { $line = ("$line $word").Trim() }
    }
    if ($line) { $lines += $line }
    return $lines
}

#endregion


#region ==================== 2. MENU ITEMS ====================

# One script to run: path under scripts/, arguments, and a name (shown when an option has several steps).
function New-Step($Script, $ScriptArgs, $Name) {
    [pscustomobject]@{ Script = $Script; Args = @($ScriptArgs | Where-Object { $_ }); Name = $Name }
}

# Group, Id (the name used on the site), Script (path under scripts/), Args, Name and Desc in both languages.
function New-MenuItem($Group, $Id, $Script, $ScriptArgs, $Name, $Desc) {
    [pscustomobject]@{ Group = $Group; Id = $Id; Steps = @(New-Step $Script $ScriptArgs ''); Name = $Name; Desc = $Desc }
}

# An option that runs several scripts in order (each one can be skipped).
function New-MenuSequence($Group, $Id, [object[]]$Steps, $Name, $Desc) {
    [pscustomobject]@{ Group = $Group; Id = $Id; Steps = $Steps; Name = $Name; Desc = $Desc }
}

function Get-Menu {
    $setup = T 'Set up' 'Configurar'; $care = T 'Maintenance' 'Manutenção'; $format = T 'Formatting the PC' 'Formatar o PC'; $undo = T 'Undo' 'Desfazer'
    @(
        New-MenuItem $setup  'windows'        'windows/Configure-Windows.ps1'        $null      (T 'Windows' 'Windows')                       (T 'Turns off telemetry, ads and suggestions, removes preinstalled apps and OneDrive, adjusts the taskbar, File Explorer, power and DNS. Asks before each change and creates a restore point.' 'Desliga telemetria, anúncios e sugestões, remove apps pré-instalados e o OneDrive, ajusta a barra de tarefas, o Explorador, a energia e o DNS. Pergunta antes de cada mudança e cria um ponto de restauração.')
        New-MenuItem $setup  'apps'           'apps/Configure-Apps.ps1'              $null      (T 'Install apps' 'Instalar apps')            (T 'Pick from 104 apps (browsers, games, development, utilities...) and install them with WinGet.' 'Escolha entre 104 apps (navegadores, jogos, programação, utilitários...) e instale com o WinGet.')
        New-MenuItem $setup  'fonts'          'fonts/Install-Fonts.ps1'              $null      (T 'Install fonts' 'Instalar fontes')         (T 'Fonts for code (JetBrains Mono, Fira Code...), for the terminal with icons (Nerd Fonts) and for text (Inter, Roboto...).' 'Fontes para código (JetBrains Mono, Fira Code...), para o terminal com ícones (Nerd Fonts) e para texto (Inter, Roboto...).')
        New-MenuItem $setup  'chrome'         'browsers/Configure-Chrome.ps1'        $null      'Chrome'                                     (T 'Privacy: turns off telemetry, Gemini and other AI features, third-party cookies and background mode. Google sign-in keeps working.' 'Privacidade: desliga telemetria, Gemini e outros recursos de IA, cookies de terceiros e o segundo plano. O login do Google continua funcionando.')
        New-MenuItem $setup  'brave'          'browsers/Configure-Brave.ps1'         $null      'Brave'                                      (T 'Turns off Wallet, VPN, Rewards, Leo (AI), News and usage reports. Ad blocking stays on.' 'Desliga Wallet, VPN, Recompensas, Leo (IA), News e relatórios de uso. O bloqueio de anúncios continua ligado.')
        New-MenuItem $setup  'firefox'        'browsers/Configure-Firefox.ps1'       $null      'Firefox'                                    (T 'Turns off telemetry, sponsored content and AI features, and installs uBlock Origin and Bitwarden.' 'Desliga telemetria, conteúdo patrocinado e recursos de IA, e instala o uBlock Origin e o Bitwarden.')
        New-MenuItem $setup  'dev'            'dev/Configure-Dev.ps1'                $null      (T 'Development' 'Programação')               (T 'Editors, Git, SSH key sent to GitHub, signed commits, Windows Terminal with a Nerd Font, languages and WSL.' 'Editores, Git, chave SSH enviada ao GitHub, commits assinados, Windows Terminal com Nerd Font, linguagens e WSL.')
        New-MenuItem $setup  'wallpapers'     'wallpapers/Get-Wallpapers.ps1'        $null      (T 'Wallpapers' 'Papéis de parede')           (T 'Pick wallpapers from the TidyWin collection and download them; can set one as the background.' 'Escolha papéis de parede da coleção do TidyWin e baixe; pode definir um como fundo.')

        New-MenuItem $care   'report'         'windows/Get-Report.ps1'               $null      (T 'PC report' 'Relatório do PC')             (T 'Only reads: activation, TPM and Secure Boot, disks, battery, drivers and crashes, in a page that opens in the browser. Good to send when asking for help.' 'Só lê: ativação, TPM e Secure Boot, discos, bateria, drivers e travamentos, numa página que abre no navegador. Bom para mandar ao pedir ajuda.')
        New-MenuItem $care   'windows-check'  'windows/Configure-Windows.ps1'        '-Check'   (T 'Check after a Windows update' 'Conferir após atualização do Windows') (T 'Finds what a big Windows update brought back (telemetry, removed apps, OneDrive...) and offers to reapply only that.' 'Encontra o que uma atualização grande do Windows trouxe de volta (telemetria, apps removidos, OneDrive...) e oferece reaplicar só isso.')
        New-MenuItem $care   'uninstall'      'apps/Uninstall-Apps.ps1'              $null      (T 'Uninstall programs' 'Desinstalar programas')  (T 'Uninstalls the programs you pick with their official uninstaller, then shows the leftovers and deletes only what you confirm, with a backup.' 'Desinstala os programas que você escolher com o desinstalador oficial e depois mostra os resquícios, apagando só o que você confirmar, com backup.')
        New-MenuItem $care   'cleanup'        'windows/Clean-Windows.ps1'            $null      (T 'Free up disk space' 'Liberar espaço')      (T 'Temporary files, Windows Update downloads, error reports and more. Shows the size of each and asks before deleting.' 'Arquivos temporários, downloads do Windows Update, relatórios de erro e mais. Mostra o tamanho de cada um e pergunta antes de apagar.')
        New-MenuItem $care   'repair'         'windows/Repair-Windows.ps1'           $null      (T 'Repair Windows' 'Reparar o Windows')      (T 'For when Windows acts strange: checks and repairs the system files and the disk with Windows'' own tools (DISM, sfc). 10 to 30 minutes.' 'Para quando o Windows estiver estranho: verifica e repara os arquivos do sistema e o disco com as ferramentas do próprio Windows (DISM, sfc). De 10 a 30 minutos.')
        New-MenuItem $care   'network-reset'  'windows/Reset-Network.ps1'            $null      (T 'Reset the network' 'Redefinir a rede')    (T 'For "connected, no internet" or sites that don''t open. Quick or full, keeping your DNS.' 'Para "conectado, sem internet" ou sites que não abrem. Rápido ou completo, mantendo seu DNS.')

        # Backup: apps, then drivers. Restore: drivers first (network, video), then the apps, which need the internet.
        $apps    = T 'App list' 'Lista de apps'
        $drivers = T 'Drivers' 'Drivers'
        New-MenuSequence $format 'backup' @((New-Step 'apps/Backup-Apps.ps1' '-Export' $apps), (New-Step 'drivers/Backup-Drivers.ps1' '-Export' $drivers)) (T 'Back up apps and drivers' 'Fazer backup de apps e drivers') (T 'Before formatting: saves the list of installed apps and the drivers you pick, one after the other (each can be skipped). Keep them on a USB drive.' 'Antes de formatar: salva a lista de apps instalados e os drivers que você escolher, um depois do outro (dá para pular qualquer um). Guarde num pendrive.')
        New-MenuSequence $format 'restore' @((New-Step 'drivers/Backup-Drivers.ps1' '-Import' $drivers), (New-Step 'apps/Backup-Apps.ps1' '-Import' $apps)) (T 'Restore apps and drivers' 'Restaurar apps e drivers') (T 'After formatting and Windows Update: installs the saved drivers Windows didn''t bring back, then the saved apps (each can be skipped).' 'Depois de formatar e do Windows Update: instala os drivers salvos que o Windows não trouxe de volta e depois os apps salvos (dá para pular qualquer um).')

        New-MenuItem $undo   'windows-revert' 'windows/Revert-Configure-Windows.ps1' $null      'Windows'                                    (T 'Undoes most of what Windows changed: telemetry, policies, suggestions, DNS. Removed apps come back from the Microsoft Store.' 'Desfaz a maior parte do que o Windows mudou: telemetria, políticas, sugestões, DNS. Apps removidos voltam pela Microsoft Store.')
        New-MenuItem $undo   'chrome-revert'  'browsers/Configure-Chrome.ps1'        '-Revert'  'Chrome'                                     (T 'Removes every Chrome setting applied by TidyWin.' 'Remove todas as configurações do Chrome aplicadas pelo TidyWin.')
        New-MenuItem $undo   'brave-revert'   'browsers/Configure-Brave.ps1'         '-Revert'  'Brave'                                      (T 'Removes every Brave setting applied by TidyWin.' 'Remove todas as configurações do Brave aplicadas pelo TidyWin.')
        New-MenuItem $undo   'firefox-revert' 'browsers/Configure-Firefox.ps1'       '-Revert'  'Firefox'                                    (T 'Removes every Firefox setting applied by TidyWin.' 'Remove todas as configurações do Firefox aplicadas pelo TidyWin.')
        New-MenuItem $undo   'dev-revert'     'dev/Configure-Dev.ps1'                '-Revert'  (T 'Development' 'Programação')               (T 'Undoes the Windows settings changed by Development: Developer Mode, default terminal, Windows Terminal settings. Apps, Git and SSH keys stay.' 'Desfaz os ajustes do Windows feitos por Programação: Modo de Desenvolvedor, terminal padrão, configurações do Windows Terminal. Apps, Git e chaves SSH ficam.')
        New-MenuItem $undo   'fonts-revert'   'fonts/Install-Fonts.ps1'              '-Revert'  (T 'Fonts' 'Fontes')                          (T 'Removes the fonts TidyWin installed. Fonts installed some other way stay.' 'Remove as fontes que o TidyWin instalou. Fontes instaladas de outro jeito ficam.')
    )
}

#endregion


#region ==================== 3. MENU SCREEN ====================

# Full-screen menu with group headers and scrolling; the description of the selected item at the bottom.
# ↑ ↓ PgUp PgDn Home End move, Enter runs, Esc quits. Returns the item, or $null on Esc.
# $Start: index of the item selected when it opens (the last one run).
function Show-Menu([object[]]$Items, [int]$Start, [string]$Header) {
    $rows = New-Object System.Collections.Generic.List[object]
    $last = $null
    foreach ($it in $Items) {
        if ($it.Group -ne $last) { if ($rows.Count) { $rows.Add([pscustomobject]@{ Kind = 'Gap' }) }; $rows.Add([pscustomobject]@{ Kind = 'Header'; Text = $it.Group }); $last = $it.Group }
        $rows.Add([pscustomobject]@{ Kind = 'Item'; Item = $it })
    }
    $itemRows = @(for ($r = 0; $r -lt $rows.Count; $r++) { if ($rows[$r].Kind -eq 'Item') { $r } })
    $cursor = [Math]::Max(0, [Math]::Min($Start, $itemRows.Count - 1)); $scroll = 0; $lastSize = ''
    $nameWidth = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            if ("$width x $height" -ne $lastSize) { Clear-Host; $lastSize = "$width x $height" }
            $viewport = [Math]::Max(5, $height - 8)    # 3 header lines, 4 for the description and keys, last line left empty

            $row = $itemRows[$cursor]
            $wanted = if ($row -gt 0 -and $rows[$row - 1].Kind -eq 'Header') { $row - 1 } else { $row }
            if ($cursor -eq 0) { $wanted = 0 }
            if ($wanted -lt $scroll) { $scroll = $wanted }
            if ($row -ge $scroll + $viewport) { $scroll = $row - $viewport + 1 }

            $line = { param($text, $color) Write-Host ($text.PadRight($width - 1).Substring(0, $width - 1)) -ForegroundColor $color }
            [Console]::SetCursorPosition(0, 0)
            & $line "  TidyWin" 'Green'
            & $line "  $Header" 'DarkGray'
            & $line '' 'Gray'
            for ($v = 0; $v -lt $viewport; $v++) {
                $r = $scroll + $v
                if ($r -ge $rows.Count -or $rows[$r].Kind -eq 'Gap') { & $line '' 'Gray'; continue }
                if ($rows[$r].Kind -eq 'Header') { & $line "  $($rows[$r].Text)" 'Yellow'; continue }
                $selected = $r -eq $row
                $marker = if ($selected) { '  > ' } else { '    ' }
                & $line "$marker$($rows[$r].Item.Name)" $(if ($selected) { 'Cyan' } else { 'Gray' })
            }

            # Description of the selected item (two lines at most), then the keys
            $desc = @(Split-Text $rows[$row].Item.Desc ($width - 5))
            & $line '' 'Gray'
            & $line "  $(if ($desc.Count -gt 0) { $desc[0] })" 'White'
            & $line "  $(if ($desc.Count -gt 1) { $desc[1] + $(if ($desc.Count -gt 2) { '…' }) })" 'White'
            & $line (T '  ↑ ↓ choose   Enter run   Esc quit' '  ↑ ↓ escolher   Enter executar   Esc sair') 'DarkGray'

            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cursor = [Math]::Max(0, $cursor - 1) }
                'DownArrow' { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 1) }
                'PageUp'    { $cursor = [Math]::Max(0, $cursor - 5) }
                'PageDown'  { $cursor = [Math]::Min($itemRows.Count - 1, $cursor + 5) }
                'Home'      { $cursor = 0 }
                'End'       { $cursor = $itemRows.Count - 1 }
                'Enter'     { return @{ Item = $rows[$row].Item; Index = $cursor } }
                'Escape'    { return $null }
            }
        }
    } finally {
        Clear-Host
        [Console]::CursorVisible = $true
    }
}

# Without a real console (e.g. PowerShell ISE): numbered list.
function Show-MenuPlain([object[]]$Items) {
    $last = $null
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Group -ne $last) { Write-Host "`n  $($Items[$i].Group)" -ForegroundColor Yellow; $last = $Items[$i].Group }
        Write-Host ("    {0,2}) {1}" -f ($i + 1), $Items[$i].Name)
    }
    $answer = "$(Read-Host (T "`n  Number (Enter quits)" "`n  Número (Enter sai)"))".Trim()
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) { return @{ Item = $Items[$n - 1]; Index = $n - 1 } }
    return $null
}

# Runs one script: the local copy next to this file when there is one (a copy of the repository),
# otherwise downloaded from the site to this script's folder (the launcher deletes it afterwards).
function Invoke-Step($Step) {
    $file = Join-Path $PSScriptRoot $Step.Script
    if (-not (Test-Path -LiteralPath $file)) {
        $file = Join-Path $PSScriptRoot (Split-Path $Step.Script -Leaf)
        Write-Host (T "  downloading $($Step.Script)..." "  baixando $($Step.Script)...") -ForegroundColor DarkGray
        try { Invoke-WebRequest "$Base/scripts/$($Step.Script)" -OutFile $file -UseBasicParsing -ErrorAction Stop }
        catch {
            Write-Host (T "  Could not download it: $($_.Exception.Message)" "  Não foi possível baixar: $($_.Exception.Message)") -ForegroundColor Red
            return
        }
    }
    # A separate Windows PowerShell 5.1 process: the scripts expect a fresh session, and the menu survives their "return"s
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file, '-Lang', $script:Lang) + $Step.Args
    & powershell.exe @argv
}

# Enter = run the step, Esc = skip it. Without a real console: Enter or "s".
function Confirm-Step([string]$Text) {
    if (($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected) {
        return "$(Read-Host (T "  $Text — Enter runs, S skips" "  $Text — Enter executa, P pula"))".Trim() -notmatch '^[sSpP]'
    }
    Write-Host (T "  $Text — Enter runs, Esc skips" "  $Text — Enter executa, Esc pula") -ForegroundColor Cyan
    while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    while ($true) {
        $key = [Console]::ReadKey($true).Key
        if ($key -eq 'Enter')  { return $true }
        if ($key -eq 'Escape') { return $false }
    }
}

# An option with one script runs it; one with several runs them in order, asking before each.
function Invoke-MenuItem($Item) {
    $steps = @($Item.Steps)
    if ($steps.Count -eq 1) { Invoke-Step $steps[0]; return }
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Write-Host "`n-- $(T 'Step' 'Passo') $($i + 1)/$($steps.Count): $($steps[$i].Name)" -ForegroundColor Green
        if (Confirm-Step $steps[$i].Name) { Invoke-Step $steps[$i] }
        else { Write-Host (T '  skipped' '  pulado') -ForegroundColor DarkGray }
    }
}

#endregion


#region ==================== 4. EXECUTION ====================

if (-not $Lang) { $Lang = Select-Language }
$script:Lang = $Lang

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning (T 'Run it in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).')
    return
}

$menu = @(Get-Menu)
$header = "$(Get-WindowsLabel) · $(T 'every option asks before changing anything' 'toda opção pergunta antes de mudar qualquer coisa')"
$plain = ($Host.Name -ne 'ConsoleHost') -or [Console]::IsInputRedirected
$index = 0
while ($true) {
    $choice = if ($plain) { Show-MenuPlain $menu } else { Show-Menu $menu $index $header }
    if (-not $choice) { break }
    $index = $choice.Index
    Write-Host "`n== $($choice.Item.Group) · $($choice.Item.Name)" -ForegroundColor Green
    Invoke-MenuItem $choice.Item
    Write-Host ''
    [void](Read-Host (T '  Press Enter to go back to the menu' '  Aperte Enter para voltar ao menu'))
}
Write-Host (T '  TidyWin closed.' '  TidyWin fechado.') -ForegroundColor DarkGray

#endregion
