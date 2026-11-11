#ifndef ATHENA_TOON_CHARACTER_LIT_PASS
#define ATHENA_TOON_CHARACTER_LIT_PASS

#include "Packages/com.unity.render-pipelines.universal/Shaders/LitForwardPass.hlsl"

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Physically Based) shader
Varyings LitPassVertexToonCharacter(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    half3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);

//* pwrd lvjunyu
#if _LayeredEnable
    output.uv = input.texcoord;
#else
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
#endif
//* pwrd lvjunyu

//* pwrd lvjunyu: 需要切线空间转换矩阵
#if defined(_NeedTangentSpaceTransMatrix)
//* pwrd lvjunyu
    output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
    output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
    output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);
#else
    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
    output.viewDirWS = viewDirWS;
#endif

    OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

    //* pwrd zhanglingyun：天气系统雾效
    #if defined(_SUPPORT_ATHENA_FOG)
		TRANSFER_FOG_FACTOR(output.fogFactor, vertexInput.positionWS);
	#endif
//* pwrd zhanglingyun
    output.fogFactorAndVertexLight = half4(0, vertexLight);

//* pwrd lvjunyu: 需要世界坐标
#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR) || defined(_NeedWorldPos)
//* pwrd lvjunyu
    output.positionWS = vertexInput.positionWS;
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

#if ENABLE_INNER_LINE
    output.innerLineUV = input.texcoord3;
#endif

    output.positionCS = vertexInput.positionCS;
    //* pwrd lvjunyu: 顶点着色器扩展接口
    AfterLitPassVertex(input, vertexInput, output);
    //* pwrd lvjunyu
    return output;
}

    #ifdef DEBUG_DISPLAY
    #include "Packages/com.unity.render-pipelines.universal/Athena/Runtime/ShaderLibrary/PBRValidator.hlsl"
    #endif

////* pwrd zhangxuhui: supprot mrt
//struct FragmentOutput
//{
//#if UseMultiRenderTarget
//    half4 color : SV_Target0;
//    float depth : SV_Target1;
//    half3 normal: SV_Target2;
//#else
//    half4 color : SV_Target;
//#endif
//};
////* pwrd zhangxuhui

float remap(float In, float2 InMinMax, float2 OutMinMax)
{
    return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
}
// Used in Standard (Physically Based) shader


#include "ToonDissolve.hlsl"

// Fragment Shader
// 添加vfacing 来判断正反面
FragmentOutput LitPassFragmentToonCharacter(Varyings input, FRONT_FACE_TYPE vfacing: FRONT_FACE_SEMANTIC)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SurfaceData surfaceData;

	////* pwrd lvjunyu: 自定义Input数据解析
	//#if _CustomSurfaceInput
	//	CustomInitializeLitSurfaceData(input.uv, surfaceData);
	//#elif _LayeredEnable
	//	LayeredInitializeLitSurfaceData(input.uv, input.vertexColor.xyz, input.positionWS, input.normalWS.xyz, input.tangentWS.xyz, input.bitangentWS.xyz, surfaceData);
	//#else
	//	InitializeStandardLitSurfaceData(input.uv, surfaceData);
	//#endif
	////* pwrd lvjunyu

	//* pwrd zhengyiye: 暂时只保留一种输入，后续根据需要，另起一个函数来作为自定义输入
	InitializeStandardLitSurfaceData(input.uv, surfaceData);

    // 计算面的正反面, 根据正反面反转法线。
    // half isFront = IS_FRONT_VFACE(vfacing, 1, 0);
    // input.normalWS.xyz = lerp(-input.normalWS.xyz, input.normalWS.xyz, isFront);

    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);

    //* pwrd zhengyiye: dither抖动
    Dither(_DitherAlpha, input.positionCS)

    //* pwrd lvjunyu: PBR光照数据扩展接口
    AfterInitializeInputAndSuffaceData(input, surfaceData, inputData);
    //* pwrd lvjunyu

	//* pwrd zhengyiye: 初始化卡渲信息
	ToonData toonData = InitializeToonData(input.uv, surfaceData, inputData);
	//* pwrd zhengyiye

    //* liyangyuqing: 溶解处理
    #if defined(ENABLE_DISSOLVE) && _TOON_ATHENA_DISSOLVE   //* wanghaoyu 这里加上 _TOON_ATHENA_DISSOLVE
    ApplyDissolveWithEmission(input.uv, input.positionWS, surfaceData);
    #endif
    //* liyangyuqing

	// 核心PBR光照模型在这里
    half4 color = UniversalFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha, toonData);

    //* pwrd zhengyiye: 应用Matcap
    color = ApplyMatcapColor(color, inputData, toonData, input.uv);

	// 增加特效部分
	color = ApplyToonEffect(color, toonData);

    // 增加内描边部分
    #if ENABLE_INNER_LINE
    half3 edgeColor = lerp(half3(0,0,0), _EdgeColor.rgb * surfaceData.albedo.rgb, _EdgeColor.a);

    half innerLineRange = _EdgeInnerRange * lerp(1, input.vertexColor.a, _EdgeInnerAlphaAffect);

    half uvLineRangeX = (lerp(0.495, abs(input.innerLineUV.x - 0.5), innerLineRange)  - 0.5 ) ;
    half uvLineRangeY = (lerp(0.495, abs(input.innerLineUV.y - 0.5), innerLineRange)  - 0.5 ) ;
    //half uvLineRangeX = (abs(input.innerLineUV.x - 0.5) - 0.5) * _EdgeInnerRange;
    //half uvLineRangeY = (abs(input.innerLineUV.y - 0.5) - 0.5) * _EdgeInnerRange;

    half edgeInnerOffset = _EdgeInnerOffset * 0.05;

    half uvInnerLineX = uvLineRangeX + edgeInnerOffset ;
    half uvInnerLineY = uvLineRangeY + edgeInnerOffset ;

    //half uLine = saturate((uvInnerLineX)* _EdgeInnerSmooth * 100);
    //half vLine = saturate((uvInnerLineY)* _EdgeInnerSmooth * 100);
    half uLine = smoothstep(0, _EdgeInnerSmooth * 0.01, uvInnerLineX );
    half vLine = smoothstep(0, _EdgeInnerSmooth * 0.01, uvInnerLineY );

    half innerLine = max(uLine, vLine);

    color.rgb = lerp(color.rgb, edgeColor, innerLine);
    #endif

    // 增加程序实时调动特效部分   目前存在ToonBase 里面
    color = ApplyToonGameDynamicEffect(color, toonData);
    //* pwrd zhengyiye

    //* pwrd zhanglingyun：天气系统雾效
    #if defined(_SUPPORT_ATHENA_FOG)
        APPLY_FOG_COLOR(color, inputData.fogCoord, input.positionWS, _MainLightPosition.xyz, inputData.viewDirectionWS)
    #endif
    //* pwrd zhanglingyun

    #ifdef DEBUG_DISPLAY
	    DEBUG_ASSIGN_VECTOR4(Fragment_FogFactor,  half4(inputData.fogFactor, 1,1));
    #endif

	//* pwrd xuke
    #ifdef DEBUG_DISPLAY
	color = debug_resultcolor;
    #endif
	//* pwrd xuke

    //* pwrd zhangxuhui: supprot mrt
    FragmentOutput output;
    #ifdef UseMultiRenderTarget
        output.color = color;
        output.depth = input.positionCS.z;
        output.normal = input.normalWS.xyz;
    #else
        output.color = color;
    #endif
    //* pwrd zhangxuhui

    return output;
}



#endif
