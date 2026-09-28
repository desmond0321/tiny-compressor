# Tiny Compressor

A native macOS app for recursively compressing PNG, JPG, and JPEG files. It uses a TinyPNG-like PNG pipeline (`pngquant` plus Zopfli/OxiPNG), MozJPEG for JPEG files, and can convert either format into compressed WebP files.

## Use

1. Download the universal macOS release ZIP from GitHub Releases.
2. Unzip it and move `TinyCompressor.app` to Applications.
3. Open the app, then drag files or folders into the main drop area or directly into the Drop Queue sidebar. Select a queue item and use **Remove**, `Delete`, or right-click **Remove from Queue** to remove it before processing. The preview toolbar also has a trash button to remove the current image.
   Select an image in the drop queue and click **Preview**, or press `Space`, to inspect it before processing. In the preview, press `Up` or `Down` to move through queued images and `Space` or `Esc` to close. Completed images show a checkmark in the queue; folders show their completed image count while running.
4. Choose whether to save beside the originals, use a separate output folder, or replace the originals. Files saved beside an original use `-compressed` before the extension.
5. Select **Compressed WebP files** to convert images to WebP at the selected quality. WebP files can be saved beside originals as `name.webp` or in a separate output folder; they never replace originals.

The release bundle includes its compression tools, so end users do not need Homebrew. The app supports Apple Silicon and Intel Macs.

## Defaults

- PNG quality: `40-80`
- PNG speed: `1`
- Zopfli final pass: enabled
- JPEG quality: `78`
- WebP quality: `75`
- Concurrent images: `4`
- `.bak` backups: disabled

## Build

This release build is universal and bundles both ARM and Intel versions of the compression tools. The maintainer machine needs both Homebrew installations:

```sh
# Apple Silicon Homebrew
arch -arm64 /opt/homebrew/bin/brew install pngquant zopfli oxipng mozjpeg jpegoptim webp

# Intel Homebrew under Rosetta
arch -x86_64 /usr/local/bin/brew install pngquant zopfli oxipng mozjpeg jpegoptim webp

sh TinyCompressor/build-app.sh
```

The release ZIP is created at `TinyCompressor/dist/TinyCompressor-macOS-Universal.zip`.

## Third-Party Software

The app bundles pngquant, Zopfli, OxiPNG, MozJPEG, JPEGOptim, libwebp, and their required libraries. See [ThirdPartyNotices.txt](TinyCompressor/Resources/ThirdPartyNotices.txt) for licenses and source links. Review the applicable redistribution requirements before publishing a public release.
