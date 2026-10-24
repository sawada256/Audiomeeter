[日本語](INSTALL.ja.md) | [English](INSTALL.en.md) · [Home](../README.md)

# インストール

## 必要環境とパッケージ

Apple Silicon、macOS 14以降。本体pkgとドライバpkgはビルドツール不要です。まずAudiomeeterと他の音声アプリを終了し、`Audiomeeter-App-*.pkg`、次に必要なら `Audiomeeter-Drivers-*.pkg` を開いて管理者認証します。ドライバ導入はCore Audioを再起動し、システム全体の音声を一時停止します。

現在の `LOCAL-UNSIGNED` はパッケージ署名・公証なしの試験資材です。ブロックされた場合、信頼できる取得元とハッシュを確認したうえで、システム設定 → プライバシーとセキュリティに表示される「このまま開く」を使用できます。OS版・組織の管理ポリシー等により許可できない場合があります。マルウェア検出や破損警告を無視せず、その場合は停止してください。Gatekeeper全体の無効化を前提にしません。[Apple公式手順](https://support.apple.com/ja-jp/102445)。クリーンMacでのpkg導入はまだ最終検証前です。

導入先は `/Applications/Audiomeeter.app` と `/Library/Audio/Plug-Ins/HAL/` のAudiomeeter系4バンドルです。既存Audiomeeterは `/Library/Application Support/Audiomeeter/InstallerBackups/` へバックアップします。BlackHole・他社・旧試作版のHALは残ります。失敗時はバックアップから手動復旧が必要な場合があります。

## パッケージが使えない場合：ソースから導入

実行スクリプトはリポジトリに含まれています。Command Line Tools、Git、CMake 3.22以降、Python 3、macOS SDKが必要です。CMake/Pythonは公式配布または利用中のパッケージ管理方法で準備します。

```sh
xcode-select --install
git clone https://github.com/sawada256/Audiomeeter.git
cd Audiomeeter
./install_app.sh
./install_drivers.sh
open /Applications/Audiomeeter.app
```

公開リポジトリは認証なしでcloneできます。GitHubの対応ソースtar.gzを展開して、そのディレクトリで後半3コマンドを実行することもできます。tar.gzには固定JUCEソースが含まれ、GitHubの自動生成Source codeアーカイブには含まれません。通常のcloneでは初回ビルド時にJUCEを取得します。

シェルはソースをビルドして導入するため、開発ツールなしで使えるポータブル版ではありません。本体はアプリ用バックアップを作り、ドライバは管理者認証を要求して4HALだけを置き換えます。ソース導入のバックアップは `.build/installation-backup/` にあります。アプリ更新時は同じ署名IDの利用を推奨します。ad-hoc署名やID変更時にはOS許可を取り直す場合があります。

## 初期設定・許可

本体を開きマイク許可を与えます。音量キー捕捉にはAudiomeeter自身へのアクセシビリティ許可、ログイン時起動にはOS側の許可が必要になる場合があります。A1に物理出力、VAIO/AUXにAudiomeeter VAIO/AUXを選びます。旧ドライバの設定は自動で新ドライバへ変わらないため、macOS・DAW側も選び直してください。[音出しとDAWの手順](USAGE.ja.md)。

設定は `~/Library/Application Support/Audiomeeter`、録音は `~/Music/AudiomeeterRecordings`。更新でこれらを削除しません。日本語が初期値で、オーディオ設定の「言語 / Language」から英語へ切り替えます。

## 削除・復旧

アプリを終了してゴミ箱へ移動します。HALの削除は管理者権限で、Audiomeeter.driver、AudiomeeterAUX.driver、AudiomeeterB1.driver、AudiomeeterB2.driverだけをHALフォルダ外へ退避し、macOSを再起動します。他社や旧Voicemeeterのファイルを削除しないでください。復旧は保存済みの同名アプリ／HALを元の位置へ戻し、所有権・許可を管理者で確認後再起動します。設定・録音は必要に応じて別途バックアップします。
