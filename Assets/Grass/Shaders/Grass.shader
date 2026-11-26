// ============================================================================
//  Grass.shader —— URP 程序化草地（对马岛风格）
//
//  规格来源：
//    知乎《菜鸡都能学会的草地2.0（UE5 Procedural Grass）》1~6 节
//    参数名刻意与 UE 工程 /Game/Shaders/BezierCurveGrassMesh 保持一致，
//    方便两边对照调参（单位换算是唯一的差异，见各参数注释）。
//
//  ── 与 UE 版本的差异（不是缺陷，是管线不同导致的必要重写）────────────────
//    1. UE 用 Default Lit + WPO；这里要手写顶点位移 + 自定义法线 + 自定义光照，
//       因为 URP 的 Lit 不接受"顶点算出来的法线 + 逐实例数据"。
//    2. UE 的 PerInstanceCustomData 在这里换成 StructuredBuffer<GrassInstance>，
//       由 SV_InstanceID 索引（配合 DrawMeshInstancedIndirect，一次 draw 画完整片草）。
//    3. UE 的 WorldPositionOffset 是世界空间偏移；这里顶点直接在世界空间组装，
//       所以 instance → world 的变换天然成立（不会出现草跟着物体缩放的问题）。
//
//  ── 渲染管线位置 ───────────────────────────────────────────────────────────
//    ForwardLit : 主渲染，吃 URP 主光 + SH 环境光 + 阴影 + 雾
//    ShadowCaster: 投射阴影（可用 GrassField 上的开关关掉，草影很贵）
//    DepthOnly  : 给 SSAO 用
// ============================================================================

Shader "Grass/GrassField"
{
    Properties
    {
        // ── 颜色 ────────────────────────────────────────────────────────────
        [Header(Base Color)]
        _BottomColor        ("根部颜色 BottomColor", Color) = (0.015, 0.035, 0.010, 1)
        _MidColor           ("中段颜色 MidColor", Color) = (0.075, 0.185, 0.032, 1)
        _TopColor           ("草尖颜色 TopColor", Color) = (0.330, 0.400, 0.095, 1)
        _MidPoint           ("三段分界点 MidPoint", Range(0.05, 0.95)) = 0.62
        _ColorBrightness    ("颜色亮度 ColorBrightness", Float) = 1.0
        _ColorRemap         ("根尖过渡指数 ColorRemap", Range(0.2, 8)) = 1.0
        _BladeTintStrength  ("单株明暗差", Range(0, 1)) = 0.28
        _FadeAlbedo         ("草尖褪色色 FadeAlbedo", Color) = (1.00, 0.92, 0.35, 0)
        _NoFadeColorSoft    ("褪色柔和度 NoFadeColorSoft", Range(0.01, 1)) = 0.22
        _TipFadeAmount      ("褪色强度（逐株随机参与）", Range(0, 1)) = 0.75

        // ── 形状 ────────────────────────────────────────────────────────────
        [Header(Shape)]
        _Width              ("草叶宽度（米） Width", Float) = 0.035
        _Height             ("草叶高度（米） Height", Float) = 0.85
        _P1XMidpoint        ("弯曲中点 P1Xmidpoint", Range(-1, 1)) = 0.0
        _P1YCurve           ("弯曲高度 P1YCurve", Range(0, 1)) = 0.5
        _BendAmount         ("整体前倾量", Range(-2, 2)) = 0.25

        // ── 法线 ────────────────────────────────────────────────────────────
        [Header(Normal)]
        _NormalYMidribSoft  ("中脉柔和度 NormalYMidribSoft", Range(0.01, 1)) = 0.1
        _NormalYRimPosition ("内折起点 NormalYRimPosition", Range(0, 1)) = 0.5
        _NormalYRimSoft     ("内折柔和度 NormalYRimSoft", Range(0.01, 1)) = 0.08
        _NormalYStrength    ("内折强度 NormalYStrength", Range(0, 4)) = 0.7

        // ── 着色 ────────────────────────────────────────────────────────────
        [Header(Shading)]
        _RoughnessMin       ("粗糙度下限 RoughnessMin", Range(0, 1)) = 0.2
        _RoughnessMax       ("粗糙度上限 RoughnessMax", Range(0, 1)) = 0.3
        _SpecularMin        ("高光下限 SpecularMin", Range(0, 1)) = 0.05
        _SpecularMax        ("高光上限 SpecularMax", Range(0, 1)) = 0.1
        _RoughSpecularTill  ("噪声平铺 RoughSpecularTill", Vector) = (1, 2, 0, 1)
        _AOPower            ("AO 指数 AOPower", Range(0.1, 8)) = 2.2
        _Translucency       ("透光包裹强度", Range(0, 1)) = 0.35
        _TranslucencyBoost  ("逆光透亮强度", Range(0, 2)) = 0.9

        // ── 厚度 ────────────────────────────────────────────────────────────
        [Header(Thickness)]
        _ThicknessTilt      ("侧视倾斜量（0=关）", Range(0, 1)) = 0.65

        // ── 玩家交互 ────────────────────────────────────────────────────────
        [Header(Grass Interaction)]
        _TrailStrength      ("交互强度", Range(0, 4)) = 2.2
        _TrailMidWeight     ("交互弯曲权重（中点）", Range(0, 1)) = 0.5
        _TrailFlatten       ("交互压矮", Range(0, 1)) = 0.45
        [Toggle] _TrailDebug ("调试：显示推力", Float) = 0

        // ── 风 ──────────────────────────────────────────────────────────────
        [Header(Wind)]
        [NoScaleOffset] _WindNoise ("风噪声（R 通道）", 2D) = "gray" {}
        _WindTexScale       ("风纹理尺度（米/次平铺，UE 中为 cm）", Float) = 50.0
        _WindRandom         ("逐株 UV 随机 WindRandom", Float) = 1.0
        _WindSpeed          ("风向/速度 WindSpeed(XYZ)", Vector) = (1.0, 0.2, 0.7, 0)
        _WindSwell          ("风浪摆幅 WindSwell（UE 单位 cm）", Float) = 60.0
        _FlutterLength      ("飘动长度 FlutterLength（UE 单位 cm）", Float) = 50.0
        _FlutterSpeed       ("飘动速度 FlutterSpeed", Float) = 2.0
        _WindFlutter        ("飘动强度 WindFlutter", Float) = 3.0
        _WindTotalScale     ("风总强度 WindTotalScale", Float) = 1.0
        _WindScaleMidpoint  ("中点风权重 WindScale(MidPoint)", Range(0, 2)) = 0.5
        _WindScaleTop       ("尖端风权重 WindScale(Top)", Range(0, 2)) = 1.0
        [Toggle] _WindDebug ("可视化风浪 WindVisualDebug", Float) = 0

        // ── 距离 ────────────────────────────────────────────────────────────
        [Header(Distance)]
        _SpecularDistanceStart ("高光衰减起点（米）", Float) = 15
        _SpecularDistanceEnd   ("高光衰减终点（米）", Float) = 45
        _FadeStart             ("融合起点（米）", Float) = 28
        _FadeEnd               ("融合终点（米）", Float) = 40
        _FarBlendStrength      ("远处融合强度", Range(0, 1)) = 0.45
        _AmbientBoost          ("环境光倍率", Range(0, 4)) = 1.0

        [Header(Anti Flicker)]
        _MinPixelWidth      ("远处最小宽度（像素）", Range(0.5, 6)) = 1.6
        _FlutterFadeStart   ("停用抖动起点（米）", Float) = 10
        _FlutterFadeEnd     ("停用抖动终点（米）", Float) = 30
        _NormalFadeStart    ("法线滤波起点（米）", Float) = 8
        _NormalFadeEnd      ("法线滤波终点（米）", Float) = 26
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Cull Off          // 双面：草叶本来是薄片，背面也要画（UE 里 two_sided = true）
        ZWrite On

        // ====================================================================
        //  公共声明与顶点计算
        // ====================================================================
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "GrassCommon.hlsl"

        #pragma target 4.5

        // 逐实例数据（48 字节/株，由 compute 压缩后写入）：
        //   a = (世界坐标 xyz, 朝向弧度)
        //   b = (统一缩放, 随机0, 随机1, 色调偏移)
        //   c = (推力 x, 推力 z, 0, 0)  ← 草地交互，compute 已经采样好
        struct GrassInstance
        {
            float4 a;
            float4 b;
            float4 c;
        };

        // 绑定的一定是 compute 压缩后的缓冲（开关剔除都走 compute）
        StructuredBuffer<GrassInstance> _Instances;

        // 材质参数（不放进 UnityPerMaterial CBUFFER：本 shader 用 Indirect 绘制，
        // 不参与 SRP Batcher，省去布局对齐的坑）
        float4 _BottomColor, _MidColor, _TopColor, _FadeAlbedo, _RoughSpecularTill, _WindSpeed;
        float  _ColorBrightness, _ColorRemap, _NoFadeColorSoft, _TipFadeAmount;
        float  _MidPoint, _BladeTintStrength;
        float  _Width, _Height, _P1XMidpoint, _P1YCurve, _BendAmount;
        float  _NormalYMidribSoft, _NormalYRimPosition, _NormalYRimSoft, _NormalYStrength;
        float  _RoughnessMin, _RoughnessMax, _SpecularMin, _SpecularMax, _AOPower;
        float  _Translucency, _TranslucencyBoost, _ThicknessTilt;
        float  _WindTexScale, _WindRandom, _WindSwell, _FlutterLength, _FlutterSpeed;
        float  _WindFlutter, _WindTotalScale, _WindScaleMidpoint, _WindScaleTop, _WindDebug;
        float  _SpecularDistanceStart, _SpecularDistanceEnd, _FadeStart, _FadeEnd;
        float  _FarBlendStrength, _AmbientBoost;
        float  _MinPixelWidth, _FlutterFadeStart, _FlutterFadeEnd;
        float  _NormalFadeStart, _NormalFadeEnd;

        // 玩家交互：推力向量由 compute 采样好、随实例数据一起送进来，
        // 顶点阶段不做任何纹理采样（顶点阶段读 RT 在这套环境下会读回 0）
        float  _TrailStrength, _TrailMidWeight, _TrailFlatten, _TrailDebug;

        TEXTURE2D(_WindNoise);
        SAMPLER(sampler_WindNoise);

        // 全局量（由 GrassField.cs 每帧写入，跟随天空球时段）
        float4 _GrassHorizonColor;
        // 天光补光色：日落/夜里主光几乎没了，草靠这一层才不至于全黑
        float4 _GrassAmbientTint;
        float  _GrassWindTime;
        // 「一米在屏幕上占多少像素」的换算系数 = 2*tan(fovY/2)/屏幕高度，由 C# 每帧写入
        float  _GrassPixelScale;

        // ── 风 ─────────────────────────────────────────────────────────────
        // 文章第 5 节：世界 UV + 逐株随机 → 三次 Panner 采样 → 平均 → sin → remap
        // 拆成 Swell（整片风浪，低频）与 Flutter（单株抖动，高频）两部分。
        // 返回值：x = 沿草叶 forward 的弯曲量（米）, y = 沿 right 的侧摆量（米）
        float2 ComputeWind(float3 posWS, float r0, float r1, float t, float dist)
        {
            float time = _GrassWindTime;

            // 世界空间 UV（每 _WindTexScale 米平铺一次）+ 逐株随机偏移
            float2 wuv = posWS.xz / max(_WindTexScale, 0.001);
            wuv += r0 * _WindRandom;

            // 三个不同方向的 Panner，避免出现明显的平铺走向
            float sp = max(_WindSpeed.x, 0.01);
            float2 d1 = normalize(float2(1.0, _WindSpeed.y));
            float2 d2 = normalize(float2(-_WindSpeed.z, 1.0));
            float2 d3 = normalize(float2(0.6, -0.8));

            // 顶点着色器没有隐式导数，必须用 LOD 版本采样
            float n1 = SAMPLE_TEXTURE2D_LOD(_WindNoise, sampler_WindNoise, wuv + d1 * (time * sp * 0.010), 0).r;
            float n2 = SAMPLE_TEXTURE2D_LOD(_WindNoise, sampler_WindNoise, wuv * 1.7 + d2 * (time * sp * 0.016), 0).r;
            float n3 = SAMPLE_TEXTURE2D_LOD(_WindNoise, sampler_WindNoise, wuv * 2.3 + d3 * (time * sp * 0.023), 0).r;

            float swell = (n1 + n2 + n3) / 3.0;
            // 单株相位错开，否则整片同时倒伏
            swell = sin((swell + r1 * 0.25) * 6.28318) * 0.5 + 0.5;

            // UE 里 WindSwell 是 cm，这里换算成米
            float swellAmt = (swell - 0.45) * _WindSwell * 0.01 * _WindTotalScale;

            // Flutter：只吃逐株随机，给每株一点不同步的抖动
            // 远处的亚像素抖动等于给画面加噪声，按距离淡出（闪烁的主因之一）
            float flutterFade = 1.0 - saturate((dist - _FlutterFadeStart)
                                    / max(_FlutterFadeEnd - _FlutterFadeStart, 0.001));

            float flutter = sin(time * _FlutterSpeed + r1 * 6.28318) * _FlutterLength * 0.01
                          * _WindFlutter * _WindTotalScale * 0.35 * flutterFade;

            // 侧向摆动（让草不是只在一个平面里倒）
            float lateral = sin(time * _FlutterSpeed * 1.7 + r0 * 12.0) * _FlutterLength * 0.004
                          * _WindFlutter * flutterFade;

            return float2(swellAmt + flutter, lateral);
        }

        // ── 顶点组装 ───────────────────────────────────────────────────────
        struct GrassVSOut
        {
            float4 positionCS : SV_POSITION;
            float3 normalWS   : TEXCOORD0;
            float3 positionWS : TEXCOORD1;
            float2 uv         : TEXCOORD2;
            float  rand       : TEXCOORD3;
            float  height01   : TEXCOORD4;
            float  distToCam  : TEXCOORD5;
            float  fogFactor  : TEXCOORD6;
            float4 shadowCoord: TEXCOORD7;   // 只在 ForwardLit 里填（阴影 pass 不需要）
            float  tintValue  : TEXCOORD8;   // 簇内色调偏移（让成片的草有深浅变化）
            float3 trailDebug : TEXCOORD9;   // x = 推力大小（调试用）
        };

        GrassVSOut GrassComputeVertex(uint instanceID, float3 positionOS, float2 uv)
        {
            GrassVSOut o = (GrassVSOut)0;

            GrassInstance inst = _Instances[instanceID];
            float3 instPos = inst.a.xyz;
            float  yaw     = inst.a.w;
            float  scale   = inst.b.x;
            float  r0      = inst.b.y;
            float  r1      = inst.b.z;

            // ── 实例基向量（只绕 Y 旋转）──────────────────────────────────
            float s = sin(yaw);
            float c = cos(yaw);
            float3 right = float3(c, 0, -s);
            float3 fwd   = float3(s, 0,  c);

            float h = _Height * scale * lerp(0.8, 1.25, r0);
            float w = _Width  * scale * lerp(0.85, 1.15, r1);

            // ── 抗闪烁：保证草叶在屏幕上至少占 _MinPixelWidth 像素 ─────────
            // 远处一片草叶本来就只有 1 像素宽，光栅化覆盖点每帧都在跳 → 闪。
            // 这里按距离把宽度抬到"至少 N 像素"对应的世界尺度，宁可变胖也不要闪。
            float distInst = distance(instPos, _WorldSpaceCameraPos);
            float minWorldWidth = distInst * _GrassPixelScale * _MinPixelWidth;
            w = max(w, minWorldWidth);

            // ── 厚度：侧视时把草叶往相机方向倒一点（文章第 4 节）───────────
            float3 toCam = _WorldSpaceCameraPos - instPos;
            toCam.y = 0.0;
            float camDistXZ = length(toCam);
            toCam = camDistXZ > 0.001 ? toCam / camDistXZ : fwd;

            float facing = dot(fwd, toCam);                       // 1 = 正对, 0 = 侧看
            float tilt   = _ThicknessTilt * (1.0 - abs(facing));
            float3 f2 = normalize(lerp(fwd, toCam, saturate(tilt)) + 1e-5);
            float3 r2 = normalize(cross(float3(0, 1, 0), f2));

            // ── 风 ────────────────────────────────────────────────────────
            float2 wind = ComputeWind(instPos, r0, r1, uv.y, distInst);

            // ── 玩家交互：推力向量已经在 compute 里采样好，直接取 ──────────
            // 参考 idleworm《Unity草地交互的实现》的做法：
            //   在世界空间直接沿"径向"推开顶点，用 uv.y 保证根部不动。
            //   之前把推力投影到叶片自身的 f2/r2 两轴再改贝塞尔控制点，
            //   实测位移被抵消（调试显示 pushF≈0），这里换成直接推开。
            float2 trailPush = inst.c.xy * _TrailStrength;
            float  pushMag   = saturate(length(trailPush));

            // ── 贝塞尔曲线  ─────────────────────────────────
            float t = uv.y;
            float2 p0 = float2(0.0, 0.0);
            float2 p1 = float2((_P1XMidpoint + _BendAmount) * h, _P1YCurve * h);
            float2 p2 = float2(_BendAmount * h, h);

            // 风扰动控制点：中点和尖端权重不同（WindScale(MidPoint) / WindScale(Top)）
            p1.x += wind.x * _WindScaleMidpoint;
            p2.x += wind.x * _WindScaleTop;

            // 推力叠加在世界空间位移上（见下方 posWS）
            float2 pushDirXZ = trailPush;

            float2 curve = GrassBezierPoint(p0, p1, p2, t);
            float2 deriv = GrassBezierDerivative(p0, p1, p2, t);

            // ── 叶片宽度 ───────────────────
            float widthMask = GrassWidthMask(t);
            float xOff = (uv.x - 0.5) * w * widthMask;

            // ── 世界坐标组装 ─────────────────────────────────────────────
            float3 posWS = instPos + r2 * xOff + f2 * curve.x + float3(0, curve.y, 0) + r2 * (wind.y * t);

            // ── 玩家交互：直接在世界空间沿径向推开 ───────────────────────
            // uv.y (t) 保证根部不动、只有上半段倒伏；
            // 方向里加一点向下的分量，避免顶点被推穿地面。
            if (pushMag > 0.0005)
            {
                float3 pushDir = normalize(float3(pushDirXZ.x, -0.45 * _TrailFlatten - 0.001, pushDirXZ.y) + 1e-5);
                posWS += pushDir * (pushMag * t);
            }

            // ── 法线（文章第 2 节：贝塞尔导数 → 切线 → 转 90°）──────────
            float2 n2 = normalize(float2(deriv.y, -deriv.x) + 1e-5);   // (up 分量, forward 分量)

            // 内折法线：边缘向内翻折，做出 v / w / ww 的束状明暗
            float w01  = abs(uv.x - 0.5) * 2.0;                        // 0=中心 1=边缘
            float rim  = saturate((w01 - _NormalYRimPosition) / max(_NormalYRimSoft, 1e-3));
            float mid  = 1.0 - saturate(w01 / max(_NormalYMidribSoft, 1e-3));
            float fold = (rim - mid * 0.4) * _NormalYStrength * saturate(1.0 - t * 0.4);
            fold *= sign(uv.x - 0.5 + 1e-6);

            // 法线滤波（相当于给法线做 mipmap）：
            // 远处一根草只有 1~2 像素，逐顶点的高频法线变化会变成闪烁的噪点，
            // 按距离把内折强度抹平，远处趋向"整体朝上"的平滑法线。
            float normalFade = 1.0 - saturate((distInst - _NormalFadeStart)
                                    / max(_NormalFadeEnd - _NormalFadeStart, 0.001));
            fold *= normalFade;

            float3 nWS = normalize(float3(0, n2.x, 0) + f2 * n2.y + r2 * fold * 0.85);

            // ── 输出 ──────────────────────────────────────────────────────
            o.positionWS  = posWS;
            o.normalWS    = nWS;
            o.uv          = uv;
            o.rand        = r0;
            o.height01    = t;
            o.tintValue   = inst.b.w;
            o.trailDebug  = float3(pushMag, 0, 0);
            o.distToCam   = distance(posWS, _WorldSpaceCameraPos);
            o.positionCS  = TransformWorldToHClip(posWS);
            o.fogFactor   = ComputeFogFactor(o.positionCS.z);

            return o;
        }
        ENDHLSL

        // ====================================================================
        //  主渲染
        // ====================================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                uint   instanceID : SV_InstanceID;
            };

            GrassVSOut vert(Attributes v)
            {
                GrassVSOut o = GrassComputeVertex(v.instanceID, v.positionOS, v.uv);
                o.shadowCoord = TransformWorldToShadowCoord(o.positionWS);
                return o;
            }

            half4 frag(GrassVSOut i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                Light mainLight = GetMainLight(i.shadowCoord);
                float3 L = normalize(mainLight.direction);
                N = dot(N, V) < 0 ? -N : N;   // 双面：背面翻转法线

                float t   = i.height01;
                float r0  = i.rand;
                float dist = i.distToCam;

                // ── 噪声：粗糙度 / 高光 / 叶脉共用（文章第 3 节）───────────
                float noise = SAMPLE_TEXTURE2D(_WindNoise, sampler_WindNoise,
                                               i.uv * _RoughSpecularTill.xy).r;

                // ── 基础色：根部 → 中段 → 草尖（三段落，往对马岛那种层次靠）────
                // 参考图是「暗根部 → 中绿 → 亮黄尖」，两段 lerp 做不出中间那段，
                // 所以拆成三个颜色 + 一个分界点。
                float tR = saturate(pow(saturate(t), _ColorRemap));
                float m  = saturate(_MidPoint);
                float3 albedo = lerp(_BottomColor.rgb, _MidColor.rgb,
                                     smoothstep(0.0, m, tR));
                albedo = lerp(albedo, _TopColor.rgb,
                              smoothstep(m, 1.0, tR));
                albedo *= _ColorBrightness;

                // 单株明暗差：每根草亮度不同，整片才不会像一块塑料布
                albedo *= lerp(1.0 - _BladeTintStrength, 1.0 + _BladeTintStrength,
                               frac(i.rand * 71.37));

                // 簇内色调变化：同一片区域同色，区域之间深浅不同（避免整片一个颜色）
                // 对比度拉大一些，模拟草地上大块的受光/背光区域
                albedo *= lerp(0.45, 1.55, i.tintValue);

                // 草尖褪色：吃逐株随机，避免整齐划一
                float tipMask = smoothstep(1.0 - _NoFadeColorSoft, 1.0, t);
                albedo = lerp(albedo, albedo * _FadeAlbedo.rgb,
                              tipMask * _TipFadeAmount * lerp(0.35, 1.0, r0));

                // ── 粗糙度 / 高光（远处衰减，文章第 3 节 Camera Distance Specular）──
                float rough = lerp(_RoughnessMin, _RoughnessMax, noise);
                float specMask = lerp(_SpecularMin, _SpecularMax, noise);
                float dFade = saturate((dist - _SpecularDistanceStart) /
                                       max(_SpecularDistanceEnd - _SpecularDistanceStart, 0.001));
                rough = lerp(rough, 0.95, dFade);
                specMask *= (1.0 - dFade);

                // ── 漫反射：包裹光照 + 逆光透亮 ───────────────────────────
                // shadowAtten：角色/物体投在草叶上的影子。
                // 草自己不投影（castShadows 默认关），所以不会有自阴影噪点。
                float ndl  = dot(N, L);
                float wrap = saturate((ndl + _Translucency) / (1.0 + _Translucency));
                float shadowAtten = mainLight.shadowAttenuation;
                float3 diffuse = albedo * mainLight.color.rgb * wrap
                               * mainLight.distanceAttenuation * shadowAtten;

                // 逆光透亮：透射的光应该被遮挡削弱，但不完全掐掉（光会透过叶片边缘）
                float back = saturate(dot(-N, L)) * saturate(_Translucency);
                diffuse += albedo * mainLight.color.rgb * back * _TranslucencyBoost
                         * lerp(0.35, 1.0, shadowAtten);

                // ── 高光（GGX 形状的简化版）───────────────────────────────
                float3 H = normalize(L + V);
                float  ndh = saturate(dot(N, H));
                float  shiny = pow(ndh, 1.0 / max(rough * 0.35, 0.02));
                float3 specCol = mainLight.color.rgb * specMask * shiny * (1.0 - dFade) * shadowAtten;

                // ── 环境光 + AO ────────────────────────────────────────────
                // SH 给的是方向性天光；再混一层由 C# 每帧算好的天光色，
                // 保证日落/夜里主光掉到 0.05 时草不会变成纯黑。
                half3 sh = lerp(SampleSH(N), _GrassAmbientTint.rgb, 0.6) * _AmbientBoost;
                float ao = saturate(pow(saturate(t), _AOPower) * 0.9 + 0.10);
                float3 ambient = sh * albedo * ao;

                float3 col = diffuse + specCol + ambient;

                // ── 边缘受光：草叶侧面对光的那一圈更亮，给整片草"体积感" ────
                float rim = pow(1.0 - saturate(dot(N, V)), 3.0);
                // 边缘光也是"受光照亮"的成分，必须跟着阴影衰减，
                // 否则它的强度比漫反射还大（×12），会把阴影完全盖住看不到。
                col += mainLight.color.rgb * rim * saturate(ndl * 0.5 + 0.5) * 0.35 * albedo * 12.0 * shadowAtten;

                // ── 远处融合地平线颜色（和天空球的地面色对齐）─────────────
                // 目标是「压低远处的高频对比」，不是把它刷成一片白，
                // 所以用地平线色压暗后再混，亮度不会跳。
                float farBlend = saturate((dist - _FadeStart) / max(_FadeEnd - _FadeStart, 0.001));
                float3 farCol = _GrassHorizonColor.rgb * 0.60;
                col = lerp(col, farCol, farBlend * _FarBlendStrength);

                // ── 调试：把风浪显示成颜色 ────────────────────────────────
                col = lerp(col, float3(1.0, 0.2, 0.1) * saturate(t * 1.2), _WindDebug * 0.65);

                // ── 调试：把推力显示成红色 ────────────────────────────────
                col = lerp(col, float3(i.trailDebug.x * 2.0, 0.0, 0.0), _TrailDebug);

                col = MixFog(col, i.fogFactor);
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        // ====================================================================
        //  阴影投射
        // ====================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            struct AttributesShadow
            {
                float3 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                uint   instanceID : SV_InstanceID;
            };

            float4 vertShadow(AttributesShadow v) : SV_POSITION
            {
                GrassVSOut o = GrassComputeVertex(v.instanceID, v.positionOS, v.uv);

                float3 positionWS = ApplyShadowBias(o.positionWS, o.normalWS, _LightDirection);
                float4 positionCS = TransformWorldToHClip(positionWS);

            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }

            half4 fragShadow() : SV_Target { return 0; }
            ENDHLSL
        }

        // ====================================================================
        //  深度（SSAO 用）
        // ====================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex vertDepth
            #pragma fragment fragDepth

            struct AttributesDepth
            {
                float3 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                uint   instanceID : SV_InstanceID;
            };

            float4 vertDepth(AttributesDepth v) : SV_POSITION
            {
                GrassVSOut o = GrassComputeVertex(v.instanceID, v.positionOS, v.uv);
                return o.positionCS;
            }

            half4 fragDepth() : SV_Target { return 0; }
            ENDHLSL
        }
    }

    FallBack Off
}
