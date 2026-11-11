// ============================================================================
//  Skybox/StylizedSkybox —— 风格化天空球（整合版）
//
//  参考：知乎《风格化天空球》 Shin
//        https://zhuanlan.zhihu.com/p/420268006
//  管线：URP 12.1.15 / Unity 2021.3.45f1c2
//
//  ── 整合思路 ──────────────────────────────────────────────────────────────
//  原文的 9 段代码不是 9 个独立 shader，而是同一个 shader 里的 9 个"零件"。
//  本文件把它们拆成独立的函数，再在一个 fragment 里按"由远及近"的顺序叠加：
//
//      ① 基础渐变     ← 代码块 #1  GradientSkyReckon
//      ③ 星空         ← 代码块 #8  GetStar
//      ④ 月亮         ← 代码块 #4（屏幕空间）/ #5+#6（矩阵）二选一
//      ⑤ 太阳 + 光晕  ← 代码块 #2  calcSunAttenuation + #3 SunReckon
//      ⑥ 云层         ← 代码块 #7  RotateAroundYInDegrees / CloudUV / GetRotateCloud
//      ⑧ 地面         ← 文章「一、天空球配色」提到的地面颜色（原文未给代码）
//      ⑦ 天际线       ← 代码块 #9  EdgeHorizonReckon
//
//  注意：地面被放在月亮/太阳**之后**绘制。地平线以下的一切（落日、矩阵方案里
//  那个镜像月亮）都会被地面盖住，避免它们浮在地面之上。
//
//  叠加方式统一为  color = lerp(color, 本层颜色, 本层覆盖率)
//  所以任何一层都能单独关掉（强度设 0）而不影响其它层。这是把零件拼成整机的关键：
//  原文各段之间没有耦合，只要约定好"谁先画、谁盖谁"就可以了。
//
//  依赖（必须由 C# 提供，否则月亮不显示）：
//        Shader.SetGlobalMatrix("_MoonMatrix", moonTransform.worldToLocalMatrix);
//  代码块 #5 的那一行。在接上之前，_MoonIntensity 请保持 0。
// ============================================================================

Shader "Skybox/StylizedSkybox"
{
    Properties
    {
        // ── ① 基础渐变 ───────────────────────────────────────────────────────
        [Header(Base Gradient)]
        _SkyTopColor        ("白天 天空顶部", Color) = (0.118, 0.306, 0.780, 1)
        _SkyBottomColor     ("白天 天空底部", Color) = (0.760, 0.855, 0.960, 1)
        _SkyTopColorDusk    ("黄昏 天空顶部", Color) = (0.18, 0.16, 0.42, 1)
        _SkyBottomColorDusk ("黄昏 天空底部", Color) = (1.0, 0.52, 0.28, 1)
        _SkyTopColorNight   ("夜晚 天空顶部", Color) = (0.012, 0.018, 0.055, 1)
        _SkyBottomColorNight("夜晚 天空底部", Color) = (0.05, 0.07, 0.15, 1)
        _SkyGradientExponent("渐变指数 SkyGradientExponent", Range(0.05, 10)) = 1.5

        // ── ② 地面 ──────────────────────────────────────────────────────────
        _GroundColor    ("地面颜色", Color) = (0.22, 0.21, 0.19, 1)
        _GroundSharpness("地面过渡锐度", Range(0.001, 0.5)) = 0.05

        // ── ③ 星空 ──────────────────────────────────────────────────────────
        [Header(Stars)]
        _StarsTex     ("星点贴图", 2D) = "black" {}
        _StarMaskTex  ("星空遮罩贴图", 2D) = "white" {}
        _StarsColor   ("星星颜色", Color) = (0.85, 0.88, 1.0, 1)
        _StarsSize    ("星点密度 _StarsSize", Float) = 20
        _StarMaskSize ("遮罩密度 _StarMaskSize", Float) = 5
        _StarsSpeed   ("流动速度 _StarsSpeed", Float) = 0.01
        _StarsIntensity("星星强度", Range(0, 2)) = 1
        _StarHorizonFade("地平线消光强度 (0=不淡出)", Range(0, 2)) = 0.35
        _StarTwinkle  ("闪烁强度 (0=不闪)", Range(0, 1)) = 0.35
        _StarTwinkleSpeed("闪烁速度 (弧度/秒)", Range(0, 30)) = 4
        _NightSign    ("昼夜符号 _NightSign (-1 白天不显星)", Float) = -1

        // ── ④ 月亮 ──────────────────────────────────────────────────────────
        [Header(Moon)]
        _MoonTex      ("月亮贴图(带Alpha)", 2D) = "black" {}
        _MoonColor    ("月亮颜色", Color) = (0.90, 0.93, 1.0, 1)
        _MoonRadius   ("月亮大小 _MoonRadius (越大月亮越小)", Range(1, 60)) = 20
        _MoonIntensity("月亮强度 (需C#驱动, 未接驱动请保持0)", Range(0, 1)) = 0
        [Toggle(MOON_SCREENSPACE)] _MoonScreenSpace ("用屏幕空间方案(#4, 会有畸变)", Float) = 0

        // ── ⑤ 太阳 ──────────────────────────────────────────────────────────
        [Header(Sun)]
        _SunColor       ("日盘颜色 sunColor", Color) = (1.0, 0.97, 0.88, 1)
        _SunHaloColor   ("光晕颜色 litColor", Color) = (1.0, 0.72, 0.42, 1)
        _SunHaloExponent("光晕指数 sunHaloExponent", Range(1, 512)) = 64
        _SunHaloIntensity("光晕强度", Range(0, 4)) = 1
        _SunRadius      ("日盘角半径 (SIMPLE 模式)", Range(0.0001, 0.1)) = 0.02
        [Toggle(SUN_HQ)] _SunDiskHQ ("高质量日盘 (HQ / Cornette-Shanks)", Float) = 0
        _SunSize        ("HQ 日盘大小 _SunSize (越大越锐利)", Range(0.001, 1)) = 0.15
        _SunSizeConvergence("HQ 收敛 _SunSizeConvergence", Range(1, 10)) = 3

        // ── ⑥ 云层 ──────────────────────────────────────────────────────────
        [Header(Clouds)]
        _CloudTex          ("云层贴图 (R 通道)", 2D) = "black" {}
        _CloudColor        ("云层颜色", Color) = (1, 1, 1, 1)
        _CloudOpacity      ("云层不透明度", Range(0, 1)) = 1
        _CloudRotationSpeed("云层旋转速度 (度每秒)", Float) = 2
        _CloudCoverage     ("云覆盖率阈值 (越大云越少)", Range(0, 1)) = 0.38
        _CloudSoftness     ("云边缘柔和度", Range(0.01, 0.6)) = 0.25
        _CloudWarp         ("平铺域扭曲强度", Range(0, 0.15)) = 0.04
        _CloudMacro        ("宏观云量变化", Range(0, 0.4)) = 0.15
        _CloudMacroScale   ("宏观变化尺度", Range(0.02, 0.5)) = 0.12
        [Toggle(CLOUD_PLANAR)] _CloudPlanar ("启用平面投影云层", Float) = 0
        _CloudPlaneHeight  ("云层高度 (米)", Float) = 700
        _CloudScale        ("云层纹理缩放 (每米)", Float) = 0.005
        _CloudHorizonFade  ("地平线淡出范围", Range(0.01, 0.6)) = 0.12

        [Header(Clouds Lighting)]
        _CloudLitColor     ("云受光色", Color) = (1, 1, 1, 1)
        _CloudShadowColor  ("云阴影色", Color) = (0.35, 0.42, 0.52, 1)
        _CloudSunIntensity ("受光强度", Range(0, 4)) = 1
        _CloudBumpScale    ("密度起伏强度", Range(0, 3)) = 1
        _CloudBumpOffset   ("梯度采样偏移 (UV)", Range(0.0005, 0.02)) = 0.004
        _CloudShadowAbsorb ("云自阴影吸收", Range(0.1, 8)) = 2
        _CloudShadowFloor  ("云阴影环境光底", Range(0, 1)) = 0.15
        _CloudShadowStep   ("自阴影取样步长 (米)", Range(10, 2000)) = 200
        _CloudShadowSlant  ("自阴影斜射修正 (0=关闭)", Range(0, 1)) = 1
        _CloudPhaseG       ("散射相位 g (越大前向越强)", Range(0, 0.95)) = 0.7
        _CloudPhaseIntensity("散射相位强度", Range(0, 4)) = 1

        [Header(Clouds Layer 2 High)]
        _Cloud2Enable       ("启用高层云", Range(0, 1)) = 1
        _Cloud2Height       ("高层云高度 (米)", Float) = 2200
        _Cloud2Scale        ("高层云纹理缩放 (每米)", Float) = 0.0003
        _Cloud2Coverage     ("高层云覆盖率", Range(0, 1)) = 0.45
        _Cloud2Softness     ("高层云柔和度", Range(0.01, 0.6)) = 0.35
        _Cloud2Opacity      ("高层云不透明度", Range(0, 1)) = 0.55
        _Cloud2RotationSpeed("高层云旋转速度 (度每秒)", Float) = 0.6
        _Cloud2Color        ("高层云颜色", Color) = (1, 1, 1, 1)

        [Header(Clouds Legacy Dome)]
        _CloudHeightFade   ("旧方案地平线高度遮罩", Range(0.01, 1)) = 0.25

        // ── ⑦ 天际线 ────────────────────────────────────────────────────────
        [Header(Horizon)]
        _HorizonColor       ("天际线颜色 skyEdgeCol", Color) = (1.0, 0.78, 0.55, 1)
        _HorizonLineExponent("horizonLineExponent", Range(1, 512)) = 64
        _HorizonPower       ("horizonPower (原文保留参数, 暂未使用)", Range(0, 4)) = 1
        _HorizonContribution("contribution", Range(0, 1)) = 0.5

        // ── 输出 ────────────────────────────────────────────────────────────
        [Header(Output)]
        _Tint    ("整体染色", Color) = (1, 1, 1, 1)
        _Exposure("曝光", Range(0, 8)) = 1
    }

    SubShader
    {
        // 天空盒必须打上这三个 Tag，URP 才会把它当天空盒绘制
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "IgnoreProjector"="True" }

        Cull Off
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target 3.0

            // 白天 / 高质量日盘 / 月亮方案 —— 三个局部变体开关
            #pragma shader_feature_local SUN_HQ
            #pragma shader_feature_local MOON_SCREENSPACE
            #pragma shader_feature_local CLOUD_PLANAR

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Core.hlsl → Input.hlsl 已声明 _MainLightPosition、_ScreenParams、
            // _ProjectionParams、UNITY_MATRIX_V / _VP，以及 TEXTURE2D/SAMPLER 宏
            // 与 ComputeScreenPos()，无需再 include Lighting.hlsl。

            // =================================================================
            //  贴图与常量
            // =================================================================
            TEXTURE2D(_StarsTex);     SAMPLER(sampler_StarsTex);
            TEXTURE2D(_StarMaskTex);  SAMPLER(sampler_StarMaskTex);
            TEXTURE2D(_MoonTex);      SAMPLER(sampler_MoonTex);
            TEXTURE2D(_CloudTex);     SAMPLER(sampler_CloudTex);

            // 代码块 #5：由 C# 每帧写入的月亮世界→局部矩阵（全局变量，不在 Properties 里）
            float4x4 _MoonMatrix;
            // 月亮在天球上的**世界方向**（全局变量，同样由 C# 写入）。
            // 矩阵方案用它派生 moonLocal，屏幕空间方案直接用它做投影，
            // 保证两种方案看到的是同一个月亮位置。
            float3   _MoonDirection;

            half4 _SkyTopColor, _SkyBottomColor, _GroundColor;
            half4 _SkyTopColorDusk, _SkyBottomColorDusk;
            half4 _SkyTopColorNight, _SkyBottomColorNight;
            half  _SkyGradientExponent;
            half  _GroundSharpness;

            half4 _StarsColor;
            half  _StarsSize, _StarMaskSize, _StarsSpeed, _StarsIntensity, _NightSign;
            half  _StarHorizonFade, _StarTwinkle, _StarTwinkleSpeed;

            half4 _MoonColor;
            half  _MoonRadius, _MoonIntensity;

            half4 _SunColor, _SunHaloColor;
            half  _SunHaloExponent, _SunHaloIntensity, _SunRadius, _SunSize, _SunSizeConvergence;

            half4 _CloudColor;
            half  _CloudRotationSpeed, _CloudOpacity;
            half  _CloudCoverage, _CloudSoftness;
            half  _CloudWarp, _CloudMacro, _CloudMacroScale;               // 抗平铺重复：域扭曲 / 宏观云量
            half  _CloudHeightFade;                                        // 旧方案：高度遮罩
            float _CloudPlaneHeight;                                       // 平面投影：云层高度(米)
            half  _CloudScale, _CloudHorizonFade;                          // 平面投影：缩放 / 地平线淡出
            half4 _CloudLitColor, _CloudShadowColor;                       // 云光照：受光 / 阴影
            half  _CloudSunIntensity, _CloudBumpScale, _CloudBumpOffset;   // 云光照：强度 / 起伏 / 梯度步长
            half  _CloudShadowAbsorb, _CloudShadowFloor;                   // 云自阴影：吸收 / 阴影环境光底
            half  _CloudShadowStep;                                        // 云自阴影：取样步长(米)
            half  _CloudShadowSlant;                                       // 云自阴影：斜射修正强度
            half  _CloudPhaseG, _CloudPhaseIntensity;                      // 云散射相位：不对称参数 / 强度
            half4 _Cloud2Color;                                            // 高层云：颜色
            half  _Cloud2Enable, _Cloud2Scale, _Cloud2Coverage, _Cloud2Softness,
                  _Cloud2Opacity, _Cloud2RotationSpeed;                    // 高层云：各参数
            float _Cloud2Height;                                           // 高层云：高度(米)

            half4 _HorizonColor;
            half  _HorizonLineExponent, _HorizonPower, _HorizonContribution;

            half4 _Tint;
            half  _Exposure;

            #define MIE_G  (-0.99)    // 与 Unity 内置 skybox-procedural 同值
            #define MIE_G2 0.9801     // = MIE_G * MIE_G

            // =================================================================
            //  数据布局
            // =================================================================
            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 dirWS      : TEXCOORD0;  // 世界方向（用于所有基于方向的层）
                float3 objPos     : TEXCOORD1;  // 物体空间位置（等价于方向）
                float3 cloudPos   : TEXCOORD2;  // 代码块 #7：绕 Y 旋转后的位置
                float3 moonDir    : TEXCOORD3;  // 代码块 #6：月亮局部空间方向
                float4 screenPos  : TEXCOORD4;  // 代码块 #4：屏幕空间坐标
            };

            // =================================================================
            //  【工具】取太阳方向
            //  原文直接使用 URP 全局 _MainLightPosition。这里做一次归一化 + 兜底，
            //  避免场景没有平行光时 normalize(0) 产生 NaN。
            // =================================================================
            float3 GetSunDirection()
            {
                float3 d   = _MainLightPosition.xyz;
                float  len = length(d);
                return (len > 1e-5) ? (d / len) : float3(0.0, 1.0, 0.0);
            }

            // =================================================================
            //  ① 基础渐变 —— 代码块 #1
            //  用 dot(方向, 上) 做渐变，配合指数控制"从地平线到天顶"的过渡快慢。
            //  原文签名带 inout color，这里改成"返回值"，方便合成时直接 lerp。
            // =================================================================
            half3 GradientSky(half dotViewUp, half3 skyTopColor, half3 skyBottomColor,
                              float skyGradientExponent)
            {
                half gradient = 1.0 - saturate(dotViewUp);
                gradient = pow(gradient, skyGradientExponent);
                gradient = 1.0 - saturate(gradient);
                return lerp(skyBottomColor, skyTopColor, gradient);
            }

            // =================================================================
            //  ⑤-a 日盘衰减 —— 代码块 #2  calcSunAttenuation
            //  两种模式，对应内置 Skybox/Procedural 的 SIMPLE / HQ。
            // =================================================================
            half getMiePhase(half eyeCos, half eyeCos2)
            {                // 与 Unity 内置 skybox-procedural / HDRP ProceduralSky 同源的实现。
                //
                // ⚠ 它不是纯 Henyey-Greenstein，而是 Cornette-Shanks 近似：
                //   • 归一化系数 1.5*(1-g²)/(2+g²)，取代了 HG 的 (1-g²)
                //   • 分子多一项 (1 + cos²θ)
                // 这两个改动修正了 HG 在后向散射角附近的偏差，代价只多一次乘加。
                // 另外内置取的 g 是 **-0.99（负值）**，靠调用方传入的负 eyeCos 抵消，
                // 所以看源码时的符号会显得很反直觉，别被绕进去。
                half temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;

                // 内置写作 PositivePow(_SunSize, 0.65) * 10：
                // 指数越大，日盘越锐利、中心越亮、衰减越快。
                half miePower = pow(max(_SunSize, 1e-4), 0.65) * 10.0;
                temp = pow(max(temp, 1e-4), miePower);
                temp = max(temp, 1e-4);   // 贴近日盘中心时 temp 会趋近 0，兜住除零

                temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
                return temp;
            }

            half calcSunAttenuation(float3 sunDir, float3 ray, half sunRadius)
            {
            #if defined(SUN_HQ)
                // HQ：米氏散射，边缘更自然，适合大光晕
                half focusedEyeCos = pow(saturate(dot(sunDir, ray)), _SunSizeConvergence);
                return getMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos);
            #else
                // SIMPLE：在方向上做一个球，对距离做 smoothstep，平方后收边
                half3 delta = sunDir - ray;
                half  dist  = length(delta);
                half  spot  = 1.0 - smoothstep(0.0, sunRadius, dist);
                return spot * spot;
            #endif
            }

            // =================================================================
            //  ⑤-c 云的散射相位函数（Henyey-Greenstein）
            //
            //  云是水滴（10~20µm >> 波长），米氏散射强烈前向：
            //  你正对着太阳看云 → 极亮；太阳在背后 → 很暗。
            //  没有它，逆光的云和顺光的云一样亮，观感很"平"。
            //
            //  g = 不对称参数：0=各向同性，0.7~0.9=云的典型值（强前向）
            //  这里返回未归一化的 HG 值，由调用方除以峰值归一化到 0..1
            // =================================================================
            half CloudPhaseHG(float cosTheta, half g)
            {
                half g2 = g * g;
                half d  = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-3);
                return (1.0 - g2) / pow(d, 1.5);
            }

            // =================================================================
            //  ⑤-b 太阳 + 光晕 —— 代码块 #3  SunReckon
            //  日盘压硬边，光晕用贝尔曲线 + 地平线柔化。
            //
            //  ⚠ 与原文的差异（这是整合时唯一需要改写的逻辑）：
            //  原文 #3 内部自己画日盘：
            //        half sun = pow(dotViewSun, 10000 * litRadius);
            //        sun = saturate(sun * 25);
            //  而 #2 的 calcSunAttenuation 其实也是同一件事的另一种画法，两者会重复。
            //  整合版让 #2 负责"日盘形状"，#3 只负责"光晕"，避免两个日盘叠加。
            //  想完全回到原文写法，把 sun 那一行换成上面两行即可。
            // =================================================================
            void SunReckon(inout half3 color, float3 dirWS, float3 sunDirWS, half dotViewUp,
                           half3 sunColor, half3 litColor, half sunHaloExponent, half sunAtten)
            {
                half dotViewSun = saturate(dot(normalize(dirWS), sunDirWS));

                // 光晕：贝尔曲线 × 地平线柔化（原样保留）
                half bellCurve     = pow(dotViewSun, sunHaloExponent * saturate(abs(dotViewUp)));
                half horizonSoften = 1.0 - pow(1.0 - saturate(dotViewUp), 5.0);
                half3 sunHalo      = saturate(bellCurve * horizonSoften) * litColor;

                // 日盘：强度直接来自 #2 的 calcSunAttenuation
                //
                // 原文这里是  sun = saturate(pow(dotViewSun, 10000*litRadius) * 25);
                // 那个 ×25 是为了把"高次幂"算出来几乎为 0 的值放大到 1。
                // 而 #2 的两种实现本身都已经输出 0~1 的遮罩：
                //   SIMPLE → spot*spot ∈ [0,1]，硬边圆盘
                //   HQ     → Cornette-Shanks，数值可达上百，天然是"亮核 + 宽光晕"
                // 再乘 25 会把半个天空压成白色，所以这里不再放大。
                float sun = saturate((float)sunAtten);

                color = lerp(color, sunColor, (half)sun) + sunHalo * _SunHaloIntensity;
            }

            // =================================================================
            //  ④-b 月亮（矩阵方案）—— 代码块 #6  GetMoons
            //  用 C# 传入的 _MoonMatrix 把天空球顶点转到"月亮局部空间"，
            //  月亮就变成贴在天空球上的一个盘，会跟随相机旋转，也不会畸变。
            // =================================================================
            half4 GetMoonMatrixSpace(float3 moonDir)
            {
                float2 muv = moonDir.xy * _MoonRadius + float2(0.5, 0.5);

                // ① uv 一出 [0,1] 就丢弃。
                //    不这么做的话：贴图的 Wrap Mode 若是 Repeat，越界 uv 会让整片天空重复出现月亮。
                half inRange = step(0.0, muv.x) * step(muv.x, 1.0)
                             * step(0.0, muv.y) * step(muv.y, 1.0);

                // ② 半空间剔除 —— 消除"两个月亮"的关键。
                //    这里只用 xy 做 uv，丢掉了 z 的符号，于是月亮局部空间的 +z 与 -z
                //    两个方向会落到同一块贴图上，天球上就出现两个相差 180°、长得一样的月亮。
                //    moonDir 已归一化，z 的符号可靠，只保留 +z 半球即可。
                //
                //    ⚠ 原文写的 moonmask（相机前向 vs 反太阳方向）解决不了这个问题：
                //      那个值全屏统一，只能"整屏显示 / 整屏隐藏"，无法逐像素区分正反半球。
                half frontHalf = step(0.0, moonDir.z);

                half4 moonDisc = SAMPLE_TEXTURE2D(_MoonTex, sampler_MoonTex, muv);
                moonDisc.a *= inRange * frontHalf;
                return moonDisc;
            }

            // =================================================================
            //  ④-a 月亮（屏幕空间方案）—— 代码块 #4  GetMoon
            //  保留原文实现作为对照。缺点（作者自己也提到了）：
            //  不跟随相机旋转、视角边缘会拉伸，所以默认关闭。
            // =================================================================
            half4 GetMoonScreenSpace(float3 moonDir, float2 screenUV)
            {
                // 月亮方向 → 裁剪空间。传进去的是方向(w=0)，所以裁剪空间的 w 分量
                // 实际上就是"该方向相对相机的 z 深度"。
                float4 moonPosCS = mul(UNITY_MATRIX_VP, float4(moonDir, 0.0));

                // ① 背面剔除：w <= 0 说明月亮在相机背后。
                //    此时透视除法会得到完全错误的坐标（甚至负负得正跑到画面里），
                //    必须直接丢弃，否则整片天空都会被贴图糊住。
                half facing = step(1e-4, moonPosCS.w);

                // ② 防除零：w 趋近 0 时（月亮贴近视平面），uv 会飙到几千上万。
                float w = max(moonPosCS.w, 1e-4);

                // 透视除法。注意分子里的偏移量必须是 ndc.w = w * 0.5，
                // 不是 w —— 用 w 会把结果从 [0,1] 推到 [0,2]，月亮整体偏移半个屏幕。
                float4 ndc = moonPosCS * 0.5;
                float2 moonCenterUV = float2(ndc.x, ndc.y * _ProjectionParams.x) + ndc.w;
                moonCenterUV /= w;

                // 用屏幕长宽比把贴图还原成原始比例
                float aspect    = _ScreenParams.x / _ScreenParams.y;
                moonCenterUV.y /= aspect;

                float2 moonUV = float2(screenUV.x, screenUV.y / aspect);

                // uv + 0.5 把坐标中心点挪到贴图中心
                float2 sampleUV = (moonUV - moonCenterUV) * _MoonRadius * aspect * 2.0
                                  + float2(0.5, 0.5);

                // ③ 越界保护：与矩阵方案保持一致。
                //    少了这一步，Repeat 类型的贴图会把月亮重复铺满整个天空。
                half inRange = step(0.0, sampleUV.x) * step(sampleUV.x, 1.0)
                             * step(0.0, sampleUV.y) * step(sampleUV.y, 1.0);

                half4 moonDisc = SAMPLE_TEXTURE2D(_MoonTex, sampler_MoonTex, sampleUV);
                // 原来的"双月亮遮罩"基于反太阳方向，现在位置由 _MoonDirection 独立控制，
                // 用 facing（相机背面剔除）代替即可。
                moonDisc.a *= inRange * facing;
                return moonDisc;
            }

            // =================================================================
            //  ⑥ 云层 —— 代码块 #7
            //  三个工具函数 + 一次采样。核心是把方向转成"等距柱状投影(equirect)"的 uv，
            //  这样一张平面云图就能裹到天空球上。
            // =================================================================
            float3 RotateAroundYInDegrees(float3 vertex, float degrees)
            {
                float alpha = degrees * PI / 180.0;
                float sina, cosa;
                sincos(alpha, sina, cosa);
                float2x2 m = float2x2(cosa, -sina, sina, cosa);
                return float3(mul(m, vertex.xz), vertex.y).xzy;
            }

            float2 ToRadialCoords(float3 coords)
            {
                float3 normalizedCoords = normalize(coords);
                float latitude  = acos(normalizedCoords.y);                 // 0..PI
                float longitude = atan2(normalizedCoords.z, normalizedCoords.x); // -PI..PI
                float2 sphereCoords = float2(longitude, latitude) * float2(0.5 / PI, 1.0 / PI);
                return float2(0.5, 1.0) - sphereCoords;
            }

            float2 CloudUV(float3 pos)
            {
                float2 tc = ToRadialCoords(pos);
                if (tc.x > 1.0)
                    return half2(0.0, 0.0);   // 经度绕回处丢弃，避免接缝
                tc.x = fmod(tc.x, 1.0);
                tc.y *= 2.0;
                return tc;
            }

            half GetRotateCloud(float3 texcoord, float heightMask)
            {
                float2 tc   = CloudUV(texcoord.xyz);
                half   cloud = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, tc).r
                               * saturate(heightMask);
                return cloud;
            }

            // =================================================================
            //  ③ 星空 —— 代码块 #8  GetStar
            //  用法线的平面投影采星点，再用另一张图做"星云遮罩"，
            //  最后用主光方向决定白天/夜晚。
            // =================================================================
            half3 GetStar(float3 dir, float3 sunDir)
            {
                // 等距柱状投影（equirectangular）。
                // 星星在无穷远处，应当按"立体角"均匀分布；
                // 原来的平面投影 dir.xz / dir.y 会让天顶坐标塌缩到 0（星点被放大成团块），
                // 地平线处又趋向无穷（纹理无限重复）。
                float lon = atan2(dir.z, dir.x);              // -PI .. PI
                float lat = acos(clamp(dir.y, -1.0, 1.0));    // 0 .. PI
                float2 skyuv = float2(lon / (2.0 * PI) + 0.5, lat / PI);

                // RGB = 亮度 + 色温差异；A = 每颗星自己的随机相位（用于独立闪烁）
                half4 starTex = SAMPLE_TEXTURE2D(_StarsTex, sampler_StarsTex, skyuv * _StarsSize);
                half3 stars   = starTex.rgb;

                half  starsmask = SAMPLE_TEXTURE2D(_StarMaskTex, sampler_StarMaskTex,
                                                   skyuv * _StarMaskSize + _StarsSpeed * _Time.x).r;

                // ── 闪烁（scintillation）────────────────────────────────────
                //   真实的星光闪烁来自大气湍流，特点是：
                //     · 每颗星相位独立（不会整片天一起亮暗）
                //     · 频率较高（数 Hz）
                //   相位存在贴图的 A 通道里（同一颗星内部恒定），所以相邻星不同步。
                half twPhase = _Time.y * _StarTwinkleSpeed + starTex.a * 6.2831853;
                half twinkle = lerp(1.0, 0.5 + 0.5 * sin(twPhase), _StarTwinkle);

                // 原文：saturate(_MainLightPosition.y)  —— 让星星只在夜晚显示
                // URP 里 _MainLightPosition 指向光源，白天太阳在上 y > 0，
                // 直接取用会让星星白天出现，所以乘 _NightSign（默认 -1）。
                // 若你的场景昼夜相反，把材质的 _NightSign 改成 1 即可。
                half nightFactor = saturate(_NightSign * sunDir.y);

                // ── 大气消光 ────────────────────────────────────────────────
                //   星光要穿过大气才能到达眼睛。天顶方向空气柱最短（airmass=1），
                //   越接近地平线路径越长：10° 仰角≈5.6 倍，3°≈20 倍，
                //   所以地平线附近的星星会被散射掉、看不见。
                half airmass       = 1.0 / max(dir.y, 0.02);
                half transmittance = exp(-_StarHorizonFade * (airmass - 1.0));

                //   消光是波长相关的（蓝光散射更强），所以低空的星星会偏红，
                //   和夕阳是同一个道理。用透射率顺带做一点红化。
                half3 extinctTint  = lerp(half3(1.0, 0.70, 0.55), half3(1.0, 1.0, 1.0), transmittance);

                return nightFactor * starsmask * stars * _StarsColor.rgb
                     * transmittance * extinctTint * twinkle;
            }

            // =================================================================
            //  ⑦ 天际线 —— 代码块 #9  EdgeHorizonReckon
            //  在 dotViewUp 接近 0 的位置打一条亮边，模拟大气散射 / 远处的雾光。
            // =================================================================
            void EdgeHorizonReckon(inout half3 combined, half dotViewUp, half3 skyEdgeCol,
                                   half horizonLineExponent, half horizonPower, half contribution)
            {
                half edgeskyhorizon = saturate(1.0 - abs(dotViewUp));
                edgeskyhorizon = pow(edgeskyhorizon, horizonLineExponent);
                edgeskyhorizon = saturate(edgeskyhorizon);
                combined = lerp(combined, skyEdgeCol, edgeskyhorizon * contribution);
                // horizonPower 在原文里接进来了但函数体内没用到，此处保持一致，
                // 留作你做"天际线随高度衰减"时的接口。
            }

            // =================================================================
            //  顶点阶段
            // =================================================================
            Varyings vert(Attributes v)
            {
                Varyings o;

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);

                // 天空盒是贴在相机上的单位立方体，物体空间方向 ≈ 世界方向。
                // 用 unity_ObjectToWorld 的 3x3 部分，可兼容引擎对天空盒施加的旋转。
                o.dirWS  = normalize(mul((float3x3)unity_ObjectToWorld, v.positionOS.xyz));
                o.objPos = v.positionOS.xyz;

                // 代码块 #7 的顶点部分：让云层绕 Y 轴持续旋转。
                // 注意只旋转云，不旋转整个天空 —— 否则太阳会跟光照方向错位。
                o.cloudPos = RotateAroundYInDegrees(v.positionOS.xyz, _CloudRotationSpeed * _Time.y);

                // 代码块 #6 的顶点部分：转到月亮局部空间。
                // 原文用 #if !_DAY 包裹，这里常驻计算（几条指令，开销可忽略），
                // 由 _MoonIntensity 控制是否参与合成。
                //
                // ⚠ 与原文的差异：这里多做了一次 normalize。
                // 天空盒立方体的顶点模长在面对面中心时为 1、顶点角落时为 √3≈1.73，
                // 直接用原始顶点会让月盘的大小随所在方位变化（在立方体棱角处被放大 1.7 倍）。
                // 归一化之后 moonDir 就是纯方向，月盘的半径只由 _MoonRadius 决定。
                float3 moonLocal = mul((float3x3)_MoonMatrix, v.positionOS.xyz);
                float  moonLen   = length(moonLocal);
                // _MoonMatrix 未由脚本写入时是全零矩阵，normalize(0) 会得到 NaN 并污染整帧，
                // 所以这里给一个安全的兜底方向（配合 _MoonIntensity=0 完全不可见）。
                o.moonDir = (moonLen > 1e-4) ? (moonLocal / moonLen) : float3(0.0, 0.0, 1.0);
                o.moonDir.x *= -1.0;   // 原文的镜像约定，保留

                o.screenPos = ComputeScreenPos(o.positionCS);

                return o;
            }

            // =================================================================
            //  像素阶段 —— 合成主函数
            //  顺序即"谁盖谁"，改动顺序会直接改变遮挡关系（见文件头说明）。
            // =================================================================
            half4 frag(Varyings i) : SV_Target
            {
                float3 dir       = normalize(i.dirWS);
                half   dotViewUp = dot(dir, half3(0.0, 1.0, 0.0));
                float3 sunDir    = GetSunDirection();

                half3 color;

                // ── ① 基础渐变（白天 / 黄昏 / 夜晚 三段配色，按太阳高度混合）──
                //   三者权重由 sunDir.y 决定，且和恒为 1：
                //     dayW   : 太阳抬高 → 占满
                //     nightW : 太阳落到地平线下 → 占满
                //     duskW  : 剩下的必然落在日出/日落附近
                half dayW   = saturate(sunDir.y * 3.0);
                half nightW = saturate(-sunDir.y * 3.0);
                half duskW  = saturate(1.0 - dayW - nightW);

                half3 skyTop = _SkyTopColor.rgb       * dayW
                             + _SkyTopColorDusk.rgb   * duskW
                             + _SkyTopColorNight.rgb  * nightW;

                // 地平线暖色只在"朝向太阳"的一侧更浓，背向太阳的一侧收敛
                half2 dirH   = normalize(dir.xz + 1e-5);
                half2 sunH   = normalize(sunDir.xz + 1e-5);
                half  facing = saturate(dot(dirH, sunH) * 0.5 + 0.5);
                half3 duskBottom = lerp(_SkyBottomColorDusk.rgb * 0.55, _SkyBottomColorDusk.rgb, facing);

                half3 skyBottom = _SkyBottomColor.rgb      * dayW
                                + duskBottom               * duskW
                                + _SkyBottomColorNight.rgb * nightW;

                color = GradientSky(dotViewUp, skyTop, skyBottom, _SkyGradientExponent);

                // ── ③ 星空（最远，先叠）───────────────────────────────────
                // 星星是加色叠加：天空越暗越明显，符合物理直觉。
                color += GetStar(dir, sunDir) * _StarsIntensity;

                // ── ④ 月亮 ────────────────────────────────────────────────
                half4 moonDisc;
            #if defined(MOON_SCREENSPACE)
                // 原方案：月亮位置绑死在反太阳方向。
                // 缺点：① 月亮永远和太阳对立，无法独立安排；② 太阳在上时月亮必然在地平线下，
                //       且相机若背对它，投影的 w 会 ≤0 直接崩掉。
                // moonDisc = GetMoonScreenSpace(-sunDir, i.screenPos.xy / i.screenPos.w);

                // 现在：由 MoonDriver 通过 _MoonDirection 传入真实的月亮方向，
                // 与矩阵方案共用同一个位置来源。未接驱动时退回反太阳方向兜底。
                float3 screenMoonDir = (length(_MoonDirection) > 0.5)
                                     ? normalize(_MoonDirection)
                                     : -sunDir;
                moonDisc = GetMoonScreenSpace(screenMoonDir, i.screenPos.xy / i.screenPos.w);
            #else
                // 矩阵方案（默认）
                moonDisc = GetMoonMatrixSpace(i.moonDir);
            #endif
                color = lerp(color, moonDisc.rgb * _MoonColor.rgb,
                             saturate(moonDisc.a) * _MoonIntensity);

                // ── ⑤ 太阳 ────────────────────────────────────────────────
                // 先用 #2 算出日盘强度，再交给 #3 合成日盘 + 光晕。
                half sunAtten = calcSunAttenuation(sunDir, dir, _SunRadius);
                SunReckon(color, dir, sunDir, dotViewUp,
                          _SunColor.rgb, _SunHaloColor.rgb, _SunHaloExponent, sunAtten);

                // ── ⑥ 云层 ────────────────────────────────────────────────
                #if defined(CLOUD_PLANAR)
                    // ── ⑥-a 高层云（远 → 必须先画）───────────────────────
                    //   简化版：1 次采样，无自阴影、无法线。
                    //   高空卷云本身就薄、平、对比低，这样既省性能又符合观感。
                    //   和近层用不同的高度/尺度/转速 → 相机平移时产生视差，
                    //   这才是"多层"最核心的观感来源。
                    if (_Cloud2Enable > 0.5)
                    {
                        float  dh2  = _Cloud2Height - _WorldSpaceCameraPos.y;
                        float  t2   = dh2 / max(dir.y, 1e-3);
                        float2 hit2 = _WorldSpaceCameraPos.xz + dir.xz * t2;

                        float  a2 = radians(_Cloud2RotationSpeed * _Time.y);
                        float  s2, c2;
                        sincos(a2, s2, c2);
                        float2 cuv2 = mul(float2x2(c2, -s2, s2, c2), hit2) * _Cloud2Scale;

                        half d2  = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, cuv2).r;
                        half a2d = saturate((d2 - _Cloud2Coverage) / max(1e-4, _Cloud2Softness));
                        // 高层云可以压到更低的仰角，所以淡出范围用近层的
                        a2d *= saturate((dir.y - 0.02) / max(1e-4, _CloudHorizonFade));

                        // 薄云不做自阴影/相位，只按太阳高度在阴影色和受光色之间过渡
                        half  up2   = saturate(sunDir.y * 3.0);
                        half3 l2shd = _Cloud2Color.rgb * _CloudShadowColor.rgb;
                        half3 l2lit = _Cloud2Color.rgb * _CloudLitColor.rgb * _CloudSunIntensity;
                        half3 l2col = lerp(l2shd, l2lit, up2);

                        // alpha 合成（不能加法）：近层随后会盖在它上面
                        color = lerp(color, l2col, a2d * _Cloud2Opacity);
                    }

                    // ── ⑥-b 近层积云（近 → 后画，会遮住高层）─────────────
                    // 平面投影：把视线打到一块水平云层上，用交点的世界 XZ 采样。
                    //   deltaH = 云层高出相机的米数
                    //   t      = deltaH / dir.y   —— 交点距离；dir.y→0 时 t→∞，即地平线压缩
                    //   hitXZ  = 相机位置 + 方向 × 距离  —— 必须是世界绝对坐标，才有平移视差
                    float deltaH = _CloudPlaneHeight - _WorldSpaceCameraPos.y;
                    float dy     = max(dir.y, 1e-3);                  // 兜住地平线除零
                    float t      = deltaH / dy;
                    float2 hitXZ = _WorldSpaceCameraPos.xz + dir.xz * t;

                    // 绕 Y 自转 —— 等价于旋转平面坐标，只影响云层，不牵连太阳/月亮/星星
                    float  a = radians(_CloudRotationSpeed * _Time.y);
                    float  sa, ca;
                    sincos(a, sa, ca);
                    float2 cuvBase = mul(float2x2(ca, -sa, sa, ca), hitXZ) * _CloudScale;

                    // ── 域扭曲：打散平铺网格 ─────────────────────────────
                    //   直接用平铺 UV 采样会看到规则的"行列"重复。
                    //   这里叠两个频率互质的正弦做低频扰动，让相邻瓦片错位，
                    //   网格线就难以辨认了。纯数学运算，不增加采样。
                    float2 warp = float2(
                        sin(cuvBase.y * 4.7 + 1.3) + 0.5 * sin(cuvBase.y * 11.3 + 4.1),
                        cos(cuvBase.x * 5.3 + 2.7) + 0.5 * cos(cuvBase.x * 9.7 + 0.9)
                    ) * _CloudWarp;
                    float2 cuv = cuvBase + warp;

                    // ── 密度采样：中心 + U/V 两个方向（用于求梯度）──
                    float2 gx = float2(_CloudBumpOffset, 0.0);
                    float2 gy = float2(0.0, _CloudBumpOffset);
                    float dC = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, cuv).r;
                    float dU = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, cuv + gx).r;
                    float dV = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, cuv + gy).r;

                    // ── 覆盖率重映射 ─────────────────────────────────────────
                    //   原始密度是糊状分布（大量中间值），直接用会把云画成半透明，
                    //   导致星星从云里透出来。这里把它压成"有云 / 没云"两种状态：
                    //     _CloudCoverage 以下 → 0（晴天，星星可见）
                    //     +_CloudSoftness 以上 → 1（实心云，完全遮挡星星）
                    // ── 宏观云量变化 ─────────────────────────────────────
                    //   用同一张图的极低频采样当作"云量地图"，让不同天区疏密不同。
                    //   这一步对打破重复感非常有效：即使瓦片重复，密度分布也不重复。
                    half macro    = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex,
                                                     cuv * _CloudMacroScale + 0.37).r;
                    half covLocal = saturate(_CloudCoverage + (macro - 0.5) * _CloudMacro);

                    half cloudDensity = saturate((dC - covLocal) / max(1e-4, _CloudSoftness));

                    // 地平线淡出：UV 在此处被拉得极长，先淡掉可以避免噪点/摩尔纹
                    half horizonFade = saturate((dir.y - 0.02) / max(1e-4, _CloudHorizonFade));
                    half cloud = cloudDensity * horizonFade;

                    // ── 把密度场当作高度场，用梯度构造法线 ──
                    //   dC 越大 = 该处云越"高"
                    //   斜率 = 密度差 / 采样间距（归一化后才是真正的坡度，与偏移大小无关）
                    //   坡面法线 = (-dH/du, 1, -dH/dv) 归一化
                    float invStep = 1.0 / max(1e-5, _CloudBumpOffset);
                    float slopeU  = (dU - dC) * invStep;
                    float slopeV  = (dV - dC) * invStep;
                    float3 nCloud = normalize(float3(-slopeU * _CloudBumpScale,
                                                      1.0,
                                                      -slopeV * _CloudBumpScale));

                    // 云在自转，法线又是定义在 cuv 空间里的，
                    // 所以太阳方向必须用同一个旋转矩阵变换到 cuv 空间才能对齐
                    float2 sun2D    = mul(float2x2(ca, -sa, sa, ca), sunDir.xz);
                    float3 sunLocal = float3(sun2D.x, sunDir.y, sun2D.y);

                    half sunUp = step(0.0, sunDir.y);                       // 太阳在地平线下 -> 只剩环境光
                    half NdotL = saturate(dot(nCloud, normalize(sunLocal))) * sunUp;

                    // ── 云自阴影 v2：朝太阳方向累加光学厚度（Beer 定律）──────
                    //   从当前点沿"云平面内的太阳方向"走 4 步，把路上的有效云量累加：
                    //     走在云团边缘  → tau 小 → T 大 → 亮（银边）
                    //     走在云团深处  → tau 大 → T 小 → 暗
                    //   减 _CloudCoverage 是关键：否则晴空的基线密度会累加，
                    //   导致整片天空一起变暗、对比度被抹平。
                    float2 marchDir = normalize(sunLocal.xz + 1e-6);      // cuv 空间内朝太阳的方向

                    // 斜射修正：太阳越低，光线越贴着云层走，遮挡路径越长。
                    //   sunDir.y=1(天顶) → 1.0；0.5(30°) → 2.0；0.18(10°) → 5.5
                    //   _CloudShadowSlant 用来控制这个修正的强度（0=关闭）
                    float slant = lerp(1.0, 1.0 / max(sunDir.y, 0.18), _CloudShadowSlant);
                    float stepUV = _CloudShadowStep * _CloudScale * slant;  // 米 → UV 单位

                    float  tau = 0;
                    float2 p   = cuv;
                    [unroll] for (int si = 1; si <= 4; si++)
                    {
                        p   += marchDir * stepUV;
                        float ds = SAMPLE_TEXTURE2D_LOD(_CloudTex, sampler_CloudTex, p, 0).r;
                        tau += max(0.0, ds - _CloudCoverage);
                    }

                    half T = exp(-tau * _CloudShadowAbsorb);

                    // ── 散射相位：朝太阳看时云被"烧穿"（前向散射）─────────
                    //   HG 归一化到前向峰值 = 1，所以 phase ∈ (0,1]，正对太阳时=1。
                    half cosT  = dot(dir, sunDir);
                    half pMax  = CloudPhaseHG(1.0, _CloudPhaseG);
                    half phase = CloudPhaseHG(cosT, _CloudPhaseG) / max(pMax, 1e-4);

                    half3 albedo = _CloudColor.rgb;                         // 云的本色
                    half3 litCol = albedo * _CloudLitColor.rgb * _CloudSunIntensity;
                    half3 shdCol = albedo * _CloudShadowColor.rgb;          // 阴影侧 = 本色 × 环境光颜色

                    // 环境光 + 单次散射（加法形式，逆光时能超过 litCol，交给 Bloom）
                    half baseLit = NdotL * lerp(_CloudShadowFloor, 1.0, T);

                    // ⚠ 前向散射必须独立成项，不能乘 NdotL：
                    //   太阳很低时顶面余弦趋近 0，会把逆光发亮整个压没
                    //   （真实情况是光几乎横穿云层，与顶面朝向无关）。
                    //   T 仍然参与，保证"厚云挡光、薄云透光"。
                    half glow      = _CloudPhaseIntensity * phase * T;
                    half scattered = baseLit + glow;

                    half3 clCol = shdCol + litCol * scattered;

                    color = lerp(color, clCol, saturate(cloud) * _CloudOpacity);
                #else
                    // 旧方案：等距柱状(经纬)投影，云层像贴在穹顶上，无透视压缩/无视差
                    half cloudHeight = saturate(i.cloudPos.y / max(1e-3, _CloudHeightFade));
                    half cloud       = GetRotateCloud(i.cloudPos, cloudHeight);
                    color = lerp(color, _CloudColor.rgb, saturate(cloud) * _CloudOpacity);
                #endif 
                
                // ── ⑧ 地面（挪到最后绘制）─────────────────────────────────
                // 原文只在文字里提到"地面颜色"，这里用地平线以下的遮罩补上。
                // 顺序很重要：必须放在太阳 / 月亮之后，否则落到地平线以下的太阳，
                // 以及矩阵方案里那个"镜像月亮"，都会盖在地面之上显形。
                // 地面亮度也随时间变化：夜间只剩极弱的余晖
                half groundLight = 0.06 + 0.94 * dayW + 0.45 * duskW;
                half groundMask = saturate(-dotViewUp / max(1e-4, _GroundSharpness));
                color = lerp(color, _GroundColor.rgb * groundLight, groundMask);

                // ── ⑦ 天际线（最上层的亮边）───────────────────────────────
                // 亮边强度也随时间变化：正午最亮、黄昏偏亮、夜间几乎消失
                half horizonStrength = 0.10 + 0.90 * dayW + 0.85 * duskW;
                EdgeHorizonReckon(color, dotViewUp, _HorizonColor.rgb * horizonStrength,
                                  _HorizonLineExponent, _HorizonPower, _HorizonContribution);

                // ── 输出 ──────────────────────────────────────────────────
                color *= _Tint.rgb * _Exposure;
                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
