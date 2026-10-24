[日本語](DISTRIBUTION.ja.md) | [English](DISTRIBUTION.en.md) · [Home](../README.md)

# GitHub Release assets

Attach all of these to the same GitHub Release of the public repository; they are unsigned, unnotarized test builds. Attach them together:

| Asset | Purpose |
|---|---|
| `Audiomeeter-App-1.1.0-13-arm64-LOCAL-UNSIGNED.pkg` | App, plugin host and notices |
| `Audiomeeter-Drivers-1.1.0-13-arm64-LOCAL-UNSIGNED.pkg` | Four VAIO/AUX/B1/B2 HALs |
| `Audiomeeter-Source-1.1.0-13.tar.gz` | Matching source, modified HAL, pinned JUCE, install scripts/docs |
| `release-manifest-1.1.0-13-arm64-LOCAL-UNSIGNED.json` | Source revision and SHA-256 hashes |

Do not substitute GitHub's automatic Source code archives for the corresponding-source artifact. Binary recipients need access to matching source. If the repository is ever made private, corresponding source is still provided separately to people who already received binaries.

## Release body template

> Audiomeeter 1.1.0 build 13 — test build / 試験版
> Apple Silicon / macOS 14+ only. Not notarized; installer packages unsigned. / 未公証・パッケージ署名なし。
> Install App, then Drivers if virtual routing is needed. Quit audio apps first; driver installation restarts Core Audio. / 本体→必要ならドライバの順。事前に音声アプリを終了。
> See Installation / User guide / Known issues in both languages. Corresponding source and SHA-256 manifest are attached. / 日英導入・操作・既知の課題を参照。対応ソースとハッシュ同梱。
> No third-party effect binaries. AGPL-3.0-only app; GPL-3.0-only HAL. / 第三者プラグイン本体は非同梱。

Before publishing, link to tagged docs and add the exact revision, tested environment and changes. The old v1.0.0 tag is an early baseline; create a fresh prerelease tag from the verified commit.

## Build and verify

```sh
./build_installers.sh
python3 Tools/verify_installers.py
```

Requires a clean committed tree. Unsigned packages are always ad-hoc signed and the build stops otherwise, so a personal development certificate (which embeds the developer's name and email) never ends up in a release. Outputs remain in ignored dist/. To repackage an existing marked release build, use `./build_installers.sh --skip-build`. Nothing is uploaded automatically.

## Before general distribution

Obtain Developer ID Application/Installer certificates. Set `VM_CODESIGN_IDENTITY` and `VM_INSTALLER_SIGNING_IDENTITY`, then run `./build_installers.sh --signed`. Never commit keys. Signing still requires Apple notarization submission, success verification and stapling. Recalculate final hashes and accurately update manifest notarization status. See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Test installation, updates, recovery, HAL I/O and permissions on clean Macs before general distribution. Suitable Developer ID certificates are unavailable here; these gates remain open. See [Known issues](AUDIT.en.md).
