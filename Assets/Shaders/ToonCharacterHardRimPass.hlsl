#ifndef ATHENA_TOON_CHARACTER_HARDRIM_PASS
#define ATHENA_TOON_CHARACTER_HARDRIM_PASS

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Athena/Runtime/Toon/Utils.hlsl"

#include "Packages/com.unity.render-pipelines.universal/Shaders/LitForwardPass.hlsl"

//////////////////////////////////////////////////////////////////////////////////////////////////
// Rim  //////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////

struct URPToonHardRimVertexInput
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 uv	  : TEXCOORD0;
};

struct URPToonHardRimVertexToFragment
{
    float4 posCS      : SV_POSITION;
    float2 uv		  : TEXCOORD0;
    float3 normalWS   : TEXCOORD1;
    float3 posWS      : TEXCOORD2;
    float2 posSS      : TEXCOORD3;
    float2 target1PosSS : TEXCOORD4;
    float2 target2PosSS : TEXCOORD5;
    float  vdotl        : TEXCOORD6;
    float4 lightInfo    : TEXCOORD7;
};

float2 TransformClipToScreen(float4 posCS) {
    float2 posSS = posCS.xy / posCS.w;
#if UNITY_UV_STARTS_AT_TOP
    posSS.y *= -1;
#endif
    posSS = 0.5*(posSS + 1.0);

    return posSS;
}
float2 TransformViewToScreen(float3 posVS) {
    float4 posCS = mul(UNITY_MATRIX_P, posVS);

    return TransformClipToScreen(posCS);
}
inline URPToonHardRimVertexToFragment URPToonHardRimVert(URPToonHardRimVertexInput v)
{
    URPToonHardRimVertexToFragment o;
    o.normalWS = normalize(mul(UNITY_MATRIX_M, float4(v.normal, 0.0)).xyz);
    o.posCS = TransformObjectToHClip(v.vertex);
    o.uv = v.uv;
    o.posWS = mul(unity_ObjectToWorld, v.vertex);

    o.posSS = TransformClipToScreen(o.posCS);

    float3 posVS = TransformWorldToView(o.posWS);
    float3 target1 = posVS + float3(_HardRimWidth/100, 0, 0);
    float3 target2 = posVS - float3(_HardRimWidth/100, 0, 0);

    o.target1PosSS = TransformViewToScreen(target1);
    o.target2PosSS = TransformViewToScreen(target2);

    float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - o.posWS.xyz);
    float3 lightDirection = SafeNormalize(_MainLightPosition.xyz);
    o.vdotl = dot(viewDirection, lightDirection);

    o.lightInfo.rgb = SafeNormalize(_MainLightColor.rgb);
    o.lightInfo.a = length(_MainLightColor.rgb);
    return o;
}
inline float GetDepth(float2 targetUV) {
    float rawDepth = SampleSceneDepth(targetUV);
    float depth = LinearEyeDepth(rawDepth, _ZBufferParams);
    return depth;
}
float GetRimInt(float2 target1, float2 target2, float2 ssUV, float depth, float3 normalWS, float vdotl) {
    float depthTarget;
    depthTarget = GetDepth(target1);
    depthTarget += GetDepth(target2);
    depthTarget /= 2;
    //get rim based on depth difference
    float depthDiff = depthTarget - depth;

    //get rim based on depth difference
    float rimIntLowerBound = saturate(_HardRimDepthThresholdBase / 100 * 0.99 * (1 - _HardRimFeather));
    float rimIntUpperBound = _HardRimDepthThresholdBase / 100;

    float rimInt = linearStep(rimIntLowerBound, rimIntUpperBound, depthDiff);
    rimInt *= Remap(vdotl, -1, 1, _HardRimIntBackLight, _HardRimIntFaceLight);
    float n = normalWS.y;
    //n = step(0, n) * pow(abs(n), 1- _NormalEffecttIntensity);
    rimInt *= Remap(n, 0.9, -0.9, _HardRimIntNormalUp, _HardRimIntNormalDown);

    return saturate(rimInt);
}

inline half4 URPToonHardRimFrag(URPToonHardRimVertexToFragment i) : SV_Target
{
    //* pwrd zhengyiye: Dither
    Dither(_DitherAlpha, i.posCS)

    //get current depth
    float2 ssUV = i.posSS;
    float depth = GetDepth(ssUV);

    //get rim intensity
    float rimInt = GetRimInt(i.target1PosSS, i.target2PosSS, ssUV, depth, i.normalWS, i.vdotl);

    //influence from light
    float3 rimColor = lerp(_HardRimColor.rgb, i.lightInfo.rgb, _HardRimLighColBlend);
    rimInt *= lerp(_HardRimInt, i.lightInfo.a, _HardRimLighIntBlend);

    return half4(rimColor * rimInt , 1);
}

#endif
