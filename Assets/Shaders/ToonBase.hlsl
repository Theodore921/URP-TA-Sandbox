#ifndef ATHENA_TOON_BASE
#define ATHENA_TOON_BASE

//#include "Packages/com.unity.render-pipelines.universal/Athena/Runtime/ShaderLibrary/AthenaDither.hlsl"

#if _TOON_ATHENA

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

#include "ToonMatcap.hlsl"
#include "ToonDataStruct.hlsl"


//--------------------------------
// Toon Light
//--------------------------------

half3 GetToonLightDir(half3 originalLightDir)
{
	half3 result = 0;
    UNITY_BRANCH
    if(_ToonLightHeightClamp == 0)
    {
        result = originalLightDir;
    }
	else
	{
	    half originalHeight = originalLightDir.y;
        // 计算输出高度
        half outHeight = lerp(originalHeight, _ToonLightHeight, _ToonLightHeightClamp);
        half outXZLenght = sqrt(1 - outHeight * outHeight);
        half2 calLightXZ = originalLightDir.xz;
        calLightXZ = normalize(calLightXZ) * outXZLenght;

        half3 outLightDir = half3(calLightXZ.x, outHeight, calLightXZ.y);
        result = outLightDir;
	}
	return result;

}

half GetToonLightAttenuation(half lightAtten)
{
    #if defined(_SHADOWAREA)
        return 0;
    #else
        return lightAtten;
    #endif
}

half3 ClampLightIntensity()
{
	half3 result = 0;
    half3 lightColor = _MainLightColor.rgb;
    half3 lightMaxChannel = max(max(lightColor.r, lightColor.g), lightColor.b);
    UNITY_BRANCH
    if(any(lightMaxChannel <= _ToonLightLimit))
    {
        result = lightColor;
    }
	else
	{
        result = lightColor * (_ToonLightLimit / lightMaxChannel);
	}
	return result;
}

// 额外点光源的风格化
#if _TOON_ATHENA_LIGHTING_ADDITIONAL
half3 LightingAdditionalToon(BRDFData brdfData, Light light, InputData inputData, half grading)
{
    half3 normalWS = inputData.normalWS;
    half3 viewDirectionWS = inputData.viewDirectionWS;
    half3 lightColor = light.color;

	half clampedGrading = 0;
	#if _USE_GRADING_MAP_TO_MASK_SDF
	// SDF脸部需要区分出不使用SDF的部分，这种时候，Grading 是不正确的，所以要限制
	clampedGrading = min(0, grading);
	#endif
    half halfNdotL = dot(light.direction, normalWS) * 0.5 + 0.5;
    half adjustedNdotL = saturate(saturate((halfNdotL - _ToonCutLocationAdditional ) * _ToonCutSharpnessAdditional * light.distanceAttenuation ) + clampedGrading);
        //* wanghaoyu 百万,对于额外光希望不依赖法线,让角色显得更平,且需要更明确的面部SDF阴影
    #if _ADDITIONAL_LIGHTS_TOON_FLAT
    adjustedNdotL = saturate(saturate(_ToonCutSharpnessAdditional * light.distanceAttenuation ) + clampedGrading);
    half addLightAtten = saturate(light.distanceAttenuation / _ToonAdditionalFlat);
    half moreFlat = pow(addLightAtten,lerp(_ToonAdditionalFlatContrast,max(_ToonAdditionalFlatContrast-1,0),addLightAtten));
    adjustedNdotL *= moreFlat;
        //* wanghaoyu 百万，对于额外光希望对金属和非金属部分有明确区分，跟上面用的同一个宏
    return DirectBDRF(brdfData, normalWS, light.direction, viewDirectionWS) * adjustedNdotL * lightColor * light.shadowAttenuation * _ToonDiffuseIntensityAdditional;
    #endif
    return brdfData.diffuse * adjustedNdotL * lightColor * light.shadowAttenuation * _ToonDiffuseIntensityAdditional;

}
#endif

#if _TOON_ATHENA_LIGHTING
// 计算主光源的明暗交界线位置
half GetToonCutLocation(half vdotl)
{
#if ENABLE_NDOTL_MOVE_BY_VDOTL
    //half vdotl = dot(viewDir, lightDir);
    half cutLocationOffsetFaceLight = lerp(0, _ToonCutLocationFaceLight, abs(vdotl));
    half cutLocationOffsetBackLight = lerp(0, _ToonCutLocationBackLight, abs(vdotl));
    half cutLocationOffset = lerp(cutLocationOffsetBackLight, cutLocationOffsetFaceLight,  saturate(sign(vdotl)) );
    half cutLocation = _ToonCutLocation + cutLocationOffset;
    return cutLocation;
#else
    return _ToonCutLocation;
#endif
}

// 计算风格化NdotL
half CalculateToonNdotL(half halfNdotL, ToonData toonData)
{
    half adjustedNdotL;
    // 使用这个config内的参数，来尝试作区分
    #if _USE_GRADING_MAP_TO_MASK_SDF
        UNITY_FLATTEN
        if(_ToonUseSdfFace && toonData.diffuseGrading > 0.9)
    #else
        UNITY_BRANCH
        if(_ToonUseSdfFace)
    #endif
        {
            half sdfOutput = toonData.sdf * (_ToonSDFOffsetFront + 1 - _ToonSDFOffset) + _ToonSDFOffset;
            sdfOutput = smoothstep(_PrecomputeArccosine - 0.5 * _ToonSDFBlur, _PrecomputeArccosine + 0.5 * _ToonSDFBlur,  sdfOutput);
            adjustedNdotL = sdfOutput;
        }
        else
        {
            // 获取CutLocation
            half cutLocation = GetToonCutLocation(toonData.VdotL);
            // 简单二值化
            adjustedNdotL = saturate(saturate((halfNdotL - cutLocation ) * _ToonCutSharpness ) + toonData.diffuseGrading);
        }
    return adjustedNdotL;
}
#endif

//* wanghaoyu 把平行光的计算从Lighting挪到这里了
//* pwrd zhengyiye : 增加卡通渲染光照模型
#if _TOON_ATHENA_LIGHTING
half3 LightingPBRToon(BRDFData brdfData, Light light, InputData inputData, ToonData toonData, half metallic, half3 albedo)
{
    half3 normalWS = inputData.normalWS;
    half3 viewDirectionWS = inputData.viewDirectionWS;

    half3 lightColor = light.color;
    // 限制主光饱和度
    half3 hsv = RgbToHsv(lightColor);
    hsv.g = lerp(0, _LightSaturationLimited, hsv.g);
    lightColor = HsvToRgb(hsv);

    // 预先生成变量
    half adjustedNdotL;
    half lightAttenuation;
    half cutLocation;
    half NdotL = toonData.NdotL;
    half NdotV = toonData.NdotV;
    half halfNdotL = NdotL * 0.5 + 0.5;
    half3 lightDirectionWS = toonData.lightDirToonWS;

    // 用ToonBase 计算灯光高度和影子计算
    lightAttenuation = GetToonLightAttenuation(light.distanceAttenuation * light.shadowAttenuation);

    // 在ToonBase 中计算NdotL
    adjustedNdotL = CalculateToonNdotL(halfNdotL, toonData);

    half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
    half3 darkColor = toonData.darkColor;

    // 区分是否使用Ramp贴图
    #ifdef USE_RAMP
    half2 rampUV = half2(adjustedNdotL * lightAttenuation, inputData.vertexColor.r) ;
    half3 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, rampUV.xy).xyz;
    half3 toonDiffuse = lerp(darkColor,  brdfData.diffuse, ramp ) * lightColor;

    #else
    half3 toonDiffuse = lerp(darkColor,  brdfData.diffuse, adjustedNdotL * lightAttenuation ) * lightColor;
    #endif  // USE_RAMP

    half3 skinRimColor = pow(abs(toonDiffuse + 0.0001), _SkinFactor);
    skinRimColor *= lerp(1, _SkinOverrideColor.rgb , _SkinOverrideColor.a);
    skinRimColor *= _SkinColorBoost;
    toonDiffuse *= lerp(skinRimColor, 1, NdotV) * toonData.diffuseIntensity * oneMinusReflectivity;
    // diffuse饱和度调节
    half3 hsv1 = RgbToHsv(toonDiffuse);
    hsv1.g = saturate(lerp(_DiffuseSaturationLimited, 1, hsv1.g));
    toonDiffuse = HsvToRgb(hsv1);

    half3 radiance = lightColor * (lightAttenuation * saturate(NdotL + toonData.diffuseGrading));

    half3 toonDiffuseCombine = lerp(toonDiffuse, brdfData.diffuse * radiance, toonData.isPBR);

    brdfData.diffuse = 0;
    // 背面补光
    half fillAdjustedNdotL = 1 - (saturate(adjustedNdotL) * lightAttenuation);
    half3 fillColor = (DirectBDRF(brdfData, normalWS, viewDirectionWS, viewDirectionWS) + albedo) * fillAdjustedNdotL * lightColor * _FillIntensity;
    fillColor *= 0.4;

    half3 color = DirectBDRF(brdfData, normalWS, lightDirectionWS, viewDirectionWS) * radiance + toonDiffuseCombine;
    color += fillColor;

    //*pwrd xuke
    #if defined( DEBUG_DISPLAY) && defined(LIGHTING_DEBUG)
        float3 Direct_Diffuse =  DEBUG_RESULT_VALUE(Direct_Diffuse);
        float3 Direct_Specular =  DEBUG_RESULT_VALUE(Direct_Specular);
        half3 result = DirectBDRF(brdfData, normalWS, lightDirectionWS, viewDirectionWS);
        DEBUG_ASSIGN_VECTOR4(Direct_Diffuse,  float4(DEBUG_RESULT_VALUE(Direct_Diffuse).xyz * radiance + Direct_Diffuse,1));
        DEBUG_ASSIGN_VECTOR4(Direct_Specular, float4(DEBUG_RESULT_VALUE(Direct_Specular).xyz * radiance + Direct_Specular,1));
        return result * radiance;
    #else //DEBUG_DISPLAY && LIGHTING_DEBUG
        return color;
    #endif //DEBUG_DISPLAY && LIGHTING_DEBUG
    //* pwrd xuke
}
#endif





//--------------------------------
// Toon Initialization
//--------------------------------
inline ToonData InitializeToonData(half2 uv, SurfaceData surfaceData, inout InputData inputData)
{
    ToonData outToonData;

    half4 sampleMixedToonMap = SAMPLE_TEXTURE2D(_MixedToonMap, sampler_MixedToonMap, uv);

    #if defined(USE_DARKMAP)
    half4 sampleDarkMap = SAMPLE_TEXTURE2D(_DarkMap, sampler_DarkMap, uv);
    outToonData.darkColor = sampleDarkMap.rgb * _BaseColor.rgb;
    #elif !defined(_Mode_Kajiya_Kay)
    outToonData.darkColor = lerp(surfaceData.albedo, surfaceData.albedo * _DarkColor.rgb, _DarkColor.a);
    #endif

    // mixed 贴图的R通道是Grading，g通道是RimMask，B通道是PBRMask
    #if !defined(_Mode_Kajiya_Kay)
    outToonData.diffuseGrading = sampleMixedToonMap.r * 2 - 1;
    outToonData.isPBR = sampleMixedToonMap.b;
    outToonData.diffuseIntensity = _ToonDiffuseIntensity;

	//* pwrd fanxingtong: Athena/Toon/Hair Cast Stencil Shadow中将MixTex的Alpha通道作为KK模型的Mask
	#else
	outToonData.KajiyaKayMask = sampleMixedToonMap.a;
    #endif
    outToonData.rimMask = sampleMixedToonMap.g;

    #ifdef USE_MATCAP
    outToonData.matcapMask = sampleMixedToonMap.a;
    #endif

    half3 lightDir = GetToonLightDir(_MainLightPosition.xyz);
    half3 viewDir = inputData.viewDirectionWS;
    half3 normalDir = inputData.normalWS;

    outToonData.lightDirToonWS = lightDir;
    outToonData.NdotV = dot(normalDir, viewDir);
    outToonData.NdotL = dot(normalDir, lightDir);
    outToonData.VdotL = dot(viewDir, lightDir);

    // 计算屏幕空间 NdotL
    UNITY_BRANCH
    if(_RimlightUseScreenSpaceDirection < 0.5 )
    {
        outToonData.SSNdotL = outToonData.NdotL;
    }
    else
    {
        half3 crossDir = cross(viewDir, lightDir);
        // 用VdotL Power 来避免直看光源方向
        half3 ssLightDir = SafeNormalize(lerp(cross(crossDir, viewDir), half3(0,1,0), outToonData.VdotL * outToonData.VdotL * outToonData.VdotL * outToonData.VdotL));
        //half3 ssLightDir = cross(viewDir, crossDir);
        outToonData.SSNdotL = dot(normalDir, ssLightDir);
    }

    outToonData.clampedLightColor = ClampLightIntensity();

    #if !defined(_Mode_Kajiya_Kay)
    // 计算SDF
    UNITY_BRANCH
    if(_ToonUseSdfFace)
    {
        half2 sdfSampleUV = half2(lerp(uv.x, 1 - uv.x, _PrecomputeFaceSign),  uv.y);
        outToonData.sdf = SAMPLE_TEXTURE2D(_ToonSDFMap, sampler_ToonSDFMap, sdfSampleUV).r;
    }
    else
    {
        outToonData.sdf = 0;
    }
    #else
        outToonData.sdf = 0;
    #endif

	// 初始化主光源影子信息，到计算光照的时候传进去
	outToonData.mainLightAtten = 1;

	// 淡化颜色
	half paleAmbientColor = dot(inputData.bakedGI.rgb, float3(0.2126, 0.7152, 0.0722));
	inputData.bakedGI.rgb = lerp(inputData.bakedGI.rgb, paleAmbientColor.rrr, _ToonAmbientColorFale);

    return outToonData;
}



//--------------------------------
// Toon Effect
//--------------------------------

half4 ApplyRimLight(half4 color,  half NdotV, half NdotL, half mask)
{
    // 跳过Stencil 阴影
    #ifndef _SHADOWAREA
        half rim = saturate(((1 - abs(NdotV)) * (NdotL + 0.2) - _RimlightCutPosition ) * _RimlightSharpness );  // abs(NoV)是为了解决去掉vface之后出现的大面积边缘光
        rim *= lerp(1, mask, _RimLightUseMask) * _RimlightColor.a;
        //half3 rimColor = rim * _RimlightColor.rgb * rimMask;
        half3 lightColor = lerp(1, _MainLightColor.rgb, _RimLightMultiplyLightColor);
        half3 blendRimColor = lerp(color.rgb, _RimlightColor.rgb * lightColor, rim);
        half3 additiveRimColor = color.rgb + _RimlightColor.rgb * rim * lightColor;

        color.rgb = lerp(blendRimColor, additiveRimColor, _RimlightBlendToAdditive);
    #endif

    return color;
}

half4 ApplyRimLightDark(half4 color,  half NdotV, half NdotL, half mask)
{
    //half rim = saturate(((1 - NdotV) * (-NdotL + 0.2) - _RimlightDarkCutPosition ) * _RimlightDarkSharpness );
    half rim = saturate(((1 - NdotV) * lerp(1, (-NdotL + 0.2), _RimlightDirectivity) - _RimlightDarkCutPosition ) * _RimlightDarkSharpness );
    rim *= lerp(1, mask, _RimLightDarkUseMask) * _RimlightDarkColor.a;
    half3 lightColor = lerp(1, _MainLightColor.rgb, _RimLightMultiplyLightColor);
    //half3 rimColor = rim * _RimlightColor.rgb * rimMask;
    UNITY_BRANCH
    if (_RimLightDarkType < 0.5)
    {
        half3 additiveRimColor = color.rgb + _RimlightDarkColor.rgb * rim * lightColor;
        color.rgb = additiveRimColor;
    }
    else if (_RimLightDarkType < 1.5)                     //#elif defined(BACKRIM_MULTIPLY)
    {
        half3 multiplyRimColor = color.rgb * lerp(1, _RimlightDarkColor.rgb, rim);
        color.rgb = multiplyRimColor;
    }
    else
    {
        half3 blendRimColor = lerp(color.rgb, _RimlightDarkColor.rgb * lightColor, rim);
        color.rgb = blendRimColor;
    }

    //color.rgb = lerp(blendRimColor, additiveRimColor, _RimlightDarkBlendToAdditive);

    return color;
}



half4 ApplyToonEffect(half4 color, ToonData toonData)
{

    // 这里用屏幕空间代替世界空间光源方向
    color = ApplyRimLight(color, toonData.NdotV, toonData.SSNdotL, toonData.rimMask);
    color = ApplyRimLightDark(color, toonData.NdotV, toonData.SSNdotL, toonData.rimMask);



    return color;
}

half4 ApplyToonGameDynamicEffect(half4 color, ToonData toonData)
{
    #if defined(ENABLE_OVERRIDERIMLIGHT)
    half overrideColorIntensity = saturate(1 - toonData.NdotV + _DynamicOverrideRimBase) * _DynamicOverrideRimColor.a;
    color.rgb = lerp(color.rgb, _DynamicOverrideRimColor.rgb, overrideColorIntensity);

    #endif

    return color;
}

#else
// _TOON_ATHENA
struct ToonData

{

};

#endif
// _TOON_ATHENA

#endif
