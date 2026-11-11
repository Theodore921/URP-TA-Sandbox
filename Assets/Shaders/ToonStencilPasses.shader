/// 这个shader用于管理Stencil相关的shader
/// 用到的是屏幕空间前发投影。


Shader "Hidden/Athena/Toon/StencilPasses"
{
    Properties
    {

    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}
        LOD 100

        Pass
		{
			Name "SelfShadowStencil"
			Tags { "LightMode" = "SelfShadowStencil" }

			ZWrite Off
            Cull [_Cull]

			Stencil
			{
				Ref 2
				Pass Replace
			}

			ColorMask 0

			HLSLPROGRAM

            #define _TOON_ATHENA 1
			#define _TOON_ATHENA_DISSOLVE 1

			#pragma vertex forwardVertStencilCast
			#pragma fragment forwardFragStencilCast

			#include "ToonConfig.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "ToonStencil.hlsl"

			ENDHLSL
		}

        // 头发使用的版本，需要支持 kajiya_Kay 来支持SRP Batcher
        Pass
		{
			Name "SelfShadowStencilHair"
			Tags { "LightMode" = "SelfShadowStencil" }

			ZWrite Off
            Cull [_Cull]

			Stencil
			{
				Ref 2
				Pass Replace
			}

			ColorMask 0

			HLSLPROGRAM

            #define _TOON_ATHENA 1
			#define _Mode_Kajiya_Kay 1
			#define _TOON_ATHENA_DISSOLVE 1

			#pragma vertex forwardVertStencilCast
			#pragma fragment forwardFragStencilCast

			#include "ToonConfig.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "ToonStencil.hlsl"

			ENDHLSL
		}

        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            Name "SelfShadowStencilReceive"
            Tags{"LightMode" = "SelfShadowStencilReceive"}

            Blend[_SrcBlend][_DstBlend]
            ZWrite Off
            Cull[_Cull]

            Stencil
			{
				Ref 2
				Comp Equal
                Pass Zero
			}

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
			// zhengyiye: 使用了3.5以获得更好的性能
            #pragma target 3.5

            // -------------------------------------
            // Material Keywords
            //#pragma shader_feature _NORMALMAP
            #define _NORMALMAP 1
            #pragma shader_feature _ALPHATEST_ON
            // #pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            //#pragma shader_feature _METALLICSPECGLOSSMAP
            #define _METALLICSPECGLOSSMAP
            //#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            //#pragma shader_feature _OCCLUSIONMAP
            #define _OCCLUSIONMAP

            #pragma shader_feature_local DISSOLVE_ROTATION
            #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _ENVIRONMENTREFLECTIONS_OFF
            //#pragma shader_feature _SPECULAR_SETUP
            //#pragma shader_feature _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Pipeline keywords
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            //#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            // 脸部接收的投影也要和脸自身的着色计算一致，把附加光也考虑在内
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            //#pragma multi_compile _ _SHADOWS_SOFT
            //#pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            //* pwrd majiao:  Shadow-Cache阴影 //
            //#pragma shader_feature _ RT_R16 RT_SHADOWMAP
            //#pragma shader_feature _ INNER_SHADOW
            //#pragma shader_feature _ MIDDLE_SHADOW
            //#pragma shader_feature _ OUTER_SHADOW
            //#pragma shader_feature _ SOFT_PCF_REGULAR SOFT_PCF_ROTATED_POISSON SOFT_ESM
            //* pwrd majiao //

            // -------------------------------------
            // Unity defined keywords
            //#pragma multi_compile _ DIRLIGHTMAP_COMBINED
            //#pragma multi_compile _ LIGHTMAP_ON
            // #pragma multi_compile_fog
            //--------------------------------------
            // GPU Instancing
            // #pragma multi_compile_instancing

            //* pwrd zhanglingyun:天气系统
            #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

            #pragma vertex LitPassVertexToonCharacter
            #pragma fragment LitPassFragmentToonCharacter

			//* pwrd zhengyiye: Define Toon
            #define REQUIRES_WORLD_SPACE_POS_INTERPOLATOR
			#define _TOON_ATHENA 1
            #define _TOON_ATHENA_LIGHTING 1
            #define _TOON_ATHENA_LIGHTING_ADDITIONAL 1
            #define _TOON_ATHENA_DISSOLVE 1
            #define _SHADOWAREA
            #pragma shader_feature_local _ USE_RAMP
            #pragma shader_feature_local _ USE_DARKMAP
            #pragma shader_feature_local _ USE_MATCAP
            #pragma shader_feature_local _ ENABLE_INNER_LINE
            #pragma multi_compile_local _ USE_TOONGAMEEFFECT
            #include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "ToonCharacterLitPass.hlsl"

          	//* pwrd xuke
            #pragma shader_feature _ DEBUG_DISPLAY
            #pragma shader_feature _ LIGHTING_DEBUG
            //* pwrd xuke

            ENDHLSL
        }
    }
}
