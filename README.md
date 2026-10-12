# TidyWin Windows Utility

TidyWin **cleans up** Windows 10 and 11 (telemetry, preinstalled apps, ads), **installs** apps and fonts, **configures** Chrome, Brave and Firefox for privacy and **keeps** the PC in shape afterwards.

[![Lint](https://img.shields.io/github/actions/workflow/status/androksi/tidywin/lint.yml?branch=main&label=lint&style=for-the-badge)](https://github.com/androksi/tidywin/actions/workflows/lint.yml)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge)](#good-to-know)
[![License](https://img.shields.io/github/license/androksi/tidywin?style=for-the-badge)](LICENSE)

---

![The TidyWin menu in Windows PowerShell](assets/banner.svg)

## Quick Start

Right-click the Start button, choose **Terminal** (or PowerShell) and run:

```powershell
irm androksi.github.io/tidywin/run | iex
```

It asks for administrator rights and the language (English or Portuguese), then opens the menu: pick an option with the arrows and press <kbd>Enter</kbd>. When it finishes, you're back in the menu.

> [!TIP]
> Formatting the PC? Follow [Reinstalling Windows, step by step](docs/reinstall.md): it lists the menu options in the right order.

## What's in the menu

| Option | What it does | Details |
|---|---|---|
| **Set up** | | |
| Windows | Removes telemetry, ads, preinstalled apps and OneDrive; adjusts the taskbar, File Explorer, power and DNS. Asks before each change. | [Options](docs/windows.md) |
| Install apps | Pick from 104 apps and install them with WinGet. | [List](docs/apps.md) |
| Install fonts | Pick fonts for code, the terminal and text, and install them. | [List](docs/fonts.md) |
| Chrome · Brave · Firefox | Privacy settings: no telemetry, AI features or ads. | [Policies](docs/browsers.md) |
| Development | Editors, Git, SSH key for GitHub, Windows Terminal, languages and WSL. | [Steps](docs/dev.md) |
| Wallpapers | Pick wallpapers and download them. | [Gallery](docs/wallpapers.md) |
| **Maintenance** | | |
| PC report | Only reads: a page with Windows, activation, TPM/Secure Boot, disks, battery, drivers and crashes. Safe to share. | [Details](docs/windows.md#report) |
| Check after a Windows update | Finds what a big update brought back and reapplies it. | [Details](docs/windows.md#check) |
| Uninstall programs | With their official uninstaller, then shows the leftovers before deleting them. | [Details](docs/apps.md#uninstalling) |
| Free up disk space | Temporary files, update downloads and more, asking before each item. | [Details](docs/windows.md#cleanup) |
| Repair Windows | Repairs system files and the disk with Windows' own tools. | [Details](docs/windows.md#repair) |
| Reset the network | Fixes "connected, no internet" with Windows' own commands, keeping your DNS. | [Details](docs/windows.md#network-reset) |
| **Formatting the PC** | | |
| Before / After: apps | Saves your app list before formatting and installs it back afterwards. | [Details](docs/apps.md#moving-apps-to-another-pc) |
| Before / After: drivers | Saves the drivers you pick and installs back the ones Windows didn't. | [Details](docs/drivers.md) |
| **Undo** | Windows, the browsers, Development and fonts. | |

## Good to know

- Needs Windows 10 or 11 and Administrator rights (requested automatically). Windows PowerShell 5.1 comes with Windows.
- Every option asks before changing anything; Windows creates a restore point first.
- Windows Defender, Firewall, Windows Update and Safe Browsing are never touched.
- Everything can be run again safely.
- Nothing stays on the PC: the scripts are downloaded to `%TEMP%\tidywin` and deleted when the menu closes.

<details>
<summary>Run from a local copy</summary>

```powershell
git clone https://github.com/androksi/tidywin
cd tidywin
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\TidyWin.ps1
```

Run as Administrator. The menu uses the scripts next to it instead of downloading them. Each script also runs on its own (for example `.\scripts\windows\Get-Report.ps1`); the browser, `dev` and `fonts` scripts accept `-Revert`, and `windows` is undone by `Revert-Configure-Windows.ps1`.

</details>

---

[Changelog](CHANGELOG.md) · [Report an issue](https://github.com/androksi/tidywin/issues) · [GPL-3.0](LICENSE), provided as is, without warranty.
