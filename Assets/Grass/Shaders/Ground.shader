// ============================================================================
//  Ground.shader —— 草地场景的地面材质（PBR + 接触阴影）
//
//  使用自定义 Terrain shader：
//    · 保留草地密度图接触阴影和道路掩码
//    · 同时读取 Unity Terrain 的 control map，混合最多四个 Terrain Layer
//
//  Terrain Layer 使用 Terrain UV 和各自的平铺设置；细节贴图、道路掩码
//  和草地密度图继续使用世界 XZ 坐标。
//
//  ── Displacement 的用法 ────────────────────────────────────────────────
//  URP 12 没有曲面细分，位移图**不能真的把顶点顶起来**。
//  这里按方案 A 使用：拿它求梯度叠加到法线上（颗粒起伏），
//  再用它做一层细节 AO（凹处更暗）。
//  如果以后要真的车辙，需要把高度烘进 Terrain 的 heightmap。
// ============================================================================

Shader "Grass/Ground"
{
    Properties
    {
        [Header(Base Color)]
        _BaseColor          ("地面色调", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _BaseMap ("颜色图 (Color, sRGB)", 2D) = "white" {}
        _TilingMeters       ("平铺：多少米一张图", Float) = 4.0
        _MacroTiling        ("宏观平铺倍率（打散重复）", Float) = 7.0
        _MacroStrength      ("宏观明暗变化", Range(0, 1)) = 0.25

        [Header(Normal and Roughness)]
        [NoScaleOffset] _NormalMap ("法线图 (NormalGL)", 2D) = "bump" {}
        _NormalScale        ("法线强度", Range(0, 2)) = 1.0
        [NoScaleOffset] _RoughnessMap ("粗糙度图 (R)", 2D) = "white" {}
        _RoughnessMin       ("粗糙度下限", Range(0, 1)) = 0.55
        _RoughnessMax       ("粗糙度上限", Range(0, 1)) = 1.0
        _SpecIntensity      ("高光强度", Range(0, 2)) = 0.55

        [Header(Height Detail)]
        [NoScaleOffset] _HeightMap ("高度图 (Displacement)", 2D) = "gray" {}
        _HeightDetail       ("高度→法线细节", Range(0, 4)) = 1.2
        _HeightAO           ("高度→细节 AO", Range(0, 1)) = 0.45

        [Header(Contact Shadow)]
        [NoScaleOffset] _DensityTex ("草地密度图 (R)", 2D) = "black" {}
        _DensityStrength    ("接触阴影强度", Range(0, 1)) = 0.72
        _DensityBoost       ("密度增益", Range(0.5, 4)) = 1.6
        _DensityRange       ("密度图世界范围 (中心X, 中心Z, 尺寸, 0)", Vector) = (0, 0, 120, 0)

        [Header(Road)]
        [NoScaleOffset] _RoadMask ("道路掩码 (R)", 2D) = "black" {}
        _RoadRange          ("掩码世界范围 (中心X, 中心Z, 尺寸, 0)", Vector) = (0, 0, 120, 0)
        _RoadTint           ("路面色调", Color) = (0.95, 0.80, 0.62, 1)
        _RoadDarken         ("路面压暗", Range(0, 1)) = 0.30
        _RoadSmooth         ("路面光滑度增量", Range(0, 1)) = 0.35
        _RoadNormalBoost    ("路面法线增强", Range(0, 3)) = 1.6
        _RoadMaskToLayer    ("道路掩码混合到 Terrain Layer 2", Range(0, 1)) = 0

        [Header(Terrain Layers)]
        _TerrainLayerTint0  ("Terrain Layer 0 色调", Color) = (1, 1, 1, 1)
        _TerrainLayerTint1  ("Terrain Layer 1 色调", Color) = (1, 1, 1, 1)
        _TerrainLayerTint2  ("Terrain Layer 2 色调", Color) = (1, 1, 1, 1)
        _TerrainLayerTint3  ("Terrain Layer 3 色调", Color) = (1, 1, 1, 1)

        [HideInInspector] [PerRendererData] _Control ("Control (RGBA)", 2D) = "red" {}
        [HideInInspector] [PerRendererData] _Splat0 ("Layer 0 (R)", 2D) = "white" {}
        [HideInInspector] [PerRendererData] _Splat1 ("Layer 1 (G)", 2D) = "white" {}
        [HideInInspector] [PerRendererData] _Splat2 ("Layer 2 (B)", 2D) = "white" {}
        [HideInInspector] [PerRendererData] _Splat3 ("Layer 3 (A)", 2D) = "white" {}
        [HideInInspector] [PerRendererData] _Normal0 ("Normal 0 (R)", 2D) = "bump" {}
        [HideInInspector] [PerRendererData] _Normal1 ("Normal 1 (G)", 2D) = "bump" {}
        [HideInInspector] [PerRendererData] _Normal2 ("Normal 2 (B)", 2D) = "bump" {}
        [HideInInspector] [PerRendererData] _Normal3 ("Normal 3 (A)", 2D) = "bump" {}
        [HideInInspector] [PerRendererData] _Smoothness0 ("Smoothness 0", Range(0, 1)) = 0.5
        [HideInInspector] [PerRendererData] _Smoothness1 ("Smoothness 1", Range(0, 1)) = 0.5
        [HideInInspector] [PerRendererData] _Smoothness2 ("Smoothness 2", Range(0, 1)) = 0.5
        [HideInInspector] [PerRendererData] _Smoothness3 ("Smoothness 3", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "TerrainCompatible" = "True"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);       SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);     SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RoughnessMap);  SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_HeightMap);     SAMPLER(sampler_HeightMap);
            TEXTURE2D(_DensityTex);    SAMPLER(sampler_DensityTex);
            TEXTURE2D(_RoadMask);      SAMPLER(sampler_RoadMask);
            TEXTURE2D(_Control);       SAMPLER(sampler_Control);
            TEXTURE2D(_Splat0);        SAMPLER(sampler_Splat0);
            TEXTURE2D(_Splat1);
            TEXTURE2D(_Splat2);
            TEXTURE2D(_Splat3);
            TEXTURE2D(_Normal0);       SAMPLER(sampler_Normal0);
            TEXTURE2D(_Normal1);
            TEXTURE2D(_Normal2);
            TEXTURE2D(_Normal3);

            float4 _BaseColor, _DensityRange, _RoadRange, _RoadTint;
            float4 _Control_TexelSize;
            float4 _Splat0_ST, _Splat1_ST, _Splat2_ST, _Splat3_ST;
            float4 _TerrainLayerTint0, _TerrainLayerTint1;
            float4 _TerrainLayerTint2, _TerrainLayerTint3;
            float  _TilingMeters, _MacroTiling, _MacroStrength;
            float  _NormalScale, _RoughnessMin, _RoughnessMax, _SpecIntensity;
            float  _HeightDetail, _HeightAO;
            float  _DensityStrength, _DensityBoost;
            float  _RoadDarken, _RoadSmooth, _RoadNormalBoost;
            float  _RoadMaskToLayer;
            float  _Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3;
            float  _NormalScale0, _NormalScale1, _NormalScale2, _NormalScale3;

            // 全局变量（不挂在材质上）：GrassField 启用时 = 1，禁用时 = 0。
            // 临时关掉草地时，地面上那块"草根阴影"会一起消失，
            // 不会留下一团看不懂的黑斑。
            float  _GrassContactShadow;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float  fogFactor   : TEXCOORD1;
                float4 shadowCoord : TEXCOORD2;
                float2 terrainUV   : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                // Terrain 开了 Draw Instanced 时，顶点变换必须走实例矩阵
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);

                o.positionCS  = p.positionCS;
                o.positionWS  = p.positionWS;
                o.fogFactor   = ComputeFogFactor(p.positionCS.z);
                o.shadowCoord = TransformWorldToShadowCoord(p.positionWS);
                o.terrainUV   = v.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // ── 平面投影：世界 XZ ─────────────────────────────────────
                float2 uv = i.positionWS.xz / max(_TilingMeters, 0.01);

                // ── Terrain Layer splat 混合 ─────────────────────────────
                // Terrain control map uses RGBA for layers 0-3. Match URP Terrain's
                // half-texel sampling so painted layer edges stay aligned.
                float2 controlUV = (i.terrainUV * (_Control_TexelSize.zw - 1.0) + 0.5)
                                 * _Control_TexelSize.xy;
                float4 layerWeights = SAMPLE_TEXTURE2D(_Control, sampler_Control, controlUV);
                float weightSum = dot(layerWeights, 1.0);
                layerWeights = weightSum > 1e-5
                    ? layerWeights / weightSum
                    : float4(1.0, 0.0, 0.0, 0.0);

                // Optionally let the spline mask drive Terrain Layer 2. Keep this
                // disabled until a Road diffuse texture has been assigned.
                float2 ruv = (i.positionWS.xz - _RoadRange.xy) / max(_RoadRange.z, 0.001) + 0.5;
                float road = 0.0;
                if (all(ruv > 0.0) && all(ruv < 1.0))
                    road = SAMPLE_TEXTURE2D(_RoadMask, sampler_RoadMask, ruv).r;

                float otherWeight = layerWeights.r + layerWeights.g + layerWeights.a;
                float roadWeight = max(layerWeights.b, road * _RoadMaskToLayer);
                float remainingWeight = 1.0 - roadWeight;
                if (otherWeight > 1e-5)
                {
                    float otherScale = remainingWeight / otherWeight;
                    layerWeights.r *= otherScale;
                    layerWeights.g *= otherScale;
                    layerWeights.a *= otherScale;
                }
                else
                {
                    layerWeights.r = 0.0;
                    layerWeights.g = 0.0;
                    layerWeights.a = 0.0;
                }
                layerWeights.b = roadWeight;

                float4 splat0 = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0,
                    i.terrainUV * _Splat0_ST.xy + _Splat0_ST.zw);
                float4 splat1 = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat0,
                    i.terrainUV * _Splat1_ST.xy + _Splat1_ST.zw);
                float4 splat2 = SAMPLE_TEXTURE2D(_Splat2, sampler_Splat0,
                    i.terrainUV * _Splat2_ST.xy + _Splat2_ST.zw);
                float4 splat3 = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat0,
                    i.terrainUV * _Splat3_ST.xy + _Splat3_ST.zw);

                float3 albedo = splat0.rgb * _TerrainLayerTint0.rgb * layerWeights.r
                              + splat1.rgb * _TerrainLayerTint1.rgb * layerWeights.g
                              + splat2.rgb * _TerrainLayerTint2.rgb * layerWeights.b
                              + splat3.rgb * _TerrainLayerTint3.rgb * layerWeights.a;

                // ── 宏观变化（打散平铺感）─────────────────────────────────
                float  macro  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,
                                                 i.positionWS.xz / max(_TilingMeters * _MacroTiling, 0.01)).r;
                albedo *= lerp(1.0 - _MacroStrength, 1.0 + _MacroStrength, macro);
                albedo *= _BaseColor.rgb;

                // ── 切线基：平面地面直接用世界轴 ──────────────────────────
                float3 T = float3(1, 0, 0);
                float3 B = float3(0, 0, 1);
                float3 N = float3(0, 1, 0);

                // ── 法线贴图 ──────────────────────────────────────────────
                float3 baseNormal = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalScale);
                float3 terrainNormal =
                    UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal0, sampler_Normal0,
                        i.terrainUV * _Splat0_ST.xy + _Splat0_ST.zw), _NormalScale0) * layerWeights.r
                  + UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal1, sampler_Normal0,
                        i.terrainUV * _Splat1_ST.xy + _Splat1_ST.zw), _NormalScale1) * layerWeights.g
                  + UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal2, sampler_Normal0,
                        i.terrainUV * _Splat2_ST.xy + _Splat2_ST.zw), _NormalScale2) * layerWeights.b
                  + UnpackNormalScale(SAMPLE_TEXTURE2D(_Normal3, sampler_Normal0,
                        i.terrainUV * _Splat3_ST.xy + _Splat3_ST.zw), _NormalScale3) * layerWeights.a;
                float3 nTS = normalize(float3(
                    baseNormal.xy + terrainNormal.xy,
                    baseNormal.z * terrainNormal.z));

                // 路面上：法线更明显（被踩出来的颗粒感）
                nTS = normalize(float3(nTS.xy * lerp(1.0, _RoadNormalBoost, road), nTS.z));

                // 路面偏暖褐、压暗（裸土比长草的土更暗更"实"）
                albedo = lerp(albedo, albedo * _RoadTint.rgb, road);
                albedo *= lerp(1.0, 1.0 - _RoadDarken, road);

                // ── 高度图 → 细节法线（方案 A：不位移，只扰动法线）────────
                float2 texel = 1.0 / 1024.0;
                float  hC = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r;
                float  hX = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv + float2(texel.x, 0)).r;
                float  hY = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv + float2(0, texel.y)).r;
                float2 grad = float2(hX - hC, hY - hC) * _HeightDetail * 12.0;
                nTS = normalize(float3(nTS.xy + grad, nTS.z));

                float3 Nw = normalize(T * nTS.x + N * nTS.z + B * nTS.y);

                // ── 粗糙度 / 平滑度 ───────────────────────────────────────
                float rough = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, uv).r;
                rough = lerp(_RoughnessMin, _RoughnessMax, rough);
                float terrainSmoothness = dot(layerWeights,
                    float4(_Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3));
                rough = lerp(rough, 1.0 - terrainSmoothness, 0.5);
                // 被踩实的路面更光滑一点（会有一层柔和的反光）
                rough = lerp(rough, max(rough - _RoadSmooth, 0.12), road);
                float smoothness = 1.0 - rough;

                // ── 接触阴影：按草地密度压暗地面 ──────────────────────────
                float size = max(_DensityRange.z, 0.001);
                float2 duv = (i.positionWS.xz - _DensityRange.xy) / size + 0.5;
                float  dens = 0.0;
                if (all(duv > 0.0) && all(duv < 1.0))
                    dens = SAMPLE_TEXTURE2D(_DensityTex, sampler_DensityTex, duv).r;

                float occ = 1.0 - _DensityStrength * _GrassContactShadow * saturate(dens * _DensityBoost);
                occ *= lerp(1.0, saturate(hC * 1.6), _HeightAO);
                albedo *= occ;

                // ── 光照 ──────────────────────────────────────────────────
                Light mainLight = GetMainLight(i.shadowCoord);
                float3 L = normalize(mainLight.direction);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 H = normalize(L + V);

                float ndl = saturate(dot(Nw, L));
                float3 diffuse = albedo * mainLight.color.rgb * ndl
                               * mainLight.distanceAttenuation * mainLight.shadowAttenuation;

                float3 ambient = SampleSH(Nw) * albedo;

                // 简化 GGX：光滑处（湿泥）出现柔和高光
                float shine = exp2(lerp(3.0, 11.0, smoothness));
                float specTerm = pow(saturate(dot(Nw, H)), shine) * (shine + 8.0) * 0.008;
                float3 spec = mainLight.color.rgb * specTerm * smoothness * _SpecIntensity;

                float3 col = diffuse + ambient + spec;

                col = MixFog(col, i.fogFactor);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }
    }

    FallBack Off
}
