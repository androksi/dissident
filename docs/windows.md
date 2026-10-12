[← back to README](../README.md)

# Windows

```powershell
.\scripts\windows\Configure-Windows.ps1
```

All questions come first; then a summary and a confirmation.
To use only the defaults, with no questions: `-NoPrompt`.

## Automatic
| Feature | What it does |
|---|---|
| Restore point | Creates a restore point before any change. |
| Summary | Shows everything that was chosen and asks "Aplicar agora?" (apply now?). |
| Fault tolerant | If a step fails, it warns and moves on to the next one. |

## Privacy and cleanup
| Feature | What it does |
|---|---|
| Telemetry | Turns off the telemetry service and collection tasks, and applies the policies for minimum diagnostics, no ads, no activity history and no Bing in search. Turns off Widgets. |
| Suggestions | Turns off suggestions, ads and silent app installs (Candy Crush etc.). |
| Junk apps | Removes Clipchamp, Bing, Solitaire, Teams, the new Outlook, Copilot and others. |
| Optional apps | Also removes Phone Link, Sticky Notes, Sound Recorder, Clock, Quick Assist, Media Player and OneNote. |
| Xbox | Removes the Xbox app, Game Bar, Xbox sign-in and Gaming Services, and turns off Game DVR. Store/Game Pass games and games with Xbox sign-in stop working; Steam, Epic and Riot don't. Default no. |
| Snipping Tool | Removes the Snipping Tool (Snip & Sketch on Windows 10) and frees the Print Screen key for another app such as ShareX. Win+Shift+S stops working. Default no. |
| OneDrive | Uninstalls OneDrive and keeps it from coming back. |
| Edge | Edge policies: no telemetry, background mode, sidebar, Copilot or shopping. |
| Recall | Windows 11: removes Recall and stops it from being turned on (official policies). Only exists on Copilot+ PCs. |
| Edge shortcut | Deletes the Edge desktop shortcut and stops Edge updates from creating it again. |
| Windows Security | Turns on blocking of potentially unwanted apps and downloads, and hides unimportant notifications. |
| C: folders | Hides `inetpub` and deletes `PerfLogs`. |
| Device apps | Doesn't download manufacturer apps and icons when devices are connected (drivers still come). |
| WPBT | Stops Windows from running programs the motherboard firmware provides at boot (how Armoury Crate, Vantage and similar come back after formatting). Default no: some PCs use it for a network driver or anti-theft. |
| Hide areas | Hides "Account protection" and "Device security" in Windows Security (Microsoft account nags). |

## Personalization
| Feature | What it does |
|---|---|
| Theme | Keep, Windows light or Windows dark. Turns off Windows Spotlight and applies the theme's wallpaper. |
| Taskbar | Keep, icons centered or on the left. |
| Search | Keep, hidden, icon only or search box. |
| Task View | Keep, show or hide the button. |
| No pins | Removes every pinned icon from the taskbar. |
| Battery % | Shows the battery percentage on the taskbar (laptops only). |
| Extensions | Shows file extensions. |
| No frequent folders | Hides frequent folders in Quick access. |
| No Music in Quick access | Unpins the Music folder from Quick access (the folder stays). |
| No recent files | Hides recent files in File Explorer. |
| Hidden files | Shows hidden files and folders. |
| No folder discovery | Large folders open faster. Resets custom folder views. |
| No Home/Gallery | Removes Home and Gallery from File Explorer, which then opens in "This PC". |
| Classic menu | Windows 11: the full right-click menu, without "Show more options". |
| No Snap | Turns off "Snap windows": no snapping to the screen edges and no Snap layouts. Default no. |
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
| No Fast Startup | "Shut down" really shuts down instead of hibernating part of Windows. Startup is a few seconds slower. Default no. |
| Volume 100% | Sets the current audio device volume to 100%. |
| Verbose blue screen | Shows the technical error details on the blue screen. |

## Power
| Feature | What it does |
|---|---|
| Screen, sleep and hibernation | Default: keep as is. Or choose when to turn off the screen, sleep and hibernate, plugged in and (laptops) on battery, from 1 minute to never. Each menu starts at the current value. Hibernation is only asked if it is turned on. Applies to the active power plan, like Settings → System → Power. |

## Network
| Feature | What it does |
|---|---|
| DNS | Sets IPv4 and IPv6 DNS manually, with DNS over HTTPS (automatic template) on Windows 11. |

## Check

```powershell
.\scripts\windows\Configure-Windows.ps1 -Check
```

Compares the PC with the answers saved the last time you ran `Configure-Windows` (in `%ProgramData%\TidyWin`), shows what came back after a Windows update and asks whether to reapply only that. Personalization is not checked.

## Cleanup

```powershell
.\scripts\windows\Clean-Windows.ps1
```

Measures each item, asks before deleting each one and shows how much space was freed.

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

```powershell
.\scripts\windows\Repair-Windows.ps1
```

For when Windows acts strange. Creates a restore point, checks the Windows image with DISM and repairs it from Windows Update only if it is damaged, runs `sfc /scannow`, and checks the disk online (asks before scheduling a fix at the next restart). Only Windows' own tools; your files, apps and settings are not touched. Takes 10 to 30 minutes.

## Revert

```powershell
.\scripts\windows\Revert-Configure-Windows.ps1
```

| Feature | What it does |
|---|---|
| Revert | Undoes telemetry, policies, suggestions, border, Snap windows, DNS, Game DVR, the Print Screen key, Recall, Edge (including the shortcut policy), Windows Security areas, WPBT, Fast Startup, Num Lock, Home/Gallery, Music in Quick access, classic right-click menu, folder discovery, devices, blue screen and `inetpub`. |
| Not reverted | Removed apps (Xbox and Snipping Tool included; reinstall from the Microsoft Store), OneDrive, screen and sleep times, theme, taskbar, extensions, volume, hidden files and battery (undo through Settings). |
