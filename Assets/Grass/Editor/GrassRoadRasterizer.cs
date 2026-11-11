using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// ============================================================================
//  GrassRoadRasterizer —— 把路点光栅化成一张掩码贴图
//
//  流程：
//    路点 → Catmull-Rom 样条（平滑曲线）→ 每隔几厘米取一个采样点
//         → 在每个采样点盖一个软边圆（半径带噪声扰动）
//         → 得到 R 通道的掩码，1 = 路面中心，0 = 没有路
//
//  为什么用"沿曲线盖圆"而不是"画多边形"：
//    圆盖法天然得到圆润的端点和柔和的边缘，而且不需要处理自交；
//    路的宽度可以在每个采样点单独扰动，边缘就不会像用尺子画出来的。
// ============================================================================

public static class GrassRoadRasterizer
{
    /// <summary>按路点重建掩码，写进 path.mask（资产会被原地更新）。</summary>
    public static bool Rebuild(GrassRoadPath path, string assetPath)
    {
        if (path == null) { Debug.LogError("[道路] 没有 GrassRoadPath"); return false; }
        if (path.points == null || path.points.Count < 2)
        {
            Debug.LogWarning("[道路] 至少需要 2 个路点");
            return false;
        }

        int res = Mathf.Clamp(path.resolution, 64, 4096);
        var buf = new float[res * res];

        // ── 1. 采样样条 ──────────────────────────────────────────────────
        var samples = SampleSpline(path.points, 24);
        if (samples.Count == 0) return false;

        // ── 2. 沿曲线盖软边圆 ────────────────────────────────────────────
        float halfWidth = Mathf.Max(path.width, 0.1f) * 0.5f;

        for (int s = 0; s < samples.Count; s++)
        {
            Vector2 p = samples[s];

            // 世界坐标 → 掩码 UV
            Vector2 uv = (p - path.worldCenter) / Mathf.Max(path.worldSize, 0.001f) + new Vector2(0.5f, 0.5f);
            if (uv.x < 0f || uv.x > 1f || uv.y < 0f || uv.y > 1f) continue;

            // 噪声扰动路宽（沿路径连续变化，不会一截粗一截细得很突兀）
            float n = Mathf.PerlinNoise(p.x * path.edgeNoiseScale + 13.7f,
                                        p.y * path.edgeNoiseScale + 7.3f) - 0.5f;
            float radius = halfWidth * (1f + n * 2f * path.edgeNoise);
            radius = Mathf.Max(radius, 0.05f);

            float rUV = radius / path.worldSize;
            StampCircle(buf, res, uv.x * res, uv.y * res, rUV * res, path.softness);
        }

        // ── 3. 写进贴图（原地更新，保持资产引用不变）────────────────────
        var mask = path.mask;
        bool isNew = false;

        if (mask == null || mask.width != res || mask.height != res)
        {
            mask = new Texture2D(res, res, TextureFormat.RGBA32, false, true)
            {
                name = "RoadMask",
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };
            isNew = true;
        }

        var px = new Color32[res * res];
        for (int i = 0; i < buf.Length; i++)
        {
            byte v = (byte)Mathf.Clamp(Mathf.RoundToInt(buf[i] * 255f), 0, 255);
            px[i] = new Color32(v, v, v, 255);
        }
        mask.SetPixels32(px);
        mask.Apply(false);

        if (!AssetDatabase.IsValidFolder("Assets/Grass/Data"))
            AssetDatabase.CreateFolder("Assets/Grass", "Data");

        if (isNew)
        {
            AssetDatabase.DeleteAsset(assetPath);
            AssetDatabase.CreateAsset(mask, assetPath);
            path.mask = AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
        }
        else
        {
            EditorUtility.SetDirty(mask);
        }

        path.worldCenter = path.worldCenter;
        EditorUtility.SetDirty(path);
        AssetDatabase.SaveAssets();

        Debug.Log($"[道路] 掩码已重建：{res}×{res}，采样点 {samples.Count}，路宽 {path.width:F1}m → {assetPath}");
        return true;
    }

    // ── Catmull-Rom 采样 ───────────────────────────────────────────────────
    //  注意：Vector3 → Vector2 的隐式转换取的是 (x, y)，而我们的路点都在地面上（y=0），
    //  直接转会把 Z 丢掉、整条路压成一条横线。这里显式取 (x, z)。
    static Vector2 XZ(Vector3 v) => new Vector2(v.x, v.z);

    static List<Vector2> SampleSpline(List<Vector3> pts, int stepsPerSegment)
    {
        var result = new List<Vector2>(pts.Count * stepsPerSegment);

        for (int i = 0; i < pts.Count - 1; i++)
        {
            Vector2 p0 = XZ(pts[Mathf.Max(i - 1, 0)]);
            Vector2 p1 = XZ(pts[i]);
            Vector2 p2 = XZ(pts[i + 1]);
            Vector2 p3 = XZ(pts[Mathf.Min(i + 2, pts.Count - 1)]);

            int steps = Mathf.Max(2, stepsPerSegment);
            for (int s = 0; s < steps; s++)
            {
                float t = s / (float)steps;
                result.Add(CatmullRom(p0, p1, p2, p3, t));
            }
        }

        // 补上最后一个点
        result.Add(XZ(pts[pts.Count - 1]));
        return result;
    }

    static Vector2 CatmullRom(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, float t)
    {
        float t2 = t * t;
        float t3 = t2 * t;
        return 0.5f * ((2f * p1) +
                       (-p0 + p2) * t +
                       (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 +
                       (-p0 + 3f * p1 - 3f * p2 + p3) * t3);
    }

    // ── 软边圆 ────────────────────────────────────────────────────────────
    static void StampCircle(float[] buf, int res, float cx, float cy, float radius, float softness)
    {
        int x0 = Mathf.Clamp(Mathf.FloorToInt(cx - radius - 1), 0, res - 1);
        int x1 = Mathf.Clamp(Mathf.CeilToInt(cx + radius + 1), 0, res - 1);
        int y0 = Mathf.Clamp(Mathf.FloorToInt(cy - radius - 1), 0, res - 1);
        int y1 = Mathf.Clamp(Mathf.CeilToInt(cy + radius + 1), 0, res - 1);

        float invR = 1f / Mathf.Max(radius, 0.0001f);
        float soft = Mathf.Clamp(softness, 0.01f, 1f);

        for (int y = y0; y <= y1; y++)
        {
            float dy = (y + 0.5f) - cy;
            for (int x = x0; x <= x1; x++)
            {
                float dx = (x + 0.5f) - cx;
                float d = Mathf.Sqrt(dx * dx + dy * dy) * invR;
                if (d >= 1f) continue;

                // d=0 → 1，d=1 → 0；soft 控制过渡的宽窄
                float v = Mathf.Clamp01((1f - d) / Mathf.Max(soft, 0.001f));
                v = v * v * (3f - 2f * v);          // smoothstep

                int idx = y * res + x;
                if (v > buf[idx]) buf[idx] = v;     // 取最大值，重叠处不会叠加
            }
        }
    }
}
