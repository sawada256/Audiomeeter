[日本語](README.md) | [English](README.en.md)

# Audiomeeter

A flexible stereo virtual audio mixer for Apple Silicon / macOS 14+. Route microphones, audio interfaces, system audio and calling apps to speakers, headphones and streaming/calling apps, and shape them with gain, EQ, dynamics and VST3 effects.

> **Relationship to the original**
> Audiomeeter is an independent macOS implementation inspired by the workflow of [Voicemeeter](https://vb-audio.com/Voicemeeter/) for Windows (VB-Audio Software). It is not affiliated with, endorsed by or an official product of VB-Audio, and it is not compatible with Voicemeeter's settings, drivers or sound. No Voicemeeter code, images or logos are used.
> If the rights holder or anyone concerned raises an issue about the name, appearance or anything else, this repository will promptly be made private and then corrected or withdrawn. Please get in touch through [Issues](https://github.com/sawada256/Audiomeeter/issues).

[Install & uninstall](docs/INSTALL.en.md) · [User guide](docs/USAGE.en.md) · [EQ/pads](docs/PADS_SPECTRUM.en.md) · [Output buses](docs/OUTPUT_BUS.en.md) · [Comparison](docs/COMPARISON.en.md)

## Download

Get the installers from [Releases](https://github.com/sawada256/Audiomeeter/releases).

| File | Contents |
|---|---|
| `Audiomeeter-App-*.pkg` | The app (`/Applications/Audiomeeter.app`) and VST3 host |
| `Audiomeeter-Drivers-*.pkg` | Dedicated virtual devices **Audiomeeter VAIO / AUX / B1 / B2** (Core Audio HAL drivers) |

1. Quit Audiomeeter and audio apps (calling apps, DAWs).
2. Open `Audiomeeter-App-*.pkg` and install.
3. To use the dedicated VAIO/AUX/B1/B2 devices, also install `Audiomeeter-Drivers-*.pkg` (all Mac audio pauses for a few seconds).
4. Open Audiomeeter and allow microphone access.

Current packages are **test builds without signing or Apple notarization**. If macOS refuses to open them, check where you downloaded them and use "Open Anyway" in System Settings → Privacy & Security. See [Install & uninstall](docs/INSTALL.en.md).

## Layout

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│ AUDIOMEETER   Mac output: [▾] [→VAIO]  ENGINE LIVE  48000 Hz  256 samples   Menu ▾ │
├───────────────────────────────────────────────────────────────────────────────────┤
│ Recorder/player  REC / PLAY / PAUSE / STOP / LOOP   SRC / FMT   PLAY TO [A1..B2]  │
├──────────┬──────────┬──────────┬──────────┬──────────┬────────────────────────────┤
│ HARDWARE │ HARDWARE │ HARDWARE │   VAIO   │   AUX    │ MASTER SECTION             │
│ INPUT 1  │ INPUT 2  │ INPUT 3  │ (system) │ (calls)  │  A1  A2  A3   B1  B2       │
│ PAD      │ PAD      │ PAD      │ EQ 3band │ EQ 3band │  device / Mac volume bar   │
│ COMP/GATE│ COMP/GATE│ COMP/GATE│ KARAOKE  │ KARAOKE  │  MODE / Mute / INSERT      │
│ INSERTS  │ INSERTS  │ INSERTS  │ APPS     │ APPS     │  EQ (6-band) / LIMIT       │
│ [A1..A3] │ [A1..A3] │ [A1..A3] │ INSERTS  │ INSERTS  │                            │
│ [B1][B2] │ [B1][B2] │ [B1][B2] │ PAN      │ PAN      │                            │
│ Mute/Solo│ Mute/Solo│ Mute/Solo│ Mute/Solo│ Mute/Solo│                            │
│ Fader/VU │ Fader/VU │ Fader/VU │ Fader/VU │ Fader/VU │  Fader / VU                │
└──────────┴──────────┴──────────┴──────────┴──────────┴────────────────────────────┘
```

Use 3–5 hardware inputs and A1–A3 up to A1–A5 (Audio Settings → Engine).

## Features

### Mixer and routing
- **Inputs**: 3–5 hardware inputs and two virtual inputs (**VAIO** = Mac system audio, **AUX** = calling apps and others).
- **Outputs**: physical A1–A5 (speakers, headphones) and virtual B1/B2 (mixes for streaming, calling and recording apps). **A1 is the master clock.**
- Per-input `A1–A5`, `B1`, `B2` buttons send any input to any output; a **routing matrix** window shows everything at once.
- Left/right channels are selectable per input and output (the same channel for both gives mono).
- Independently clocked devices are synchronized by adaptive clock correction and sample-rate conversion. Inputs and extra output channels on the A1 device itself are read and written directly in the A1 callback, without correction.
- Unplugged devices and stalled audio are detected and reconnected automatically.

### Input strips
- **Hardware inputs**: PAD (COLOR PAN [tone + balance] / PAN / MODULATION / PITCH / FORMANT [experimental]), COMP, GATE.
- **Virtual inputs**: 3-band EQ (BASS/MED/TREBLE, three presets), KARAOKE (center vocal reduction), PAN, per-app volume (APPS).
- All inputs: gain (−60 to +12 dB, double-click for 0 dB), Mute/Solo, PRE/POST VST3 inserts, peak/RMS meters.

### Output buses
- Mode (Normal / Mix Down / Mono), Mute, gain and extra delay for device alignment.
- **6-band parametric EQ** with three presets and an overlaid spectrum analyzer.
- **Limiter** (threshold, ceiling, 0–20 ms lookahead).
- Selectable signal order (EQ before or after the inserts, before or after the limiter).
- Under each bus header, the assigned device's **macOS output volume bar** and mute — the Mac volume is applied last, so this is where to check it.

### VST3 effects
- ARM64 VST3 effects on inputs and buses, PRE or POST. Each plugin runs in **its own process**; a crash or overload never stops the mixer (it falls back to latency-matched dry audio and restarts automatically by default).
- Adding, removing, reordering and sidechain changes apply without stopping audio.
- **Latency compensation (PDC)** for routes into the same bus, between output buses, and between sidechain and main signal (each switchable).
- **Sidechains** from any input or output bus (cyclic links use the previous block).
- **Two bypass kinds**: soft (latency kept, gray) and full (removed from the path, black). Option-click uses the other kind.
- **MIDI input** to plugins, and MIDI-controller control of plugin parameters.

### Dedicated virtual devices (driver package)
- **Audiomeeter VAIO / AUX**: playback targets for apps, feeding the VAIO/AUX inputs.
- **Audiomeeter B1 / B2**: input devices that deliver the B1/B2 buses to recording, streaming and calling apps.
- Full duplex for DAWs: choosing Audiomeeter VAIO in a DAW plays to VAIO and records from B1 (AUX pairs with B2).
- **Per-app volume** for apps playing to VAIO/AUX, remembered per app.

### Control and automation
- **Mac output switching**: pick where apps play (the same setting as Control Center) from the top bar; "→VAIO" switches in one tap and back on the next.
- **MIDI controllers**: MIDI Learn (also from a fader's right-click menu), CC, notes and pitch bend (14-bit faders), two relative encoder formats, pickup (no jumps), toggle/follow buttons.
- **Macro buttons**: scripts that run several actions (e.g. `Strip[0].A1 = 1; Bus[1].Gain -= 3; Scene = "Streaming"`); push, toggle or momentary, radio groups, keys and MIDI.
- **Scenes**: save and recall routing, levels, Mute/Solo, EQ, dynamics and insert states together, with a selectable recall scope and JSON export/import.
- **Hotkeys** and the Mac **volume keys** drive faders; a floating **mini mixer** shows faders, meters and per-app volume.
- **Diagnostics** window: load, deadline overruns, per-path mode, buffer state, clock correction and latency, per-plugin processing time and restarts, recording drops.

### Recording and playback
- Record any bus or input to WAV (16/24/32-bit float) or AAC (128–320 kbps).
- Play audio files into any buses (loop, seek, streamed from disk).

### Other
- Japanese (default) and English. Settings are saved automatically. Optional launch at login.

## Example: mix your microphone and system audio for streaming or calls

1. Choose headphones or speakers (or an audio interface) for **A1**.
2. Choose your microphone for **HARDWARE INPUT 1** and turn on `B1` (send your voice). Turn on `A1` too to hear yourself.
3. Choose **Audiomeeter VAIO** for the **VAIO** input and turn on `A1` (listen) and `B1` (stream it).
4. Select **Audiomeeter VAIO** in "Mac output" at the top (or press "→VAIO"). Browser and game audio now enter VAIO.
5. Set your calling app's output to **Audiomeeter AUX**; turn on only `A1` for AUX (leave `B1` off so the other party is not sent back).
6. Choose **Audiomeeter B1** as the microphone (input) in your calling app and OBS.

See the [user guide](docs/USAGE.en.md) for DAW setups.

## Requirements and limitations

- Apple Silicon Mac, macOS 14 or later. Stereo processing (32-bit float).
- ARM64 VST3 effects only (no VST2, AU, Intel-only plugins or instruments).
- This is a test build: unsigned, unnotarized and not tested with every device and macOS combination. Turn volumes down before you start.
- VST3 plugins run in separate processes, but that does not make a plugin itself safe. Use plugins you trust.
- Not a replacement for every Voicemeeter feature (network audio, surround and others) and not settings-compatible ([Comparison](docs/COMPARISON.en.md)).

## Troubleshooting

- **No sound**: check input/output Mute, the A1 device, the Mac volume bar under the bus header (0% or muted is silent), and that "Mac output" at the top is Audiomeeter VAIO. Menu → "Diagnostics…" shows the state of every path.
- **Dropouts**: increase the buffer size in Audio Settings.
- **Dedicated devices missing**: restart the Mac after installing the driver package.
- Report problems or ideas in [Issues](https://github.com/sawada256/Audiomeeter/issues).

## Building from source

You can also build it yourself instead of using the packages (requires Xcode Command Line Tools, CMake 3.22+ and Python 3).

```sh
git clone https://github.com/sawada256/Audiomeeter.git
cd Audiomeeter
./install_app.sh        # build and install the app to /Applications
./install_drivers.sh    # build and install the dedicated devices (admin authentication)
```

## License

The app, VST3 host and packaging tools are **AGPL-3.0-only**; the dedicated HAL drivers (modified from [BlackHole](https://github.com/ExistentialAudio/BlackHole)) are **GPL-3.0-only**. Dependencies such as JUCE and the VST3 SDK keep their own terms. See [LICENSE](LICENSE.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Each Release includes the corresponding source for its binaries (`Audiomeeter-Source-*.tar.gz`).

Voicemeeter is a trademark of VB-Audio Software. Other product names are trademarks of their respective owners.
