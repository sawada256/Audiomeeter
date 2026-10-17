[日本語](README.md) | [English](README.en.md)

# Audiomeeter

Apple Silicon / macOS 14以降向けステレオミキサー。非公開開発版で、未公証のテスト用インストーラーを用意しています。VB-Audioとは独立した実装で、公式製品ではありません。

[導入](docs/INSTALL.ja.md) · [使い方](docs/USAGE.ja.md) · [本家との違い](docs/COMPARISON.ja.md) · [EQ・PAD](docs/PADS_SPECTRUM.ja.md) · [出力バス](docs/OUTPUT_BUS.ja.md) · [Release](docs/DISTRIBUTION.ja.md) · [ライセンス](docs/LICENSING.ja.md) · [既知の課題](docs/AUDIT.ja.md) · [設計レビュー](docs/REVIEW_2026-10.ja.md) · [開発](docs/DEVELOPMENT.ja.md)

## 機能

- 物理3〜5＋VAIO/AUX入力、A1–A3〜A5/B1/B2、左右チャンネル指定、PAN/EQ/ダイナミクス。
- ARM64 VST3のPRE/POSTインサート、別プロセス処理、サイドチェインと遅延補正。
- 専用HALによるVAIO/B1・AUX/B2の全二重とアプリ別trim。
- EQプリセット・重ね表示スペアナ、切替式入力PAD（試験Formantを含む）。
- MIDIコントローラー割り当て（MIDI Learn、相対エンコーダー、ピックアップ、VST3パラメーター）。
- マクロボタン・シーン保存、ルーティングマトリクス、診断画面。
- 録音・再生、ホットキー、常駐ミニミキサー、自動復帰・ログイン時起動。
- 日本語（既定）／英語切替。OS・第三者エディターの言語は提供元に従います。

## 導入とライセンス

本体・ドライバの2つのpkgを使います。未公証版はmacOSの許可操作が必要になる場合があります。ビルド用シェルによる代替導入手順もあります。[導入手順](docs/INSTALL.ja.md)を確認してください。VST2/AU、Intel専用プラグイン、サラウンドには対応していません。

アプリ／ホスト／配布ツールはAGPL-3.0-only、独立HALはGPL-3.0-only。依存素材には各条件が適用されます。[LICENSE](LICENSE.md)・[第三者通知](THIRD_PARTY_NOTICES.ja.md)を参照してください。Releaseへはバイナリだけでなく対応ソースも添付します。署名・公証・実機検証など[一般公開前の課題](docs/AUDIT.ja.md)が残っています。
