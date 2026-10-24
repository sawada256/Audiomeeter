[日本語](DEVELOPMENT.ja.md) | [English](DEVELOPMENT.en.md) · [Home](../README.md)

# Development and Git

This is the canonical implementation, published at `sawada256/Audiomeeter`. The earlier prototype from before the rename lives in a separate repository and is not included.

```sh
./build_app.sh
./Tests/run_audio_tests.sh
python3 Tools/check_repository.py
```

Requires Command Line Tools, CMake 3.22+ and Python 3. JUCE 8.0.12 is pinned to an exact commit. Verify and commit each coherent change. Never commit generated apps/HALs, recordings, settings, logs or signing keys. Check `git diff --check` and `git status` before committing.

Pushes and Release publication require the owner's explicit instruction. If the rights holder or others raise a concern, the repository is made private while it is addressed.
