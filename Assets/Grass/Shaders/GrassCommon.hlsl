// ============================================================================
//  GrassCommon.hlsl —— 草地系统的公共数学工具
//
//  对应知乎《菜鸡都能学会的草地2.0》第 1 节：
//    二次贝塞尔曲线  B(t) = lerp( lerp(p0,p1,t) , lerp(p1,p2,t) , t )
//  以及它的导数（用于算法线，第 2 节）。
//
//  约定：
//    曲线的二维空间是 (bend, height) = (弯曲方向, 向上方向)。
//    在 Unity 里 bend 落到草叶自身的 forward，height 落到世界 up。
// ============================================================================

#ifndef GRASS_COMMON_INCLUDED
#define GRASS_COMMON_INCLUDED

// ── 二次贝塞尔：求点 ────────────────────────────────────────────────────────
float2 GrassBezierPoint(float2 p0, float2 p1, float2 p2, float t)
{
    float2 a = lerp(p0, p1, t);
    float2 b = lerp(p1, p2, t);
    return lerp(a, b, t);
}

// ── 二次贝塞尔：求导（切线方向）────────────────────────────────────────────
//  B'(t) = 2(1-t)(p1-p0) + 2t(p2-p1)
float2 GrassBezierDerivative(float2 p0, float2 p1, float2 p2, float t)
{
    return 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1);
}

// ── 草叶宽度遮罩 ────────────────────────────────────────────────────────────
//  v=0 根部略微收窄（避免根部像刀切），v 中段最宽，v=1 尖端收成一点。
float GrassWidthMask(float v)
{
    float root = smoothstep(0.0, 0.06, v);          // 根部 6% 快速展开
    float taper = pow(saturate(1.0 - v), 0.75);     // 向尖端收窄
    return root * taper;
}

// ── 整数哈希（撒点/剔除时做稳定随机）──────────────────────────────────────
float GrassHash12(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float GrassHash13(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

#endif // GRASS_COMMON_INCLUDED
