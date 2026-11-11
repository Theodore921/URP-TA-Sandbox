#ifndef ATHENA_TOON_STENCIL
#define ATHENA_TOON_STENCIL

/// 定义角色的Stencil阴影用到的计算
struct VertexInput
{
    float4 vertex	: POSITION;
    half4 color		: COLOR;
    half2 uv        : TEXCOORD0;
};

struct VertexOutput
{
    float4 pos		: SV_POSITION;
    half4 color		: COLOR;
    half2 uv        : TEXCOORD0;
};

VertexOutput forwardVertStencilCast(VertexInput v)
{
    VertexOutput o = (VertexOutput)0;

    o.pos = TransformObjectToHClip(v.vertex.xyz);
    o.color = v.color;
    o.uv = v.uv.xy;

    // 对Stencil 做深度调整
    //float4 cameraPositionCS = TransformWorldToHClip(GetCameraPositionWS());

    #if UNITY_REVERSED_Z
        half zOffset = _StencilShadowZOffset;
    #else
        half zOffset = -_StencilShadowZOffset;
    #endif
    zOffset = zOffset * -0.1 * o.pos.z / o.pos.w;

    // 阴影在裁剪面空间按光照方向偏移
    half3 lightDirCS = mul(GetWorldToHClipMatrix(), float4(-_MainLightPosition.xyz, 0.0)).xyz;
    float2 offset = lightDirCS.xy * v.color.r * 0.01 * _StencilShadowOffset;
    o.pos.xy += offset;
    // o.pos.z += zOffset;

    return o;
}

half4 forwardFragStencilCast(VertexOutput i) : SV_Target
{
    // 增加对半透的Clip
    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).a;

    clip(i.color.r * alpha - _Cutoff);

    return 0;
}

#endif  // ATHENA_TOON_STENCIL
