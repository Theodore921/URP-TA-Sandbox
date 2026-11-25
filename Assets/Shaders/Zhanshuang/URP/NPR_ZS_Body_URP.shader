Shader "NPR/URP/NPR_ZS_Body"
{
    Properties
    {
        [KeywordEnum(Cloth, Skin, Face, Hair, Debug)] _Type ("Type", Float) = 0
        [KeywordEnum(BaseColor, NormalMap, VC_R, VC_G, VC_B, L_R, L_G, L_B, L_A)] _Debug ("Debug", Float) = 0
        _MainTex ("MainTex", 2D) = "white" {}
        [Normal] _NormalMap ("NormalMap", 2D) = "white" {}
        _RampOffset ("RampOffset", Range(-1, 1)) = 0
        _HairRampOffset ("HairRampOffset", Range(-1, 1)) = 0
        _DarkIntensity ("DarkIntensity", Range(0, 1)) = 0.5
        _BrightIntensity ("BrightIntensity", Range(0, 10)) = 1
        _SkinRamp ("SkinRamp", 2D) = "white" {}
        _FaceRamp ("FaceRamp", 2D) = "white" {}
        _LightMap ("LightMap", 2D) = "white" {}
        _HairLightMap ("HairLightMap", 2D) = "white" {}
        _HairSpecularExponent ("HairSpecularExponent", Float) = 4
        _HairSpecularScale ("HairSpecularScale", Float) = 1
        _FaceLightMap ("FaceLightMap", 2D) = "black" {}
        _SpecularExp ("SpecularExp", Float) = 0
        _SpecularScale ("SpecularScale", Float) = 1
        [HideInInspector] _texcoord ("", 2D) = "white" {}
        _OulineScale ("_OulineScale", Float) = 0.1
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
        LOD 100

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            Blend Off
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex BodyVert
            #pragma fragment BodyFrag
            #pragma multi_compile_instancing
            #pragma shader_feature_local _TYPE_CLOTH _TYPE_SKIN _TYPE_FACE _TYPE_HAIR _TYPE_DEBUG
            #pragma shader_feature_local _DEBUG_BASECOLOR _DEBUG_NORMALMAP _DEBUG_VC_R _DEBUG_VC_G _DEBUG_VC_B _DEBUG_L_R _DEBUG_L_G _DEBUG_L_B _DEBUG_L_A
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _NormalMap_ST;
                float4 _LightMap_ST;
                float4 _FaceLightMap_ST;
                float4 _HairLightMap_ST;
                float4 _OutlineColor;
                float _RampOffset;
                float _HairRampOffset;
                float _DarkIntensity;
                float _BrightIntensity;
                float _HairSpecularExponent;
                float _HairSpecularScale;
                float _SpecularExp;
                float _SpecularScale;
                float _OulineScale;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_LightMap);
            SAMPLER(sampler_LightMap);
            TEXTURE2D(_SkinRamp);
            SAMPLER(sampler_SkinRamp);
            TEXTURE2D(_FaceRamp);
            SAMPLER(sampler_FaceRamp);
            TEXTURE2D(_FaceLightMap);
            SAMPLER(sampler_FaceLightMap);
            TEXTURE2D(_HairLightMap);
            SAMPLER(sampler_HairLightMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
                float4 tangentOS : TANGENT;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float3 tangentWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float4 color : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings BodyVert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

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

            float4 BodyFrag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 mainUv = TRANSFORM_TEX(input.uv, _MainTex);
                float2 lightUv = TRANSFORM_TEX(input.uv, _LightMap);
                float2 normalUv = TRANSFORM_TEX(input.uv, _NormalMap);
                float2 faceLightUv = TRANSFORM_TEX(input.uv, _FaceLightMap);
                float2 hairLightUv = TRANSFORM_TEX(input.uv, _HairLightMap);

                float4 mainSample = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, mainUv);
                float4 darkColor = mainSample * _DarkIntensity;
                float4 brightColor = mainSample * _BrightIntensity;
                float4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, lightUv);
                float4 normalMap = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUv);
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS);
                float3 bitangentWS = normalize(input.bitangentWS);
                float3x3 tangentToWorld = float3x3(
                    tangentWS.x, bitangentWS.x, normalWS.x,
                    tangentWS.y, bitangentWS.y, normalWS.y,
                    tangentWS.z, bitangentWS.z, normalWS.z);
                float3 worldNormalMap = mul(tangentToWorld, normalMap.rgb);
                float3 lightDirection = normalize(GetMainLight().direction);
                float3 viewDirection = normalize(GetWorldSpaceViewDir(input.positionWS));
                float3 halfDirection = normalize(viewDirection + lightDirection);

                float threshold = step(
                    lightMap.r + _RampOffset, dot(worldNormalMap, lightDirection)) * lightMap.g;
                float4 cloth = lerp(darkColor, brightColor, threshold);
                float clothSpecular = pow(
                    saturate(dot(halfDirection, normalWS)), _SpecularExp) *
                    _SpecularScale * lightMap.b;
                cloth += clothSpecular;

                float2 rampUv = float2(dot(normalWS, lightDirection) * 0.5 + 0.5, 0.5);
                float4 skinRamp = SAMPLE_TEXTURE2D(_SkinRamp, sampler_SkinRamp, rampUv);
                float4 skin = lerp(darkColor, brightColor, skinRamp);
                float4 faceRamp = SAMPLE_TEXTURE2D(_FaceRamp, sampler_FaceRamp, rampUv);
                float4 faceLightMap = SAMPLE_TEXTURE2D(
                    _FaceLightMap, sampler_FaceLightMap, faceLightUv);
                float4 face = lerp(darkColor, brightColor, faceRamp) + faceLightMap.r;

                float4 hairLightMap = SAMPLE_TEXTURE2D(
                    _HairLightMap, sampler_HairLightMap, hairLightUv);
                float hairSpecular = hairLightMap.r *
                    (pow(saturate(dot(halfDirection, normalWS)), _HairSpecularExponent) *
                     _HairSpecularScale);
                float4 hairDiffuse = lerp(
                    darkColor,
                    brightColor,
                    step(hairLightMap.g + _HairRampOffset, dot(normalWS, lightDirection)));
                float4 hair = hairSpecular + hairDiffuse;

                float4 debugColor = mainSample;
                #if defined(_DEBUG_NORMALMAP)
                    debugColor = normalMap;
                #elif defined(_DEBUG_VC_R)
                    debugColor = input.color.rrrr;
                #elif defined(_DEBUG_VC_G)
                    debugColor = input.color.gggg;
                #elif defined(_DEBUG_VC_B)
                    debugColor = input.color.bbbb;
                #elif defined(_DEBUG_L_R)
                    debugColor = lightMap.rrrr;
                #elif defined(_DEBUG_L_G)
                    debugColor = lightMap.gggg;
                #elif defined(_DEBUG_L_B)
                    debugColor = lightMap.bbbb;
                #elif defined(_DEBUG_L_A)
                    debugColor = lightMap.aaaa;
                #endif

                #if defined(_TYPE_SKIN)
                    return skin;
                #elif defined(_TYPE_FACE)
                    return face;
                #elif defined(_TYPE_HAIR)
                    return hair;
                #elif defined(_TYPE_DEBUG)
                    return debugColor;
                #else
                    return cloth;
                #endif
            }
            ENDHLSL
        }
    }

    CustomEditor "ASEMaterialInspector"
    Fallback Off
}
