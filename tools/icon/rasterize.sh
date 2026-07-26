#!/usr/bin/env bash
# Перегенерирует SVG и раскатывает иконку Calenfi по всем платформам рабочего дерева.
set -euo pipefail
cd "$(dirname "$0")"                 # tools/icon
ROOT="$(cd ../.. && pwd)"
python3 gen_icon.py

MASTER=calenfi_icon.svg
FG=calenfi_fg.svg
BG=bg.svg

r() { rsvg-convert -w "$1" -h "$1" "$2" -o "$3"; }

# --- превью/база ---
r 1024 "$MASTER" calenfi_icon.png
r 1024 "$FG" calenfi_fg.png
r 1024 "$BG" calenfi_bg.png
r 192  "$MASTER" preview192.png

# --- Android legacy ic_launcher.png ---
declare -A LEG=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
# --- Android adaptive foreground/background (108dp базис) ---
declare -A ADP=( [mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432 )
for d in "${!LEG[@]}"; do
  dir="$ROOT/android/app/src/main/res/mipmap-$d"
  r "${LEG[$d]}" "$MASTER" "$dir/ic_launcher.png"
  r "${ADP[$d]}" "$FG" "$dir/ic_launcher_foreground.png"
  r "${ADP[$d]}" "$BG" "$dir/ic_launcher_background.png"
done

# --- macOS appiconset ---
ICS="macos_appicon/AppIcon.appiconset"
for s in 16 32 64 128 256 512 1024; do r "$s" "$MASTER" "$ICS/app_icon_$s.png"; done

# --- Linux hicolor ---
for s in 64 128 256 512; do r "$s" "$MASTER" "linux_$s.png"; done
cp linux_512.png calenfi_linux.png

# --- Windows .ico (мульти-размер) ---
tmpdir=$(mktemp -d)
for s in 16 24 32 48 64 128 256; do r "$s" "$MASTER" "$tmpdir/i_$s.png"; done
magick "$tmpdir"/i_16.png "$tmpdir"/i_24.png "$tmpdir"/i_32.png "$tmpdir"/i_48.png \
       "$tmpdir"/i_64.png "$tmpdir"/i_128.png "$tmpdir"/i_256.png calenfi.ico
cp calenfi.ico "$ROOT/windows/runner/resources/app_icon.ico"
rm -rf "$tmpdir"

echo "OK: иконки перегенерированы во всём рабочем дереве."
