[日本語](COMPARISON.ja.md) | [English](COMPARISON.en.md) · [Home](../README.md)

# Differences from Windows Voicemeeter

Audiomeeter is an independent macOS implementation, not an official VB-Audio product. It does not promise compatible settings, drivers or DSP.

| Area | Audiomeeter | Relationship to Windows Voicemeeter |
|---|---|---|
| Mixer size | Three to five hardware + two virtual inputs; A1–A3 to A1–A5, B1/B2 | Banana to Potato physical size; two virtual paths because of the drivers |
| Audio backend | Stereo Core Audio HAL | Windows WDM/MME/KS/ASIO settings do not apply |
| DAW I/O | Duplex VAIO playback/B1 capture and AUX playback/B2 capture | Core Audio implementation, not virtual ASIO |
| Plugins | Direct ARM64 VST3 PRE/POST hosting | Windows PATCH INSERT enables round trips through an external ASIO application |
| PATCH COMPOSITE | No equivalent eight-channel assembly | Windows Composite can assemble channels from selected inputs |
| Pads | PAN, tone, modulation, pitch, experimental formant | Different algorithms and sound |
| App trims | Clients of dedicated VAIO/AUX HAL | Not a Windows-wide app-mixer compatibility layer |
| Macros | Macro buttons (Voicemeeter-like script, toggle groups, keys, MIDI) and scenes | Not full MacroButtons syntax compatibility |
| Additional UI | EQ spectrum, mini mixer, per-effect previews, routing matrix, diagnostics | Audiomeeter features |
| Unavailable | VBAN, MIDI feedback, surround, VST2/AU, Intel-only VST3 | Not a replacement for every original feature |

Mix Down is not the original multichannel implementation; see its [actual formula](OUTPUT_BUS.en.md). EQ and limiter DSP are also independent. Cubase-only built-in effects generally are not standalone VST3 products and are not supported scan targets.

Original-product references: [official Banana manual](https://vb-audio.com/Voicemeeter/VoicemeeterBanana_UserManual.pdf), [official Insert Driver guide](https://voicemeeter.com/user-guide-connect-audio-apps-to-the-voicemeeter-insert-driver/). This compares feature categories, not guaranteed compatibility.
