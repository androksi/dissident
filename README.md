<div align="center">

<img src="assets/logo.svg" width="120" alt="dissident">

# dissident

**Your PC. Your rules.**

Scripts for a Windows that works for you — no telemetry, no junk, no asking for permission.

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0d1117?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-0d1117?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-0d1117?style=flat-square)
[![Lint](https://github.com/androksi/dissident/actions/workflows/lint.yml/badge.svg)](https://github.com/androksi/dissident/actions/workflows/lint.yml)

</div>

<!-- Record a GIF of the menu with ScreenToGif, save it as assets/demo.gif and uncomment:
<p align="center"><img src="assets/demo.gif" width="720" alt="demo"></p> -->

---

> [!NOTE]
> The scripts' prompts and messages are in Brazilian Portuguese.

## Quick start

Open **PowerShell** (Win + X → Terminal) and paste a command. Nothing to download; it asks for administrator rights on its own.

```powershell
irm androksi.github.io/dissident/windows | iex
irm androksi.github.io/dissident/apps    | iex
irm androksi.github.io/dissident/chrome  | iex
irm androksi.github.io/dissident/brave   | iex
irm androksi.github.io/dissident/firefox | iex
```

To undo, add `-revert` to the name: `windows-revert`, `chrome-revert`, `brave-revert` or `firefox-revert`.
List with copy buttons: [androksi.github.io/dissident](https://androksi.github.io/dissident).

The script is downloaded to `%TEMP%\dissident`, runs, and the folder is deleted at the end.

<details>
<summary>Run from a downloaded copy of the repository</summary>

Download the repository (**Code → Download ZIP**, or `git clone`), extract it and open **Terminal as Administrator** in the folder:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\Configure-Windows.ps1
```

</details>

Every question has a default — just pressing **Enter** picks the recommended choice.
Every script can be run more than once safely.

## Scripts

| Script | What it does | Details |
|---|---|---|
| `scripts/windows/Configure-Windows.ps1` | Telemetry, junk apps, OneDrive, Edge, theme, taskbar, File Explorer, encrypted DNS and more — all through questions | [docs/windows.md](docs/windows.md) |
| `scripts/windows/Revert-Configure-Windows.ps1` | Undoes what Configure-Windows changed | [docs/windows.md](docs/windows.md#revert) |
| `scripts/apps/Configure-Apps.ps1` | A list of 100 apps to pick and install with WinGet | [docs/apps.md](docs/apps.md) |
| `scripts/browsers/Configure-Brave.ps1` | Brave without Wallet, VPN, Rewards, Leo, News and telemetry | [docs/browsers.md](docs/browsers.md#brave) |
| `scripts/browsers/Configure-Chrome.ps1` | Chrome without telemetry and AI, with Google sign-in still working | [docs/browsers.md](docs/browsers.md#chrome) |
| `scripts/browsers/Configure-Firefox.ps1` | Firefox without telemetry, sponsored content and AI, with uBlock Origin and Bitwarden | [docs/browsers.md](docs/browsers.md#firefox) |

To undo a browser: run the same script with `-Revert`.

## Recommended order after a fresh install

1. Windows Update until nothing else shows up (including *Optional updates*)
2. Manufacturer drivers (graphics card through the vendor's app)
3. Microsoft Store → *Get updates*
4. Restart
5. `Configure-Windows.ps1` → `Configure-Apps.ps1` → browser scripts

## What it does **not** do

- Does not turn off Windows Defender, the Firewall or Safe Browsing
- Does not block or delay Windows Update
- Does not touch drivers, power settings or hibernation
- Does not install anything behind your back — `Configure-Apps` only installs what you pick
- Does not use performance "tweaks" with no real effect (services set to manual, power plans, "magic" registry keys)

Before changing anything, `Configure-Windows` creates a **restore point**.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built into Windows), run as Administrator
- `Configure-Apps`: WinGet (the script offers to install it if missing)

## Disclaimer

These scripts change system settings and remove apps. Read what each one does before running it.
Use at your own risk: there is no warranty of any kind (see the license).

## License

[GPL-3.0](LICENSE). You may use, modify and redistribute it; if you distribute a modified version, it must also be GPL-3.0 with its source code available.
