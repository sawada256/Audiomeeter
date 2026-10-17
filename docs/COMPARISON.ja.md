[日本語](COMPARISON.ja.md) | [English](COMPARISON.en.md) · [Home](../README.md)

# Windows版Voicemeeterとの違い

Audiomeeterは独立したmacOS実装です。VB-Audioの公式製品ではなく、設定ファイル・ドライバー・DSPの完全互換を目的としません。

| 項目 | Audiomeeter | Windows版との関係 |
|---|---|---|
| ミキサー規模 | 物理3〜5＋仮想2入力、A1–A3〜A1–A5/B1/B2 | Banana〜Potatoの物理規模。仮想はドライバーの都合で2系統 |
| 音声基盤 | Core Audio HAL、ステレオ | WindowsのWDM/MME/KS/ASIO設定は適用されない |
| DAW入出力 | VAIO再生＋B1録音、AUX再生＋B2録音の全二重 | Windowsの仮想ASIOとは異なるCore Audio実装 |
| プラグイン | ARM64 VST3を直接PRE/POSTへ挿入 | 本家のPATCH INSERTは外部ASIOアプリとの往復を有効化する機能 |
| PATCH COMPOSITE | 同等の8ch組み立て機能なし | 本家は入力を組み合わせた多チャンネルComposite信号を作れる |
| PAD | PAN、音色、Modulation、Pitch、試験Formant | 本家と同じアルゴリズム・音質ではない |
| アプリ別trim | 専用HALのVAIO/AUXクライアント | Windows全体のアプリミキサー互換ではない |
| マクロ | マクロボタン（Voicemeeter風スクリプト、トグル・グループ・キー・MIDI）、シーン保存 | 本家MacroButtonsの全構文互換ではない |
| 追加UI | EQスペアナ、ミニミキサー、個別VST3プレビュー、ルーティングマトリクス、診断 | Audiomeeter独自機能 |
| 未提供 | VBAN、MIDIフィードバック、サラウンド、VST2/AU、Intel専用VST3 | 本家の全機能の代替ではない |

Mix Downの名称も本家の多チャンネル処理と同一仕様ではありません。[現在の数式](OUTPUT_BUS.ja.md)を参照してください。内蔵EQ・リミッターの音も独自実装です。Cubase専用内蔵エフェクトは、一般に独立VST3として提供されないため読み込み対象ではありません。

本家の仕様の参照：[公式Bananaマニュアル](https://vb-audio.com/Voicemeeter/VoicemeeterBanana_UserManual.pdf)、[公式Insert Driverガイド](https://voicemeeter.com/user-guide-connect-audio-apps-to-the-voicemeeter-insert-driver/)。本表は機能分類の比較であり互換性の保証ではありません。
