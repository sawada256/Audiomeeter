[日本語](LICENSING.ja.md) | [English](LICENSING.en.md) · [Home](../README.md)

# Licensing and distribution

Project-owned app, host, packaging, documentation and icon assets use AGPL-3.0-only, to the extent contributors hold rights. Independent HAL source/build files use GPL-3.0-only. Full terms and exceptions are in [LICENSE](../LICENSE.md); preserve upstream notices. This is not an MIT-only project.

| Component | Terms and obligations |
|---|---|
| Swift app and project host code | AGPL-3.0-only; provide notices and corresponding source as required |
| JUCE 8.0.12 | AGPLv3 option, or a separate commercial agreement; process isolation does not automatically remove obligations |
| Modified BlackHole HAL | GPLv3; retain attribution, modification notice, license and corresponding source/build instructions |
| Bundled VST3 SDK | Actual bundled license is MIT; retain its copyright and permission notice |
| User-installed effects | Each vendor's terms; scanning/loading does not grant redistribution rights |
| Name/icon/UI | Copyright and trademark questions are separate; no clearance guarantee |

Open-source distribution under these terms is the prepared route. Selling copies is permitted while preserving recipients' rights. Project-owned portions could separately use other terms if their owners choose, but dependencies prevent describing the whole combined distribution as MIT-only. Proprietary distribution requires appropriate separate permissions or replacement of copyleft dependencies; a JUCE agreement alone does not resolve driver obligations.

Attach the exact corresponding-source archive, including pinned JUCE and modified HAL/build scripts, with binaries. Preserve availability for recipients. Third-party effect binaries and keys are not included. Distribution of a combined proprietary plugin/host product requires a separate licensing assessment.

The exact initial BlackHole checkout has not been reconstructed. Final dependency/SBOM checks, VST trademark usage and Audiomeeter name/UI review remain. The owner confirmed on 2026-10-12 that the existing icon was originally AI-generated at their request; see [provenance](../Assets/AppIcon.md). This does not establish trademark clearance or guaranteed copyright eligibility.

Official references: [pinned JUCE license](https://github.com/juce-framework/JUCE/blob/8.0.12/LICENSE.md), [JUCE commercial agreement](https://juce.com/legal/juce-8-licence/), [BlackHole source/license](https://github.com/ExistentialAudio/BlackHole), [Steinberg SDK information](https://www.steinberg.net/developers/).

This describes implementation dependencies, not a guarantee of legal clearance. The repository is privately managed at the owner's request; public distribution remains separate.
