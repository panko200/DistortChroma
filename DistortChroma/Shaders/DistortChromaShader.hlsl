Texture2D InputTexture : register(t0);
SamplerState InputSampler : register(s0)
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

// ★改良1：微細なノイズを拾わず、滑らかで大きな「うねり」を抽出する
float3 computeNormal(float2 uv, float angle_val, float2 duvdx, float2 duvdy, float blurStrength)
{
    // ぼかしが強いほど、差分を取る距離を広げてノイズを潰す
    float sampleDist = 2.0 + (blurStrength * 0.5);
    
    float2 offX = PixelToUVOffset(float2(sampleDist, 0.0), duvdx, duvdy);
    float2 offY = PixelToUVOffset(float2(0.0, sampleDist), duvdx, duvdy);
    
    float gx = getLuminance(InputTexture.SampleLevel(InputSampler, uv + offX, 0).rgb)
             - getLuminance(InputTexture.SampleLevel(InputSampler, uv - offX, 0).rgb);
    float gy = getLuminance(InputTexture.SampleLevel(InputSampler, uv + offY, 0).rgb)
             - getLuminance(InputTexture.SampleLevel(InputSampler, uv - offY, 0).rgb);
             
    // 抽出した差分から滑らかな法線ベクトルを作る
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

// ★改良2：バキバキにならない、滑らかで安定したガウス風ブラー
float3 smoothNormalBlur(float2 uv, float blurStrength, float angle_val, float2 duvdx, float2 duvdy)
{
    if (blurStrength <= 0.01)
        return computeNormal(uv, angle_val, duvdx, duvdy, 0.0);
    
    float3 result = float3(0, 0, 0);
    float totalWeight = 0.0;
    
    int radius = 4; // サンプル範囲を少し広げて滑らかに
    float stride = 1.0 + (blurStrength * 0.3); // 広げすぎによる多重影を防ぐ
    float sigma = (float) radius * 0.5;

    [loop]
    for (int x = -radius; x <= radius; x++)
    {
        [loop]
        for (int y = -radius; y <= radius; y++)
        {
            float2 pixelOffset = float2(x, y) * stride;
            float2 uvOffset = PixelToUVOffset(pixelOffset, duvdx, duvdy);
            
            // ガウス関数による重み付け（中心に近いほど濃く、外ほど薄く拾う）
            float distSq = (x * x + y * y);
            float weight = exp(-distSq / (2.0 * sigma * sigma));
            
            result += computeNormal(uv + uvOffset, angle_val, duvdx, duvdy, blurStrength) * weight;
            totalWeight += weight;
        }
    }
    return result / totalWeight;
}

float4 main(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv0 : TEXCOORD0) : SV_Target
{
    float2 uv = uv0.xy;
    
    float originalAlpha = InputTexture.Sample(InputSampler, uv).a;
    if (originalAlpha <= 0.001)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    
    float2 duvdx = ddx(uv);
    float2 duvdy = ddy(uv);
    
    // 滑らかな法線を生成
    float3 normal = smoothNormalBlur(uv, Blur, Angle, duvdx, duvdy);
    
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
        
        // 歪み適用
        float2 displacementPixel = (normal.xy * 2.0 - 1.0) * Amount * fi;
        float2 displacedUV = uv + PixelToUVOffset(displacementPixel, duvdx, duvdy);

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