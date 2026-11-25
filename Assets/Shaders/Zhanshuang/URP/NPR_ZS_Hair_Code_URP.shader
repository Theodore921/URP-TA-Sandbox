Shader "NPR/URP/NPR_ZS_Hair_Code"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _LightMap ("_LightMap", 2D) = "black" {}
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Range(0, 1)) = 0.5
        _BrightIntensity ("_BrightIntensity", Float) = 1
        [Space(10)]
        _HairSpecularExp ("_HairSpecularExp", Float) = 1
        _HairSpecularIntensity ("_HairSpecularIntensity", Float) = 1
        [Space(10)]
        _RimIntensity ("_RimScale", Float) = 1
        _RimWdith ("_RimStep", Float) = 0.3
        [Space(30)]
        _OulineScale ("_OulineScale", Float) = 1
        _OutlineColor ("_OutlineColor", Color) = (0, 0, 0, 0)
        [Space(30)]
        _SpecularRange ("_SpecularRange", Range(0, 5)) = 1
        _SpecularIntensity ("_SpecularIntensity", Range(0, 5)) = 1
        _SpecularDarkIntensity ("_SpecularDarkIntensity", Range(0, 5)) = 1
        _SpecularNVExp ("_SpecularNVExp", Float) = 1
        _SpecularNVIntensity ("_SpecularNVIntensity", Float) = 1
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
            #pragma vertex HairVert
            #pragma fragment HairFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _HairSpecularExp;
                float _HairSpecularIntensity;
                float _RimIntensity;
                float _RimWdith;
                float _OulineScale;
                float _SpecularRange;
                float _SpecularNVExp;
                float _SpecularNVIntensity;
                float _SpecularIntensity;
                float _SpecularDarkIntensity;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
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
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
            };

            Varyings HairVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            float4 HairFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float nv = dot(normalWS, viewDirection);
                float3 baseMap = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).rgb;
                float3 rimLight =
                    step(nv, _RimWdith) * _RimIntensity * baseMap;
                float4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, input.uv);
                float shadowAo = lightMap.g > 0.01 ? 1.0 : 0.0;
                float threshold = step(_RampOffset, dot(normalWS, lightDirection)) * shadowAo;
                float3 diffuse = lerp(
                    baseMap * _DarkIntensity,
                    baseMap * _BrightIntensity,
                    threshold);

                float specularMask = lightMap.r;
                float specular = step(
                    pow(1.0 - nv, _SpecularNVExp) * _SpecularNVIntensity,
                    specularMask * _SpecularRange) * (specularMask > 0.1 ? 1.0 : 0.0);
                specular *= lerp(_SpecularDarkIntensity, _SpecularIntensity, threshold);
                return float4(diffuse + specular * baseMap + rimLight, 0.0) * 1.2;
            }
            ENDHLSL
        }

        UsePass "NPR/NPR_ZS_PBR_URP/NORMAL"
    }
    Fallback Off
}
