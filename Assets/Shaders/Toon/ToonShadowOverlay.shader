// 角色局部阴影叠加（发影 / 眼影 / 眼白阴影）
// 这类贴片在模型里是独立 submesh，贴图是一张极小的灰度遮罩（32x32），
// 用半透明叠加到脸上即可，不参与光照。
Shader "Custom/ToonShadowOverlay"
{
    Properties
    {
        [NoScaleOffset]_BaseMap ("Shadow Mask", 2D) = "white" {}
        [HDR]_ShadowColor ("Shadow Color", Color) = (0.32,0.34,0.45,1)
        _Strength ("Strength", Range(0,2)) = 1
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent-10"
        }

        Pass
        {
            Name "ShadowOverlay"
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull [_Cull]
            Offset -1, -1

            HLSLPROGRAM
            #pragma vertex OverlayVert
            #pragma fragment OverlayFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _ShadowColor;
                float _Strength;
                float _Cull;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings OverlayVert(Attributes input)
            {
                Varyings o = (Varyings)0;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = input.uv;
                return o;
            }

            float4 OverlayFrag(Varyings input) : SV_Target
            {
                float mask = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).r;
                float a = saturate(mask * _Strength) * _ShadowColor.a;
                return float4(_ShadowColor.rgb, a);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
