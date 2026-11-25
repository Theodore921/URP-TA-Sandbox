Shader "NPR/URP/NPR_ZS_Eye_Code"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Range(0, 1)) = 0.5
        _BrightIntensity ("_BrightIntensity", Float) = 1
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
            #pragma vertex EyeVert
            #pragma fragment EyeFrag
            #pragma multi_compile_local MODE_VALUE MODE_TEX
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

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

            Varyings EyeVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            float4 EyeFrag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 baseColor = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, input.uv).rgb;
                float3 diffuse = lerp(
                    baseColor * _DarkIntensity,
                    baseColor * _BrightIntensity,
                    step(_RampOffset, dot(normalWS, lightDirection)));
                return float4(diffuse * 1.2, 0.0);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
