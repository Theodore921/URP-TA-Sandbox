Shader "NPR/URP/NPR_ZS_Face_Code"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _RampMap ("_RampMap", 2D) = "white" {}
        _LightMap ("_LightMap", 2D) = "black" {}
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Range(0, 1)) = 0.5
        _DarkColor ("_DarkColor", Color) = (1, 1, 1, 1)
        _BrightIntensity ("_BrightIntensity", Float) = 1
        [Space(10)]
        _RimIntensity ("_RimScale", Float) = 1
        _RimWdith ("_RimStep", Float) = 0.3
        _NoiseLightIntensity ("_NoiseLightIntensity", Float) = 1
        [KeywordEnum(Ramp, None)] UseRamp ("UseRamp?", Float) = 0
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
            #pragma vertex FaceVert
            #pragma fragment FaceFrag
            #pragma shader_feature_local USERAMP_RAMP USERAMP_NONE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _DarkColor;
                float4 _OutlineColor;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _RimIntensity;
                float _RimWdith;
                float _NoiseLightIntensity;
                float UseRamp;
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

            Varyings FaceVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            float4 FaceFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float3 baseColor = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, input.uv).rgb;
                float3 rimLight =
                    step(dot(normalWS, viewDirection), _RimWdith) * _RimIntensity * baseColor;
                float3 lightMap = SAMPLE_TEXTURE2D(
                    _LightMap, sampler_LightMap, input.uv).rgb;
                float shadowAo = step(lightMap.g, 0.3);
                float3 diffuse;

                #if defined(USERAMP_RAMP)
                    float rampU = clamp(dot(normalWS, lightDirection) * 0.5 + 0.5, 0.01, 0.99);
                    float3 ramp = SAMPLE_TEXTURE2D(
                        _RampMap, sampler_RampMap, float2(rampU, 0.5)).rgb;
                    diffuse = lerp(
                        baseColor * _DarkIntensity,
                        baseColor * _BrightIntensity,
                        ramp * shadowAo);
                #else
                    diffuse = lerp(
                        baseColor * _DarkIntensity * _DarkColor.rgb,
                        baseColor * _BrightIntensity,
                        step(_RampOffset * shadowAo, dot(normalWS, lightDirection)));
                #endif

                diffuse += lightMap.r * _NoiseLightIntensity;
                return float4(diffuse + rimLight, 0.0);
            }
            ENDHLSL
        }

        UsePass "NPR/NPR_ZS_PBR_URP/NORMAL"
    }
    Fallback Off
}
