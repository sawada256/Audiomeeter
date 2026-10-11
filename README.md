# Audiomeeter

[入力PAD・スペアナ](docs/PADS_SPECTRUM.ja.md) · [出力バスの操作・処理順](docs/OUTPUT_BUS.ja.md) · [English](docs/README.en.md) · [インストール](docs/INSTALL.ja.md) · [検証・既知の課題](docs/AUDIT.ja.md) · [ライセンス整理](docs/LICENSING.ja.md)

Apple Silicon / macOS 14以降向けのステレオ音声ミキサー。現在は公開準備中のローカル開発版です。VB-Audio製品とは独立した実装であり、同社の公式製品・互換製品ではありません。

## 機能

- 物理入力3系統、仮想入力VAIO/AUX、出力A1–A3/B1/B2のルーティング。
- フェーダー、ミュート、ソロ、ステレオPAN、EQとプリセット、ダイナミクス。
- 物理入力の切替式PAN／音色／モジュレーション／ピッチ／試験用FORMANT PAD、ON/OFF式EQスペアナ。
- デバイスが公開するチャンネル数に応じた左右の物理チャンネル選択。
- ARM64 VST3エフェクトのプロセス分離、入力／出力のPRE/POSTインサート、サイドチェイン、遅延補正。
- 専用HALドライバーによる仮想デバイス、VAIO/B1・AUX/B2の全二重接続、アプリ別トリム。
- レコーダー／プレーヤー、録音ソースメーター、Finderでの録音表示。
- 音量キー／カスタムホットキー、常駐ミニミキサー、1.5秒の操作時表示。
- 日本語（初期値）／英語。オーディオ設定の「言語 / Language」で切り替え。

プラグイン自身の設定画面、OSの許可ダイアログ、デバイス・アプリ名は各提供元の言語に従います。VST2、AU、Intel専用プラグイン、サラウンド、Windows版ASIO互換は対象外です。

## 開発

```sh
./build_app.sh
open Audiomeeter.app
./Tests/run_audio_tests.sh
```

Command Line Tools、CMake、Gitが必要です。JUCE 8.0.12を固定コミットから取得します。生成物・キャッシュ・ログ・ユーザー設定・録音はGit管理しません。テストは品質維持のため同梱します。

アプリ・ホスト・配布ツールはAGPL-3.0-only、独立HALドライバはGPL-3.0-onlyです。`LICENSE.md`と第三者通知を確認してください。リモートは未設定で、署名・公証・権利確認を完了した一般配布版ではありません。外部配布前に[公開前の課題](docs/AUDIT.ja.md)と[ライセンス整理](docs/LICENSING.ja.md)を確認してください。

## インストーラーを作成

変更をGitへ記録した状態で `./build_installers.sh` を実行すると、`dist/`へ本体用・ドライバ用の2つの `.pkg`、対応ソース一式、SHA-256マニフェストを作成します。既定は未公証・未署名のローカル検証用パッケージです。インストールやアップロードは自動では行いません。[配布手順](docs/DISTRIBUTION.ja.md)を参照してください。
