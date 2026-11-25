unit PaperBreak_D3D;

// AviUtl2と同じD3D11デバイスで描画し、深度付きの結果を画像へGPU内コピーする。

interface

uses Winapi.D3D11, Winapi.DXGIFormat, PaperBreak_Types, PaperBreak_Mesh;

type
  TPaperD3D = class
  private
    FDevice: ID3D11Device;
    FDeferred: ID3D11DeviceContext;
    FLayout: ID3D11InputLayout;
    FVS: ID3D11VertexShader;
    FPS: ID3D11PixelShader;
    FRaster: ID3D11RasterizerState;
    FSampler: ID3D11SamplerState;
    FVertices, FConstants: ID3D11Buffer;
    FCapacity: Integer;
    FTarget, FDepth, FSource: ID3D11Texture2D;
    FRTV: ID3D11RenderTargetView;
    FDSV: ID3D11DepthStencilView;
    FSourceView: ID3D11ShaderResourceView;
    FWidth,FHeight: Integer;
    FFormat,FSourceFormat: DXGI_FORMAT;
    FSamples: Cardinal;
    FAllowMSAA: Boolean;
    procedure SelectDevice(const Device: ID3D11Device);
    procedure MakePipeline;
    procedure MakeTargets(Width, Height: Integer; Format: DXGI_FORMAT;
      AllowMSAA: Boolean);
    procedure MakeSource(Width, Height: Integer; Format: DXGI_FORMAT);
    procedure EnsureVertexCapacity(Count: Integer);
  public
    // Image is borrowed for this call only. Its top-left Width x Height region is replaced.
    procedure Render(const Image: ID3D11Texture2D; Width, Height: Integer;
      const Frame: TPaperFrame; Mesh: TPaperMesh);
    procedure Clear(const Image: ID3D11Texture2D; Width, Height: Integer);
  end;

implementation

uses
  System.SysUtils, Winapi.Windows, Winapi.D3DCommon, Winapi.D3DCompiler, PaperBreak_Fragments;

{$I PaperBreak_Shader.inc}

type
  TShaderFrame = record
    Camera, Paper, Damage, Mode, PixelSize: array[0..3] of Single;
  end;

const
  CLEAR_RGBA: TFourSingleArray = (0,0,0,0);

procedure Check(Res: HRESULT; const Operation: string);
begin
  if Failed(Res) then
    raise EOSError.CreateFmt('%s failed (0x%.8x)',[Operation,Cardinal(Res)]);
end;

function Shader(const EntryPoint, Profile: AnsiString): ID3DBlob;
var
  Errors: ID3DBlob;
  Res: HRESULT;
  Details: AnsiString;
begin
  Res := D3DCompile(PAnsiChar(PAPER_SHADER),Length(PAPER_SHADER),'PaperBreak',
    nil,nil,PAnsiChar(EntryPoint),PAnsiChar(Profile),D3DCOMPILE_OPTIMIZATION_LEVEL3,
    0,Result,Errors);
  if Failed(Res) and (Errors<>nil) then
  begin
    SetString(Details,PAnsiChar(Errors.GetBufferPointer),Errors.GetBufferSize);
    raise EInvalidOp.Create(string(Details));
  end;
  Check(Res,'D3DCompile');
end;

function ColorFormat(Format: DXGI_FORMAT): DXGI_FORMAT;
begin
  case Format of
    DXGI_FORMAT_R8G8B8A8_TYPELESS: Result := DXGI_FORMAT_R8G8B8A8_UNORM;
    DXGI_FORMAT_B8G8R8A8_TYPELESS: Result := DXGI_FORMAT_B8G8R8A8_UNORM;
    DXGI_FORMAT_R16G16B16A16_TYPELESS: Result := DXGI_FORMAT_R16G16B16A16_FLOAT;
    DXGI_FORMAT_R32G32B32A32_TYPELESS: Result := DXGI_FORMAT_R32G32B32A32_FLOAT;
    DXGI_FORMAT_R10G10B10A2_TYPELESS: Result := DXGI_FORMAT_R10G10B10A2_UNORM;
  else
    Result := Format;
  end;
end;

function TextureDesc(Width, Height: Integer; Format: DXGI_FORMAT;
  Samples, BindFlags: Cardinal): D3D11_TEXTURE2D_DESC;
begin
  Result := Default(D3D11_TEXTURE2D_DESC);
  Result.Width := Width;
  Result.Height := Height;
  Result.Format := Format;
  Result.MipLevels := 1;
  Result.ArraySize := 1;
  Result.SampleDesc.Count := Samples;
  Result.Usage := D3D11_USAGE_DEFAULT;
  Result.BindFlags := BindFlags;
end;

function Region(Width, Height: Integer): D3D11_BOX;
begin
  Result := Default(D3D11_BOX);
  Result.Right := Width;
  Result.Bottom := Height;
  Result.Back := 1;
end;

function MakeResourceView(Device: ID3D11Device; const Image: ID3D11Texture2D;
  Format: DXGI_FORMAT; out View: ID3D11ShaderResourceView): HRESULT;
var
  Desc: D3D11_SHADER_RESOURCE_VIEW_DESC;
begin
  Desc := Default(D3D11_SHADER_RESOURCE_VIEW_DESC);
  Desc.Format := Format;
  Desc.ViewDimension := D3D11_SRV_DIMENSION_TEXTURE2D;
  Desc.Texture2D.MipLevels := 1;
  Result := Device.CreateShaderResourceView(Image,@Desc,View);
end;

procedure TPaperD3D.SelectDevice(const Device: ID3D11Device);
begin
  if (FDevice=Device) and (FDeferred<>nil) then Exit;
  FDevice := Device;
  FDeferred := nil;
  FTarget := nil;
  FDepth := nil;
  FRTV := nil;
  FDSV := nil;
  FSource := nil;
  FSourceView := nil;
  FLayout := nil;
  FVS := nil;
  FPS := nil;
  FRaster := nil;
  FSampler := nil;
  FConstants := nil;
  FVertices := nil;
  FCapacity := 0;
  Check(Device.CreateDeferredContext(0,FDeferred),'CreateDeferredContext');
end;

procedure TPaperD3D.MakePipeline;
var
  VSBlob, PSBlob: ID3DBlob;
  Input: array[0..3] of D3D11_INPUT_ELEMENT_DESC;
  Raster: D3D11_RASTERIZER_DESC;
  Sampler: D3D11_SAMPLER_DESC;
  Buffer: D3D11_BUFFER_DESC;
begin
  if FConstants<>nil then Exit;
  VSBlob := Shader('VS','vs_5_0');
  PSBlob := Shader('PS','ps_5_0');
  Check(FDevice.CreateVertexShader(VSBlob.GetBufferPointer,VSBlob.GetBufferSize,
    nil,@FVS),'CreateVertexShader');
  Check(FDevice.CreatePixelShader(PSBlob.GetBufferPointer,PSBlob.GetBufferSize,
    nil,FPS),'CreatePixelShader');

  FillChar(Input,SizeOf(Input),0);
  Input[0].SemanticName := 'POSITION';
  Input[0].Format := DXGI_FORMAT_R32G32B32_FLOAT;
  Input[1].SemanticName := 'NORMAL';
  Input[1].Format := DXGI_FORMAT_R32G32B32_FLOAT;
  Input[1].AlignedByteOffset := 12;
  Input[2].SemanticName := 'TEXCOORD';
  Input[2].Format := DXGI_FORMAT_R32G32_FLOAT;
  Input[2].AlignedByteOffset := 24;
  Input[3].SemanticName := 'TEXCOORD';
  Input[3].SemanticIndex := 1;
  Input[3].Format := DXGI_FORMAT_R32G32_FLOAT;
  Input[3].AlignedByteOffset := 32;
  Check(FDevice.CreateInputLayout(@Input[0],Length(Input),VSBlob.GetBufferPointer,
    VSBlob.GetBufferSize,FLayout),'CreateInputLayout');

  Raster := Default(D3D11_RASTERIZER_DESC);
  Raster.FillMode := D3D11_FILL_SOLID;
  Raster.CullMode := D3D11_CULL_NONE;
  Raster.FrontCounterClockwise := True;
  Raster.DepthClipEnable := True;
  Raster.MultisampleEnable := True;
  Check(FDevice.CreateRasterizerState(Raster,FRaster),'CreateRasterizerState');

  Sampler := Default(D3D11_SAMPLER_DESC);
  Sampler.Filter := D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT;
  Sampler.AddressU := D3D11_TEXTURE_ADDRESS_CLAMP;
  Sampler.AddressV := D3D11_TEXTURE_ADDRESS_CLAMP;
  Sampler.AddressW := D3D11_TEXTURE_ADDRESS_CLAMP;
  Sampler.ComparisonFunc := D3D11_COMPARISON_NEVER;
  Sampler.MaxAnisotropy := 1;
  Check(FDevice.CreateSamplerState(Sampler,FSampler),'CreateSamplerState');

  Buffer := Default(D3D11_BUFFER_DESC);
  Buffer.ByteWidth := SizeOf(TShaderFrame);
  Buffer.Usage := D3D11_USAGE_DYNAMIC;
  Buffer.BindFlags := D3D11_BIND_CONSTANT_BUFFER;
  Buffer.CPUAccessFlags := D3D11_CPU_ACCESS_WRITE;
  Check(FDevice.CreateBuffer(Buffer,nil,FConstants),'CreateConstantBuffer');
end;

procedure TPaperD3D.MakeTargets(Width, Height: Integer; Format: DXGI_FORMAT;
  AllowMSAA: Boolean);
var
  Desc: D3D11_TEXTURE2D_DESC;
  Samples, ColorQuality, DepthQuality, Flags: Cardinal;
  Target, Depth: ID3D11Texture2D;
  RTV: ID3D11RenderTargetView;
  DSV: ID3D11DepthStencilView;
begin
  if (FTarget<>nil) and (FWidth=Width) and (FHeight=Height) and
    (FFormat=Format) and (FAllowMSAA=AllowMSAA) then Exit;
  Samples := 1;
  // 大きい画像では色と深度のMSAAが圧迫するVRAMを抑える。
  if AllowMSAA and (Int64(Width)*Height<=3200000) and
    Succeeded(FDevice.CheckFormatSupport(Format,Flags)) and
    ((Flags and Ord(D3D11_FORMAT_SUPPORT_MULTISAMPLE_RESOLVE))<>0) then
  begin
    if Int64(Width)*Height<=1200000 then Samples := 4
    else Samples := 2;
    while Samples>1 do
    begin
      if Succeeded(FDevice.CheckMultisampleQualityLevels(Format,Samples,ColorQuality)) and
        Succeeded(FDevice.CheckMultisampleQualityLevels(DXGI_FORMAT_D32_FLOAT,
          Samples,DepthQuality)) and (ColorQuality>0) and (DepthQuality>0) then Break;
      Samples := Samples div 2;
    end;
  end;

  Desc := TextureDesc(Width,Height,Format,Samples,D3D11_BIND_RENDER_TARGET);
  Check(FDevice.CreateTexture2D(Desc,nil,Target),'CreateColorTexture');
  Check(FDevice.CreateRenderTargetView(Target,nil,RTV),'CreateRenderTargetView');
  Desc := TextureDesc(Width,Height,DXGI_FORMAT_D32_FLOAT,Samples,D3D11_BIND_DEPTH_STENCIL);
  Check(FDevice.CreateTexture2D(Desc,nil,Depth),'CreateDepthTexture');
  Check(FDevice.CreateDepthStencilView(Depth,nil,DSV),'CreateDepthStencilView');

  FTarget := Target;
  FRTV := RTV;
  FDepth := Depth;
  FDSV := DSV;
  FWidth := Width;
  FHeight := Height;
  FFormat := Format;
  FSamples := Samples;
  FAllowMSAA := AllowMSAA;
end;

procedure TPaperD3D.MakeSource(Width, Height: Integer; Format: DXGI_FORMAT);
var
  Desc: D3D11_TEXTURE2D_DESC;
  Source: ID3D11Texture2D;
  View: ID3D11ShaderResourceView;
begin
  if FSource<>nil then
  begin
    FSource.GetDesc(Desc);
    if (Desc.Width=Cardinal(Width)) and (Desc.Height=Cardinal(Height)) and
      (FSourceFormat=Format) then Exit;
  end;
  Desc := TextureDesc(Width,Height,Format,1,D3D11_BIND_SHADER_RESOURCE);
  Check(FDevice.CreateTexture2D(Desc,nil,Source),'CreateSourceTexture');
  Check(MakeResourceView(FDevice,Source,Format,View),'CreateSourceView');
  FSource := Source;
  FSourceView := View;
  FSourceFormat := Format;
end;

procedure TPaperD3D.EnsureVertexCapacity(Count: Integer);
var
  Desc: D3D11_BUFFER_DESC;
  Capacity: Integer;
  Buffer: ID3D11Buffer;
begin
  if Count<=FCapacity then Exit;
  Capacity := 4096;
  while Capacity<Count do Capacity := Capacity*2;
  Desc := Default(D3D11_BUFFER_DESC);
  Desc.ByteWidth := Capacity*SizeOf(TPaperVertex);
  Desc.Usage := D3D11_USAGE_DYNAMIC;
  Desc.BindFlags := D3D11_BIND_VERTEX_BUFFER;
  Desc.CPUAccessFlags := D3D11_CPU_ACCESS_WRITE;
  Check(FDevice.CreateBuffer(Desc,nil,Buffer),'CreateVertexBuffer');
  FVertices := Buffer;
  FCapacity := Capacity;
end;

procedure TPaperD3D.Clear(const Image: ID3D11Texture2D; Width, Height: Integer);
var
  Device: ID3D11Device;
  Immediate: ID3D11DeviceContext;
  View: ID3D11RenderTargetView;
  ImageDesc, ClearDesc: D3D11_TEXTURE2D_DESC;
  Desc: D3D11_RENDER_TARGET_VIEW_DESC;
  Target: ID3D11Texture2D;
  Format: DXGI_FORMAT;
  Box: D3D11_BOX;
begin
  Image.GetDevice(Device);
  Image.GetDesc(ImageDesc);
  Device.GetImmediateContext(Immediate);
  Format := ColorFormat(ImageDesc.Format);
  Desc := Default(D3D11_RENDER_TARGET_VIEW_DESC);
  Desc.Format := Format;
  Desc.ViewDimension := D3D11_RTV_DIMENSION_TEXTURE2D;
  if Succeeded(Device.CreateRenderTargetView(Image,@Desc,View)) then
    Immediate.ClearRenderTargetView(View,CLEAR_RGBA)
  else
  begin
    // RTVを持たない画像へも同型のGPUテクスチャから透明画素を書き込める。
    if (FDevice=Device) and (FTarget<>nil) and (FSamples=1) and
      (FWidth=Width) and (FHeight=Height) and (FFormat=Format) then
    begin
      Target := FTarget;
      View := FRTV;
    end
    else
    begin
      ClearDesc := TextureDesc(Width,Height,Format,1,D3D11_BIND_RENDER_TARGET);
      Check(Device.CreateTexture2D(ClearDesc,nil,Target),'CreateClearTexture');
      Check(Device.CreateRenderTargetView(Target,nil,View),'CreateClearView');
    end;
    Immediate.ClearRenderTargetView(View,CLEAR_RGBA);
    Box := Region(Width,Height);
    Immediate.CopySubresourceRegion(Image,0,0,0,0,Target,0,@Box);
  end;
  Check(Device.GetDeviceRemovedReason,'ClearImage');
end;

procedure TPaperD3D.Render(const Image: ID3D11Texture2D; Width, Height: Integer;
  const Frame: TPaperFrame; Mesh: TPaperMesh);
var
  Device: ID3D11Device;
  Immediate: ID3D11DeviceContext;
  ImageDesc: D3D11_TEXTURE2D_DESC;
  Format: DXGI_FORMAT;
  InputView, EmptyView: ID3D11ShaderResourceView;
  Cmd: ID3D11CommandList;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  Constants: TShaderFrame;
  Viewport: D3D11_VIEWPORT;
  Box: D3D11_BOX;
  Stride, Offset: Cardinal;
  Finished: Boolean;
begin
  Image.GetDevice(Device);
  Image.GetDesc(ImageDesc);
  if (ImageDesc.ArraySize<>1) or (ImageDesc.SampleDesc.Count<>1) or
    (ImageDesc.Width<Cardinal(Width)) or (ImageDesc.Height<Cardinal(Height)) then
    raise EInvalidOp.Create('Unsupported object texture layout');

  SelectDevice(Device);
  Format := ColorFormat(ImageDesc.Format);
  MakePipeline;
  MakeTargets(Width,Height,Format,
    (ImageDesc.Width=Cardinal(Width)) and (ImageDesc.Height=Cardinal(Height)));
  EnsureVertexCapacity(Mesh.Count);

  Constants := Default(TShaderFrame);
  Constants.Camera[0] := 1/Frame.HalfW;
  Constants.Camera[1] := 1/Frame.HalfH;
  if Frame.Settings.Style<>psBurn then
    Constants.Camera[2] := Frame.Lighting;
  Constants.Camera[3] := Frame.Progress;
  Constants.Paper[0] := Frame.Origin.X;
  Constants.Paper[1] := Frame.Origin.Y;
  Constants.Paper[2] := Frame.HalfW;
  Constants.Paper[3] := Frame.HalfH;
  Constants.Damage[0] := Frame.Radius;
  Constants.Damage[1] := 0;
  Constants.Damage[2] := Frame.ShortSide;
  Constants.Damage[3] := 257*Noise(148,Frame.Settings.Seed);
  Constants.Mode[0] := Ord(Frame.Settings.Style);
  Constants.Mode[1] := Width/ImageDesc.Width;
  Constants.Mode[2] := Height/ImageDesc.Height;
  Constants.Mode[3] := Ord(Frame.Thickness>0);
  Constants.PixelSize[0] := 1/Width;
  Constants.PixelSize[1] := 1/Height;
  if Frame.Settings.Style in [psBurn,psSoak] then
    Constants.Damage[1] := DamageFront(Frame);

  Box := Region(Width,Height);
  Finished := False;
  try
    if Mesh.Count>0 then
    begin
      if Failed(MakeResourceView(FDevice,Image,Format,InputView)) then
      begin
        MakeSource(Width,Height,Format);
        FDeferred.CopySubresourceRegion(FSource,0,0,0,0,Image,0,@Box);
        InputView := FSourceView;
        Constants.Mode[1] := 1;
        Constants.Mode[2] := 1;
      end;
      Check(FDeferred.Map(FVertices,0,D3D11_MAP_WRITE_DISCARD,0,Mapped),'MapVertices');
      Move(Mesh.Data^,Mapped.pData^,Mesh.Count*SizeOf(TPaperVertex));
      FDeferred.Unmap(FVertices,0);
      Check(FDeferred.Map(FConstants,0,D3D11_MAP_WRITE_DISCARD,0,Mapped),'MapConstants');
      Move(Constants,Mapped.pData^,SizeOf(Constants));
      FDeferred.Unmap(FConstants,0);

      Viewport := Default(D3D11_VIEWPORT);
      Viewport.Width := Width;
      Viewport.Height := Height;
      Viewport.MaxDepth := 1;
      Stride := SizeOf(TPaperVertex);
      Offset := 0;
      FDeferred.IASetInputLayout(FLayout);
      FDeferred.IASetVertexBuffers(0,1,FVertices,@Stride,@Offset);
      FDeferred.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
      FDeferred.VSSetShader(FVS,nil,0);
      FDeferred.VSSetConstantBuffers(0,1,FConstants);
      FDeferred.PSSetShader(FPS,nil,0);
      FDeferred.PSSetConstantBuffers(0,1,FConstants);
      FDeferred.PSSetShaderResources(0,1,InputView);
      FDeferred.PSSetSamplers(0,1,FSampler);
      FDeferred.RSSetState(FRaster);
      FDeferred.RSSetViewports(1,@Viewport);
      FDeferred.OMSetRenderTargets(1,FRTV,FDSV);
      FDeferred.ClearDepthStencilView(FDSV,D3D11_CLEAR_DEPTH,1,0);
    end;
    FDeferred.ClearRenderTargetView(FRTV,CLEAR_RGBA);
    if Mesh.Count>0 then FDeferred.Draw(Mesh.Count,0);
    EmptyView := nil;
    FDeferred.PSSetShaderResources(0,1,EmptyView);
    FDeferred.OMSetRenderTargets(0,nil,nil);
    if FSamples>1 then
      FDeferred.ResolveSubresource(Image,0,FTarget,0,Format)
    else
      FDeferred.CopySubresourceRegion(Image,0,0,0,0,FTarget,0,@Box);
    Check(FDeferred.FinishCommandList(False,Cmd),'FinishCommandList');
    Finished := True;
    Device.GetImmediateContext(Immediate);
    Immediate.ExecuteCommandList(Cmd,True);
    Check(Device.GetDeviceRemovedReason,'ExecuteCommandList');
  finally
    // 作成途中のコマンドも、コールバックをまたいでホスト画像を保持しない。
    if not Finished then FDeferred := nil;
  end;
end;

end.
