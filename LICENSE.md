# Audiomeeter licensing

Copyright (C) 2026 Audiomeeter contributors.

Except for the components listed below, the project-owned source code, build and
installer scripts, documentation and the project icon assets are licensed
under the GNU Affero General Public License, version 3 only
(SPDX-License-Identifier: AGPL-3.0-only). See LICENSES/AGPL-3.0.txt for the complete
terms. This software is provided without warranty, including implied warranties
of merchantability or fitness for a particular purpose.

## Components retaining their own terms

- Drivers/BlackHoleCore.c and the independent HAL driver distribution: GPL-3.0-only;
  original copyright belongs to Existential Audio Inc. See Drivers/MODIFICATIONS.md
  and LICENSES/BlackHole-GPL-3.0.txt. Other project-owned files under Drivers/ are
  also offered under GPL-3.0-only so the driver can be built independently.
- JUCE 8.0.12: used under its AGPLv3 option. Its upstream notices and dependencies
  retain their original terms; see LICENSES/JUCE-8.0.12.md and THIRD_PARTY_NOTICES.md.
- The bundled VST3 SDK: MIT; see LICENSES/VST3-MIT.txt.
- Apple frameworks are system dependencies and are not redistributed.
- The existing icon was AI-generated at the project owner's request; see Assets/AppIcon.md. It is included under the project license to the extent the contributors hold applicable rights. No claim of human-only authorship or guaranteed copyright eligibility is made.

Only rights held by the Audiomeeter contributors are granted by this notice.
Third-party copyrights, patents and trademarks are not relicensed. No third-party
audio effect binaries are included. Loading a plugin does not grant redistribution
rights; users and distributors must comply with applicable plugin terms.

Redistributed binaries must be accompanied by the applicable license notices and
corresponding source as required by the component licenses. Our release tooling
provides the project's source and pinned JUCE source together, without Git history,
credentials or user data. Keep that archive available with the matching
binary release. Selling copies is permitted under the licenses; recipients retain
their license rights. A proprietary release requires separate permission or
replacement of applicable copyleft dependencies.
