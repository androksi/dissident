#Requires -RunAsAdministrator
<#
    Configure-Dev.ps1 — a ready-to-code Windows: editors, Git, SSH key, signed commits, terminal, fonts,
    languages and WSL

    HOW TO RUN (Windows PowerShell 5.1 as Administrator), after Windows, drivers and apps are set up:
        powershell -ExecutionPolicy Bypass -File .\Configure-Dev.ps1
    UNDO the Windows-level settings (Developer Mode, default terminal, Terminal settings):
        powershell -ExecutionPolicy Bypass -File .\Configure-Dev.ps1 -Revert

    How it works:
      - Every question comes first (arrow-key menus; defaults come selected), then a summary and a
        confirmation. Nothing changes before that.
      - Each step that fails is reported and the next one runs; the list of failures is shown at the end.
      - Safe to run again: what is already done is detected and skipped.
      - Never overwrites: an existing SSH key is reused, an existing Git name/e-mail is kept unless you
        change it, Windows Terminal settings get a backup before any change.
      - Everything shown on screen is also saved in %LOCALAPPDATA%\TidyWin\dev-<date>.log.

    FILE LAYOUT
        1. Helpers ............... menus, text input, steps, WinGet, Git
        2. Detection ............. what is already installed or configured
        3. Actions ............... one function per step
        4. Revert ................ -Revert
        5. Questions
        6. Summary and execution
#>
param(
    [switch]$Revert
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Warning 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).'
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


#region ==================== 1. HELPERS ====================

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Skip([string]$Text) { Write-Host "  [--] $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text) { Write-Host "  [ATENÇÃO] $Text" -ForegroundColor Yellow }

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

# Checklist: ↑ ↓ move, Space checks, Enter confirms. $Items: objects with Label, Checked, Note.
# Returns the checked items. Without a real console: numbers separated by commas.
function Select-Many([string]$Question, [object[]]$Items) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
            Write-Host "    $($i + 1)) $mark $($Items[$i].Label)  $($Items[$i].Note)"
        }
        $answer = "$(Read-Host '  Números separados por vírgula (Enter mantém os marcados)')".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }
    Write-Host '  (↑ ↓ navega, Espaço marca/desmarca, Enter confirma)' -ForegroundColor DarkGray
    foreach ($it in $Items) { Write-Host '' }
    $top = [Console]::CursorTop - $Items.Count
    $sel = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Items.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                $box  = if ($Items[$i].Checked) { '[x]' } else { '[ ]' }
                $mark = if ($i -eq $sel) { '  > ' } else { '    ' }
                $line = ("$mark$box $($Items[$i].Label)  $($Items[$i].Note)")
                $line = $line.Substring(0, [Math]::Min($line.Length, [Console]::WindowWidth - 1)).PadRight([Console]::WindowWidth - 1)
                if ($i -eq $sel) { Write-Host $line -ForegroundColor Cyan -NoNewline } else { Write-Host $line -NoNewline }
            }
            $key = [Console]::ReadKey($true).Key
            if     ($key -eq 'UpArrow')   { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            elseif ($key -eq 'DownArrow') { $sel = ($sel + 1) % $Items.Count }
            elseif ($key -eq 'Spacebar')  { $Items[$sel].Checked = -not $Items[$sel].Checked }
            elseif ($key -eq 'Enter')     { break }
        }
    } finally {
        [Console]::SetCursorPosition(0, $top + $Items.Count)
        [Console]::CursorVisible = $true
    }
    return @($Items | Where-Object Checked)
}

# Typed answer with an optional default (Enter keeps it) and an optional validation pattern.
function Read-Text([string]$Question, [string]$Default, [string]$Pattern, [string]$Hint) {
    while ($true) {
        $prompt = if ($Default) { "  $Question [$Default]" } else { "  $Question" }
        $answer = "$(Read-Host $prompt)".Trim()
        if (-not $answer) { $answer = $Default }
        if ($answer -and (-not $Pattern -or $answer -match $Pattern)) { return $answer }
        Write-Host "  $Hint" -ForegroundColor DarkYellow
    }
}

# Runs a step. If it fails, records it and moves on.
$script:Failures = @()
function Invoke-Step([string]$Title, [scriptblock]$Body) {
    Write-Step $Title
    try { & $Body }
    catch {
        $script:Failures += "${Title}: $($_.Exception.Message)"
        Write-Warning "Esta etapa falhou ($($_.Exception.Message)). Seguindo para a próxima."
    }
}

# New programs add themselves to PATH in the registry; this session only sees them after a reload.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Test-WingetInstalled([string]$Id) {
    & winget list --id $Id -e --accept-source-agreements 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

# Installs with WinGet unless it is already there. -Interactive opens the app's own installer.
function Install-App([string]$Name, [string]$Id, [switch]$Interactive) {
    if (Test-WingetInstalled $Id) { Write-Skip "$Name já está instalado"; return }
    Write-Host "  instalando $Name$(if ($Interactive) { ' (o instalador vai abrir: escolha as opções nele)' })..."
    $args2 = @('install', '--id', $Id, '-e', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
    if ($Interactive) { $args2 += '--interactive' } else { $args2 += '--silent' }
    & winget @args2
    if ($LASTEXITCODE -ne 0 -and -not (Test-WingetInstalled $Id)) { throw "$Name não foi instalado (WinGet código $LASTEXITCODE)" }
    Write-Ok "$Name instalado"
    Update-SessionPath
}

function Get-GitConfig([string]$Key) {
    $value = & git config --global --get $Key 2>$null
    if ($LASTEXITCODE -eq 0) { "$value".Trim() }
}

function Set-GitConfig([string]$Key, [string]$Value) {
    & git config --global $Key $Value
    if ($LASTEXITCODE -ne 0) { throw "git config $Key falhou" }
    Write-Ok "git $Key = $Value"
}

#endregion


#region ==================== 2. DETECTION ====================

$build      = [Environment]::OSVersion.Version.Build
$isWin11    = $build -ge 22000
$OpenSSH    = "$env:SystemRoot\System32\OpenSSH"
$KeyPath    = Join-Path $HOME '.ssh\id_ed25519'
$PubPath    = "$KeyPath.pub"
$WtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$PwshGuid   = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'     # Windows Terminal's built-in "PowerShell" (7) profile
$DevKey     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$ConsoleKey = 'HKCU:\Console\%%Startup'
$LogDir     = Join-Path $env:LOCALAPPDATA 'TidyWin'

function Test-Git        { [bool](Get-Command git -ErrorAction SilentlyContinue) }
function Test-Pwsh       { [bool](Get-Command pwsh -ErrorAction SilentlyContinue) -or (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") }
function Test-Terminal   { [bool](Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue) }
function Test-DevMode    { (Get-ItemProperty $DevKey -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1 }
function Test-Wsl {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    & wsl.exe --status 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}
function Test-Font([string]$Face) {
    foreach ($root in 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') {
        $props = (Get-ItemProperty $root -ErrorAction SilentlyContinue).PSObject.Properties.Name
        if ($props | Where-Object { $_ -like "$Face*" }) { return $true }
    }
    return $false
}

#endregion


#region ==================== 3. ACTIONS ====================

# Editors and languages: lists with WinGet IDs. Interactive = the app's own installer opens.
$Editors = @(
    [pscustomobject]@{ Label = 'VS Code';           Id = 'Microsoft.VisualStudioCode'; Interactive = $true;  Checked = $true;  Note = 'editor de código (instalador interativo: marque "Abrir com Code")' }
    [pscustomobject]@{ Label = 'Cursor';            Id = 'Anysphere.Cursor';           Interactive = $false; Checked = $false; Note = 'baseado no VS Code, com IA' }
    [pscustomobject]@{ Label = 'Zed';               Id = 'ZedIndustries.Zed';          Interactive = $false; Checked = $false; Note = 'editor muito rápido (open source)' }
    [pscustomobject]@{ Label = 'JetBrains Toolbox'; Id = 'JetBrains.Toolbox';          Interactive = $false; Checked = $false; Note = 'instala IntelliJ, PyCharm, WebStorm, Rider...' }
    [pscustomobject]@{ Label = 'Sublime Text';      Id = 'SublimeHQ.SublimeText.4';    Interactive = $false; Checked = $false; Note = 'editor leve' }
    [pscustomobject]@{ Label = 'Neovim';            Id = 'Neovim.Neovim';              Interactive = $false; Checked = $false; Note = 'editor no terminal (open source)' }
)
$Languages = @(
    [pscustomobject]@{ Label = 'Node.js LTS';       Id = 'OpenJS.NodeJS.LTS';              Checked = $false; Note = 'JavaScript/TypeScript' }
    [pscustomobject]@{ Label = 'Python 3.14';       Id = 'Python.Python.3.14';             Checked = $false; Note = '' }
    [pscustomobject]@{ Label = 'Go';                Id = 'GoLang.Go';                      Checked = $false; Note = '' }
    [pscustomobject]@{ Label = 'Rust (rustup)';     Id = 'Rustlang.Rustup';                Checked = $false; Note = 'precisa das ferramentas de build do Visual Studio; o rustup avisa' }
    [pscustomobject]@{ Label = 'Java 25 (Temurin)'; Id = 'EclipseAdoptium.Temurin.25.JDK'; Checked = $false; Note = '' }
    [pscustomobject]@{ Label = 'Bun';               Id = 'Oven-sh.Bun';                    Checked = $false; Note = 'runtime JavaScript' }
    [pscustomobject]@{ Label = 'Docker Desktop';    Id = 'Docker.DockerDesktop';           Checked = $false; Note = 'usa o WSL' }
)
$Fonts = @{
    'CaskaydiaCove' = @{ Zip = 'CascadiaCode';  Face = 'CaskaydiaCove Nerd Font' }
    'JetBrainsMono' = @{ Zip = 'JetBrainsMono'; Face = 'JetBrainsMono Nerd Font' }
}

function Install-Editors($List) {
    foreach ($e in $List) {
        try { Install-App $e.Label $e.Id -Interactive:$e.Interactive }
        catch { $script:Failures += "Editor $($e.Label): $($_.Exception.Message)"; Write-Warning $_.Exception.Message }
    }
}

function Install-Languages($List) {
    foreach ($l in $List) {
        try { Install-App $l.Label $l.Id }
        catch { $script:Failures += "Linguagem $($l.Label): $($_.Exception.Message)"; Write-Warning $_.Exception.Message }
    }
}

# --- Git ----------------------------------------------------------------------

function Set-GitBasics([string]$Name, [string]$Email, [bool]$PullRebase) {
    if (-not (Test-Git)) { throw 'o Git não está instalado' }
    if ($Name)  { Set-GitConfig 'user.name'  $Name }
    if ($Email) { Set-GitConfig 'user.email' $Email }
    Set-GitConfig 'init.defaultBranch' 'main'
    Set-GitConfig 'core.longpaths'     'true'     # paths over 260 characters (node_modules)
    Set-GitConfig 'core.autocrlf'      'true'     # Windows line endings in the files, LF in the repository
    Set-GitConfig 'fetch.prune'        'true'     # forget remote branches that were deleted
    Set-GitConfig 'pull.rebase'        $(if ($PullRebase) { 'true' } else { 'false' })
    if (-not (Get-GitConfig 'credential.helper')) { Set-GitConfig 'credential.helper' 'manager' }
}

# --- SSH ----------------------------------------------------------------------

# Windows' own OpenSSH (the agent runs as a Windows service). Installs it if it was removed.
function Enable-SshAgent {
    if (-not (Test-Path "$OpenSSH\ssh-keygen.exe")) {
        Write-Host '  instalando o cliente OpenSSH do Windows...'
        Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' -ErrorAction Stop | Out-Null
    }
    Set-Service ssh-agent -StartupType Automatic -ErrorAction Stop
    Start-Service ssh-agent -ErrorAction Stop
    Write-Ok 'ssh-agent ligado (inicia com o Windows)'
}

function New-SshKey([string]$Email, [bool]$Passphrase) {
    if (Test-Path $KeyPath) { Write-Skip "chave já existe, mantida: $KeyPath"; return }
    New-Item -ItemType Directory -Path (Split-Path $KeyPath) -Force | Out-Null
    $comment = if ($Email) { $Email } else { "$env:USERNAME@$env:COMPUTERNAME" }
    if ($Passphrase) {
        Write-Host '  digite a senha da chave duas vezes (ela não aparece enquanto você digita):'
        & "$OpenSSH\ssh-keygen.exe" -t ed25519 -C $comment -f $KeyPath
    } else {
        & "$OpenSSH\ssh-keygen.exe" -t ed25519 -C $comment -f $KeyPath -N '""' -q   # '""' = empty passphrase in Windows PowerShell
    }
    if (-not (Test-Path $PubPath)) { throw 'a chave não foi criada' }
    Write-Ok "chave criada: $KeyPath"
}

function Add-KeyToAgent {
    $fingerprint = ((& "$OpenSSH\ssh-keygen.exe" -lf $PubPath) -split ' ')[1]
    $loaded = & "$OpenSSH\ssh-add.exe" -l 2>$null
    if ($loaded -match [regex]::Escape($fingerprint)) { Write-Skip 'chave já está no ssh-agent'; return }
    Write-Host '  adicionando a chave ao ssh-agent (se ela tiver senha, digite agora; é só desta vez)...'
    & "$OpenSSH\ssh-add.exe" $KeyPath
    if ($LASTEXITCODE -ne 0) { throw 'ssh-add falhou' }
    Write-Ok 'chave no ssh-agent'
}

# Git for Windows has its own ssh, which can't see the Windows agent. Point Git to Windows' OpenSSH.
function Set-GitUseWindowsSsh {
    if (-not (Test-Git)) { throw 'o Git não está instalado' }
    Set-GitConfig 'core.sshCommand' "$($OpenSSH -replace '\\', '/')/ssh.exe"
}

# --- GitHub ------------------------------------------------------------------

# Signs in to GitHub CLI (in the browser) with permission to add SSH keys, then adds the key for
# authentication and, if chosen, for signing. A key that is already there counts as done.
function Publish-KeyWithGh([bool]$Signing) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'o GitHub CLI não está instalado' }
    $scopes = 'admin:public_key' + $(if ($Signing) { ',admin:ssh_signing_key' } else { '' })
    & gh auth status --hostname github.com 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  entrando no GitHub (o navegador vai abrir; copie o código que aparecer aqui)...'
        & gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key --scopes $scopes
    } else {
        Write-Host '  pedindo permissão para adicionar chaves (o navegador pode abrir)...'
        & gh auth refresh --hostname github.com --scopes $scopes
    }
    if ($LASTEXITCODE -ne 0) { throw 'não foi possível entrar no GitHub pelo GitHub CLI' }

    $title = "$env:COMPUTERNAME (TidyWin)"
    $types = @('authentication') + $(if ($Signing) { @('signing') } else { @() })
    foreach ($type in $types) {
        $out = & gh ssh-key add $PubPath --title $title --type $type 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok "chave enviada ao GitHub ($type)" }
        elseif ("$out" -match 'already') { Write-Skip "chave já estava no GitHub ($type)" }
        else { throw "gh ssh-key add ($type): $out" }
    }
}

# Without GitHub CLI: copies the public key and opens the page to paste it.
function Show-KeyForManualUpload([bool]$Signing) {
    Get-Content $PubPath -Raw | Set-Clipboard
    Write-Ok 'chave pública copiada para a área de transferência'
    Write-Host '  Na página que vai abrir: cole em "Key", e salve.'
    if ($Signing) { Write-Host '  Repita uma segunda vez escolhendo "Key type: Signing Key" (para os commits verificados).' }
    Start-Process 'https://github.com/settings/ssh/new'
    Read-Host '  Enter quando terminar' | Out-Null
}

function Test-GitHubSsh {
    $out = & "$OpenSSH\ssh.exe" -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes git@github.com 2>&1
    if ("$out" -match 'successfully authenticated') { Write-Ok "conexão com o GitHub funcionando ($((("$out" -split '!')[0]) -replace '^.*Hi ', ''))" }
    else { Write-Warn "o GitHub ainda não aceitou a chave. Confira se ela foi salva em github.com/settings/keys. Detalhe: $out" }
}

# Signed commits with the SSH key ("Verified" on GitHub). Uses Windows' ssh-keygen so the agent
# provides the key (no passphrase on every commit). allowed_signers lets "git log --show-signature" verify locally.
function Set-CommitSigning([string]$Email) {
    if (-not (Test-Git)) { throw 'o Git não está instalado' }
    $pub = (Get-Content $PubPath -Raw).Trim()
    $signers = Join-Path $HOME '.ssh\allowed_signers'
    $line = "$Email namespaces=`"git`" $pub"
    if (-not (Test-Path $signers) -or -not (Select-String -Path $signers -SimpleMatch $pub -Quiet)) {
        Add-Content -Path $signers -Value $line -Encoding ASCII
    }
    Set-GitConfig 'gpg.format'                 'ssh'
    Set-GitConfig 'gpg.ssh.program'            "$($OpenSSH -replace '\\', '/')/ssh-keygen.exe"
    Set-GitConfig 'user.signingkey'            ($PubPath -replace '\\', '/')
    Set-GitConfig 'gpg.ssh.allowedSignersFile' ($signers -replace '\\', '/')
    Set-GitConfig 'commit.gpgsign'             'true'
    Set-GitConfig 'tag.gpgsign'                'true'
}

# --- Windows ------------------------------------------------------------------

function Enable-DevMode {
    if (Test-DevMode) { Write-Skip 'Modo de Desenvolvedor já está ligado'; return }
    if (-not (Test-Path $DevKey)) { New-Item -Path $DevKey -Force | Out-Null }
    New-ItemProperty -Path $DevKey -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Ok 'Modo de Desenvolvedor ligado (links simbólicos sem administrador, entre outros)'
}

# Windows 11 22H2+: the console app that opens command-line programs. These two IDs are Windows Terminal's.
function Set-DefaultTerminal {
    if (-not (Test-Path $ConsoleKey)) { New-Item -Path $ConsoleKey -Force | Out-Null }
    New-ItemProperty -Path $ConsoleKey -Name DelegationConsole  -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ConsoleKey -Name DelegationTerminal -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' -PropertyType String -Force | Out-Null
    Write-Ok 'Windows Terminal é o terminal padrão'
}

# Nerd Font from the official release, installed for the current user (no system-wide change).
function Install-NerdFont([string]$Key) {
    $font = $Fonts[$Key]
    if (Test-Font $font.Face) { Write-Skip "$($font.Face) já está instalada"; return }
    $work = Join-Path $env:TEMP "tidywin-font-$Key"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'font.zip'
        Write-Host "  baixando $($font.Face)..."
        Invoke-WebRequest "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$($font.Zip).zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive $zip -DestinationPath $work -Force
        $target = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $files = Get-ChildItem $work -Filter '*NerdFont-*.ttf' | Where-Object Name -notmatch 'NerdFontMono|NerdFontPropo'
        if (-not $files) { throw 'nenhum arquivo de fonte no pacote' }
        foreach ($f in $files) {
            Copy-Item $f.FullName $target -Force
            $name = ($f.BaseName -replace 'NerdFont-', ' Nerd Font ') + ' (TrueType)'
            New-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $name -Value (Join-Path $target $f.Name) -PropertyType String -Force | Out-Null
        }
        Write-Ok "$($font.Face) instalada ($($files.Count) estilos)"
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Edits Windows Terminal's settings.json: default font and/or PowerShell 7 as the default profile.
# A timestamped backup is made first. Comments in the file are not kept (the backup has them).
function Set-TerminalSettings([string]$FontFace, [bool]$PwshDefault) {
    if (-not (Test-Path $WtSettings)) {
        Write-Warn 'o Windows Terminal ainda não foi aberto nenhuma vez, então não tem configuração para ajustar. Abra o Terminal uma vez e rode o dev de novo (o resto já feito é pulado).'
        return
    }
    $text = Get-Content $WtSettings -Raw -Encoding UTF8
    try { $json = $text | ConvertFrom-Json -ErrorAction Stop }
    catch {
        try { $json = ($text -replace '(?m)^\s*//.*$', '') | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'não foi possível ler o settings.json do Terminal; ajuste a fonte em Configurações > Padrões > Aparência' }
    }
    $backup = "$WtSettings.tidywin-$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    Copy-Item $WtSettings $backup
    Write-Ok "backup: $(Split-Path $backup -Leaf)"

    if (-not $json.profiles) { $json | Add-Member profiles ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) }
    if ($json.profiles -is [array]) { throw 'formato antigo de settings.json; ajuste a fonte pelas Configurações do Terminal' }
    if (-not $json.profiles.defaults) { $json.profiles | Add-Member defaults ([pscustomobject]@{}) -Force }
    if ($FontFace) {
        if (-not $json.profiles.defaults.font) { $json.profiles.defaults | Add-Member font ([pscustomobject]@{}) -Force }
        $json.profiles.defaults.font | Add-Member face $FontFace -Force
        Write-Ok "fonte do Terminal: $FontFace"
    }
    if ($PwshDefault) {
        $json | Add-Member defaultProfile $PwshGuid -Force
        Write-Ok 'o Terminal abre no PowerShell 7'
    }
    [IO.File]::WriteAllText($WtSettings, ($json | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
}

function Install-Wsl([string]$Distro) {
    if ($Distro) { & wsl.exe --install -d $Distro --no-launch }
    else         { & wsl.exe --install --no-distribution }
    if ($LASTEXITCODE -ne 0) { throw "wsl --install terminou com código $LASTEXITCODE" }
    $script:NeedsRestart = $true
    Write-Ok "WSL instalado$(if ($Distro) { " com $Distro" }). Reinicie o PC; depois abra o $(if ($Distro) { $Distro } else { 'Terminal' }) para terminar."
}

#endregion


#region ==================== 4. REVERT ====================

function Invoke-Revert {
    Write-Host "`nConfigure-Dev -Revert" -ForegroundColor Green
    Write-Host '  Desfaz os ajustes do Windows. Apps, Git, chaves SSH e WSL ficam (veja no fim como remover).'
    Write-Step 'Modo de Desenvolvedor'
    Remove-ItemProperty $DevKey -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
    Write-Ok 'desligado'
    Write-Step 'Terminal padrão'
    Remove-ItemProperty $ConsoleKey -Name DelegationConsole, DelegationTerminal -ErrorAction SilentlyContinue
    Write-Ok 'volta para "Deixar o Windows decidir"'
    $backups = @(Get-ChildItem "$WtSettings.tidywin-*.bak" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($backups) {
        Write-Step 'Configurações do Windows Terminal'
        if (Ask "Voltar o settings.json para antes do primeiro dev ($($backups[0].Name))?" $true) {
            Copy-Item $backups[0].FullName $WtSettings -Force
            Write-Ok 'restaurado'
        }
    }
    Write-Host @'

Para remover o resto, se quiser:
  Apps ............ winget uninstall --id <ID>   (ex.: Microsoft.VisualStudioCode)
  Fontes .......... Configurações > Personalização > Fontes
  Git ............. apague %USERPROFILE%\.gitconfig (perde nome, e-mail e assinatura)
  Chave SSH ....... apague %USERPROFILE%\.ssh\id_ed25519* e remova em github.com/settings/keys
  WSL ............. wsl --unregister <distro>, depois desinstale "Subsistema do Windows para Linux"
  Logs ............ apague %LOCALAPPDATA%\TidyWin\dev-*.log
'@
}

if ($Revert) { Invoke-Revert; return }

#endregion


#region ==================== 5. QUESTIONS ====================

Write-Host "`nConfigure-Dev" -ForegroundColor Green
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'O WinGet não está instalado. Rode o apps (irm androksi.github.io/tidywin/apps | iex), que oferece instalar, e tente de novo.' -ForegroundColor Yellow
    return
}
Write-Host '  Todas as perguntas vêm primeiro; nada muda antes do resumo e da confirmação.'

$opt = [ordered]@{}

# --- Editors
Write-Host "`n  Editores e IDEs" -ForegroundColor Cyan
Write-Host '    verificando o que já está instalado...' -ForegroundColor DarkGray
foreach ($e in $Editors) { if (Test-WingetInstalled $e.Id) { $e.Checked = $false; $e.Note = 'já instalado' } }
$opt.Editors = @(Select-Many 'Quais instalar?' $Editors | Where-Object { $_.Note -ne 'já instalado' })

# --- Git
Write-Host "`n  Git" -ForegroundColor Cyan
$hasGit = Test-Git
$opt.InstallGit = if ($hasGit) { Write-Skip 'Git já instalado'; $false } else { Ask 'Instalar o Git?' $true }
$opt.Git = $hasGit -or $opt.InstallGit
$opt.GitName = $null; $opt.GitEmail = $null
if ($opt.Git) {
    $curName  = if ($hasGit) { Get-GitConfig 'user.name' }
    $curEmail = if ($hasGit) { Get-GitConfig 'user.email' }
    if ($curName -and $curEmail) {
        Write-Host "    nome e e-mail atuais: $curName <$curEmail>"
        $change = -not (Ask 'Manter esse nome e e-mail?' $true)
    } else { $change = $true }
    if ($change) {
        Write-Host '    Dica: para não expor seu e-mail, use o "noreply" que aparece em github.com/settings/emails.' -ForegroundColor DarkGray
        $opt.GitName  = Read-Text 'Nome para os commits:' $curName '' 'Digite um nome.'
        $opt.GitEmail = Read-Text 'E-mail para os commits:' $curEmail '^[^@\s]+@[^@\s]+\.[^@\s]+$' 'E-mail inválido.'
    }
    $opt.Email = if ($opt.GitEmail) { $opt.GitEmail } else { $curEmail }
    $curRebase = if ($hasGit) { Get-GitConfig 'pull.rebase' }            # the current choice becomes the default
    $opt.PullRebase = Ask 'git pull com rebase (histórico linear, sem commits de merge automáticos)?' ($curRebase -eq 'true')
    $hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    $opt.InstallGh = if ($hasGh) { $false } else { Ask 'Instalar o GitHub CLI (gh)? Ele também envia a chave SSH para o GitHub por você.' $true }
    $opt.Gh = $hasGh -or $opt.InstallGh
}

# --- SSH
Write-Host "`n  Chave SSH" -ForegroundColor Cyan
$hasKey = Test-Path $KeyPath
if ($hasKey) {
    Write-Host "    chave encontrada: $KeyPath (será usada, nunca substituída)"
    $opt.Ssh = Ask 'Configurar o ssh-agent e o GitHub com essa chave?' $true
} else {
    $opt.Ssh = Ask 'Criar uma chave SSH (ed25519) para o GitHub?' $true
}
$opt.Passphrase = if ($opt.Ssh -and -not $hasKey) { Ask 'Proteger a chave com senha? (recomendado; o ssh-agent lembra, você digita uma vez só)' $true } else { $false }
$opt.Upload = 'none'
if ($opt.Ssh) {
    $opt.Upload = if ($opt.Gh) {
        @('gh', 'manual', 'none')[(Choose 'Enviar a chave para o GitHub:' @('Automaticamente, pelo GitHub CLI (abre o navegador para entrar)', 'Eu colo no site (copia a chave e abre a página)', 'Não enviar agora') 0)]
    } else {
        @('manual', 'none')[(Choose 'Enviar a chave para o GitHub:' @('Eu colo no site (copia a chave e abre a página)', 'Não enviar agora') 0)]
    }
}
$opt.Signing = if ($opt.Ssh -and $opt.Git -and $opt.Email) { Ask 'Assinar commits com a chave SSH (selo "Verified" no GitHub)?' $true } else { $false }

# --- Terminal
Write-Host "`n  Terminal" -ForegroundColor Cyan
$hasWt = Test-Terminal
$opt.InstallWt = if ($hasWt) { $false } else { Ask 'Instalar o Windows Terminal?' $true }
$opt.Wt = $hasWt -or $opt.InstallWt
$opt.DefaultTerminal = if ($opt.Wt -and $isWin11 -and $build -ge 22621) { Ask 'Usar o Windows Terminal como terminal padrão do Windows?' $true } else { $false }
$hasPwsh = Test-Pwsh
$opt.InstallPwsh = if ($hasPwsh) { $false } else { Ask 'Instalar o PowerShell 7?' $true }
$opt.PwshDefault = if ($opt.Wt -and ($hasPwsh -or $opt.InstallPwsh)) { Ask 'Abrir o Windows Terminal no PowerShell 7?' $true } else { $false }
$fontNames = @('CaskaydiaCove Nerd Font (a fonte do Terminal, com ícones)', 'JetBrainsMono Nerd Font', 'Não instalar fonte')
$opt.Font = @('CaskaydiaCove', 'JetBrainsMono', $null)[(Choose 'Fonte para programar (Nerd Font: mostra ícones em ferramentas de terminal):' $fontNames 0)]
$opt.FontInTerminal = if ($opt.Font -and $opt.Wt) { Ask 'Usar essa fonte no Windows Terminal?' $true } else { $false }

# --- Windows
Write-Host "`n  Windows" -ForegroundColor Cyan
$opt.DevMode = if (Test-DevMode) { Write-Skip 'Modo de Desenvolvedor já está ligado'; $false } else { Ask 'Ligar o Modo de Desenvolvedor (links simbólicos sem administrador)?' $true }

# --- Languages
Write-Host "`n  Linguagens e ferramentas" -ForegroundColor Cyan
foreach ($l in $Languages) { if (Test-WingetInstalled $l.Id) { $l.Note = 'já instalado' } }
$opt.Languages = @(Select-Many 'Quais instalar? (nenhuma vem marcada)' $Languages | Where-Object { $_.Note -ne 'já instalado' })

# --- WSL
Write-Host "`n  WSL (Linux dentro do Windows)" -ForegroundColor Cyan
$opt.Wsl = $null
if (Test-Wsl) { Write-Skip 'WSL já instalado' }
else {
    $wslChoice = Choose 'Instalar o WSL? (baixa alguns GB e precisa reiniciar)' @('Não', 'Sim, com Ubuntu', 'Sim, com Debian', 'Sim, sem distribuição') 0
    $opt.Wsl = @($null, 'Ubuntu', 'Debian', '')[$wslChoice]
}

#endregion


#region ==================== 6. SUMMARY AND EXECUTION ====================

$yes = { param($b) if ($b) { 'sim' } else { 'não' } }
Write-Host "`n  Resumo:" -ForegroundColor Cyan
$lines = [ordered]@{
    'Editores'           = $(if ($opt.Editors) { ($opt.Editors | ForEach-Object Label) -join ', ' } else { 'nenhum' })
    'Git'                = $(if ($opt.InstallGit) { 'instalar e configurar' } elseif ($opt.Git) { 'configurar' } else { 'não' })
    'Nome e e-mail'      = $(if ($opt.GitName) { "$($opt.GitName) <$($opt.GitEmail)>" } else { 'manter' })
    'git pull rebase'    = & $yes $opt.PullRebase
    'GitHub CLI'         = $(if ($opt.InstallGh) { 'instalar' } elseif ($opt.Gh) { 'já instalado' } else { 'não' })
    'Chave SSH'          = $(if (-not $opt.Ssh) { 'não' } elseif ($hasKey) { 'usar a existente' } elseif ($opt.Passphrase) { 'criar, com senha' } else { 'criar, sem senha' })
    'Enviar ao GitHub'   = @{ gh = 'pelo GitHub CLI'; manual = 'colar no site'; none = 'não' }[$opt.Upload]
    'Commits assinados'  = & $yes $opt.Signing
    'Windows Terminal'   = $(if ($opt.InstallWt) { 'instalar' } elseif ($opt.Wt) { 'já instalado' } else { 'não' })
    'Terminal padrão'    = & $yes $opt.DefaultTerminal
    'PowerShell 7'       = $(if ($opt.InstallPwsh) { 'instalar' } elseif ($opt.PwshDefault) { 'já instalado' } else { 'não' }) + $(if ($opt.PwshDefault) { ', padrão no Terminal' } else { '' })
    'Fonte'              = $(if ($opt.Font) { $Fonts[$opt.Font].Face + $(if ($opt.FontInTerminal) { ', no Terminal' } else { '' }) } else { 'não' })
    'Modo Desenvolvedor' = & $yes $opt.DevMode
    'Linguagens'         = $(if ($opt.Languages) { ($opt.Languages | ForEach-Object Label) -join ', ' } else { 'nenhuma' })
    'WSL'                = $(if ($null -eq $opt.Wsl) { 'não' } elseif ($opt.Wsl) { $opt.Wsl } else { 'sem distribuição' })
}
foreach ($k in $lines.Keys) { Write-Host ("    {0,-20} {1}" -f $k, $lines[$k]) }
Write-Host ''
if (-not (Ask 'Aplicar agora?' $true)) { Write-Host 'Nada foi alterado.'; return }

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$log = Join-Path $LogDir "dev-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
try { Start-Transcript -Path $log -ErrorAction Stop | Out-Null } catch { $log = $null }
$script:NeedsRestart = $false

if ($opt.Editors)   { Invoke-Step 'Editores e IDEs' { Install-Editors $opt.Editors } }
if ($opt.InstallGit) { Invoke-Step 'Instalando o Git' { Install-App 'Git' 'Git.Git' } }
if ($opt.Git)       { Invoke-Step 'Configurando o Git' { Set-GitBasics $opt.GitName $opt.GitEmail $opt.PullRebase } }
if ($opt.InstallGh) { Invoke-Step 'Instalando o GitHub CLI' { Install-App 'GitHub CLI' 'GitHub.cli' } }

$keyReady = $false
if ($opt.Ssh) {
    Invoke-Step 'ssh-agent' { Enable-SshAgent }
    Invoke-Step 'Chave SSH' { New-SshKey $opt.Email $opt.Passphrase; Add-KeyToAgent; $script:keyReady = $true }
    if ($opt.Git) { Invoke-Step 'Git usando o SSH do Windows' { Set-GitUseWindowsSsh } }
    if ($script:keyReady) {
        switch ($opt.Upload) {
            'gh'     { Invoke-Step 'Enviando a chave ao GitHub' { Publish-KeyWithGh $opt.Signing } }
            'manual' { Invoke-Step 'Enviando a chave ao GitHub' { Show-KeyForManualUpload $opt.Signing } }
        }
        if ($opt.Upload -ne 'none') { Invoke-Step 'Testando a conexão com o GitHub' { Test-GitHubSsh } }
        if ($opt.Signing) { Invoke-Step 'Commits assinados' { Set-CommitSigning $opt.Email } }
    }
}

if ($opt.InstallWt)       { Invoke-Step 'Instalando o Windows Terminal' { Install-App 'Windows Terminal' 'Microsoft.WindowsTerminal' } }
if ($opt.DefaultTerminal) { Invoke-Step 'Terminal padrão' { Set-DefaultTerminal } }
if ($opt.InstallPwsh)     { Invoke-Step 'Instalando o PowerShell 7' { Install-App 'PowerShell 7' 'Microsoft.PowerShell' } }
if ($opt.Font)            { Invoke-Step 'Fonte' { Install-NerdFont $opt.Font } }
if ($opt.FontInTerminal -or $opt.PwshDefault) {
    $face = if ($opt.FontInTerminal) { $Fonts[$opt.Font].Face } else { $null }
    Invoke-Step 'Configurações do Windows Terminal' { Set-TerminalSettings $face $opt.PwshDefault }
}
if ($opt.DevMode)   { Invoke-Step 'Modo de Desenvolvedor' { Enable-DevMode } }
if ($opt.Languages) { Invoke-Step 'Linguagens e ferramentas' { Install-Languages $opt.Languages } }
if ($null -ne $opt.Wsl) { Invoke-Step 'WSL' { Install-Wsl $opt.Wsl } }

# --- Done
if ($script:Failures.Count) {
    Write-Host "`nEtapas que falharam (o resto foi aplicado; rode o dev de novo depois de resolver):" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Step 'Concluído'
if (Test-Path $PubPath) { Write-Host "  Chave SSH: $PubPath" }
Write-Host '  Feche e abra o terminal para os programas novos aparecerem no PATH.'
if ($script:NeedsRestart) { Write-Host '  Reinicie o computador para terminar o WSL.' -ForegroundColor Yellow }
if ($log) { try { Stop-Transcript | Out-Null } catch { }; Write-Host "  Registro completo: $log" -ForegroundColor DarkGray }
Write-Host '  Para desfazer os ajustes do Windows: dev-revert' -ForegroundColor DarkGray

#endregion
