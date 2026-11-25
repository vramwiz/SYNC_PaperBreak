// 固定正面投影と、紙・印刷・破断面・道具の材質。外部シェーダーファイルは不要。
const
  PAPER_SHADER: AnsiString =
    'cbuffer Frame : register(b0)'#10 +
    '{'#10 +
    '  float4 camera;    // x/y projection, lighting weight, timeline progress'#10 +
    '  float4 paper;     // origin xy, paper half dimensions'#10 +
    '  float4 damage;    // max radius, current front, short half dimension, seed phase'#10 +
    '  float4 mode;      // style, shader resource width/height scale, solid paper'#10 +
    '  float4 pixelSize; // reciprocal image width and height'#10 +
    '};'#10 +
    ''#10 +
    'Texture2D image : register(t0);'#10 +
    'SamplerState linearClamp : register(s0);'#10 +
    ''#10 +
    'struct Vertex'#10 +
    '{'#10 +
    '  float3 xyz : POSITION;'#10 +
    '  float3 normal : NORMAL;'#10 +
    '  float2 uv : TEXCOORD0;'#10 +
    '  float2 surface : TEXCOORD1;'#10 +
    '};'#10 +
    ''#10 +
    'struct Pixel'#10 +
    '{'#10 +
    '  float4 clipPos : SV_Position;'#10 +
    '  float3 normal : NORMAL;'#10 +
    '  float2 uv : TEXCOORD0;'#10 +
    '  nointerpolation float kind : TEXCOORD1;'#10 +
    '  float edge : TEXCOORD2;'#10 +
    '};'#10 +
    ''#10 +
    'Pixel VS(Vertex v)'#10 +
    '{'#10 +
    '  Pixel p;'#10 +
    '  p.clipPos = float4(v.xyz.xy * camera.xy, 0.52 - 0.155*v.xyz.z, 1);'#10 +
    '  p.normal = v.normal;'#10 +
    '  p.uv = v.uv;'#10 +
    '  p.kind = v.surface.x;'#10 +
    '  p.edge = v.surface.y;'#10 +
    '  return p;'#10 +
    '}'#10 +
    ''#10 +
    'float hash(float2 p)'#10 +
    '{'#10 +
    '  float3 q = frac(float3(p.xyx) * 0.1031 + damage.w*0.0013);'#10 +
    '  q += dot(q, q.yzx + 33.33);'#10 +
    '  return frac((q.x + q.y) * q.z);'#10 +
    '}'#10 +
    ''#10 +
    'float noise(float2 p)'#10 +
    '{'#10 +
    '  float2 i = floor(p);'#10 +
    '  float2 f = frac(p);'#10 +
    '  f = f*f*(3-2*f);'#10 +
    '  return lerp(lerp(hash(i),hash(i+float2(1,0)),f.x),'#10 +
    '              lerp(hash(i+float2(0,1)),hash(i+1),f.x),f.y);'#10 +
    '}'#10 +
    ''#10 +
    'float4 ink(float2 uv)'#10 +
    '{'#10 +
    '  float2 bounds = pixelSize.xy * 0.5;'#10 +
    '  return image.Sample(linearClamp, clamp(uv,bounds,1-bounds)*mode.yz);'#10 +
    '}'#10 +
    ''#10 +
    'float4 PS(Pixel p, bool front : SV_IsFrontFace) : SV_Target'#10 +
    '{'#10 +
    '  const float kind = p.kind;'#10 +
    '  const bool tool = kind >= 4 && kind <= 6;'#10 +
    '  if (!front && (mode.w > 0 || tool)) discard;'#10 +
    '  const bool backside = kind == 7 || !front;'#10 +
    '  float3 normal = normalize(front ? p.normal : -p.normal);'#10 +
    '  float light = 0.52 + 0.66*saturate(dot(normal, float3(-0.39,0.49,0.78)));'#10 +
    '  float fine = noise(p.uv*float2(380,174))-0.5;'#10 +
    '  float3 color;'#10 +
    '  float alpha = 1;'#10 +
    ''#10 +
    '  if (tool)'#10 +
    '  {'#10 +
    '    if (kind == 4)'#10 +
    '    {'#10 +
    '      float bright = 0.58 + 0.39*smoothstep(0.62,0.99,p.uv.y);'#10 +
    '      float brushed = sin(p.uv.y*260 + 0.1*sin(p.uv.x*13))*0.025;'#10 +
    '      color = float3(0.83,0.87,0.91)*(bright+brushed)*light;'#10 +
    '    }'#10 +
    '    else if (kind == 5)'#10 +
    '      color = float3(0.17,0.25,0.37)*light + pow(saturate(normal.z),12)*0.06;'#10 +
    '    else'#10 +
    '      color = float3(0.68,0.70,0.74)*light*'#10 +
    '        (1-0.35*(1-smoothstep(0.015,0.080,abs(p.uv.y-0.5))));'#10 +
    '    return float4(saturate(color),1);'#10 +
    '  }'#10 +
    ''#10 +
    '  float rough = 0;'#10 +
    '  float distance = 1;'#10 +
    '  if (mode.x == 6 || mode.x == 7)'#10 +
    '  {'#10 +
    '    float2 plane = (p.uv*2-1)*paper.zw*float2(1,-1)-paper.xy;'#10 +
    '    float2 scaleNoise = p.uv*paper.zw/max(damage.z,0.002);'#10 +
    '    rough = 0.16*(noise(scaleNoise*8)-0.43) +'#10 +
    '      0.068*(noise(scaleNoise*31)-0.5) + 0.027*(noise(scaleNoise*91)-0.5);'#10 +
    '    distance = length(plane)/damage.x - damage.y +'#10 +
    '      rough*damage.z/damage.x;'#10 +
    '  }'#10 +
    ''#10 +
    '  float4 print = ink(p.uv);'#10 +
    '  float3 printRGB = print.rgb/max(print.a,0.00001);'#10 +
    '  alpha = print.a;'#10 +
    '  if (alpha < 0.001) discard;'#10 +
    '  if (kind == 1)'#10 +
    '    color = float3(0.83,0.77,0.67) * (0.86 + 0.21*noise(p.uv*float2(1561,799)));'#10 +
    '  else if (backside)'#10 +
    '    color = float3(0.97,0.94,0.86) * (1 + fine*0.045);'#10 +
    '  else'#10 +
    '    color = printRGB;'#10 +
    ''#10 +
    '  if (kind == 3)'#10 +
    '  {'#10 +
    '    float thread = noise(p.uv*float2(820,149));'#10 +
    '    color = lerp(color*float3(0.65,0.61,0.52),float3(0.66,0.60,0.48),'#10 +
    '      0.34+0.30*thread);'#10 +
    '    clip(thread - 0.28 + 0.25*p.edge);'#10 +
    '  }'#10 +
    '  else if (mode.x == 6)'#10 +
    '  {'#10 +
    '    if (damage.y > 0) clip(distance);'#10 +
    '    float hot = (1-smoothstep(0.017,0.12,distance)) * smoothstep(0,0.10,camera.w);'#10 +
    '    float charred = hot*(1-0.22*noise(p.uv*171));'#10 +
    '    float3 toasted = lerp(float3(0.44,0.22,0.092),float3(0.042,0.023,0.015),'#10 +
    '      1-smoothstep(0.018,0.075,distance));'#10 +
    '    color = lerp(color,toasted,saturate(charred*1.26));'#10 +
    '    float ember = (1-smoothstep(0.002,0.014,distance)) *'#10 +
    '      smoothstep(0,0.08,camera.w)*(0.42+0.58*noise(p.uv*86+camera.w*7));'#10 +
    '    color += ember * float3(0.83,0.13,0.018);'#10 +
    '  }'#10 +
    '  else if (mode.x == 7)'#10 +
    '  {'#10 +
    '    if (damage.y > 0)'#10 +
    '    {'#10 +
    '      float erosion = distance + 0.034 + 0.046*noise(p.uv*float2(94,144));'#10 +
    '      clip(erosion);'#10 +
    '    }'#10 +
    '    float wet = (1-smoothstep(0.008,0.17,distance)) * smoothstep(0,0.14,camera.w);'#10 +
    '    if (kind == 0 && !backside && wet > 0.01)'#10 +
    '    {'#10 +
    '      float2 bleed = wet * (float2(rough*0.037 + 0.003,rough*0.062 + 0.004));'#10 +
    '      float4 blurred = (ink(p.uv+bleed)+ink(p.uv-bleed)+'#10 +
    '        ink(p.uv+bleed.yx*float2(-2,1)) + ink(p.uv+bleed.yx*float2(2,-1)))*0.25;'#10 +
    '      color = lerp(color,blurred.rgb/max(blurred.a,0.001),wet*0.66);'#10 +
    '    }'#10 +
    '    color *= lerp(float3(1,1,1),float3(0.57,0.67,0.73),wet*0.77);'#10 +
    '    color = lerp(color,float3(0.71,0.65,0.50)*(0.75+fine*0.25),'#10 +
    '      wet * (1-smoothstep(-0.047,0.012,distance))*0.56);'#10 +
    '  }'#10 +
    '  else if (mode.x == 8)'#10 +
    '  {'#10 +
    '    float age = smoothstep(0.02,0.61,camera.w);'#10 +
    '    float stain = noise(p.uv*19)+0.25*noise(p.uv*71);'#10 +
    '    float luma = dot(color,float3(0.299,0.587,0.114));'#10 +
    '    color = lerp(color,lerp(float3(0.36,0.28,0.17),float3(0.88,0.78,0.59),'#10 +
    '      luma*(0.72+stain*0.29)),age*0.82);'#10 +
    '    float width = age * lerp(0.008,0.16,noise(p.uv*107));'#10 +
    '    if (kind != 1)'#10 +
    '    {'#10 +
    '      if (camera.w > 0.36) clip(p.edge - width*0.14*smoothstep(0.36,0.7,camera.w));'#10 +
    '      color *= lerp(1-age*0.76,1,smoothstep(0,width+0.001,p.edge));'#10 +
    '    }'#10 +
    '  }'#10 +
    ''#10 +
    '  // The SDK texture and coverage from the MSAA resolve use premultiplied RGBA.'#10 +
    '  color *= lerp(1, light, camera.z);'#10 +
    '  return float4(max(0,color)*alpha,alpha);'#10 +
    '}';
