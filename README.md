# dissident

PowerShell scripts that remove telemetry and preinstalled apps from Windows 10 and 11, install common apps with WinGet, and apply privacy policies to Chrome, Brave and Firefox.

[![Lint](https://github.com/androksi/dissident/actions/workflows/lint.yml/badge.svg)](https://github.com/androksi/dissident/actions/workflows/lint.yml)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

> [!NOTE]
> The scripts' prompts and messages are in Brazilian Portuguese.

## Usage

Run in PowerShell. Administrator rights are requested automatically.

```powershell
irm androksi.github.io/dissident/<name> | iex
```

| Name | Script | Undo |
|---|---|---|
| `windows` | Privacy, cleanup and personalization | `windows-revert` |
| `apps` | Install apps with WinGet | — |
| `chrome` | Chrome policies | `chrome-revert` |
| `brave` | Brave policies | `brave-revert` |
| `firefox` | Firefox policies and extensions | `firefox-revert` |

The script is downloaded to `%TEMP%\dissident` and deleted after it runs. To run from a local copy instead, use the files in [`scripts/`](scripts) as Administrator.

## Documentation

- [Windows](docs/windows.md)
- [Apps](docs/apps.md)
- [Browsers](docs/browsers.md)

## Notes

- `Configure-Windows` creates a restore point before making changes.
- Windows Defender, Windows Firewall, Windows Update and Safe Browsing are left untouched.
- Every script can be run more than once.

Requires Windows 10 or 11 with Windows PowerShell 5.1.

## License

[GPL-3.0](LICENSE). Provided as is, without warranty.
