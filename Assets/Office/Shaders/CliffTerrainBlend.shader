Shader "Office/Cliff Terrain Blend"
{
    Properties
    {
        [MainTexture] _BaseMap ("Rock Albedo", 2D) = "white" {}
        [MainColor] _BaseColor ("Rock Tint", Color) = (1, 1, 1, 1)
        [Normal] _BumpMap ("Rock Normal", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Range(0, 2)) = 1
        _RoughnessMap ("Rock Roughness (R)", 2D) = "white" {}
        _Smoothness ("Smoothness", Range(0, 1)) = 0.35

        [Header(Color Matching)]
        _Saturation ("Rock Saturation", Range(0, 2)) = 1
        _Exposure ("Rock Exposure (EV)", Range(-2, 2)) = 0

        [Header(Terrain Blend)]
        _GroundMap ("Terrain Albedo", 2D) = "white" {}
        _GroundTint ("Terrain Tint", Color) = (1, 1, 1, 1)
        _GroundTiling ("Terrain Texture Tile Size (m)", Float) = 8
        _GroundOffset ("Terrain Texture Offset (m)", Vector) = (0, 0, 0, 0)
        _BlendStart ("Blend Start Below Terrain (m)", Float) = -0.25
        _BlendEnd ("Blend End Above Terrain (m)", Float) = 0.8
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);
            TEXTURE2D(_RoughnessMap);
            SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_GroundMap);
            SAMPLER(sampler_GroundMap);
            TEXTURE2D(_CliffTerrainHeightMap);
            SAMPLER(sampler_CliffTerrainHeightMap);
            float4 _CliffTerrainOrigin;
            float4 _CliffTerrainSize;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float4 _GroundTint;
                float4 _GroundOffset;
                float _BumpScale;
                float _Smoothness;
                float _Saturation;
                float _Exposure;
                float _GroundTiling;
                float _BlendStart;
                float _BlendEnd;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float fogFactor : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                float3 normalWS = normalize(normalInputs.normalWS);
                float3 tangentWS = normalInputs.tangentWS;
                float tangentSign = input.tangentOS.w;
                if (dot(tangentWS, tangentWS) < 1e-6)
                {
                    float3 referenceAxis = abs(normalWS.y) < 0.999
                        ? float3(0, 1, 0)
                        : float3(0, 0, 1);
                    tangentWS = normalize(cross(referenceAxis, normalWS));
                }
                if (abs(tangentSign) < 0.5)
                    tangentSign = 1;

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalWS;
                output.tangentWS = float4(
                    normalize(tangentWS),
                    tangentSign * GetOddNegativeScale());
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogFactor = ComputeFogFactor(positionInputs.positionCS.z);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                half4 rockSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 rockAlbedo = rockSample.rgb * _BaseColor.rgb;
                half luminance = dot(rockAlbedo, half3(0.2126, 0.7152, 0.0722));
                rockAlbedo = lerp(luminance.xxx, rockAlbedo, _Saturation);
                rockAlbedo *= exp2(_Exposure);

                float2 terrainUV = (input.positionWS.xz - _CliffTerrainOrigin.xz)
                    / max(_CliffTerrainSize.xz, float2(0.001, 0.001));
                half insideTerrain = step(0.0, terrainUV.x) * step(terrainUV.x, 1.0)
                    * step(0.0, terrainUV.y) * step(terrainUV.y, 1.0);
                half terrainHeight = SAMPLE_TEXTURE2D_LOD(
                    _CliffTerrainHeightMap, sampler_CliffTerrainHeightMap, saturate(terrainUV), 0).r;
                float distanceFromTerrain = input.positionWS.y
                    - (_CliffTerrainOrigin.y + terrainHeight * _CliffTerrainSize.y);
                half rockMask = smoothstep(_BlendStart, max(_BlendEnd, _BlendStart + 0.001),
                    distanceFromTerrain);
                rockMask = lerp(1.0h, rockMask, insideTerrain);

                float2 groundUV = (input.positionWS.xz - _CliffTerrainOrigin.xz + _GroundOffset.xy)
                    / max(_GroundTiling, 0.001);
                half3 groundAlbedo = SAMPLE_TEXTURE2D(
                    _GroundMap, sampler_GroundMap, groundUV).rgb * _GroundTint.rgb;
                half3 albedo = lerp(groundAlbedo, rockAlbedo, rockMask);

                half3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half3 normalWS = normalize(input.normalWS);
                half3 tangentWS = normalize(input.tangentWS.xyz);
                half3 bitangentWS = normalize(cross(normalWS, tangentWS) * input.tangentWS.w);
                normalWS = normalize(TransformTangentToWorld(
                    normalTS, half3x3(tangentWS, bitangentWS, normalWS)));

                half roughness = SAMPLE_TEXTURE2D(
                    _RoughnessMap, sampler_RoughnessMap, input.uv).r;

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.specular = half3(0.04, 0.04, 0.04);
                surfaceData.metallic = 0;
                surfaceData.smoothness = saturate((1.0h - roughness) * _Smoothness);
                surfaceData.normalTS = half3(0, 0, 1);
                surfaceData.emission = 0;
                surfaceData.occlusion = 1;
                surfaceData.alpha = 1;
                surfaceData.clearCoatMask = 0;
                surfaceData.clearCoatSmoothness = 0;

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.positionCS = input.positionCS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                inputData.fogCoord = input.fogFactor;
                inputData.vertexLighting = VertexLighting(input.positionWS, normalWS);
                inputData.bakedGI = SampleSH(normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = half4(1, 1, 1, 1);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, input.fogFactor);
                return color;
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        UsePass "Universal Render Pipeline/Lit/Meta"
    }
}
