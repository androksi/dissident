[← back to README](../README.md)

# Drivers

Save the PC's drivers before formatting and install them back afterwards, so you don't have to hunt for each one on the manufacturer's site.

## Before formatting

In the [TidyWin panel](../README.md#quick-start): **Back up → Create**, with **Drivers** on. [How the backup works](backup.md)

1. Lists the drivers that didn't come with Windows, by type (video, audio, network, Bluetooth...), with the device that uses each one, the version and the size. Drivers no device uses now say so: old versions and devices that are not connected.
2. Nothing checked; **Select all** checks a whole type. Video drivers take 2 to 3 GB each, so a USB drive or another disk is the best place.
3. They go in the `drivers` folder of the `tidywin-backup-<PC>-<date>` folder:
   - one folder per driver;
   - `drivers.json`, the list that Restore reads;
   - `README.txt`, explaining how to install them by hand.

## After formatting

Run **Windows Update** first: it brings back many drivers by itself. Then:

In the [TidyWin panel](../README.md#quick-start): **Back up → Restore**, with **Drivers** on (they are installed before the Wi-Fi networks and the apps).

1. Finds the newest `tidywin-backup-*` folder on USB drives, other disks, Desktop, Documents, Downloads and OneDrive (or choose another folder).
2. Lists the saved drivers, nothing checked, marking **Installed** what Windows already has (same version or newer). With another folder, the ones Windows doesn't have are installed.
3. Installs each one with `pnputil`, Windows' own tool, which only accepts signed drivers.
4. Says when a driver needs a restart.
## By hand

Without TidyWin: Device Manager → right-click the device → **Update driver** → **Browse my computer** → pick the saved folder with **Include subfolders** checked. Or right-click a `.inf` file → **Install**.

## Good to know

- Drivers only work on the same Windows architecture (x64 / ARM64). A newer Windows version usually accepts drivers saved on an older one.
- For the video card, the installer from NVIDIA, AMD or Intel brings the control panel too. The saved driver is a good fallback for when there's no internet yet.
- Nothing else on the PC is changed, and saving doesn't remove anything.
