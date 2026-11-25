unit PaperBreak_Scissors;

// ハサミの刃、樹脂の指環、支点を深度付きの立体として生成する。

interface

uses PaperBreak_Types, PaperBreak_Mesh;

procedure DrawScissors(Mesh: TPaperMesh; const BitePoint, Direction: TVec2;
  Scale, Opening: Single);

implementation

uses System.Math;

function ToolPoint(const Pivot: TVec2; Scale,X,Y,Z,Angle: Single): TVec3;
var
  S,C: Single;
begin
  SinCos(Angle,S,C);
  Result := V3(Pivot.X+Scale*(C*X-S*Y),Pivot.Y+Scale*(S*X+C*Y),Scale*Z);
end;

procedure DrawScissors(Mesh: TPaperMesh; const BitePoint, Direction: TVec2;
  Scale, Opening: Single);
var
  Pivot: TVec2;
  Facing: Single;
  Side: Integer;

  procedure Blade(Angle, Z, Hand: Single);
  begin
    Mesh.Grid(14,5,Scale*0.034,MAT_STEEL,MAT_STEEL,
      function(U,V: Single): TPaperSample
      var
        X,Y, Width, Bevel: Single;
      begin
        X := -0.19+0.95*U;
        Width := (0.12+0.064*Sin(Pi*U))*(1-0.97*Power(U,2.9));
        Y := Width*(V-0.25*Hand-0.5);
        Bevel := 0.022*Ease(0.04,0.45,1-Abs(2*V-1));
        Result := PaperSample(ToolPoint(Pivot,Scale,X,Y,Z+Bevel,Angle),V2(U,V));
      end);
  end;

  procedure Ring(Angle,Z,Hand: Single);
  begin
    Mesh.Grid(36,12,0,MAT_GRIP,MAT_GRIP,
      function(U,V: Single): TPaperSample
      var
        A,B,C,D, Width: Single;
      begin
        SinCos(2*Pi*U,A,B);
        SinCos(2*Pi*V,C,D);
        Width := 0.052*D;
        Result := PaperSample(ToolPoint(Pivot,Scale,-0.46+(0.24+Width)*B,
          -Hand*0.084+(0.125+Width)*A,Z+0.048*C,Angle),V2(U,V));
      end);
    Mesh.Grid(5,3,Scale*0.041,MAT_GRIP,MAT_GRIP,
      function(U,V: Single): TPaperSample
      begin
        Result := PaperSample(ToolPoint(Pivot,Scale,-0.28+0.18*U,
          (V-0.5)*0.11-Hand*0.068*(1-U),Z+0.038,Angle),V2(U,V));
      end);
  end;

var
  Angle, Depth, Hand: Single;
begin
  Facing := ArcTan2(Direction.Y,Direction.X);
  Pivot := BitePoint-Direction*(0.76*Scale*Cos(Opening));
  for Side := 0 to 1 do
  begin
    Hand := 2*Side-1;
    Angle := Facing+Hand*Opening;
    Depth := -0.044+Side*0.164;
    Ring(Angle,Depth,Hand);
    Blade(Angle,Depth,Hand);
  end;
  Mesh.Grid(28,3,Scale*0.012,MAT_PIN,MAT_STEEL,
    function(U,V: Single): TPaperSample
    var
      S,C: Single;
    begin
      SinCos(-U*2*Pi,S,C);
      Result := PaperSample(ToolPoint(Pivot,Scale,V*0.066*C,V*0.066*S,
        0.183+0.012*(1-V),Facing),V2(0.5+V*C*0.5,0.5+V*S*0.5));
    end);
end;

end.
