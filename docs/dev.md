[← back to README](../README.md)

# Developer setup

In the [TidyWin menu](../README.md#quick-start): **Set up → Development**. From a local copy:

```powershell
.\scripts\dev\Configure-Dev.ps1
```

Meant to run after Windows, drivers, apps and browsers are set up. Every question comes first, then a summary and a confirmation. Safe to run again: what is already done is skipped. A log is saved in `%LOCALAPPDATA%\TidyWin`.

| Step | Default | What it does |
|---|---|---|
| Editors and IDEs | VS Code | Checklist: VS Code (interactive installer), Cursor, Zed, JetBrains Toolbox, Sublime Text, Neovim. |
| Git | Install if missing | Name and e-mail (kept if already set), `main` branch, long paths, `autocrlf`, `fetch.prune`, credential manager. |
| GitHub CLI | Yes | Installs `gh`. |
| SSH key | Yes | Creates `~\.ssh\id_ed25519` (an existing key is reused, never replaced), with an optional passphrase. |
| ssh-agent | With the key | Windows ssh-agent service on, key added, Git set to use Windows' OpenSSH. |
| Send to GitHub | GitHub CLI | Through `gh`, by pasting on the site, or not now. Then tests `ssh -T git@github.com`. |
| Remove old keys | Yes | With GitHub CLI: deletes from GitHub older keys this script sent from the same PC name ("<PC> (TidyWin)"). Other keys are never touched. |
| Signed commits | Yes | Commits and tags signed with the SSH key ("Verified" on GitHub). |
| Windows Terminal | Yes | Installs if missing; default terminal on Windows 11 22H2+. |
| PowerShell 7 | Yes | Installs if missing and makes it the Terminal's default profile. |
| Font | CaskaydiaCove | Nerd Font from the official release, for your user; set in Windows Terminal (settings backed up first). |
| Developer Mode | Yes | Symbolic links without administrator rights. |
| Languages | None | Checklist: Node.js LTS, Python, Go, Rust, Java, Bun, Docker Desktop. |
| WSL | No | With Ubuntu, Debian or no distribution. Needs a restart. |

## Revert

In the [TidyWin menu](../README.md#quick-start): **Undo → Development**. From a local copy:

```powershell
.\scripts\dev\Configure-Dev.ps1 -Revert
```

Turns off Developer Mode, resets the default terminal and offers to restore Windows Terminal settings from the first backup. Apps, fonts, Git settings, SSH keys and WSL stay; the script shows how to remove each one.
