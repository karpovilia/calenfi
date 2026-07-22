#!/usr/bin/env bash
# Сборка релиза + установка как приложения qtile (бинарь, иконка, .desktop).
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build linux --release
rm -rf ~/.local/opt/calenfi
mkdir -p ~/.local/opt
cp -r build/linux/x64/release/bundle ~/.local/opt/calenfi
mkdir -p ~/.local/bin
ln -sf ~/.local/opt/calenfi/calenfi ~/.local/bin/calenfi   # для rofi run / Win+r
update-desktop-database ~/.local/share/applications 2>/dev/null || true
echo "✓ Calenfi установлен → ~/.local/opt/calenfi/calenfi"
echo "  запуск: Win+r → calenfi  (или из меню приложений)"
