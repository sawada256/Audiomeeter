# Audiomeeter v1

A private development snapshot of a stereo mixer for Apple Silicon and macOS 14+. Audiomeeter is an independent project, not an official VB-Audio product and not a claim of binary/driver compatibility.

Three hardware inputs, VAIO/AUX virtual inputs, A1–A3/B1/B2 output buses, stereo channel mapping, EQ presets, dynamics, PAN, recording/playback, app trims, custom/media hotkeys, and a mini mixer are included. ARM64 VST3 effects run in separate worker processes with PRE/POST inserts, sidechain routing, and latency compensation. VST2/AU, Intel-only plugins, surround, and Windows ASIO compatibility are not implemented.

Japanese is the default. Switch to English in Audio Settings → 言語 / Language. Third-party plugin editors, native OS authorization dialogs, and device/application names remain controlled by their vendors or the OS.

Build using `./build_app.sh` and verify with `./Tests/run_audio_tests.sh`. See [installation](INSTALL.en.md). No Git remote is configured. A release license for project-owned code has not been selected; this is not a cleared-for-distribution release. Read [licensing](LICENSING.ja.md) and [audit / release blockers](AUDIT.ja.md) before publishing.

## Input PADs and spectrum analyzer (build 5)

Choose PAN, INTELLIPAN, MODULATION, PITCH or FORMANT (EXP) from a hardware input PAD menu. Right-click cycles modes; double-click centers. INTELLIPAN brightness uses low/high shelves, not high/low-pass filtering. Modulation is stereo chorus. Pitch spans ±12 semitones; the menu selects nominal ~10 ms or ~20 ms latency, included in path compensation. Granular artifacts are possible, and its time-varying read delay is not exact phase alignment. FORMANT is experimental shifting of fixed vowel-like resonances, without pitch changes or envelope analysis/resynthesis.

SPECTRUM in the EQ editor toggles analysis. Defaults: OFF, 8192-point Hann FFT, 300 ms averaging, 1/6-octave smoothing, +3.01 dB/oct display slope for flat pink-noise power. Analysis stops when disabled or the editor closes. FFT runs on a utility queue; only the spectrum plot observes its 20 fps frames. Recorder reels update only while active, at 15 fps.

EQ placement is before the INSERT group, after it / before LIMIT, or after LIMIT. After INSERT and before LIMIT are equivalent in the fixed PRE → FADER → POST → LIMIT chain.

Build 6 overlays the spectrum on the restored 200 pt EQ plot, sharing its 20 Hz–20 kHz frequency axis. EQ gain is on the left; slope-adjusted spectrum levels are on the right. Response → Fast selects 2048-point FFT, 30 ms averaging and up to 60 fps. FFT, Avg and FPS remain individually adjustable; Avg 0 ms disables averaging. Shorter windows respond faster but reduce frequency resolution, especially in the bass.

Build 7 increases the shared graph to 270 pt by using the remaining vertical space. On smaller screens, vertical scrolling keeps all controls accessible.

## EQ spectrum rendering (build 8)

Spectrum frames now pass through a latest-frame mailbox to a native CAShapeLayer, with Core Animation interpolation instead of per-frame SwiftUI notifications. FFT analysis continues to use Apple Accelerate/vDSP; no new third-party dependency is required. Periodic HAL app-list reads run on a serial background queue, with stale-result rejection and no overlapping requests. Unchanged state no longer triggers redundant UI notifications, and EQ response curves reuse filter coefficients. The visible v1 badge is removed; bundle metadata and Git retain version tracking.

## Spectrum range and limiter lookahead (build 9)

Spectrum Top selects the upper display level (−60 to +24 dB); Range selects a 40/60/80/100/120 dB span. Auto fits the latest displayed peak with at least 6 dB of headroom in 12 dB steps, preserving the span. This changes only the spectrum scale.

Right-click LIMIT to select Lookahead OFF/1/3/5/10/20 ms. OFF preserves legacy zero-latency soft-knee waveshaping. ON adds the selected delay and uses linked stereo sliding-peak gain control with a 50 ms release. This is sample-peak limiting, not true-peak processing. Delay participates in existing route/output alignment; mode changes reset history and may briefly interrupt audio. Default remains OFF.
