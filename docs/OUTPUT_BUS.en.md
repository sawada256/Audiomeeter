[日本語](OUTPUT_BUS.ja.md) | [English](OUTPUT_BUS.en.md) · [Home](../README.md)

# Output buses, EQ and limiter

The default signal order is **PRE INSERT → FADER / MODE → POST INSERT → EQ → LIMIT**. EQ can be placed before the insert group, after it, before LIMIT or after LIMIT. After inserts and before LIMIT are the same position with the other stages fixed. The EQ panel follows the selected order. The physical fader stays at the bottom; a FADER line marks its signal position.

Left-click EQ to toggle it; right-click EQ or click its curve to edit. Save/recall presets in the editor. INSERT combines PRE/POST into a three-row scrolling preview. When POST exists, the FADER line marks the boundary. Tooltips reveal truncated names.

Left-click LIMIT to toggle it; right-click to configure Threshold, Ceiling and Lookahead. Gain reduction lights it red, retaining short peak indications. Lookahead options are OFF/1/3/5/10/20 ms. OFF retains sample-wise soft-knee limiting; ON uses stereo-linked peak detection and a 50 ms release. Added latency is `floor(sampleRate × ms / 1000)` samples and participates in compensation. This is not oversampled/True Peak limiting. EQ boosts after LIMIT can exceed its Ceiling.

Normal preserves stereo. Mono sends `(L + R) × 0.5` to both channels; Mix Down sends `(L + R) × 0.7071`. For correlated signals, Mix Down is about 3 dB louder than Mono. It is not surround downmixing.

An insert meter's 0 dBFS denotes digital full scale, distinct from fader 0 dB (unity gain) and the +12 dB adjustment range. Floating-point processing may exceed 0 dBFS internally; physical outputs can still clip.
