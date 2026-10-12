[日本語](README.md) | [English](README.en.md)

# Audiomeeter

A stereo mixer for Apple Silicon / macOS 14+. Private development build with unnotarized test installers. Independently implemented; not an official VB-Audio product.

[Installation](docs/INSTALL.en.md) · [User guide](docs/USAGE.en.md) · [Comparison](docs/COMPARISON.en.md) · [EQ/pads](docs/PADS_SPECTRUM.en.md) · [Output buses](docs/OUTPUT_BUS.en.md) · [Release](docs/DISTRIBUTION.en.md) · [Licensing](docs/LICENSING.en.md) · [Known issues](docs/AUDIT.en.md) · [Development](docs/DEVELOPMENT.en.md)

## Features

- Three hardware plus VAIO/AUX inputs; A1–A3/B1/B2; channel mapping, PAN/EQ/dynamics.
- ARM64 VST3 PRE/POST inserts, isolated workers, sidechains and latency compensation.
- Dedicated duplex VAIO/B1 and AUX/B2 HAL devices with per-app trims.
- EQ presets/overlaid spectrum; selectable input pads including experimental formant.
- Recording/playback, hotkeys, floating mini mixer, device recovery and launch at login.
- Japanese by default, selectable English. OS/third-party editors use their own languages.

## Installation and licensing

Use the separate app and driver packages. Unnotarized builds may require explicit macOS approval. Source-build installation scripts provide a fallback; see [Installation](docs/INSTALL.en.md). VST2/AU, Intel-only plugins and surround are unsupported.

The app/host/packaging use AGPL-3.0-only; independent HAL drivers use GPL-3.0-only. Dependencies retain their terms. See [LICENSE](LICENSE.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Attach corresponding source alongside release binaries. Signing, notarization and hardware testing remain [public-release gates](docs/AUDIT.en.md).
