[日本語](AUDIT.ja.md) | [English](AUDIT.en.md) · [Home](../README.md)

# Verification, limitations and improvements

Static review, offline regression tests, builds and selected UI/live legacy-HAL checks have been performed. These do not prove absence of bugs on every Mac, device or plugin.

## Fixes and checks

Recording filenames include UUIDs to avoid overwrites. Recording finalization is asynchronous and serialized; write errors are surfaced. Invalid channel selections return silence rather than stale/unintended channels. Individual channel mappings override the old pair API correctly. App updates stage and verify copies with backups; the source HAL installer can roll back changed targets.

Media-key capture runs separately from the UI and excludes mouse events. Meter updates do not redraw the full mixer. Plugin workers fall back on crash/hang without synchronous real-time IPC waits. Acyclic sidechains use the current block; cyclic paths use history. Recording meters use the selected recording tap.

Regression coverage includes SPSC transport, underruns, interleaving/channel maps, resampling and drift models, buffer sizes, DSP gain/limiting/EQ, recording drain/restart, ARM64 test VST3 state and sidechains, crash/hang fallback, actual mixer impulse/PDC/routing, app trims (also ASan/UBSan), duplex driver transport, media-key lifecycle and mouse exclusion, settings and localization placeholders. Installer verification expands payloads and checks architecture, identity, signatures, notices and source archives.

Run `./Tests/run_audio_tests.sh`, `./build_app.sh`, `./Drivers/build_all_drivers.sh`, `python3 Tools/check_repository.py` and `python3 Tools/verify_installers.py`. Live HAL tests are opt-in and can interrupt audio. Generated logs remain in `.build`.

## Remaining release gates

- Developer ID signing/notarization and clean-machine package installation, update/recovery and removal remain unverified. New Audiomeeter HAL packages have not been installed on this development Mac; selected live checks used legacy HALs.
- Test UMC channel outputs, multiple USB/Bluetooth devices, sleep/wake, hotplug and supported macOS versions. Unusual stream formats are not comprehensively tested.
- Restore exact historical BlackHole checkout provenance; finalize dependency inventory and name/UI trademark review. The owner confirmed the icon is AI-generated original artwork, which is not trademark clearance.
- Process separation is not a security sandbox: plugins can access files/network and exhaust resources. Commercial plugin/activation compatibility is not exhaustive.
- Disk-full/removal, power loss, very long recording and overflow visibility need further testing. Playback currently loads files into memory.
- Accessibility, VoiceOver, long labels and every layout/language combination are not fully covered. OS/plugin localization is external.
- No VST2, AU, Intel-only plugin support, surround or Windows ASIO compatibility. Version 1 is a version identifier, not a claim of production certification.

## Suggested next improvements

1. Save channel mappings by device UID and bus, instead of bus alone.
2. Add diagnostics for underruns, dropped blocks, plugin deadline misses, recording overflow and measured latency.
3. Add routing/EQ scenes and click-reducing transitions.
4. Show the hotkey's target temporarily even if hidden in the mini mixer; make timeout configurable.
5. Stream playback, split long recordings and expose disk/overflow warnings.
6. Add plugin scan quarantine, resource monitoring and recovery policies.
7. Add clean CI, an SBOM and a hardware/macOS installation test matrix.

## Existing-environment migration

Audiomeeter has its own app identity/settings and retains explicit legacy HAL UID compatibility. Original English labels remain in Japanese mode; English mode translates Japanese messages. The old personal icon is preserved. Audiomeeter needs its own Accessibility grant; the old app's permission does not transfer. Legacy duplex/app-trim checks and language switching were exercised, but disconnected UMC output hardware was not measured.
