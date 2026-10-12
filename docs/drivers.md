[← back to README](../README.md)

# Drivers

Save the PC's drivers before formatting and install them back afterwards, so you don't have to hunt for each one on the manufacturer's site.

## Before formatting

In the [TidyWin menu](../README.md#quick-start): **Formatting the PC → Back up apps and drivers** (the drivers step; skip the apps step if you only want the drivers).

1. A list of the drivers that didn't come with Windows, by type (video, audio, network, Bluetooth...), with the device that uses each one, the version and the size.
   - **Checked**: drivers in use, and add-ons to other drivers (audio effects, manufacturer settings).
   - **Unchecked**: old versions and devices that are not connected now.
   - ↑ ↓ move, Space checks, A checks the whole type, Enter continues. The total size is shown at the bottom.
2. Choose where to save. USB drives and other disks come first; they survive formatting. Video drivers take 2 to 3 GB each, so OneDrive is not a good place.
3. A `tidywin-drivers-<PC>-<date>` folder is created with:
   - one folder per driver;
   - `drivers.json`, the list that the import reads;
   - `README.txt`, explaining how to install them by hand.

## After formatting

Run **Windows Update** first: it brings back many drivers by itself. Then:

In the [TidyWin menu](../README.md#quick-start): **Formatting the PC → Restore apps and drivers** (the drivers step comes first).

1. Finds the `tidywin-drivers-*` folder on USB drives, other disks, Desktop, Documents, Downloads and OneDrive (or asks for the path).
2. Shows the same list, marking what Windows already installed (same version or newer). **Only the missing ones come checked.**
3. Installs each one with `pnputil`, Windows' own tool, which only accepts signed drivers.
4. Offers to restart if a driver needs it.

## By hand

Without TidyWin: Device Manager → right-click the device → **Update driver** → **Browse my computer** → pick the saved folder with **Include subfolders** checked. Or right-click a `.inf` file → **Install**.

## Good to know

- Drivers only work on the same Windows architecture (x64 / ARM64). A newer Windows version usually accepts drivers saved on an older one.
- For the video card, the installer from NVIDIA, AMD or Intel brings the control panel too. The saved driver is a good fallback for when there's no internet yet.
- Nothing else on the PC is changed, and saving doesn't remove anything.
