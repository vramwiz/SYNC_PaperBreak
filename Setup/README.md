# SYNC_PaperBreak のZIP配布

`make_release_zip.bat`を実行すると、配布用の`SYNC_PaperBreak.auf2`を`SYNC_PaperBreak.zip`へ梱包し、`SYNC_PaperBreak.catalog.json`の末尾バージョンへ実物のXXH3-128を設定します。

## 作成前の準備

- 配布用の本体を用意します。標準の参照先は`C:\ProgramData\aviutl2\Plugin\SYNC_PaperBreak`です。
- 初回の正式バージョンは**v1.0.0**です。本体の表示バージョンとJSONを合わせ、JSONの`release_date`を実際の公開日へ設定します。
- ハッシュ計算には[xxHash公式v0.8.4のWindows版](https://github.com/Cyan4973/xxHash/releases/download/v0.8.4/xxhsum_win64_v0_8_4.zip)の`xxhsum.exe`を使用します。`Win64\Dependencies\xxHash-0.8.4\xxhsum.exe`へ配置するか、PATHへ登録します。

```bat
Setup\make_release_zip.bat
```

参照先を明示する場合:

```bat
Setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_PaperBreak" -XxhsumPath "D:\Tools\xxhsum.exe"
```

## ZIPの内容

```text
SYNC_PaperBreak/
  SYNC_PaperBreak.auf2
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  ThirdParty/
    LICENSE.AviUtl2-SDK.txt
```

同梱READMEはプロジェクトルートの`README.md`から生成します。画像・GIFのリンクはGitHubのリリースタグにある画像を参照します。本体と同じ5ファイルをJSONのアンインストール対象へ登録します。

作成後はZIPの内容・本体のバージョン・JSONの公開日を確認し、GitHubリリースのタグを`v1.0.0`に合わせてZIPとJSONを公開します。
