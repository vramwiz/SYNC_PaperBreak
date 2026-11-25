unit PaperBreak_Sheets;

// 連続した紙の引き裂き、切断、折りたたみ、握りつぶし。

interface

uses PaperBreak_Types, PaperBreak_Mesh;

procedure DrawTornSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);
procedure DrawFoldedSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);
procedure DrawCrumpledSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);

implementation

uses System.Math, System.Generics.Collections, PaperBreak_Scissors;

type
  TSplit = record
    AcrossX: Boolean;
    Anchor, Start, Time, Bend, Travel: Single;
    Key: Integer;
  end;

  TTearPath = array[0..2] of TSplit;
  TSides = array[0..2] of Integer;

function GetRun(const Split: TSplit; const UV: TVec2): Single; inline;
begin
  if Split.AcrossX then Result := UV.Y else Result := UV.X;
end;

function SeamAt(const Split: TSplit; Run: Single; SmoothCut: Boolean): Single;
var
  Distance, Variation: Single;
begin
  Distance := Abs(Run-Split.Start);
  Result := Split.Anchor+(EnsureRange(Split.Anchor,0.24,0.76)-Split.Anchor) *
    Ease(0,0.7,Distance);
  if SmoothCut then Exit;
  Variation := 0.052*Sin(Run*11.3+Split.Key) +
    0.021*Sin(Run*36.5-Split.Key*1.31) +
    0.012*Sin(Run*97.0+Split.Key*0.49) +
    0.005*Sin(Run*221.0-Split.Key);
  Result := Limit(Result + Variation*Ease(0,0.14,Distance));
end;

function InParent(const Split: TSplit; const P: TVec2; Side: Integer;
  SmoothCut: Boolean): TVec2;
var
  Seam, Across: Single;
begin
  Seam := SeamAt(Split,GetRun(Split,P),SmoothCut);
  if Split.AcrossX then Across := P.X else Across := P.Y;
  if Side=0 then Across := Across*Seam
  else Across := Seam+Across*(1-Seam);
  Result := P;
  if Split.AcrossX then Result.X := Across else Result.Y := Across;
end;

function ToPaper(const F: TPaperFrame; const P: TVec2): TVec2;
begin
  Result := V2((2*P.X-1)*F.HalfW,(2*P.Y-1)*F.HalfH);
end;

function NormalizePaper(const F: TPaperFrame; const P: TVec2): TVec2;
begin
  Result := V2(0.5+0.5*P.X/F.HalfW,0.5+0.5*P.Y/F.HalfH);
end;

procedure DrawTornSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);
var
  F: TPaperFrame;
  Path: TTearPath;
  Sides: TSides;
  AtStart, AtEnd: TVec2;
  Cutting: Boolean;
  Bite, Opening, ToolRun: Single;
  DepthCount: Integer;

  procedure EmitLeaf(Count: Integer);
  var
    LocalPath: TTearPath;
    LocalSides: TSides;
    GridAcross, GridRun, Level, J: Integer;
    LocalUV: TVec2;
    Pivot: array[0..2] of TVec2;
  begin
    LocalPath := Path;
    LocalSides := Sides;
    for Level := 0 to Count-1 do
    begin
      LocalUV := V2(0.5,0.5);
      for J := Level downto 0 do
        LocalUV := InParent(LocalPath[J],LocalUV,LocalSides[J],Cutting);
      Pivot[Level] := ToPaper(F,LocalUV);
    end;
    GridAcross := 20;
    GridRun := 22;
    if Count=1 then
    begin
      if LocalPath[0].AcrossX then GridRun := 88
      else GridAcross := 88;
    end;
    Mesh.Grid(GridAcross,GridRun,F.Thickness,MAT_PAPER,MAT_EDGE,
      function(U,V: Single): TPaperSample
      var
        P, XY: TVec2;
        Runs: array[0..2] of Single;
        K: Integer;
        Split: TSplit;
        Q: TVec3;
        Reach, Side, Open, Release, Drop, Curl, Pull, Stretch, Delta,
          Scale, Crack, Recoil: Single;
      begin
        P := V2(U,V);
        for K := Count-1 downto 0 do
        begin
          Runs[K] := GetRun(LocalPath[K],P);
          P := InParent(LocalPath[K],P,LocalSides[K],Cutting);
        end;
        XY := ToPaper(F,P);
        Q := V3(XY.X,XY.Y,0);

        for K := Count-1 downto 0 do
        begin
          Split := LocalPath[K];
          Side := 2*LocalSides[K]-1;
          Scale := F.ShortSide / (1+K*0.8);
          Reach := Abs(Runs[K]-Split.Start)/Max(Split.Start,1-Split.Start);
          if Cutting then
          begin
            Open := Ease(0,0.12,Bite-Reach);
            Release := Ease(0.715,1,F.Progress);
            Crack := Bite;
          end
          else
          begin
            Open := Ease(0.13+0.39*Reach,0.33+0.39*Reach,Split.Time);
            Release := Power(Limit((Split.Time-0.48)/0.52),1.50);
            Crack := Limit((Split.Time-0.13)/0.39);
          end;
          Curl := Open*Split.Bend * (0.15*Sin(Runs[K]*13+Split.Key) +
            0.20*Sin(Runs[K]*4+Split.Key));
          Stretch := Ease(0,0.22,Split.Time) * (1-Ease(0.42,0.68,Split.Time));
          Delta := Reach-Crack;
          Pull := Stretch * Exp(-6*Sqr(Delta)) * Split.Bend * Scale*0.09;
          Drop := Sqr(Release)*Split.Travel*F.HalfH*(0.43+0.73*F.Settings.Gravity);
          Recoil := Sin(3*Pi*Release)*Sqr(1-Release)*0.21;
          Q.Z := Q.Z + Pull + (Curl+Recoil)*Scale;
          if Split.AcrossX then
          begin
            Q := Rotate(Q-V3(Pivot[K].X,Pivot[K].Y,0),
              Release*0.68, Side*(Release*1.34+Recoil), Side*Release*0.36) +
              V3(Pivot[K].X,Pivot[K].Y,0);
            Q.X := Q.X + Side*(Scale*Open*0.057+Sqr(Release)*Split.Travel*F.HalfW);
          end
          else
          begin
            Q := Rotate(Q-V3(Pivot[K].X,Pivot[K].Y,0),
              Side*(Release*1.34+Recoil), Release*0.68, -Side*Release*0.36) +
              V3(Pivot[K].X,Pivot[K].Y,0);
            Q.Y := Q.Y + Side*(Scale*Open*0.057+Sqr(Release)*Split.Travel*F.HalfH*0.48);
            Q.X := Q.X + Side*Sqr(Release)*Split.Travel*F.HalfW;
          end;
          Q.Y := Q.Y - Drop;
        end;
        Result := PaperSample(Q,F.ToUV(XY));
      end);
  end;

  procedure EmitBranches(Level, Key: Integer);
  var
    Side: Integer;
  begin
    if Level=DepthCount then
    begin
      EmitLeaf(Level);
      Exit;
    end;
    Path[Level].AcrossX := not Path[Level-1].AcrossX;
    Path[Level].Anchor := 0.33+0.34*Noise(Key,F.Settings.Seed);
    Path[Level].Start := Ord(Odd(Key));
    Path[Level].Time := Limit((F.Progress-(Level*0.16+Noise(Key+16,F.Settings.Seed)*0.044))/
      (0.65-Level*0.095));
    Path[Level].Bend := Path[0].Bend;
    Path[Level].Travel := Path[0].Travel / (3+Level);
    Path[Level].Key := Key+Floor(Noise(Key+3,F.Settings.Seed)*121);
    if Path[Level].Time <= 0.13 then
    begin
      EmitLeaf(Level);
      Exit;
    end;
    for Side := 0 to 1 do
    begin
      Sides[Level] := Side;
      EmitBranches(Level+1,Key*2+Side);
    end;
  end;

var
  Start: TVec2;
  ToolT, Cycle, Complete, Scale, EnterDistance, EndDistance, RootRelease: Single;
  Side: Integer;
begin
  F := Frame;
  Cutting := F.Settings.Style=psScissors;
  if Cutting then Start := NormalizePaper(F,F.Boundary)
  else Start := NormalizePaper(F,F.Origin);
  Path[0].AcrossX := Abs(F.Boundary.Y/F.HalfH) >= Abs(F.Boundary.X/F.HalfW);
  Path[0].Start := GetRun(Path[0],Start);
  if Path[0].AcrossX then Path[0].Anchor := Start.X else Path[0].Anchor := Start.Y;
  Path[0].Key := Floor(Noise(91,F.Settings.Seed)*233);
  Path[0].Bend := (0.25+0.75*F.Settings.Deformation)*(1-0.65*F.Settings.Stiffness);
  Path[0].Travel := 1.46+0.85*F.Settings.Scatter;
  Path[0].Time := F.Progress;
  DepthCount := 1;
  if F.Settings.Style=psRepeatedTear then
  begin
    DepthCount := 3;
    // 分割が進行してから、親となる紙片を大きく移動させる。
    Path[0].Time := Limit(F.Progress*0.75+0.25*Ease(0.63,1,F.Progress));
  end;

  // 開く間は切断点を保ち、閉じる間だけ次の区間を切る。
  Bite := 0;
  Opening := 0;
  ToolRun := 0;
  if Cutting then
  begin
    ToolT := 9*Limit((F.Progress-0.135)/0.59);
    Complete := Floor(ToolT);
    Cycle := ToolT-Complete;
    Bite := (Complete+Ease(0.45,1,Cycle))/9;
    Opening := 0.53*Sin(Pi*Cycle);
    ToolRun := Path[0].Start+(1-2*Path[0].Start)*Bite;
  end;
  for Side := 0 to 1 do
  begin
    Sides[0] := Side;
    EmitBranches(1,2+Side);
  end;
  if not Cutting then Exit;

  if Path[0].AcrossX then
  begin
    AtStart := ToPaper(F,V2(SeamAt(Path[0],ToolRun,True),ToolRun));
    AtEnd := V2(0,1-2*Path[0].Start);
  end
  else
  begin
    AtStart := ToPaper(F,V2(ToolRun,SeamAt(Path[0],ToolRun,True)));
    AtEnd := V2(1-2*Path[0].Start,0);
  end;
  Scale := F.ShortSide*0.55;
  EnterDistance := 0.34*Scale*(1-Ease(0,0.135,F.Progress));
  RootRelease := Ease(0.73,1,F.Progress);
  EndDistance := 1.8*Scale*RootRelease;
  DrawScissors(Mesh,AtStart+AtEnd*(EndDistance-EnterDistance),AtEnd,Scale,Opening);
end;

type
  TFoldHinge = record
    AlongX: Boolean;
    Angle, StartLine, Direction, Radius: Single;
  end;

procedure BendPaper(const Hinge: TFoldHinge; var Point, Normal: TVec3);
var
  Axis, D, BendEnd, Angle, S,C, Flat, Layer, NormalD, NormalZ: Single;
begin
  if Hinge.Angle<=0 then Exit;
  if Hinge.AlongX then Axis := Point.X else Axis := Point.Y;
  D := (Axis-Hinge.StartLine)*Hinge.Direction;
  if D<=0 then Exit;
  BendEnd := Hinge.Radius*Hinge.Angle;
  Flat := Max(0,D-BendEnd);
  Angle := Min(D/Hinge.Radius,Hinge.Angle);
  SinCos(Angle,S,C);

  // 各紙層は同じ軸を異なる半径で回る。軸は既存の最上層より手前に置く。
  Layer := Hinge.Radius-Point.Z;
  Axis := Hinge.StartLine+Hinge.Direction*(Layer*S+Flat*C);
  Point.Z := Hinge.Radius-Layer*C+Flat*S;
  if Hinge.AlongX then NormalD := Normal.X else NormalD := Normal.Y;
  NormalD := NormalD*Hinge.Direction;
  if D<BendEnd then NormalD := NormalD*Hinge.Radius/Layer;
  NormalZ := NormalD*S+Normal.Z*C;
  NormalD := NormalD*C-Normal.Z*S;
  if Hinge.AlongX then Point.X := Axis else Point.Y := Axis;
  if Hinge.AlongX then Normal.X := NormalD*Hinge.Direction
  else Normal.Y := NormalD*Hinge.Direction;
  Normal.Z := NormalZ;
end;

procedure AddCreaseStops(Stops: TList<Single>; StartLine, Span, HalfExtent: Single;
  const Fold: TFoldHinge);
var
  I, Sections: Integer;
  Sample: Single;
begin
  Sections := Ceil(Fold.Angle*24/Pi);
  if Sections<=0 then Exit;
  for I := 0 to Sections do
  begin
    Sample := StartLine+I/Sections*Span;
    if (Sample>-HalfExtent) and (Sample<HalfExtent) then Stops.Add(Sample);
  end;
end;

function SortedStops(List: TList<Single>): TArray<Single>;
var
  I,Count: Integer;
begin
  List.Sort;
  SetLength(Result,List.Count);
  Count := 0;
  for I := 0 to List.Count-1 do
    if (Count=0) or (List[I]>Result[Count-1]) then
    begin
      Result[Count] := List[I];
      Inc(Count);
    end;
  SetLength(Result,Count);
end;

procedure DrawFoldedSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);
var
  F: TPaperFrame;
  First, Second, Third: TFoldHinge;
  Clearance, Drop, FoldedRight: Single;
  XList,YList: TList<Single>;
  XStops,YStops: TArray<Single>;
begin
  F := Frame;
  Clearance := Max(0.000002,
    Max(F.Thickness*0.16,F.ShortSide*(0.0009+0.0012*F.Settings.Stiffness)));
  Drop := Ease(0.75,1,F.Progress);

  First.AlongX := True;
  First.Direction := 1;
  First.Angle := Pi*Ease(0.015,0.30,F.Progress);
  First.Radius := Clearance;
  First.StartLine := -Pi*First.Radius/2;
  Second.AlongX := False;
  Second.Direction := -1;
  Second.Angle := Pi*Ease(0.30,0.54,F.Progress);
  Second.Radius := 2*First.Radius+F.Thickness+Clearance;
  Second.StartLine := Pi*Second.Radius/2;
  Third.AlongX := True;
  Third.Direction := -1;
  Third.Angle := Pi*Ease(0.54,0.74,F.Progress);
  Third.Radius := 2*Second.Radius+F.Thickness+Clearance;
  FoldedRight := First.StartLine+First.Radius+F.Thickness;
  Third.StartLine := (FoldedRight-F.HalfW)/2+Pi*Third.Radius/2;

  XList := TList<Single>.Create;
  try
    XList.Add(-F.HalfW);
    XList.Add(F.HalfW);
    AddCreaseStops(XList,First.StartLine,First.Angle*First.Radius,F.HalfW,First);
    // 先に折った右側の紙では、第3折り目の元のX座標が左右反転する。
    AddCreaseStops(XList,Third.StartLine,-Third.Angle*Third.Radius,F.HalfW,Third);
    AddCreaseStops(XList,-Third.StartLine,Third.Angle*Third.Radius,F.HalfW,Third);
    XStops := SortedStops(XList);
  finally
    XList.Free;
  end;
  YList := TList<Single>.Create;
  try
    YList.Add(-F.HalfH);
    YList.Add(F.HalfH);
    AddCreaseStops(YList,Second.StartLine,-Second.Angle*Second.Radius,F.HalfH,Second);
    YStops := SortedStops(YList);
  finally
    YList.Free;
  end;

  Mesh.LayerGrid(XStops,YStops,F.Thickness,
    procedure(X,Y,Depth: Single; out Position, Normal: TVec3)
    begin
      Position := V3(X,Y,Depth);
      Normal := V3(0,0,1);
      BendPaper(First,Position,Normal);
      BendPaper(Second,Position,Normal);
      BendPaper(Third,Position,Normal);
      Position := Rotate(Position+V3(F.HalfW*0.27,-F.HalfH*0.26,0),
        Drop*0.98,Drop*0.96,-Drop*0.4);
      Position.X := Position.X-F.HalfW*0.27+Drop*F.Settings.Scatter*0.6;
      Position.Y := Position.Y+F.HalfH*0.26-Sqr(Drop)*(1.7+1.7*F.Settings.Gravity);
      Normal := UnitVector(Rotate(Normal,Drop*0.98,Drop*0.96,-Drop*0.4));
    end);
end;

procedure DrawCrumpledSheet(Mesh: TPaperMesh; const Frame: TPaperFrame);
var
  F: TPaperFrame;
  Compression, Drop, Drift, SeedPhase: Single;
begin
  F := Frame;
  Compression := Ease(0.025,0.74,F.Progress);
  Drop := Ease(0.70,1,F.Progress);
  Drift := F.HalfW*(0.22+0.95*F.Settings.Scatter);
  SeedPhase := Noise(192,F.Settings.Seed)*2*Pi;
  Mesh.Grid(56,56,F.Thickness,MAT_PAPER,MAT_EDGE,
    function(U,V: Single): TPaperSample
    var
      X,Y,Z, NX,NY, Radius, Theta, Wrinkle, Pleat, Pull, Bulge, Softness,
        Arc, Ball, Rim: Single;
      Q: TVec3;
    begin
      NX := 2*U-1;
      NY := 2*V-1;
      Radius := Hypot(NX,NY);
      Theta := ArcTan2(NY,NX);
      Softness := (0.55+0.84*F.Settings.Deformation)*(1-0.51*F.Settings.Stiffness);
      Pull := 1-Compression;
      Arc := Radius*(2.02+0.17*Cos(Theta*3+SeedPhase));
      Ball := F.ShortSide*0.26*Compression;
      Rim := Ball*Sin(Arc)/Max(Radius,0.05);
      Pleat := Sin(Theta*5+Radius*11+SeedPhase+Sin(Theta*3)) +
        0.30*Sin(Theta*9-Radius*13-SeedPhase);
      Pleat := Pleat*Ease(0,0.55,Radius);
      Wrinkle := Sin(NX*15-NY*12+Sin(NY*9)) *
        Sin(NY*12+NX*8+SeedPhase) + 0.24*Sin(NX*34+NY*29+SeedPhase);
      Bulge := F.ShortSide*Compression*Softness;
      X := NX*(F.HalfW*Pull+Rim)+Bulge*(0.099*Pleat*NX+0.064*Wrinkle);
      Y := NY*(F.HalfH*Pull+Rim)+Bulge*(0.092*Pleat*NY+0.055*Wrinkle);
      Z := Ball*Cos(Arc)+Bulge*(0.132*Wrinkle+0.100*Pleat);
      Q := Rotate(V3(X,Y,Z),1.87*Drop,1.27*Drop,
        0.3*Compression+Drop*1.15);
      Q.X := Q.X+Drop*Drift;
      Q.Y := Q.Y-Sqr(Drop)*F.HalfH*(1.92+F.Settings.Gravity*1.02);
      Result := PaperSample(Q,V2(U,1-V));
    end);
end;

end.
