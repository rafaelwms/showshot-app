#!/usr/bin/env bash
# Installs a built Show Shot bundle for the current user (no root needed):
#
#   ~/.local/lib/showshot/          the Flutter bundle (binary + data + lib)
#   ~/.local/bin/showshot           symlink to the binary
#   ~/.local/share/applications/com.rafaelwms.showshot.desktop
#   ~/.local/share/icons/hicolor/*/apps/com.rafaelwms.showshot.png
#
# The .desktop file is what lets GNOME match the running window (Wayland
# app_id = com.rafaelwms.showshot) to a name and icon in the dock, and what
# xdg-desktop-portal keys the app's permissions (screenshot, global
# shortcuts) on — without it the app shows up as a generic gear icon.
#
# Usage:
#   linux/packaging/install-local.sh            # latest release build
#   linux/packaging/install-local.sh --debug    # latest debug build
#   linux/packaging/install-local.sh --link     # don't copy; point the
#                                               # launcher at build/ (dev)
#   linux/packaging/install-local.sh --uninstall
set -euo pipefail

APP_ID=com.rafaelwms.showshot
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
LIB_DIR="$HOME/.local/lib/showshot"
BIN_LINK="$HOME/.local/bin/showshot"
DESKTOP_FILE="$PREFIX/applications/$APP_ID.desktop"

mode=release
link=false
for arg in "$@"; do
  case "$arg" in
    --debug) mode=debug ;;
    --link) link=true ;;
    --uninstall)
      rm -rf "$LIB_DIR" "$BIN_LINK" "$DESKTOP_FILE"
      find "$PREFIX/icons/hicolor" -name "$APP_ID.png" -delete 2>/dev/null || true
      rm -f "$HOME/.config/autostart/$APP_ID.desktop" 2>/dev/null || true
      update-desktop-database "$PREFIX/applications" 2>/dev/null || true
      gtk-update-icon-cache -q -t "$PREFIX/icons/hicolor" 2>/dev/null || true
      echo "Show Shot uninstalled."
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
bundle="$ROOT/build/linux/$arch/$mode/bundle"
if [[ ! -x "$bundle/shoshot" ]]; then
  echo "No $mode bundle at $bundle — run: flutter build linux --$mode" >&2
  exit 1
fi

if $link; then
  exec_path="$bundle/shoshot"
  rm -rf "$LIB_DIR"
else
  rm -rf "$LIB_DIR"
  mkdir -p "$(dirname "$LIB_DIR")"
  cp -a "$bundle" "$LIB_DIR"
  exec_path="$LIB_DIR/shoshot"
fi
mkdir -p "$(dirname "$BIN_LINK")"
ln -sfn "$exec_path" "$BIN_LINK"

for icon in "$ROOT"/linux/icons/hicolor/*/apps/$APP_ID.png; do
  size_dir="$(basename "$(dirname "$(dirname "$icon")")")"
  install -Dm644 "$icon" "$PREFIX/icons/hicolor/$size_dir/apps/$APP_ID.png"
done

mkdir -p "$PREFIX/applications"
sed "s|^Exec=.*|Exec=$exec_path|" "$ROOT/linux/$APP_ID.desktop" > "$DESKTOP_FILE"

update-desktop-database "$PREFIX/applications" 2>/dev/null || true
gtk-update-icon-cache -q -t "$PREFIX/icons/hicolor" 2>/dev/null || true

echo "Installed Show Shot ($mode) → $exec_path"
