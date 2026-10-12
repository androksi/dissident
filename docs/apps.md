[← back to README](../README.md)

# Apps

```powershell
.\scripts\apps\Configure-Apps.ps1
```

| Feature | What it does |
|---|---|
| Install WinGet | If WinGet is missing (usually on Windows 10), offers to install it first. |
| App list | 102 apps in categories. ↑ ↓ moves, Space checks, Esc quits. |
| Already installed | Shows "instalado" (installed) next to apps already on the PC. |
| Check category | A key: checks every app in the category (again: unchecks). |
| Search | / key: type the name and the cursor jumps to the app. Enter confirms, Esc cancels. |
| Interactive install | I key: opens the app's own installer so you can choose its options (VS Code comes checked). |
| Confirmation | Shows the chosen apps: "Retornar" (back, default) returns to the list, "Instalar apps" installs. |
| Summary | Shows what was installed, what was already installed and what failed. |
| Adding apps | One line in the script's `$Apps` list (find the ID with `winget search <name>`). |
| Firefox and Thunderbird | Installed in the Windows display language (`Mozilla.Firefox.pt-BR`, `Mozilla.Firefox.de`...). English (US) when Mozilla has no version in that language. Already installed in any language counts as installed. |

## Keys

| Key | Action |
|---|---|
| ↑ ↓ PageUp PageDown Home End | move |
| Space | check / uncheck |
| A | check the whole category |
| I | interactive install |
| / | search by name |
| Enter | continue |
| Esc | quit |

## Full list

<details>
<summary>See all 102 apps</summary>

### Communication (8)

| App | What it is | ID |
|---|---|---|
| Discord | voice and text chat | `Discord.Discord` |
| Telegram | messenger | `Telegram.TelegramDesktop` |
| Signal | encrypted messenger (open source) | `OpenWhisperSystems.Signal` |
| Thunderbird | email client, in the Windows language (open source) | `Mozilla.Thunderbird.<language>` |
| WhatsApp | WhatsApp for desktop (Microsoft Store) | `9NKSQGP7F2NH` (Store) |
| Zoom | video calls | `Zoom.Zoom` |
| Slack | work chat | `SlackTechnologies.Slack` |
| Microsoft Teams | work meetings and chat | `Microsoft.Teams` |

### Design (7)

| App | What it is | ID |
|---|---|---|
| GIMP | image editor (open source) | `GIMP.GIMP.3` |
| Inkscape | vector drawing (open source) | `Inkscape.Inkscape` |
| Krita | digital painting (open source) | `KDE.Krita` |
| Blender | 3D modeling and animation (open source) | `BlenderFoundation.Blender` |
| Figma | interface design | `Figma.Figma` |
| Paint.NET | simple image editor | `dotPDN.PaintDotNet` |
| ScreenToGif | records the screen as a GIF (open source) | `NickeManarin.ScreenToGif` |

### Games (12)

| App | What it is | ID |
|---|---|---|
| Steam | game store and library | `Valve.Steam` |
| Heroic Games Launcher | Epic, GOG and Amazon games (open source) | `HeroicGamesLauncher.HeroicGamesLauncher` |
| NVIDIA App | NVIDIA graphics drivers and settings | `XP8CLZL93F5Z4P` (Store) |
| Epic Games Launcher | Epic's store | `EpicGames.EpicGamesLauncher` |
| EA app | EA's store | `ElectronicArts.EADesktop` |
| Ubisoft Connect | Ubisoft's store | `Ubisoft.Connect` |
| Battle.net | Blizzard's store | `Blizzard.BattleNet` |
| GOG Galaxy | GOG's store | `GOG.Galaxy` |
| MSI Afterburner | FPS and temperatures on screen in games | `Guru3D.Afterburner` |
| Playnite | brings every game library together (open source) | `Playnite.Playnite` |
| Prism Launcher | Minecraft launcher with mods (open source) | `PrismLauncher.PrismLauncher` |
| RetroArch | retro console emulator (open source) | `Libretro.RetroArch` |

### Media (10)

| App | What it is | ID |
|---|---|---|
| Spotify | music (Microsoft Store version) | `9NCBCSZSJRSB` (Store) |
| VLC | plays any video or audio (open source) | `VideoLAN.VLC` |
| OBS Studio | screen recording and streaming (open source) | `OBSProject.OBSStudio` |
| Audacity | audio editor (open source) | `Audacity.Audacity` |
| HandBrake | convert and compress videos (open source) | `HandBrake.HandBrake` |
| Kdenlive | video editor (open source) | `KDE.Kdenlive` |
| Shotcut | simple video editor (open source) | `Meltytech.Shotcut` |
| foobar2000 | lightweight music player | `PeterPawlowski.foobar2000` |
| ImageGlass | fast image viewer (open source) | `DuongDieuPhap.ImageGlass` |
| Stremio | movies and TV shows hub | `Stremio.Stremio` |

### Browsers (7)

| App | What it is | ID |
|---|---|---|
| Brave | browser with an ad blocker | `Brave.Brave` |
| Chrome | Google's browser | `Google.Chrome` |
| Firefox | Mozilla's browser, in the Windows language | `Mozilla.Firefox.<language>` |
| Opera GX | Opera's "gamer" browser | `Opera.OperaGX` |
| Zen Browser | Firefox-based browser with a modern look (open source) | `Zen-Team.Zen-Browser` |
| LibreWolf | privacy-focused Firefox (open source) | `LibreWolf.LibreWolf` |
| Vivaldi | highly customizable browser | `Vivaldi.Vivaldi` |

### Productivity (10)

| App | What it is | ID |
|---|---|---|
| LibreOffice | office suite (open source) | `TheDocumentFoundation.LibreOffice` |
| Joplin | Markdown notes (open source) | `Joplin.Joplin` |
| SumatraPDF | lightweight PDF reader (open source) | `SumatraPDF.SumatraPDF` |
| Claude | Claude desktop app | `Anthropic.Claude` |
| Obsidian | Markdown notes | `Obsidian.Obsidian` |
| Notion | notes, tasks and wikis | `Notion.Notion` |
| Adobe Acrobat Reader | Adobe's PDF reader | `Adobe.Acrobat.Reader.64-bit` |
| Google Drive | syncs Google Drive with the PC | `Google.GoogleDrive` |
| ONLYOFFICE | Office-compatible suite (open source) | `ONLYOFFICE.DesktopEditors` |
| Logseq | connected notes (open source) | `Logseq.Logseq` |

### Development (27)

| App | What it is | ID |
|---|---|---|
| Git | version control (open source) | `Git.Git` |
| GitHub Desktop | Git with a graphical interface | `GitHub.GitHubDesktop` |
| VS Code | code editor | `Microsoft.VisualStudioCode` |
| Node.js LTS | JavaScript outside the browser (open source) | `OpenJS.NodeJS.LTS` |
| fnm | switches between Node.js versions (open source) | `Schniz.fnm` |
| Python 3.14 | Python language (open source) | `Python.Python.3.14` |
| PowerShell 7 | modern PowerShell (open source) | `Microsoft.PowerShell` |
| Windows Terminal | tabbed terminal (built into Windows 11) | `Microsoft.WindowsTerminal` |
| Notepad++ | text editor (open source) | `Notepad++.Notepad++` |
| WinMerge | compare files and folders (open source) | `WinMerge.WinMerge` |
| DBeaver | database client (open source) | `DBeaver.DBeaver.Community` |
| Bruno | API testing, a Postman alternative (open source) | `Bruno.Bruno` |
| Insomnia | API testing (open source) | `Insomnia.Insomnia` |
| Yaak | API testing (open source) | `Yaak.app` |
| Postman | API testing | `Postman.Postman` |
| Dataflare | database client | `Dataflare.Dataflare` |
| Cursor | AI code editor (based on VS Code) | `Anysphere.Cursor` |
| JetBrains Toolbox | installs JetBrains IDEs | `JetBrains.Toolbox` |
| Docker Desktop | containers | `Docker.DockerDesktop` |
| Zed | very fast code editor (open source) | `ZedIndustries.Zed` |
| Go | Go language (open source) | `GoLang.Go` |
| Rustup | installs the Rust language (open source) | `Rustlang.Rustup` |
| Java (Temurin 25) | Java JDK 25 LTS (open source) | `EclipseAdoptium.Temurin.25.JDK` |
| Bun | fast JavaScript runtime (open source) | `Oven-sh.Bun` |
| HeidiSQL | MySQL/MariaDB client (open source) | `HeidiSQL.HeidiSQL` |
| MongoDB Compass | MongoDB client | `MongoDB.Compass.Full` |
| Ollama | runs AI models on your own PC (open source) | `Ollama.Ollama` |

### Security (5)

| App | What it is | ID |
|---|---|---|
| Bitwarden | password manager (open source) | `Bitwarden.Bitwarden` |
| KeePassXC | offline password manager (open source) | `KeePassXCTeam.KeePassXC` |
| Proton VPN | VPN with a free plan (open source) | `Proton.ProtonVPN` |
| Cloudflare One | Cloudflare's WARP and 1.1.1.1 client; free VPN and Zero Trust access | `Cloudflare.Warp` |
| Malwarebytes | anti-malware (second opinion to Defender) | `Malwarebytes.Malwarebytes` |

### Utilities (16)

| App | What it is | ID |
|---|---|---|
| 7-Zip | file archiver (open source) | `7zip.7zip` |
| WinRAR | file archiver (RAR) | `RARLab.WinRAR` |
| Everything | finds files on the PC instantly | `voidtools.Everything` |
| AnyDesk | remote access | `AnyDesk.AnyDesk` |
| HWiNFO | hardware information and sensors | `REALiX.HWiNFO` |
| CPU-Z | processor and memory information | `CPUID.CPU-Z` |
| WizTree | shows what takes up disk space | `AntibodySoftware.WizTree` |
| Flow Launcher | opens apps and files from the keyboard (open source) | `Flow-Launcher.Flow-Launcher` |
| PowerToys | Microsoft utilities (open source) | `Microsoft.PowerToys` |
| ShareX | screenshots and screen recording (open source) | `ShareX.ShareX` |
| LocalSend | send files over the local network (open source) | `LocalSend.LocalSend` |
| qBittorrent | ad-free torrent client (open source) | `qBittorrent.qBittorrent` |
| UniGetUI | interface for WinGet; updates everything (open source) | `Devolutions.UniGetUI` |
| Bulk Crap Uninstaller | uninstalls and cleans up leftovers (open source) | `Klocman.BulkCrapUninstaller` |
| CrystalDiskInfo | SSD/HDD health (open source) | `CrystalDewWorld.CrystalDiskInfo` |
| Unified Remote | control the PC from your phone (server; the app goes on the phone) | `UnifiedIntents.UnifiedRemote` |

</details>

## Moving apps to another PC

```powershell
.\scripts\apps\Backup-Apps.ps1 -Export   # before formatting
.\scripts\apps\Backup-Apps.ps1 -Import   # after formatting
```

Export saves `tidywin-apps-<PC>-<date>.json` with every app WinGet knows (Desktop, Documents, Downloads, OneDrive or a folder you type). Import finds the newest file in those folders, lists the apps and installs the ones that are missing. Only apps are saved, not their settings.

## Uninstalling

```powershell
winget uninstall --id <ID>
```

**Bulk Crap Uninstaller** (in the list) also removes leftover folders and registry keys.
