unit SYNC_PaperBreak_FilterPlugin;

// 「紙消失 / SYNC」の登録と、オブジェクト画像・時刻のコールバック境界。

interface

uses AviUtl2FilterTypes;

const
  PAPERBREAK_REQUIRED_VERSION = 2011600;

function GetPaperBreakFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils, System.Math, System.SyncObjs, Winapi.Windows, Winapi.D3D11,
  PluginFilterTable, PaperBreak_Types, PaperBreak_Parameters, PaperBreak_Mesh,
  PaperBreak_Sheets, PaperBreak_Fragments, PaperBreak_D3D;

type
  TPaperSession = class
  private
    FLock: TCriticalSection;
    FD3D: TPaperD3D;
    FMesh: TPaperMesh;
    FFragments: TPaperFragments;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(Video: PFILTER_PROC_VIDEO; const Settings: TPaperSettings;
      Progress: Double);
  end;

var
  TableInitialized: Boolean;

constructor TPaperSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FD3D := TPaperD3D.Create;
  FMesh := TPaperMesh.Create;
  FFragments := TPaperFragments.Create;
end;

destructor TPaperSession.Destroy;
begin
  FFragments.Free;
  FMesh.Free;
  FD3D.Free;
  FLock.Free;
  inherited;
end;

procedure TPaperSession.Render(Video: PFILTER_PROC_VIDEO;
  const Settings: TPaperSettings; Progress: Double);
var
  Image: ID3D11Texture2D;
  Frame: TPaperFrame;
  Width,Height: Integer;
  Zeroes: TArray<TPIXEL_RGBA>;
begin
  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if (Width<=0) or (Height<=0) or (Width>16384) or (Height>16384) then Exit;

  // SDKの生ポインターはこの呼出中だけ参照する。COM参照をローカルで対にする。
  if Assigned(Video^.GetImageTexture2D) then
  begin
    Pointer(Image) := Video^.GetImageTexture2D();
    if Image<>nil then Image._AddRef;
  end;
  FLock.Acquire;
  try
    if Progress>=1 then
    begin
      if Image<>nil then
      try
        FD3D.Clear(Image,Width,Height);
        Exit;
      except
        // GPU側をクリアできない場合も、SDKの画像設定経路で消失を維持する。
      end;
      if Assigned(Video^.SetImageData) then
      begin
        SetLength(Zeroes,Width*Height);
        Video^.SetImageData(@Zeroes[0],Width,Height);
      end;
      Exit;
    end;
    if Image=nil then Exit;
    Frame := MakeFrame(Settings,Progress,Width,Height);
    FMesh.Reset;
    case Settings.Style of
      psTear, psRepeatedTear, psScissors: DrawTornSheet(FMesh,Frame);
      psCrumple: DrawCrumpledSheet(FMesh,Frame);
      psFold: DrawFoldedSheet(FMesh,Frame);
      psShred, psBurn, psSoak, psWeather: FFragments.Draw(FMesh,Frame);
    end;
    FD3D.Render(Image,Width,Height,Frame,FMesh);
  finally
    FLock.Release;
  end;
end;

function ProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Settings: TPaperSettings;
  Elapsed: Double;
begin
  Result := 1;
  if (Video=nil) or (Video^.Object_=nil) or (Video^.UserData=nil) then Exit;
  try
    Elapsed := Video^.Object_^.Time;
    if IsNan(Elapsed) or (Elapsed<=0) then Exit;
    Settings := ReadPaperSettings;
    TPaperSession(Video^.UserData).Render(Video,Settings,Elapsed/Settings.Duration);
  except
    on E: Exception do
      OutputDebugString(PWideChar('SYNC_PaperBreak render: '+E.Message));
  end;
end;

function CreateSession(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TPaperSession.Create;
  except
    // ホストのコールバックから例外を出さない。
  end;
end;

procedure DestroySession(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TPaperSession(UserData).Free;
  except
    // ホストのコールバックから例外を出さない。
  end;
end;

function GetPaperBreakFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_USERDATA,
      '紙消失','SYNC','紙消失 / SYNC_PaperBreak v1.0.0',ProcVideo,nil);
    RegisterPaperParameters;
    GetPluginTable^.Func_Create := CreateSession;
    GetPluginTable^.Func_Destroy := DestroySession;
    TableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
