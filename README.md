# Tiny Compressor

A native macOS app for recursively compressing PNG, JPG, and JPEG files. It uses a TinyPNG-like PNG pipeline (`pngquant` plus Zopfli/OxiPNG) and MozJPEG for JPEG files.

## Use

1. Download the universal macOS release ZIP from GitHub Releases.
2. Unzip it and move `TinyCompressor.app` to Applications.
3. Open the app, then drag files or folders into the drop area.
4. Choose an output folder or enable in-place replacement, configure quality and concurrency, then click **Compress Images**.

The release bundle includes its compression tools, so end users do not need Homebrew. The app supports Apple Silicon and Intel Macs.

## Defaults

- PNG quality: `40-80`
- PNG speed: `1`
- Zopfli final pass: enabled
- JPEG quality: `78`
- Concurrent images: `4`
- `.bak` backups: disabled

## Build

This release build is universal and bundles both ARM and Intel versions of the compression tools. The maintainer machine needs both Homebrew installations:

```sh
# Apple Silicon Homebrew
arch -arm64 /opt/homebrew/bin/brew install pngquant zopfli oxipng mozjpeg jpegoptim

# Intel Homebrew under Rosetta
arch -x86_64 /usr/local/bin/brew install pngquant zopfli oxipng mozjpeg jpegoptim

sh TinyCompressor/build-app.sh
```

The release ZIP is created at `TinyCompressor/dist/TinyCompressor-macOS-Universal.zip`.

## Third-Party Software

The app bundles pngquant, Zopfli, OxiPNG, MozJPEG, JPEGOptim, and their required libraries. See [ThirdPartyNotices.txt](TinyCompressor/Resources/ThirdPartyNotices.txt) for licenses and source links. Review the applicable redistribution requirements before publishing a public release.
