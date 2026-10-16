[← back to README](../README.md)

# Browsers

All three use each browser's official policies: they apply to every profile, even if the browser is installed later. Close and reopen the browser to apply them (it will show "Managed by your organization" — that's normal with policies). Check them at `brave://policy`, `chrome://policy` or `about:policies`.

In the panel: **Set up → Browsers**, one page for the three. Turn on a browser and its options show up under it, each row below as a box in one list with "Select all", none checked at first: only what you check is applied. Extensions and the password options come last, under their own title. Each extension can be added or undone without touching the other; they install from the official store, stay up to date and can be turned off, not removed. Review lists the changes by browser.

To undo: panel → **Undo → Browsers**, or run the same script with `-Revert`. Turn on a browser and it lists a box for each group above that is on this PC, none checked, with "Select all", and one more for policies TidyWin doesn't know about (from an older version or another program); only what you check is removed.

## Brave

From a local copy:

```powershell
.\scripts\browsers\configure-brave.ps1
```

| Feature | What it does |
|---|---|
| Brave features | Turns off Wallet, VPN, Rewards, Leo, News, Talk, Playlist, Wayback, Tor and Speedreader. |
| Telemetry | Turns off P3A, the daily ping and Web Discovery. |
| Chromium policies | Turns off reports, surveys, promotional tabs, background mode, shopping list and the "not your default browser" prompt. |
| Bitwarden | Installs Bitwarden from the Chrome Web Store. No uBlock Origin: Brave already blocks ads. |
| Apps, passwords and cards | Blocks installing sites as apps, the password manager and saved cards. |
| Cast to TV | Keep (creates the firewall rule) or turn off. Either way, no firewall prompt. |

## Chrome

From a local copy:

```powershell
.\scripts\browsers\configure-chrome.ps1
```

| Feature | What it does |
|---|---|
| Telemetry | Turns off reports, URL collection, cloud spell check, surveys and feedback. |
| Search suggestions | Stops sending what you type to Google in real time. |
| Preloading | Turns off page preloading. |
| AI | Turns off Gemini, AI Mode and every AI feature. |
| Cookies | Blocks third-party cookies, allowing Google's domains. |
| Extras | Blocks sync, background mode, shopping list and the "not your default browser" prompt. Safe Browsing in Standard mode. |
| uBlock Origin Lite | Installs uBlock Origin Lite from the Chrome Web Store (the full uBlock Origin no longer runs in Chrome). |
| Bitwarden | Installs Bitwarden from the Chrome Web Store. |
| Passwords and cards | Turns off Chrome's password manager and saved cards. Passwords already saved stay in the Google account. |

## Firefox

From a local copy:

```powershell
.\scripts\browsers\configure-firefox.ps1
```

| Feature | What it does |
|---|---|
| Telemetry | Turns off telemetry, studies, the default browser agent and the "not your default browser" prompt. |
| Sponsored and recommendations | Removes sponsored content and recommendations from the new tab and the address bar. |
| AI | Turns off AI features. Local translation keeps working unless you turn it off. |
| uBlock Origin | Installs uBlock Origin from Mozilla's add-on store. |
| Bitwarden | Installs Bitwarden from Mozilla's add-on store. |
| Bitwarden only | Turns off Firefox's password manager and address and card autofill (warns if there are saved passwords). |
| No nags | Removes address bar tips, invitations to experimental features and the default bookmarks. |
| Search suggestions | Stops sending what you type to the search engine in real time. |
| Preloading | Turns off page preloading. |
| HTTPS-Only | Warns before opening sites without a secure connection. |
| Address bar buttons | Removes the "Add to taskbar" and Picture-in-Picture buttons. Picture-in-Picture itself keeps working. |
| Translation | Keep page translation (its icon stays in the address bar) or turn it off (the icon goes away). |
| Reader View icon | Removes the Reader View icon from the address bar. Uses AutoConfig (`defaults\pref\autoconfig.js` and `tidywin.cfg` in the Firefox folder), because policies cannot change it. Skipped if another AutoConfig exists; removed by `-Revert`. |
| Right-click menu | Removes lines you don't use from the right-click menu, one option each: *View Page Source*, *Send to Device*, *Take Screenshot*, *Inspect Accessibility Properties*, *Translate Selection* and *Ask an AI Chatbot*. Only the menu line goes, the feature stays. A block between two TidyWin markers in chrome\userChrome.css of every profile (your own CSS in that file stays), and the `toolkit.legacyUserProfileCustomizations.stylesheets` preference so Firefox reads it. Applying again adds to the lines already hidden; -Revert removes only TidyWin's block. Close and reopen Firefox to see it. |
