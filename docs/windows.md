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
| OneDrive | Uninstalls OneDrive and keeps it from coming back. |
| Edge | Edge policies: no telemetry, background mode, sidebar, Copilot or shopping. |
| Windows Security | Turns on blocking of potentially unwanted apps and downloads, and hides unimportant notifications. |
| C: folders | Hides `inetpub` and deletes `PerfLogs`. |
| Device apps | Doesn't download manufacturer apps and icons when devices are connected (drivers still come). |
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
| No recent files | Hides recent files in File Explorer. |
| Hidden files | Shows hidden files and folders. |
| No folder discovery | Large folders open faster. Resets custom folder views. |
| No Home/Gallery | Removes Home and Gallery from File Explorer, which then opens in "This PC". |
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
| Volume 100% | Sets the current audio device volume to 100%. |
| Verbose blue screen | Shows the technical error details on the blue screen. |

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

## Revert

```powershell
.\scripts\windows\Revert-Configure-Windows.ps1
```

| Feature | What it does |
|---|---|
| Revert | Undoes telemetry, policies, suggestions, border, DNS, Edge, Windows Security areas, Home/Gallery, folder discovery, devices, blue screen and `inetpub`. |
| Not reverted | Removed apps, OneDrive, theme, taskbar, extensions, volume, hidden files and battery (undo through Settings). |
