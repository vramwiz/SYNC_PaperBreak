unit PaperBreak_Fragments;

// 紙片の不規則な分割、燃焼・浸透の進行範囲と湿った紙面の変形。

interface

uses PaperBreak_Types, PaperBreak_Mesh;

type
  TPaperFragments = class
  private type
    TCell = record
      Center: TVec2;
      Outline: TPaperPolygon;
    end;
  private
    FCells: TArray<TCell>;
    FHalfW, FHalfH: Single;
    FSeed: Integer;
    FStyle: TPaperStyle;
    procedure UpdateCells(const Frame: TPaperFrame);
    procedure EmitCell(Mesh: TPaperMesh; const Frame: TPaperFrame; Index: Integer;
      Age: Single; Material: Integer);
  public
    procedure Draw(Mesh: TPaperMesh; const Frame: TPaperFrame);
  end;

function DamageFront(const Frame: TPaperFrame): Single;

implementation

uses System.Math;

function DamageFront(const Frame: TPaperFrame): Single;
begin
  if Frame.Settings.Style=psSoak then
    Result := 1.10*Power(Limit((Frame.Progress-0.016)/0.972),1.38)
  else
    Result := 1.07*Power(Limit((Frame.Progress-0.012)/0.974),1.25);
end;

procedure TPaperFragments.UpdateCells(const Frame: TPaperFrame);
var
  Cols,Rows,X,Y,I,J,K,N,NewCount: Integer;
  Base: Integer;
  Cells: TArray<TCell>;
  Points,A,B: array of TVec2;
  D,M,P,Q,Center: TVec2;
  PrevDist,Dist: Single;
begin
  if (Length(FCells)>0) and (FHalfW=Frame.HalfW) and (FHalfH=Frame.HalfH) and
    (FSeed=Frame.Settings.Seed) and (FStyle=Frame.Settings.Style) then Exit;

  case Frame.Settings.Style of
    psShred: Base := 8;
    psWeather: Base := 13;
  else
    Base := 16;
  end;
  Cols := EnsureRange(Round(Base*Sqrt(Frame.HalfW/Frame.HalfH)),3,36);
  Rows := EnsureRange(Round(Base*Sqrt(Frame.HalfH/Frame.HalfW)),3,36);
  SetLength(Cells,Cols*Rows);
  SetLength(Points,Length(Cells));
  SetLength(A,Length(Points)+4);
  SetLength(B,Length(A));
  for Y := 0 to Rows-1 do
    for X := 0 to Cols-1 do
    begin
      I := Y*Cols+X;
      Points[I] := V2(
        (2*(X+0.12+0.76*Noise(2*I+17,Frame.Settings.Seed))/Cols-1)*Frame.HalfW,
        (2*(Y+0.12+0.76*Noise(2*I+39,Frame.Settings.Seed))/Rows-1)*Frame.HalfH);
    end;
  for I := 0 to High(Points) do
  begin
    // 近接点との等距離線で長方形を切り詰め、端まで隙間なく分割する。
    A[0] := V2(-Frame.HalfW,-Frame.HalfH);
    A[1] := V2(Frame.HalfW,-Frame.HalfH);
    A[2] := V2(Frame.HalfW,Frame.HalfH);
    A[3] := V2(-Frame.HalfW,Frame.HalfH);
    N := 4;
    for J := 0 to High(Points) do
    begin
      if (I=J) or (N=0) then Continue;
      D := Points[J]-Points[I];
      M := (Points[J]+Points[I])*0.5;
      P := A[N-1];
      PrevDist := Dot(D,P-M);
      NewCount := 0;
      for K := 0 to N-1 do
      begin
        Q := A[K];
        Dist := Dot(D,Q-M);
        if (PrevDist>0) <> (Dist>0) then
        begin
          B[NewCount] := P+(Q-P)*(PrevDist/(PrevDist-Dist));
          Inc(NewCount);
        end;
        if Dist<=0 then
        begin
          B[NewCount] := Q;
          Inc(NewCount);
        end;
        P := Q;
        PrevDist := Dist;
      end;
      N := NewCount;
      if N>0 then Move(B[0],A[0],N*SizeOf(TVec2));
    end;
    SetLength(Cells[I].Outline,N);
    if N=0 then Continue;
    Center := V2(0,0);
    for K := 0 to N-1 do
    begin
      Cells[I].Outline[K] := A[K];
      Center := Center+A[K];
    end;
    Cells[I].Center := Center*(1/N);
  end;
  FCells := Cells;
  FHalfW := Frame.HalfW;
  FHalfH := Frame.HalfH;
  FSeed := Frame.Settings.Seed;
  FStyle := Frame.Settings.Style;
end;

procedure TPaperFragments.EmitCell(Mesh: TPaperMesh; const Frame: TPaperFrame;
  Index: Integer; Age: Single; Material: Integer);
var
  F: TPaperFrame;
  C: TVec2;
  PieceScale, Curl, Ax,Ay,Az, R, Shrink, Phase: Single;
  Drift: TVec3;
begin
  F := Frame;
  C := FCells[Index].Center;
  R := Noise(Index+1161,F.Settings.Seed);
  Phase := 2*Pi*Noise(Index+111,F.Settings.Seed);
  Ax := (2*Noise(Index+347,F.Settings.Seed)-1)*Age*5.1;
  Ay := (2*Noise(Index+653,F.Settings.Seed)-1)*Age*5.4;
  Az := (2*Noise(Index+853,F.Settings.Seed)-1)*Age*3.9;
  Shrink := 1-0.048*Age;
  if Material=MAT_PULP then
    Shrink := (0.22+R*0.21)*(1-0.55*Age);
  PieceScale := (0.18+0.82*F.Settings.Scatter)*(0.35+0.9*R);
  Drift.X := Sqr(Age)*PieceScale*1.75*Cos(Phase);
  Drift.Y := Sqr(Age)*(0.65*PieceScale*Sin(Phase)-
    (2.05+2.0*F.Settings.Gravity)*(0.8+0.45*R));
  Drift.Z := Sqr(Age)*PieceScale*0.43*Sin(Phase);
  Curl := (0.28+F.Settings.Deformation)*(1-0.72*F.Settings.Stiffness);
  Mesh.Fan(FCells[Index].Outline,C,F.Thickness*Min(1,Shrink+0.24),Material,
    function(const P: TVec2): TPaperSample
    var
      D: TVec2;
      Q: TVec3;
      WidthFactor: Single;
    begin
      D := (P-C)*Shrink;
      WidthFactor := 1;
      if Material=MAT_PULP then WidthFactor := 0.20+0.44*R;
      Q := Rotate(V3(D.X*WidthFactor,D.Y,
        Curl*Age*(Sin(Phase)*D.X+Cos(Phase)*D.Y-Dot(D,D)*9)),Ax,Ay,Az);
      Result := PaperSample(V3(C.X,C.Y,0)+Q+Drift,F.ToUV(P));
    end);
end;

procedure TPaperFragments.Draw(Mesh: TPaperMesh; const Frame: TPaperFrame);
var
  F: TPaperFrame;
  I: Integer;
  Front, Distance, Birth, Age, Variation, Heat, Wave, D: Single;
  Cell: TCell;
begin
  F := Frame;
  if F.Settings.Style=psBurn then
  begin
    // 燃焼境界はUV上で進める。紙面は元画像の位置と寸法に合わせて固定する。
    Mesh.Grid(1,1,F.Thickness,MAT_PAPER,MAT_EDGE,
      function(U,V: Single): TPaperSample
      begin
        Result := PaperSample(V3((2*U-1)*F.HalfW,(2*V-1)*F.HalfH,0),V2(U,1-V));
      end);
    Exit;
  end;
  UpdateCells(F);
  if F.Settings.Style=psSoak then
  begin
    Front := DamageFront(F);
    Heat := (0.30+F.Settings.Deformation)*(1-0.72*F.Settings.Stiffness);
    Wave := 2*Pi*Noise(87,F.Settings.Seed);
    Mesh.Grid(48,42,F.Thickness,MAT_PAPER,MAT_EDGE,
      function(U,V: Single): TPaperSample
      var
        P,Q,Delta: TVec2;
        DistanceToFront, Warp, Z: Single;
      begin
        P := V2((2*U-1)*F.HalfW,(2*V-1)*F.HalfH);
        Delta := P-F.Origin;
        DistanceToFront := Hypot(Delta.X,Delta.Y)/F.Radius-Front;
        Warp := Ease(-0.25,0.13,-DistanceToFront)*Ease(0,0.22,F.Progress)*Heat;
        Q := P+Delta*(Warp*0.075);
        Z := F.ShortSide*Warp*(0.18*Sin(U*18+V*21+Wave)+
          0.075*Sin(U*39-V*27) - 0.10);
        Result := PaperSample(V3(Q.X,Q.Y,Z),V2(U,1-V));
      end);
    for I := 0 to High(FCells) do
    begin
      Cell := FCells[I];
      if Length(Cell.Outline)<3 then Continue;
      Variation := Noise(I+62,F.Settings.Seed);
      if Variation > 0.40+0.48*F.Settings.Scatter then Continue;
      Distance := Hypot(Cell.Center.X-F.Origin.X,Cell.Center.Y-F.Origin.Y)/F.Radius;
      Birth := Distance+0.022+0.057*Variation;
      D := Front-Birth;
      if (D<=0) or (D>=0.38) then Continue;
      Age := Ease(0,0.39,D);
      EmitCell(Mesh,F,I,Age,MAT_PULP);
    end;
    Exit;
  end;

  for I := 0 to High(FCells) do
  begin
    Cell := FCells[I];
    if Length(Cell.Outline)<3 then Continue;
    Distance := Hypot(Cell.Center.X-F.Origin.X,Cell.Center.Y-F.Origin.Y)/F.Radius;
    Variation := Noise(I+62,F.Settings.Seed);
    if F.Settings.Style=psShred then
      Birth := Min(0.83,0.13+0.59*Distance+0.29*Variation)
    else
      Birth := Min(0.85,0.26+0.40*Distance+0.28*Variation);
    Age := Ease(Birth,Min(0.993,Birth+0.33),F.Progress);
    EmitCell(Mesh,F,I,Age,MAT_PAPER);
  end;
end;

end.
