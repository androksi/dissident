[← back to README](../README.md)

# Back up and Restore

Save your drivers, apps and Wi-Fi networks before formatting, and put them back afterwards. In the [TidyWin panel](../README.md#quick-start): **Utils → Back up** and **Utils → Restore**.

## Back up

1. **Save to** comes already set to a USB drive or another disk, if there is one: they survive formatting. You can pick Desktop, Documents, Downloads, OneDrive or another folder instead.
2. Turn on what to save:
   - **Drivers**: the ones Windows doesn't bring by itself, for the devices of this PC (video, network, audio...), with how many and their size. Video drivers take 2 to 3 GB each. [Details](drivers.md)
   - **Apps**: the list of apps WinGet knows, Microsoft Store apps included. Only the apps, not their settings or files. [Details](apps.md#moving-apps-to-another-pc)
   - **Wi-Fi networks**: the saved networks and their passwords. The passwords are saved readable in the backup folder (an encrypted one only works on the Windows that saved it): keep the folder safe and delete it when you no longer need it.

Everything goes in one folder:

```
tidywin-backup-<PC>-<date>\
    drivers\      one folder per driver, drivers.json and a README.txt for installing by hand
    apps.json     the WinGet list
    wifi\         one .xml per network
```

Your own files (Documents, Pictures, Desktop...) are not saved: copy them yourself.

## Restore

1. **Backup** comes already set to the newest `tidywin-backup-*` folder on USB drives, other disks, Desktop, Documents, Downloads and OneDrive, with what it has. You can pick another folder.
2. Turn on what to put back. It always runs in this order:
   1. **Drivers**: the ones this PC doesn't have yet (the same version or a newer one is skipped). Some need a restart.
   2. **Wi-Fi networks**: added for every user, so the PC connects by itself. Needs the Wi-Fi adapter's driver, which is why drivers come first.
   3. **Apps**: the ones not installed yet, with WinGet. They need the internet, which is why they come last.

From a local copy, each part runs on its own with `-Export` (back up) or `-Import` (restore):

```powershell
.\scripts\drivers\backup-drivers.ps1 -Export
.\scripts\apps\backup-apps.ps1 -Export
.\scripts\windows\backup-wifi.ps1 -Export
```
