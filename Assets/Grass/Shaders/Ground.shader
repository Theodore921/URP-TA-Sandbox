// ============================================================================
//  Ground.shader —— 草地场景的地面材质（PBR + 接触阴影）
//
//  为什么不直接用 URP Lit / Terrain Lit：
//    · Terrain/Lit 在这个项目里没有 control map 时会画成棋盘格
//    · 我们需要两个自定义能力：草地密度图压暗（接触阴影）、以后的路面掩码
//
//  ── 坐标约定 ────────────────────────────────────────────────────────────
//  地面是平面，用**世界 XZ 平面投影**采样，不依赖 UV 和切线：
//      uv  = worldPos.xz / _TilingMeters
//      T   = (1,0,0)   B = (0,0,1)   N = (0,1,0)
//  所以任意地形网格都能用，也不需要模型有切线数据。
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

            float4 _BaseColor, _DensityRange, _RoadRange, _RoadTint;
            float  _TilingMeters, _MacroTiling, _MacroStrength;
            float  _NormalScale, _RoughnessMin, _RoughnessMax, _SpecIntensity;
            float  _HeightDetail, _HeightAO;
            float  _DensityStrength, _DensityBoost;
            float  _RoadDarken, _RoadSmooth, _RoadNormalBoost;

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
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // ── 平面投影：世界 XZ ─────────────────────────────────────
                float2 uv = i.positionWS.xz / max(_TilingMeters, 0.01);

                // ── 基础色 + 宏观变化（打散平铺感）────────────────────────
                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).rgb;
                float  macro  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,
                                                 i.positionWS.xz / max(_TilingMeters * _MacroTiling, 0.01)).r;
                albedo *= lerp(1.0 - _MacroStrength, 1.0 + _MacroStrength, macro);
                albedo *= _BaseColor.rgb;

                // ── 切线基：平面地面直接用世界轴 ──────────────────────────
                float3 T = float3(1, 0, 0);
                float3 B = float3(0, 0, 1);
                float3 N = float3(0, 1, 0);

                // ── 法线贴图 ──────────────────────────────────────────────
                float3 nTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalScale);

                // ── 道路掩码 ──────────────────────────────────────────────
                float2 ruv = (i.positionWS.xz - _RoadRange.xy) / max(_RoadRange.z, 0.001) + 0.5;
                float  road = 0.0;
                if (all(ruv > 0.0) && all(ruv < 1.0))
                    road = SAMPLE_TEXTURE2D(_RoadMask, sampler_RoadMask, ruv).r;

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
