[← back to README](../README.md)

# Fonts

```powershell
irm androksi.github.io/tidywin/fonts | iex
```

Check the fonts you want and they are installed for every user of the PC, ready to use without restarting (apps that were already open may need to be reopened). Each font is downloaded from its official source. Fonts already installed are marked in the list, and files that already exist are never replaced.

## Code

| Font | Source | Notes |
|---|---|---|
| JetBrains Mono | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) | Made for code, with ligatures. The font of the JetBrains IDEs. |
| Fira Code | [tonsky/FiraCode](https://github.com/tonsky/FiraCode) | With ligatures (`=>`, `!=`, `===`). |
| Geist Mono | [vercel/geist-font](https://github.com/vercel/geist-font) | By Vercel. |
| Source Code Pro | [adobe-fonts/source-code-pro](https://github.com/adobe-fonts/source-code-pro) | By Adobe. |
| IBM Plex Mono | [Google Fonts](https://fonts.google.com/specimen/IBM+Plex+Mono) | By IBM. |
| Hack | [source-foundry/Hack](https://github.com/source-foundry/Hack) | Made for small sizes. |

## With icons (Nerd Fonts)

Code fonts with thousands of extra icons, needed by terminal prompts such as Oh My Posh, Starship and Powerlevel10k, and by tools like `eza` and `lazygit`. From [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts). Large downloads.

| Font | Based on | Download |
|---|---|---|
| JetBrainsMono Nerd Font | JetBrains Mono | ~130 MB |
| CaskaydiaCove Nerd Font | Cascadia Code (Windows Terminal's font) | ~55 MB |
| FiraCode Nerd Font | Fira Code | ~30 MB |
| MesloLGS Nerd Font | Menlo; the one Oh My Posh and Powerlevel10k recommend | ~110 MB |

The `dev` script can also install CaskaydiaCove or JetBrainsMono Nerd Font and set it in Windows Terminal.

## Text

| Font | Source | Notes |
|---|---|---|
| Inter | [rsms/inter](https://github.com/rsms/inter) | Made for screens. Shows up as "Inter Variable". |
| Geist | [vercel/geist-font](https://github.com/vercel/geist-font) | Pairs with Geist Mono. |
| IBM Plex Sans | [Google Fonts](https://fonts.google.com/specimen/IBM+Plex+Sans) | Pairs with IBM Plex Mono. |
| Roboto | [Google Fonts](https://fonts.google.com/specimen/Roboto) | Android and Google. |
| Open Sans | [Google Fonts](https://fonts.google.com/specimen/Open+Sans) | Neutral, very readable. |
| Noto Sans | [Google Fonts](https://fonts.google.com/noto/specimen/Noto+Sans) | Covers almost every language. |
| Lato | [Google Fonts](https://fonts.google.com/specimen/Lato) | Good for documents. |
| Montserrat | [Google Fonts](https://fonts.google.com/specimen/Montserrat) | Geometric, good for titles. |
| Poppins | [Google Fonts](https://fonts.google.com/specimen/Poppins) | Geometric and round. |

Every font on the list is free to use and share (SIL Open Font License; Hack under its own MIT-style license). The latest version is always downloaded.

## How it installs

- Files go to `C:\Windows\Fonts` and are registered for every user, like Windows' own "Install for all users".
- What was installed is recorded in `%ProgramData%\TidyWin\fonts.json`.
- The list of files comes from GitHub, which allows 60 lookups per hour without a login. One run uses at most one per font; if the limit is reached, the script says so.

## Revert

```powershell
irm androksi.github.io/tidywin/fonts-revert | iex
```

Lists the fonts installed by `fonts`, all checked; uncheck the ones to keep. Fonts installed some other way are never touched. A font file in use can't be deleted: restart the PC and run it again.

## Adding a font

One `New-Font` line in [`Install-Fonts.ps1`](../scripts/fonts/Install-Fonts.ps1) (section 2), then this page and the `fonts` entry in [`web/index.html`](../web/index.html):

- `release`: the GitHub repository, a pattern for the release asset (`.zip`) and a pattern for the files inside it. Prefer the `.ttf` files and only one set: static **or** variable, never both.
- `google`: the folder in [google/fonts](https://github.com/google/fonts) (`ofl/<name>`).
- The family is the name Windows shows in font menus. The script uses it to tell whether the font is already installed.
