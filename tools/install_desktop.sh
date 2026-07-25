#!/usr/bin/env bash
# Сборка релиза + установка как приложения (бинарь, иконка, .desktop).
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build linux --release
rm -rf ~/.local/opt/calenfi
mkdir -p ~/.local/opt
cp -r build/linux/x64/release/bundle ~/.local/opt/calenfi
mkdir -p ~/.local/bin
ln -sf ~/.local/opt/calenfi/calenfi ~/.local/bin/calenfi   # для rofi run / Win+r

# --- иконки (hicolor) ---
for s in 64 128 256 512; do
  dir=~/.local/share/icons/hicolor/${s}x${s}/apps
  mkdir -p "$dir"
  if [[ -f tools/icon/linux_${s}.png ]]; then
    cp tools/icon/linux_${s}.png "$dir/calenfi.png"
  fi
done
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true

# --- .desktop ---
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/calenfi.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Calenfi
Comment=Local-first calendar aggregator
Exec=$HOME/.local/opt/calenfi/calenfi
Icon=calenfi
Terminal=false
Categories=Office;Calendar;
StartupWMClass=calenfi
DESKTOP
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "✓ Calenfi установлен → ~/.local/opt/calenfi/calenfi"
echo "  запуск: Win+r → calenfi  (или из меню приложений)"
