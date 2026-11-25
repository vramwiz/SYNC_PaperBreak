# ライセンスと共通基盤の由来

SYNC_PaperBreak（紙消失）Copyright (c) 2026 VRAMの魔術師。DelphiソースはGPL-3.0-onlyです。 [ライセンス全文](LICENSE)

## AviUtl ExEdit2 Plugin SDK

KenkunのSDKはMITライセンスです。WeatherFXから継承した `Source/Lib/AviUtl2FilterTypes.pas` に、SDKに由来する型・コールバックのABI定義を含みます。著作権は Copyright (c) 2025 Kenkun です。 [SDKのMITライセンス](ThirdParty/LICENSE.AviUtl2-SDK.txt)

## 参照したプロジェクト

- **SYNC_WeatherFX** のDelphiプロジェクト、Win64ビルドイベント、SDK型、登録処理、ライセンス、Setupを継承しています。WeatherFXの共通基盤はSYNC_AquaFXなどから継承されたものです。
- **SYNC_PianoRoll** の3D描画と深度調査を、正面投影と独自深度処理の設計に参照しました。
