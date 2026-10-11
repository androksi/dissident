#Requires -RunAsAdministrator
<#
    Configure-Dev.ps1 — a ready-to-code Windows: editors, Git, SSH key, signed commits, terminal, fonts,
    languages and WSL

    HOW TO RUN (Windows PowerShell 5.1 as Administrator), after Windows, drivers and apps are set up:
        powershell -ExecutionPolicy Bypass -File .\Configure-Dev.ps1
    UNDO the Windows-level settings (Developer Mode, default terminal, Terminal settings):
        powershell -ExecutionPolicy Bypass -File .\Configure-Dev.ps1 -Revert
    Language: asked at the start (English by default); skip the question with -Lang en or -Lang pt.

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
    [switch]$Revert,
    [ValidateSet('en', 'pt')][string]$Lang
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    # T is not defined yet: same choice inline (English unless -Lang pt)
    Write-Warning $(if ($Lang -eq 'pt') { 'Rode no Windows PowerShell 5.1 (powershell.exe), não no PowerShell 7 (pwsh).' } else { 'Run this in Windows PowerShell 5.1 (powershell.exe), not in PowerShell 7 (pwsh).' })
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12


#region ==================== 1. HELPERS ====================

# Text in the chosen language: T 'English text' 'Texto em português'
function T([string]$En, [string]$Pt) { if ($script:Lang -eq 'pt') { $Pt } else { $En } }

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host '  [OK] ' -ForegroundColor Green -NoNewline; Write-Host $Text }
function Write-Skip([string]$Text) { Write-Host "  [--] $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text) { Write-Host "  $(T '[WARNING]' '[ATENÇÃO]') $Text" -ForegroundColor Yellow }

# Menu driven by the ↑ ↓ arrow keys and Enter. Returns the chosen index.
# The "use the arrows" hint is shown only on the first menu.
function Choose([string]$Question, [string[]]$Options, [int]$Default = 0) {
    Write-Host "  $Question"
    $arrows = ($Host.Name -eq 'ConsoleHost') -and -not [Console]::IsInputRedirected
    if (-not $arrows) {
        # No real console (e.g. PowerShell ISE): numbered menu instead
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "    $($i + 1)) $($Options[$i])" }
        while ($true) {
            $answer = "$(Read-Host (T "  Number [$($Default + 1)]" "  Número [$($Default + 1)]"))".Trim()
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
        $answer = "$(Read-Host (T '  Numbers separated by commas (Enter keeps the checked ones)' '  Números separados por vírgula (Enter mantém os marcados)'))".Trim()
        if ($answer) {
            $picked = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
            for ($i = 0; $i -lt $Items.Count; $i++) { $Items[$i].Checked = $picked -contains $i }
        }
        return @($Items | Where-Object Checked)
    }
    Write-Host (T '  (↑ ↓ move, Space checks/unchecks, Enter confirms)' '  (↑ ↓ navega, Espaço marca/desmarca, Enter confirma)') -ForegroundColor DarkGray
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
        Write-Warning (T "This step failed ($($_.Exception.Message)). Moving on to the next one." "Esta etapa falhou ($($_.Exception.Message)). Seguindo para a próxima.")
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
    if (Test-WingetInstalled $Id) { Write-Skip (T "$Name is already installed" "$Name já está instalado"); return }
    Write-Host (T "  installing $Name$(if ($Interactive) { ' (the installer will open: choose the options there)' })..." "  instalando $Name$(if ($Interactive) { ' (o instalador vai abrir: escolha as opções nele)' })...")
    $args2 = @('install', '--id', $Id, '-e', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
    if ($Interactive) { $args2 += '--interactive' } else { $args2 += '--silent' }
    & winget @args2
    if ($LASTEXITCODE -ne 0 -and -not (Test-WingetInstalled $Id)) { throw (T "$Name was not installed (WinGet code $LASTEXITCODE)" "$Name não foi instalado (WinGet código $LASTEXITCODE)") }
    Write-Ok (T "$Name installed" "$Name instalado")
    Update-SessionPath
}

function Get-GitConfig([string]$Key) {
    $value = & git config --global --get $Key 2>$null
    if ($LASTEXITCODE -eq 0) { "$value".Trim() }
}

function Set-GitConfig([string]$Key, [string]$Value) {
    & git config --global $Key $Value
    if ($LASTEXITCODE -ne 0) { throw (T "git config $Key failed" "git config $Key falhou") }
    Write-Ok "git $Key = $Value"
}

# Language: asked once at the start (default English), unless -Lang was given.
if (-not $Lang) { $Lang = @('en', 'pt')[(Choose 'Language / Idioma:' @('English', 'Português (Brasil)') 0)] }
$script:Lang = $Lang

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
# Installed is set during the questions (already installed = shown but never installed again).
$Editors = @(
    [pscustomobject]@{ Label = 'VS Code';           Id = 'Microsoft.VisualStudioCode'; Interactive = $true;  Checked = $true;  Installed = $false; Note = (T 'code editor (interactive installer: check "Open with Code")' 'editor de código (instalador interativo: marque "Abrir com Code")') }
    [pscustomobject]@{ Label = 'Cursor';            Id = 'Anysphere.Cursor';           Interactive = $false; Checked = $false; Installed = $false; Note = (T 'based on VS Code, with AI' 'baseado no VS Code, com IA') }
    [pscustomobject]@{ Label = 'Zed';               Id = 'ZedIndustries.Zed';          Interactive = $false; Checked = $false; Installed = $false; Note = (T 'very fast editor (open source)' 'editor muito rápido (open source)') }
    [pscustomobject]@{ Label = 'JetBrains Toolbox'; Id = 'JetBrains.Toolbox';          Interactive = $false; Checked = $false; Installed = $false; Note = (T 'installs IntelliJ, PyCharm, WebStorm, Rider...' 'instala IntelliJ, PyCharm, WebStorm, Rider...') }
    [pscustomobject]@{ Label = 'Sublime Text';      Id = 'SublimeHQ.SublimeText.4';    Interactive = $false; Checked = $false; Installed = $false; Note = (T 'lightweight editor' 'editor leve') }
    [pscustomobject]@{ Label = 'Neovim';            Id = 'Neovim.Neovim';              Interactive = $false; Checked = $false; Installed = $false; Note = (T 'terminal editor (open source)' 'editor no terminal (open source)') }
)
$Languages = @(
    [pscustomobject]@{ Label = 'Node.js LTS';       Id = 'OpenJS.NodeJS.LTS';              Checked = $false; Installed = $false; Note = 'JavaScript/TypeScript' }
    [pscustomobject]@{ Label = 'Python 3.14';       Id = 'Python.Python.3.14';             Checked = $false; Installed = $false; Note = '' }
    [pscustomobject]@{ Label = 'Go';                Id = 'GoLang.Go';                      Checked = $false; Installed = $false; Note = '' }
    [pscustomobject]@{ Label = 'Rust (rustup)';     Id = 'Rustlang.Rustup';                Checked = $false; Installed = $false; Note = (T 'needs the Visual Studio build tools; rustup tells you' 'precisa das ferramentas de build do Visual Studio; o rustup avisa') }
    [pscustomobject]@{ Label = 'Java 25 (Temurin)'; Id = 'EclipseAdoptium.Temurin.25.JDK'; Checked = $false; Installed = $false; Note = '' }
    [pscustomobject]@{ Label = 'Bun';               Id = 'Oven-sh.Bun';                    Checked = $false; Installed = $false; Note = (T 'JavaScript runtime' 'runtime JavaScript') }
    [pscustomobject]@{ Label = 'Docker Desktop';    Id = 'Docker.DockerDesktop';           Checked = $false; Installed = $false; Note = (T 'uses WSL' 'usa o WSL') }
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
        catch { $script:Failures += (T "Language $($l.Label): $($_.Exception.Message)" "Linguagem $($l.Label): $($_.Exception.Message)"); Write-Warning $_.Exception.Message }
    }
}

# --- Git ----------------------------------------------------------------------

function Set-GitBasics([string]$Name, [string]$Email) {
    if (-not (Test-Git)) { throw (T 'Git is not installed' 'o Git não está instalado') }
    if ($Name)  { Set-GitConfig 'user.name'  $Name }
    if ($Email) { Set-GitConfig 'user.email' $Email }
    Set-GitConfig 'init.defaultBranch' 'main'
    Set-GitConfig 'core.longpaths'     'true'     # paths over 260 characters (node_modules)
    Set-GitConfig 'core.autocrlf'      'true'     # Windows line endings in the files, LF in the repository
    Set-GitConfig 'fetch.prune'        'true'     # forget remote branches that were deleted
    if (-not (Get-GitConfig 'credential.helper')) { Set-GitConfig 'credential.helper' 'manager' }
}

# --- SSH ----------------------------------------------------------------------

# Windows' own OpenSSH (the agent runs as a Windows service). Installs it if it was removed.
function Enable-SshAgent {
    if (-not (Test-Path "$OpenSSH\ssh-keygen.exe")) {
        Write-Host (T '  installing the Windows OpenSSH client...' '  instalando o cliente OpenSSH do Windows...')
        Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' -ErrorAction Stop | Out-Null
    }
    Set-Service ssh-agent -StartupType Automatic -ErrorAction Stop
    Start-Service ssh-agent -ErrorAction Stop
    Write-Ok (T 'ssh-agent on (starts with Windows)' 'ssh-agent ligado (inicia com o Windows)')
}

function New-SshKey([string]$Email, [bool]$Passphrase) {
    if (Test-Path $KeyPath) { Write-Skip (T "key already exists, kept: $KeyPath" "chave já existe, mantida: $KeyPath"); return }
    New-Item -ItemType Directory -Path (Split-Path $KeyPath) -Force | Out-Null
    $comment = if ($Email) { $Email } else { "$env:USERNAME@$env:COMPUTERNAME" }
    if ($Passphrase) {
        Write-Host (T '  type the key passphrase twice (it does not show while you type):' '  digite a senha da chave duas vezes (ela não aparece enquanto você digita):')
        & "$OpenSSH\ssh-keygen.exe" -t ed25519 -C $comment -f $KeyPath
    } else {
        & "$OpenSSH\ssh-keygen.exe" -t ed25519 -C $comment -f $KeyPath -N '""' -q   # '""' = empty passphrase in Windows PowerShell
    }
    if (-not (Test-Path $PubPath)) { throw (T 'the key was not created' 'a chave não foi criada') }
    Write-Ok (T "key created: $KeyPath" "chave criada: $KeyPath")
}

function Add-KeyToAgent {
    $fingerprint = ((& "$OpenSSH\ssh-keygen.exe" -lf $PubPath) -split ' ')[1]
    $loaded = & "$OpenSSH\ssh-add.exe" -l 2>$null
    if ($loaded -match [regex]::Escape($fingerprint)) { Write-Skip (T 'key is already in ssh-agent' 'chave já está no ssh-agent'); return }
    Write-Host (T '  adding the key to ssh-agent (if it has a passphrase, type it now; only this once)...' '  adicionando a chave ao ssh-agent (se ela tiver senha, digite agora; é só desta vez)...')
    & "$OpenSSH\ssh-add.exe" $KeyPath
    if ($LASTEXITCODE -ne 0) { throw (T 'ssh-add failed' 'ssh-add falhou') }
    Write-Ok (T 'key in ssh-agent' 'chave no ssh-agent')
}

# Git for Windows has its own ssh, which can't see the Windows agent. Point Git to Windows' OpenSSH.
function Set-GitUseWindowsSsh {
    if (-not (Test-Git)) { throw (T 'Git is not installed' 'o Git não está instalado') }
    Set-GitConfig 'core.sshCommand' "$($OpenSSH -replace '\\', '/')/ssh.exe"
}

# --- GitHub ------------------------------------------------------------------

# Signs in to GitHub CLI (in the browser) with permission to add SSH keys, then adds the key for
# authentication and, if chosen, for signing. A key that is already there counts as done.
function Publish-KeyWithGh([bool]$Signing, [bool]$RemoveOld) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw (T 'GitHub CLI is not installed' 'o GitHub CLI não está instalado') }
    $scopes = 'admin:public_key' + $(if ($Signing) { ',admin:ssh_signing_key' } else { '' })
    & gh auth status --hostname github.com 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host (T '  signing in to GitHub (the browser will open; copy the code shown here)...' '  entrando no GitHub (o navegador vai abrir; copie o código que aparecer aqui)...')
        & gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key --scopes $scopes
    } else {
        Write-Host (T '  asking for permission to add keys (the browser may open)...' '  pedindo permissão para adicionar chaves (o navegador pode abrir)...')
        & gh auth refresh --hostname github.com --scopes $scopes
    }
    if ($LASTEXITCODE -ne 0) { throw (T 'could not sign in to GitHub with GitHub CLI' 'não foi possível entrar no GitHub pelo GitHub CLI') }

    $title = "$env:COMPUTERNAME (TidyWin)"
    $types = @('authentication') + $(if ($Signing) { @('signing') } else { @() })
    foreach ($type in $types) {
        $out = & gh ssh-key add $PubPath --title $title --type $type 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok (T "key sent to GitHub ($type)" "chave enviada ao GitHub ($type)") }
        elseif ("$out" -match 'already') { Write-Skip (T "key was already on GitHub ($type)" "chave já estava no GitHub ($type)") }
        else { throw "gh ssh-key add ($type): $out" }
    }
    if ($RemoveOld) { Remove-OldGitHubKeys $title $Signing }
}

# Keys this script added from this same PC before (same title) that are not the current key: after
# formatting, the old key file is gone and they only take up space. Keys with any other title are never touched.
function Remove-OldGitHubKeys([string]$Title, [bool]$Signing) {
    $current = ((Get-Content $PubPath -Raw).Trim() -split '\s+')[0..1] -join ' '     # "ssh-ed25519 AAAA..." without the comment
    $endpoints = @('user/keys') + $(if ($Signing) { @('user/ssh_signing_keys') } else { @() })
    $removed = 0
    foreach ($endpoint in $endpoints) {
        $lines = & gh api $endpoint --paginate --jq '.[]' 2>$null          # one JSON object per line, across pages
        if ($LASTEXITCODE -ne 0) { Write-Warn (T "could not list the keys in $endpoint" "não foi possível listar as chaves em $endpoint"); continue }
        $old = @($lines | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object {
            $_.title -eq $Title -and ((($_.key -split '\s+')[0..1]) -join ' ') -ne $current
        })
        foreach ($k in $old) {
            & gh api -X DELETE "$endpoint/$($k.id)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $removed++; Write-Ok (T "old key removed from GitHub ($($k.title), created on $(([datetime]$k.created_at).ToString('dd/MM/yyyy')))" "chave antiga removida do GitHub ($($k.title), criada em $(([datetime]$k.created_at).ToString('dd/MM/yyyy')))") }
            else { Write-Warn (T "could not remove the old key $($k.id)" "não foi possível remover a chave antiga $($k.id)") }
        }
    }
    if (-not $removed) { Write-Skip (T 'no old keys from this PC on GitHub' 'nenhuma chave antiga deste PC no GitHub') }
}

# Without GitHub CLI: copies the public key and opens the page to paste it.
function Show-KeyForManualUpload([bool]$Signing) {
    Get-Content $PubPath -Raw | Set-Clipboard
    Write-Ok (T 'public key copied to the clipboard' 'chave pública copiada para a área de transferência')
    Write-Host (T '  On the page that opens: paste it into "Key" and save.' '  Na página que vai abrir: cole em "Key", e salve.')
    if ($Signing) { Write-Host (T '  Repeat a second time choosing "Key type: Signing Key" (for verified commits).' '  Repita uma segunda vez escolhendo "Key type: Signing Key" (para os commits verificados).') }
    Start-Process 'https://github.com/settings/ssh/new'
    Read-Host (T '  Press Enter when done' '  Enter quando terminar') | Out-Null
}

function Test-GitHubSsh {
    $out = & "$OpenSSH\ssh.exe" -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes git@github.com 2>&1
    if ("$out" -match 'successfully authenticated') { Write-Ok (T "connection to GitHub working ($((("$out" -split '!')[0]) -replace '^.*Hi ', ''))" "conexão com o GitHub funcionando ($((("$out" -split '!')[0]) -replace '^.*Hi ', ''))") }
    else { Write-Warn (T "GitHub has not accepted the key yet. Check that it was saved at github.com/settings/keys. Details: $out" "o GitHub ainda não aceitou a chave. Confira se ela foi salva em github.com/settings/keys. Detalhe: $out") }
}

# Signed commits with the SSH key ("Verified" on GitHub). Uses Windows' ssh-keygen so the agent
# provides the key (no passphrase on every commit). allowed_signers lets "git log --show-signature" verify locally.
function Set-CommitSigning([string]$Email) {
    if (-not (Test-Git)) { throw (T 'Git is not installed' 'o Git não está instalado') }
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
    if (Test-DevMode) { Write-Skip (T 'Developer Mode is already on' 'Modo de Desenvolvedor já está ligado'); return }
    if (-not (Test-Path $DevKey)) { New-Item -Path $DevKey -Force | Out-Null }
    New-ItemProperty -Path $DevKey -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Ok (T 'Developer Mode on (symbolic links without administrator, among others)' 'Modo de Desenvolvedor ligado (links simbólicos sem administrador, entre outros)')
}

# Windows 11 22H2+: the console app that opens command-line programs. These two IDs are Windows Terminal's.
function Set-DefaultTerminal {
    if (-not (Test-Path $ConsoleKey)) { New-Item -Path $ConsoleKey -Force | Out-Null }
    New-ItemProperty -Path $ConsoleKey -Name DelegationConsole  -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ConsoleKey -Name DelegationTerminal -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' -PropertyType String -Force | Out-Null
    Write-Ok (T 'Windows Terminal is the default terminal' 'Windows Terminal é o terminal padrão')
}

# Nerd Font from the official release, installed for the current user (no system-wide change).
function Install-NerdFont([string]$Key) {
    $font = $Fonts[$Key]
    if (Test-Font $font.Face) { Write-Skip (T "$($font.Face) is already installed" "$($font.Face) já está instalada"); return }
    $work = Join-Path $env:TEMP "tidywin-font-$Key"
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'font.zip'
        Write-Host (T "  downloading $($font.Face)..." "  baixando $($font.Face)...")
        Invoke-WebRequest "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$($font.Zip).zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive $zip -DestinationPath $work -Force
        $target = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $files = Get-ChildItem $work -Filter '*NerdFont-*.ttf' | Where-Object Name -notmatch 'NerdFontMono|NerdFontPropo'
        if (-not $files) { throw (T 'no font files in the package' 'nenhum arquivo de fonte no pacote') }
        foreach ($f in $files) {
            Copy-Item $f.FullName $target -Force
            $name = ($f.BaseName -replace 'NerdFont-', ' Nerd Font ') + ' (TrueType)'
            New-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $name -Value (Join-Path $target $f.Name) -PropertyType String -Force | Out-Null
        }
        Write-Ok (T "$($font.Face) installed ($($files.Count) styles)" "$($font.Face) instalada ($($files.Count) estilos)")
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Edits Windows Terminal's settings.json: default font and/or PowerShell 7 as the default profile.
# A timestamped backup is made first. Comments in the file are not kept (the backup has them).
function Set-TerminalSettings([string]$FontFace, [bool]$PwshDefault) {
    if (-not (Test-Path $WtSettings)) {
        Write-Warn (T 'Windows Terminal has never been opened yet, so there are no settings to adjust. Open Terminal once and run dev again (what is already done is skipped).' 'o Windows Terminal ainda não foi aberto nenhuma vez, então não tem configuração para ajustar. Abra o Terminal uma vez e rode o dev de novo (o resto já feito é pulado).')
        return
    }
    $text = Get-Content $WtSettings -Raw -Encoding UTF8
    try { $json = $text | ConvertFrom-Json -ErrorAction Stop }
    catch {
        try { $json = ($text -replace '(?m)^\s*//.*$', '') | ConvertFrom-Json -ErrorAction Stop }
        catch { throw (T "could not read Terminal's settings.json; set the font in Settings > Defaults > Appearance" 'não foi possível ler o settings.json do Terminal; ajuste a fonte em Configurações > Padrões > Aparência') }
    }
    $backup = "$WtSettings.tidywin-$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    Copy-Item $WtSettings $backup
    Write-Ok "backup: $(Split-Path $backup -Leaf)"

    if (-not $json.profiles) { $json | Add-Member profiles ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) }
    if ($json.profiles -is [array]) { throw (T "old settings.json format; set the font in Terminal's Settings" 'formato antigo de settings.json; ajuste a fonte pelas Configurações do Terminal') }
    if (-not $json.profiles.defaults) { $json.profiles | Add-Member defaults ([pscustomobject]@{}) -Force }
    if ($FontFace) {
        if (-not $json.profiles.defaults.font) { $json.profiles.defaults | Add-Member font ([pscustomobject]@{}) -Force }
        $json.profiles.defaults.font | Add-Member face $FontFace -Force
        Write-Ok (T "Terminal font: $FontFace" "fonte do Terminal: $FontFace")
    }
    if ($PwshDefault) {
        $json | Add-Member defaultProfile $PwshGuid -Force
        Write-Ok (T 'Terminal opens in PowerShell 7' 'o Terminal abre no PowerShell 7')
    }
    [IO.File]::WriteAllText($WtSettings, ($json | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
}

function Install-Wsl([string]$Distro) {
    if ($Distro) { & wsl.exe --install -d $Distro --no-launch }
    else         { & wsl.exe --install --no-distribution }
    if ($LASTEXITCODE -ne 0) { throw (T "wsl --install ended with code $LASTEXITCODE" "wsl --install terminou com código $LASTEXITCODE") }
    $script:NeedsRestart = $true
    Write-Ok (T "WSL installed$(if ($Distro) { " with $Distro" }). Restart the PC, then open $(if ($Distro) { $Distro } else { 'Terminal' }) to finish." "WSL instalado$(if ($Distro) { " com $Distro" }). Reinicie o PC; depois abra o $(if ($Distro) { $Distro } else { 'Terminal' }) para terminar.")
}

#endregion


#region ==================== 4. REVERT ====================

function Invoke-Revert {
    Write-Host "`nConfigure-Dev -Revert" -ForegroundColor Green
    Write-Host (T '  Undoes the Windows settings. Apps, Git, SSH keys and WSL stay (see at the end how to remove them).' '  Desfaz os ajustes do Windows. Apps, Git, chaves SSH e WSL ficam (veja no fim como remover).')
    Write-Step (T 'Developer Mode' 'Modo de Desenvolvedor')
    Remove-ItemProperty $DevKey -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
    Write-Ok (T 'off' 'desligado')
    Write-Step (T 'Default terminal' 'Terminal padrão')
    Remove-ItemProperty $ConsoleKey -Name DelegationConsole, DelegationTerminal -ErrorAction SilentlyContinue
    Write-Ok (T 'back to "Let Windows decide"' 'volta para "Deixar o Windows decidir"')
    $backups = @(Get-ChildItem "$WtSettings.tidywin-*.bak" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($backups) {
        Write-Step (T 'Windows Terminal settings' 'Configurações do Windows Terminal')
        if (Ask (T "Restore settings.json to how it was before the first dev run ($($backups[0].Name))?" "Voltar o settings.json para antes do primeiro dev ($($backups[0].Name))?") $true) {
            Copy-Item $backups[0].FullName $WtSettings -Force
            Write-Ok (T 'restored' 'restaurado')
        }
    }
    if ($script:Lang -eq 'pt') {
        Write-Host @'

Para remover o resto, se quiser:
  Apps ............ winget uninstall --id <ID>   (ex.: Microsoft.VisualStudioCode)
  Fontes .......... Configurações > Personalização > Fontes
  Git ............. apague %USERPROFILE%\.gitconfig (perde nome, e-mail e assinatura)
  Chave SSH ....... apague %USERPROFILE%\.ssh\id_ed25519* e remova em github.com/settings/keys
  WSL ............. wsl --unregister <distro>, depois desinstale "Subsistema do Windows para Linux"
  Logs ............ apague %LOCALAPPDATA%\TidyWin\dev-*.log
'@
    } else {
        Write-Host @'

To remove the rest, if you want:
  Apps ............ winget uninstall --id <ID>   (e.g. Microsoft.VisualStudioCode)
  Fonts ........... Settings > Personalization > Fonts
  Git ............. delete %USERPROFILE%\.gitconfig (loses name, e-mail and signing)
  SSH key ......... delete %USERPROFILE%\.ssh\id_ed25519* and remove it at github.com/settings/keys
  WSL ............. wsl --unregister <distro>, then uninstall "Windows Subsystem for Linux"
  Logs ............ delete %LOCALAPPDATA%\TidyWin\dev-*.log
'@
    }
}

if ($Revert) { Invoke-Revert; return }

#endregion


#region ==================== 5. QUESTIONS ====================

Write-Host "`nConfigure-Dev" -ForegroundColor Green
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host (T 'WinGet is not installed. Run apps (irm androksi.github.io/tidywin/apps | iex), which offers to install it, and try again.' 'O WinGet não está instalado. Rode o apps (irm androksi.github.io/tidywin/apps | iex), que oferece instalar, e tente de novo.') -ForegroundColor Yellow
    return
}
Write-Host (T '  All questions come first; nothing changes before the summary and the confirmation.' '  Todas as perguntas vêm primeiro; nada muda antes do resumo e da confirmação.')

$opt = [ordered]@{}

# --- Editors
Write-Host "`n  $(T 'Editors and IDEs' 'Editores e IDEs')" -ForegroundColor Cyan
Write-Host (T '    checking what is already installed...' '    verificando o que já está instalado...') -ForegroundColor DarkGray
foreach ($e in $Editors) { if (Test-WingetInstalled $e.Id) { $e.Checked = $false; $e.Installed = $true; $e.Note = (T 'already installed' 'já instalado') } }
$opt.Editors = @(Select-Many (T 'Which ones to install?' 'Quais instalar?') $Editors | Where-Object { -not $_.Installed })

# --- Git
Write-Host "`n  Git" -ForegroundColor Cyan
$hasGit = Test-Git
$opt.InstallGit = if ($hasGit) { Write-Skip (T 'Git already installed' 'Git já instalado'); $false } else { Ask (T 'Install Git?' 'Instalar o Git?') $true }
$opt.Git = $hasGit -or $opt.InstallGit
$opt.GitName = $null; $opt.GitEmail = $null
if ($opt.Git) {
    $curName  = if ($hasGit) { Get-GitConfig 'user.name' }
    $curEmail = if ($hasGit) { Get-GitConfig 'user.email' }
    if ($curName -and $curEmail) {
        Write-Host (T "    current name and e-mail: $curName <$curEmail>" "    nome e e-mail atuais: $curName <$curEmail>")
        $change = -not (Ask (T 'Keep this name and e-mail?' 'Manter esse nome e e-mail?') $true)
    } else { $change = $true }
    if ($change) {
        Write-Host (T '    Tip: to keep your e-mail private, use the "noreply" address shown at github.com/settings/emails.' '    Dica: para não expor seu e-mail, use o "noreply" que aparece em github.com/settings/emails.') -ForegroundColor DarkGray
        $opt.GitName  = Read-Text (T 'Name for commits:' 'Nome para os commits:') $curName '' (T 'Type a name.' 'Digite um nome.')
        $opt.GitEmail = Read-Text (T 'E-mail for commits:' 'E-mail para os commits:') $curEmail '^[^@\s]+@[^@\s]+\.[^@\s]+$' (T 'Invalid e-mail.' 'E-mail inválido.')
    }
    $opt.Email = if ($opt.GitEmail) { $opt.GitEmail } else { $curEmail }
    $hasGh = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    $opt.InstallGh = if ($hasGh) { $false } else { Ask (T 'Install GitHub CLI (gh)? It also sends the SSH key to GitHub for you.' 'Instalar o GitHub CLI (gh)? Ele também envia a chave SSH para o GitHub por você.') $true }
    $opt.Gh = $hasGh -or $opt.InstallGh
}

# --- SSH
Write-Host "`n  $(T 'SSH key' 'Chave SSH')" -ForegroundColor Cyan
$hasKey = Test-Path $KeyPath
if ($hasKey) {
    Write-Host (T "    key found: $KeyPath (it will be used, never replaced)" "    chave encontrada: $KeyPath (será usada, nunca substituída)")
    $opt.Ssh = Ask (T 'Set up ssh-agent and GitHub with this key?' 'Configurar o ssh-agent e o GitHub com essa chave?') $true
} else {
    $opt.Ssh = Ask (T 'Create an SSH key (ed25519) for GitHub?' 'Criar uma chave SSH (ed25519) para o GitHub?') $true
}
$opt.Passphrase = if ($opt.Ssh -and -not $hasKey) { Ask (T 'Protect the key with a passphrase? (recommended; ssh-agent remembers it, you type it only once)' 'Proteger a chave com senha? (recomendado; o ssh-agent lembra, você digita uma vez só)') $true } else { $false }
$opt.Upload = 'none'
if ($opt.Ssh) {
    $opt.Upload = if ($opt.Gh) {
        @('gh', 'manual', 'none')[(Choose (T 'Send the key to GitHub:' 'Enviar a chave para o GitHub:') @((T 'Automatically, with GitHub CLI (opens the browser to sign in)' 'Automaticamente, pelo GitHub CLI (abre o navegador para entrar)'), (T 'I paste it on the website (copies the key and opens the page)' 'Eu colo no site (copia a chave e abre a página)'), (T 'Do not send now' 'Não enviar agora')) 0)]
    } else {
        @('manual', 'none')[(Choose (T 'Send the key to GitHub:' 'Enviar a chave para o GitHub:') @((T 'I paste it on the website (copies the key and opens the page)' 'Eu colo no site (copia a chave e abre a página)'), (T 'Do not send now' 'Não enviar agora')) 0)]
    }
}
$opt.RemoveOld = if ($opt.Upload -eq 'gh') { Ask (T "Delete this PC's old keys from GitHub (the ones TidyWin sent with the name `"$env:COMPUTERNAME (TidyWin)`")?" "Apagar do GitHub as chaves antigas deste PC (as que o TidyWin enviou com o nome `"$env:COMPUTERNAME (TidyWin)`")?") $true } else { $false }
$opt.Signing = if ($opt.Ssh -and $opt.Git -and $opt.Email) { Ask (T 'Sign commits with the SSH key ("Verified" badge on GitHub)?' 'Assinar commits com a chave SSH (selo "Verified" no GitHub)?') $true } else { $false }

# --- Terminal
Write-Host "`n  Terminal" -ForegroundColor Cyan
$hasWt = Test-Terminal
$opt.InstallWt = if ($hasWt) { $false } else { Ask (T 'Install Windows Terminal?' 'Instalar o Windows Terminal?') $true }
$opt.Wt = $hasWt -or $opt.InstallWt
$opt.DefaultTerminal = if ($opt.Wt -and $isWin11 -and $build -ge 22621) { Ask (T "Use Windows Terminal as Windows' default terminal?" 'Usar o Windows Terminal como terminal padrão do Windows?') $true } else { $false }
$hasPwsh = Test-Pwsh
$opt.InstallPwsh = if ($hasPwsh) { $false } else { Ask (T 'Install PowerShell 7?' 'Instalar o PowerShell 7?') $true }
$opt.PwshDefault = if ($opt.Wt -and ($hasPwsh -or $opt.InstallPwsh)) { Ask (T 'Open Windows Terminal in PowerShell 7?' 'Abrir o Windows Terminal no PowerShell 7?') $true } else { $false }
$fontNames = @((T "CaskaydiaCove Nerd Font (Terminal's font, with icons)" 'CaskaydiaCove Nerd Font (a fonte do Terminal, com ícones)'), 'JetBrainsMono Nerd Font', (T 'Do not install a font' 'Não instalar fonte'))
$opt.Font = @('CaskaydiaCove', 'JetBrainsMono', $null)[(Choose (T 'Coding font (Nerd Font: shows icons in terminal tools):' 'Fonte para programar (Nerd Font: mostra ícones em ferramentas de terminal):') $fontNames 0)]
$opt.FontInTerminal = if ($opt.Font -and $opt.Wt) { Ask (T 'Use this font in Windows Terminal?' 'Usar essa fonte no Windows Terminal?') $true } else { $false }

# --- Windows
Write-Host "`n  Windows" -ForegroundColor Cyan
$opt.DevMode = if (Test-DevMode) { Write-Skip (T 'Developer Mode is already on' 'Modo de Desenvolvedor já está ligado'); $false } else { Ask (T 'Turn on Developer Mode (symbolic links without administrator)?' 'Ligar o Modo de Desenvolvedor (links simbólicos sem administrador)?') $true }

# --- Languages
Write-Host "`n  $(T 'Languages and tools' 'Linguagens e ferramentas')" -ForegroundColor Cyan
foreach ($l in $Languages) { if (Test-WingetInstalled $l.Id) { $l.Installed = $true; $l.Note = (T 'already installed' 'já instalado') } }
$opt.Languages = @(Select-Many (T 'Which ones to install? (none come checked)' 'Quais instalar? (nenhuma vem marcada)') $Languages | Where-Object { -not $_.Installed })

# --- WSL
Write-Host "`n  $(T 'WSL (Linux inside Windows)' 'WSL (Linux dentro do Windows)')" -ForegroundColor Cyan
$opt.Wsl = $null
if (Test-Wsl) { Write-Skip (T 'WSL already installed' 'WSL já instalado') }
else {
    $wslChoice = Choose (T 'Install WSL? (downloads a few GB and needs a restart)' 'Instalar o WSL? (baixa alguns GB e precisa reiniciar)') @((T 'No' 'Não'), (T 'Yes, with Ubuntu' 'Sim, com Ubuntu'), (T 'Yes, with Debian' 'Sim, com Debian'), (T 'Yes, without a distribution' 'Sim, sem distribuição')) 0
    $opt.Wsl = @($null, 'Ubuntu', 'Debian', '')[$wslChoice]
}

#endregion


#region ==================== 6. SUMMARY AND EXECUTION ====================

$yes = { param($b) if ($b) { T 'yes' 'sim' } else { T 'no' 'não' } }
Write-Host "`n  $(T 'Summary:' 'Resumo:')" -ForegroundColor Cyan
$lines = [ordered]@{
    (T 'Editors' 'Editores')                    = $(if ($opt.Editors) { ($opt.Editors | ForEach-Object Label) -join ', ' } else { T 'none' 'nenhum' })
    'Git'                                       = $(if ($opt.InstallGit) { T 'install and configure' 'instalar e configurar' } elseif ($opt.Git) { T 'configure' 'configurar' } else { T 'no' 'não' })
    (T 'Name and e-mail' 'Nome e e-mail')       = $(if ($opt.GitName) { "$($opt.GitName) <$($opt.GitEmail)>" } else { T 'keep' 'manter' })
    'GitHub CLI'                                = $(if ($opt.InstallGh) { T 'install' 'instalar' } elseif ($opt.Gh) { T 'already installed' 'já instalado' } else { T 'no' 'não' })
    (T 'SSH key' 'Chave SSH')                   = $(if (-not $opt.Ssh) { T 'no' 'não' } elseif ($hasKey) { T 'use the existing one' 'usar a existente' } elseif ($opt.Passphrase) { T 'create, with passphrase' 'criar, com senha' } else { T 'create, without passphrase' 'criar, sem senha' })
    (T 'Send to GitHub' 'Enviar ao GitHub')     = @{ gh = (T 'with GitHub CLI' 'pelo GitHub CLI'); manual = (T 'paste on the website' 'colar no site'); none = (T 'no' 'não') }[$opt.Upload] + $(if ($opt.RemoveOld) { T ", deleting this PC's old ones" ', apagando as antigas deste PC' } else { '' })
    (T 'Signed commits' 'Commits assinados')    = & $yes $opt.Signing
    'Windows Terminal'                          = $(if ($opt.InstallWt) { T 'install' 'instalar' } elseif ($opt.Wt) { T 'already installed' 'já instalado' } else { T 'no' 'não' })
    (T 'Default terminal' 'Terminal padrão')    = & $yes $opt.DefaultTerminal
    'PowerShell 7'                              = $(if ($opt.InstallPwsh) { T 'install' 'instalar' } elseif ($opt.PwshDefault) { T 'already installed' 'já instalado' } else { T 'no' 'não' }) + $(if ($opt.PwshDefault) { T ', default in Terminal' ', padrão no Terminal' } else { '' })
    (T 'Font' 'Fonte')                          = $(if ($opt.Font) { $Fonts[$opt.Font].Face + $(if ($opt.FontInTerminal) { T ', in Terminal' ', no Terminal' } else { '' }) } else { T 'no' 'não' })
    (T 'Developer Mode' 'Modo Desenvolvedor')   = & $yes $opt.DevMode
    (T 'Languages' 'Linguagens')                = $(if ($opt.Languages) { ($opt.Languages | ForEach-Object Label) -join ', ' } else { T 'none' 'nenhuma' })
    'WSL'                                       = $(if ($null -eq $opt.Wsl) { T 'no' 'não' } elseif ($opt.Wsl) { $opt.Wsl } else { T 'without a distribution' 'sem distribuição' })
}
foreach ($k in $lines.Keys) { Write-Host ("    {0,-20} {1}" -f $k, $lines[$k]) }
Write-Host ''
if (-not (Ask (T 'Apply now?' 'Aplicar agora?') $true)) { Write-Host (T 'Nothing was changed.' 'Nada foi alterado.'); return }

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$log = Join-Path $LogDir "dev-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
try { Start-Transcript -Path $log -ErrorAction Stop | Out-Null } catch { $log = $null }
$script:NeedsRestart = $false

if ($opt.Editors)   { Invoke-Step (T 'Editors and IDEs' 'Editores e IDEs') { Install-Editors $opt.Editors } }
if ($opt.InstallGit) { Invoke-Step (T 'Installing Git' 'Instalando o Git') { Install-App 'Git' 'Git.Git' } }
if ($opt.Git)       { Invoke-Step (T 'Configuring Git' 'Configurando o Git') { Set-GitBasics $opt.GitName $opt.GitEmail } }
if ($opt.InstallGh) { Invoke-Step (T 'Installing GitHub CLI' 'Instalando o GitHub CLI') { Install-App 'GitHub CLI' 'GitHub.cli' } }

$keyReady = $false
if ($opt.Ssh) {
    Invoke-Step 'ssh-agent' { Enable-SshAgent }
    Invoke-Step (T 'SSH key' 'Chave SSH') { New-SshKey $opt.Email $opt.Passphrase; Add-KeyToAgent; $script:keyReady = $true }
    if ($opt.Git) { Invoke-Step (T "Git using Windows' SSH" 'Git usando o SSH do Windows') { Set-GitUseWindowsSsh } }
    if ($script:keyReady) {
        switch ($opt.Upload) {
            'gh'     { Invoke-Step (T 'Sending the key to GitHub' 'Enviando a chave ao GitHub') { Publish-KeyWithGh $opt.Signing $opt.RemoveOld } }
            'manual' { Invoke-Step (T 'Sending the key to GitHub' 'Enviando a chave ao GitHub') { Show-KeyForManualUpload $opt.Signing } }
        }
        if ($opt.Upload -ne 'none') { Invoke-Step (T 'Testing the connection to GitHub' 'Testando a conexão com o GitHub') { Test-GitHubSsh } }
        if ($opt.Signing) { Invoke-Step (T 'Signed commits' 'Commits assinados') { Set-CommitSigning $opt.Email } }
    }
}

if ($opt.InstallWt)       { Invoke-Step (T 'Installing Windows Terminal' 'Instalando o Windows Terminal') { Install-App 'Windows Terminal' 'Microsoft.WindowsTerminal' } }
if ($opt.DefaultTerminal) { Invoke-Step (T 'Default terminal' 'Terminal padrão') { Set-DefaultTerminal } }
if ($opt.InstallPwsh)     { Invoke-Step (T 'Installing PowerShell 7' 'Instalando o PowerShell 7') { Install-App 'PowerShell 7' 'Microsoft.PowerShell' } }
if ($opt.Font)            { Invoke-Step (T 'Font' 'Fonte') { Install-NerdFont $opt.Font } }
if ($opt.FontInTerminal -or $opt.PwshDefault) {
    $face = if ($opt.FontInTerminal) { $Fonts[$opt.Font].Face } else { $null }
    Invoke-Step (T 'Windows Terminal settings' 'Configurações do Windows Terminal') { Set-TerminalSettings $face $opt.PwshDefault }
}
if ($opt.DevMode)   { Invoke-Step (T 'Developer Mode' 'Modo de Desenvolvedor') { Enable-DevMode } }
if ($opt.Languages) { Invoke-Step (T 'Languages and tools' 'Linguagens e ferramentas') { Install-Languages $opt.Languages } }
if ($null -ne $opt.Wsl) { Invoke-Step 'WSL' { Install-Wsl $opt.Wsl } }

# --- Done
if ($script:Failures.Count) {
    Write-Host (T "`nSteps that failed (the rest was applied; run dev again after fixing them):" "`nEtapas que falharam (o resto foi aplicado; rode o dev de novo depois de resolver):") -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Step (T 'Done' 'Concluído')
if (Test-Path $PubPath) { Write-Host (T "  SSH key: $PubPath" "  Chave SSH: $PubPath") }
Write-Host (T '  Close and reopen the terminal so the new programs show up in PATH.' '  Feche e abra o terminal para os programas novos aparecerem no PATH.')
if ($script:NeedsRestart) { Write-Host (T '  Restart the computer to finish WSL.' '  Reinicie o computador para terminar o WSL.') -ForegroundColor Yellow }
if ($log) { try { Stop-Transcript | Out-Null } catch { }; Write-Host (T "  Full log: $log" "  Registro completo: $log") -ForegroundColor DarkGray }
Write-Host (T '  To undo the Windows settings: dev-revert' '  Para desfazer os ajustes do Windows: dev-revert') -ForegroundColor DarkGray

#endregion
