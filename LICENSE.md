# Licensing status — private development snapshot

No outbound license has yet been selected for project-owned Audiomeeter code or artwork. This notice is not a claim of ownership over third-party material, does not relicense that material, and does not restrict rights already granted by its license. Keep this repository private until the owner chooses compatible release terms and completes the provenance review.

`Drivers/BlackHoleCore.c` is modified BlackHole code, copyright Existential Audio Inc., under GPLv3. See `LICENSES/BlackHole-GPL-3.0.txt` and `THIRD_PARTY_NOTICES.md`. JUCE modules used by the build are dual licensed under AGPLv3 and a commercial JUCE agreement. See `LICENSES/JUCE-8.0.12.md`. The vendored VST3 SDK within pinned JUCE carries its own MIT license.

A practical open-source release option is AGPL-3.0 for the combined JUCE-linked application/host and GPL-3.0 for the independent modified HAL driver, preserving each component's notices and providing corresponding build/install source. Do not describe the entire current distribution as MIT-only. Commercial/proprietary distribution requires separate review of both JUCE and BlackHole permissions; buying one license does not resolve the other.

No third-party effect plugins or proprietary SDKs are included in this repository. Merely finding installed plugins does not grant redistribution rights for those plugins.
