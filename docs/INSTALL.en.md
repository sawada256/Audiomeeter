# Installation

Requires Apple Silicon, macOS 14+, Xcode Command Line Tools, Git, CMake 3.22+, and Python 3. Internet access is needed for the first pinned JUCE checkout.

Build with `./build_app.sh`, then open `Audiomeeter.app`. Quit it before running `./install_app.sh` to install under `/Applications`; a previous Audiomeeter app is backed up. The existing legacy Voicemeeter app/settings are not migrated or replaced.

For dedicated virtual endpoints, quit audio apps and run `./install_drivers.sh`. This requests administrator authorization, installs four Audiomeeter HAL bundles, and restarts Core Audio, briefly interrupting system audio. Existing Voicemeeter/BlackHole drivers are left alone.

Grant microphone access on launch. Accessibility permission is needed only for media volume key capture. Login-at-startup may also require approval in System Settings. Development/ad-hoc builds are not notarized public releases. Use the same signing identity for updates; ad-hoc builds or changed identities may require renewed permissions.

Select a physical A1 output, Audiomeeter for VAIO, and Audiomeeter AUX for AUX. Set system sound output to Audiomeeter and route VAIO to A1. DAWs selecting Audiomeeter receive B1 and play into VAIO; avoid feedback by leaving VAIO → B1 off when monitoring that capture.

Recordings: `~/Music/AudiomeeterRecordings`. Settings/catalog: `~/Library/Application Support/Audiomeeter`. Choose English in Audio Settings → 言語 / Language.

To uninstall, quit the app and move it to Trash. Remove/backup only the four Audiomeeter `.driver` bundles from `/Library/Audio/Plug-Ins/HAL` with administrator rights, then restart macOS. Preserve other vendors' drivers and your recordings. App/driver backups live in `.build/installation-backup`.

Run `./Tests/run_audio_tests.sh` for offline verification. Optional live HAL tests require exclusive access and can interrupt audio; read the script before enabling them.

## Installer packages

Open the separate Audiomeeter-App and Audiomeeter-Drivers packages on Apple Silicon/macOS 14+. End users do not need build tools. Quit the mixer and audio apps first; driver installation restarts Core Audio. Existing Audiomeeter files are backed up under `/Library/Application Support/Audiomeeter/InstallerBackups/`. Other products and user data are preserved. Recovery after an installation failure may require restoring those backups manually.

LOCAL-UNSIGNED packages are local test artifacts, not notarized public releases. Do not disable Gatekeeper to deploy them. Public release requires Developer ID signing and notarization.

Select Audiomeeter VAIO, Audiomeeter AUX, Audiomeeter B1 and Audiomeeter B2 in the mixer, macOS and DAW. Legacy drivers remain installed; switch selections manually when migrating. Audiomeeter UIDs remain stable.
