unit PaperBreak_Types;

// 紙面座標、再現可能な乱数、各種演出が共有する入力値。

interface

type
  TPaperStyle = (psTear, psRepeatedTear, psShred, psCrumple, psFold, psScissors,
    psBurn, psSoak, psWeather);

  TPaperSettings = record
    Style: TPaperStyle;
    Duration, Angle, Position, Thickness, Stiffness, Deformation, Gravity,
      Scatter: Double;
    Seed: Integer;
  end;

  TVec2 = record
    X, Y: Single;
    class operator Add(const A, B: TVec2): TVec2;
    class operator Subtract(const A, B: TVec2): TVec2;
    class operator Multiply(const A: TVec2; B: Single): TVec2;
  end;

  TVec3 = record
    X, Y, Z: Single;
    class operator Add(const A, B: TVec3): TVec3;
    class operator Subtract(const A, B: TVec3): TVec3;
    class operator Multiply(const A: TVec3; B: Single): TVec3;
  end;

  TPaperFrame = record
    Settings: TPaperSettings;
    Progress, HalfW, HalfH, ShortSide, Thickness, Lighting: Single;
    Origin, Boundary, Direction: TVec2;
    Radius: Single;
    function ToUV(const P: TVec2): TVec2;
  end;

  TPaperVertex = record
    Position, Normal: TVec3;
    UV: TVec2;
    Material, Edge: Single;
  end;
  PPaperVertex = ^TPaperVertex;

const
  MAT_PAPER = 0;
  MAT_EDGE = 1;
  MAT_PULP = 3;
  MAT_STEEL = 4;
  MAT_GRIP = 5;
  MAT_PIN = 6;

function V2(X,Y: Single): TVec2; inline;
function V3(X,Y,Z: Single): TVec3; inline;
function Dot(const A,B: TVec2): Single; inline;
function Cross(const A,B: TVec3): TVec3; inline;
function UnitVector(const A: TVec3): TVec3;
function Rotate(const P: TVec3; AX, AY, AZ: Single): TVec3;
function Limit(X: Single): Single; inline;
function Ease(FromValue, ToValue, X: Single): Single;
function Noise(Key, Seed: Integer): Single;
function MakeFrame(const Settings: TPaperSettings; Progress: Double;
  Width, Height: Integer): TPaperFrame;

implementation

uses System.Math;

function V2(X,Y: Single): TVec2;
begin
  Result.X := X;
  Result.Y := Y;
end;

function V3(X,Y,Z: Single): TVec3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

class operator TVec2.Add(const A, B: TVec2): TVec2;
begin
  Result := V2(A.X+B.X, A.Y+B.Y);
end;

class operator TVec2.Subtract(const A, B: TVec2): TVec2;
begin
  Result := V2(A.X-B.X, A.Y-B.Y);
end;

class operator TVec2.Multiply(const A: TVec2; B: Single): TVec2;
begin
  Result := V2(A.X*B, A.Y*B);
end;

class operator TVec3.Add(const A, B: TVec3): TVec3;
begin
  Result := V3(A.X+B.X, A.Y+B.Y, A.Z+B.Z);
end;

class operator TVec3.Subtract(const A, B: TVec3): TVec3;
begin
  Result := V3(A.X-B.X, A.Y-B.Y, A.Z-B.Z);
end;

class operator TVec3.Multiply(const A: TVec3; B: Single): TVec3;
begin
  Result := V3(A.X*B, A.Y*B, A.Z*B);
end;

function Dot(const A,B: TVec2): Single;
begin
  Result := A.X*B.X + A.Y*B.Y;
end;

function Cross(const A,B: TVec3): TVec3;
begin
  Result := V3(A.Y*B.Z-A.Z*B.Y, A.Z*B.X-A.X*B.Z, A.X*B.Y-A.Y*B.X);
end;

function UnitVector(const A: TVec3): TVec3;
var
  L: Single;
begin
  L := Sqrt(Sqr(A.X)+Sqr(A.Y)+Sqr(A.Z));
  if L > 1E-9 then Result := A * (1/L)
  else Result := V3(0,0,1);
end;

function Rotate(const P: TVec3; AX, AY, AZ: Single): TVec3;
var
  Q: TVec3;
  S,C: Single;
begin
  SinCos(AX,S,C);
  Q := V3(P.X, C*P.Y-S*P.Z, S*P.Y+C*P.Z);
  SinCos(AY,S,C);
  Result := V3(C*Q.X+S*Q.Z, Q.Y, C*Q.Z-S*Q.X);
  SinCos(AZ,S,C);
  Q := Result;
  Result := V3(C*Q.X-S*Q.Y, S*Q.X+C*Q.Y, Q.Z);
end;

function Limit(X: Single): Single;
begin
  if X<0 then Result := 0
  else if X>1 then Result := 1
  else Result := X;
end;

function Ease(FromValue, ToValue, X: Single): Single;
var
  T: Single;
begin
  T := Limit((X-FromValue)/(ToValue-FromValue));
  Result := T*T*(3-2*T);
end;

// 32ビット相当の整数ハッシュ。Debugの演算オーバーフロー検査にも対応する。
function Noise(Key, Seed: Integer): Single;
var
  H: UInt64;
begin
  H := (UInt64(Cardinal(Key))*$9E3779B1 xor Cardinal(Seed)) and $FFFFFFFF;
  H := ((H xor (H shr 16))*$7FEB352D) and $FFFFFFFF;
  H := ((H xor (H shr 15))*$846CA68B) and $FFFFFFFF;
  H := H xor (H shr 16);
  Result := Single(H and $FFFFFF) / $FFFFFF;
end;

function TPaperFrame.ToUV(const P: TVec2): TVec2;
begin
  Result := V2(0.5+P.X/(2*HalfW), 0.5-P.Y/(2*HalfH));
end;

function MakeFrame(const Settings: TPaperSettings; Progress: Double;
  Width, Height: Integer): TPaperFrame;
var
  Extent: Integer;
  RayScale: Single;
begin
  Extent := Max(Width, Height);
  Result.Settings := Settings;
  Result.Progress := Progress;
  Result.HalfW := Width / Extent;
  Result.HalfH := Height / Extent;
  Result.ShortSide := Min(Result.HalfW,Result.HalfH);
  Result.Thickness := 0.013 * Result.ShortSide * Settings.Thickness *
    Ease(0,0.11,Result.Progress);
  Result.Lighting := Ease(0,0.14,Result.Progress);
  Result.Direction := V2(Cos(DegToRad(Settings.Angle)),Sin(DegToRad(Settings.Angle)));
  RayScale := 1 / Max(Abs(Result.Direction.X)/Result.HalfW,
    Abs(Result.Direction.Y)/Result.HalfH);
  Result.Boundary := Result.Direction * RayScale;
  Result.Origin := Result.Boundary * Settings.Position;
  Result.Radius := Hypot(Result.HalfW+Abs(Result.Origin.X),
    Result.HalfH+Abs(Result.Origin.Y));
end;

end.
