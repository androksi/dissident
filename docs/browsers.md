[← back to README](../README.md)

# Browsers

All three use each browser's official policies: they apply to every profile, even if the browser is installed later. Close and reopen the browser to apply them (it will show "Managed by your organization" — that's normal with policies). Check them at `brave://policy`, `chrome://policy` or `about:policies`.

To undo: run the same script with `-Revert`.

## Brave

```powershell
.\scripts\browsers\Configure-Brave.ps1
```

| Feature | What it does |
|---|---|
| Brave features | Turns off Wallet, VPN, Rewards, Leo, News, Talk, Playlist, Wayback, Tor and Speedreader. |
| Telemetry | Turns off P3A, the daily ping and Web Discovery. |
| Chromium policies | Turns off reports, surveys, promotional tabs, background mode, shopping list and the "not your default browser" prompt. |
| Apps, passwords and cards | Blocks installing sites as apps, the password manager and saved cards. |
| Cast to TV | Keep (creates the firewall rule) or turn off. Either way, no firewall prompt. |

## Chrome

```powershell
.\scripts\browsers\Configure-Chrome.ps1
```

| Feature | What it does |
|---|---|
| Telemetry | Turns off reports, URL collection, cloud spell check, surveys and feedback. |
| Search suggestions | Stops sending what you type to Google in real time (asks). |
| Preloading | Turns off page preloading (asks). |
| AI | Turns off Gemini, AI Mode and every AI feature. |
| Cookies | Blocks third-party cookies, allowing Google's domains. |
| Extras | Blocks sync, background mode, shopping list and the "not your default browser" prompt. Safe Browsing in Standard mode. |

## Firefox

```powershell
.\scripts\browsers\Configure-Firefox.ps1
```

| Feature | What it does |
|---|---|
| Telemetry | Turns off telemetry, studies, the default browser agent and the "not your default browser" prompt. |
| Sponsored and recommendations | Removes sponsored content and recommendations from the new tab and the address bar. |
| AI | Turns off AI features. Local translation keeps working. |
| Extensions | Installs uBlock Origin and Bitwarden. |
| Bitwarden only | Turns off Firefox's password manager and address and card autofill (warns if there are saved passwords). |
| No nags | Removes address bar tips, invitations to experimental features and the default bookmarks. |
| Search suggestions | Stops sending what you type to the search engine in real time (asks). |
| Preloading | Turns off page preloading (asks). |
| HTTPS-Only | Warns before opening sites without a secure connection (asks). |
