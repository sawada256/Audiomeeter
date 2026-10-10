# Audiomeeter v1

A private development snapshot of a stereo mixer for Apple Silicon and macOS 14+. Audiomeeter is an independent project, not an official VB-Audio product and not a claim of binary/driver compatibility.

Three hardware inputs, VAIO/AUX virtual inputs, A1–A3/B1/B2 output buses, stereo channel mapping, EQ presets, dynamics, PAN, recording/playback, app trims, custom/media hotkeys, and a mini mixer are included. ARM64 VST3 effects run in separate worker processes with PRE/POST inserts, sidechain routing, and latency compensation. VST2/AU, Intel-only plugins, surround, and Windows ASIO compatibility are not implemented.

Japanese is the default. Switch to English in Audio Settings → 言語 / Language. Third-party plugin editors, native OS authorization dialogs, and device/application names remain controlled by their vendors or the OS.

Build using `./build_app.sh` and verify with `./Tests/run_audio_tests.sh`. See [installation](INSTALL.en.md). No Git remote is configured. A release license for project-owned code has not been selected; this is not a cleared-for-distribution release. Read [licensing](LICENSING.ja.md) and [audit / release blockers](AUDIT.ja.md) before publishing.
