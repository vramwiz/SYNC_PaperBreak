unit PaperBreak_Parameters;

// AviUtl2の標準セレクターとトラックを登録し、描画ごとに現在値を読み取る。

interface

uses PaperBreak_Types;

procedure RegisterPaperParameters;
function ReadPaperSettings: TPaperSettings;

implementation

uses System.Math, AviUtl2FilterTypes, PluginFilterTable;

var
  Style: TFILTER_ITEM_SELECT;
  Duration, Angle, Position, Thickness, Stiffness, Deformation, Gravity,
    Scatter, Seed: TFILTER_ITEM_TRACK;

const
  Styles: array[0..9] of TFILTER_ITEM_SELECT_ITEM = (
    (Name: '二つに引き裂く'; Value: Ord(psTear)),
    (Name: '繰り返し引き裂く'; Value: Ord(psRepeatedTear)),
    (Name: '細かくちぎる'; Value: Ord(psShred)),
    (Name: '握りつぶす'; Value: Ord(psCrumple)),
    (Name: '折りたたむ'; Value: Ord(psFold)),
    (Name: 'ハサミで切る'; Value: Ord(psScissors)),
    (Name: '燃焼'; Value: Ord(psBurn)),
    (Name: '水濡れ・崩壊'; Value: Ord(psSoak)),
    (Name: '風化・崩壊'; Value: Ord(psWeather)),
    (Name: nil; Value: 0));

procedure RegisterPaperParameters;
begin
  AddSelect(Style, 'スタイル', Ord(psTear), @Styles[0]);
  AddTrack(Duration, '消失時間', 3, 0.01, 100, 0.01);
  AddTrack(Angle, '開始角度', 270, 0, 360, 0.01);
  AddTrack(Position, '開始位置', 100, 0, 100, 0.01);
  AddTrack(Thickness, '紙の厚さ', 10, 0, 100, 0.01);
  AddTrack(Stiffness, '紙の硬さ', 50, 0, 100, 0.01);
  AddTrack(Deformation, '変形強度', 50, 0, 100, 0.01);
  AddTrack(Gravity, '重力', 50, 0, 100, 0.01);
  AddTrack(Scatter, '飛散強度', 30, 0, 100, 0.01);
  AddTrack(Seed, 'ランダムシード', 0, Low(Integer), High(Integer), 1);
end;

function TrackValue(const Track: TFILTER_ITEM_TRACK; DefaultValue: Double): Double;
begin
  if IsNan(Track.Value) then Result := DefaultValue
  else Result := EnsureRange(Track.Value, Track.S, Track.E);
end;

function ReadPaperSettings: TPaperSettings;
begin
  Result.Style := TPaperStyle(EnsureRange(Style.Value, Ord(Low(TPaperStyle)),
    Ord(High(TPaperStyle))));
  Result.Duration := TrackValue(Duration,3);
  Result.Angle := TrackValue(Angle,270);
  Result.Position := TrackValue(Position,100)*0.01;
  Result.Thickness := TrackValue(Thickness,10)*0.01;
  Result.Stiffness := TrackValue(Stiffness,50)*0.01;
  Result.Deformation := TrackValue(Deformation,50)*0.01;
  Result.Gravity := TrackValue(Gravity,50)*0.01;
  Result.Scatter := TrackValue(Scatter,30)*0.01;
  Result.Seed := Round(TrackValue(Seed,0));
end;

end.
