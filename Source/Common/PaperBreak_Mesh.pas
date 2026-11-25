unit PaperBreak_Mesh;

// 三角形バッファと、表裏・厚みのある紙面を組み立てる。

interface

uses PaperBreak_Types;

type
  TPaperSample = record
    Position: TVec3;
    UV: TVec2;
    Edge: Single;
  end;

  TPaperSurface = reference to function(U,V: Single): TPaperSample;
  TPaperLayerSurface = reference to procedure(X,Y,Depth: Single;
    out Position, Normal: TVec3);
  TPaperPolygon = array of TVec2;
  TPaperPolygonSurface = reference to function(const P: TVec2): TPaperSample;

  TPaperMesh = class
  private type
    TNode = record
      Front, Back: TPaperVertex;
    end;
  private
    FVertices: array of TPaperVertex;
    FGrid: array of TNode;
    FCount: Integer;
    procedure SetNode(var Node: TNode; const Sample: TPaperSample;
      const Normal: TVec3; Thickness, Material: Single);
    procedure AddShell(const A,B,C: TNode; Thick: Boolean);
    procedure AddWall(const A,B: TNode; Material: Single);
    procedure EmitGrid(Columns, Rows: Integer; Thick: Boolean; WallMaterial: Single);
  public
    procedure Reset;
    function Data: PPaperVertex;
    property Count: Integer read FCount;
    procedure Triangle(const A,B,C: TPaperVertex);
    procedure Grid(Columns, Rows: Integer; Thickness, Material,
      WallMaterial: Single; const Surface: TPaperSurface);
    // 折り目では表と裏を個別に変形させ、紙の厚みを保つ。
    procedure LayerGrid(const XStops,YStops: TArray<Single>; Thickness: Single;
      const Surface: TPaperLayerSurface);
    procedure Fan(const Polygon: TPaperPolygon; const Center: TVec2;
      Thickness, Material: Single; const Surface: TPaperPolygonSurface);
  end;

function PaperSample(const Position: TVec3; const UV: TVec2): TPaperSample;

implementation

uses System.Math;

const
  MATERIAL_BACK = 7;

function PaperSample(const Position: TVec3; const UV: TVec2): TPaperSample;
begin
  Result.Position := Position;
  Result.UV := UV;
  Result.Edge := 1;
end;

procedure TPaperMesh.Reset;
begin
  FCount := 0;
end;

function TPaperMesh.Data: PPaperVertex;
begin
  Result := nil;
  if FCount > 0 then Result := @FVertices[0];
end;

procedure TPaperMesh.Triangle(const A,B,C: TPaperVertex);
begin
  if FCount+3 > Length(FVertices) then
    SetLength(FVertices, Length(FVertices)*2+3072);
  FVertices[FCount] := A;
  FVertices[FCount+1] := B;
  FVertices[FCount+2] := C;
  Inc(FCount,3);
end;

procedure TPaperMesh.SetNode(var Node: TNode; const Sample: TPaperSample;
  const Normal: TVec3; Thickness, Material: Single);
begin
  Node.Front.Position := Sample.Position;
  Node.Front.Normal := Normal;
  Node.Front.UV := Sample.UV;
  Node.Front.Material := Material;
  Node.Front.Edge := Sample.Edge;
  Node.Back := Node.Front;
  if Thickness <= 0 then Exit;
  Node.Back.Position := Sample.Position - Normal*Thickness;
  Node.Back.Normal := Normal*(-1);
  if Material = MAT_PAPER then Node.Back.Material := MATERIAL_BACK;
end;

procedure TPaperMesh.AddShell(const A,B,C: TNode; Thick: Boolean);
begin
  Triangle(A.Front,B.Front,C.Front);
  if Thick then Triangle(C.Back,B.Back,A.Back);
end;

procedure TPaperMesh.AddWall(const A,B: TNode; Material: Single);
var
  AF,AB,BF,BB: TPaperVertex;
  Normal: TVec3;
begin
  AF := A.Front;
  AB := A.Back;
  BF := B.Front;
  BB := B.Back;
  Normal := UnitVector(Cross(AB.Position-AF.Position, BF.Position-AF.Position));
  AF.Normal := Normal;
  AB.Normal := Normal;
  BF.Normal := Normal;
  BB.Normal := Normal;
  AF.Material := Material;
  AB.Material := Material;
  BF.Material := Material;
  BB.Material := Material;
  Triangle(AF,AB,BF);
  Triangle(BF,AB,BB);
end;

procedure TPaperMesh.Grid(Columns, Rows: Integer; Thickness, Material,
  WallMaterial: Single; const Surface: TPaperSurface);
var
  X,Y,I,Stride: Integer;
  Left,Right,Bottom,Top: TVec3;
  S: TPaperSample;
  Normal: TVec3;
begin
  Stride := Columns+1;
  if Length(FGrid) < Stride*(Rows+1) then SetLength(FGrid,Stride*(Rows+1));
  for Y := 0 to Rows do
    for X := 0 to Columns do
    begin
      S := Surface(X/Columns,Y/Rows);
      I := Y*Stride+X;
      FGrid[I].Front.Position := S.Position;
      FGrid[I].Front.UV := S.UV;
      FGrid[I].Front.Edge := S.Edge;
    end;
  for Y := 0 to Rows do
    for X := 0 to Columns do
    begin
      I := Y*Stride+X;
      S.Position := FGrid[I].Front.Position;
      S.UV := FGrid[I].Front.UV;
      S.Edge := FGrid[I].Front.Edge;
      Left := FGrid[Y*Stride+Max(X-1,0)].Front.Position;
      Right := FGrid[Y*Stride+Min(X+1,Columns)].Front.Position;
      Bottom := FGrid[Max(Y-1,0)*Stride+X].Front.Position;
      Top := FGrid[Min(Y+1,Rows)*Stride+X].Front.Position;
      Normal := UnitVector(Cross(Right-Left,Top-Bottom));
      SetNode(FGrid[I],S,Normal,Thickness,Material);
    end;
  EmitGrid(Columns,Rows,Thickness>0,WallMaterial);
end;

procedure TPaperMesh.LayerGrid(const XStops,YStops: TArray<Single>; Thickness: Single;
  const Surface: TPaperLayerSurface);
var
  I,J,Index: Integer;
  X,Y,MinX,MaxY,Width,Height: Single;
  Sample: TPaperSample;
  Position,Normal: TVec3;
begin
  if Length(FGrid)<Length(XStops)*Length(YStops) then
    SetLength(FGrid,Length(XStops)*Length(YStops));
  MinX := XStops[0];
  MaxY := YStops[High(YStops)];
  Width := XStops[High(XStops)]-MinX;
  Height := MaxY-YStops[0];
  Index := 0;
  for J := 0 to High(YStops) do
    for I := 0 to High(XStops) do
    begin
      X := XStops[I];
      Y := YStops[J];
      Surface(X,Y,0,Position,Normal);
      Sample := PaperSample(Position,V2((X-MinX)/Width,(MaxY-Y)/Height));
      SetNode(FGrid[Index],Sample,Normal,Thickness,MAT_PAPER);
      if Thickness>0 then
      begin
        Surface(X,Y,-Thickness,Position,Normal);
        FGrid[Index].Back.Position := Position;
        FGrid[Index].Back.Normal := Normal*(-1);
      end;
      Inc(Index);
    end;
  EmitGrid(High(XStops),High(YStops),Thickness>0,MAT_EDGE);
end;

procedure TPaperMesh.EmitGrid(Columns, Rows: Integer; Thick: Boolean; WallMaterial: Single);
var
  X,Y,I,Stride: Integer;
begin
  Stride := Columns+1;
  for Y := 0 to Rows-1 do
    for X := 0 to Columns-1 do
    begin
      I := Y*Stride+X;
      AddShell(FGrid[I],FGrid[I+1],FGrid[I+Stride],Thick);
      AddShell(FGrid[I+1],FGrid[I+Stride+1],FGrid[I+Stride],Thick);
    end;
  if not Thick then Exit;
  for X := 0 to Columns-1 do
  begin
    AddWall(FGrid[X],FGrid[X+1],WallMaterial);
    I := Rows*Stride+X;
    AddWall(FGrid[I+1],FGrid[I],WallMaterial);
  end;
  for Y := 0 to Rows-1 do
  begin
    I := Y*Stride+Columns;
    AddWall(FGrid[I],FGrid[I+Stride],WallMaterial);
    I := Y*Stride;
    AddWall(FGrid[I+Stride],FGrid[I],WallMaterial);
  end;
end;

procedure TPaperMesh.Fan(const Polygon: TPaperPolygon; const Center: TVec2;
  Thickness, Material: Single; const Surface: TPaperPolygonSurface);
var
  I: Integer;
  C,A,B: TNode;
  Middle,P,Q: TPaperSample;
  Normal: TVec3;
begin
  if Length(Polygon)<3 then Exit;
  Middle := Surface(Center);
  Middle.Edge := 1;
  P := Surface(Polygon[High(Polygon)]);
  P.Edge := 0;
  for I := 0 to High(Polygon) do
  begin
    Q := Surface(Polygon[I]);
    Q.Edge := 0;
    Normal := UnitVector(Cross(P.Position-Middle.Position,Q.Position-Middle.Position));
    SetNode(C,Middle,Normal,Thickness,Material);
    SetNode(A,P,Normal,Thickness,Material);
    SetNode(B,Q,Normal,Thickness,Material);
    AddShell(C,A,B,Thickness>0);
    if Thickness>0 then AddWall(A,B,MAT_EDGE);
    P := Q;
  end;
end;

end.
