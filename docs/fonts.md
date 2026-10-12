[← back to README](../README.md)

# Fonts

In the [TidyWin menu](../README.md#quick-start): **Set up → Install fonts**.

Check the fonts you want and they are installed for every user of the PC, ready to use without restarting (apps that were already open may need to be reopened). Each font is downloaded from its official source. Fonts already installed are marked in the list, and files that already exist are never replaced.

## Code

| Font | Source | Notes |
|---|---|---|
| JetBrains Mono | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) | Made for code, with ligatures. The font of the JetBrains IDEs. |
| Fira Code | [tonsky/FiraCode](https://github.com/tonsky/FiraCode) | With ligatures (`=>`, `!=`, `===`). |
| Geist Mono | [vercel/geist-font](https://github.com/vercel/geist-font) | By Vercel. |
| Source Code Pro | [Google Fonts](https://fonts.google.com/specimen/Source+Code+Pro) | By Adobe. |
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

The Development option can also install CaskaydiaCove or JetBrainsMono Nerd Font and set it in Windows Terminal.

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
- Downloads come straight from github.com and raw.githubusercontent.com. The GitHub API is not used: without a login it allows only 60 calls per hour, shared by everyone on the same connection.

## Revert

In the [TidyWin menu](../README.md#quick-start): **Undo → Fonts**.

Lists the fonts installed by Install fonts, all checked; uncheck the ones to keep. Fonts installed some other way are never touched. A font file in use can't be deleted: restart the PC and run it again.

## Adding a font

One `New-Font` line in [`Install-Fonts.ps1`](../scripts/fonts/Install-Fonts.ps1) (section 2), then this page and the `fonts` entry in [`web/index.html`](../web/index.html):

- `release`: the GitHub repository, the release `.zip` name (`{v}` stands for the version, e.g. `JetBrainsMono-{v}.zip`) and a pattern for the files inside it. Prefer the `.ttf` files and only one set: static **or** variable, never both.
- `google`: the folder in [google/fonts](https://github.com/google/fonts) (`ofl/<name>`) and the file names in it. For one file per style, `Get-StaticNames` builds the list.
- The family is the name Windows shows in font menus. The script uses it to tell whether the font is already installed.
