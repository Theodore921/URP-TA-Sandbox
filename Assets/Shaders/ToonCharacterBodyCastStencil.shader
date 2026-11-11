Shader "Athena/Toon/Character Body Cast Stencil Shadow（废弃）"
{
    Properties
    {
        // Specular vs Metallic workflow
        [HideInInspector] _WorkflowMode("WorkflowMode", Float) = 1.0

        [MainColor] _BaseColor("Color", Color) = (0.5,0.5,0.5,1)
        [MainTexture] _BaseMap("Base Color", 2D) = "white" {}

		[NoScaleOffset]_DarkMap("Dark Map", 2D) = "black"{}
        _DarkColor("Dark Color Tint", Color) = (0.5,0.5,0.5,1)

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        [Header(Dither)]
        _DitherAlpha("Dither Alpha", Range(0,1)) = 1

		[Header(Toon)]
        _ToonDiffuseIntensity("Toon Diffuse Intensity", Range(0,1)) = 0.9
		_ToonCutLocation("Toon Cut Location", Range(0,1)) = 0.5
        _ToonCutLocationFaceLight("Toon Cut Location FL", Range(-1,1)) = 0
        _ToonCutLocationBackLight("Toon Cut Location BL", Range(-1,1)) = 0
		_ToonCutSharpness("Toon Cut Sharpness", Range(1, 100)) = 10

        // 是否使用SDF 脸部算法
        _ToonUseSdfFace("Toon Use SDF Face", Int) = 0
        _ToonSDFMap("Toon SDF Map", 2D) = "white" {}
        _ToonSDFOffset("SDF 边缘偏移", Range(-1, 1)) = 0
        _ToonSDFOffsetFront("SDF 正面偏移", Range(-1, 1)) = 0
        _ToonSDFBlur("SDF 柔化", Range(0,1)) = 0

        // 预计算
        //_Precompute("预计算", int) = 0
        _PrecomputeArccosine("输入反余弦", float) = 0
        _PrecomputeFaceSign("输入方向", float) = 0

        [Toggle(USE_RAMP)]_UseRamp("Use Ramp", Int) = 0
        [NoScaleOffset]_RampMap("Ramp Texture", 2D) = "white" {}
        _ToonLightHeight("Toon Light Height", Range(-0.99,0.99)) = 0.5
        _ToonLightHeightClamp("Toon Light Height Lerp", Range(0,1)) = 0
        _ToonShadowLocalBias("Toon Shadow Local Bias", Range(0,1.5)) = 0.02
        _ToonLightLimit("Toon Light Limit", Range(1,3)) = 1.2

        _ToonDiffuseIntensityAdditional("Toon Diffuse Intensity(A)", Range(0,1)) = 1
        _ToonCutLocationAdditional("Toon Cut Location(A)", Range(0,1)) = 0.5
		_ToonCutSharpnessAdditional("Toon Cut Sharpness(A)", Range(1, 100)) = 10

		[NoScaleOffset]_MixedToonMap("GradeMap(R) RimMask(G) ", 2D) = "gray" {}

        [Header(ToonSkin)]
        _SkinFactor("Rim Skin Factor", Range(0,2)) = 0
        _SkinOverrideColor("Skin Override Color", Color) = (1,1,1,0)
        _SkinColorBoost("Skin Color Boost", Range(1,2)) = 1

        [Header(ToonMatcap)]
        [Toggle(USE_MATCAP)]_ToonMatcap("Use Matcap", Int) = 0
        _MatcapNormalScale("Matcap Normal Scale", Range(0,5)) = 1
        [Toggle]_MatcapIsOrtho("Matcap Is Orthogonal", Int) = 0
        //_MatcapNormalIntensity("Matcap Use Detail Normal", Range(0,1)) = 1
        _MatcapNormalTex("Matcap Detail Normal", 2D) = "bump" {}
        [NoScaleOffset]_MatcapTex("Matcap Texture", 2D) = "black"{}
        _MatcapOffset("Matcap Offset", Range(0,1)) = 0.35
        _MatcapDarkIntensity("Matcap Intensity In Dark", Range(0,1)) = 0.5
        _MatcapTint("Matcap Tint", Color) = (1,1,1,1)

		[Header(ToonRim)]
		_RimlightCutPosition("Rim CutPosition",Range(0, 1)) = 0.7
		_RimlightSharpness("Rim Sharpness", Range(1, 100)) = 10
		_RimlightDarkCutPosition("Rim Dark CutPosition",Range(0, 1)) = 0.7
		_RimlightDarkSharpness("Rim Dark Sharpness", Range(1, 100)) = 10
        [Toggle]_RimlightUseScreenSpaceDirection("Rim Use Screen Space Dir", Int) = 0
        _RimlightDirectivity("Rim Dark Directivity", Range(0,1)) = 1

        _RimLightDarkType("Rim Dark Blendmode", Float) = 0
		[HDR]_RimlightColor("Rim Color", Color) = (1,1,1,1)
		[HDR]_RimlightDarkColor("Rim Dark Color", Color) = (1,1,1,1)
		_RimlightBlendToAdditive("Rim Blend or Additive", Range(0,1)) = 1
		//_RimlightDarkBlendToAdditive("Rim Dark Blend to Additive", Range(0,1)) = 1
		_RimLightUseMask("Rim Use Mask", Range(0,1)) = 1
		_RimLightDarkUseMask("Rim Dark Use Mask", Range(0,1)) = 1
		_RimLightMultiplyLightColor("Rim Use Light Color", Range(0,1)) = 1

		[Header(PBR)]
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        //_GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
        //_SmoothnessTextureChannel("Smoothness texture channel", Float) = 0

        [HideInInspector] [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        [NoScaleOffset]_MetallicGlossMap("Metallic Gloss Map", 2D) = "black" {}

        //_SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
        //_SpecGlossMap("Specular", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        _BumpScale("Normal Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion Map", 2D) = "white" {}

        _EmissionColor("Emission Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

		[Header(Edge)]
        [KeywordEnum(Normal, ColorOS, ColorTS, UV1TS, UV2TS)]_EdgeNormal("Edge Normal Source", Float) = 0
        [Toggle(USE_EDGETEXTUREMASK)]_EdgeUseTextureMask("Edge Use Texture Mask", Int) = 0
        [NoScaleOffset]_EdgeTextureMask("Edge Texture Mask", 2D) = "white" {}
        [HDR]_EdgeColor ("Edge Color Override", Color) = (0, 0, 0, 0)
		_EdgeThickness ("Edge Thickness", Range(0, 5)) = 0.1
		_EdgeZOffset ("Edge Z Offset", Range(-1, 1)) = 0
        [Toggle]_EdgeAlphaAffectZOffset("Edge Z Offset by Alpha", Float) = 0
		_EdgeFarDistance ("Edge Far Distance", Float) = 100

        [Toggle(ENABLE_INNER_LINE)]_EnabledInnerLine("Enable Inner Line", Int) = 0
        _EdgeInnerSmooth("Edge Inner Smooth Factor", Range(0.01, 4)) = 0.6
        _EdgeInnerOffset("Edge Inner Offset", Range(-1, 1)) = 0
        _EdgeInnerRange("Edge Inner Range", Range(0, 2)) = 1
        [Toggle]_EdgeInnerAlphaAffect("Edge Inner Alpha Affect", Float) = 1

        //Toon Stencil Shadow
        _StencilShadowOffset("Stencil Shadow Offset", Range(0.1, 3)) = 1
        _StencilShadowZOffset("Stencil Shadow Z Offset", Range(-1, 1)) = -0.1

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
        _DissolveBackDarknessThreshold("Dissolve Threshold", range(0, 1)) = 0.2
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
        [HideInInspector] _StencilShadowOffset("Stencil Shadow Offset", Range(0.1, 3)) = 1
        [HideInInspector] _StencilShadowZOffset("Stencil Shadow Z Offset", Range(-1, 1)) = -0.1
    }

    SubShader
    {
        // Universal Pipeline tag is required. If Universal render pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Universal Render Pipeline and Builtin Unity Pipeline
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}
        LOD 300

        // ------------------------------------------------------------------
        //  Forward pass. Shades all light in a single pass. GI + emission + Fog
        UsePass "Athena/Toon/Character Body/ForwardLit"

		UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassOutline"

        UsePass "Athena/Toon/Character Body/ShadowCaster"

		UsePass "Athena/Toon/Character Body/DepthOnly"

        UsePass "Hidden/Athena/Toon/StencilPasses/SelfShadowStencil"

        UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassToonHardRim"

		// This pass it not used during regular rendering, only for lightmap baking.
		//UsePass "Universal Render Pipeline/Lit/Meta"

    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "Athena.AthenaToonGUI"
}
