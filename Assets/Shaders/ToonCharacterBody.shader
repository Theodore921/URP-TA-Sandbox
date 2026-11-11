Shader "Athena/Toon/Character Body"
{
    Properties
    {
        // Specular vs Metallic workflow
        _FillIntensity("Fill Intensity", Range(0, 1)) = 0
        _LightSaturationLimited("Light Saturation Limited", Range(0, 1)) = 1
        _DiffuseSaturationLimited("Diffuse Saturation Limited", Range(-1,1)) = 0
        [HideInInspector] _WorkflowMode("工作流选择", Float) = 1.0

        [MainColor] _BaseColor("Color", Color) = (0.5,0.5,0.5,1)
        [MainTexture] _BaseMap("基础贴图", 2D) = "white" {}

		[Header(PBR)]
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        //_GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
        //_SmoothnessTextureChannel("Smoothness texture channel", Float) = 0

        [HideInInspector] [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        [NoScaleOffset]_MetallicGlossMap("Metallic Gloss Map", 2D) = "black" {}

		[ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        _BumpScale("Normal Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion Map", 2D) = "white" {}

        _EmissionColor("Emission Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

		[NoScaleOffset]_DarkMap("Toon Dark Map", 2D) = "black"{}
        _DarkColor("Toon 暗面染色", Color) = (0.5,0.5,0.5,1)

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _DitherAlpha("Dither Alpha", Range(0,1)) = 1

		[Header(Toon)]
        _ToonDiffuseIntensity("Toon 亮面强度", Range(0,1)) = 0.9
        _VertexSHFlatten("_VertexSHFlatten", Range(0, 1)) = 0
		_ToonCutLocation("Toon 明暗交界位置", Range(0,1)) = 0.5
        _ToonCutLocationFaceLight("Toon 镜头正对 向阳面偏移", Range(-1,1)) = 0
        _ToonCutLocationBackLight("Toon 镜头背对 向阳面偏移", Range(-1,1)) = 0
		_ToonCutSharpness("Toon 明暗交界锋利度", Range(1, 100)) = 10

        // 是否使用SDF 脸部算法
        _ToonStencilMode("Toon Stencil Mode", Int) = 0
        _ToonUseSdfFace("Toon 使用SDF贴图 控制脸部", Int) = 0
        _ToonSDFMap("Toon SDF 贴图", 2D) = "white" {}
        _ToonSDFOffset("Toon SDF 边缘偏移", Range(-1, 1)) = 0
        _ToonSDFOffsetFront("Toon SDF 正面偏移", Range(-1, 1)) = 0
        _ToonSDFBlur("Toon SDF 柔化", Range(0,1)) = 0

        // 预计算
        //_Precompute("预计算", int) = 0
        _PrecomputeArccosine("SDF 输入反余弦", float) = 0
        _PrecomputeFaceSign("SDF 输入方向", float) = 0

        [Toggle(USE_RAMP)]_UseRamp("Use Ramp Texture", Int) = 0
        _RampMap("Ramp Texture", 2D) = "white" {}
        _ToonLightHeight("Toon 自定义灯光高度", Range(-0.99,0.99)) = 0.5
        _ToonLightHeightClamp("Toon 限制灯光高度", Range(0,1)) = 0
        _ToonShadowLocalBias("Toon 影子偏移量", Range(0,1.5)) = 0.02
        _ToonLightLimit("Toon 主光源强度上限", Range(1,3)) = 1.2
		_ToonAmbientColorFale("Toon 环境光颜色变淡", Range(0,1)) = 0

        //* wanghaoyu 百万,对于额外光希望不依赖法线,让角色显得更平,且需要更明确的面部SDF阴影
        [HideInInspector] _UseFlatAdditionalLight("百万专用额外光",Int) = 0   // 单纯用在GUI里增强用户体验
        _ToonAdditionalFlat("Toon 更平的额外光范围", Range(0,200)) = 1   // 更平整
        _ToonAdditionalFlatContrast("Toon 更平的额外光衰减对比度", Range(1,2)) = 1   // 越高衰减中心和边缘的强度对比会更强
        //* wanghaoyu
        _ToonDiffuseIntensityAdditional("Toon 额外光强度", Range(0,1)) = 1
        _ToonCutLocationAdditional("Toon 额外光交界位置", Range(0,1)) = 0.5
		_ToonCutSharpnessAdditional("Toon 额外光交接锋利度", Range(1, 100)) = 10

		[NoScaleOffset]_MixedToonMap("Toon Mix贴图 ", 2D) = "gray" {}

        [Header(ToonSkin)]
        _SkinFactor("Skin Factor", Range(0,2)) = 0
        _SkinOverrideColor("Skin 覆盖颜色", Color) = (1,1,1,0)
        _SkinColorBoost("Skin 颜色增强", Range(1,2)) = 1

        [Header(ToonMatcap)]
        [Toggle(USE_MATCAP)]_ToonMatcap("Use Matcap", Int) = 0
        _MatcapNormalScale("Matcap 法线强度", Range(0,5)) = 1
        [Toggle]_MatcapIsOrtho("Matcap 为正交", Int) = 0
        //_MatcapNormalIntensity("Matcap Use Detail Normal", Range(0,1)) = 1
        _MatcapNormalTex("Matcap 法线贴图", 2D) = "bump" {}
        [NoScaleOffset]_MatcapTex("Matcap 贴图", 2D) = "black"{}
        _MatcapOffset("Matcap 偏移程度", Range(0,1)) = 0.35
        _MatcapDarkIntensity("Matcap 暗部强度", Range(0,1)) = 0.5
        _MatcapTint("Matcap 色调", Color) = (1,1,1,1)
        //* wanghaoyu 百万,控制平行光强度混合
        _MatcapLightIntensity("Matcap 色调", range(0,1)) = 1

		[Header(ToonRim)]
		_RimlightCutPosition("向阳边缘光 边界位置",Range(0, 1)) = 0.7
		_RimlightSharpness("向阳边缘光 边界锋利度", Range(1, 100)) = 10
		[HDR]_RimlightColor("向阳边缘光 颜色", Color) = (1,1,1,1)
		_RimlightBlendToAdditive("混合模式： 正常或线性减淡", Range(0,1)) = 1
		_RimLightUseMask("向阳边缘光 适用蒙版", Range(0,1)) = 1

        _RimLightDarkType("背阳边缘光 混合模式", Float) = 0
		_RimlightDarkCutPosition("背阳边缘光 边界位置",Range(0, 1)) = 0.7
		_RimlightDarkSharpness("背阳边缘光 边界锋利度", Range(1, 100)) = 10
		[HDR]_RimlightDarkColor("背阳边缘光 颜色", Color) = (1,1,1,1)
		_RimLightDarkUseMask("背阳边缘光 适用蒙版", Range(0,1)) = 1

		_RimLightMultiplyLightColor("边缘光 使用阳光颜色", Range(0,1)) = 1
		[Toggle]_RimlightUseScreenSpaceDirection("使用屏幕空间 光源方向", Int) = 0
        _RimlightDirectivity("背阳边缘光 方向性", Range(0,1)) = 1

		[Header(Edge)]
        [KeywordEnum(Normal, ColorOS, ColorTS, UV1TS, UV2TS)]_EdgeNormal("描边法线来源", Float) = 0
        [Toggle(USE_EDGETEXTUREMASK)]_EdgeUseTextureMask("描边 贴图控制粗细", Int) = 0
        [NoScaleOffset]_EdgeTextureMask("描边 粗细控制贴图", 2D) = "white" {}
        [HDR]_EdgeColor ("描边 颜色混合", Color) = (0, 0, 0, 0)
		_EdgeThickness ("描边粗细", Range(0, 5)) = 0.1
		_EdgeZOffset ("描边深度偏移", Range(-1, 1)) = 0
        [Toggle]_EdgeAlphaAffectZOffset("顶点色Alpha 影响描边深度偏移", Float) = 0
		_EdgeFarDistance ("描边消失距离", Float) = 100

        [Toggle(ENABLE_INNER_LINE)]_EnabledInnerLine("启用内描边", Int) = 0
        _EdgeInnerSmooth("内描边抗锯齿参数", Range(0.01, 4)) = 0.6
        _EdgeInnerOffset("内描边 整体厚度偏移", Range(-1, 1)) = 0
        _EdgeInnerRange("内描边 厚度比例", Range(0, 2)) = 1
        _EdgeInnerAlphaAffect("顶点色ALpha 影响内描边厚度", Float) = 1

        [Header(ToonGameEffect)]
        [Toggle(USE_TOONGAMEEFFECT)]_UseToonGameEffect("Use Dynamic Game Effect", Int) = 0
        [HDR]_DynamicOverrideRimColor("Dynamic Override Rim Color", Color) = (1,1,1,1)
        _DynamicOverrideRimBase("Dynamic Override Rim Base", Range(-1,1)) = 0.3
        _DynamicEdgeColor("Dynamic Edge Color Override", Color) = (0,0,0,0)

        //liyangyuqing: Dissolve
        [Header(ToonDissolve)]
        [Toggle(DISSOLVE_ROTATION)] _DissolveRot("Dissolve With Direction", Float) = 0
        _DissolveTexture("Dissolve Texture", 2D) = "white" {}
        _NoiseTiling("Noise Texture Tiling", vector) = (1, 1, 0, 0)
        _DissolveAmount("Dissolve Amount", range(0, 1.05)) = 0
        _DissolveDistance("Dissolve Distance", Float) = 1     // zhengyiye : 增加世界空间的溶解距离
        _DissolveBackDarknessThreshold("Dissolve Threshold", range(0.05, 1)) = 0.2
        //_DissolveAmount("Dissolve Amount", float) = 0
        [HDR]_DissolveColor("Dissove Color", Color) = (1, 1, 1)
        _EdgeWidth("Edge Width", range(0, 0.1)) = 0.05
        _EdgeSmoothness("Edge Smothness", Range(0, 0.5)) = 0.1
        _StartingPivot("Starting pivot point", Vector) = (0, 0, 0, 0)
        _DirVec("Direction Vector", Vector) = (0, 0, 0, 0)
        _DissolveRange("Dissolve Range", range(0, 1)) = 0
        //liyangyuqing

        //chencan: depth based rim
        [Header(ToonHardRim)]
        _HardRimColor("Rim Color", Color) = (1, 1, 1, 1)
        _HardRimInt("Rim Intensity", float) = 0.25
        _HardRimWidth("Rim Width", float) = 0.7
        _HardRimLighColBlend("Rim Color Affected by Light", Range(0, 1)) = 0.7
        _HardRimLighIntBlend("Rim Intensity Affected by Light", Range(0, 1)) = 0
        _HardRimIntNormalUp("Rim Intensity multiplier when normal y is 1", float) = 0.5
        _HardRimIntNormalDown("Rim Intensity multiplier when normal y is -1", float) = 1.3
        _HardRimIntFaceLight("Rim Intensity multiplier when facing light", float) = 0
        _HardRimIntBackLight("Rim Intensity multiplier when not facing light", float) = 1
        _HardRimDepthThresholdBase("Depth Threshold Base", Range(0, 1)) = 4 //don't need to be changed much
        _HardRimFeather("Rim Feather", Range(0, 1)) = 0.8
        //chencan

        // Blending state
        [HideInInspector] _Surface("__surface", Float) = 0.0
        [HideInInspector] _Blend("__blend", Float) = 0.0
        [HideInInspector] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _Cull("__cull", Float) = 2.0

        [Header(Shadow)]
        _ReceiveShadows("Receive Shadows", Float) = 1.0
        // Editmode props
        [HideInInspector] _QueueOffset("Queue offset", Float) = 0.0

        // ObsoleteProperties
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        [HideInInspector] _Color("Base Color", Color) = (0.5, 0.5, 0.5, 1)
        [HideInInspector] _GlossMapScale("Smoothness", Float) = 0.0
        [HideInInspector] _Glossiness("Smoothness", Float) = 0.0
        [HideInInspector] _GlossyReflections("EnvironmentReflections", Float) = 0.0

        // SRP Batching 兼容
        [HideInInspector] _SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
        _StencilShadowOffset("Stencil Shadow Offset", Range(0.1, 3)) = 1
        _StencilShadowZOffset("Stencil Shadow Z Offset", Range(-1, 1)) = -0.1
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
            #pragma shader_feature _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE SHADOWS_SHADOWMASK SHADOWS_DISTANCE_SHADOWMASK
	        // #pragma multi_compile _ _SHADOWS_SOFT
            // #define _SHADOWS_SOFT 1

            //#pragma multi_compile _ _CLUSTER_LIGHTING_SPECULAR_OFF _CLUSTER_LIGHTING_SPECULAR_ON

            //* pwrd majiao:  Shadow-Cache阴影 //
            //#pragma shader_feature _ RT_R16 RT_SHADOWMAP
            //#pragma shader_feature _ INNER_SHADOW
            //#pragma shader_feature _ MIDDLE_SHADOW
            //#pragma shader_feature _ OUTER_SHADOW
            //#pragma shader_feature _ SOFT_PCF_REGULAR SOFT_PCF_ROTATED_POISSON SOFT_ESM
            //* pwrd majiao //

            // -------------------------------------
            // Unity defined keywords
            // #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            // #pragma multi_compile _ LIGHTMAP_ON
            //#pragma multi_compile_fog
            //--------------------------------------
            // GPU Instancing
            // #pragma multi_compile_instancing

            #pragma vertex LitPassVertexToonCharacter
            #pragma fragment LitPassFragmentToonCharacter

            //* pwrd zhanglingyun:天气系统
            // #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
            //#pragma multi_compile _ WEATHER_EFFECT //天气效果效果
            //* pwrd zhanglingyun

			//* pwrd zhengyiye: Define Toon
            #define REQUIRES_WORLD_SPACE_POS_INTERPOLATOR
			#define _TOON_ATHENA 1
            #define _TOON_ATHENA_LIGHTING 1
            #define _TOON_ATHENA_LIGHTING_ADDITIONAL 1
            #define _TOON_ATHENA_DISSOLVE 1
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
        //* wanghaoyu 干掉UsePass
        // UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassToonHardRim"
        Pass
        {
            Tags { "LightMode" = "CharacterHardRim" }

            // Name "ToonUtilityPassToonHardRim"

            ZWrite Off
            Blend One One //blending with additive, can change later

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
            // #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
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
		// UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassOutline"
        Pass
		{
            Tags { "LightMode" = "CharacterOutline" }

			// Name "ToonUtilityPassOutline"

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
            // #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
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

            #define _TOON_ATHENA 1
            #define _TOON_ATHENA_DISSOLVE 1
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

			#include "ToonConfig.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "HDShadowCaster"
            Tags{"LightMode" = "HDShadowCaster"}

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
            #pragma shader_feature _HD_SHADOW_CASTER

            #define _TOON_ATHENA 1
            #define _TOON_ATHENA_DISSOLVE 1
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

            #define _TOON_ATHENA 1
            #define _TOON_ATHENA_DISSOLVE 1
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

        // 前发投影Stencil
        // UsePass "Hidden/Athena/Toon/StencilPasses/SelfShadowStencil"
        Pass
		{
			// Name "SelfShadowStencil"
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

			#pragma prefer_hlslcc gles
			#pragma exclude_renderers d3d11_9x

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

        // UsePass "Hidden/Athena/Toon/StencilPasses/SelfShadowStencilReceive"
        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            // Name "SelfShadowStencilReceive"
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
            //#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
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
            // #pragma multi_compile _ HEIGHT_FOG _ENABLE_BILINEAR_FOG // ATMOSPHERIC_FOG_DAY ATMOSPHERIC_FOG_NIGHT
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
            #pragma multi_compile _ DEBUG_DISPLAY
            #pragma multi_compile _ LIGHTING_DEBUG
            //* pwrd xuke

            ENDHLSL
        }


        //UsePass "Universal Render Pipeline/Lit/DepthOnly"

		// This pass it not used during regular rendering, only for lightmap baking.
		//UsePass "Universal Render Pipeline/Lit/Meta"

    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "Athena.AthenaToonGUI"
}
