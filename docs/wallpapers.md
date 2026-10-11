[← back to README](../README.md)

# Wallpapers

```powershell
irm androksi.github.io/tidywin/wallpapers | iex
```

Check the ones you want, choose the folder (`Pictures\Wallpapers` by default) and they are downloaded at the end. Optionally sets one of them as the desktop background. Click a preview to open the full image.

<!-- gallery:start -->
<table>
<tr><td align="center"><a href="../wallpapers/bloom-black.png"><img src="../wallpapers/previews/bloom-black.jpg" width="400" alt="bloom-black"></a><br><code>bloom-black</code> (1920×1080)</td></tr>
</table>
<!-- gallery:end -->

## Adding wallpapers

1. Put the image (`.jpg` or `.png`) in [`wallpapers/`](../wallpapers). Use a short lowercase name with hyphens, such as `mountain-night.jpg`.
2. Run `.\tools\Update-WallpaperGallery.ps1`. It creates the previews and updates the gallery above.
3. Commit. The list used by the `wallpapers` shortcut is built from the folder when the site is published.

## Rights

Only images that can be shared freely go here: your own work, or images under CC0 or a license that allows redistribution. When the license asks for credit, add it under the gallery.
