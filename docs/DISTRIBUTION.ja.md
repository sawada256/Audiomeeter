[日本語](DISTRIBUTION.ja.md) | [English](DISTRIBUTION.en.md) · [Home](../README.md)

# GitHub Releasesに添付するもの

公開リポジトリのGitHub Releasesに、以下を同じReleaseとして添付します。署名・公証のない試験版です。

| 資材 | 用途 |
|---|---|
| `Audiomeeter-App-1.1.0-13-arm64-LOCAL-UNSIGNED.pkg` | 本体・プラグインホスト・ライセンス |
| `Audiomeeter-Drivers-1.1.0-13-arm64-LOCAL-UNSIGNED.pkg` | VAIO/AUX/B1/B2の4HAL |
| `Audiomeeter-Source-1.1.0-13.tar.gz` | そのバイナリに対応するソース、改変HAL、固定JUCE、導入シェル・文書 |
| `release-manifest-1.1.0-13-arm64-LOCAL-UNSIGNED.json` | ソースコミットと各ファイルのSHA-256 |

GitHubの自動生成Source code(zip/tar.gz)だけで対応ソース資材を代用しないでください。対応ソースの取得場所・アクセスはバイナリの受領者にも提供します。リポジトリを非公開にした場合でも、すでにバイナリを受け取った人が対応ソースを入手できるよう、別途提供します。

## Release本文テンプレート

> Audiomeeter 1.1.0 build 13 — test build / 試験版
> Apple Silicon / macOS 14+ only. Not notarized; installer packages unsigned. / 未公証・パッケージ署名なし。
> Install App, then Drivers if virtual routing is needed. Quit audio apps first; driver installation restarts Core Audio. / 本体→必要ならドライバの順。事前に音声アプリを終了。
> See Installation / User guide / Known issues in both languages. Corresponding source and SHA-256 manifest are attached. / 日英導入・操作・既知の課題を参照。対応ソースとハッシュ同梱。
> No third-party effect binaries. AGPL-3.0-only app; GPL-3.0-only HAL. / 第三者プラグイン本体は非同梱。

公開時にはリンクをそのタグのドキュメントへ固定し、実際のコミット・検証環境・変更点を追記します。古いv1.0.0タグを最新版と誤認して使わず、確認済みHEADに新しいプレリリースタグを作成します。

## 作成と確認

```sh
./build_installers.sh
python3 Tools/verify_installers.py
```

コミット済みでクリーンな状態が必要です。生成物はdistのみでGitへ入れません。既存の配布用ビルドを再パッケージする場合は `./build_installers.sh --skip-build`。GitHubへのアップロードは自動では行いません。

## 一般配布の前

Developer ID Application／Installerの両証明書を用意し、環境変数 `VM_CODESIGN_IDENTITY`、`VM_INSTALLER_SIGNING_IDENTITY` に設定して `./build_installers.sh --signed` を実行します。鍵をコミットしません。署名後もAppleへの公証提出・成功確認・stapleが必要です。最終成果物のハッシュを再計算し、manifestの公証状態を実態へ合わせます。[Apple公証手順](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

クリーンMacでの導入・更新・失敗復旧・HAL入出力・macOS権限を検証してから一般配布します。現在の環境には適切なDeveloper ID証明書がなく、これらは完了していません。[既知の課題](AUDIT.ja.md)。
