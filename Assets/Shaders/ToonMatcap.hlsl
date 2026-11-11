#ifndef ATHENA_TOON_MATCAP
#define ATHENA_TOON_MATCAP

/// 定义卡通渲染用的Matcap算法，根源上是UTS2上的Matcap算法

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "ToonDataStruct.hlsl"

#ifdef USE_MATCAP


    // 经过测试，Overlay算法会提高饱和度，造成意料之外的色带。
    //inline half OverlayPerChannel(half baseColorChannel, half blendColorChannel)
    //{
    //    half outputChannel;
    //    // 使用flatten  展平if，避免状态切换
    //    UNITY_FLATTEN
    //    if(baseColorChannel <= 0.5)
    //    {
    //        outputChannel = baseColorChannel * blendColorChannel * 2;
    //    }
    //    else
    //    {
    //        outputChannel = 1 - (1 - baseColorChannel) * (1 - blendColorChannel) * 2;
    //    }
    //    return outputChannel;
    //}

    //// 使用Overlay 算法来获得更好的混合结果
    //inline half3 OverlayBlending(half3 baseColor, half3 blendColor)
    //{
    //    half mixedR = OverlayPerChannel(baseColor.r, blendColor.r);
    //    half mixedG = OverlayPerChannel(baseColor.g, blendColor.g);
    //    half mixedB = OverlayPerChannel(baseColor.b, blendColor.b);
    //    return half3(mixedR, mixedG, mixedB);
    //}


    // Matcap 核心算法
    inline half3 CalculateMatcap(half3 matcapNormal, half3 viewWS, half diffuseIntensity, half mask)
    {
        // Calculate view space matcap normal
	    half3 normalViewSpace = mul((float3x3)UNITY_MATRIX_V, matcapNormal);

	    // Calculate matcap uv
	    half3 normalBlend_matcapUV_Detail = normalViewSpace * half3(-1,-1,1);
	    half3 normalBlend_matcapUV_Base = mul((float3x3)UNITY_MATRIX_V, viewWS).xyz * half3(-1, -1, 1) + half3(0, 0, 1);
	    half3 noSknewViewNormal = normalBlend_matcapUV_Base * dot(normalBlend_matcapUV_Base, normalBlend_matcapUV_Detail ) / normalBlend_matcapUV_Base.z - normalBlend_matcapUV_Detail;
        half2 matcapUV = lerp(noSknewViewNormal.xy, normalViewSpace.xy, _MatcapIsOrtho) * 0.5 + 0.5;

	    // Calculate pitch angle offset
	    half matcapUVOffset = viewWS.y * _MatcapOffset;
	    matcapUVOffset *= sqrt(1 - normalViewSpace.x * normalViewSpace.x);
	    matcapUV += half2(0, matcapUVOffset);

        // Sample matcap and calculate matcap color
        half4 sampledMatcap = SAMPLE_TEXTURE2D(_MatcapTex, sampler_MatcapTex, matcapUV);
        half  matcapIntensity = lerp( _MatcapDarkIntensity, 1, diffuseIntensity) * mask;
        half3 matcapColor = sampledMatcap.rgb * matcapIntensity * sampledMatcap.a;
	    matcapColor *= _MatcapTint.rgb * _MatcapTint.a;

        return matcapColor;
    }

    half4 ApplyMatcapColor(half4 color, InputData inputData, ToonData toonData, half2 uv)
    {
        half2 matcapNormalUV = TRANSFORM_TEX(uv, _MatcapNormalTex);
        half3 matcapDetailNormal = SampleNormal(matcapNormalUV, TEXTURE2D_ARGS(_MatcapNormalTex, sampler_MatcapNormalTex), _MatcapNormalScale);
        half3 MatcapNormalWS = mul(matcapDetailNormal, half3x3(inputData.tangentWS.xyz, inputData.binormalWS.xyz, inputData.normalWS.xyz));
        half diffuseIntensityWithShadow = min(saturate(toonData.NdotL), toonData.mainLightAtten);
        half3 matcapColor = CalculateMatcap(MatcapNormalWS, inputData.viewDirectionWS, diffuseIntensityWithShadow, toonData.matcapMask);
        //* wanghaoyu 百万,平行光强度影响matcap
        #if _LIGHTAFFECTMATCAP
        matcapColor *= lerp(1,toonData.clampedLightColor,_MatcapLightIntensity); // 用的限制后的平行光强度
        #endif
        color.rgb += matcapColor;
        //color.rgb = OverlayBlending(color.rgb, matcapColor);
        return color;
    }

#else // USE_MATCAP

    half4 ApplyMatcapColor(half4 color, InputData inputData, ToonData toonData, half2 uv)
    {
        return color;
    }

#endif // USE_MATCAP


#endif  // ATHENA_TOON_MATCAP
