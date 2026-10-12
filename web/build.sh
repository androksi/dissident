#!/usr/bin/env bash
# Builds the GitHub Pages site into _site/:
#   _site/<shortcut>  one launcher per shortcut, generated from web/launcher.ps1
#   _site/scripts/    copy of the scripts (the launcher downloads from here)
#   _site/index.html  page listing the shortcuts
#
# Usage: web/build.sh https://androksi.github.io/tidywin
# To add a shortcut: one "shortcut" line below and one entry in web/index.html.
set -euo pipefail

base="${1:?usage: web/build.sh <site-url>}"
base="${base%/}"
short="${base#https://}"     # shown on the page: irm androksi.github.io/tidywin/brave | iex
out=_site

rm -rf "$out"
mkdir -p "$out"
cp -r scripts "$out/scripts"
sed "s|__SHORT__|$short|g" web/index.html > "$out/index.html"

# Wallpapers: the images plus a list the wallpapers script reads (previews stay in the repo only)
mkdir -p "$out/assets/wallpapers" wallpapers   # not "$out/wallpapers": that name is the shortcut
find wallpapers -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -exec cp {} "$out/assets/wallpapers/" \;
python3 web/wallpapers-index.py wallpapers > "$out/assets/wallpapers/index.json"

# shortcut <name> <script> [argument]
shortcut() {
    local name=$1 script=$2 args=${3:-}
    [ -f "$script" ] || { echo "script not found: $script" >&2; exit 1; }
    sed -e "s|__NAME__|$name|g" \
        -e "s|__SCRIPT__|$script|g" \
        -e "s|__ARGS__|$args|g" \
        -e "s|__BASE__|$base|g" \
        web/launcher.ps1 > "$out/$name"
    echo "  $base/$name -> $script $args"
}

echo "Shortcuts:"
shortcut windows        scripts/windows/Configure-Windows.ps1
shortcut windows-revert scripts/windows/Revert-Configure-Windows.ps1
shortcut windows-check  scripts/windows/Configure-Windows.ps1       -Check
shortcut cleanup        scripts/windows/Clean-Windows.ps1
shortcut repair         scripts/windows/Repair-Windows.ps1
shortcut network-reset  scripts/windows/Reset-Network.ps1
shortcut apps-export    scripts/apps/Backup-Apps.ps1             -Export
shortcut apps-import    scripts/apps/Backup-Apps.ps1             -Import
shortcut drivers-export scripts/drivers/Backup-Drivers.ps1       -Export
shortcut drivers-import scripts/drivers/Backup-Drivers.ps1       -Import
shortcut apps           scripts/apps/Configure-Apps.ps1
shortcut fonts          scripts/fonts/Install-Fonts.ps1
shortcut fonts-revert   scripts/fonts/Install-Fonts.ps1          -Revert
shortcut chrome         scripts/browsers/Configure-Chrome.ps1
shortcut chrome-revert  scripts/browsers/Configure-Chrome.ps1  -Revert
shortcut brave          scripts/browsers/Configure-Brave.ps1
shortcut brave-revert   scripts/browsers/Configure-Brave.ps1   -Revert
shortcut firefox        scripts/browsers/Configure-Firefox.ps1
shortcut firefox-revert scripts/browsers/Configure-Firefox.ps1 -Revert
shortcut dev            scripts/dev/Configure-Dev.ps1
shortcut dev-revert     scripts/dev/Configure-Dev.ps1            -Revert
shortcut wallpapers     scripts/wallpapers/Get-Wallpapers.ps1

# No placeholder may be left over
if grep -rl '__[A-Z]*__' "$out" --exclude-dir=scripts --exclude-dir=assets; then
    echo "unreplaced placeholder in the files above" >&2
    exit 1
fi
