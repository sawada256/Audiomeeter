[日本語](PADS_SPECTRUM.ja.md) | [English](PADS_SPECTRUM.en.md) · [Home](../README.md)

# Input pads and EQ spectrum

The hardware-input pad switches between PAN, INTELLIPAN, MODULATION, PITCH and FORMANT (EXP). Use its selector or right-click to cycle modes in the same area. Standard PAN supports center snapping and double-click reset. INTELLIPAN Bright/Dark uses tonal shelves, not simple high/low-pass filters.

MODULATION provides chorus-like modulation; PITCH is a lightweight pitch effect. FORMANT is a separate experimental pad moving fixed resonances, not precise vocal-tract analysis or pitch-independent formant resynthesis. Treat it as a creative voice effect rather than a commercial voice-conversion algorithm.

Open output EQ by right-clicking EQ or clicking its curve. Spectrum is optional and overlays the EQ on a shared frequency axis. The left scale is EQ gain; the right scale is spectrum level. Configure FFT size (2048–16384), window, averaging, display rate and slope. The default approximately 3.01 dB/oct slope makes pink noise (1/f power density) roughly flat. It changes visualization, not audio.

Fast mode favors a smaller FFT, shorter averaging and faster updates. Larger FFTs improve frequency resolution while smearing time; averaging further slows response. Top and Range set the visible dB limits; Auto fits the current peak once.

Even when enabled, spectrum collection, FFT and rendering stop while the EQ editor is closed. FFT runs outside the audio callback; bounded frame rates and separate display updates limit overhead. High resolution/rates still use more CPU; lower them if audio drops out.
