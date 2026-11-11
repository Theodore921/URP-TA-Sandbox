// URP 12 风格化水面（第一版：深度色 + Fresnel + 双尺度波纹 + 宽高光，暂不含反射/折射）
// 参考数据来自终末地实拍采样：
//   陡视角 #112822 (linear 0.006,0.021,0.016) → 掠射 #B6D0D8 (0.469,0.634,0.688)
//   逆光高光带 #E0EBEE (0.749,0.834,0.863)
Shader "Custom/ToonWater"
{
    Properties
    {
        [Header(Base)]
        _ShallowColor ("Shallow / Steep Color", Color) = (0.070, 0.157, 0.171, 1)
        _DeepColor ("Deep Color", Color) = (0.006, 0.021, 0.016, 1)
        _DepthFade ("Depth Fade Distance", Range(0.01, 20)) = 1.2
        _DepthPower ("Depth Curve", Range(0.2, 4)) = 1
        _ShallowAlpha ("Shallow Alpha", Range(0,1)) = 0.15
        _DeepAlpha ("Deep Alpha", Range(0,1)) = 0.95

        [Header(Fresnel)]
        _HorizonColor ("Horizon Color", Color) = (0.469, 0.634, 0.688, 1)
        [Toggle(_REFLECT_SKY_ON)] _ReflectSky ("Reflect Sky Color", Float) = 1
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 3.2
        _FresnelStrength ("Fresnel Strength", Range(0, 2)) = 1
        _FresnelOpacity ("Fresnel Opacity", Range(0, 1)) = 0.55

        [Header(Planar Reflection)]
        _ReflectionStrength ("Reflection Strength", Range(0, 2)) = 1
        _ReflectionDistortion ("Reflection Distortion", Range(0, 0.2)) = 0.02
        _ReflectionBlur ("Reflection Blur (texels)", Range(0, 8)) = 2
        _ReflectionBlurDistance ("Blur Per Meter", Range(0, 0.2)) = 0.04
        _ReflectionHaze ("Reflection Haze", Range(0, 1)) = 0.6
        _HazeDistance ("Haze Distance", Range(5, 500)) = 80
        [HDR]_ReflectionTint ("Reflection Tint", Color) = (1,1,1,1)

        [Header(Ripples)]
        _NormalMap ("Ripple Normal 1", 2D) = "bump" {}
        _NormalMap2 ("Ripple Normal 2", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 0.55
        _Layer1Tiling ("Layer 1 Tiling", Float) = 0.35
        _Layer1Speed ("Layer 1 Speed", Float) = 0.03
        _Layer2Tiling ("Layer 2 Tiling", Float) = 0.09
        _Layer2Speed ("Layer 2 Speed", Float) = 0.012

        [Header(Specular)]
        [HDR]_SpecColor ("Spec Color", Color) = (0.749, 0.834, 0.863, 1)
        _SpecIntensity ("Spec Intensity", Range(0,4)) = 0.9
        _SpecThreshold ("Spec Threshold (cos)", Range(0.1, 0.99)) = 0.55
        _SpecSoftness ("Spec Softness (cos)", Range(0.01, 0.6)) = 0.22

        [Header(Foam)]
        _FoamColor ("Foam Color", Color) = (0.85, 0.9, 0.92, 1)
        _FoamWidth ("Foam Width", Range(0, 2)) = 0.06
        _FoamStrength ("Foam Strength", Range(0, 2)) = 0

        [Header(Interaction)]
        _WaterInteractRadius ("Fallback Radius", Float) = 0.6
        _WaterInteractStrength ("Push Strength", Range(0, 3)) = 1
        _RingFreq ("Ring Frequency", Range(1, 40)) = 12
        _RingSpeed ("Ring Speed", Range(0, 20)) = 4
        _RingDecay ("Ring Decay", Range(0.1, 8)) = 1.5
        _RingStrength ("Ring Strength", Range(0, 2)) = 0.5
        _FoamRingStrength ("Foam Ring Strength", Range(0, 2)) = 0.6
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "ToonWater"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma vertex WaterVert
            #pragma fragment WaterFrag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _ShallowColor;
                float4 _DeepColor;
                float4 _HorizonColor;
                float4 _SpecColor;
                float4 _FoamColor;
                float4 _NormalMap_ST;
                float4 _NormalMap2_ST;
                float _DepthFade;
                float _DepthPower;
                float _ShallowAlpha;
                float _DeepAlpha;
                float _FresnelPower;
                float _FresnelStrength;
                float _FresnelOpacity;
                float _ReflectSky;
                float _NormalStrength;
                float _Layer1Tiling;
                float _Layer1Speed;
                float _Layer2Tiling;
                float _Layer2Speed;
                float _SpecIntensity;
                float _SpecThreshold;
                float _SpecSoftness;
                float _FoamWidth;
                float _FoamStrength;
                float4 _ReflectionTint;
                float _ReflectionStrength;
                float _ReflectionDistortion;
                float _ReflectionBlur;
                float _ReflectionBlurDistance;
                float _ReflectionHaze;
                float _HazeDistance;
                float _WaterInteractRadius;
                float _WaterInteractStrength;
                float _RingFreq;
                float _RingSpeed;
                float _RingDecay;
                float _RingStrength;
                float _FoamRingStrength;
            CBUFFER_END

            // 每帧由 C# 写入的交互体数据（最多 8 个），不能放进 CBUFFER
            float4 _WaterActors[8];        // xyz = 世界位置, w = 影响半径
            float _WaterActorSpeed[8];     // 水平速度
            float _WaterActorCount;

            TEXTURE2D(_PlanarReflectionTex);
            SAMPLER(sampler_PlanarReflectionTex);
            float _PlanarReflectionOn;
            float4 _PlanarReflectionTex_TexelSize;

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_NormalMap2);
            SAMPLER(sampler_NormalMap2);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
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
            };

            Varyings WaterVert(Attributes input)
            {
                Varyings o = (Varyings)0;
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                o.positionCS = posInputs.positionCS;
                o.positionWS = posInputs.positionWS;
                o.normalWS = normInputs.normalWS;
                o.tangentWS = normInputs.tangentWS;
                o.bitangentWS = normInputs.bitangentWS;
                o.uv = input.uv;
                o.fogFactor = ComputeFogFactor(posInputs.positionCS.z);
                return o;
            }

            // 多个交互体（角色 / 漂浮物 / 球）的解析式"距离 + 梯度"
            // 关键：dist→0 时 dir 不稳定，必须用 bodyFade 在物体内部把扰动压到 0，
            // 否则中心会出现放射状尖刺
            float3 WaterNormalWS(Varyings input, out float interactMaskOut)
            {
                float t = _Time.y;
                float2 baseUV = input.positionWS.xz;
                float2 pushAccum = float2(0.0, 0.0);
                float2 ringAccum = float2(0.0, 0.0);
                float maskAccum = 0.0;

                int actorCount = (int)_WaterActorCount;
                for (int i = 0; i < 8; i++)
                {
                    if (i >= actorCount) break;

                    float4 actor = _WaterActors[i];
                    float2 d = input.positionWS.xz - actor.xz;
                    float dist = length(d);
                    float R = max(actor.w, 0.01);
                    if (dist > R) continue;

                    float2 dir = d / max(dist, 1e-4);
                    float speed = _WaterActorSpeed[i];

                    // 体内为 0（消除奇点）、外缘平滑衰减
                    float bodyFade = smoothstep(R * 0.18, R * 0.55, dist);
                    float outerFade = 1.0 - smoothstep(R * 0.70, R, dist);
                    float env = bodyFade * outerFade;

                    // 扩散环：沿径向的正弦，用导数（cos）做法线倾斜 → 环形水波
                    float phase = dist * _RingFreq - t * _RingSpeed;
                    float ring = cos(phase) * exp(-dist * _RingDecay)
                               * env * _RingStrength * saturate(speed);
                    ringAccum += dir * ring;

                    // 推开波纹 UV：让波纹从物体周围让开
                    pushAccum += dir * env * _WaterInteractStrength * 0.05 * saturate(speed + 0.25);

                    maskAccum = max(maskAccum, env);
                }

                interactMaskOut = maskAccum;
                baseUV += pushAccum;

                float2 uv1 = baseUV * _Layer1Tiling + t * _Layer1Speed * float2(1.0, 0.6);
                float2 uv2 = baseUV * _Layer2Tiling + t * _Layer2Speed * float2(-0.7, 0.45);

                float2 n1 = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv1).rg * 2.0 - 1.0;
                float2 n2 = SAMPLE_TEXTURE2D(_NormalMap2, sampler_NormalMap2, uv2).rg * 2.0 - 1.0;

                float2 nxy = (n1 + n2) * _NormalStrength + ringAccum * 0.15;

                nxy = clamp(nxy, -0.99, 0.99);
                float3 nTS = normalize(float3(nxy.x, nxy.y, sqrt(saturate(1.0 - dot(nxy, nxy)))));

                float3 N = normalize(input.normalWS);
                float3 T = normalize(cross(N, float3(0.0, 0.0, 1.0)));
                if (length(T) < 0.01) T = normalize(cross(N, float3(1.0, 0.0, 0.0)));
                float3 B = normalize(cross(N, T));
                return normalize(T * nTS.x + B * nTS.y + N * nTS.z);
            }

            float4 WaterFrag(Varyings input) : SV_Target
            {
                float3 N0 = normalize(input.normalWS);
                // 交互体（角色/球）对水面的扰动
                float interactMask;
                float3 N = WaterNormalWS(input, interactMask);
                float3 V = SafeNormalize(GetWorldSpaceViewDir(input.positionWS));

                // ---- 深度：水面到场景几何的距离，决定颜色与透明度
                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
                float rawDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float surfaceEyeDepth = -TransformWorldToView(input.positionWS).z;
                float depthDiff = max(0.0, sceneEyeDepth - surfaceEyeDepth);

                float depthT = saturate(depthDiff / max(_DepthFade, 0.001));
                depthT = pow(depthT, _DepthPower);

                float3 waterColor = lerp(_ShallowColor.rgb, _DeepColor.rgb, depthT);
                float alpha = lerp(_ShallowAlpha, _DeepAlpha, depthT);

                // ---- Fresnel：陡视角看底下，掠射看天空/雾色
                // 注意：用几何法线算 fresnel。用带波纹的法线会让掠射角下的高光/亮度整片抖动
                float ndotv = saturate(dot(N0, V));
                float fres = pow(1.0 - ndotv, _FresnelPower);
                fres = saturate(fres * _FresnelStrength);

                // ---- 平面反射：优先用镜像相机渲染的贴图，没有就退回地平线色
                float3 reflectColor = _HorizonColor.rgb;
                if (_PlanarReflectionOn > 0.5)
                {
                    float viewDist = input.positionCS.w;   // 视空间深度，近似到水面的距离
                    // 用波纹法线的世界 xz 扰动屏幕 UV，制造"水面扰动倒影"的感觉
                    float2 distortion = float2(N.x, N.z) * _ReflectionDistortion;
                    float2 reflUV = saturate(screenUV + distortion);

                    // 模糊半径随距离增长：近处清、远处糊，模拟粗糙水面
                    float radius = _ReflectionBlur + viewDist * _ReflectionBlurDistance;
                    float2 texel = _PlanarReflectionTex_TexelSize.xy * radius;

                    // 8 抽头旋转采样
                    static const float2 kOffsets[8] =
                    {
                        float2( 1.0,  0.0), float2(-1.0,  0.0),
                        float2( 0.0,  1.0), float2( 0.0, -1.0),
                        float2( 0.7,  0.7), float2(-0.7,  0.7),
                        float2( 0.7, -0.7), float2(-0.7, -0.7)
                    };

                    float3 acc = 0.0;
                    [unroll]
                    for (int i = 0; i < 8; i++)
                    {
                        acc += SAMPLE_TEXTURE2D(_PlanarReflectionTex, sampler_PlanarReflectionTex,
                                                saturate(reflUV + kOffsets[i] * texel)).rgb;
                    }
                    reflectColor = acc * 0.125 * _ReflectionTint.rgb;

                    // 空气透视：天空盒不参与雾计算，反射进来仍是全对比度，必须按距离冲淡
                    float hazeT = saturate(viewDist / max(_HazeDistance, 1.0)) * _ReflectionHaze;
                    reflectColor = lerp(reflectColor, _HorizonColor.rgb, hazeT);
                }

                waterColor = lerp(waterColor, reflectColor, fres * _ReflectionStrength);
                alpha = saturate(alpha + fres * _FresnelOpacity);

                // ---- 逆光高光：宽而碎的条带，靠法线扰动打碎
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                float3 H = SafeNormalize(mainLight.direction + V);
                float ndoth = saturate(dot(N, H));
                float specMask = smoothstep(_SpecThreshold - _SpecSoftness,
                                            _SpecThreshold + _SpecSoftness, ndoth);
                // 逆光时更亮：视线与光照方向越接近相反，高光带越明显
                float backlit = saturate(dot(-V, mainLight.direction) * 0.5 + 0.5);
                float3 spec = _SpecColor.rgb * specMask * _SpecIntensity
                            * mainLight.color * mainLight.shadowAttenuation
                            * lerp(0.35, 1.0, backlit);
                waterColor += spec;

                // ---- 岸线泡沫（默认关闭，参考图里基本没有程序化泡沫）
                float foam = saturate(1.0 - depthDiff / max(_FoamWidth, 0.001));
                waterColor = lerp(waterColor, _FoamColor.rgb, foam * _FoamStrength);
                alpha = saturate(alpha + foam * _FoamStrength * 0.6);

                // ---- 入水扰动：只留一圈很淡的接触泡沫，波纹交给法线扰动
                {
                    float contactFoam = pow(saturate(interactMask), 3.0) * _FoamRingStrength;
                    waterColor = lerp(waterColor, _FoamColor.rgb, saturate(contactFoam));
                    alpha = saturate(alpha + contactFoam * 0.3);
                }

                waterColor = MixFog(waterColor, input.fogFactor);

                return float4(waterColor, alpha);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
