# Audiomeeter HAL driver modifications

SPDX-License-Identifier: GPL-3.0-only

Original implementation: BlackHole, Copyright (C) 2019 Existential Audio Inc.
Upstream: https://github.com/ExistentialAudio/BlackHole

Modified for Audiomeeter in 2026:

- Four independently named stereo endpoints: Audiomeeter VAIO, AUX, B1 and B2.
- VAIO/B1 and AUX/B2 full-duplex DAW transports with independent rings.
- Per-client application gain controls, safe client lifecycle and ring bounds.
- UID compatibility, separate plugin factory UUIDs and build/install scripts.

These are source-built derivatives, not official BlackHole binaries. BlackHole
names and trademarks identify provenance only; no logo or official installer is
included. Copyright notices and the upstream GPL notice are retained in
LICENSES/BlackHole-GPL-3.0.txt. The precise historical upstream checkout used
before this repository was created is not known; do not claim a verified original
commit or an endorsement by Existential Audio. The current complete modified
source is supplied with distribution source archives.
