library SYNC_PaperBreak;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2への登録とWin64 DLLの公開関数。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  PaperBreak_Types in 'Source\Common\PaperBreak_Types.pas',
  PaperBreak_Mesh in 'Source\Common\PaperBreak_Mesh.pas',
  PaperBreak_Scissors in 'Source\Common\PaperBreak_Scissors.pas',
  PaperBreak_Sheets in 'Source\Common\PaperBreak_Sheets.pas',
  PaperBreak_Fragments in 'Source\Common\PaperBreak_Fragments.pas',
  PaperBreak_D3D in 'Source\Common\PaperBreak_D3D.pas',
  PaperBreak_Parameters in 'Source\Plugin\Filter\PaperBreak_Parameters.pas',
  SYNC_PaperBreak_FilterPlugin in 'Source\Plugin\Filter\SYNC_PaperBreak_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if Version < PAPERBREAK_REQUIRED_VERSION then Exit;
    GetPaperBreakFilterTable;
    Result := 1;
  except
    // 初期化失敗は戻り値で伝える。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  // 描画資源は各エフェクトのfunc_destroyで破棄する。
end;

function RequiredVersion: Cardinal; cdecl;
begin
  Result := PAPERBREAK_REQUIRED_VERSION;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetPaperBreakFilterTable;
  except
    // 登録テーブルを作成できなかった場合はnilを返す。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
