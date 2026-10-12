[日本語](DEVELOPMENT.ja.md) | [English](DEVELOPMENT.en.md) · [Home](../README.md)

# Development and Git

This is the canonical implementation, hosted privately at `sawada256/Audiomeeter`. The old Voicemeeter-Mac repository remains separate.

```sh
./build_app.sh
./Tests/run_audio_tests.sh
python3 Tools/check_repository.py
```

Requires Command Line Tools, CMake 3.22+ and Python 3. JUCE 8.0.12 is pinned to an exact commit. Verify and commit each coherent change. Never commit generated apps/HALs, recordings, settings, logs or signing keys. Check `git diff --check` and `git status` before committing.

A private push, changing repository visibility and publishing a Release are separate actions. Visibility changes and Release publication require the owner's explicit instruction. The existing v1.0.0 tag is an early development baseline, not the latest release. Create future release tags from verified commits and build matching assets there.
