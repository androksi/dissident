<div align="center">

<img src="assets/logo.svg" width="80" alt="">

# tidywin

Removes telemetry and preinstalled apps from Windows 10 and 11, installs apps with WinGet<br>and applies privacy policies to Chrome, Brave and Firefox.

[![Lint](https://github.com/androksi/tidywin/actions/workflows/lint.yml/badge.svg)](https://github.com/androksi/tidywin/actions/workflows/lint.yml)
![Windows 10 | 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

<br>

<img src="assets/banner.svg" width="820" alt="tidywin running in Windows PowerShell">

</div>

## Usage

Run in PowerShell. Administrator rights are requested automatically.

```powershell
irm androksi.github.io/tidywin/<name> | iex
```

| Name | What it does | Undo |
|---|---|---|
| `windows` | Telemetry, preinstalled apps, OneDrive, Edge, taskbar, File Explorer, DNS | `windows-revert` |
| `apps` | Pick and install from 100 apps with WinGet | — |
| `chrome` | Telemetry, AI features, third-party cookies | `chrome-revert` |
| `brave` | Wallet, VPN, Rewards, Leo, News, telemetry | `brave-revert` |
| `firefox` | Telemetry, sponsored content, AI; installs uBlock Origin and Bitwarden | `firefox-revert` |

The script is downloaded to `%TEMP%\tidywin` and deleted after it runs.
The scripts' prompts and messages are in Brazilian Portuguese.

<details>
<summary>Run from a local copy</summary>

```powershell
git clone https://github.com/androksi/tidywin
cd tidywin
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\Configure-Windows.ps1
```

Run as Administrator. Browser scripts accept `-Revert`.

</details>

## Documentation

- [Windows](docs/windows.md): every option of `Configure-Windows` and what the revert script undoes
- [Apps](docs/apps.md): full app list, keys and how to uninstall
- [Browsers](docs/browsers.md): policies applied to Chrome, Brave and Firefox

## Notes

- `Configure-Windows` creates a restore point before making changes.
- Windows Defender, Windows Firewall, Windows Update and Safe Browsing are left untouched.
- Every script can be run more than once.
- Requires Windows 10 or 11 with Windows PowerShell 5.1.

## License

[GPL-3.0](LICENSE). Provided as is, without warranty.
