[日本語](OUTPUT_BUS.ja.md) | [English](OUTPUT_BUS.en.md) · [Home](../README.md)

# 出力バス・EQ・リミッター

既定の信号順は **PRE INSERT → FADER / MODE → POST INSERT → EQ → LIMIT**。EQ位置はINSERT群の前、INSERT群の後、LIMITの前、LIMITの後から選択できます。「INSERT群の後」と「LIMITの前」は固定された他段との関係上同じ位置です。EQ枠の表示順も設定へ追従します。実フェーダーは下部固定、FADER横線が信号上の位置を示します。

EQは左クリックでON/OFF、右クリックかプレビュークリックで編集します。プリセットの保存・呼出が可能です。INSERTはPRE/POSTをまとめた3行のスクロール表示。POSTがある場合は境目にFADER線が入ります。長い名前の全文はツールチップで確認できます。

LIMITは左クリックでON/OFF、右クリックでThreshold、Ceiling、Lookaheadを設定します。制限が掛かると赤く表示し短いピークも保持します。先読みはOFF／1／3／5／10／20 ms。OFFは従来のサンプル単位ソフトニー制限、ONは左右連動ピーク検出と50 msリリースを使います。追加遅延は `floor(sampleRate × ms / 1000)` サンプルで、遅延補正へ含まれます。True Peak／オーバーサンプリングではありません。LIMIT後のEQ増幅はCeilingを超え得ます。

Normalはステレオを維持。Monoは `(L + R) × 0.5`、Mix Downは `(L + R) × 0.7071` を左右両方へ出します。同相の信号ではMix DownのほうがMonoより約3 dB大きくなります。サラウンドからのダウンミックスではありません。

インサートメーターの0 dBFSはデジタルフルスケールの基準で、フェーダーの0 dB（増減なし）や+12 dBの可動範囲とは別です。浮動小数点内部処理では0 dBFSを超えることがありますが、物理出力等でのクリッピングに注意してください。
