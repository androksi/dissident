[← back to README](../README.md)

# Reinstalling Windows

From backup to a PC ready to use, with the TidyWin options in the right order.

Every **bold path** below is an option in the sidebar of the TidyWin panel. Open it with (right-click Start → Terminal):

```powershell
irm androksi.github.io/tidywin/run | iex
```

The panel stays open after each option, so you can keep it open and go down the list.

## Before formatting

1. **Back up your drivers, apps and Wi-Fi networks** to a USB drive: panel → **Back up → Create**. Turn on what you need. Drivers matter most on laptops and for the network card: without it there's no internet after formatting. [Details](backup.md)
   Keep the app list on a USB drive, in Google Drive or in an e-mail to yourself. **Not in OneDrive**: the Windows option can remove OneDrive.
2. **Back up your files**: Documents, Desktop, Downloads, projects that are not on GitHub, game saves and `.env` files.
3. **Browsers**: make sure sync is on (Firefox, Brave, Chrome), or export your passwords if you don't keep them in a password manager.
4. **Activation**: Settings → System → Activation should say *activated with a digital license*. It is tied to the hardware and comes back on its own.
5. **Video driver**: download the NVIDIA (or AMD/Intel) driver installer and keep it on the USB drive. It brings the control panel too; the saved driver is the fallback.

## Formatting

6. Settings → System → Recovery → **Reset this PC** → **Remove everything** → **Cloud download**.
   - Under *Change settings*, leave **Clean data = No**. It only matters if you are selling the PC; your files and the old Windows are gone either way.
   - If asked about other drives, choose **only the Windows drive**, so other disks are not wiped.
7. **Windows setup**: say no to every privacy screen (location, diagnostics, ads, tailored experiences).
   - **Local account**: the tricks to skip the Microsoft account change with every Windows version. The reliable way is to sign in with a Microsoft account and switch later in Settings → Accounts → Your info.

## After formatting, in this order

8. **Windows Update** until nothing is left, restarting between rounds. This brings chipset, network and audio drivers.
9. **Microsoft Store** → Library → **Update all**. This updates WinGet (App Installer), which installs your apps back; on a fresh Windows it sometimes doesn't work yet.
10. **Restore your drivers, Wi-Fi networks and apps**: panel → **Back up → Restore**. First the drivers Windows Update didn't bring back, then the Wi-Fi networks, then your apps.
11. **Video driver**: install it (clean install) and restart.
12. **Windows**: panel → **Set up → Windows**. Creates a restore point, then cleans up and configures Windows. Restart at the end. Then **Set up → Apps** for anything new.
13. **Browsers**, after installing them, only the ones you use: panel → **Set up → Browsers**, turning on Firefox, Brave or Chrome.
14. **Your files**: copy them back from the backup and sign in to your accounts.
15. **Disk space**: panel → **Maintenance → Disk space**. You can also turn on *Old Windows components*. Restart one last time.

## From time to time

| Menu option | When |
|---|---|
| Back up → Create | Every now and then, so the backup is current for the next reinstall. |
| Maintenance → Fix Windows | Only when Windows acts strange. |

## Games with anti-cheat

None of the options touch TPM, Secure Boot, Memory integrity or test signing. If a game like VALORANT complains (VAN 9001/9003), check them in Windows Security → Device security and in System Information (`msinfo32`), or in the BIOS: updating or resetting it sometimes turns TPM or Secure Boot off.

- TPM: <kbd>Win</kbd> + <kbd>R</kbd> → `tpm.msc` → *The TPM is ready for use*.
- Secure Boot: <kbd>Win</kbd> + <kbd>R</kbd> → `msinfo32` → *Secure Boot State* = **On**.
