# インストールと更新

## パッケージから導入

Apple Silicon / macOS 14以降用の本体用 `Audiomeeter-App-*.pkg` と、ドライバ用 `Audiomeeter-Drivers-*.pkg` をそれぞれ開きます。利用者側でXcodeやCMakeは不要です。Audiomeeterを終了し、ドライバ導入時はDAW等の音声アプリも終了してください。管理者認証が必要で、導入後Core Audioが再起動します。

現在生成する `LOCAL-UNSIGNED` は未公証のローカル検証用で、一般配布用ではありません。macOSのセキュリティ機能を無効化する手順は使用しません。一般配布はDeveloper ID署名・公証を完了したパッケージを使用してください。

配置は本体 `/Applications/Audiomeeter.app`、ドライバ `/Library/Audio/Plug-Ins/HAL/`。以前のAudiomeeterファイルは `/Library/Application Support/Audiomeeter/InstallerBackups/` に管理者専用で保存します。導入失敗時は自動復元を保証せず、このバックアップから復元してください。VoicemeeterやBlackHoleの既存ドライバと個人設定は残ります。

新しいデバイス名は **Audiomeeter VAIO／Audiomeeter AUX／Audiomeeter B1／Audiomeeter B2** です。旧ドライバと共存するため、既存設定からは入力VAIO/AUX・出力B1/B2を手動で新デバイスへ選び直し、macOSやDAW側の選択も変更してください。UIDは既存Audiomeeter版と同じで、表示名変更による再割当てを避けます。

以下はソースから作る開発者向けの説明です。

## 必要環境

- Apple Silicon、macOS 14以降。Intel版・Windows版はありません。
- Xcode Command Line Tools (`xcode-select --install`)、Git、CMake 3.22以降、Python 3。
- 初回ビルドはJUCEを取得するためネット接続が必要です。エフェクト本体は同梱しません。

## ビルド・アプリ導入

```sh
./build_app.sh
open Audiomeeter.app
```

動作を確認したらアプリを終了し、`./install_app.sh`で`/Applications/Audiomeeter.app`へ導入します。旧アプリは`.build/installation-backup`へ保存します。現在インストールされているVoicemeeterアプリと設定は置換・移行しません。

`VM_CODESIGN_IDENTITY`で署名IDを指定できます。未指定時は利用可能なApple Development証明書、なければad-hoc署名を使用します。同じbundle IDと証明書で更新すると許可を引き継ぎやすくなりますが、ad-hoc署名や証明書変更では再許可が必要になる場合があります。一般配布には別途Developer ID署名・公証と適切なエンタイトルメントの検証が必要です。

## 仮想ドライバー（管理者権限が必要）

まず音声を使うアプリとAudiomeeterを終了してください。

```sh
./install_drivers.sh
```

専用HALドライバー4個をビルドし、`/Library/Audio/Plug-Ins/HAL`に導入します。管理者認証を求めます。Core Audioを再起動するためMac全体の音声が一時停止します。既存Audiomeeterドライバーをバックアップします。VoicemeeterやBlackHoleのドライバーは削除しません。

- Audiomeeter VAIO：VAIOへの再生、B1からの録音を同一デバイスで提供。
- Audiomeeter AUX：AUXへの再生、B2からの録音を同一デバイスで提供。
- Audiomeeter B1 / B2：仮想マイク側の独立端点。

初回起動でマイク許可を与えます。音量キー置換を使う場合だけ、システム設定 → プライバシーとセキュリティ → アクセシビリティでこのアプリを許可してください。自動起動はオーディオ設定で有効化し、必要ならログイン項目を許可します。

## 基本設定

1. A1にヘッドフォン／スピーカーを選ぶ。最初は音量を低くする。
2. VAIO入力にAudiomeeter VAIO、AUX入力にAudiomeeter AUXを選ぶ。
3. macOSの出力をAudiomeeter VAIOにし、VAIO → A1をON。
4. 配信・通話には必要な入力をB1へ送り、相手アプリの入力をAudiomeeter B1にする。
5. DAWでAudiomeeter VAIOを選ぶと再生VAIO／録音B1。VAIO → B1の戻しで意図しないループを作らない。
6. 複数出力機器はチャンネル割り当てで左右を指定。現在はバス単位で保存され、デバイス別のプリセットではありません。

録音は`~/Music/AudiomeeterRecordings`、設定とプラグインカタログは`~/Library/Application Support/Audiomeeter`に保存します。日本語／英語はオーディオ設定の言語選択で切り替えます。

## 削除と復元

アプリを終了し、`/Applications/Audiomeeter.app`をゴミ箱へ移動します。ドライバーは上記HALフォルダ内の**Audiomeeter / AudiomeeterAUX / AudiomeeterB1 / AudiomeeterB2 `.driver`のみ**を管理者権限で別フォルダへ退避し、Macを再起動してください。他製品のHALや`coreaudiod`自体を削除しないでください。設定・録音は残ります。以前のアプリ／HALへ戻す場合は`.build/installation-backup`の該当バックアップを使います。

## 検証

`./Tests/run_audio_tests.sh`はオフライン回帰テストを実行します。実機HALテストは既定OFFで、専用デバイスの独占利用が必要です。`VM_TEST_INSTALLED_HAL=1`と`VM_TEST_DUPLEX_HAL=1`は音声アプリを終了した検証環境でのみ指定してください。最新の条件はテストスクリプトを確認してください。

## 既存の個人用環境からの移行

Audiomeeterは旧Voicemeeter仮想デバイスのUIDにも対応します。既存HALをそのまま使う場合、OS上のデバイス名はVoicemeeterのままです。旧アプリを終了してからAudiomeeterを使用し、両方のエンジンを同時実行しないでください。設定は別領域で保存します。日本語モードは旧版の英語ラベルと日本語説明を維持し、英語モードは日本語説明も英訳します。
