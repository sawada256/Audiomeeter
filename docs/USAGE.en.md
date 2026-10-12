[日本語](USAGE.ja.md) | [English](USAGE.en.md) · [Home](../README.md)

# User guide

## First sound

1. Follow [Installation](INSTALL.en.md), installing the app and HAL drivers as needed. Start at a low listening level.
2. Select your speakers/interface using the button above A1.
3. Choose Audiomeeter VAIO for VAIO and Audiomeeter AUX for AUX. Select Audiomeeter VAIO as the macOS output to feed system audio into VAIO.
4. Enable VAIO → A1, unmute both strips and adjust their faders.
5. Select Audiomeeter B1 as the input of a call/recording app; enable B1 on each source you want to send.

A1–A3 are hardware outputs; B1/B2 are virtual sends. Route three hardware inputs and VAIO/AUX to these five outputs. Input solo, mute, PAN, EQ and dynamics are also available.

## DAWs and internal routing

For a DAW requiring one input/output device, choose Audiomeeter VAIO: DAW playback feeds VAIO and DAW recording receives B1. AUX similarly pairs with B2. This does not combine the physical A1 device itself. A separate Studio aggregate device is unnecessary.

B1/B2 can also be selected as internal input sources. Sending a return back to itself can create feedback. To record system audio in a DAW, send VAIO → B1 and use AUX or another separate path for DAW playback.

## Inserts and sidechains

Right-click INSERT to open the rack, scan installed plugins and select an ARM64 VST3 by name. Standard VST3 locations are scanned; the plugin's own activation remains necessary. Hardware inputs, VAIO/AUX and output buses support PRE/POST effects.

Left-click the INSERT heading to bypass the chain; left-click an effect preview to toggle that effect; right-click it to open its editor. Use the rack to add, remove or edit effects. Closing an editor leaves processing active. Crashes/timeouts fall back to bypass; isolation is not a security sandbox or a guarantee against excessive CPU use.

Sidechains can be unassigned (silence), an input or an output bus. Acyclic routes use the same block; cyclic routes use the preceding block. Block duration is `1000 × frames / sampleRate` ms (about 5.33 ms at 48 kHz/256 frames). Optional main/sidechain alignment delays the main signal to reduce their time difference. Plugin lookahead is additional latency.

## Settings and latency

Audio settings expose sample rate, buffer size, channel mapping and delay compensation. Smaller buffers reduce latency but increase CPU/dropout risk; hardware may restrict supported values. Select left/right channels from the device's advertised channel count. Mappings are currently saved per bus, not as per-device presets.

Output-bus alignment delays faster buses to match the slowest plugin path. Disable it for independent low-latency monitoring. Plugin latency is shown in samples and milliseconds. Automatic device recovery and launch at login are configurable.

## App trims, hotkeys and mini mixer

APPS lists active audio clients of the dedicated VAIO/AUX HAL. Silent/disconnected apps need not appear. Equivalent control is not guaranteed with third-party HAL drivers.

Choose the volume-key/custom-shortcut target and dB step in settings. Media-key capture requires Accessibility permission for Audiomeeter. Optional OS volume locking keeps virtual-device volume at 100%; it is independent of mixer faders.

Configure always-visible/hold-to-show mode, corner and opacity. Select meters/faders for each of ten strips and optional app trims. Volume/mute hotkeys show the mini mixer for about 1.5 seconds after the last operation. Muted strips use an icon and gray styling. Scroll direction is reversible in settings.

## Recorder and player

Choose the recording source with SRC and format with FMT. Check the source meter before recording, then start/stop recording. The Finder button reveals recordings; the default folder is `~/Music/AudiomeeterRecordings`. Wait for finalization before starting another recording. Load a file into the player and select its destination. Very large playback files can consume substantial memory.

## EQ, pads and output modes

See [EQ/pads/spectrum](PADS_SPECTRUM.en.md) and [output processing/limiter](OUTPUT_BUS.en.md). Language settings affect app-owned UI. OS dialogs and third-party editors follow their providers.
