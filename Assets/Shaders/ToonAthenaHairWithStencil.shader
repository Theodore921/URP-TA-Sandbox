Shader "Athena/Toon/Hair Cast Stencil Shadow"
{
    Properties
    {
        // Specular vs Metallic workflow
        [HideInInspector] _WorkflowMode("工作流选择", Float) = 1.0

        [MainColor] _BaseColor("Color", Color) = (0.5,0.5,0.5,1)
        [MainTexture] _BaseMap("基础贴图", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        [Header(Dither)]
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

        [Header(Toon)]
        _ToonShadowLocalBias("Toon 影子偏移量", Range(0,1.5)) = 0.02
        _ToonLightLimit("Toon 主光源强度上限", Range(1,3)) = 1.2
        [NoScaleOffset]_MixedToonMap("Toon Mix贴图 ", 2D) = "gray" {}

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

        _EmissionStrength("Emission Strength", Range(0.0, 10.0)) = 1.0
        [Toggle] _EmissionEnabled("Emission Enabled", Int) = 0.0

        //KAJIYA_KAY
        _PrimarySpecularIntensity("Primary Intensity", Range(0, 5.0)) = 1.0
        _PrimaryExponent ("Primary Smoothness", Range(0, 1.0)) = 0.8
		_PrimaryShift ("Primary Shift", Range(-1.0, 1.0)) = 0.0
		_PrimarySpecularColor ("Primary Specualr Color", Color) = (0.2,0.2,0.2,1.0)
		_SecondSpecularIntensity("Second Intensity", Range(0, 5.0)) = 1.0
		_SecondExponent ("Second Smoothness", Range(0, 1.0)) = 0.6
		_SecondShift ("Second Shift", Range(-1.0, 1.0)) = 0.0
		_SecondSpecularColor ("Second Specualr Color", Color) = (0.2,0.2,0.3,1.0)
		[NoScaleOffset] _AnisoShiftMap ("Anisotropic Shift Map", 2D) = "grey" {}
		_AnisoShiftIntensity ("Anisotropic Shift Intensity", Range(0, 2)) = 1.0
		_AnisoShiftTiling ("Anisotropic Shift Tiling", Range(0, 15)) = 1.0
		_TangentMap ("Tangent Map", 2D) = "grey" {}
        //* pwrd zhengyiye
        _KajiyaKayBackLightIntensity("Kajiya-Kay的高光的背光面强度", Range(0,1)) = 0
        //* pwrd zhengyiye

   		//Bent Normal
   		_BentNormalMap("Bent Normal Map", 2D) = "bump" {}

        [Header(ToonSkin)]
        _SkinFactor("Rim Skin Factor", Range(0,2)) = 0
        _SkinOverrideColor("Skin Override Color", Color) = (1,1,1,0)
        _SkinColorBoost("Skin Color Boost", Range(1,2)) = 1

        //Toon Edge
        [Header(Edge)]
        [KeywordEnum(Normal, ColorOS, ColorTS, UV1TS, UV2TS)]_EdgeNormal("描边法线来源", Float) = 0
        [Toggle(USE_EDGETEXTUREMASK)]_EdgeUseTextureMask("描边 贴图控制粗细", Int) = 0
        [NoScaleOffset]_EdgeTextureMask("描边 粗细控制贴图", 2D) = "white" {}
        [HDR]_EdgeColor ("描边 颜色混合", Color) = (0, 0, 0, 0)
		_EdgeThickness ("描边粗细", Range(0, 5)) = 0.1
		_EdgeZOffset ("描边深度偏移", Range(-1, 1)) = 0
        [Toggle]_EdgeAlphaAffectZOffset("顶点色Alpha 影响描边深度偏移", Float) = 0
		_EdgeFarDistance ("描边消失距离", Float) = 100

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

        // Hidden For SRP Batcher
        [HideInInspector]_ToonLightHeight("Toon 自定义灯光高度", Range(-0.99,0.99)) = 0.5
        [HideInInspector]_ToonLightHeightClamp("Toon 限制灯光高度", Range(0,1)) = 0

        [HideInInspector] [Toggle(ENABLE_INNER_LINE)]_EnabledInnerLine("Enable Inner Line", Int) = 0
        [HideInInspector] _EdgeInnerSmooth("Edge Inner Smooth Factor", Range(0.01, 4)) = 0.6
        [HideInInspector] _EdgeInnerOffset("Edge Inner Offset", Range(-1, 1)) = 0
        [HideInInspector] _EdgeInnerRange("Edge Inner Range", Range(0, 2)) = 1
        [HideInInspector] [Toggle]_EdgeInnerAlphaAffect("Edge Inner Alpha Affect", Float) = 1

   		//Debug
   		[Toggle] _Direct_Diffuse ("Direct Diffuse", Float) = 1.0
        [Toggle] _Direct_Specular ("Direct Specular", Float) = 1.0
        [Toggle] _Indirect_Diffuse ("Indirect Diffuse", Float) = 1.0
        [Toggle] _Indirect_Specular ("Indirect Specular", Float) = 1.0
    }

    SubShader
    {
        // Universal Pipeline tag is required. If Universal render pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Universal Render Pipeline and Builtin Unity Pipeline
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"}
        LOD 300

        UsePass "Athena/Toon/Hair/ForwardLitToonHair"

        UsePass "Athena/Toon/Hair/ForwardLitToonHairTransparent"

      //UsePass "Athena/Hair/HairDepth"
        UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassToonHardRimHair"

        UsePass "Hidden/Athena/Toon/UtilityPasses/ToonUtilityPassHairOutline"

        UsePass "Athena/Toon/Hair/ShadowCaster"

		UsePass "Athena/Toon/Hair/DepthOnly"

        UsePass "Hidden/Athena/Toon/StencilPasses/SelfShadowStencilHair"

		// This pass it not used during regular rendering, only for lightmap baking.
		//UsePass "Athena/Hair/Meta"
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "Athena.AthenaHairGUI"
}
