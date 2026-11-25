program PaperBreak_RenderTests;

// 本番AUF2を読み込み、D3D11画像を渡してフィルター処理を検査する。
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, Winapi.Windows, Winapi.D3D11, Winapi.D3DCommon,
  Winapi.DXGIFormat, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TRequiredVersion = function: Cardinal; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  PChoice = ^TFILTER_ITEM_SELECT_ITEM;
  THalfPixel = packed record
    R,G,B,A: Word;
  end;
  TPixelBuffer = TArray<THalfPixel>;
  TCounts = record
    Visible, Transparent, Changed: Integer;
  end;

const
  STYLES: array[0..8] of string = ('Tear','Repeat','Shred','Crumple','Fold',
    'Scissors','Burn','Soak','Weather');
  TIMES: array[0..5] of Double = (0.13,0.30,0.46,0.60,0.74,0.88);
  REPLAY_ORDER: array[0..5] of Integer = (5,1,3,0,4,2);
  COLUMNS = 6;

var
  Device: ID3D11Device;
  Context: ID3D11DeviceContext;
  Source, Readback: ID3D11Texture2D;
  Width,Height,TexWidth,TexHeight: Integer;
  ObjectInfo: TOBJECT_INFO;
  Video: TFILTER_PROC_VIDEO;
  Table: PFILTER_PLUGIN_TABLE;
  Original: TPixelBuffer;
  Select: PFILTER_ITEM_SELECT;
  Tracks: array[0..8] of PFILTER_ITEM_TRACK;

procedure Expect(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

procedure Check(Res: HRESULT; const Operation: string);
begin
  Expect(Succeeded(Res),Format('%s (0x%.8x)',[Operation,Cardinal(Res)]));
end;

function GetImageTexture: Pointer; cdecl;
begin
  Result := Pointer(Source);
end;

procedure PutPixels(Buffer: Pointer; W,H: Integer);
var
  Box: D3D11_BOX;
begin
  Expect((Buffer<>nil) and (W=Width) and (H=Height),'Fixture dimensions');
  Box := Default(D3D11_BOX);
  Box.Right := W;
  Box.Bottom := H;
  Box.Back := 1;
  Context.UpdateSubresource(Source,0,@Box,Buffer,W*SizeOf(THalfPixel),0);
end;

function Half(Value: Single): Word;
var
  Bits: Cardinal;
begin
  if Value=0 then Exit(0);
  Move(Value,Bits,SizeOf(Value));
  Result := Word((((Bits shr 23)-112) shl 10) +
    (((Bits and $7FFFFF)+$1000) shr 13));
end;

function ByteFromHalf(Value: Word): Integer;
var
  Exponent: Integer;
begin
  Exponent := (Value shr 10) and 31;
  if Exponent=0 then
    Exit(Round((Value and 1023)*(255/16777216)));
  Result := Round(Ldexp(1+(Value and 1023)/1024,Exponent-15)*255);
end;

procedure MakeTexture(AWidth,AHeight: Integer; Padded: Boolean; BindFlags: Cardinal);
var
  Desc: D3D11_TEXTURE2D_DESC;
  X,Y,I: Integer;
  P: TPIXEL_RGBA;
begin
  Width := AWidth;
  Height := AHeight;
  TexWidth := Width+Ord(Padded)*17;
  TexHeight := Height+Ord(Padded)*9;
  Desc := Default(D3D11_TEXTURE2D_DESC);
  Desc.Width := TexWidth;
  Desc.Height := TexHeight;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_R16G16B16A16_FLOAT;
  Desc.SampleDesc.Count := 1;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Desc.BindFlags := BindFlags;
  Check(Device.CreateTexture2D(Desc,nil,Source),'Create input texture');

  Desc.Usage := D3D11_USAGE_STAGING;
  Desc.BindFlags := 0;
  Desc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
  Check(Device.CreateTexture2D(Desc,nil,Readback),'Create readback texture');

  ObjectInfo.Width := Width;
  ObjectInfo.Height := Height;
  SetLength(Original,Width*Height);
  for Y := 0 to Height-1 do
    for X := 0 to Width-1 do
    begin
      I := Y*Width+X;
      P.R := 35+X*165 div Width;
      P.G := 32+Y*149 div Height;
      P.B := 128+(X+Y)*80 div (Width+Height);
      P.A := 255;
      if ((X div 11 + Y div 11) mod 2=0) and
        (X>Width div 11) and (X<Width*10 div 11) and
        (Y>Height div 9) and (Y<Height*8 div 9) then
      begin
        P.R := P.R div 2;
        P.G := P.G div 2;
        P.B := P.B div 2;
      end;
      if (Abs(X-Width div 2)<2) or (Abs(Y-Height div 2)<2) then
      begin
        P.R := 237;
        P.G := 191;
        P.B := 100;
      end;
      Original[I].R := Half(P.R/255);
      Original[I].G := Half(P.G/255);
      Original[I].B := Half(P.B/255);
      Original[I].A := Half(P.A/255);
    end;
end;

function Draw(Seconds: Double): TPixelBuffer;
var
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  Before, After: D3D11_VIEWPORT;
  Viewports: Cardinal;
  Y: Integer;
begin
  PutPixels(@Original[0],Width,Height);
  Before := Default(D3D11_VIEWPORT);
  Before.TopLeftX := 3;
  Before.TopLeftY := 2;
  Before.Width := 80;
  Before.Height := 77;
  Before.MaxDepth := 1;
  Context.RSSetViewports(1,@Before);
  ObjectInfo.Time := Seconds;
  Expect(Table^.Func_Proc_Video(@Video)=1,'Filter must preserve the output chain');
  Viewports := 1;
  Context.RSGetViewports(Viewports,@After);
  Expect((Viewports=1) and CompareMem(@Before,@After,SizeOf(Before)),
    'Filter changed the host D3D viewport');
  Context.CopyResource(Readback,Source);
  Check(Context.Map(Readback,0,D3D11_MAP_READ,0,Mapped),'Read result');
  try
    SetLength(Result,Width*Height);
    for Y := 0 to Height-1 do
      Move(PByte(Mapped.pData)[NativeInt(Y)*Mapped.RowPitch],Result[Y*Width],Width*SizeOf(THalfPixel));
  finally
    Context.Unmap(Readback,0);
  end;
end;

function Identical(const A,B: TPixelBuffer): Boolean;
begin
  Result := (Length(A)=Length(B)) and CompareMem(@A[0],@B[0],Length(A)*SizeOf(THalfPixel));
end;

function Count(const Pixels: TPixelBuffer): TCounts;
var
  I: Integer;
  P: THalfPixel;
begin
  Result := Default(TCounts);
  for I := 0 to High(Pixels) do
  begin
    P := Pixels[I];
    if P.A>0 then Inc(Result.Visible)
    else
    begin
      Inc(Result.Transparent);
      Expect((P.R=0) and (P.G=0) and (P.B=0),'Clear pixel has nonzero color');
    end;
    if not CompareMem(@P,@Original[I],SizeOf(THalfPixel)) then Inc(Result.Changed);
  end;
end;

procedure VerifyTable;
var
  Item: PPointer;
  Choice: PChoice;
  I: Integer;
begin
  Expect(Table<>nil,'Registration table');
  Expect(string(Table^.Name)='紙消失','Plugin name');
  Expect(string(Table^.Label_)='SYNC','Plugin group');
  Expect(Table^.Flag=FILTER_FLAG_VIDEO or FILTER_FLAG_USERDATA,'Image effect flags');
  Item := PPointer(Table^.Items);
  Select := PFILTER_ITEM_SELECT(Item^);
  Expect(string(Select^.Name)='スタイル','First parameter');
  Expect(Select^.Value=0,'Default style');
  Choice := PChoice(Select^.List);
  for I := 0 to High(STYLES) do
  begin
    Expect((Choice^.Name<>nil) and (Choice^.Value=I),'Style choices');
    Inc(Choice);
  end;
  Expect(Choice^.Name=nil,'Style list terminator');
  for I := 0 to High(Tracks) do
  begin
    Inc(Item);
    Tracks[I] := PFILTER_ITEM_TRACK(Item^);
    Expect(string(Tracks[I]^.ItemType)='track','Track type');
    if I<High(Tracks) then
      Expect(SameValue(Tracks[I]^.Step,0.01,1E-9),'Track step')
    else Expect(Tracks[I]^.Step=1,'Integer seed');
  end;
  Expect(SameValue(Tracks[0]^.S,0.01,1E-9) and
    (Tracks[0]^.E=100) and (Tracks[0]^.Value=3),'Duration spec');
  Inc(Item);
  Expect(Item^=nil,'Parameter list terminator');
end;

procedure Paint(PNG: TPngImage; const Pixels: TPixelBuffer; Row, Col: Integer);
var
  ColorRow: PByte;
  X,Y,Offset,Shade,Alpha: Integer;
  P: THalfPixel;
begin
  for Y := 0 to Height-1 do
  begin
    ColorRow := PNG.Scanline[Row*(Height+4)+Y];
    for X := 0 to Width-1 do
    begin
      P := Pixels[Y*Width+X];
      Offset := 3*(Col*(Width+4)+X);
      Alpha := ByteFromHalf(P.A);
      Shade := 28+15*((X div 8 + Y div 8) mod 2);
      ColorRow[Offset] := Min(255,ByteFromHalf(P.B)+Shade*(255-Alpha) div 255);
      ColorRow[Offset+1] := Min(255,ByteFromHalf(P.G)+Shade*(255-Alpha) div 255);
      ColorRow[Offset+2] := Min(255,ByteFromHalf(P.R)+Shade*(255-Alpha) div 255);
    end;
  end;
end;

procedure VerifyStyles(const PreviewPath: string);
var
  Style,I,J: Integer;
  Baseline: array[0..High(TIMES)] of TPixelBuffer;
  Pixels: TPixelBuffer;
  Stats: TCounts;
  PNG: TPngImage;
  SeedScene: TPixelBuffer;
  Backside: THalfPixel;
begin
  MakeTexture(256,144,False,D3D11_BIND_SHADER_RESOURCE or D3D11_BIND_RENDER_TARGET);
  PNG := nil;
  if PreviewPath<>'' then
    PNG := TPngImage.CreateBlank(COLOR_RGB,8,COLUMNS*(Width+4),Length(STYLES)*(Height+4));
  try
    for Style := 0 to High(STYLES) do
    begin
      Select^.Value := Style;
      Expect(Identical(Draw(0),Original),STYLES[Style]+': start differs');
      Expect(Count(Draw(3)).Transparent=Length(Original),STYLES[Style]+': end');
      Expect(Count(Draw(9)).Transparent=Length(Original),STYLES[Style]+': after end');
      for I := 0 to High(TIMES) do
      begin
        Baseline[I] := Draw(TIMES[I]*3);
        if PNG<>nil then Paint(PNG,Baseline[I],Style,I);
      end;
      if Style=4 then
      begin
        Backside := Baseline[1][(Height div 2)*Width+Width div 4];
        Expect((Backside.A=Half(1)) and (ByteFromHalf(Backside.R)>190) and
          (ByteFromHalf(Backside.G)>180),'Fold does not show the paper reverse');
      end;
      Stats := Count(Baseline[2]);
      Expect(Stats.Changed>Length(Original) div 20,STYLES[Style]+': mid-frame unchanged');
      Expect(Stats.Visible>Length(Original) div 60,STYLES[Style]+': mid-frame empty');
      Expect(Stats.Transparent>10,STYLES[Style]+': mid-frame has no holes');
      for I := 0 to High(REPLAY_ORDER) do
      begin
        J := REPLAY_ORDER[I];
        Pixels := Draw(TIMES[J]*3);
        Expect(Identical(Pixels,Baseline[J]),STYLES[Style]+': nondeterministic when seeking');
      end;
      Expect(Count(Baseline[5]).Visible<Count(Baseline[0]).Visible,
        STYLES[Style]+': no net disappearance');
      Writeln(Format('%-9s PASS  midpoint %d/%d visible  late %d/%d',
        [STYLES[Style],Stats.Visible,Length(Original),Count(Baseline[5]).Visible,Length(Original)]));
    end;
    if PNG<>nil then PNG.SaveToFile(PreviewPath);
  finally
    PNG.Free;
  end;

  Select^.Value := 0;
  SeedScene := Draw(1.23);
  Tracks[8]^.Value := Low(Integer);
  Expect(not Identical(Draw(1.23),SeedScene),'Tear seed must vary the result');
  Tracks[8]^.Value := High(Integer);
  Expect(not Identical(Draw(1.23),SeedScene),'Tear high seed must vary the result');
  Tracks[8]^.Value := 0;
end;

procedure CheckCoveredPrint(const Pixels: TPixelBuffer; Left,Top,Right,Bottom: Integer;
  const Stage: string);
var
  X,Y: Integer;
  Pixel: THalfPixel;
begin
  for Y := Top to Bottom do
    for X := Left to Right do
    begin
      Pixel := Pixels[Y*Width+X];
      Expect((Pixel.A=Half(1)) and (Pixel.R>Pixel.B),Stage);
    end;
end;

procedure VerifyFoldOverlap(const PreviewPath: string);
const
  FoldTimes: array[0..8] of Double = (0.18,0.24,0.299,0.385,0.47,0.539,
    0.625,0.685,0.739);
  Thicknesses: array[0..2] of Integer = (0,10,100);
var
  Picture: TPngImage;
  Pixels: TPixelBuffer;
  I,J: Integer;
begin
  Select^.Value := 4;
  MakeTexture(192,120,False,D3D11_BIND_SHADER_RESOURCE or D3D11_BIND_RENDER_TARGET);
  Picture := nil;
  if PreviewPath<>'' then
    Picture := TPngImage.CreateBlank(COLOR_RGB,8,Length(FoldTimes)*(Width+4),
      Length(Thicknesses)*(Height+4));
  try
    for I := 0 to High(Thicknesses) do
    begin
      Tracks[3]^.Value := Thicknesses[I];
      for J := 0 to High(FoldTimes) do
      begin
        Pixels := Draw(3*FoldTimes[J]);
        if Picture<>nil then Paint(Picture,Pixels,I,J);
        case J of
          3: CheckCoveredPrint(Pixels,9,72,35,85,'Second fold exposes covered print');
          6: CheckCoveredPrint(Pixels,40,20,45,28,'Third fold exposes covered print');
        end;
      end;
    end;
    if Picture<>nil then Picture.SaveToFile(ChangeFileExt(PreviewPath,'-fold.png'));
    Writeln('Second and third folds hide the inner faces at all tested thicknesses PASS');
  finally
    Tracks[3]^.Value := 10;
    Picture.Free;
  end;
end;

procedure VerifyBurnDoesNotMove;
var
  Baseline, ResultPixels: TPixelBuffer;
  X,Y,I: Integer;
  Expected, Actual: THalfPixel;
begin
  Select^.Value := 6;
  MakeTexture(315,180,False,D3D11_BIND_SHADER_RESOURCE or D3D11_BIND_RENDER_TARGET);
  Baseline := Draw(3*0.36);
  for Y := 2 to Height div 8 do
    for X := 0 to Width-1 do
    begin
      I := Y*Width+X;
      Expected := Original[I];
      Actual := Baseline[I];
      Expect((Actual.A=Expected.A) and
        (Abs(ByteFromHalf(Actual.R)-ByteFromHalf(Expected.R))<=1) and
        (Abs(ByteFromHalf(Actual.G)-ByteFromHalf(Expected.G))<=1) and
        (Abs(ByteFromHalf(Actual.B)-ByteFromHalf(Expected.B))<=1),
        'Burn moved or relit the intact part of the print');
    end;

  Tracks[4]^.Value := 0;
  Tracks[5]^.Value := 100;
  Tracks[6]^.Value := 100;
  Tracks[7]^.Value := 100;
  ResultPixels := Draw(3*0.36);
  Expect(Identical(Baseline,ResultPixels),'Burn geometry depends on the motion parameters');
  Tracks[4]^.Value := 50;
  Tracks[5]^.Value := 50;
  Tracks[6]^.Value := 50;
  Tracks[7]^.Value := 30;
  Writeln('Burn keeps the intact print fixed and unchanged PASS');
end;

procedure VerifyAspectAndInputs;
var
  AtRight, AtTop, AtHalf: TPixelBuffer;
  Stats: TCounts;
  Style: Integer;
begin
  // RTV/SRVを持たず、画像領域より大きいホストテクスチャを通す。
  MakeTexture(115,201,True,0);
  Select^.Value := 6;
  Tracks[1]^.Value := 0;
  AtRight := Draw(0.98);
  Tracks[1]^.Value := 90;
  AtTop := Draw(0.98);
  Expect(not Identical(AtTop,AtRight),'Start angle changes burn source');
  Stats := Count(AtTop);
  Expect((Stats.Visible>0) and (Stats.Transparent>0),'Padded texture draw');
  Tracks[2]^.Value := 0;
  Expect(not Identical(Draw(0.98),AtTop),'Start position changes burn source');
  AtHalf := Draw(1.5);
  Tracks[0]^.Value := 0.01;
  Expect(Count(Draw(0.01)).Transparent=Length(Original),'Minimum duration');
  Tracks[0]^.Value := 100;
  Expect(Count(Draw(100)).Transparent=Length(Original),'Maximum duration');
  Expect(Identical(AtHalf,Draw(50)),'Duration must scale the same normalized frame');
  Stats := Count(Draw(49));
  Expect((Stats.Visible>0) and (Stats.Transparent>0),'Long duration in progress');
  Tracks[1]^.Value := 270;
  Tracks[2]^.Value := 100;
  Tracks[3]^.Value := 0;
  for Style := 0 to High(STYLES) do
  begin
    Select^.Value := Style;
    Stats := Count(Draw(46));
    Expect((Stats.Visible>10) and (Stats.Changed>10),STYLES[Style]+': zero-thickness draw');
  end;
  Writeln('Padded portrait texture, inscribed start ray, zero thickness, durations PASS');
end;

procedure Run;
var
  DLL: HMODULE;
  Init: TInitialize;
  Uninit: TUninitialize;
  Required: TRequiredVersion;
  GetTable: TGetTable;
  Level: D3D_FEATURE_LEVEL;
  Driver: D3D_DRIVER_TYPE;
begin
  Expect(ParamCount>=1,'Pass the path to the AUF2. Optional preview PNG and warp flag.');
  Driver := D3D_DRIVER_TYPE_HARDWARE;
  if SameText(ParamStr(3),'warp') then Driver := D3D_DRIVER_TYPE_WARP;
  Check(D3D11CreateDevice(nil,Driver,0,0,nil,0,D3D11_SDK_VERSION,
    Device,Level,Context),'Create test device');
  DLL := LoadLibrary(PChar(ExpandFileName(ParamStr(1))));
  if DLL=0 then RaiseLastOSError;
  try
    Init := TInitialize(GetProcAddress(DLL,'InitializePlugin'));
    Uninit := TUninitialize(GetProcAddress(DLL,'UninitializePlugin'));
    Required := TRequiredVersion(GetProcAddress(DLL,'RequiredVersion'));
    GetTable := TGetTable(GetProcAddress(DLL,'GetFilterPluginTable'));
    Expect(Assigned(Init) and Assigned(Uninit) and Assigned(Required) and
      Assigned(GetTable),'Four SDK exports');
    Expect((Required()=2011600) and (Init(Required()-1)=0) and
      (Init(Required())=1),'Minimum version');
    Table := GetTable();
    VerifyTable;
    ObjectInfo.EffectID := 134;
    Video.Object_ := @ObjectInfo;
    Video.GetImageTexture2D := GetImageTexture;

    Video.UserData := Table^.Func_Create(ObjectInfo.EffectID);
    Expect(Video.UserData<>nil,'Create filter session');
    try
      VerifyStyles(ParamStr(2));
      VerifyFoldOverlap(ParamStr(2));
      VerifyBurnDoesNotMove;
      VerifyAspectAndInputs;
    finally
      Table^.Func_Destroy(ObjectInfo.EffectID,Video.UserData);
      Uninit;
    end;
  finally
    FreeLibrary(DLL);
  end;
  Writeln('All PaperBreak render checks passed.');
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput,E.ClassName,': ',E.Message);
      ExitCode := 1;
    end;
  end;
end.
