[← voltar ao README](../README.md)

# Apps

```powershell
.\scripts\apps\Configure-Apps.ps1
```

| Funcionalidade | O que faz |
|---|---|
| Instalar WinGet | Se o WinGet não existir (geralmente no Windows 10), oferece instalar antes de tudo. |
| Lista de apps | 100 apps em categorias. ↑ ↓ navega, Espaço marca, Esc sai. |
| Já instalados | Mostra "instalado" ao lado dos apps que já estão no PC. |
| Marcar categoria | Tecla A: marca todos os apps da categoria (de novo: desmarca). |
| Busca | Tecla /: digite o nome e o cursor pula para o app. Enter confirma, Esc cancela. |
| Instalação interativa | Tecla I: abre o instalador do próprio app para escolher as opções (VS Code já vem marcado). |
| Confirmação | Mostra os apps escolhidos: "Retornar" (padrão) volta à lista, "Instalar apps" instala. |
| Resumo | Mostra o que instalou, o que já estava instalado e o que falhou. |
| Adicionar apps | Uma linha na lista `$Apps` do script (ID com `winget search <nome>`). |

## Teclas

| Tecla | Ação |
|---|---|
| ↑ ↓ PageUp PageDown Home End | navegar |
| Espaço | marcar / desmarcar |
| A | marcar a categoria inteira |
| I | instalação interativa |
| / | buscar pelo nome |
| Enter | continuar |
| Esc | sair |

## Lista completa

<details>
<summary>Ver os 100 apps</summary>

### Comunicação (8)

| App | O que é | ID |
|---|---|---|
| Discord | chat de voz e texto | `Discord.Discord` |
| Telegram | mensageiro | `Telegram.TelegramDesktop` |
| Signal | mensageiro com criptografia (open source) | `OpenWhisperSystems.Signal` |
| Thunderbird (pt-BR) | cliente de e-mail (open source) | `Mozilla.Thunderbird.pt-BR` |
| WhatsApp | WhatsApp para desktop (Microsoft Store) | `9NKSQGP7F2NH` (Store) |
| Zoom | videochamadas | `Zoom.Zoom` |
| Slack | chat de trabalho | `SlackTechnologies.Slack` |
| Microsoft Teams | reuniões e chat de trabalho | `Microsoft.Teams` |

### Design (7)

| App | O que é | ID |
|---|---|---|
| GIMP | editor de imagens (open source) | `GIMP.GIMP.3` |
| Inkscape | desenho vetorial (open source) | `Inkscape.Inkscape` |
| Krita | pintura digital (open source) | `KDE.Krita` |
| Blender | modelagem 3D e animação (open source) | `BlenderFoundation.Blender` |
| Figma | design de interfaces | `Figma.Figma` |
| Paint.NET | editor de imagens simples | `dotPDN.PaintDotNet` |
| ScreenToGif | grava a tela em GIF (open source) | `NickeManarin.ScreenToGif` |

### Jogos (12)

| App | O que é | ID |
|---|---|---|
| Steam | loja e biblioteca de jogos | `Valve.Steam` |
| Heroic Games Launcher | jogos da Epic, GOG e Amazon (open source) | `HeroicGamesLauncher.HeroicGamesLauncher` |
| NVIDIA App | drivers e ajustes da placa NVIDIA | `XP8CLZL93F5Z4P` (Store) |
| Epic Games Launcher | loja da Epic | `EpicGames.EpicGamesLauncher` |
| EA app | loja da EA | `ElectronicArts.EADesktop` |
| Ubisoft Connect | loja da Ubisoft | `Ubisoft.Connect` |
| Battle.net | loja da Blizzard | `Blizzard.BattleNet` |
| GOG Galaxy | loja da GOG | `GOG.Galaxy` |
| MSI Afterburner | FPS e temperaturas na tela dos jogos | `Guru3D.Afterburner` |
| Playnite | junta todas as bibliotecas de jogos (open source) | `Playnite.Playnite` |
| Prism Launcher | launcher de Minecraft com mods (open source) | `PrismLauncher.PrismLauncher` |
| RetroArch | emulador de consoles antigos (open source) | `Libretro.RetroArch` |

### Mídia (10)

| App | O que é | ID |
|---|---|---|
| Spotify | música (versão da Microsoft Store) | `9NCBCSZSJRSB` (Store) |
| VLC | toca qualquer vídeo ou áudio (open source) | `VideoLAN.VLC` |
| OBS Studio | gravar a tela e fazer live (open source) | `OBSProject.OBSStudio` |
| Audacity | editor de áudio (open source) | `Audacity.Audacity` |
| HandBrake | converter e comprimir vídeos (open source) | `HandBrake.HandBrake` |
| Kdenlive | editor de vídeo (open source) | `KDE.Kdenlive` |
| Shotcut | editor de vídeo simples (open source) | `Meltytech.Shotcut` |
| foobar2000 | player de música leve | `PeterPawlowski.foobar2000` |
| ImageGlass | visualizador de imagens rápido (open source) | `DuongDieuPhap.ImageGlass` |
| Stremio | central de filmes e séries | `Stremio.Stremio` |

### Navegadores (7)

| App | O que é | ID |
|---|---|---|
| Brave | navegador com bloqueador de anúncios | `Brave.Brave` |
| Chrome | navegador do Google | `Google.Chrome` |
| Firefox (pt-BR) | navegador da Mozilla | `Mozilla.Firefox.pt-BR` |
| Opera GX | navegador "gamer" da Opera | `Opera.OperaGX` |
| Zen Browser | navegador baseado no Firefox, visual moderno (open source) | `Zen-Team.Zen-Browser` |
| LibreWolf | Firefox focado em privacidade (open source) | `LibreWolf.LibreWolf` |
| Vivaldi | navegador cheio de personalização | `Vivaldi.Vivaldi` |

### Produtividade (10)

| App | O que é | ID |
|---|---|---|
| LibreOffice | pacote de escritório (open source) | `TheDocumentFoundation.LibreOffice` |
| Joplin | notas em Markdown (open source) | `Joplin.Joplin` |
| SumatraPDF | leitor de PDF leve (open source) | `SumatraPDF.SumatraPDF` |
| Claude | app do Claude para desktop | `Anthropic.Claude` |
| Obsidian | notas em Markdown | `Obsidian.Obsidian` |
| Notion | notas, tarefas e wikis | `Notion.Notion` |
| Adobe Acrobat Reader | leitor de PDF da Adobe | `Adobe.Acrobat.Reader.64-bit` |
| Google Drive | sincroniza o Google Drive com o PC | `Google.GoogleDrive` |
| ONLYOFFICE | escritório compatível com Office (open source) | `ONLYOFFICE.DesktopEditors` |
| Logseq | notas conectadas (open source) | `Logseq.Logseq` |

### Programação (27)

| App | O que é | ID |
|---|---|---|
| Git | controle de versão (open source) | `Git.Git` |
| GitHub Desktop | Git com interface gráfica | `GitHub.GitHubDesktop` |
| VS Code | editor de código | `Microsoft.VisualStudioCode` |
| Node.js LTS | JavaScript fora do navegador (open source) | `OpenJS.NodeJS.LTS` |
| fnm | troca entre versões do Node.js (open source) | `Schniz.fnm` |
| Python 3.14 | linguagem Python (open source) | `Python.Python.3.14` |
| PowerShell 7 | PowerShell moderno (open source) | `Microsoft.PowerShell` |
| Windows Terminal | terminal com abas (já vem no Windows 11) | `Microsoft.WindowsTerminal` |
| Notepad++ | editor de texto (open source) | `Notepad++.Notepad++` |
| WinMerge | comparar arquivos e pastas (open source) | `WinMerge.WinMerge` |
| DBeaver | cliente de banco de dados (open source) | `DBeaver.DBeaver.Community` |
| Bruno | testar APIs, alternativa ao Postman (open source) | `Bruno.Bruno` |
| Insomnia | testar APIs (open source) | `Insomnia.Insomnia` |
| Yaak | testar APIs (open source) | `Yaak.app` |
| Postman | testar APIs | `Postman.Postman` |
| Dataflare | cliente de banco de dados | `Dataflare.Dataflare` |
| Cursor | editor de código com IA (baseado no VS Code) | `Anysphere.Cursor` |
| JetBrains Toolbox | instala as IDEs da JetBrains | `JetBrains.Toolbox` |
| Docker Desktop | containers | `Docker.DockerDesktop` |
| Zed | editor de código muito rápido (open source) | `ZedIndustries.Zed` |
| Go | linguagem Go (open source) | `GoLang.Go` |
| Rustup | instala a linguagem Rust (open source) | `Rustlang.Rustup` |
| Java (Temurin 25) | Java JDK 25 LTS (open source) | `EclipseAdoptium.Temurin.25.JDK` |
| Bun | runtime JavaScript rápido (open source) | `Oven-sh.Bun` |
| HeidiSQL | cliente de MySQL/MariaDB (open source) | `HeidiSQL.HeidiSQL` |
| MongoDB Compass | cliente do MongoDB | `MongoDB.Compass.Full` |
| Ollama | roda modelos de IA no próprio PC (open source) | `Ollama.Ollama` |

### Segurança (4)

| App | O que é | ID |
|---|---|---|
| Bitwarden | gerenciador de senhas (open source) | `Bitwarden.Bitwarden` |
| KeePassXC | gerenciador de senhas offline (open source) | `KeePassXCTeam.KeePassXC` |
| Proton VPN | VPN com plano grátis (open source) | `Proton.ProtonVPN` |
| Malwarebytes | antimalware (segunda opinião ao Defender) | `Malwarebytes.Malwarebytes` |

### Utilitários (15)

| App | O que é | ID |
|---|---|---|
| 7-Zip | compactador de arquivos (open source) | `7zip.7zip` |
| WinRAR | compactador de arquivos (RAR) | `RARLab.WinRAR` |
| Everything | busca arquivos no PC na hora | `voidtools.Everything` |
| AnyDesk | acesso remoto | `AnyDesk.AnyDesk` |
| HWiNFO | informações e sensores do hardware | `REALiX.HWiNFO` |
| CPU-Z | informações do processador e da memória | `CPUID.CPU-Z` |
| WizTree | mostra o que ocupa espaço no disco | `AntibodySoftware.WizTree` |
| Flow Launcher | abre apps e arquivos pelo teclado (open source) | `Flow-Launcher.Flow-Launcher` |
| PowerToys | utilitários da Microsoft (open source) | `Microsoft.PowerToys` |
| ShareX | capturas e gravação de tela (open source) | `ShareX.ShareX` |
| LocalSend | enviar arquivos pela rede local (open source) | `LocalSend.LocalSend` |
| qBittorrent | torrent sem anúncios (open source) | `qBittorrent.qBittorrent` |
| UniGetUI | interface para o WinGet; atualiza tudo (open source) | `Devolutions.UniGetUI` |
| Bulk Crap Uninstaller | desinstala e limpa os restos (open source) | `Klocman.BulkCrapUninstaller` |
| CrystalDiskInfo | saúde do SSD/HD (open source) | `CrystalDewWorld.CrystalDiskInfo` |

</details>

## Desinstalar

```powershell
winget uninstall --id <ID>
```

O **Bulk Crap Uninstaller** (da lista) também remove as pastas e chaves que sobram.
