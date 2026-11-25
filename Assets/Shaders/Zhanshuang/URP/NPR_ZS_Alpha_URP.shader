Shader "NPR/URP/NPR_ZS_Alpha"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _NormalMap ("_NormalMap", 2D) = "white" {}
        _LightMap ("_LightMap", 2D) = "black" {}
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Range(0, 1)) = 0.5
        _BrightIntensity ("_BrightIntensity", Float) = 1
        _Roughness ("_Roughness", Range(0, 1)) = 0.5
        _Metallic ("_Metallic", Range(0, 1)) = 0.1
        _SpecularIntensity ("_SpecularIntensity", Float) = 1
        _RimExp ("_RimExp", Float) = 4
        [Space(10)]
        _RimIntensity ("_RimScale", Float) = 1
        _RimWdith ("_RimStep", Float) = 0.3
        [Space(10)]
        _Alpha ("_Alpha", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex AlphaVert
            #pragma fragment AlphaFrag
            #pragma multi_compile_local MODE_VALUE MODE_TEX
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "NPR_ZS_PBR_URP_Brdf.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _Roughness;
                float _Metallic;
                float _SpecularIntensity;
                float _RimExp;
                float _RimIntensity;
                float _RimWdith;
                float _Alpha;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_LightMap);
            SAMPLER(sampler_LightMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 tangentOS : TANGENT;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
            };

            Varyings AlphaVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                output.bitangentWS = normalInputs.bitangentWS;
                output.uv = input.uv;
                return output;
            }

            float4 AlphaFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float3 halfDirection = normalize(viewDirection + lightDirection);
                float4 baseSample = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, input.uv);
                float3 baseColor = baseSample.rgb;
                float3 f0 = lerp(0.04, baseColor, _Metallic);
                float3 rimLight =
                    step(dot(normalWS, viewDirection), _RimWdith) * _RimIntensity * baseColor;
                float3 diffuse = lerp(
                    baseColor * _DarkIntensity,
                    baseColor * _BrightIntensity,
                    step(_RampOffset, dot(normalWS, lightDirection)));

                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(
                        _NormalMap, sampler_NormalMap, input.uv),
                    1.0);
                float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
                float3 shadingNormal = normalize(mul(normalTS, tangentToWorld));
                float3 specular = Specular_GGX(
                    shadingNormal, lightDirection, halfDirection, viewDirection, _Roughness, f0) *
                    _SpecularIntensity;
                return float4(diffuse + specular + rimLight, _Alpha * baseSample.a);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
