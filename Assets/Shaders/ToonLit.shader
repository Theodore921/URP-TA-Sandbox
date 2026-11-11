Shader "Athena/Toon/Lit With Edge"
{
    Properties
    {
        // Specular vs Metallic workflow
        [HideInInspector] _WorkflowMode("WorkflowMode", Float) = 1.0

        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _DitherAlpha("Dither Alpha", Range(0,1)) = 1

        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
        _SmoothnessTextureChannel("Smoothness texture channel", Float) = 0

        [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        _SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
        _SpecGlossMap("Specular", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

        [Header(Edge)]
        [KeywordEnum(Normal, ColorOS, ColorTS, UV1TS, UV2TS)]_EdgeNormal("Edge Normal Source", Float) = 0
        [Toggle(USE_EDGETEXTUREMASK)]_EdgeUseTextureMask("Edge Use Texture Mask", Int) = 0
        [NoScaleOffset]_EdgeTextureMask("Edge Texture Mask", 2D) = "white" {}
        _EdgeColor ("Edge Color Override", Color) = (0, 0, 0, 0)
		_EdgeThickness ("Edge Thickness", Range(0, 5)) = 0.1
		_EdgeZOffset ("Edge Z Offset", Range(-1, 1)) = 0
        [Toggle]_EdgeAlphaAffectZOffset("Edge Z Offset by Alpha", Float) = 0
		_EdgeFarDistance ("Edge Far Distance", Float) = 100

        //chencan: depth based rim
        [Header(ToonHardRim)]
        _HardRimColor("Rim Color", Color) = (1, 1, 1, 1)
        _HardRimInt("Rim Intensity", float) = 1//
        _HardRimIntNormalDown("Rim Intensity multiplier when normal y is -1", float) = 0.5
        _HardRimIntNormalUp("Rim Intensity multiplier when normal y is 1", float) = 1.5
        _HardRimIntFaceLight("Rim Intensity multiplier when facing light", float) = 0.2
        _HardRimIntBackLight("Rim Intensity multiplier when not facing light", float) = 1
        _HardRimLighColBlend("Rim Color Affected by Light", Range(0, 1)) = 0.7
        _HardRimWidth("Rim Width", float) = 0.01
        _HardRimDepthThresholdBase("Depth Threshold Base", Range(0, 1)) = 0.005 //don't need to be changed much
        _HardRimFeather("Rim Feather", Range(0, 1)) = 0.8

        //chencan


        [HideInInspector] [Toggle(ENABLE_INNER_LINE)]_EnabledInnerLine("Enable Inner Line", Int) = 0
        [HideInInspector] _EdgeInnerSmooth("Edge Inner Smooth Factor", Range(0.01, 4)) = 0.6
        [HideInInspector] _EdgeInnerOffset("Edge Inner Offset", Range(-1, 1)) = 0
        [HideInInspector] _EdgeInnerRange("Edge Inner Range", Range(0, 2)) = 1
        [HideInInspector] [Toggle]_EdgeInnerAlphaAffect("Edge Inner Alpha Affect", Float) = 1

        // Blending state
        [HideInInspector] _Surface("__surface", Float) = 0.0
        [HideInInspector] _Blend("__blend", Float) = 0.0
        [HideInInspector] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _Cull("__cull", Float) = 2.0

        _ReceiveShadows("Receive Shadows", Float) = 1.0
        // Editmode props
        [HideInInspector] _QueueOffset("Queue offset", Float) = 0.0

        // ObsoleteProperties
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        [HideInInspector] _Color("Base Color", Color) = (0.5, 0.5, 0.5, 1)
        [HideInInspector] _GlossMapScale("Smoothness", Float) = 0.0
        [HideInInspector] _Glossiness("Smoothness", Float) = 0.0
        [HideInInspector] _GlossyReflections("EnvironmentReflections", Float) = 0.0
    }

    SubShader
    {
        // Universal Pipeline tag is required. If Universal render pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Universal Render Pipeline and Builtin Unity Pipeline
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}
        LOD 300

        HLSLINCLUDE

        #define _BILINEAR_FOG_OFF

        #include "Packages/com.unity.render-pipelines.universal/Athena/Runtime/ShaderLibrary/ShaderLevel.hlsl"

        ENDHLSL

        // ------------------------------------------------------------------
        //  Forward pass. Shades all light in a single pass. GI + emission + Fog
        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ALPHATEST_ON
            // #pragma shader_feature _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICSPECGLOSSMAP
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _OCCLUSIONMAP

            #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _ENVIRONMENTREFLECTIONS_OFF
            #pragma shader_feature _SPECULAR_SETUP
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // #pragma multi_compile _ _SHADOWS_SOFT
            // #define _SHADOWS_SOFT 1
            // #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE SHADOWS_SHADOWMASK SHADOWS_DISTANCE_SHADOWMASK

	        //* pwrd wangyaomin: ssao
	        //#pragma multi_compile _ _SCREEN_SPACE_OCCLUSION
            //* pwrd wangyaomin

            //#pragma multi_compile _ _CLUSTER_LIGHTING_SPECULAR_OFF _CLUSTER_LIGHTING_SPECULAR_ON

            //* pwrd majiao:  Shadow-Cache阴影 //
            //#pragma multi_compile _ SHADOW_CACHE_READ
            //#pragma multi_compile _ RT_R16 RT_SHADOWMAP
            //#pragma multi_compile _ INNER_SHADOW INNER_MIDDLE_SHADOW INNER_MIDDLE_OUTER_SHADOW
            //#pragma multi_compile _ SOFT_PCF_REGULAR SOFT_PCF_ROTATED_POISSON SOFT_ESM
            //#pragma multi_compile _ MERGE_SHADOWMASK

            //#if defined(SHADOW_CACHE_READ) && defined(MERGE_SHADOWMASK)
            //    #define SHADOW_CACHE_MERGE_SHADOWMASK
            //#endif
            //* pwrd majiao //

            // -------------------------------------
            // Unity defined keywords
            // #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            //#pragma multi_compile_fog
            //--------------------------------------
            // GPU Instancing
            // #pragma multi_compile_instancing

            #define _TOON_ATHENA_EDGE 1

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitForwardPass.hlsl"

          	//* pwrd xuke Debug Window
            #pragma shader_feature _ DEBUG_DISPLAY
            #pragma shader_feature _ LIGHTING_DEBUG
            //* pwrd xuke

            //* pwrd zhengyiye: support Dither
            #pragma shader_feature _ ENABLE_DITHER

            //* pwrd zhanglingyun:天气系统
            // #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG //ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

            //* pwrd zhanglingyun:Skylight SH
            //#pragma multi_compile _ SKYLIGHT_SH
            //模拟AO(目前)和烘焙AO理论上应该互斥，目前没有对接，先拆开定义
            //#pragma multi_compile CALULATE_OCCLUSION_FROM_INDIRECT_LIGHT
            //* pwrd zhanglingyun

            //#pragma multi_compile  _ _BRDF_UE4_PC
            //* pwrd shenchen : shadowMask合并到lightMap的a通道
            //#pragma multi_compile _ DLDR_MERGE_SHADOWMASK DLDR_MERGE_AO

            //* pwrd zhangziaho
            //#pragma multi_compile _ _TERRAIN_BLENDING
            //* pwrd zhangziaho

            //* pwrd shenchen : 体积云投影
            //#pragma multi_compile _ ENABLE_CLOUD_SHADOW

            ENDHLSL
        }

        //UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassToonHardRim"

        UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassPBROutline"

//        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
//
//		UsePass "Universal Render Pipeline/Lit/DepthOnly"

        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON

            //--------------------------------------
            // GPU Instancing
            // #pragma multi_compile_instancing
            //#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #define _TOON_ATHENA_EDGE 1
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

			#include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #define _TOON_ATHENA_EDGE 1
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON
            //#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            // #pragma multi_compile_instancing
			#include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

		// This pass it not used during regular rendering, only for lightmap baking.
		UsePass "Universal Render Pipeline/Lit/Meta"


    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "Athena.AthenaToonGUI"
}
