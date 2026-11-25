Shader "NPR/NPR_ZS_PBR_URP"
{
    Properties
    {
        _MainTex ("_MainTex", 2D) = "white" {}
        _NormalMap ("_NormalMap", 2D) = "white" {}
        _PBRMixMap ("_PBRMixMap", 2D) = "black" {}
        _LightMap ("_LightMap", 2D) = "black" {}

        [Space(10)]
        _RoughnessScale ("_RoughnessScale", Float) = 1
        _MetallicScale ("_MetallicScale", Float) = 1
        _SpecularIntensity ("_SpecularIntensity", Float) = 1
        _SpecularStep ("_SpecularStep", Float) = 0

        [Space(10)]
        _RampOffset ("_RampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("_DarkIntensity", Float) = 0.5
        _BrightIntensity ("_BrightIntensity", Float) = 1

        [Space(10)]
        _StepLightWidth ("_StepLightWidth", Float) = 0.3
        _StepLightIntensity ("_StepLightIntensity", Float) = 1

        [Space(10)]
        [KeywordEnum(None, SecondStepLight)] _UseSecondStepLight ("_UseSecondStepLight", Float) = 0
        _RampOffset2 ("_RampOffset2", Range(-1, 1)) = 0
        _DarkIntensity2 ("_DarkIntensity2", Float) = 0.5

        [Space(10)]
        [KeywordEnum(None, GGX, BlinPhong)] _SpecShift ("SpecShift", Float) = 1
        _SpecShiftIntensity ("_SpecShiftIntensity", Float) = 1
        _Shininess ("_Shininess", Float) = 1
        _Gloss ("_Gloss", Float) = 1
        _Threshold ("_Threshold", Float) = 0.2

        [Space(10)]
        _RimIntensity ("_RimScale", Float) = 1
        _RimWdith ("_RimStep", Float) = 0.3

        [Space(10)]
        _MaskTest ("_MaskTest", Range(-1, 1)) = 0

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
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex NPRPBRVert
            #pragma fragment NPRPBRFrag
            #pragma shader_feature_local _SPECSHIFT_NONE _SPECSHIFT_GGX _SPECSHIFT_BLINPHONG
            #pragma shader_feature_local _USESECONDSTEPLIGHT_NONE _USESECONDSTEPLIGHT_SECONDSTEPLIGHT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "NPR_ZS_PBR_URP_Brdf.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _RoughnessScale;
                float _MetallicScale;
                float _SpecularIntensity;
                float _SpecularStep;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _StepLightWidth;
                float _StepLightIntensity;
                float _RampOffset2;
                float _DarkIntensity2;
                float _SpecShiftIntensity;
                float _Shininess;
                float _Gloss;
                float _Threshold;
                float _RimIntensity;
                float _RimWdith;
                float _MaskTest;
                float _OulineScale;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_PBRMixMap);
            SAMPLER(sampler_PBRMixMap);
            TEXTURE2D(_LightMap);
            SAMPLER(sampler_LightMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 tangentOS : TANGENT;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float4 color : TEXCOORD5;
            };

            Varyings NPRPBRVert(Attributes input)
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
                output.color = input.color;
                return output;
            }

            float4 NPRPBRFrag(Varyings input) : SV_Target
            {
                float3 geometricNormal = normalize(input.normalWS);
                float3 tangent = normalize(input.tangentWS);
                float3 bitangent = normalize(input.bitangentWS);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                Light mainLight = GetMainLight();
                float3 lightDirection = normalize(mainLight.direction);
                float3 halfDirection = normalize(viewDirection + lightDirection);
                float nh = dot(geometricNormal, halfDirection);

                float3 baseMap = SAMPLE_TEXTURE2D(
                    _MainTex, sampler_MainTex, input.uv).rgb;
                float4 mixMap = SAMPLE_TEXTURE2D(
                    _PBRMixMap, sampler_PBRMixMap, input.uv);

                float metallic = mixMap.r * _MetallicScale;
                float roughness = (1.0 - mixMap.g) * _RoughnessScale;
                float ao = mixMap.b;
                float ggxMask = mixMap.a;

                float materialMask = 1.0;
                if (ggxMask < 0.2 || ggxMask > 0.44)
                {
                    materialMask = 0.0;
                }
                if (ggxMask > 0.76)
                {
                    materialMask = 1.0;
                }

                float3 f0 = lerp(0.04, baseMap, metallic);
                float3 rimLight =
                    step(dot(geometricNormal, viewDirection), _RimWdith) *
                    _RimIntensity * baseMap;

                float3 lightMap = SAMPLE_TEXTURE2D(
                    _LightMap, sampler_LightMap, input.uv).rgb;
                float rampAdd = lightMap.r;
                float shadowAo = lightMap.g;

                float3 diffuse = lerp(
                    baseMap * _DarkIntensity,
                    baseMap * _BrightIntensity,
                    step((_RampOffset + rampAdd) * shadowAo, dot(geometricNormal, lightDirection)));

                #if defined(_USESECONDSTEPLIGHT_SECONDSTEPLIGHT)
                    float3 secondStep = lerp(
                        baseMap * _DarkIntensity2,
                        diffuse,
                        step((_RampOffset2 + rampAdd) * shadowAo, dot(geometricNormal, lightDirection)));
                    diffuse = lerp(diffuse, secondStep, materialMask);
                #endif

                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(
                        _NormalMap, sampler_NormalMap, input.uv),
                    1.0);
                float3x3 tangentToWorld = float3x3(tangent, bitangent, geometricNormal);
                float3 shadingNormal = normalize(mul(normalTS, tangentToWorld));

                float3 specular = 0.0;
                #if defined(_SPECSHIFT_GGX)
                    specular += Specular_GGX(
                        shadingNormal, lightDirection, halfDirection, viewDirection, roughness, f0) *
                        ao * _SpecularIntensity * ggxMask * materialMask;
                #elif defined(_SPECSHIFT_BLINPHONG)
                    StylizedSpecularParam param;
                    param.BaseColor = baseMap;
                    param.Normal = shadingNormal;
                    param.Shininess = _Shininess;
                    param.Gloss = _Gloss;
                    param.Threshold = _Threshold;
                    param.dv = tangent;
                    param.du = bitangent;
                    specular += StylizedSpecularLight_BlinPhong(param, halfDirection) *
                        _SpecShiftIntensity * ggxMask * materialMask;
                #endif

                float3 stepLight =
                    step(1.0 - _StepLightWidth, nh) * _StepLightIntensity * baseMap;
                return float4(diffuse + specular + rimLight + stepLight, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "NORMAL"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _RoughnessScale;
                float _MetallicScale;
                float _SpecularIntensity;
                float _SpecularStep;
                float _RampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _StepLightWidth;
                float _StepLightIntensity;
                float _RampOffset2;
                float _DarkIntensity2;
                float _SpecShiftIntensity;
                float _Shininess;
                float _Gloss;
                float _Threshold;
                float _RimIntensity;
                float _RimWdith;
                float _MaskTest;
                float _OulineScale;
            CBUFFER_END

            struct OutlineAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
            };

            struct OutlineVaryings
            {
                float4 positionCS : SV_POSITION;
            };

            OutlineVaryings OutlineVert(OutlineAttributes input)
            {
                OutlineVaryings output;
                input.positionOS.xyz += input.normalOS.xyz * _OulineScale * 0.01 * input.color.a;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            float4 OutlineFrag(OutlineVaryings input) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
