[← back to README](../README.md)

# Apps

In the [TidyWin panel](../README.md#quick-start): **Set up → Apps**. From a local copy:

```powershell
.\scripts\apps\configure-apps.ps1
```

| Feature | What it does |
|---|---|
| App list | 105 apps, a tab per category. Nothing comes selected. |
| Already installed | Marked **Installed** in green. Choosing one updates it if there is a newer version. |
| Interactive | Next to each app (not the Microsoft Store ones): opens the app's own installer, so you choose its options, like VS Code's "Open with Code". |
| Review | Lists the chosen apps before you install them. |
| Install WinGet | If WinGet is missing (usually on Windows 10), it is installed first. |
| Summary | Shows what was installed, what was already installed and what failed. |
| Adding apps | One line in the script's `$Apps` list (find the ID with `winget search <name>`). |
| Firefox and Thunderbird | Installed in the Windows display language (`Mozilla.Firefox.pt-BR`, `Mozilla.Firefox.de`...). English (US) when Mozilla has no version in that language. Already installed in any language counts as installed. |

## Keys, when run directly

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
<summary>See all 105 apps</summary>

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

### Utilities (19)

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
| Lenovo Vantage | updates and settings for Lenovo PCs (Microsoft Store) | `9WZDNCRFJ4MV` |
| Visual C++ 2015-2022 | runtime most programs and games need (x64 + x86; also arm64 on ARM PCs) | `Microsoft.VCRedist.2015+.x86`, `.x64`, `.arm64` |
| Visual C++ 2005-2013 | older runtimes, for older games and programs (x64 + x86) | `Microsoft.VCRedist.<2005, 2008, 2010, 2012, 2013>.x86` and `.x64` |

</details>

## Moving apps to another PC

In the [TidyWin panel](../README.md#quick-start): **Back up → Create** and **Back up → Restore**, with **Apps** on. [How the backup works](backup.md). From a local copy:

```powershell
.\scripts\apps\backup-apps.ps1 -Export   # before formatting
.\scripts\apps\backup-apps.ps1 -Import   # after formatting
```

Export saves `apps.json`, with every app WinGet knows, in the `tidywin-backup-<PC>-<date>` folder. Import finds that folder and installs the apps that are missing. Only apps are saved, not their settings.

## Uninstalling

In the [TidyWin panel](../README.md#quick-start): **Maintenance → Remove apps**.

| Step | What it does |
|---|---|
| Programs | The same list as Settings → Apps → Installed apps, without system components and updates, with a search box. Nothing checked. |
| Uninstall | Warns about programs still open, creates a restore point, then runs each program's **official uninstaller**, one at a time, with its own window. Nothing is forced; cancelling keeps the program. |
| Leftovers | **Remove leftovers**, a checkbox at the bottom of the page, next to Review, off at first. On: once the uninstallers finish, what is **certainly theirs** goes right away (the install folder that remained, under 1 GB; broken shortcuts; empty Start menu folders; scheduled tasks of the program). What **only might be theirs** (folders and registry keys with the program's name, big install folders, usually your data, folders named after the publisher, anything of a program whose uninstaller was missing, and anything too big for the Recycle Bin) shows in a list at the end, nothing checked: only what you check is deleted. |
| Never touched | Windows, Program Files/ProgramData/AppData themselves, Common Files, Microsoft folders, your Desktop/Documents/Downloads, links, and anything an installed program still uses. |
| Delete | Folders and shortcuts go to the **Recycle Bin**; what doesn't fit is only deleted for good when you check it in the list, which says so. Registry keys and scheduled tasks are exported first to `%ProgramData%\TidyWin\uninstall-backup\<date>`, with a `deleted.txt` listing everything: double-click a `.reg` file to put a key back. |

Microsoft Store apps are not listed: remove them from Settings, or with the panel's Windows option.
