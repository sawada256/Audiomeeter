[日本語](DEVELOPMENT.ja.md) | [English](DEVELOPMENT.en.md) · [Home](../README.md)

# 開発・Git管理

正本はこのAudiomeeterリポジトリです。GitHubは `sawada256/Audiomeeter` の非公開リポジトリとして管理します。旧Voicemeeter-Macは別リポジトリのままです。

```sh
./build_app.sh
./Tests/run_audio_tests.sh
python3 Tools/check_repository.py
```

Command Line Tools、CMake 3.22以降、Python 3が必要です。JUCE 8.0.12は固定コミットから取得します。変更は適切な検証後にまとまり単位でコミットします。生成アプリ／HAL、録音、設定、ログ、署名鍵はコミットしません。コミット前に `git diff --check` と `git status` を確認します。

私有リポジトリへのpushと一般公開・Release公開は別の操作です。公開範囲変更やRelease公開は所有者の明示的な指示で行います。既存のv1.0.0タグは初期開発基準点で、最新版Releaseを示しません。配布版は確認済みコミットから新たなタグを作成し、そのコミットで資材を生成してください。
