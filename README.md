# TidyWin Windows Utility

TidyWin **cleans up** Windows 10 and 11 (telemetry, preinstalled apps, ads), **installs** apps and fonts, **configures** Chrome, Brave and Firefox for privacy and **keeps** the PC in shape afterwards.

[![Lint](https://img.shields.io/github/actions/workflow/status/androksi/tidywin/lint.yml?branch=main&label=lint&style=for-the-badge)](https://github.com/androksi/tidywin/actions/workflows/lint.yml)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge)](#good-to-know)
[![License](https://img.shields.io/github/license/androksi/tidywin?style=for-the-badge)](LICENSE)

---

![TidyWin running in Windows PowerShell](assets/banner.svg)

## Quick Start

1. Right-click the Start button and choose **Terminal** (or PowerShell).
2. Run a command. For example, to clean up Windows:

```powershell
irm androksi.github.io/tidywin/windows | iex
```

To run another one, replace `windows` with any command from the table below. Every command, with a copy button: [androksi.github.io/tidywin](https://androksi.github.io/tidywin).

> [!TIP]
> Formatting the PC? Follow [Reinstalling Windows, step by step](docs/reinstall.md): it lists the commands in the right order.

## Commands

| Command | What it does | Details |
|---|---|---|
| `windows` | Removes telemetry, ads, preinstalled apps and OneDrive; adjusts the taskbar, File Explorer, power and DNS. Asks before each change. | [Options](docs/windows.md) |
| `apps` | Pick from 104 apps and install them with WinGet. | [List](docs/apps.md) |
| `fonts` | Pick fonts for code, the terminal and text, and install them. | [List](docs/fonts.md) |
| `chrome` `brave` `firefox` | Privacy settings: no telemetry, AI features or ads. | [Policies](docs/browsers.md) |
| `dev` | Editors, Git, SSH key for GitHub, Windows Terminal, languages and WSL. | [Steps](docs/dev.md) |
| `wallpapers` | Pick wallpapers and download them. | [Gallery](docs/wallpapers.md) |

**Maintenance**

| Command | What it does |
|---|---|
| `windows-check` | After a big Windows update: finds what came back and reapplies it. |
| `cleanup` | Frees disk space, asking before each item. |
| `repair` | Repairs system files and the disk with Windows' own tools. |
| `apps-export` / `apps-import` | Saves your app list before formatting and installs it back afterwards. |

**Undo:** add `-revert` to `windows`, `chrome`, `brave`, `firefox`, `dev` or `fonts`, as in `irm androksi.github.io/tidywin/windows-revert | iex`.

## Good to know

- Needs Windows 10 or 11 and Administrator rights (requested automatically). Windows PowerShell 5.1 comes with Windows.
- `windows` creates a restore point before changing anything.
- Windows Defender, Firewall, Windows Update and Safe Browsing are never touched.
- Every command can be run again safely and asks for the language first: English or Portuguese.
- Nothing stays on the PC: the script is downloaded to `%TEMP%\tidywin` and deleted after it runs.

<details>
<summary>Run from a local copy</summary>

```powershell
git clone https://github.com/androksi/tidywin
cd tidywin
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\Configure-Windows.ps1
```

Run as Administrator. The browser, `dev` and `fonts` scripts accept `-Revert`; `windows` is undone by `Revert-Configure-Windows.ps1`.

</details>

---

[Changelog](CHANGELOG.md) · [Report an issue](https://github.com/androksi/tidywin/issues) · [GPL-3.0](LICENSE), provided as is, without warranty.
