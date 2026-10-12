#!/usr/bin/env bash
# Builds the GitHub Pages site into _site/:
#   _site/run         the launcher (from web/launcher.ps1): irm .../run | iex opens the TidyWin menu
#   _site/scripts/    copy of the scripts (the menu downloads the chosen one from here)
#   _site/index.html  page with the command and what each menu option does
#
# Usage: web/build.sh https://androksi.github.io/tidywin
# To add an option: one line in scripts/TidyWin.ps1 ($Menu) and one entry in web/index.html.
set -euo pipefail

base="${1:?usage: web/build.sh <site-url>}"
base="${base%/}"
short="${base#https://}"     # shown on the page: irm androksi.github.io/tidywin/run | iex
out=_site

rm -rf "$out"
mkdir -p "$out"
cp -r scripts "$out/scripts"
sed "s|__SHORT__|$short|g" web/index.html > "$out/index.html"

# Wallpapers: the images plus a list the wallpapers script reads (previews stay in the repo only)
mkdir -p "$out/assets/wallpapers" wallpapers   # where Get-Wallpapers.ps1 downloads them from
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

echo "Launcher:"
shortcut run            scripts/TidyWin.ps1

# No placeholder may be left over
if grep -rl '__[A-Z]*__' "$out" --exclude-dir=scripts --exclude-dir=assets; then
    echo "unreplaced placeholder in the files above" >&2
    exit 1
fi
