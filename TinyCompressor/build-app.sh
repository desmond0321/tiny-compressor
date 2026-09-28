#!/bin/sh
set -eu
export COPYFILE_DISABLE=1

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$SCRIPT_DIR/build/TinyCompressor.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
TOOLS_DIR="$RESOURCES_DIR/Tools"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
DIST_DIR="$SCRIPT_DIR/dist"
X86_BREW_PREFIX=${X86_BREW_PREFIX:-/usr/local}
ARM_BREW_PREFIX=${ARM_BREW_PREFIX:-/opt/homebrew}
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tiny-compressor-build.XXXXXX")

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$TOOLS_DIR" "$FRAMEWORKS_DIR" "$DIST_DIR"

/usr/bin/swiftc -target x86_64-apple-macos14.0 -parse-as-library -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers "$SCRIPT_DIR/Sources/TinyCompressorApp.swift" -o "$WORK_DIR/TinyCompressor-x86_64"
/usr/bin/swiftc -target arm64-apple-macos14.0 -parse-as-library -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers "$SCRIPT_DIR/Sources/TinyCompressorApp.swift" -o "$WORK_DIR/TinyCompressor-arm64"
lipo -create "$WORK_DIR/TinyCompressor-x86_64" "$WORK_DIR/TinyCompressor-arm64" -output "$MACOS_DIR/TinyCompressor"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

require_file() {
  [ -f "$1" ] || { printf 'Missing required build dependency: %s\n' "$1" >&2; exit 1; }
}

copy_universal_binary() {
  binary_name=$1
  x86_path=$2
  arm_path=$3
  destination_dir=$4
  require_file "$x86_path"
  require_file "$arm_path"
  lipo -create "$x86_path" "$arm_path" -output "$destination_dir/$binary_name"
  chmod 755 "$destination_dir/$binary_name"
}

copy_universal_library() {
  library_name=$1
  x86_path=$2
  arm_path=$3
  copy_universal_binary "$library_name" "$x86_path" "$arm_path" "$FRAMEWORKS_DIR"
  install_name_tool -id "@rpath/$library_name" "$FRAMEWORKS_DIR/$library_name"
  install_name_tool -add_rpath "@loader_path" "$FRAMEWORKS_DIR/$library_name" 2>/dev/null || true
}

rewrite_dependencies() {
  target=$1
  install_name_tool -add_rpath "@loader_path/../../Frameworks" "$target" 2>/dev/null || true
  for dependency in \
    "$X86_BREW_PREFIX/opt/little-cms2/lib/liblcms2.2.dylib" \
    "$ARM_BREW_PREFIX/opt/little-cms2/lib/liblcms2.2.dylib" \
    "$X86_BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib" \
    "$ARM_BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib" \
    "$X86_BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" \
    "$ARM_BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" \
    "$X86_BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib" \
    "$ARM_BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib" \
    "$X86_BREW_PREFIX/opt/webp/lib/libwebp.7.dylib" \
    "$ARM_BREW_PREFIX/opt/webp/lib/libwebp.7.dylib" \
    "$X86_BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib" \
    "$ARM_BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib" \
    "$X86_BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib" \
    "$ARM_BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib" \
    "$X86_BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib" \
    "$ARM_BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib" \
    "$X86_BREW_PREFIX/opt/xz/lib/liblzma.5.dylib" \
    "$ARM_BREW_PREFIX/opt/xz/lib/liblzma.5.dylib"; do
    dependency_name=$(basename "$dependency")
    install_name_tool -change "$dependency" "@rpath/$dependency_name" "$target" 2>/dev/null || true
  done
}

copy_universal_binary pngquant "$X86_BREW_PREFIX/bin/pngquant" "$ARM_BREW_PREFIX/bin/pngquant" "$TOOLS_DIR"
copy_universal_binary zopflipng "$X86_BREW_PREFIX/bin/zopflipng" "$ARM_BREW_PREFIX/bin/zopflipng" "$TOOLS_DIR"
copy_universal_binary oxipng "$X86_BREW_PREFIX/bin/oxipng" "$ARM_BREW_PREFIX/bin/oxipng" "$TOOLS_DIR"
copy_universal_binary cjpeg "$X86_BREW_PREFIX/opt/mozjpeg/bin/cjpeg" "$ARM_BREW_PREFIX/opt/mozjpeg/bin/cjpeg" "$TOOLS_DIR"
copy_universal_binary jpegoptim "$X86_BREW_PREFIX/bin/jpegoptim" "$ARM_BREW_PREFIX/bin/jpegoptim" "$TOOLS_DIR"
copy_universal_binary cwebp "$X86_BREW_PREFIX/bin/cwebp" "$ARM_BREW_PREFIX/bin/cwebp" "$TOOLS_DIR"

copy_universal_library liblcms2.2.dylib "$X86_BREW_PREFIX/opt/little-cms2/lib/liblcms2.2.dylib" "$ARM_BREW_PREFIX/opt/little-cms2/lib/liblcms2.2.dylib"
copy_universal_library libpng16.16.dylib "$X86_BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib" "$ARM_BREW_PREFIX/opt/libpng/lib/libpng16.16.dylib"
copy_universal_library libzopflipng.1.dylib "$X86_BREW_PREFIX/opt/zopfli/lib/libzopflipng.1.dylib" "$ARM_BREW_PREFIX/opt/zopfli/lib/libzopflipng.1.dylib"
copy_universal_library libzopfli.1.dylib "$X86_BREW_PREFIX/opt/zopfli/lib/libzopfli.1.dylib" "$ARM_BREW_PREFIX/opt/zopfli/lib/libzopfli.1.dylib"
copy_universal_library libjpeg.62.dylib "$X86_BREW_PREFIX/opt/mozjpeg/lib/libjpeg.62.dylib" "$ARM_BREW_PREFIX/opt/mozjpeg/lib/libjpeg.62.dylib"
copy_universal_library libjpeg.8.dylib "$X86_BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib" "$ARM_BREW_PREFIX/opt/jpeg-turbo/lib/libjpeg.8.dylib"
copy_universal_library libwebpdemux.2.dylib "$X86_BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib" "$ARM_BREW_PREFIX/opt/webp/lib/libwebpdemux.2.dylib"
copy_universal_library libwebp.7.dylib "$X86_BREW_PREFIX/opt/webp/lib/libwebp.7.dylib" "$ARM_BREW_PREFIX/opt/webp/lib/libwebp.7.dylib"
copy_universal_library libsharpyuv.0.dylib "$X86_BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib" "$ARM_BREW_PREFIX/opt/webp/lib/libsharpyuv.0.dylib"
copy_universal_library libtiff.6.dylib "$X86_BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib" "$ARM_BREW_PREFIX/opt/libtiff/lib/libtiff.6.dylib"
copy_universal_library libzstd.1.dylib "$X86_BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib" "$ARM_BREW_PREFIX/opt/zstd/lib/libzstd.1.dylib"
copy_universal_library liblzma.5.dylib "$X86_BREW_PREFIX/opt/xz/lib/liblzma.5.dylib" "$ARM_BREW_PREFIX/opt/xz/lib/liblzma.5.dylib"

for target in "$TOOLS_DIR"/* "$FRAMEWORKS_DIR"/*.dylib; do
  rewrite_dependencies "$target"
done

cp "$SCRIPT_DIR/Resources/ThirdPartyNotices.txt" "$RESOURCES_DIR/ThirdPartyNotices.txt"
find "$APP_DIR" -name '._*' -type f -delete
for target in "$TOOLS_DIR"/* "$FRAMEWORKS_DIR"/*.dylib; do
  codesign --force --sign - "$target"
done
codesign --force --sign - "$APP_DIR"
rm -f "$DIST_DIR/TinyCompressor-macOS-Universal.zip"
(cd "$SCRIPT_DIR/build" && zip -r -X "$DIST_DIR/TinyCompressor-macOS-Universal.zip" TinyCompressor.app >/dev/null)
printf 'Built %s\n' "$APP_DIR"
printf 'Share %s\n' "$DIST_DIR/TinyCompressor-macOS-Universal.zip"
