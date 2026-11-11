Shader "Hidden/Athena/Toon/UtilityPasses"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

         // Pass - Outline
        Pass
		{
			Tags
			{
				"LightMode" = "CharacterOutline"
			}

			Name "ToonUtilityPassOutline"

			Cull   Front
			ZTest  Less
			ZWrite On

			//Stencil
			//{
			//	Ref  6
			//	Comp Always
			//	Pass Replace
			//}

			HLSLPROGRAM

			#pragma target 3.5
			// #pragma multi_compile_fog
			#pragma multi_compile_fwdbase
			// #pragma multi_compile_instancing

			#pragma multi_compile_local _ USE_TOONGAMEEFFECT
			//#pragma shader_feature ENABLE_DISSOLVE
			//#define ENABLE_DISSOLVE 1
			#pragma shader_feature_local DISSOLVE_ROTATION
			//#pragma shader_feature ENABLE_DITHER
			//#pragma shader_feature ENABLE_OBSCURED
			#pragma shader_feature _ _ALPHATEST_ON

            //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

			#pragma vertex   URPToonEdgeVert
			#pragma fragment URPToonEdgeFrag

			#define _TOON_ATHENA 1
			#define _TOON_ATHENA_DISSOLVE 1
            #pragma shader_feature_local _EDGENORMAL_NORMAL _EDGENORMAL_COLOROS _EDGENORMAL_COLORTS _EDGENORMAL_UV1TS _EDGENORMAL_UV2TS
			#pragma shader_feature_local _ USE_EDGETEXTUREMASK

			#include "ToonConfig.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "ToonCharacterEdgePass.hlsl"

			ENDHLSL
		}

         // Pass - Outline For Hair
        Pass
		{
			Tags
			{
				"LightMode" = "CharacterOutline"
			}

			Name "ToonUtilityPassHairOutline"

			Cull   Front
			ZTest  Less
			ZWrite On

			//Stencil
			//{
			//	Ref  6
			//	Comp Always
			//	Pass Replace
			//}

			HLSLPROGRAM

			#pragma target 3.5
			// #pragma multi_compile_fog
			#pragma multi_compile_fwdbase
			// #pragma multi_compile_instancing

			#pragma multi_compile_local _ USE_TOONGAMEEFFECT
			//#pragma shader_feature ENABLE_DISSOLVE
			//#define ENABLE_DISSOLVE 1
			#pragma shader_feature_local DISSOLVE_ROTATION
			//#pragma shader_feature ENABLE_DITHER
			//#pragma shader_feature ENABLE_OBSCURED
			#pragma shader_feature _ _ALPHATEST_ON

            //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

			#pragma vertex   URPToonEdgeVert
			#pragma fragment URPToonEdgeFrag

			#define _TOON_ATHENA 1
			#define _Mode_Kajiya_Kay 1
			#define _TOON_ATHENA_DISSOLVE 1
            #pragma shader_feature_local _EDGENORMAL_NORMAL _EDGENORMAL_COLOROS _EDGENORMAL_COLORTS _EDGENORMAL_UV1TS _EDGENORMAL_UV2TS
			#pragma shader_feature_local _ USE_EDGETEXTUREMASK

			#include "ToonConfig.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "ToonCharacterEdgePass.hlsl"

			ENDHLSL
		}

        // Pass - Outline For PBR
        Pass
		{
			Tags
			{
				"LightMode" = "CharacterOutline"
			}

			Name "ToonUtilityPassPBROutline"

			Cull   Front
			ZTest  Less
			ZWrite On

			//Stencil
			//{
			//	Ref  6
			//	Comp Always
			//	Pass Replace
			//}

			HLSLPROGRAM

			#pragma target 3.5
			#pragma multi_compile_fog
			#pragma multi_compile_fwdbase
			// #pragma multi_compile_instancing

			#pragma multi_compile_local _ USE_TOONGAMEEFFECT
			//#pragma shader_feature ENABLE_DISSOLVE
			//#define ENABLE_DISSOLVE 1
			#pragma shader_feature_local DISSOLVE_ROTATION
			//#pragma shader_feature ENABLE_DITHER
			//#pragma shader_feature ENABLE_OBSCURED
			#pragma shader_feature _ _ALPHATEST_ON

            //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

			#pragma vertex   URPToonEdgeVert
			#pragma fragment URPToonEdgeFrag

			#define _TOON_ATHENA_EDGE 1
            #pragma shader_feature_local _EDGENORMAL_NORMAL _EDGENORMAL_COLOROS _EDGENORMAL_COLORTS _EDGENORMAL_UV1TS _EDGENORMAL_UV2TS
			#pragma shader_feature_local _ USE_EDGETEXTUREMASK

			#include "ToonConfig.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "ToonCharacterEdgePass.hlsl"

			ENDHLSL
		}

        Pass
        {
            Tags
        {
            "LightMode" = "CharacterHardRim"
        }

            Name "ToonUtilityPassToonHardRim"

            ZWrite Off
            Blend One One //blending with additive, can change later

            HLSLPROGRAM

            #pragma target 3.5
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            // #pragma multi_compile_instancing

            #pragma multi_compile_local _ USE_TOONGAMEEFFECT
                        //#pragma shader_feature ENABLE_DISSOLVE
                        //#define ENABLE_DISSOLVE 1
            #pragma shader_feature_local DISSOLVE_ROTATION
                        //#pragma shader_feature ENABLE_DITHER
                        //#pragma shader_feature ENABLE_OBSCURED
            #pragma shader_feature _ _ALPHATEST_ON

                        //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
                        //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
                        //* pwrd zhanglingyun

            #pragma vertex   URPToonHardRimVert
            #pragma fragment URPToonHardRimFrag

            #define _TOON_ATHENA 1
            #define _TOON_ATHENA_DISSOLVE 1
            //#pragma shader_feature_local _EDGENORMAL_NORMAL _EDGENORMAL_COLOROS _EDGENORMAL_COLORTS _EDGENORMAL_UV1TS _EDGENORMAL_UV2TS

            //#pragma shader_feature _HARDRIMMODE_HORIZONTAL _HARDRIMMODE_FACELIGHT

            #include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "ToonCharacterHardRimPass.hlsl"

            ENDHLSL
        }

        // 头发专用
        Pass
        {
            Tags
        {
            "LightMode" = "CharacterHardRim"
        }

            Name "ToonUtilityPassToonHardRimHair"

            ZWrite Off
            Blend One One //blending with additive, can change later

            HLSLPROGRAM

            #pragma target 3.5
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            // #pragma multi_compile_instancing

            #pragma multi_compile_local _ USE_TOONGAMEEFFECT
                        //#pragma shader_feature ENABLE_DISSOLVE
                        //#define ENABLE_DISSOLVE 1
            #pragma shader_feature_local DISSOLVE_ROTATION
                        //#pragma shader_feature ENABLE_DITHER
                        //#pragma shader_feature ENABLE_OBSCURED
            #pragma shader_feature _ _ALPHATEST_ON

                        //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
                        //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
                        //* pwrd zhanglingyun

            #pragma vertex   URPToonHardRimVert
            #pragma fragment URPToonHardRimFrag

            #define _TOON_ATHENA 1
            #define _Mode_Kajiya_Kay 1
            #define _TOON_ATHENA_DISSOLVE 1
            //#pragma shader_feature _EDGENORMAL_NORMAL _EDGENORMAL_COLOROS _EDGENORMAL_COLORTS _EDGENORMAL_UV1TS _EDGENORMAL_UV2TS

            //#pragma shader_feature _HARDRIMMODE_HORIZONTAL _HARDRIMMODE_FACELIGHT

            #include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "ToonCharacterHardRimPass.hlsl"

            ENDHLSL
        }
    }
}
