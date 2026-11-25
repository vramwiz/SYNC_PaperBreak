# SYNC_PaperBreak 作業ノート

## プロジェクトと継承元

- Delphiプロジェクトは `SYNC_PaperBreak.dproj`。本体はWin64用の `SYNC_PaperBreak.auf2` 1本で、画像効果は「紙消失」、グループは「SYNC」。
- `D:\DelphiProg\MyApp\SYNC_WeatherFX` から `.dproj` の設定、共通SDK型、登録処理、リソース、ライセンスを継承した。新規プロジェクトの名前・GUID・参照ユニットを登録し、Win64 Debug／ReleaseのAUF2出力先を `C:\ProgramData\aviutl2\Plugin\SYNC_PaperBreak\` に設定した。
- `Setup` はWeatherFXのフォルダーを配布済みZIPも含めてそのままコピーした。中のスクリプト・カタログ・ZIPはWeatherFX用。
- `SYNC_PianoRoll` の3D深度調査では、カメラ制御のないホストの `DrawPoly` で不透明面が送信順に重なることが確認されている。紙消失は同じ頂点ベースの描画を、固定視点と専用の深度バッファで行う。
- SDK付属の `MediaObject.cpp` と `filter2.h` で、ホストの画像テクスチャを直接扱う方式、ABIの並び、乗算済みアルファを照合した。 [AviUtl ExEdit2 Plugin SDK](https://spring-fragrance.mints.ne.jp/aviutl/)

## ビルド

プロジェクトルートでDelphi 37.0の `rsvars.bat` を読み込み、Win64 Debug／ReleaseをMSBuildでビルドする。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PaperBreak.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_PaperBreak.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
```

- 初期版は出力先がプロジェクト内だったため、AviUtl2のプラグイン検索対象に入らなかった。Win64の出力先を修正したプロジェクト設定は、Delphiで開き直すと反映される。AviUtl2のプラグイン読み込みは起動時に行われる。
- ビルド後イベントは生成したDLLを同じフォルダーのAUF2にコピーしてDLLを削除する。Release構成ではRSMも削除する。DCUは各構成の `DCU` に出力する。
- ユニット追加時は `.dpr` の `in` と `.dproj` の `DCCReference` を両方更新する。
- 日本語を含むDelphi／PowerShellソースはUTF-8 BOMとCRLFを使用する。SDK ABIの変更は公式ヘッダと照合し、ホスト所有ポインターの寿命は当該コールバック内とし、Delphi例外をDLL境界内で捕捉する。

## ソース

| パス | 責務 |
| --- | --- |
| `SYNC_PaperBreak.dpr` | DLLの公開関数と最低対応バージョン |
| `Source/Plugin/Filter/` | SDK登録、パラメータ、インスタンスと入力画像 |
| `Source/Common/PaperBreak_Types.pas` | 座標、長方形外周との交点、乱数 |
| `Source/Common/PaperBreak_Mesh.pas` | 三角形、メッシュの法線、表裏と側面 |
| `Source/Common/PaperBreak_Sheets.pas`、`PaperBreak_Scissors.pas` | 裂け、折り、しわ、切断に使う道具 |
| `Source/Common/PaperBreak_Fragments.pas` | 不規則な紙片、燃焼・浸透の進行、水濡れによる変形と剥離 |
| `Source/Common/PaperBreak_D3D.pas`、`PaperBreak_Shader.inc` | 深度付きD3D11描画、GPU内画像コピー、紙や道具の材質 |
| `Source/Lib/` | WeatherFXから継承したSDK型と登録処理 |

開始フレームは画像に触れずに通過する。途中は経過秒数とシードから計算し、ホストのテクスチャから印刷面をサンプリングする。色と深度の描画先、頂点バッファ、紙片の輪郭を再利用する。コマンドリストの実行時はホストのD3D状態を復元する。終端からは同じサイズのまま透明にする。

紙飛行機は任意仕様のため初版の選択肢から省いた。

## AviUtl2を起動しない検査

```powershell
.\Tests\run_tests.ps1 -Config Debug
.\Tests\run_tests.ps1 -Config Release
.\Tests\run_tests.ps1 -Config Release -Warp
```

共通の出力先には最後にビルドした構成が配置される。各Rebuildの直後に、対応する `-Config` で検査する。別のAUF2を検査する場合は `-PluginPath` に指定する。

検査EXEは配置先の本番AUF2を読み込み、AviUtl2相当のD3D11テクスチャ（RGBA16F、乗算済みアルファ）をモックのコールバックで渡す。9演出の開始・途中・終了、逆方向のシーク、同じフレームの再描画、ホストの描画状態、長方形の開始位置、消失時間の上下限、紙の裏面と厚み0を確認する。描画の一覧画像は `Win64\Verification` に保存する。

検査画像の行はREADMEのスタイル順。列は消失時間の13%、30%、46%、60%、74%、88%。Debug／Releaseのハードウェア描画と、ReleaseのWARP描画を確認した。

## 折りたたみ・燃焼の修正

- 折りたたみでは、2回目と3回目の折り途中に下の印刷面が見える状態を再現した。紙束より手前に各折り軸を置き、表裏の位置を個別に変形して各層が貫通しないようにした。折り目の円弧に沿って頂点を増やし、折り途中も元のUVを保持する。
- 燃焼では紙面を元の位置に固定した。色の変化と不規則な焼失境界をシェーダーで進める。
- 実AUF2の確認では、紙厚0・10・100で折り途中の印刷面が隠れること、燃焼していない領域の印刷と座標が保たれることを検査する。検査画像のうち `-fold.png` は上から紙厚0・10・100。
