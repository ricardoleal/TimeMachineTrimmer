![Static Badge](https://img.shields.io/badge/26_Tahoe-orange?label=macOS&style=flat-square)
![GitHub release (with filter)](https://img.shields.io/github/v/release/ricardoleal/TimeMachineTrimmer?style=flat-square)
![Downloads](https://img.shields.io/github/downloads/ricardoleal/TimeMachineTrimmer/TimeMachineTrimmer.dmg?style=flat-square&logo=github&label=Downloads&color=green)

# TimeMachineTrimmer

A lightweight macOS utility to trim old Time Machine backups and reclaim disk space. Still in early development — suggestions and contributions welcome.

> ⬇️ Download from [releases](https://github.com/ricardoleal/TimeMachineTrimmer/releases/latest).

![Header](.github/banner.svg)

## Download

### GitHub Releases

Download the latest `.dmg` from the [Releases Section](https://github.com/ricardoleal/TimeMachineTrimmer/releases/latest).

### Homebrew

```bash
HOMEBREW_GITHUB_API_TOKEN=$(gh auth token) brew tap ricardoleal/tap
brew trust ricardoleal/tap/time-machine-trimmer
brew install --cask time-machine-trimmer
```

> `HOMEBREW_GITHUB_API_TOKEN` is required because the tap repository is private.

## Features

* Trim old backups from any Time Machine volume
* Reclaim disk space by removing snapshots you don't need
* Fast, safe, and macOS-native

## Contributing

Have a look at [open issues](https://github.com/ricardoleal/TimeMachineTrimmer/issues) or open a [new one](https://github.com/ricardoleal/TimeMachineTrimmer/issues/new) to discuss ideas.

> Please do not create pull requests for new features without discussing it first.

When submitting a pull request, make sure you are on a feature branch in your fork.

## Publishing

```bash
# 1. Tag the release
git tag v1.0.0 && git push origin v1.0.0

# 2. CI builds unsigned DMG & creates GitHub Release

# 3. Build & sign locally with your cert
./.scripts/build.sh

# 4. Upload the signed .app from build/ to the Release manually
```

## Development Setup

Clone the repository and open in **Xcode** on macOS 26 (Tahoe).

> **Warning**
> Make sure you change the signing team to your own, otherwise entitlements may not persist.

Then build and run with the `Run` button.

## License

See `LICENSE` file in the root of the repository.
