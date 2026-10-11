# 配布資材の作成（2026-10-12）

## ローカル検証用

変更をコミットし、以下を実行します。生成物はGitへ入れません。生成後は `python3 Tools/verify_installers.py` でpkgを展開し、実ペイロード・署名・名前・UID・対応ソースを静的検証できます。インストールは行いません。

```sh
./build_installers.sh
```

`dist/`に以下を作成します。

- `Audiomeeter-App-1.0.0-12-arm64-LOCAL-UNSIGNED.pkg`：本体、ホスト、ワーカー、許諾表示。
- `Audiomeeter-Drivers-1.0.0-12-arm64-LOCAL-UNSIGNED.pkg`：HAL4個、GPL全文、改変表示。
- `Audiomeeter-Source-1.0.0-12.tar.gz`：対応するGit管理ソースとJUCE 8.0.12固定ソース。履歴、署名鍵、ユーザー設定、録音、生成アプリは除外。
- `release-manifest-*.json`：バージョン、ソースコミット、各成果物のSHA-256。

本体・HALともApple Silicon、macOS 14以降です。本体だけ導入することもできます。ドライバを使うには別途ドライバ用pkgを導入します。パッケージは別ボリューム・ユーザー別HALへの導入には対応しません。

インストール時に既存Audiomeeterファイルを管理者専用バックアップへ保存しますが、電源断等を含む完全な自動ロールバックは提供しません。Core Audio再起動で全体の音声が止まります。既存Voicemeeter／BlackHole／他社ドライバや録音は削除しません。旧デバイスから新デバイスへの設定変更は利用者が行います。HALのbundle IDはアプリと衝突しない`local.audiomeeter.driver.*`に分離し、デバイスUIDは維持します。

アーカイブ内の `.build/dependencies/JUCE` はビルドキャッシュではなく、対応ソースとして同梱する固定依存ソースです。展開先で `./build_app.sh` を実行すれば、追加ダウンロードなしでそのJUCEソースを使用します。Xcode Command Line Tools、CMake、Python 3、macOS SDKは別途必要です。

## 一般配布用の署名

Developer ID証明書を別途取得し、**公開用の認証情報はソースへ保存しません**。

```sh
export VM_CODESIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export VM_INSTALLER_SIGNING_IDENTITY='Developer ID Installer: YOUR NAME (TEAMID)'
./build_installers.sh --signed
```

本体・dylib・ワーカーを内側から署名し、HALも署名します。ワーカーだけは第三者VST3をロードするためLibrary Validationを解除します。これはセキュリティサンドボックスではありません。配布用モードではad-hocやApple Development証明書へ黙ってフォールバックしません。

署名済みでも公証済みとは限りません。公開前にはAppleのnotarytoolへ各pkgを提出し、成功ログを確認し、staplerでチケットを添付して、最終成果物のハッシュを取り直します。このツールは認証情報を要求せず、提出・アップロードを自動実行しません。

参考：[Appleの公証手順](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。Gatekeeperを無効化する導入手順は採用しません。

## ソース・通知

アプリ／JUCEホストはAGPLv3、独立した改変HALはGPLv3として配布します。pkgと対応するソースを一緒に提供し、受領者のライセンス上の権利を制限しないでください。ライセンスは免責を含み、商用販売自体を禁じません。プラグイン製品・鍵・ユーザー設定は含めません。

既存アイコンは所有者によるAI生成オリジナルとの説明に基づきそのまま使用します。Assets/AppIcon.mdへ来歴を記録しています。

公開する場合はソースアーカイブを展開し、JUCEの同梱ソースを保存したまま配布するか、Git用にはJUCEを固定コミットから取得する通常の構成にします。既存開発履歴を外部へpushする作業はこのツールでは行いません。GitHub上の公開リポジトリをまだ作っていないため、対応ソースの公開URLは未設定です。実際に配布する時にはその版のソースアーカイブを継続提供してください。

## 公開前に残る確認

- このMacにはDeveloper ID Application／Installerの有効な組合せがなく、一般配布署名・公証は未実施。
- 管理者権限でのpkg導入、クリーンMac、アップデート・失敗復元、実HALの再起動／DAW全二重／アプリ別trimは隔離環境で最終検証が必要。
- BlackHole由来は特定し改変・GPL表示は維持したが、元の取得コミットの履歴は未復元。
- Audiomeeter名称・画面外観・商標、任意の専有プラグインとの結合物を配布する場合の条件は別途確認。
- 全macOS版・USB／Bluetooth機器・市販プラグインの組合せを網羅していない。一般公開済み品質や法的適法性の保証ではない。
