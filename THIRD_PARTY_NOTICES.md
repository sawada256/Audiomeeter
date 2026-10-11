# Third-party provenance

- **BlackHole**: `Drivers/BlackHoleCore.c` retains the original 2019 Existential Audio Inc. copyright. This repository contains a modified HAL implementation: per-application trim, independent full-duplex capture/playback transport, and Audiomeeter device naming. See `Drivers/MODIFICATIONS.md`; exact historical checkout provenance remains incomplete and is explicitly not represented as verified. The upstream source is GPLv3; official binaries, trademarks, and artwork have separate terms. [Upstream](https://github.com/ExistentialAudio/BlackHole), [license](LICENSES/BlackHole-GPL-3.0.txt).
- **JUCE 8.0.12**: build-time download of commit `29396c22c93392d6738e021b83196283d6e4d850`. Modules use AGPLv3 or a separate commercial JUCE agreement. Used by the plugin host and isolated worker. A process boundary is not assumed to remove applicable copyleft obligations. [Pinned license](LICENSES/JUCE-8.0.12.md), [upstream](https://github.com/juce-framework/JUCE/tree/8.0.12).
- **Steinberg VST3 SDK**: located inside the pinned JUCE dependency; the actual bundled SDK license is MIT, copyright 2025 Steinberg Media Technologies GmbH. [License](LICENSES/VST3-MIT.txt). This does not grant VST trademark rights or permission to redistribute third-party plugins.
- **Other JUCE dependencies**: notices shipped in the app include the dependency license files from the pinned source tree. The top-level JUCE license inventories them. Audit which codecs and frameworks are compiled into a release binary before publishing a final SBOM.
- **Apple system frameworks**: linked from the macOS SDK and not redistributed here.
- **Audiomeeter artwork**: the owner confirmed on 2026-10-12 that the existing icon was created through AI image generation at their request. It is retained for local and public builds; see `Assets/AppIcon.md`. No VB-Audio-provided logo asset is included. Similarity/trademark clearance for the name and overall UI remains a separate release task.

This is an attribution inventory, not a warranty of complete copyright clearance.

Project-owned application, host, packaging and documentation: AGPL-3.0-only. Independent driver source and driver build scripts: GPL-3.0-only. See LICENSE.md for scope. Distribution source archives include the pinned JUCE tree, including embedded third-party license headers.
