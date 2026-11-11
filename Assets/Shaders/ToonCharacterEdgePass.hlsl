#ifndef ATHENA_TOON_CHARACTER_EDGE_PASS
#define ATHENA_TOON_CHARACTER_EDGE_PASS

#include "Packages/com.unity.render-pipelines.universal/Shaders/LitForwardPass.hlsl"

//////////////////////////////////////////////////////////////////////////////////////////////////
// Edge //////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////

#define INV_EDGE_THICKNESS_DIVISOR 0.02

struct URPToonEdgeVertexInput
{
	float4 vertex  : POSITION;
	float2 uv      : TEXCOORD0;
	half4  color   : COLOR;
	half3  normal  : NORMAL;
    half4  tangent : TANGENT;
    float2  uv1     : TEXCOORD1;
    #if _EDGENORMAL_UV2TS
    float2  uv2     : TEXCOORD2;
    #endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct URPToonEdgeVertexToFragment
{
	float4 vertex     : SV_POSITION;
	//float3 uvAndFog   : TEXCOORD0;
	float2 uv         : TEXCOORD0;
	half4  positionWS : TEXCOORD1;
	half4  screenPos  : TEXCOORD2;
	half3  normalWS   : TEXCOORD3;
    half3  viewDirWS  : TEXCOORD4;

	#if defined(_SUPPORT_ATHENA_FOG)
	    half2 fogFactor             : TEXCOORD9;
	#endif
};

inline URPToonEdgeVertexToFragment URPToonEdgeVert (URPToonEdgeVertexInput v)
{
    VertexNormalInputs normals = GetVertexNormalInputs(v.normal.xyz);
    VertexPositionInputs positions = GetVertexPositionInputs(v.vertex.xyz);

    // 判断哪个UV储存了切线空间法线。
    #if _EDGENORMAL_UV1TS
        float2 packedUV = v.uv1.xy;
    #elif _EDGENORMAL_UV2TS
        float2 packedUV = v.uv2.xy;
    #endif

	// Object space normal
	#if _EDGENORMAL_COLOROS
        // 使用Normal Painter把世界空间法线写入模型的顶点色的时候
		half3 normalOS = normalize(v.color.rgb * 2.0 - 1.0) * - 1;
        normalOS.xyz = normalOS.zyx;

    #elif _EDGENORMAL_COLORTS
        // 使用Normal Painter把切线空间法线写入模型的顶点色的时候
        half3 normalColor = v.color.xyz * 2 - 1;
        half3 binormal = cross(normalize(v.normal), normalize(v.tangent.xyz)) * v.tangent.w;
        half3x3 matTangentToObject = half3x3(v.tangent.xyz, binormal.xyz, v.normal);
        half3 normalOS = mul(normalize(normalColor), matTangentToObject);

    #elif _EDGENORMAL_UV1TS || _EDGENORMAL_UV2TS
        // 使用UV1储存切线空间法线时
        half zSign = sign(packedUV.y);
        half unpackedY = (abs(packedUV.y) - 0.5) * 2;
        float unpackedZ = sqrt(1 - packedUV.x * packedUV.x - unpackedY * unpackedY) * zSign;
        //half3 normalTS = half3 (v.uv1, v.uv2.x);
        half3 normalTS = half3(packedUV.x, unpackedY, unpackedZ);
        half3 binormal = cross(normalize(v.normal), normalize(v.tangent.xyz)) * v.tangent.w;
        half3x3 matTangentToObject = half3x3(v.tangent.xyz, binormal.xyz, v.normal);
        half3 normalOS = mul(normalize(normalTS), matTangentToObject);
    #else
        // 没有标注时，相当于使用_EDGENORMAL_NORMAL
        half3 normalOS = v.normal;
	#endif

	// Edge thickness
    #if USE_EDGETEXTUREMASK
        float thicknessFactor = SAMPLE_TEXTURE2D_LOD(_EdgeTextureMask, sampler_EdgeTextureMask, v.uv.xy, 0).r * v.color.a;
    #else
        float thicknessFactor = v.color.a;
    #endif
	float3 centerPositionWS = TransformObjectToWorld(float3(0, 0, 0));
	half   edgeThickness = clamp(positions.positionCS.w, 0.5, 2) * thicknessFactor * _EdgeThickness * INV_EDGE_THICKNESS_DIVISOR;
	edgeThickness *= smoothstep(_EdgeFarDistance, 0, distance(centerPositionWS, _WorldSpaceCameraPos.xyz));

	// Edge XY offset and edge thickness
	half3 normalWS = normalize(mul((float3x3)UNITY_MATRIX_IT_MV, normalOS));
	half2 XYOffset = TransformWViewToHClip(half3(normalWS.xy, 0)).xy * edgeThickness;

	// Edge Z offset
	float4 cameraPositionCS = TransformWorldToHClip(GetCameraPositionWS());
	half   ZOffset = _EdgeZOffset * -0.1 * cameraPositionCS.z;
    //* pwrd zhengyiye : 增加顶点色对深度偏移的判断
    ZOffset *=  lerp(1, v.color.a, _EdgeAlphaAffectZOffset);
	// #if defined(UNITY_REVERSED_Z)
	// 	half ZOffset = _EdgeZOffset * -0.1 * cameraPositionCS.z;
	// #else
	// 	half ZOffset = _EdgeZOffset * 0.1 * cameraPositionCS.z;
	// #endif

    //* pwrd zhengyiye : 增加视角方向
    half3 viewDirectionWS = GetCameraPositionWS() - positions.positionWS;
    //* pwrd zhengyiye

	URPToonEdgeVertexToFragment o;

    //* pwrd zhanglingyun：天气系统雾效
	#if defined(_SUPPORT_ATHENA_FOG)
		TRANSFER_FOG_FACTOR(o.fogFactor, positions.positionWS);
	#endif
    //* pwrd zhanglingyun

	o.uv = v.uv.xy;
    o.normalWS = normals.normalWS;
	o.vertex = positions.positionCS + float4(XYOffset, ZOffset, 0);
	o.positionWS.xyz = positions.positionWS;
	o.screenPos = ComputeScreenPos(positions.positionCS);
    o.viewDirWS = viewDirectionWS;

    // Effect vertex to fragment
    //MJJEffectVertexInputData effectInputData = (MJJEffectVertexInputData)0;
    //MJJEFFECT_VERTEX_TO_FRAGMENT(v, o, effectInputData);

	return o;
}

float remap(float In, float2 InMinMax, float2 OutMinMax)
{
    return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
}

#if _TOON_ATHENA_DISSOLVE
#include "ToonDissolve.hlsl"
#endif

inline half4 URPToonEdgeFrag (URPToonEdgeVertexToFragment input) : SV_Target
{
    //half4 sampleBaseMap = SampleAlbedoAlpha(input.uvAndFog.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));;
    half4 sampleBaseMap = SampleAlbedoAlpha(input.uv.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));

    //* pwrd zhengyiye: dither抖动
    Dither(_DitherAlpha, input.vertex)

    #if defined(ENABLE_DISSOLVE) && _TOON_ATHENA_DISSOLVE   //* wanghaoyu 这里去掉define()
    ApplyDissolve(input.uv.xy, input.positionWS.xyz);
    #endif

	#if defined(_ALPHATEST_ON)
    {
		clip(sampleBaseMap.a - _Cutoff);
    }
	#endif

    half3 outColor = saturate(sampleBaseMap.rgb);
    outColor = lerp(half3(0,0,0), _EdgeColor.rgb * outColor, _EdgeColor.a);
    #if USE_TOONGAMEEFFECT && _TOON_ATHENA
    outColor = lerp(outColor, _DynamicEdgeColor.rgb, _DynamicEdgeColor.a);
    #endif

    half3 viewDirWS = SafeNormalize(input.viewDirWS);

    // 计算内描边颜色
    #if ENABLE_INNER_LINE

    #endif


    //* pwrd zhanglingyun：天气系统雾效
    #if defined(_SUPPORT_ATHENA_FOG)
        //APPLY_FOG_COLOR(outColor, input.uvAndFog.z, input.positionWS, _MainLightPosition.xyz, viewDirWS)
        APPLY_FOG_COLOR(outColor, input.fogFactor, input.positionWS, _MainLightPosition.xyz, viewDirWS)
    #endif
    //* pwrd zhanglingyun

	half4 finalColor = half4(outColor, 1);

    // Global effect
    //MJJEffectFragmentInputData effectInputData = (MJJEffectFragmentInputData)0;
    //effectInputData.uv = i.uv;
    //effectInputData.viewWS = normalize(GetCameraPositionWS() - i.positionWS.xyz);
    //effectInputData.normalWS = normalize(i.normalWS);
    //effectInputData.fogFactor = i.positionWS.w;
    //effectInputData.positionWS = i.positionWS.xyz;
    //effectInputData.screenPos = i.screenPos;
    //MJJEFFECT_FRAGMENT_OUTPUT(i, finalColor, effectInputData);

	return saturate(finalColor);
}

#endif
