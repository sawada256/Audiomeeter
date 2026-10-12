[日本語](INSTALL.ja.md) | [English](INSTALL.en.md) · [Home](../README.md)

# Installation

## Requirements and packages

Apple Silicon, macOS 14+. Packages require no build tools. Quit Audiomeeter and other audio apps, then open `Audiomeeter-App-*.pkg` and, if needed, `Audiomeeter-Drivers-*.pkg`, authorizing with an administrator account. Driver installation restarts Core Audio and briefly interrupts system-wide audio.

Current `LOCAL-UNSIGNED` artifacts have no installer signature or notarization. If blocked, verify their trusted origin/hash, then use Open Anyway in System Settings → Privacy & Security when available. OS versions and managed-device policies may prevent overrides. Stop on malware/damage warnings. Do not disable Gatekeeper globally. See [Apple's instructions](https://support.apple.com/en-us/102445). Clean-machine package installation still needs final testing.

Targets are `/Applications/Audiomeeter.app` and four Audiomeeter bundles in `/Library/Audio/Plug-Ins/HAL/`. Existing Audiomeeter files are backed up in `/Library/Application Support/Audiomeeter/InstallerBackups/`. Legacy Voicemeeter, BlackHole and other HALs remain intact. Failure recovery may require manual backup restoration.

## Source-install fallback

The repository includes installation scripts. Requires Command Line Tools, Git, CMake 3.22+, Python 3 and the macOS SDK. Install CMake/Python from their official distribution or your preferred package manager.

```sh
xcode-select --install
git clone https://github.com/sawada256/Audiomeeter.git
cd Audiomeeter
./install_app.sh
./install_drivers.sh
open /Applications/Audiomeeter.app
```

Cloning the private repository requires its owner or an invited account. Alternatively extract the corresponding-source tar.gz and run the final three commands there. Our source tar.gz includes pinned JUCE; GitHub's automatic Source code archives do not. A normal clone downloads JUCE on its first build.

These scripts build from source, not a portable installation without developer tools. The app installer creates a backup. The driver installer requests administrator rights and replaces only four Audiomeeter HALs. Source-install backups live in `.build/installation-backup/`. Use a consistent signing identity for updates; ad-hoc signing or identity changes can require renewed permissions.

## First launch and permissions

Allow microphone access. Media-key capture needs Accessibility permission for Audiomeeter itself; launch at login may require OS approval. Select hardware output A1 and Audiomeeter VAIO/AUX inputs. Legacy selections are not automatically migrated: reselect devices in macOS and your DAW. See [first sound and DAW routing](USAGE.en.md).

Settings live in `~/Library/Application Support/Audiomeeter`; recordings in `~/Music/AudiomeeterRecordings`. Updates preserve these. Japanese is the default; select English in Audio Settings → 言語 / Language.

## Removal and recovery

Quit and move the app to Trash. With administrator rights, move only Audiomeeter.driver, AudiomeeterAUX.driver, AudiomeeterB1.driver and AudiomeeterB2.driver out of the HAL directory, then restart macOS. Preserve legacy/other-vendor files. Restore saved app/HAL bundles to their original locations for recovery, checking ownership/permissions as administrator before rebooting. Back up settings and recordings separately as needed.
