<#
.SYNOPSIS
    Rebuilds the wallpaper previews and the gallery in docs/wallpapers.md.

.DESCRIPTION
    For maintainers. Put .jpg or .png images in wallpapers/ and run this script:
    - creates a 640 px wide preview in wallpapers/previews/ for each new or changed image;
    - deletes previews whose image no longer exists;
    - rewrites the table between the gallery markers in docs/wallpapers.md.
    Then commit the result. The list used by the wallpapers shortcut is built from the
    folder when the site is published, so there is nothing else to update.

.EXAMPLE
    .\tools\Update-WallpaperGallery.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$PreviewWidth = 640
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$images   = Join-Path $Root 'wallpapers'
$previews = Join-Path $images 'previews'
$doc      = Join-Path $Root 'docs\wallpapers.md'
$start    = '<!-- gallery:start -->'
$end      = '<!-- gallery:end -->'

New-Item -ItemType Directory -Force -Path $previews | Out-Null

$files = @(Get-ChildItem -LiteralPath $images -File |
    Where-Object { $_.Extension -match '^\.(jpe?g|png)$' } |
    Sort-Object Name)

# JPEG encoder at quality 85
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams = New-Object System.Drawing.Imaging.EncoderParameters 1
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]85)

$cells = @()
foreach ($f in $files) {
    $base    = $f.BaseName
    $preview = Join-Path $previews "$base.jpg"
    $img = [System.Drawing.Image]::FromFile($f.FullName)
    try {
        $w = $img.Width; $h = $img.Height
        $stale = -not (Test-Path -LiteralPath $preview) -or ((Get-Item -LiteralPath $preview).LastWriteTime -lt $f.LastWriteTime)
        if ($stale) {
            $pw = [Math]::Min($PreviewWidth, $w)
            $ph = [int][Math]::Round($h * $pw / $w)
            $bmp = New-Object System.Drawing.Bitmap $pw, $ph
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.DrawImage($img, 0, 0, $pw, $ph)
                $bmp.Save($preview, $jpeg, $encParams)
            } finally { $g.Dispose(); $bmp.Dispose() }
            Write-Host "  preview  $base.jpg"
        }
    } finally { $img.Dispose() }

    $cells += "<td align=""center""><a href=""../wallpapers/$($f.Name)""><img src=""../wallpapers/previews/$base.jpg"" width=""400"" alt=""$base""></a><br><code>$base</code> ($w$([char]0x00D7)$h)</td>"
}

# Previews without an image
$names = $files | ForEach-Object { $_.BaseName }
Get-ChildItem -LiteralPath $previews -File -Filter *.jpg | Where-Object { $names -notcontains $_.BaseName } | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName
    Write-Host "  removed  previews\$($_.Name)"
}

# Table, two per row
if ($cells.Count) {
    $rows = for ($i = 0; $i -lt $cells.Count; $i += 2) { '<tr>' + ($cells[$i..([Math]::Min($i + 1, $cells.Count - 1))] -join '') + '</tr>' }
    $gallery = (@('<table>') + $rows + @('</table>')) -join "`n"
} else {
    $gallery = '_No wallpapers yet._'
}

$text = [IO.File]::ReadAllText($doc)
$pattern = [regex]::Escape($start) + '[\s\S]*?' + [regex]::Escape($end)
if ($text -notmatch $pattern) { throw "Gallery markers not found in $doc" }
$text = [regex]::Replace($text, $pattern, { param($m) "$start`n$gallery`n$end" })
[IO.File]::WriteAllText($doc, $text, (New-Object System.Text.UTF8Encoding $false))

Write-Host "Gallery updated: $($cells.Count) wallpaper(s)."
