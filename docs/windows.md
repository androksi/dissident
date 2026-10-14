[← back to README](../README.md)

# Windows

In the [TidyWin panel](../README.md#quick-start): **Set up → Windows**. From a local copy:

```powershell
.\scripts\windows\configure-windows.ps1
```

Every option shows on one page, in tabs. **Nothing comes selected**: only what you turn on or pick is applied, the rest stays as it is. **Review** lists what will change; nothing changes before **Apply**.

## Automatic
| Feature | What it does |
|---|---|
| Restore point | Creates a restore point before any change. |
| Review | Lists everything that will change, by tab, before you apply. |
| Fault tolerant | If a step fails, it warns and moves on to the next one. |
| Detailed log | One line per setting: `[OK]` changed now, `[--]` it already was like that. At the end, a summary with how many changed, were already set or failed. |
| Log file | Everything shown while applying, plus your answers, is saved to `TidyWin log <date>.txt` on the Desktop. No user or PC name in it, so it can be sent when asking for help. |

## Privacy and cleanup
| Feature | What it does |
|---|---|
| Telemetry | Turns off the telemetry service and collection tasks, and applies the policies for minimum diagnostics, no ads, no activity history and no Bing in search. Turns off Widgets. |
| Suggestions | Turns off suggestions, ads and silent app installs (Candy Crush etc.). |
| Apps to remove | A checklist with only the apps on this PC. **Checked**: rarely used ones (Clipchamp, Copilot, Bing, Solitaire, LinkedIn, Teams, new Outlook, Paint 3D...). **Unchecked**: ones some people use (Phone Link, Sticky Notes, Clock, Media Player, OneNote, Snipping Tool) and Xbox (Xbox app, Game Bar, Xbox sign-in, Gaming Services: Game Pass games and games with Xbox sign-in stop working). Removing the Snipping Tool frees the Print Screen key for ShareX; removing Xbox apps turns off Game DVR. Removed for every user and for new accounts. |
| OneDrive | Uninstalls OneDrive and keeps it from coming back. |
| Edge | Edge policies: no telemetry, background mode, sidebar, Copilot or shopping. |
| Recall | Windows 11: removes Recall and stops it from being turned on (official policies). Only exists on Copilot+ PCs. |
| Edge shortcut | Deletes the Edge desktop shortcut and stops Edge updates from creating it again. |
| Windows Security | Turns on blocking of potentially unwanted apps and downloads, and hides unimportant notifications. |
| C: folders | Hides `inetpub` and deletes `PerfLogs`. |
| Device apps | Doesn't download manufacturer apps and icons when devices are connected (drivers still come). |
| WPBT | Stops Windows from running programs the motherboard firmware provides at boot (how Armoury Crate, Vantage and similar install themselves). A Windows registry setting only: the BIOS is not changed, and a fresh install allows it again. To stop it for good, turn off the matching BIOS option (e.g. ASUS "Armoury Crate", Lenovo "Vantage"). Some anti-theft software (Computrace) uses WPBT too. |
| Hide areas | Hides "Account protection" and "Device security" in Windows Security (Microsoft account nags). |

## Personalization
| Feature | What it does |
|---|---|
| Theme | Light or dark. Turns off Windows Spotlight and applies the theme's wallpaper. |
| Screen | For each monitor: resolution, refresh rate and scale, from the ones the monitor supports, with the recommended and current ones marked. Nothing picked: nothing changes. After a resolution or refresh change, Enter keeps it; otherwise it goes back by itself in 15 seconds. |
| Taskbar | Icons centered or on the left. |
| Search | Hidden, icon only or search box. |
| Task View | Show or hide the button. |
| No pins | Removes every pinned icon from the taskbar. |
| No Start ads | Unpins only the ad shortcuts from Start (LinkedIn, Spotify, TikTok, Solitaire, Candy Crush...); everything else pinned stays. |
| Battery % | Shows the battery percentage on the taskbar (laptops only). |
| Extensions | Shows file extensions. |
| No frequent folders | Hides frequent folders in Quick access. |
| No Music in Quick access | Unpins the Music folder from Quick access (the folder stays). |
| No recent files | Hides recent files in File Explorer. |
| Hidden files | Shows hidden files and folders. |
| No folder discovery | Large folders open faster. Resets custom folder views. |
| No Home/Gallery | Removes Home and Gallery from File Explorer, which then opens in "This PC". |
| Classic menu | Windows 11: the full right-click menu, without "Show more options". |
| No Snap | Turns off "Snap windows": no snapping to the screen edges and no Snap layouts. |
| Thin border | Shrinks the invisible window resize area. |

## Everyday use
| Feature | What it does |
|---|---|
| Long paths | Allows paths longer than 260 characters. |
| End task | Adds "End task" when right-clicking an app on the taskbar. |
| Sudo | Turns on `sudo` in the terminal. |
| Win+V history | Turns on clipboard history. |
| No acceleration | Turns off mouse acceleration. |
| No Sticky Keys | Turns off the Sticky Keys shortcut (Shift 5 times). |
| Num Lock | Num Lock on when Windows starts, sign-in screen included. |
| No Fast Startup | "Shut down" really shuts down instead of hibernating part of Windows. Startup is a few seconds slower. |
| Volume 100% | Sets the current audio device volume to 100%. |
| Verbose blue screen | Shows the technical error details on the blue screen. |

## Power
| Feature | What it does |
|---|---|
| Screen, sleep and hibernation | Choose when to turn off the screen, sleep and hibernate, plugged in and (laptops) on battery, from 1 minute to never. Each one shows the current value; the ones you leave empty stay as they are. Hibernation is only asked if it is turned on. Applies to the active power plan, like Settings → System → Power. |

## Network
| Feature | What it does |
|---|---|
| DNS | Sets IPv4 and IPv6 DNS manually, with DNS over HTTPS (automatic template) on Windows 11. |

## Cleanup

In the [TidyWin panel](../README.md#quick-start): **Maintenance → Disk space**. From a local copy:

```powershell
.\scripts\windows\clean-windows.ps1
```

Measures each item and shows a switch for each one with its size, all off. Only what you turn on is deleted; at the end it shows how much space was freed.

| Item | Default | What it deletes |
|---|---|---|
| Your temporary files | Yes | The %TEMP% folder. |
| Windows temporary files | Yes | C:\Windows\Temp. |
| Windows Update downloads | Yes | Updates already installed. Skipped while an update is installing or waiting for a restart. |
| Delivery Optimization cache | Yes | Update copies kept to share with other PCs. |
| Error reports and memory dumps | Yes | App crash reports and blue screen dumps. |
| Thumbnail and icon cache | No | Rebuilt by Windows; File Explorer restarts. |
| Recycle Bin | No | Everything in it, on every drive. |
| Old Windows components | No | Old system files left by updates (DISM). Can take minutes. Skipped while an update is pending. |
| Windows.old | No | The previous Windows installation, if present. No going back after it. |

## Repair

In the [TidyWin panel](../README.md#quick-start): **Maintenance → Fix Windows**. From a local copy:

```powershell
.\scripts\windows\repair-windows.ps1
```

For when Windows acts strange. Creates a restore point, checks the Windows image with DISM and repairs it from Windows Update only if it is damaged, runs `sfc /scannow`, and checks the disk online. Each step is a switch, all off, plus one to schedule the disk fix at the next restart and one to go on if Windows can't create the restore point. Only Windows' own tools; your files, apps and settings are not touched. Takes 10 to 30 minutes.

## Network reset

In the [TidyWin panel](../README.md#quick-start): **Maintenance → Network**.

For "connected, no internet", sites that don't open or a connection that keeps dropping. The page shows the network adapters (connected or not, and the DNS set by hand that will be kept) and how far to go, nothing picked:

| Option | What it does |
|---|---|
| Quick | Clears the DNS and ARP caches and gets a new IP from the router. No restart. |
| Full | Also resets Winsock and TCP/IP (IPv4 and IPv6). Needs a restart, which a switch can do at the end. On a PC with a manual IP, the TCP/IP reset is skipped so the IP is not erased. |

Full: DNS servers set by hand and DNS over HTTPS are saved to `%ProgramData%\TidyWin\network-reset` first and put back right after the reset. Not used: Settings' *Network reset* (it removes the adapters and VPNs) and proxy resets. The connection drops for a few seconds; the internet is tested at the end.

## Revert

In the [TidyWin panel](../README.md#quick-start): **Undo → Windows**. From a local copy:

```powershell
.\scripts\windows\revert-configure-windows.ps1
```

| Feature | What it does |
|---|---|
| Revert | A page with one switch per subject, all off: only what you turn on is undone. Covers telemetry, policies, suggestions, border, Snap windows, DNS, Game DVR, the Print Screen key, the Start ad shortcuts (when the app is installed), Recall, Edge (including the shortcut policy), Windows Security areas, WPBT, Fast Startup, Num Lock, Home/Gallery, Music in Quick access, classic right-click menu, folder discovery, devices, blue screen, `inetpub` and update sharing. |
| Not reverted | Removed apps (Xbox and Snipping Tool included; reinstall from the Microsoft Store), OneDrive, screen resolution, refresh rate and scale, screen and sleep times, theme, taskbar, extensions, volume, hidden files and battery (undo through Settings). |
