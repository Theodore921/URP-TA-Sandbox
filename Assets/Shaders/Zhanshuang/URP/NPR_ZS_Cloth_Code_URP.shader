Shader "NPR/URP/NPR_ZS_Cloth_Code"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _NormalMap ("_NormalMap", 2D) = "white" {}
        _LightMap ("_LightMap", 2D) = "black" {}
        _LightThreshold ("_LightThreshold", Range(-2, 2)) = 1
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
            #pragma vertex ClothVert
            #pragma fragment ClothFrag
            #pragma multi_compile_local MODE_VALUE MODE_TEX
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "NPR_ZS_PBR_URP_Brdf.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _LightThreshold;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _Roughness;
                float _Metallic;
                float _SpecularIntensity;
                float _RimExp;
                float _RimIntensity;
                float _RimWdith;
                float _OulineScale;
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

            Varyings ClothVert(Attributes input)
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

            float4 ClothFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float nl = dot(normalWS, lightDirection);
                float nv = dot(normalWS, viewDirection);
                float nl01 = nl * 0.5 + 0.5;

                float4 baseSample = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, input.uv);
                float4 lightMap = SAMPLE_TEXTURE2D(
                    _LightMap, sampler_LightMap, input.uv);
                float rampOffsetMask = lightMap.r * 2.0 - 1.0;
                float shadowAo = lightMap.g > 0.001 ? 1.0 : 0.0;
                float specularMask = lightMap.b;
                float threshold = step(
                    _LightThreshold, nl01 + _RampOffset + rampOffsetMask) * shadowAo;
                float3 diffuse = lerp(
                    baseSample.rgb * _DarkIntensity,
                    baseSample.rgb * _BrightIntensity,
                    threshold);
                float3 rimLight =
                    step(nv, _RimWdith) * _RimIntensity * baseSample.rgb;

                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(
                        _NormalMap, sampler_NormalMap, input.uv),
                    1.0);
                float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
                float3 shadingNormal = normalize(mul(normalTS, tangentToWorld));
                float3 halfDirection = normalize(viewDirection + lightDirection);
                float3 f0 = lerp(0.04, baseSample.rgb, _Metallic);
                float3 specular = Specular_GGX(
                    shadingNormal, lightDirection, halfDirection, viewDirection, _Roughness, f0) *
                    specularMask * _SpecularIntensity;
                return float4((diffuse + specular + rimLight) * 1.2, 0.0);
            }
            ENDHLSL
        }

        UsePass "NPR/NPR_ZS_PBR_URP/NORMAL"
    }
    Fallback Off
}
