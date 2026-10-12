[← back to README](../README.md)

# Reinstalling Windows

From backup to a PC ready to use, with the TidyWin commands in the right order.

## Before formatting

1. **Save your app list.**
   ```powershell
   irm androksi.github.io/tidywin/apps-export | iex
   ```
   Keep the file on a USB drive, in Google Drive or in an e-mail to yourself. **Not in OneDrive**: the `windows` command can remove OneDrive.
2. **Save your drivers** to a USB drive. The ones in use come checked. Most important on laptops and for the network card: without it there's no internet after formatting. [Details](drivers.md)
   ```powershell
   irm androksi.github.io/tidywin/drivers-export | iex
   ```
3. **Back up your files**: Documents, Desktop, Downloads, projects that are not on GitHub, game saves and `.env` files.
4. **Browsers**: make sure sync is on (Firefox, Brave, Chrome), or export your passwords if you don't keep them in a password manager.
5. **Activation**: Settings → System → Activation should say *activated with a digital license*. It is tied to the hardware and comes back on its own.
6. **Video driver**: download the NVIDIA (or AMD/Intel) driver installer and keep it on the USB drive. It brings the control panel too; the saved driver is the fallback.

SSH keys don't need a backup: `dev` creates a new one and deletes the old key of this PC from GitHub.

## Formatting

7. Settings → System → Recovery → **Reset this PC** → **Remove everything** → **Cloud download**.
   - Under *Change settings*, leave **Clean data = No**. It only matters if you are selling the PC; your files and the old Windows are gone either way.
   - If asked about other drives, choose **only the Windows drive**, so other disks are not wiped.
8. **Windows setup**: say no to every privacy screen (location, diagnostics, ads, tailored experiences).
   - **Local account**: the tricks to skip the Microsoft account change with every Windows version. The reliable way is to sign in with a Microsoft account and switch later in Settings → Accounts → Your info.

## After formatting, in this order

9. **Windows Update** until nothing is left, restarting between rounds. This brings chipset, network and audio drivers.
10. **`drivers-import`**, if you saved your drivers: installs only the ones Windows Update didn't bring back.
    ```powershell
    irm androksi.github.io/tidywin/drivers-import | iex
    ```
11. **Microsoft Store** → Library → **Update all**. This updates WinGet (App Installer), which the scripts use; on a fresh Windows it sometimes doesn't work yet.
12. **Video driver**: install it (clean install) and restart.
13. **`windows`**: creates a restore point, then cleans up and configures Windows. Restart at the end.
    ```powershell
    irm androksi.github.io/tidywin/windows | iex
    ```
14. **`apps-import`**: reinstalls the apps from the list you saved. Run `apps` afterwards for anything new.
    ```powershell
    irm androksi.github.io/tidywin/apps-import | iex
    ```
15. **Browsers**, after installing them, only the ones you use:
    ```powershell
    irm androksi.github.io/tidywin/firefox | iex
    irm androksi.github.io/tidywin/brave | iex
    irm androksi.github.io/tidywin/chrome | iex
    ```
16. **`dev`**: editors, Git, SSH key sent to GitHub, signed commits and Windows Terminal with a Nerd Font.
    ```powershell
    irm androksi.github.io/tidywin/dev | iex
    ```
17. **`wallpapers`**, if you want.
18. **Your files**: copy them back from the backup and sign in to your accounts.
19. **`cleanup`**: you can also accept *Old Windows components*. Restart one last time.
    ```powershell
    irm androksi.github.io/tidywin/cleanup | iex
    ```
20. **`report`**: checks that everything is in place (activation, drivers, TPM/Secure Boot, disks). Only reads; the summary at the top lists anything left to fix.
    ```powershell
    irm androksi.github.io/tidywin/report | iex
    ```

## From time to time

| Command | When |
|---|---|
| `windows-check` | After a big Windows update, to see whether anything came back. |
| `apps-export` | Every now and then, so the list is current for the next reinstall. |
| `repair` | Only when Windows acts strange. |
| `report` | Before asking for help: send the report (it has no personal data). |

The scripts request administrator rights on their own, so a normal PowerShell is enough (right-click Start → Terminal).

## Games with anti-cheat

None of the scripts touch TPM, Secure Boot, Memory integrity or test signing. If a game like VALORANT complains (VAN 9001/9003), run `report`: its *Security and anti-cheat* section shows all four. Or check the BIOS: updating or resetting it sometimes turns TPM or Secure Boot off.

- TPM: <kbd>Win</kbd> + <kbd>R</kbd> → `tpm.msc` → *The TPM is ready for use*.
- Secure Boot: <kbd>Win</kbd> + <kbd>R</kbd> → `msinfo32` → *Secure Boot State* = **On**.
