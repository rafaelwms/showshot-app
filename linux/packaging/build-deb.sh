#!/usr/bin/env bash
# Builds the Debian package for this machine's architecture:
#
#   build/deb/showshot_<version>_<arch>.deb
#   build/deb/showshot_<version>_<arch>.deb.sha256
#
# Layout (the one an apt repository would accept — lintian rejects /opt):
#   /usr/lib/showshot/                 the Flutter release bundle
#   /usr/bin/showshot                  → ../lib/showshot/shoshot
#   /usr/share/applications/com.rafaelwms.showshot.desktop
#   /usr/share/icons/hicolor/*/apps/com.rafaelwms.showshot.png
#   /usr/share/metainfo/com.rafaelwms.showshot.metainfo.xml
#   /usr/share/doc/showshot/{copyright,changelog.gz}
#
# Runtime library dependencies come from dpkg-shlibdeps (computed from the
# binaries, not hand-written), so the same script works on amd64 and arm64.
# No maintainer scripts: dpkg's triggers refresh the desktop database and
# icon cache by themselves.
#
# Needs: dpkg-dev (dpkg-shlibdeps), patchelf, binutils (strip); lintian to
# check the result (`lintian build/deb/*.deb` should print nothing).
#
# Usage:
#   linux/packaging/build-deb.sh              # flutter build + package
#   linux/packaging/build-deb.sh --no-build   # package the existing bundle
set -euo pipefail

APP_ID=com.rafaelwms.showshot
PACKAGE=showshot
MAINTAINER='Rafael WMS <rafael.wms@msn.com>'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

build=true
for arg in "$@"; do
  case "$arg" in
    --no-build) build=false ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

version="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)"
arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) flutter_arch=x64 ;;
  arm64) flutter_arch=arm64 ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

if $build; then
  flutter build linux --release
fi
bundle="build/linux/$flutter_arch/release/bundle"
[[ -x "$bundle/shoshot" ]] || { echo "no release bundle at $bundle" >&2; exit 1; }

out_dir="build/deb"
name="${PACKAGE}_${version}_${arch}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/$name"

# --- files -----------------------------------------------------------------
install -d "$pkg/usr/lib/$PACKAGE" "$pkg/usr/bin"
cp -a "$bundle/." "$pkg/usr/lib/$PACKAGE/"
ln -s "../lib/$PACKAGE/shoshot" "$pkg/usr/bin/$PACKAGE"

install -Dm644 "linux/$APP_ID.desktop" \
  "$pkg/usr/share/applications/$APP_ID.desktop"
sed -i "s|^Exec=.*|Exec=$PACKAGE|" "$pkg/usr/share/applications/$APP_ID.desktop"
for icon in linux/icons/hicolor/*/apps/$APP_ID.png; do
  size="$(basename "$(dirname "$(dirname "$icon")")")"
  install -Dm644 "$icon" "$pkg/usr/share/icons/hicolor/$size/apps/$APP_ID.png"
done
install -Dm644 "linux/$APP_ID.metainfo.xml" \
  "$pkg/usr/share/metainfo/$APP_ID.metainfo.xml"

doc="$pkg/usr/share/doc/$PACKAGE"
install -d "$doc"
cat > "$doc/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Show Shot
Upstream-Contact: $MAINTAINER
Source: https://showshot.rafaelwms.com

Files: *
Copyright: 2026 Rafael WMS
License: proprietary
 Show Shot is free to download and use. All rights reserved; it may not be
 modified or redistributed without the author's permission.
EOF
cat > "$stage/changelog" <<EOF
$PACKAGE ($version) stable; urgency=medium

  * Release $version — see https://showshot.rafaelwms.com

 -- $MAINTAINER  $(date -R)
EOF
gzip -9n -c "$stage/changelog" > "$doc/changelog.gz"

# Binaries: drop debug symbols, and replace the plugins' RUNPATH — CMake
# bakes in the build machine's absolute linux/flutter/ephemeral path — with
# $ORIGIN (they sit next to libflutter_linux_gtk.so). libapp.so (the Dart AOT
# snapshot) and libflutter_linux_gtk.so ship already stripped; leave them be.
lib_dir="$pkg/usr/lib/$PACKAGE/lib"
strip --strip-unneeded --remove-section=.comment --remove-section=.note \
  "$pkg/usr/lib/$PACKAGE/shoshot"
for so in "$lib_dir"/*.so; do
  case "$(basename "$so")" in
    libapp.so | libflutter_linux_gtk.so) continue ;;
  esac
  strip --strip-unneeded --remove-section=.comment --remove-section=.note "$so"
  if [[ -n "$(patchelf --print-rpath "$so")" ]]; then
    patchelf --set-rpath '$ORIGIN' "$so"
  fi
done

# Manual page (`man showshot`).
install -d "$pkg/usr/share/man/man1"
cat > "$stage/showshot.1" <<EOF
.TH SHOWSHOT 1 "$(date +%Y-%m-%d)" "Show Shot $version" "User Commands"
.SH NAME
showshot \- capture, annotate and share screenshots
.SH SYNOPSIS
.B showshot
[\fB\-\-hidden\fR]
.SH DESCRIPTION
Show Shot lives in the top bar and captures an area, a window, the whole
screen or the text in a region (OCR), then lets you annotate the capture and
copy or save it. Running it again while it is open brings its window up.
.SH OPTIONS
.TP
.B \-\-hidden
Start in the top bar only, without opening the window (used when launched at
login).
.SH SEE ALSO
https://showshot.rafaelwms.com
EOF
gzip -9n -c "$stage/showshot.1" > "$pkg/usr/share/man/man1/showshot.1.gz"

# Lintian findings that come with any Flutter app and can't be fixed here.
install -d "$pkg/usr/share/lintian/overrides"
cat > "$pkg/usr/share/lintian/overrides/$PACKAGE" <<EOF
# The Flutter engine statically links its own image/font codecs.
$PACKAGE: embedded-library freetype [usr/lib/$PACKAGE/lib/libflutter_linux_gtk.so]
$PACKAGE: embedded-library libjpeg [usr/lib/$PACKAGE/lib/libflutter_linux_gtk.so]
# libapp.so is the Dart AOT snapshot: data-only ELF, no libc needed.
$PACKAGE: shared-library-lacks-prerequisites [usr/lib/$PACKAGE/lib/libapp.so]
EOF

# Normalize permissions (the build tree may carry a restrictive umask).
find "$pkg" -type d -exec chmod 755 {} +
find "$pkg" -type f -exec chmod 644 {} +
chmod 755 "$pkg/usr/lib/$PACKAGE/shoshot"
find "$pkg/usr/lib/$PACKAGE/lib" -name '*.so*' -type f -exec chmod 644 {} +

# --- dependencies ----------------------------------------------------------
# dpkg-shlibdeps wants a debian/control next to it; the bundle's own lib/
# (libflutter_linux_gtk.so, plugins) is private, so it's passed as -l and
# never becomes a dependency.
mkdir -p "$stage/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" \
  > "$stage/debian/control"
mapfile -t elves < <(find "$pkg/usr/lib/$PACKAGE" -type f \
  \( -name shoshot -o -name '*.so*' \))
depends="$(cd "$stage" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"$pkg/usr/lib/$PACKAGE/lib" "${elves[@]}" 2>/dev/null |
  sed -n 's/^shlibs:Depends=//p')"
rm -rf "$stage/debian"
[[ -n "$depends" ]] || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }

installed_size="$(du -sk --apparent-size "$pkg" | cut -f1)"
install -d "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $version
Architecture: $arch
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Depends: $depends
Recommends: xdg-desktop-portal, xdg-desktop-portal-gnome | xdg-desktop-portal-backend, tesseract-ocr
Suggests: tesseract-ocr-por
Section: graphics
Priority: optional
Homepage: https://showshot.rafaelwms.com
Description: capture, annotate and share screenshots
 Show Shot lives in the top bar and captures an area, a window, the whole
 screen or the text in a region (OCR), then lets you annotate it — arrows,
 shapes, text, numbered steps, blur — and copy or save the result.
 .
 Works on GNOME under Wayland (through the desktop portals) and on X11.
EOF

mkdir -p "$out_dir"
dpkg-deb --root-owner-group -Zxz --build "$pkg" "$out_dir/$name.deb" >/dev/null
(cd "$out_dir" && sha256sum "$name.deb" > "$name.deb.sha256")

echo "Built $out_dir/$name.deb"
cat "$out_dir/$name.deb.sha256"
