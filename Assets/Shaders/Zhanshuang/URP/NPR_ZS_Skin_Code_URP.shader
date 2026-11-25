Shader "NPR/URP/NPR_ZS_Skin_Code"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _RampMap ("_RampMap", 2D) = "white" {}
        _LightMap ("_LightMap", 2D) = "black" {}
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Range(0, 1)) = 0.5
        _BrightIntensity ("_BrightIntensity", Float) = 1
        [Space(10)]
        _RimIntensity ("_RimScale", Float) = 1
        _RimWdith ("_RimWdith", Float) = 0.3
        [Space(30)]
        _OulineScale ("_OulineScale", Float) = 1
        _OutlineColor ("_OutlineColor", Color) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex SkinVert
            #pragma fragment SkinFrag
            #pragma shader_feature_local MODE_VALUE MODE_TEX
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _RimIntensity;
                float _RimWdith;
                float _OulineScale;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_RampMap);
            SAMPLER(sampler_RampMap);
            TEXTURE2D(_LightMap);
            SAMPLER(sampler_LightMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };

            Varyings SkinVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            float4 SkinFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float nl01 = dot(normalWS, lightDirection) * 0.5 + 0.5;
                float nv = dot(normalWS, viewDirection);
                float3 baseMap = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).rgb;
                float3 rimLight = step(nv, _RimWdith) * _RimIntensity * baseMap;
                float4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, input.uv);
                float shadowAo = lightMap.g > 0.001 ? 1.0 : 0.0;
                float2 rampUv = float2((_RampOffset + nl01) * shadowAo, 0.5);
                float3 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, rampUv).rgb;
                float3 diffuse = lerp(
                    baseMap * _DarkIntensity,
                    baseMap * _BrightIntensity,
                    ramp);
                return float4(diffuse + rimLight, 0.0) * 1.2;
            }
            ENDHLSL
        }

        UsePass "NPR/NPR_ZS_PBR_URP/NORMAL"
    }
    Fallback Off
}
