// URP 12 兼容的二次元卡通着色器（参考 DanbaidongRP NPRToon 的着色结构 + Vepley 文档的 4 行 RampTex 规范）
// V1: 在 V0 基础上补齐终末地材质所需输入
//   P1: 直接光 Ramp 明暗 + 暗部色 + 高光 Ramp + Rim + Emission
//   P2: RG 双通道法线（Lizhiyan 的 _N 贴图 B 通道为 0，不能当普通法线图用）
//   P3: 打包遮罩 _P（金属/平滑/AO）+ 逐像素阴影图 _ST + 细节遮罩
//   P4: MatCap 高光（金属、布料、头发共用一套采样）
//   P5: 眼睛分段（虹膜边缘/高光/眼影）
//   P6: 反向外壳描边（Cull Front，屏幕空间恒宽）
Shader "Custom/ToonCharacter"
{
    Properties
    {
        [Header(Base)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        [NoScaleOffset]_ShadowRamp ("Shadow Ramp (4 rows: addShadow / metalSpec / spec / directShadow)", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.5

        [Header(Normal)]
        [NoScaleOffset]_NormalMap ("Normal Map (RG, Z rebuilt)", 2D) = "bump" {}
        _NormalScale ("Normal Scale", Range(0,3)) = 1
        _NormalFlipY ("Normal Flip Y", Range(-1,1)) = 1

        [Header(Direct Light)]
        _LightArea ("Light Area (shadow threshold)", Range(0,1)) = 0.5
        _ShadowSmooth ("Shadow Edge Softness", Range(0.001,0.3)) = 0.08
        _ShadowStrength ("Shadow Strength", Range(0,1)) = 1
        _CastShadowStrength ("Cast Shadow Strength", Range(0,1)) = 0.85
        _ShadowTint ("Shadow Tint", Color) = (1,1,1,1)
        _IndirectIntensity ("Indirect Intensity", Range(0,2)) = 0.35
        [HDR]_EmissionColor ("Emission Color", Color) = (0,0,0,1)
        _EmissionIntensity ("Emission Intensity", Range(0,4)) = 1
        [NoScaleOffset]_EmissionMap ("Emission Map (E)", 2D) = "white" {}

        [Header(Shadow Texture)]
        [NoScaleOffset]_ShadowMap ("Shadow Map (ST)", 2D) = "white" {}
        _ShadowMapStrength ("Shadow Map Strength", Range(0,1)) = 0.7

        [Header(Packed Mask)]
        [NoScaleOffset]_PackedMap ("Packed Map (P)", 2D) = "white" {}
        _UsePacked ("Use Packed Mask", Range(0,1)) = 0
        _MetallicChannel ("Metallic Channel (0 none,1 R,2 G,3 B,4 A)", Range(0,4)) = 0
        _SmoothnessChannel ("Smoothness Channel", Range(0,4)) = 0
        _AOChannel ("AO Channel", Range(0,4)) = 0
        _AOStrength ("AO Strength", Range(0,1)) = 1
        _SmoothnessMin ("Spec Threshold Min (cos, 平滑度 0)", Range(0.5,0.9999)) = 0.94
        _SmoothnessMax ("Spec Threshold Max (cos, 平滑度 1)", Range(0.5,0.9999)) = 0.995
        _MetallicSpecBoost ("Metallic Spec Boost", Range(0,4)) = 1.6

        [Header(Detail Mask)]
        [NoScaleOffset]_DetailMask ("Detail Mask (M)", 2D) = "black" {}
        _DetailColor ("Detail Color", Color) = (1,1,1,1)
        _DetailStrength ("Detail Strength", Range(0,1)) = 0

        [Header(MatCap)]
        [NoScaleOffset]_MatCap ("MatCap", 2D) = "black" {}
        [HDR]_MatCapColor ("MatCap Color", Color) = (1,1,1,1)
        _MatCapIntensity ("MatCap Intensity", Range(0,4)) = 0
        _MatCapFlipY ("MatCap Flip Y", Range(0,1)) = 0

        [Header(Ambient)]
        _AmbientColor ("Ambient Floor Color", Color) = (0.34,0.36,0.46,1)
        _AmbientFloor ("Ambient Floor Strength", Range(0,1.5)) = 0.55

        [Header(Hair Specular Band)]
        [Toggle(_HAIR_SPEC_ON)] _HairSpecOn ("Hair Specular Band", Float) = 0
        _HairSpecShift ("Hair Band Shift", Range(-1,1)) = 0.25
        _HairSpecPow ("Hair Band Sharpness", Range(1,200)) = 36
        _HairSpecWidth ("Hair Band Width", Range(0.001,0.5)) = 0.09
        _HairSpecIntensity ("Hair Band Intensity", Range(0,3)) = 1.2
        [NoScaleOffset]_HairSpecMap ("Hair Spec Ramp (RS)", 2D) = "white" {}
        _HairSpecMapStrength ("Hair Spec Map Strength", Range(0,1)) = 1

        [Header(Eye)]
        [Toggle(_EYE_ON)] _EyeOn ("Eye Segment", Float) = 0
        [HDR]_IrisEdgeColor ("Iris Edge Color", Color) = (0.2,0.35,0.5,1)
        _IrisEdgePower ("Iris Edge Power", Range(0.5,8)) = 2
        _IrisEdgeStrength ("Iris Edge Strength", Range(0,1)) = 0.6
        _EyeSpecPower ("Eye Highlight Power", Range(4,400)) = 90
        _EyeSpecIntensity ("Eye Highlight Intensity", Range(0,4)) = 0.9
        _EyeShadowColor ("Eye Shadow Color", Color) = (0.55,0.6,0.75,1)
        _EyeShadowStrength ("Eye Shadow Strength", Range(0,1)) = 0.5

        [Header(Specular)]
        [HDR]_SpecColor ("Spec Color", Color) = (1,1,1,1)
        _SpecPow ("Spec Power (legacy, 未用打包遮罩时)", Range(1,200)) = 24
        _SpecIntensity ("Spec Intensity", Range(0,3)) = 0.6
        _SpecSoftness ("Spec Edge Softness (cos)", Range(0.0005,0.05)) = 0.004
        _SpecNonMetalCap ("Non-Metal Spec Cap", Range(0,1)) = 0.12

        [Header(Rim)]
        [HDR]_RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.5,12)) = 3
        _RimIntensity ("Rim Intensity", Range(0,2)) = 0.4
        _RimLightFacing ("Rim Light Facing", Range(0,1)) = 0.5

        [Header(Face SDF)]
        _FaceAnalytic ("Face Analytic Shading (no SDF tex)", Range(0,1)) = 0
        [Toggle(_FACE_SDF_ON)] _FaceSDFOn ("Use Face SDF", Float) = 0
        [NoScaleOffset]_FaceSDF ("Face SDF (R = shadow boundary)", 2D) = "black" {}
        _FaceSDFUV ("Face SDF UV Set (0=UV0 1=UV1)", Range(0,1)) = 0
        _SDFST ("SDF Tiling (xy) Offset (zw)", Vector) = (1,1,0,0)
        [Enum(Off,0,Face_Lit,1,Raw_SDF,2)] _FaceSDFDebug ("Face SDF Debug", Float) = 0
        _SDFSmooth ("SDF Edge Softness", Range(0.001,0.3)) = 0.03
        _SDFOffset ("SDF Angle Offset", Range(-1,1)) = 0
        _SDFFlip ("SDF Flip Base", Range(0,1)) = 1
        _SDFFlipV ("SDF Flip V", Range(0,1)) = 0
        _SDFSideFlip ("SDF Flip By Light Side", Range(0,1)) = 1

        [Header(Outline)]
        [HDR]_OutlineColor ("Outline Color", Color) = (0.1,0.08,0.09,1)
        _OutlineWidth ("Outline Width (screen)", Range(0,3)) = 0.8
        _OutlineMinDistance ("Outline Width At Distance", Range(0,8)) = 2
        _OutlineBackBoost ("Outline Backlit Boost", Range(1,3)) = 1.5
        _OutlineAlbedoTint ("Outline Albedo Tint", Range(0,1)) = 0.35

        [Header(Render)]
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
        [Toggle(_ALPHATEST_ON)] _AlphaTest ("Alpha Test", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _BaseColor;
            float4 _ShadowTint;
            float4 _SpecColor;
            float4 _RimColor;
            float4 _EmissionColor;
            float4 _OutlineColor;
            float4 _AmbientColor;
            float4 _SDFST;
            float4 _MatCapColor;
            float4 _DetailColor;
            float4 _IrisEdgeColor;
            float4 _EyeShadowColor;
            float _Cutoff;
            float _LightArea;
            float _ShadowSmooth;
            float _ShadowStrength;
            float _CastShadowStrength;
            float _IndirectIntensity;
            float _EmissionIntensity;
            float _SpecPow;
            float _SpecIntensity;
            float _SpecSoftness;
            float _RimPower;
            float _RimIntensity;
            float _RimLightFacing;
            float _OutlineWidth;
            float _OutlineMinDistance;
            float _OutlineBackBoost;
            float _OutlineAlbedoTint;
            float _AmbientFloor;
            float _HairSpecShift;
            float _HairSpecPow;
            float _HairSpecWidth;
            float _HairSpecIntensity;
            float _HairSpecMapStrength;
            float _Cull;
            float _FaceSDFDebug;
            float _SDFSmooth;
            float _SDFOffset;
            float _SDFFlip;
            float _SDFFlipV;
            float _SDFSideFlip;
            float _FaceSDFUV;
            float _NormalScale;
            float _NormalFlipY;
            float _ShadowMapStrength;
            float _UsePacked;
            float _MetallicChannel;
            float _SmoothnessChannel;
            float _AOChannel;
            float _AOStrength;
            float _SmoothnessMin;
            float _SmoothnessMax;
            float _MetallicSpecBoost;
            float _SpecNonMetalCap;
            float _DetailStrength;
            float _MatCapIntensity;
            float _MatCapFlipY;
            float _IrisEdgePower;
            float _IrisEdgeStrength;
            float _EyeSpecPower;
            float _EyeSpecIntensity;
            float _EyeShadowStrength;
            float _FaceAnalytic;
        CBUFFER_END

        TEXTURE2D(_BaseMap);        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_ShadowRamp);     SAMPLER(sampler_ShadowRamp);
        TEXTURE2D(_NormalMap);      SAMPLER(sampler_NormalMap);
        TEXTURE2D(_FaceSDF);        SAMPLER(sampler_FaceSDF);
        TEXTURE2D(_ShadowMap);      SAMPLER(sampler_ShadowMap);
        TEXTURE2D(_PackedMap);      SAMPLER(sampler_PackedMap);
        TEXTURE2D(_DetailMask);     SAMPLER(sampler_DetailMask);
        TEXTURE2D(_MatCap);         SAMPLER(sampler_MatCap);
        TEXTURE2D(_EmissionMap);    SAMPLER(sampler_EmissionMap);
        TEXTURE2D(_HairSpecMap);    SAMPLER(sampler_HairSpecMap);

        // RampTex 行约定（与 Vepley 文档一致）
        #define RAMP_ROW_ADD_SHADOW   0.125
        #define RAMP_ROW_METAL_SPEC   0.375
        #define RAMP_ROW_SPEC         0.625
        #define RAMP_ROW_DIRECT_SHADOW 0.875

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float4 tangentOS  : TANGENT;
            float2 uv         : TEXCOORD0;
            float2 uv1        : TEXCOORD1;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv         : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float3 normalWS   : TEXCOORD2;
            float3 tangentWS  : TEXCOORD3;
            float3 bitangentWS: TEXCOORD4;
            float  fogFactor  : TEXCOORD5;
            float2 uv1        : TEXCOORD6;
        };

        float3 SampleRamp(float rowV, float t)
        {
            return SAMPLE_TEXTURE2D(_ShadowRamp, sampler_ShadowRamp, float2(saturate(t), rowV)).rgb;
        }

        // 把 NdotL 重映射成 ramp 采样坐标：_LightArea 控制明暗分界位置，_ShadowSmooth 控制过渡宽度
        float ToonRampCoord(float ndotl)
        {
            float t = saturate(ndotl);
            // 以 _LightArea 为分界中心，向两侧展开 _ShadowSmooth 的过渡带
            float edge = saturate(1.0 - _LightArea);
            float lo = saturate(edge - _ShadowSmooth);
            float hi = saturate(edge + _ShadowSmooth);
            return smoothstep(lo, max(hi, lo + 1e-4), t);
        }

        // 通道选择器：0 = 不使用（返回 1），1..4 = R/G/B/A
        float PickChannel(float4 v, float idx)
        {
            if (idx < 0.5) return 1.0;
            if (idx < 1.5) return v.r;
            if (idx < 2.5) return v.g;
            if (idx < 3.5) return v.b;
            return v.a;
        }

        // Lizhiyan 的 _N 贴图是 RG 双通道（B 恒为 0），必须重建 Z，否则法线整片朝侧面
        float3 SampleNormalWS(float2 uv, float3 N, float3 T, float3 B)
        {
            float4 nm = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv);
            float2 rg = nm.rg * 2.0 - 1.0;
            rg.y *= _NormalFlipY;
            rg *= _NormalScale;
            rg = clamp(rg, -1.0, 1.0);
            float z = sqrt(saturate(1.0 - dot(rg, rg)));
            float3 nTS = normalize(float3(rg.x, rg.y, z));
            return normalize(T * nTS.x + B * nTS.y + N * nTS.z);
        }

        float3 SampleMatCap(float3 normalWS)
        {
            float3 nVS = TransformWorldToViewDir(normalWS, true);
            float2 mcUV = nVS.xy * 0.5 + 0.5;
            mcUV.y = lerp(mcUV.y, 1.0 - mcUV.y, _MatCapFlipY);
            return SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap, mcUV).rgb;
        }

        Varyings ToonVert(Attributes input)
        {
            Varyings o = (Varyings)0;
            VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
            VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

            o.positionCS = posInputs.positionCS;
            o.positionWS = posInputs.positionWS;
            o.normalWS = normInputs.normalWS;
            o.tangentWS = normInputs.tangentWS;
            o.bitangentWS = normInputs.bitangentWS;
            o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
            o.uv1 = input.uv1;
            o.fogFactor = ComputeFogFactor(posInputs.positionCS.z);
            return o;
        }

        // 脸部 SDF：用光源相对脸部的角度决定阴影边界，取代 NdotL 的球面明暗
        // 返回 1 = 全亮，0 = 全阴影
        float FaceSDFLit(float2 uv0, float2 uv1, float3 lightDirWS, out float rawSDF)
        {
            float3 faceFrontWS = normalize(TransformObjectToWorldDir(float3(0.0, 0.0, 1.0)));
            float3 faceRightWS = normalize(TransformObjectToWorldDir(float3(1.0, 0.0, 0.0)));

            float lightRight = dot(lightDirWS.xz, faceRightWS.xz);
            // 光越靠脸后侧，阈值越高 → 脸上阴影面积越大
            float lightBack = saturate(dot(-lightDirWS.xz, faceFrontWS.xz) * 0.5 + 0.5 + _SDFOffset);

            float2 sdfUV = lerp(uv0, uv1, _FaceSDFUV);
            sdfUV = sdfUV * _SDFST.xy + _SDFST.zw;
            sdfUV.y = lerp(sdfUV.y, 1.0 - sdfUV.y, _SDFFlipV);
            sdfUV.x = lerp(sdfUV.x, 1.0 - sdfUV.x, _SDFFlip);
            float sideFlip = (lightRight > 0.0 ? 1.0 : 0.0) * _SDFSideFlip;
            sdfUV.x = lerp(sdfUV.x, 1.0 - sdfUV.x, sideFlip);

            float sdf = SAMPLE_TEXTURE2D(_FaceSDF, sampler_FaceSDF, sdfUV).r;
            rawSDF = sdf;
            return smoothstep(lightBack - _SDFSmooth, lightBack + _SDFSmooth, sdf);
        }

        // 高光参数：阈值和软边都在"角度余弦"域，这样大小与软硬互相独立
        struct SpecParams
        {
            float edge;      // 余弦阈值，越大高光越小
            float softness;  // 余弦软边宽度
            float intensity;
            float cap;       // 非金属区域的高光衰减
            float boost;     // 金属区域的高光加成
            float metal;     // 0..1，金属/皮革遮罩
        };

        // 单个光源的卡通漫反射 + 高光
        float3 ToonLightContribution(
            float3 albedo, float3 normalWS, float3 viewDirWS,
            float3 lightDirWS, float3 lightColor, float shadowAtten, float distanceAtten,
            float rampT, float rampRowShadow, float rampRowSpec,
            SpecParams sp, float aoTerm, float shadowTexV)
        {
            rampT *= lerp(1.0, shadowAtten, _CastShadowStrength);

            float3 rampShadow = SampleRamp(rampRowShadow, rampT);
            float3 shadowTerm = lerp(float3(1,1,1), _ShadowTint.rgb * _ShadowStrength, 1.0 - saturate(rampT));
            // 逐像素阴影图只在暗部生效，亮部保持干净
            float stTerm = lerp(1.0, shadowTexV, 1.0 - saturate(rampT));
            float3 diffuse = albedo * rampShadow * shadowTerm * stTerm * aoTerm;

            // 角度域阈值：smoothness 只决定高光大小，_SpecSoftness 只决定边缘软硬
            float3 halfDir = SafeNormalize(lightDirWS + viewDirWS);
            float ndoth = saturate(dot(normalWS, halfDir));
            float specMask = smoothstep(sp.edge - sp.softness, sp.edge + sp.softness, ndoth);

            // 金属走 atlas 第 1 行（底色本来就是 0），非金属走第 3 行
            float specRow = lerp(rampRowSpec, RAMP_ROW_METAL_SPEC, step(0.5, sp.metal));
            float3 specRamp = SampleRamp(specRow, saturate(specMask));
            float3 specular = specRamp * specMask * _SpecColor.rgb * sp.intensity * sp.cap * sp.boost * shadowAtten;

            return (diffuse + specular) * lightColor * distanceAtten;
        }

        // Kayija-Kay 各向异性高光：沿切线方向出"带"而不是"点"
        float HairSpecBand(float3 T, float3 V, float3 L)
        {
            float TL = dot(T, L);
            float TV = dot(T, V);
            float sinTL = sqrt(max(0.0, 1.0 - TL * TL));
            float sinTV = sqrt(max(0.0, 1.0 - TV * TV));
            return saturate(sinTL * sinTV - TL * TV);
        }

        // 两条偏移的切线带出"天使环"的两级高光
        float HairSpecularBand(float3 N, float3 T, float3 V, float3 L)
        {
            float3 T1 = normalize(T + N * _HairSpecShift);
            float3 T2 = normalize(T - N * _HairSpecShift * 0.7);
            float k1 = pow(HairSpecBand(T1, V, L), _HairSpecPow);
            float k2 = pow(HairSpecBand(T2, V, L), _HairSpecPow);
            float w = _HairSpecWidth;
            float b1 = smoothstep(0.5 - w, 0.5 + w, k1);
            float b2 = smoothstep(0.6 - w * 0.6, 0.6 + w * 0.6, k2) * 0.65;
            return saturate(b1 + b2);
        }

        float4 ToonFrag(Varyings input) : SV_Target
        {
            float4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
            float3 albedo = baseTex.rgb * _BaseColor.rgb;
            float alpha = baseTex.a * _BaseColor.a;

            #ifdef _ALPHATEST_ON
                clip(alpha - _Cutoff);
            #endif

            float3 normalWS = normalize(input.normalWS);
            normalWS = SampleNormalWS(input.uv, normalWS,
                normalize(input.tangentWS), normalize(input.bitangentWS));

            float3 viewDirWS = SafeNormalize(GetWorldSpaceViewDir(input.positionWS));

            // ---- 打包遮罩（_P）：金属 / 平滑度 / AO
            float4 packed = SAMPLE_TEXTURE2D(_PackedMap, sampler_PackedMap, input.uv);
            float usePacked = step(0.5, _UsePacked);
            float metal = usePacked > 0.5 ? PickChannel(packed, _MetallicChannel) : 0.0;
            float smoothness = usePacked > 0.5 ? PickChannel(packed, _SmoothnessChannel) : 1.0;
            float ao = usePacked > 0.5 ? PickChannel(packed, _AOChannel) : 1.0;
            ao = lerp(1.0, ao, _AOStrength);

            // ---- 细节遮罩（_M）：做刺绣/花纹这类 albedo 混合
            float detail = SAMPLE_TEXTURE2D(_DetailMask, sampler_DetailMask, input.uv).r;
            albedo = lerp(albedo, _DetailColor.rgb, saturate(detail * _DetailStrength));

            // ---- 逐像素阴影图（_ST）
            float shadowTexV = SAMPLE_TEXTURE2D(_ShadowMap, sampler_ShadowMap, input.uv).r;
            shadowTexV = lerp(1.0, shadowTexV, _ShadowMapStrength);

            // ---- 高光参数：阈值落在角度余弦域；没有打包遮罩时用 _SpecPow 换算成等价阈值
            float metal01 = saturate(metal);
            float specEdge = usePacked > 0.5
                ? lerp(_SmoothnessMin, _SmoothnessMax, saturate(smoothness))
                : pow(0.5, 1.0 / max(_SpecPow, 1.0));
            SpecParams sp;
            sp.edge = specEdge;
            sp.softness = _SpecSoftness;
            sp.intensity = _SpecIntensity;
            sp.cap = lerp(_SpecNonMetalCap, 1.0, metal01);
            sp.boost = lerp(1.0, _MetallicSpecBoost, metal01);
            sp.metal = metal01;

            // SDF controls face shading directly; do not sample the main-light shadow map.
            #if defined(_FACE_SDF_ON)
                Light mainLight = GetMainLight();
            #else
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
            #endif

            float mainRampT = ToonRampCoord(dot(normalWS, mainLight.direction));
            float rawSDF = 0.0;
            float faceLit = 0.0;
            #if defined(_FACE_SDF_ON)
                faceLit = FaceSDFLit(input.uv, input.uv1, mainLight.direction, rawSDF);
                mainRampT = faceLit;
            #else
                if (_FaceSDFDebug > 0.5)
                {
                    faceLit = FaceSDFLit(input.uv, input.uv1, mainLight.direction, rawSDF);
                }
            #endif

            if (_FaceSDFDebug > 1.5)
            {
                return float4(rawSDF, rawSDF, rawSDF, 1.0);
            }
            if (_FaceSDFDebug > 0.5)
            {
                return float4(faceLit, faceLit, faceLit, 1.0);
            }

            // 没有 SDF 贴图时（例如 Lizhiyan），用"光相对脸朝向"的解析式代替，
            // 得到一条整体的软边界，而不是球面 N·L 那种脸部圆柱感
            #if !defined(_FACE_SDF_ON)
            if (_FaceAnalytic > 0.5)
            {
                float3 faceFrontWS = normalize(TransformObjectToWorldDir(float3(0.0, 0.0, 1.0)));
                float3 analyticLight = normalize(mainLight.direction + float3(0.0, -0.10, 0.0));
                mainRampT = smoothstep(-0.05, 0.45, dot(analyticLight, faceFrontWS));
            }
            #endif

            float3 color = ToonLightContribution(
                albedo, normalWS, viewDirWS,
                mainLight.direction, mainLight.color, mainLight.shadowAttenuation, mainLight.distanceAttenuation,
                mainRampT, RAMP_ROW_DIRECT_SHADOW, RAMP_ROW_SPEC,
                sp, ao, shadowTexV);

            // 附加光（点光/聚光）用第一行更柔的 ramp
            #if !defined(_FACE_SDF_ON)
            #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                for (uint i = 0u; i < lightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    float addRampT = ToonRampCoord(dot(normalWS, addLight.direction));
                    color += ToonLightContribution(
                        albedo, normalWS, viewDirWS,
                        addLight.direction, addLight.color, addLight.shadowAttenuation, addLight.distanceAttenuation,
                        addRampT, RAMP_ROW_ADD_SHADOW, RAMP_ROW_SPEC,
                        sp, ao, shadowTexV);
                }
            #endif
            #endif

            // 环境光：先给一个固定的暗部保底色（任何光位都不发黑），再叠加少量 SH 变化
            float3 shColor = SampleSH(normalWS);
            color += albedo * _AmbientColor.rgb * _AmbientFloor * ao;
            color += albedo * shColor * _IndirectIntensity * 0.35 * ao;

            // MatCap：金属件与布料的高光靠遮罩驱动，亮部叠加
            float matcapMask = saturate(metal) * saturate(mainRampT);
            float3 matcap = SampleMatCap(normalWS);
            color += matcap * _MatCapColor.rgb * _MatCapIntensity * matcapMask * ao;

            // 头发高光带：沿发丝的两级高光，独立于普通 Blinn-Phong
            #if defined(_HAIR_SPEC_ON)
                float hairBand = HairSpecularBand(
                    normalWS, normalize(input.tangentWS), viewDirWS, mainLight.direction);
                float3 bandColor = SAMPLE_TEXTURE2D(_HairSpecMap, sampler_HairSpecMap, float2(saturate(hairBand), 0.5)).rgb;
                bandColor = lerp(float3(1,1,1), bandColor, _HairSpecMapStrength);
                color += bandColor * _SpecColor.rgb * hairBand * _HairSpecIntensity
                       * mainLight.color * mainLight.shadowAttenuation;
            #endif

            // 眼睛：虹膜边缘压暗 + 高光点 + 眼白阴影
            #if defined(_EYE_ON)
                float irisEdge = pow(1.0 - saturate(dot(normalWS, viewDirWS)), _IrisEdgePower);
                color *= lerp(float3(1,1,1), _IrisEdgeColor.rgb, saturate(irisEdge) * _IrisEdgeStrength);
                float3 halfEye = SafeNormalize(mainLight.direction + viewDirWS);
                float eyeSpec = pow(saturate(dot(normalWS, halfEye)), _EyeSpecPower);
                color += _SpecColor.rgb * eyeSpec * _EyeSpecIntensity * mainLight.shadowAttenuation;
                float eyeShadow = saturate(1.0 - mainRampT) * _EyeShadowStrength;
                color = lerp(color, color * _EyeShadowColor.rgb, eyeShadow);
            #endif

            // 边缘光：只保留最外侧的窄带，避免整层泛白
            float fresnelRaw = 1.0 - saturate(dot(normalWS, viewDirWS));
            float fresnel = saturate((pow(fresnelRaw, _RimPower) - 0.45) * 2.2);
            float lightFacing = saturate(dot(normalWS, mainLight.direction) * 0.5 + 0.5);
            float rimMask = lerp(1.0, lightFacing, _RimLightFacing);
            color += _RimColor.rgb * fresnel * rimMask * _RimIntensity;

            // 自发光（_E）
            float3 emisTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, input.uv).rgb;
            color += emisTex * _EmissionColor.rgb * _EmissionIntensity;

            color = MixFog(color, input.fogFactor);

            return float4(color, alpha);
        }
        ENDHLSL

        // ---------------------------------------------------------------- 前向主 Pass
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull [_Cull]
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex ToonVert
            #pragma fragment ToonFrag

            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _FACE_SDF_ON
            #pragma shader_feature_local_fragment _HAIR_SPEC_ON
            #pragma shader_feature_local_fragment _EYE_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fog
            ENDHLSL
        }

        // ---------------------------------------------------------------- 投射阴影
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag

            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            ShadowVaryings ShadowVert(ShadowAttributes input)
            {
                ShadowVaryings o = (ShadowVaryings)0;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                o.positionCS = positionCS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            float4 ShadowFrag(ShadowVaryings input) : SV_Target
            {
                #ifdef _ALPHATEST_ON
                    float alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                    clip(alpha - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------- 深度预写
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            DepthVaryings DepthVert(DepthAttributes input)
            {
                DepthVaryings o = (DepthVaryings)0;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            float4 DepthFrag(DepthVaryings input) : SV_Target
            {
                #ifdef _ALPHATEST_ON
                    float alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                    clip(alpha - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------- 描边（反向外壳 + 屏幕空间恒宽）
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            struct OutlineAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct OutlineVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            OutlineVaryings OutlineVert(OutlineAttributes input)
            {
                OutlineVaryings o = (OutlineVaryings)0;
                float4 positionCS = TransformObjectToHClip(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                // 法线转到裁剪空间，只取 xy 方向做屏幕空间外扩 → 远近粗细一致
                float3 normalCS = mul((float3x3)UNITY_MATRIX_VP, normalWS);
                float2 dir = normalCS.xy;
                float len = max(length(dir), 1e-5);
                dir /= len;

                float aspect = _ScreenParams.y / max(_ScreenParams.x, 1.0);
                float2 aspectFix = float2(aspect, 1.0);

                // 背光侧更粗、受光侧更细：剪影在暗部才能"压住"
                float3 mainLightDir = normalize(_MainLightPosition.xyz);
                float facing = saturate(dot(normalWS, mainLightDir) * 0.5 + 0.5);
                float backBoost = lerp(_OutlineBackBoost, 1.0, facing);

                // 远处略微补偿，避免长焦镜头下描边彻底消失
                float farComp = lerp(1.0, 1.25, saturate((positionCS.w - 4.0) / 16.0));
                float distScale = saturate(positionCS.w / max(_OutlineMinDistance, 0.001));
                float width = _OutlineWidth * 0.005 * distScale * backBoost * farComp;

                positionCS.xy += dir * aspectFix * width * positionCS.w;
                o.positionCS = positionCS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            float4 OutlineFrag(OutlineVaryings input) : SV_Target
            {
                float4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                #ifdef _ALPHATEST_ON
                    clip(baseTex.a * _BaseColor.a - _Cutoff);
                #endif
                // 描边色向 albedo 暗部靠一点，避免一律死黑
                float3 albedoEdge = baseTex.rgb * _BaseColor.rgb * _OutlineColor.rgb * 2.0;
                float3 col = lerp(_OutlineColor.rgb, albedoEdge, _OutlineAlbedoTint);
                return float4(col, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
