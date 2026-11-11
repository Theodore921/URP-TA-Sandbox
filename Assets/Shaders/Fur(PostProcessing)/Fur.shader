// 毛发「物体用」着色器：挂在 Body 这类模型上。
//
// 它和 Fur_blur.shader 是一条流水线上的两个角色：
//   · 本 shader 的 "UniversalForward" Pass -> 把物体正常画出来（底毛/皮肤，参与光照）
//   · 本 shader 的 "FurVector"      Pass -> 不画外观，只把「每像素毛发指令」写进 _FurVector
//   · Fur_blur.shader 的 Pass 0          -> 读 _FurVector，把画面颜色沿毛发方向抹开
//
// _FurVector 的编码约定（必须和 Fur_blur.shader 对齐，改一边就要同步改另一边）：
//   R,G : 屏幕空间毛发方向，[0,1] 编码，0.5 = 零向量。解码 dir = rg * 2 - 1
//   B   : 该像素的毛发长度（缩放系数），最终模糊半径 = _BlurStrength * B
//   A   : mask，毛发区域 1、非毛发 0（Fur_blur.shader 用它做 lerp 权重）
//
// 注意：方向在屏幕空间里**不做归一化**，而是保留 |投影| 的大小。
// 这样正对相机的毛（投影趋近 0）自然不产生拖影，轮廓处（完全在屏幕平面内）拖影最长，
// 视觉上就有了正确的透视缩短感。

Shader "HLSL/Fur"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)

        [Header(Fur Vector)]
        _FurDirTex ("Fur Noise (R)", 2D) = "gray" {}
        _FurDirection ("Comb Direction (Object Space)", Vector) = (0, 1, 0, 0)
        _FurDirNoise ("Direction Noise (turns)", Range(0, 2)) = 0.35
        _FurLength ("Fur Length", Range(0, 8)) = 1
        _FurLengthNoise ("Length Noise Blend", Range(0, 1)) = 0.5
        _FurMask ("Fur Mask", Range(0, 1)) = 1
        _FurNoiseTiling ("Noise Tiling", Float) = 4
        _FurThickness ("Fur Thickness (Object Space)", Range(0, 0.5)) = 0.1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        // 所有非贴图属性都放进同一个 CBUFFER，保持 SRP Batcher 兼容
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            float4 _FurDirection;
            float  _FurDirNoise;
            float  _FurLength;
            float  _FurLengthNoise;
            float  _FurMask;
            float  _FurNoiseTiling;
            float  _FurThickness;
            float4 _FurDirTex_ST;
        CBUFFER_END

        TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
        TEXTURE2D(_FurDirTex); SAMPLER(sampler_FurDirTex);
        ENDHLSL

        // ---------------------------------------------------------------
        // Pass 0：正常前向渲染（主光 + 阴影 + 球谐环境光）
        // 这个 Pass 是让 Body「看得见」的关键。之前的 Fur_blur.shader 一个
        // LightMode 都没有，所以 URP 的前向绘制根本不会画它。
        // ---------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex ForwardVertex
            #pragma fragment ForwardFragment

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
            };

            Varyings ForwardVertex(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   normalInputs   = GetVertexNormalInputs(IN.normalOS);

                OUT.positionHCS = positionInputs.positionCS;
                OUT.positionWS  = positionInputs.positionWS;
                OUT.normalWS    = normalInputs.normalWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.shadowCoord = GetShadowCoord(positionInputs);
                return OUT;
            }

            half4 ForwardFragment(Varyings IN) : SV_Target
            {
                float3 albedo   = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                float3 normalWS = normalize(IN.normalWS);

                Light mainLight = GetMainLight(IN.shadowCoord);
                float3 lighting = LightingLambert(mainLight.color, mainLight.direction, normalWS)
                                * mainLight.shadowAttenuation;
                lighting += SampleSH(normalWS);

                return half4(albedo * lighting, _BaseColor.a);
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // Pass 1：FurVector —— 整套方案的核心
        // 每个像素输出：方向(屏幕空间, 0.5为零) / 长度 / mask
        // ---------------------------------------------------------------
        Pass
        {
            Name "FurVector"
            Tags { "LightMode" = "FurVector" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex FurVectorVertex
            #pragma fragment FurVectorFragment

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
                float2 uv          : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
            };

            Varyings FurVectorVertex(Attributes IN)
            {
                Varyings OUT;
                // 沿法线把「毛壳」外扩出去。
                // 关键作用：让 _FurVector 覆盖物体轮廓**之外**的一圈像素。
                // 后面的模糊是对称的，只有壳层像素沿毛发方向采样时能采到身体颜色，
                // 也才能把身体颜色「拉」到轮廓外面，看起来才是毛支棱出来；
                // 不外扩的话，模糊只会把背景平均进轮廓内侧，物体只会显得边缘发虚、变小。
                float3 positionOS = IN.positionOS.xyz + IN.normalOS * _FurThickness;
                OUT.positionHCS = TransformObjectToHClip(positionOS);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = IN.uv;
                OUT.positionWS  = TransformObjectToWorld(positionOS);
                return OUT;
            }

            half4 FurVectorFragment(Varyings IN) : SV_Target
            {
                float3 n = NormalizeNormalPerPixel(IN.normalWS);

                // (1) 把「梳毛方向」投影到表面切平面上，得到毛流沿表面的走向。
                //     球面用固定方向梳会天然出现两个奇点（法线与梳毛方向平行的两极）。
                float3 comb       = normalize(_FurDirection.xyz);
                float3 tangentDir = comb - n * dot(n, comb);
                float  tangentLen = length(tangentDir);

                // 奇点处退化保护：换一根与法线不平行的参考轴
                float3 fallback = abs(n.x) < 0.9 ? float3(1, 0, 0) : float3(0, 0, 1);
                tangentDir = tangentLen > 1e-4
                    ? tangentDir / tangentLen
                    : normalize(fallback - n * dot(n, fallback));

                // (2) 用噪声绕法线旋转，把整齐的毛流打散成自然的杂毛
                float3 binormal = cross(n, tangentDir);
                float  noise    = SAMPLE_TEXTURE2D(_FurDirTex, sampler_FurDirTex, IN.uv * _FurNoiseTiling).r;

                float  angle      = (noise - 0.5) * 2.0 * PI * _FurDirNoise;
                float2 rotation   = float2(cos(angle), sin(angle));
                float3 furDirWS   = tangentDir * rotation.x + binormal * rotation.y;

                // (3) 投影到屏幕空间。
                //     rg 必须写成**单位方向**：Fur_blur.shader 的解码是
                //     motionVector = (rg*2-1) * _BlurStrength * b，长度完全交给 B 通道。
                //     如果保留投影长度，就会出现「球体中心(平滑区)抹得最狠、轮廓处归零」，
                //     而轮廓恰恰是唯一有对比度的地方 —— 结果就是完全看不出毛。
                //
                //     另外：毛流方向正对相机时投影退化到 0，此时改用表面法线的屏幕投影。
                //     法线在轮廓那一圈恰好是径向朝外，看起来就是毛从轮廓支棱出来。
                float2 dirSS    = mul((float3x3)UNITY_MATRIX_V, furDirWS).xy;
                float2 radialSS = mul((float3x3)UNITY_MATRIX_V, n).xy;
                float  proj     = saturate(length(dirSS) / 0.25);
                float2 dirUnit  = normalize(lerp(normalize(radialSS + 1e-6), normalize(dirSS + 1e-6), proj));
                float2 dirEncoded = dirUnit * 0.5 + 0.5;

                // (4) 长度：轮廓处(grazing 大)更长、正对相机更短，再叠噪声扰动。
                //     这里**不要** saturate：B 会乘上 _BlurStrength 才是实际模糊半径，
                //     钳在 1 会让 _FurLength 调大完全失效。
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - IN.positionWS);
                float  grazing   = 1.0 - saturate(abs(dot(n, viewDirWS)));
                float lengthValue = max(0.0, _FurLength * lerp(0.55, 1.0, grazing) * lerp(1.0, noise, _FurLengthNoise));
                float maskValue   = saturate(_FurMask);

                return half4(dirEncoded, lengthValue, maskValue);
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // Pass 2：ShadowCaster（让物体能正常投影）
        // ---------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowVertex
            #pragma fragment ShadowFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // URP 每帧设置这两个全局量（不放 CBUFFER，避免和 UnityPerMaterial 冲突）
            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct ShadowVaryings
            {
                float4 positionHCS : SV_POSITION;
            };

            ShadowVaryings ShadowVertex(ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.positionHCS = positionCS;
                return OUT;
            }

            half4 ShadowFragment(ShadowVaryings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // Pass 3：DepthOnly（深度预通道；URP 需要时才会跑）
        // ---------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            Cull Back
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthVertex
            #pragma fragment DepthFragment

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
            };

            struct DepthVaryings
            {
                float4 positionHCS : SV_POSITION;
            };

            DepthVaryings DepthVertex(DepthAttributes IN)
            {
                DepthVaryings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 DepthFragment(DepthVaryings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // Pass 4：DepthNormals
        // 场景里的 SSAO 用的是「Depth Normals」作为输入源，缺了这个 Pass
        // 物体就不会出现在法线缓冲里，SSAO 会把它当成背景。
        // ---------------------------------------------------------------
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile _ _GBUFFER_NORMALS_OCT

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

            struct DepthNormalsAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct DepthNormalsVaryings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
            };

            DepthNormalsVaryings DepthNormalsVertex(DepthNormalsAttributes IN)
            {
                DepthNormalsVaryings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            half4 DepthNormalsFragment(DepthNormalsVaryings IN) : SV_Target
            {
                float3 normalWS = NormalizeNormalPerPixel(IN.normalWS);

                #if defined(_GBUFFER_NORMALS_OCT)
                    float2 octNormalWS = PackNormalOctQuadEncode(normalWS);
                    float2 remapped    = saturate(octNormalWS * 0.5 + 0.5);
                    half3  packed      = PackFloat2To888(remapped);
                    return half4(packed, 0.0);
                #else
                    return half4(normalWS, 0.0);
                #endif
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
