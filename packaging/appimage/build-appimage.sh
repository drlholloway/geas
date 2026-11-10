#!/bin/sh
# Wraps the Flutter Linux release bundle as an AppImage.
#   packaging/appimage/build-appimage.sh <bundle dir> <version> [output dir]
# Needs appimagetool on PATH (or APPIMAGETOOL pointing at it). GTK 3 and
# libsecret are expected from the host, as is usual for Flutter AppImages.
set -eu
BUNDLE="$1"; VERSION="$2"; OUT="${3:-.}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="${APPIMAGETOOL:-appimagetool}"
APPDIR="$(mktemp -d)/Geas.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE/." "$APPDIR/usr/bin/"
install -m755 "$ROOT/packaging/appimage/AppRun" "$APPDIR/AppRun"
install -m644 "$ROOT/packaging/appimage/geas.desktop" "$APPDIR/usr/share/applications/geas.desktop"
install -m644 "$ROOT/packaging/appimage/geas.desktop" "$APPDIR/geas.desktop"
install -m644 "$ROOT/apps/geas/assets/icon/icon_512.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/geas.png"
install -m644 "$ROOT/apps/geas/assets/icon/icon_512.png" "$APPDIR/geas.png"
mkdir -p "$OUT"
# Named like the Sightings and Fretman AppImages. Embedded update
# information lets AppImageUpdate fetch the newest release; appimagetool
# writes the matching .zsync next to the image, and both are published.
NAME="Geas-$VERSION-x86_64.AppImage"
UPDATE="gh-releases-zsync|drlholloway|geas|latest|Geas-*x86_64.AppImage.zsync"
cd "$OUT"
ARCH=x86_64 VERSION="$VERSION" "$TOOL" --appimage-extract-and-run -n -u "$UPDATE" "$APPDIR" "$NAME" 2>/dev/null \
  || ARCH=x86_64 VERSION="$VERSION" "$TOOL" -n -u "$UPDATE" "$APPDIR" "$NAME"
ls -la "$NAME" "$NAME.zsync"
