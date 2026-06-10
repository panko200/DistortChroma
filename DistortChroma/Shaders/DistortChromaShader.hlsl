Texture2D InputTexture : register(t0);
SamplerState InputSampler : register(s0)
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

// ★ マップ（ノーマル計算元ソース）用のテクスチャを追加
Texture2D MapTexture : register(t1);
SamplerState MapSampler : register(s1)
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

cbuffer Constants : register(b0)
{
    float Amount;
    float Blur;
    float Steps;
    float Angle;
};

#define WARP_R -1.0
#define WARP_G 0.0
#define WARP_B 1.0
#define COLOR_R float3(1.0, 0.0, 0.0)
#define COLOR_G float3(0.0, 1.0, 0.0)
#define COLOR_B float3(0.0, 0.0, 1.0)

float getLuminance(float3 col)
{
    return dot(col, float3(0.2126, 0.7152, 0.0722));
}

float2 PixelToUVOffset(float2 pixelOffset, float2 duvdx, float2 duvdy)
{
    return pixelOffset.x * duvdx + pixelOffset.y * duvdy;
}

// 法線計算は t1 (MapTexture) からサンプリングするため、map_uv とその偏微分を使用します
float3 computeNormal(float2 map_uv, float angle_val, float2 dmap_dx, float2 dmap_dy, float blurStrength)
{
    float sampleDist = 2.0 + (blurStrength * 0.5);
    
    float2 offX = PixelToUVOffset(float2(sampleDist, 0.0), dmap_dx, dmap_dy);
    float2 offY = PixelToUVOffset(float2(0.0, sampleDist), dmap_dx, dmap_dy);
    
    // t1 から輝度差分を計算
    float gx = getLuminance(MapTexture.SampleLevel(MapSampler, map_uv + offX, 0).rgb)
             - getLuminance(MapTexture.SampleLevel(MapSampler, map_uv - offX, 0).rgb);
    float gy = getLuminance(MapTexture.SampleLevel(MapSampler, map_uv + offY, 0).rgb)
             - getLuminance(MapTexture.SampleLevel(MapSampler, map_uv - offY, 0).rgb);
             
    float3 normal = normalize(float3(-gx * 4.0, -gy * 4.0, 1.0));
    
    float rad = angle_val * 3.14159265359 / 180.0;
    float c = cos(rad);
    float s = sin(rad);
    
    float2 rotNormal;
    rotNormal.x = normal.x * c - normal.y * s;
    rotNormal.y = normal.x * s + normal.y * c;
    normal.xy = rotNormal;
    
    return normal * 0.5 + 0.5;
}

float3 smoothNormalBlur(float2 map_uv, float blurStrength, float angle_val, float2 dmap_dx, float2 dmap_dy)
{
    if (blurStrength <= 0.01)
        return computeNormal(map_uv, angle_val, dmap_dx, dmap_dy, 0.0);
    
    float3 result = float3(0, 0, 0);
    float totalWeight = 0.0;
    
    int radius = 4;
    float stride = 1.0 + (blurStrength * 0.3);
    float sigma = (float) radius * 0.5;

    [loop]
    for (int x = -radius; x <= radius; x++)
    {
        [loop]
        for (int y = -radius; y <= radius; y++)
        {
            float2 pixelOffset = float2(x, y) * stride;
            float2 uvOffset = PixelToUVOffset(pixelOffset, dmap_dx, dmap_dy);
            
            float distSq = (x * x + y * y);
            float weight = exp(-distSq / (2.0 * sigma * sigma));
            
            result += computeNormal(map_uv + uvOffset, angle_val, dmap_dx, dmap_dy, blurStrength) * weight;
            totalWeight += weight;
        }
    }
    return result / totalWeight;
}

float4 main(
    float4 pos : SV_POSITION,
    float4 posScene : SCENE_POSITION,
    float4 uv0 : TEXCOORD0,
    float4 uv1 : TEXCOORD1 // ★ t1 (MapTexture) 用のUV座標を受け取る
) : SV_Target
{
    float2 uv = uv0.xy;
    float2 map_uv = uv1.xy; // ★ MapTexture のサンプリングにはこれを使用する
    
    // ベース画像のアルファは t0 (InputTexture) を使用
    float originalAlpha = InputTexture.Sample(InputSampler, uv).a;
    if (originalAlpha <= 0.001)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);
    
    float2 dmap_dx = ddx(map_uv);
    float2 dmap_dy = ddy(map_uv);
    
    // ★ 元のブラー処理（smoothNormalBlur）を維持したまま、バグのない新しい座標系を渡します
    float3 normal = smoothNormalBlur(map_uv, Blur, Angle, dmap_dx, dmap_dy);
    
    float3 texColor = float3(0.0, 0.0, 0.0);
    float3 blurSum = float3(0.0, 0.0, 0.0);
    
    int maxSteps = max(3, (int) Steps);

    [loop]
    for (int i = 0; i < maxSteps; i++)
    {
        float fi = (float) i / (float) (maxSteps - 1);
        
        float3 Chroma = float3(
            max(0.0, 1.0 - abs(fi - ((WARP_R + 1.0) * 0.5)) * 2.0),
            max(0.0, 1.0 - abs(fi - ((WARP_G + 1.0) * 0.5)) * 2.0),
            max(0.0, 1.0 - abs(fi - ((WARP_B + 1.0) * 0.5)) * 2.0)
        );
        
        float3 blurWeight = (COLOR_R * Chroma.r + COLOR_G * Chroma.g + COLOR_B * Chroma.b);
        blurSum += blurWeight;
        
        float2 displacementPixel = (normal.xy * 2.0 - 1.0) * Amount * fi;
        float2 displacedUV = uv + PixelToUVOffset(displacementPixel, duvdx, duvdy);

        // 色のサンプリングは描画用である t0 (InputTexture) から行う
        texColor += blurWeight * InputTexture.Sample(InputSampler, displacedUV).rgb;
    }

    float3 finalRGB = float3(0, 0, 0);
    if (blurSum.r > 0.001)
        finalRGB.r = texColor.r / blurSum.r;
    if (blurSum.g > 0.001)
        finalRGB.g = texColor.g / blurSum.g;
    if (blurSum.b > 0.001)
        finalRGB.b = texColor.b / blurSum.b;

    return saturate(float4(finalRGB, originalAlpha));
}