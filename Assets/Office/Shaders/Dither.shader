Shader "Universal Render Pipeline/Water/Dither"
{
    Properties
    {
        [WeatherParameters]
        _BeaufortScale ("Beaufort Scale", Range(0, 12)) = 0.0

        [Dither]
        _NoiseTex ("Texture", 2D) = "white" {}
        _DepthStart ("Depth Mask Start", Float) = 0.0
        _DepthEnd ("Depth Mask End", Float) = 5.0
        _DepthPower ("Depth Mask Power", Range(0.1, 4)) = 1.0
        _CoarseSimulationTileDimension ("Coarse Simulation Tile Dimension", Float) = 1.0
        _Shades ("Shades", Range(2, 256)) = 6.0
        _Tiling ("Tiling", Range(0, 20)) = 10.0
        _StepHardness ("Step Hardness", Float) = 1.0

        [Flowmap]
        _FlowMap ("Flow Map", 2D) = "black" {}
        _WaterNormalStrength ("Water Normal Strength", Vector) = (1.0, 1.0, 1.0, 1.0)
        _FlowmapStrength ("Flowmap Strength", Range(0, 1)) = 1.0
        _FlowSpeed ("Flow Speed", Float) = 1.0
        _FlowNormalNSH ("Flow Normal NSH", 2D) = "black" {}
        _FlowNormalNFH ("Flow Normal NFH", 2D) = "black" {}

        [Foam]
        _OceanNoiseTex ("Ocean Noise Texture", 2D) = "white" {}
        [NoScaleOffset] _FFTDisplacementTex ("FFT Height / Displacement (ZW)", 2D) = "black" {}
        _FFTDisplacementScale ("FFT Horizontal Displacement Scale (X/Z)", Vector) = (1, 1, 1, 1)
        _FoamJacobianThreshold ("Foam Jacobian Threshold", Range(0, 2)) = 0.8
        _FoamJacobianRange ("Foam Jacobian Range", Range(0.01, 2)) = 0.5
        _FoamBreakup ("Foam Noise Breakup", Range(0, 1)) = 0.7
        _FoamBaseLevel ("Foam Base Level", Range(0, 1)) = 0.5
        _ShorelineFoamDensity ("Shoreline Foam Density", Range(0, 1)) = 0.5
        _ShorelineFoamStrength ("Shoreline Foam Strength", Range(0, 1)) = 1.0
        _ShorelineFoamWidth ("Shoreline Foam Width", Range(0, 5)) = 5.0

        [Color]
        _WaterColor ("Water Color", Color) = (0.926, 0.987, 0.978, 1.0)
        _CloudinessColor ("Cloudiness Color", Color) = (0.62, 0.76, 0.78, 1.0)
        _FoamColor ("Foam Color", Color) = (0.92, 0.96, 0.96, 1.0)
    }
    SubShader
    {
        Tags
        { 
            "RenderType"="Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
        }

        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);
            TEXTURE2D(_FlowMap);
            SAMPLER(sampler_FlowMap);
            TEXTURE2D(_FlowNormalNSH);
            SAMPLER(sampler_FlowNormalNSH);
            TEXTURE2D(_FlowNormalNFH);
            SAMPLER(sampler_FlowNormalNFH);
            TEXTURE2D(_OceanNoiseTex);
            SAMPLER(sampler_OceanNoiseTex);
            TEXTURE2D(_FFTDisplacementTex);
            SAMPLER(sampler_FFTDisplacementTex);
            float4 _FFTDisplacementTex_TexelSize;

            static const float2 NORMAL_RG = float2(0.5, 0.5);

            CBUFFER_START(UnityPerMaterial)
                float _BeaufortScale;
                float _DepthStart;
                float _DepthEnd;
                float _DepthPower;
                float _Shades;
                float _Tiling;
                float _StepHardness;
                float _CoarseSimulationTileDimension;
                float4 _WaterNormalStrength;
                float _FlowmapStrength;
                float _FlowSpeed;
                float _FoamBaseLevel;
                float4 _FFTDisplacementScale;
                float _FoamJacobianThreshold;
                float _FoamJacobianRange;
                float _FoamBreakup;
                float _ShorelineFoamDensity;
                float _ShorelineFoamStrength;
                float _ShorelineFoamWidth;
                float4 _WaterColor;
                float4 _CloudinessColor;
                float4 _FoamColor;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float3 positionWS : TEXCOORD0;
                float  fogFactor  : TEXCOORD1;
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD2;
                float3 normalWS   : TEXCOORD3;
                float3 tangentWS  : TEXCOORD4;
                float3 bitangentWS: TEXCOORD5;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                float3 normalWS = normalize(normalInputs.normalWS);
                float3 tangentWS = normalInputs.tangentWS;
                float3 bitangentWS = normalInputs.bitangentWS;
                if (dot(tangentWS, tangentWS) < 1e-6)
                {
                    // Meshes without tangents still need a valid basis for water normal maps.
                    float3 referenceAxis = abs(normalWS.y) < 0.999
                        ? float3(0.0, 1.0, 0.0)
                        : float3(0.0, 0.0, 1.0);
                    tangentWS = normalize(cross(referenceAxis, normalWS));
                    bitangentWS = normalize(cross(normalWS, tangentWS));
                }
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                o.uv = v.uv;
                o.normalWS = normalWS;
                o.tangentWS = tangentWS;
                o.bitangentWS = bitangentWS;
                return o;
            }

            float CameraDistanceMask_Cal(float waterDepth, float depthStart, float depthEnd, float depthPower)
            {
                float cameraDistanceMask = saturate(
                    (waterDepth - depthStart) / max(depthEnd - depthStart, 0.001)); // DepthMask 
                cameraDistanceMask = pow(cameraDistanceMask, max(depthPower, 0.001));
                return cameraDistanceMask;
            }

            float2 UVTiling(float2 sourceUV, float tilesPerMeter)
            {
                return sourceUV * tilesPerMeter;
            }

            float2 FlowMapToVector(float2 flowmap)
            {
                return (flowmap + 1.0 * _WaterNormalStrength.xz) * 0.5;
            }

            float3 ColorGradientx3(float phase)
            {
                float3 color0 = float3(0.95, 0.9, 0.45); 
                float3 color1 = float3(0.9, 0.85, 0.425);
                float3 color2 = float3(0.75, 0.7, 0.35);
                float t = saturate(phase) * 2.0;

                if (t < 1.0)
                    return lerp(color0, color1, t);

                return lerp(color1, color2, t - 1.0);
            }

            float3 ColorGradientx4(float phase)
            {
                float3 color0 = float3(0.5, 0.35, 0.1);
                float3 color1 = float3(0.85, 0.85, 0.2);
                float3 color2 = float3(0.95, 0.95, 0.2); 
                float3 color3 = float3(1.0, 1.0, 0.3); 
                float t = saturate(phase) * 3.0;

                if (t < 1.0)
                    return lerp(color0, color1, t);
                else if (t < 2.0)
                    return lerp(color1, color2, t - 1.0);
                else
                    return lerp(color2, color3, t - 2.0);
            }
            // Separate FFT Jacobian calculation. Reference: https://github.com/RedShaoWuHuaQu/UnityShader.git
            float ComputeFFTJacobian(float2 fftUV, float2 uvPerMeter)
            {
                float2 texel = _FFTDisplacementTex_TexelSize.xy;
                float2 offsetX = float2(texel.x, 0.0);
                float2 offsetY = float2(0.0, texel.y);

                float2 displacementLeft = SAMPLE_TEXTURE2D(
                    _FFTDisplacementTex, sampler_FFTDisplacementTex, fftUV - offsetX).zw
                    * _FFTDisplacementScale.xy;
                float2 displacementRight = SAMPLE_TEXTURE2D(
                    _FFTDisplacementTex, sampler_FFTDisplacementTex, fftUV + offsetX).zw
                    * _FFTDisplacementScale.xy;
                float2 displacementBottom = SAMPLE_TEXTURE2D(
                    _FFTDisplacementTex, sampler_FFTDisplacementTex, fftUV - offsetY).zw
                    * _FFTDisplacementScale.xy;
                float2 displacementTop = SAMPLE_TEXTURE2D(
                    _FFTDisplacementTex, sampler_FFTDisplacementTex, fftUV + offsetY).zw
                    * _FFTDisplacementScale.xy;

                float2 derivativeX = (displacementRight - displacementLeft)
                    / max(2.0 * texel.x, 1e-6) * uvPerMeter.x;
                float2 derivativeZ = (displacementTop - displacementBottom)
                    / max(2.0 * texel.y, 1e-6) * uvPerMeter.y;

                return (1.0 + derivativeX.x) * (1.0 + derivativeZ.y)
                    - derivativeZ.x * derivativeX.y;
            }

            float AddSubHeightBlend(float heightA, float heightB, float mask, float maskMidPoint, float contrast)
            {
                float blendMask = mask - maskMidPoint;
                float subMask = heightA - blendMask;
                float addMask = heightB + blendMask;
                
                return saturate((addMask - subMask) * contrast + 0.5);
            }

            half4 frag(Varyings i) : SV_Target
            {
                // Weather Parameters
                float beaufortFactor = _BeaufortScale * 0.0833333; // Scale Beaufort to 0-1 range
                float colorDepth = lerp(1.2, 0.4, beaufortFactor);
                float foamBaseLevel = lerp(0.0, 0.7, beaufortFactor);
                float3 smoothnessParams = ColorGradientx3(beaufortFactor);// X: Smoothness level Y: Smothness far level Z: Smoothness Texture Strength
                float3 strengthParams = ColorGradientx4(beaufortFactor);// X: Foam Normal Strength Y: Microdetail Normal Strength Z: Flowmap Strength

                // Water UV
                float2 waterUV = i.positionWS.xz;
                // Ocean Noise RGBA
                float2 oceanUV = waterUV * 0.0025;
                oceanUV = UVTiling(oceanUV, 0.5);
                float4 oceanNoise = SAMPLE_TEXTURE2D(_OceanNoiseTex, sampler_OceanNoiseTex, oceanUV); // RGBA: Noise R, Noise G, Noise B, Noise A

                // Sample flowmap vector
                float2 flowVecUV = waterUV * _CoarseSimulationTileDimension * 0.125;
                flowVecUV = UVTiling(flowVecUV, 0.25);
                float flowUvPerMeter = _CoarseSimulationTileDimension * 0.125 * 0.25;
                float2 flowmap = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, flowVecUV).rg;
                float2 flowVecXY = FlowMapToVector(flowmap);

                // Camera depth mask calculations
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float rawSceneDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = LinearEyeDepth(rawSceneDepth, _ZBufferParams);
                float surfaceEyeDepth = -TransformWorldToView(i.positionWS).z;
                float waterDepth = max(sceneEyeDepth - surfaceEyeDepth, 0.0);
                float cameraDistanceMask = CameraDistanceMask_Cal(waterDepth, _DepthStart, _DepthEnd, _DepthPower);// 450, 50, 1.0

                // Noise Sampling and dither mask calculations
                float2 noiseUV = waterUV * _Tiling;
                float noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;

                float shades = max(2.0, _Shades);
                float scaledDepth = cameraDistanceMask * (shades - 1.0);
                float numerator = floor(noise * _StepHardness + frac(scaledDepth));
                numerator += floor(scaledDepth);
                float ditherResult = saturate(numerator / (shades - 1.0));
                ditherResult = (ditherResult == 0.0) ? 0.2 : ditherResult; // Prevents full black, used as UV later

                // Get Flowmap Factors: ditherResult is UV source and FlowVecXY is the FlowXY source
                float2 flowUV0 = ditherResult + flowVecXY * _FlowmapStrength * frac(_FlowSpeed * _Time.y);
                float2 flowUV1 = ditherResult + flowVecXY * _FlowmapStrength * frac(_FlowSpeed * _Time.y + 0.5);
                float flowLerp = abs(1.0 - 2.0 * frac(_FlowSpeed * _Time.y));

                float4 NSH_UV0 = SAMPLE_TEXTURE2D(_FlowNormalNSH, sampler_FlowNormalNSH, flowUV0);
                float4 NSH_UV1 = SAMPLE_TEXTURE2D(_FlowNormalNSH, sampler_FlowNormalNSH, flowUV1);
                float4 NFH_UV0 = SAMPLE_TEXTURE2D(_FlowNormalNFH, sampler_FlowNormalNFH, flowUV0);
                float4 NFH_UV1 = SAMPLE_TEXTURE2D(_FlowNormalNFH, sampler_FlowNormalNFH, flowUV1);

                float VS_Factor = clamp(acos(_WaterNormalStrength.y), 0.2, 0.8);// Vertical Surface Factor
                float VS_Mask = lerp(0.125, 1.0, VS_Factor);// Vertical Surface Mask

                float4 NSH = lerp(NSH_UV0, NSH_UV1, flowLerp);
                float4 NFH = lerp(NFH_UV0, NFH_UV1, flowLerp);
                float2 foamRG = NSH.xy;
                float2 foamHeight = lerp(NSH.w, NSH.z, VS_Factor);
                float2 MD_RG = lerp(float2(0.5, 0.5), NFH.xy, VS_Mask);// MicroDetailRG
                float MD_Smoothness = NFH.z;// MicroDetailSmoothness
                float MD_Height = NFH.w;// MicroDetailHeight

                // Foam //
                /* 
                This subgraph combines multiple foam sources (simulation-driven foam + depth-based shoreline foam) into a final foam mask for ocean rendering.

                IN
                Noise R:
                Noise G:
                Noise B:
                Noise A:
                Camera Distance Mask: Camera fade mask, 30m - 450m fade out by default.
                Foam Base Level: Foam base level, coming from the ocean weather SGP, 0 - 0.7 for beaufort 1-12 by default.
                Extra Mask Input: Extra foam mask, might coming from the vertex shader, wave decals.

                OUT
                Sim Foam Mask: Mask area for whitecaps.
                Sim Foam Mask NoBreakup: Mask area for foam, with nobreakup, will be using to create churn area under the foam.
                */
                // Base Foam //
                /*
                Produces a subtle, always-present foam layer. 
                Takes FoamBaseLevel (scaled by 0.5) and interpolates it with CameraDistanceMask so the base foam fades at distance.
                NoiseB texture is used to break up the pattern by interpolating between the low and high foam values.
                */
                float foamBase = lerp(foamBaseLevel * 0.5, foamBaseLevel, cameraDistanceMask);
                float foamBase_Noised = lerp(foamBase * 0.5, foamBase, oceanNoise.b);
                // Sim Foam Masks Combined //
                /*
                Combines the simulation-driven foam sources:
                CoarseFoam — coarse wave foam
                Coarse2Foam — secondary coarse foam
                InteractiveFFTFoam — interactive FFT-based foam
                Extra Mask Input — e.g. foam from wave decals

                These are merged via Max (strongest wins). The result is run through cheapPower2 and then blended with the camera distance mask and noise channels (NoiseA, NoiseB) to create breakup/softening. 
                The output blends between the Base Foam result and this sim foam using a multiply of multiple interpolations, producing the Sim Foam Mask output.
                */
                // FFT Foam by Jacobian //
                float jacobian = ComputeFFTJacobian(
                    flowVecUV, float2(flowUvPerMeter, flowUvPerMeter));
                float foamPotential = saturate(
                    (_FoamJacobianThreshold - jacobian) / max(_FoamJacobianRange, 0.001));
                float breakupStrength = saturate(_FoamBreakup);
                // Use FFT foam as foam Mask
                float foamMask = saturate(
                    (foamPotential - (1.0 - oceanNoise.r) * breakupStrength)
                    / max(1.0 - breakupStrength, 0.001));// Sim Foam Mask NoBreakup
                float factor_01 = lerp(0.1, 0.85, cameraDistanceMask);
                float foamMask_Blended = lerp(factor_01, 1.0, oceanNoise.a) * lerp(0.5, 1.0, oceanNoise.b) 
                    * lerp(pow(foamMask, 2.0), foamMask, cameraDistanceMask);
                float foamBase_Final = lerp(foamBase_Noised, 1.0, foamMask_Blended);
                // Shoreline Foam //
                /*
                Generates foam where the ocean meets land, based on water depth:

                WaterDepth → Range(Min=ShorelineFoamWidth, Max=0) creates a gradient mask from shore outward.
                The depth mask is multiplied by ShorelineFoamDensity and complemented.
                Noise (NoiseG/NoiseB) is interpolated using the depth mask to add organic breakup.
                A ColorBlend.multiply combines the depth mask with the noise pattern.
                The result is scaled by ShorelineFoamStrength.
                */
                float shorelineFoamMask = 1.0 - saturate(
                    waterDepth / max(_ShorelineFoamWidth, 0.001));
                float shoreLineFoamDensity = 1.0 - _ShorelineFoamDensity * shorelineFoamMask;
                float shorelineFoamNoise = lerp(oceanNoise.g, oceanNoise.b, shorelineFoamMask);
                float ShorelineFoamMask_Final = lerp(
                    shorelineFoamMask,
                    shorelineFoamMask * shorelineFoamNoise,
                    shoreLineFoamDensity);
                    
                float simFoamMask_Final = max(foamBase_Final, ShorelineFoamMask_Final);

                // Ocean Base Material //
                //Opaque foam coverage//
                /*
                Height Blends together Foam Height and MicroDetail Height; 
                it's important to have something in Microdetail height to break up the transition
                */
                float heightMask = lerp(simFoamMask_Final, simFoamMask_Final * clamp(oceanNoise.g, 0.2, 1.0), VS_Mask);
                float HeightA = MD_Height;
                float HeightB = clamp(foamHeight, 0.25, 1.0);
                float height_Blended = AddSubHeightBlend(HeightA, HeightB, heightMask, 0.35, 2.0);// Height Blending
                float balancingFactor = clamp(lerp(HeightB, lerp(0.5, 1.0, foamHeight), simFoamMask_Final), 0.0, 0.8);
                float foamCoverage = height_Blended * balancingFactor * heightMask;// Final Foam Coverage
                //Smoothness handing//
                float smoothness_Blended = (MD_Smoothness - 0.5) * smoothnessParams.z + lerp(smoothnessParams.x, 0.0, foamCoverage);
                float smoothness_Final = lerp(smoothnessParams.y * smoothness_Blended, smoothness_Blended, cameraDistanceMask); // Final Smoothness
                
                //Normal Handling//
                float2 MD_Normal = lerp(NORMAL_RG, MD_RG, strengthParams.y);
                float2 foamNormal = lerp(NORMAL_RG, foamRG, strengthParams.x);
                float2 waterNormalBlended = lerp(MD_Normal, foamNormal, foamCoverage);
                float waterNormalCombineFactor = lerp(lerp(0.1, 0.2, oceanNoise.a), lerp(0.75, 1.0, oceanNoise.a), cameraDistanceMask);// Remove Normal at distance to avoid SSR artefacts
                float2 waterNormal_Final = lerp(NORMAL_RG, waterNormalBlended, waterNormalCombineFactor); // Water Normal
                //float3 DetailNormalStrength = lerp(CameraDistanceMask(waterDepth, 50.0, 5.0, _DepthPower) * _ReflectionDetail + waterNormalCombineFactor, 0.0, foamMask);
                float2 waterNormalUnpacked = waterNormal_Final * 2.0 - 1.0;
                float3 normalTS_Final = normalize(float3(
                    waterNormalUnpacked,
                    sqrt(1.0 - saturate(dot(waterNormalUnpacked, waterNormalUnpacked)))));
                float3x3 tangentToWorld = float3x3(
                    normalize(i.tangentWS),
                    normalize(i.bitangentWS),
                    normalize(i.normalWS));
                float3 normalWS_Final = normalize(
                    TransformTangentToWorld(normalTS_Final, tangentToWorld));
                //Churn Handling//
                float cloudiness_Final = AddSubHeightBlend(oceanNoise.r, oceanNoise.a, foamMask, 0.7, 1.0);// Final Churn Coverage
                // 4 Params Out: normalWS_Final / smoothness_Final / cloudiness_Final / foamCoverage

                // Blend Water Color //
                float colorDepthScale = lerp(1.0, colorDepth, cameraDistanceMask);
                float3 color_Final = _WaterColor.rgb * colorDepthScale;
                float mixedWaterMask = saturate(_WaterColor.a);
                float3 albedo = lerp(
                    color_Final, _CloudinessColor.rgb, saturate(cloudiness_Final));
                albedo = lerp(albedo, _FoamColor.rgb, saturate(foamCoverage));
                half alpha = saturate(lerp(mixedWaterMask, 1.0, foamCoverage));

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.specular = half3(0.02, 0.02, 0.02);
                surfaceData.metallic = 0.0;
                surfaceData.smoothness = saturate(smoothness_Final);
                surfaceData.normalTS = half3(0.0, 0.0, 1.0);
                surfaceData.emission = 0.0;
                surfaceData.occlusion = 1.0;
                surfaceData.alpha = alpha;
                surfaceData.clearCoatMask = 0.0;
                surfaceData.clearCoatSmoothness = 0.0;

                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;
                inputData.positionCS = i.positionCS;
                inputData.normalWS = normalWS_Final;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                inputData.fogCoord = i.fogFactor;
                inputData.vertexLighting = 0.0;
                inputData.bakedGI = SampleSH(normalWS_Final);
                inputData.normalizedScreenSpaceUV = screenUV;
                inputData.shadowMask = half4(1.0, 1.0, 1.0, 1.0);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, i.fogFactor);
                return color;
            }
            ENDHLSL
        }
    }
}
