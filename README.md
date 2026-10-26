[日本語](README.md) | [English](README.en.md)

# Audiomeeter

Apple Silicon / macOS 14以降向けの、ルーティング自由度の高いステレオ仮想オーディオミキサーです。マイク・オーディオインターフェース・PC音声・通話アプリの音を、スピーカー／ヘッドホン／配信・通話アプリへ自由に振り分け、音量・EQ・ダイナミクス・VST3エフェクトで整えられます。

> **本家との関係について**
> Audiomeeterは、Windows向けの仮想ミキサー [Voicemeeter](https://vb-audio.com/Voicemeeter/)（VB-Audio Software）の操作感を参考に、macOS向けに独自に実装したソフトウェアです。VB-Audioとは無関係で、公式製品・公認製品ではなく、設定ファイル・ドライバー・音質の互換性もありません。Voicemeeterのコード・画像・ロゴは使用していません。
> 名称・外観・その他の点で権利者や関係者から問題の指摘があった場合は、速やかにこのリポジトリを非公開にし、修正または公開停止で対応します。ご連絡は [Issues](https://github.com/sawada256/Audiomeeter/issues) へお願いします。

[導入・削除](docs/INSTALL.ja.md) · [使い方](docs/USAGE.ja.md) · [EQ・PAD](docs/PADS_SPECTRUM.ja.md) · [出力バス](docs/OUTPUT_BUS.ja.md) · [本家との違い](docs/COMPARISON.ja.md)

## ダウンロード

[Releases](https://github.com/sawada256/Audiomeeter/releases) から次の2つのインストーラーを入手します。

| ファイル | 内容 |
|---|---|
| `Audiomeeter-App-*.pkg` | 本体（`/Applications/Audiomeeter.app`）とVST3ホスト |
| `Audiomeeter-Drivers-*.pkg` | 専用仮想デバイス **Audiomeeter VAIO / AUX / B1 / B2**（Core Audio HALドライバー） |

1. Audiomeeterと音声アプリ（通話・DAW等）を終了します。
2. `Audiomeeter-App-*.pkg` を開いて導入します。
3. VAIO/AUX/B1/B2の専用デバイスを使う場合は `Audiomeeter-Drivers-*.pkg` も導入します（Mac全体の音声が数秒止まります）。
4. Audiomeeterを開き、マイクの使用を許可します。

現在の配布物は**署名・Appleの公証を行っていない試験版**です。macOSに開けないと表示された場合は、入手元を確認したうえで「システム設定 → プライバシーとセキュリティ」の「このまま開く」から許可できます。詳しくは[導入・削除](docs/INSTALL.ja.md)を参照してください。

## 画面構成

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│ AUDIOMEETER   Mac出力: [▾] [→VAIO]   ENGINE LIVE  48000 Hz  256 samples     Menu ▾ │
├───────────────────────────────────────────────────────────────────────────────────┤
│ 録音・再生デッキ  REC / PLAY / PAUSE / STOP / LOOP   SRC / FMT   PLAY TO [A1..B2]    │
├──────────┬──────────┬──────────┬──────────┬──────────┬────────────────────────────┤
│ HARDWARE │ HARDWARE │ HARDWARE │   VAIO   │   AUX    │ MASTER SECTION             │
│ INPUT 1  │ INPUT 2  │ INPUT 3  │ (PC音声)  │  (通話等) │  A1  A2  A3   B1  B2       │
│ PAD      │ PAD      │ PAD      │ EQ 3band │ EQ 3band │  機器名 / Mac音量バー        │
│ COMP/GATE│ COMP/GATE│ COMP/GATE│ KARAOKE  │ KARAOKE  │  MODE / Mute / INSERT      │
│ INSERTS  │ INSERTS  │ INSERTS  │ APPS     │ APPS     │  EQ(6band) / LIMIT         │
│ [A1..A3] │ [A1..A3] │ [A1..A3] │ INSERTS  │ INSERTS  │                            │
│ [B1][B2] │ [B1][B2] │ [B1][B2] │ PAN      │ PAN      │                            │
│ Mute/Solo│ Mute/Solo│ Mute/Solo│ Mute/Solo│ Mute/Solo│                            │
│ Fader/VU │ Fader/VU │ Fader/VU │ Fader/VU │ Fader/VU │  Fader / VU                │
└──────────┴──────────┴──────────┴──────────┴──────────┴────────────────────────────┘
```

ハードウェア入力は3〜5本、物理出力はA1–A3〜A1–A5に切り替えられます（オーディオ設定 → エンジン）。

## 主な機能

### ミキサーとルーティング
- **入力**: 物理入力3〜5本（マイク・オーディオインターフェース等）と、仮想入力2本（**VAIO** = Macのシステム音声、**AUX** = 通話アプリ等）。
- **出力**: 物理出力A1〜A5（スピーカー・ヘッドホン等）と、仮想出力B1/B2（配信・通話・録音アプリへ送るミックス）。**A1がマスタークロック**です。
- 各入力の `A1〜A5` `B1` `B2` ボタンで、任意の入力を任意の出力へ送れます。全体を一覧で切り替える**ルーティングマトリクス**ウィンドウもあります。
- 入力ごとに左右チャンネルを個別指定（同じチャンネルを選ぶとモノラル）。出力も同様。
- 独立したクロックの機器間は、適応型のクロック補正とサンプルレート変換で同期します。A1と同じ機器の入力・別チャンネル出力は、補正なしでA1と同じ処理内で直接読み書きします。
- デバイスの抜き差し・音声停止を検知して自動で再接続します。

### 入力ストリップ
- **物理入力**: PAD（COLOR PAN〔明暗＋左右〕／PAN／MODULATION／PITCH／FORMANT〔試験的〕）、COMP、GATE。
- **仮想入力**: 3バンドEQ（BASS/MED/TREBLE、3つのプリセット）、KARAOKE（中央の声を抑える）、PAN、アプリ別音量（APPS）。
- 全入力: ゲイン（−60〜+12 dB、ダブルクリックで0 dB）、Mute/Solo、PRE/POSTのVST3インサート、ピーク・RMSメーター。

### 出力バス
- モード（Normal / Mix Down / Mono）、Mute、ゲイン、追加ディレイ（機器ごとの遅延調整）。
- **6バンド パラメトリックEQ**（プリセット3つ、スペクトラムアナライザー重ね表示）。
- **リミッター**（Threshold / Ceiling、先読み0〜20 ms）。
- 信号順序（EQをINSERTの前・後、LIMITの前・後に置く）を選択。
- バス見出しの下に、割り当てた機器の**Macの出力音量バー**とミュート（Macの音量は最後に掛かるため、ここで確認・調整できます）。

### VST3エフェクト
- ARM64のVST3エフェクトを、入力・出力バスのPRE/POSTへ挿入。プラグインは**1つずつ別プロセス**で動き、落ちたり処理が間に合わなかったりしてもミキサーは止まりません（遅延を保った原音に切り替え、既定で自動再起動）。
- 挿入・削除・並べ替え・サイドチェイン変更は音声を止めずに反映。
- **遅延補正（PDC）**: 同じバスに混ぜる経路、出力バス同士、サイドチェインと本線の時刻を揃えます（個別にON/OFF）。
- **サイドチェイン**: 任意の入力・出力バスを指定（循環接続は1ブロック前の信号を使用）。
- **バイパス2種**: 簡易（遅延を維持、グレー表示）／完全（経路から外す、黒表示）。⌥クリックでもう一方。
- プラグインへの**MIDI入力**、プラグインのパラメーターをMIDIコントローラーで操作。

### 専用仮想デバイス（ドライバーpkg）
- **Audiomeeter VAIO / AUX**: アプリの再生先。VAIO/AUX入力に入ります。
- **Audiomeeter B1 / B2**: B1/B2バスの音を録音・配信・通話アプリへ渡す入力デバイス。
- DAW向けの全二重: DAWでAudiomeeter VAIOを選ぶと、再生はVAIOへ、録音はB1から（AUXはB2と対）。
- **アプリ別音量**: VAIO/AUXに出力しているアプリごとに音量を調整・記憶。

### 操作・自動化
- **Mac出力の切り替え**: 上部メニューでアプリの出力先（コントロールセンターと同じ設定）を選択。「→VAIO」でワンタップ切り替え、もう一度押すと元に戻ります。
- **MIDIコントローラー**: MIDI Learn（フェーダーの右クリックからも可）、CC・ノート・ピッチベンド（14bitフェーダー）、相対エンコーダー2方式、ピックアップ（値の飛び防止）、ボタンのトグル／追従。
- **マクロボタン**: スクリプトで複数の操作をまとめて実行（例: `Strip[0].A1 = 1; Bus[1].Gain -= 3; Scene = "配信"`）。押す／トグル／押している間、ラジオボタン式のグループ、キー・MIDI割り当て。
- **シーン**: ルーティング・音量・Mute/Solo・EQ・ダイナミクス・INSERT状態をまとめて保存・呼び出し（呼び出す範囲を選択可能、JSONで書き出し／読み込み）。
- **ホットキー**・Macの**音量キー**でフェーダー操作、常駐**ミニミキサー**（フェーダー・メーター・アプリ別音量）。
- **診断**ウィンドウ: 処理負荷、締切超過、各経路の方式・バッファ状態・クロック補正量・遅延、プラグインごとの処理時間・再起動回数、録音の欠落。

### 録音・再生
- 任意のバス・入力を WAV（16/24/32bit float）または AAC（128〜320 kbps）で録音。
- 音声ファイルを任意のバスへ再生（ループ・シーク、ストリーミング再生）。

### その他
- 日本語（既定）／英語の切り替え。設定は自動保存。ログイン時の自動起動。

## 使い方の例：配信・通話でマイクとPC音声を混ぜる

1. **A1** にヘッドホンやスピーカー（またはオーディオインターフェース）を選びます。
2. **HARDWARE INPUT 1** にマイクを選び、`B1` をON（相手に声を送る）。自分の声を聞きたい場合は `A1` もON。
3. **VAIO** 入力に **Audiomeeter VAIO** を選び、`A1`（自分で聞く）と `B1`（配信に流す）をON。
4. 上部の「Mac出力」で **Audiomeeter VAIO** を選ぶ（または「→VAIO」）。ブラウザやゲームの音がVAIOに入ります。
5. 通話アプリの出力を **Audiomeeter AUX** にし、AUX入力は `A1` のみON（相手の声を配信・通話へ戻さないため `B1` はOFF）。
6. 通話アプリ・OBSのマイク（入力）に **Audiomeeter B1** を選びます。

DAWとの組み合わせは[使い方](docs/USAGE.ja.md)を参照してください。

## 動作環境と制限

- Apple Silicon Mac、macOS 14以降。処理はステレオ（32bit float）。
- 対応プラグインはARM64のVST3エフェクトのみ（VST2・AU・Intel専用・インストゥルメントは非対応）。
- 試験版のため、署名・公証がなく、すべての機器・macOSの組み合わせでは確認できていません。音量を下げてから使い始めてください。
- VST3プラグインは別プロセスで動きますが、プラグイン自体の安全性を保証するものではありません。信頼できるプラグインだけを使ってください。
- 本家Voicemeeterの全機能（ネットワーク送受信、サラウンド等）や設定ファイルとの互換はありません（[本家との違い](docs/COMPARISON.ja.md)）。

## 困ったときは

- **音が出ない**: 入力・出力のMute、A1の出力先、バス見出しの下のMac音量（0%やミュートだと聞こえません）、上部の「Mac出力」がAudiomeeter VAIOになっているかを確認します。Menu → 「診断…」で各経路の状態も確認できます。
- **音が途切れる**: オーディオ設定でバッファサイズを大きくします。
- **専用デバイスが一覧に出ない**: ドライバーpkgを導入後、Macを再起動します。
- 不具合の報告・要望は [Issues](https://github.com/sawada256/Audiomeeter/issues) へどうぞ。

## ソースからのビルド

pkgを使わずに自分でビルドすることもできます（Xcode Command Line Tools、CMake 3.22以降、Python 3が必要）。

```sh
git clone https://github.com/sawada256/Audiomeeter.git
cd Audiomeeter
./install_app.sh        # 本体をビルドして /Applications へ導入
./install_drivers.sh    # 専用デバイスをビルドして導入（管理者認証）
```

## ライセンス

アプリ・VST3ホスト・配布ツールは **AGPL-3.0-only**、専用HALドライバー（[BlackHole](https://github.com/ExistentialAudio/BlackHole)の改変版）は **GPL-3.0-only** です。JUCE・VST3 SDK等の依存物は各ライセンスに従います。[LICENSE](LICENSE.md)・[第三者通知](THIRD_PARTY_NOTICES.ja.md)を参照してください。各Releaseには、そのバイナリに対応するソース（`Audiomeeter-Source-*.tar.gz`）を添付しています。

Voicemeeter は VB-Audio Software の商標です。その他の製品名は各社の商標です。
