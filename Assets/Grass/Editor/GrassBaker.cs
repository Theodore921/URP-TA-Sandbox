using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// ============================================================================
//  GrassBaker —— 撒点烘焙的实现（可以被编辑器窗口调用，也可以被脚本调用）
//
//  和 PCG 的对应关系：
//    GetLandscapeData + SurfaceSampler  → 按密度在地形上撒点并贴地
//    AttributeNoise(Rand0/Rand1)        → 写进 GrassInstance.b
//    Spatial Noise + ClumpID            → clumpSize 网格哈希分簇（同簇共享朝向/尺寸/色调）
//    Transform Points                   → 随机 yaw / scale
//    Spline 抠道路 / Bounds 抠物体      → 预留 exclusions 接口
//    StaticMeshSpawner                  → 输出 GrassFieldData
// ============================================================================

public struct GrassBakeParams
{
    public Terrain terrain;
    public float densityNear;
    public float densityFar;
    public float radiusNear;
    public float radiusFar;
    public float scaleMin;
    public float scaleMax;
    public float clumpSize;
    public float clumpYawSpread;
    public int seed;
    public float sinkIntoGround;
    public float maxSlopeAngle;
    public float edgeMargin;
    public string assetPath;
}

public static class GrassBaker
{
    public static GrassFieldData Bake(GrassBakeParams p)
    {
        var t = p.terrain;
        if (t == null) { Debug.LogError("[草地] 没有 Terrain，无法撒点"); return null; }

        Vector3 center = t.transform.position + t.terrainData.size * 0.5f;
        float half = Mathf.Min(t.terrainData.size.x, t.terrainData.size.z) * 0.5f;

        float step = 1f / Mathf.Sqrt(Mathf.Max(p.densityNear, 0.01f));
        var rng = new System.Random(p.seed);
        var buckets = new Dictionary<Vector2Int, List<GrassInstance>>();

        float x0 = center.x - half, z0 = center.z - half;
        int cells = Mathf.CeilToInt(2f * half / step);
        int placed = 0;
        float maxSlopeAngle = Mathf.Clamp(p.maxSlopeAngle, 0f, 89.9f);
        float edgeMargin = Mathf.Max(0f, p.edgeMargin);
        Vector3 terrainPosition = t.transform.position;
        Vector3 terrainScale = t.transform.lossyScale;
        float terrainWidth = Mathf.Max(t.terrainData.size.x * Mathf.Abs(terrainScale.x), 0.001f);
        float terrainLength = Mathf.Max(t.terrainData.size.z * Mathf.Abs(terrainScale.z), 0.001f);
        Color32[] paintPixels = null;
        int paintWidth = 0;
        int paintHeight = 0;
        var paintMask = t.GetComponent<GrassPaintMask>();
        if (paintMask != null && paintMask.distributionMask != null)
        {
            try
            {
                paintPixels = paintMask.distributionMask.GetPixels32();
                paintWidth = paintMask.distributionMask.width;
                paintHeight = paintMask.distributionMask.height;
            }
            catch (System.Exception e)
            {
                Debug.LogError("[草地] 草地分布图不可读，无法烘焙：" + e.Message);
                return null;
            }
        }

        // ── 道路掩码：路面上不长草 ──────────────────────────────────────────
        var road = UnityEngine.Object.FindObjectOfType<GrassRoadPath>();
        Color32[] roadPixels = null;
        int roadRes = 0;
        Vector2 roadCenter = Vector2.zero;
        float roadSize = 1f;
        if (road != null && road.mask != null)
        {
            try
            {
                roadPixels = road.mask.GetPixels32();
                roadRes = road.mask.width;
                roadCenter = road.worldCenter;
                roadSize = Mathf.Max(road.worldSize, 0.001f);
            }
            catch (System.Exception e)
            {
                Debug.LogWarning("[草地] 道路掩码不可读，跳过路面剔除：" + e.Message);
            }
        }

        for (int ix = 0; ix < cells; ix++)
        {
            for (int iz = 0; iz < cells; iz++)
            {
                float x = x0 + (ix + (float)rng.NextDouble()) * step;
                float z = z0 + (iz + (float)rng.NextDouble()) * step;

                if (!IsSuitableTerrainPosition(t, x, z, edgeMargin, maxSlopeAngle))
                    continue;

                float dx = x - center.x, dz = z - center.z;
                float r = Mathf.Sqrt(dx * dx + dz * dz);
                float dens = DensityAt(p, r);
                if (paintPixels != null)
                {
                    float u = (x - terrainPosition.x) / terrainWidth;
                    float v = (z - terrainPosition.z) / terrainLength;
                    dens *= SamplePaintMask(paintPixels, paintWidth, paintHeight, u, v);
                }
                if (dens <= 0f) continue;

                // 以近处密度为基准拒绝采样 → 平滑的径向衰减
                if (rng.NextDouble() > dens / p.densityNear) continue;

                // ── 路面剔除：掩码 + 噪声抖动 → 边界是被草啃过的锯齿 ──────
                if (roadPixels != null)
                {
                    float m = SampleMask(roadPixels, roadRes, roadCenter, roadSize, x, z);
                    float jitter = ((float)rng.NextDouble() - 0.5f) * 2f * road.grassEdgeJitter;
                    if (m + jitter > road.grassCutThreshold) continue;
                }

                // ── 分簇 ────────────────────────────────────────────────────
                int cx = Mathf.FloorToInt(dx / Mathf.Max(p.clumpSize, 0.01f));
                int cz = Mathf.FloorToInt(dz / Mathf.Max(p.clumpSize, 0.01f));
                float clumpYaw  = Hash01(cx, cz, p.seed, 11) * Mathf.PI * 2f;
                float clumpScale = Hash01(cx, cz, p.seed, 23);

                // 色调不能再用"每格一个随机值"——那样每个 3m 方块颜色完全一致，
                // 块与块之间跳色，远看就是一张棋盘。改成连续噪声场 + 逐株微扰。
                float tint = Mathf.PerlinNoise((x + 1000f) * 0.030f, (z + 1000f) * 0.030f);
                tint = Mathf.Lerp(tint, Mathf.PerlinNoise((x + 500f) * 0.130f, (z + 500f) * 0.130f), 0.45f);
                tint = Mathf.Clamp01(tint + ((float)rng.NextDouble() - 0.5f) * 0.20f);

                float yaw = clumpYaw + ((float)rng.NextDouble() - 0.5f) * 2f * p.clumpYawSpread;
                float scale = Mathf.Lerp(p.scaleMin, p.scaleMax,
                    Mathf.Lerp((float)rng.NextDouble(), clumpScale, 0.6f));

                float y = t.transform.position.y + t.SampleHeight(new Vector3(x, 0f, z)) - p.sinkIntoGround;

                var inst = new GrassInstance
                {
                    a = new Vector4(x, y, z, yaw),
                    b = new Vector4(scale, (float)rng.NextDouble(), tint, tint)
                };

                var key = new Vector2Int(Mathf.FloorToInt(dx / 32f), Mathf.FloorToInt(dz / 32f));
                if (!buckets.TryGetValue(key, out var list))
                {
                    list = new List<GrassInstance>(2048);
                    buckets[key] = list;
                }
                list.Add(inst);
                placed++;
            }
        }

        // ── 摊平成连续数组（按分块顺序）─────────────────────────────────────
        var keys = new List<Vector2Int>(buckets.Keys);
        keys.Sort((a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y));

        var all = new List<GrassInstance>(placed);
        var chunks = new List<GrassChunk>(keys.Count);
        foreach (var key in keys)
        {
            var list = buckets[key];
            chunks.Add(new GrassChunk
            {
                coord = key,
                start = all.Count,
                count = list.Count,
                center = new Vector3(center.x + key.x * 32f + 16f, center.y,
                                     center.z + key.y * 32f + 16f),
                radius = 32f * 0.7071f
            });
            all.AddRange(list);
        }

        // ── 草地密度图（接触阴影用）─────────────────────────────────────────
        // 把「每平米多少株草」烘成一张贴图，地面材质按世界 XZ 采样它来压暗自己，
        // 草根与地面接触的位置就会自然变暗，草不再像悬空的。
        float fieldSize = Mathf.Min(t.terrainData.size.x, t.terrainData.size.z);
        Texture2D densTex = BuildDensityTexture(all, center, fieldSize);

        // ── 写资产 ──────────────────────────────────────────────────────────
        // 注意：必须复用已有资产，不能 Delete + Create —— 那样场景里 GrassField.data
        // 的引用会变成 Missing，表现为"重新烘焙后草全没了"。
        EnsureFolder("Assets/Grass", "Data");
        var data = AssetDatabase.LoadAssetAtPath<GrassFieldData>(p.assetPath);
        bool isNew = data == null;
        if (isNew) data = ScriptableObject.CreateInstance<GrassFieldData>();

        // 实例数据写成二进制（.bytes），32 字节/株
        // 注意：Buffer.BlockCopy 只接受基元数组，GrassInstance[] 是结构体，
        // 必须先摊成 float[]（8 个 float = 2 个 Vector4 = 32 字节）。
        var arr = all.ToArray();
        var floats = new float[arr.Length * 8];
        for (int i = 0; i < arr.Length; i++)
        {
            var a = arr[i].a;
            var b = arr[i].b;
            int o = i * 8;
            floats[o + 0] = a.x; floats[o + 1] = a.y; floats[o + 2] = a.z; floats[o + 3] = a.w;
            floats[o + 4] = b.x; floats[o + 5] = b.y; floats[o + 6] = b.z; floats[o + 7] = b.w;
        }
        var bytes = new byte[floats.Length * 4];
        if (floats.Length > 0) System.Buffer.BlockCopy(floats, 0, bytes, 0, bytes.Length);

        string bytesPath = System.IO.Path.ChangeExtension(p.assetPath, ".bytes");
        System.IO.File.WriteAllBytes(bytesPath, bytes);
        AssetDatabase.ImportAsset(bytesPath, ImportAssetOptions.ForceUpdate);
        data.binary = AssetDatabase.LoadAssetAtPath<TextAsset>(bytesPath);
        data.InvalidateCache();   // 丢掉旧缓存，否则运行时还读上一次的数据

        data.fieldCenter = center;
        data.fieldSize = new Vector2(t.terrainData.size.x, t.terrainData.size.z);
        data.densityNear = p.densityNear;
        data.densityFar = p.densityFar;
        data.radiusNear = p.radiusNear;
        data.radiusFar = p.radiusFar;
        data.clumpSize = p.clumpSize;
        data.seed = p.seed;
        data.chunks = chunks.ToArray();

        if (isNew) AssetDatabase.CreateAsset(data, p.assetPath);
        EditorUtility.SetDirty(data);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        // 把密度图挂到地面材质上
        var groundMat = t.materialTemplate;
        if (groundMat != null && groundMat.HasProperty("_DensityTex"))
        {
            groundMat.SetTexture("_DensityTex", densTex);
            groundMat.SetVector("_DensityRange", new Vector4(center.x, center.z, fieldSize, 0f));
            EditorUtility.SetDirty(groundMat);
            AssetDatabase.SaveAssets();
        }
        else
        {
            Debug.LogWarning("[草地] 地面材质不是 Grass/Ground，接触阴影不会生效。" +
                             "执行 Tools/草地/③ 重建地形材质。");
        }

        float mb = all.Count * 32f / (1024f * 1024f);
        Debug.Log($"[草地] 烘焙完成：{all.Count:N0} 株 / {chunks.Count} 分块 / " +
                  $"显存约 {mb:F1} MB → {p.assetPath}");

        // 通知场景里的 GrassField 重建 GPU 缓冲。
        // 不重建的话，新的 .bytes 已经写盘了，但显存里还是上一次的数据，
        // 画面会一直显示旧的草（改了路/密度都看不出来）。
        var fields = UnityEngine.Object.FindObjectsOfType<GrassField>(true);
        foreach (var field in fields)
        {
            if (field == null) continue;
            field.data = data;
            field.Rebuild();
            EditorUtility.SetDirty(field);
        }
        if (fields.Length > 0)
            Debug.Log($"[草地] 已刷新 {fields.Length} 个 GrassField 的显存缓冲");

        return data;
    }

    /// <summary>
    /// 把撒点结果转成一张密度贴图（256×256）：每个像素记录该区域草的相对覆盖率。
    /// 3×3 核累加 + 一次模糊，边缘才够软，压暗的地面不会出现硬边。
    /// </summary>
    static Texture2D BuildDensityTexture(List<GrassInstance> instances, Vector3 center,
                                         float size, int res = 256)
    {
        var acc = new float[res * res];
        float inv = 1f / Mathf.Max(size, 0.001f);

        foreach (var it in instances)
        {
            int tx = Mathf.Clamp(Mathf.FloorToInt(((it.a.x - center.x) * inv + 0.5f) * res), 0, res - 1);
            int ty = Mathf.Clamp(Mathf.FloorToInt(((it.a.z - center.z) * inv + 0.5f) * res), 0, res - 1);

            for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
            {
                int x = tx + dx, y = ty + dy;
                if (x < 0 || y < 0 || x >= res || y >= res) continue;
                float w = (dx == 0 && dy == 0) ? 1f : ((dx == 0 || dy == 0) ? 0.5f : 0.25f);
                acc[y * res + x] += w;
            }
        }

        float max = 0.0001f;
        for (int i = 0; i < acc.Length; i++) if (acc[i] > max) max = acc[i];

        var px = new float[acc.Length];
        for (int i = 0; i < acc.Length; i++)
            px[i] = Mathf.Pow(Mathf.Clamp01(acc[i] / max), 0.75f);

        // 一次 3×3 模糊
        var blurred = new float[acc.Length];
        for (int y = 0; y < res; y++)
        for (int x = 0; x < res; x++)
        {
            float s = 0f;
            for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
            {
                int xx = Mathf.Clamp(x + dx, 0, res - 1);
                int yy = Mathf.Clamp(y + dy, 0, res - 1);
                s += px[yy * res + xx];
            }
            blurred[y * res + x] = s / 9f;
        }

        var tex = new Texture2D(res, res, TextureFormat.RGBA32, false, true)
        {
            name = "GrassDensity",
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear
        };

        var cols = new Color[blurred.Length];
        for (int i = 0; i < blurred.Length; i++)
            cols[i] = new Color(blurred[i], blurred[i], blurred[i], 1f);
        tex.SetPixels(cols);
        tex.Apply();

        const string path = "Assets/Grass/Data/GrassDensity.asset";
        AssetDatabase.DeleteAsset(path);
        AssetDatabase.CreateAsset(tex, path);
        AssetDatabase.SaveAssets();

        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }

    /// <summary>按世界 XZ 采样道路掩码（0 = 无路，1 = 路面中心）。</summary>
    static float SampleMask(Color32[] px, int res, Vector2 center, float size, float x, float z)
    {
        float u = (x - center.x) / size + 0.5f;
        float v = (z - center.y) / size + 0.5f;
        if (u < 0f || u > 1f || v < 0f || v > 1f) return 0f;

        int ix = Mathf.Clamp((int)(u * res), 0, res - 1);
        int iy = Mathf.Clamp((int)(v * res), 0, res - 1);
        return px[iy * res + ix].r / 255f;
    }

    static float DensityAt(GrassBakeParams p, float r)    {
        if (r >= p.radiusFar) return 0f;
        if (r <= p.radiusNear) return p.densityNear;
        float k = (r - p.radiusNear) / Mathf.Max(p.radiusFar - p.radiusNear, 0.001f);
        return Mathf.Lerp(p.densityNear, p.densityFar, k);
    }

    public static float EstimateCount(GrassBakeParams p)
    {
        if (p.terrain == null) return 0f;
        var t = p.terrain;
        Vector3 center = t.transform.position + t.terrainData.size * 0.5f;
        float half = Mathf.Min(t.terrainData.size.x, t.terrainData.size.z) * 0.5f;
        float step = 1f / Mathf.Sqrt(Mathf.Max(p.densityNear, 0.01f));
        float sampleStep = Mathf.Max(step, 1f);
        float maxSlopeAngle = Mathf.Clamp(p.maxSlopeAngle, 0f, 89.9f);
        float edgeMargin = Mathf.Max(0f, p.edgeMargin);
        Vector3 terrainPosition = t.transform.position;
        Vector3 terrainScale = t.transform.lossyScale;
        float terrainWidth = Mathf.Max(t.terrainData.size.x * Mathf.Abs(terrainScale.x), 0.001f);
        float terrainLength = Mathf.Max(t.terrainData.size.z * Mathf.Abs(terrainScale.z), 0.001f);
        Color32[] paintPixels = null;
        int paintWidth = 0;
        int paintHeight = 0;
        var paintMask = t.GetComponent<GrassPaintMask>();
        if (paintMask != null && paintMask.distributionMask != null)
        {
            paintPixels = paintMask.distributionMask.GetPixels32();
            paintWidth = paintMask.distributionMask.width;
            paintHeight = paintMask.distributionMask.height;
        }
        double sum = 0;
        for (float x = center.x - half + sampleStep * 0.5f; x < center.x + half; x += sampleStep)
        for (float z = center.z - half + sampleStep * 0.5f; z < center.z + half; z += sampleStep)
        {
            if (!IsSuitableTerrainPosition(t, x, z, edgeMargin, maxSlopeAngle))
                continue;

            float r = Mathf.Sqrt((x - center.x) * (x - center.x) + (z - center.z) * (z - center.z));
            float density = DensityAt(p, r);
            if (paintPixels != null)
            {
                float u = (x - terrainPosition.x) / terrainWidth;
                float v = (z - terrainPosition.z) / terrainLength;
                density *= SamplePaintMask(paintPixels, paintWidth, paintHeight, u, v);
            }
            sum += density * sampleStep * sampleStep;
        }
        return (float)sum;
    }

    static float SamplePaintMask(Color32[] pixels, int width, int height, float u, float v)
    {
        if (pixels == null || width <= 0 || height <= 0 || pixels.Length < width * height ||
            u < 0f || u > 1f || v < 0f || v > 1f)
            return 0f;

        float x = u * (width - 1);
        float y = v * (height - 1);
        int x0 = Mathf.FloorToInt(x);
        int y0 = Mathf.FloorToInt(y);
        int x1 = Mathf.Min(x0 + 1, width - 1);
        int y1 = Mathf.Min(y0 + 1, height - 1);
        float tx = x - x0;
        float ty = y - y0;
        float a = Mathf.Lerp(pixels[y0 * width + x0].r,
                             pixels[y0 * width + x1].r, tx);
        float b = Mathf.Lerp(pixels[y1 * width + x0].r,
                             pixels[y1 * width + x1].r, tx);
        return Mathf.Lerp(a, b, ty) / 255f;
    }

    static bool IsSuitableTerrainPosition(Terrain terrain, float worldX, float worldZ,
                                          float edgeMargin, float maxSlopeAngle)
    {
        var terrainData = terrain.terrainData;
        Vector3 terrainPosition = terrain.transform.position;
        Vector3 terrainScale = terrain.transform.lossyScale;
        float width = terrainData.size.x * Mathf.Abs(terrainScale.x);
        float length = terrainData.size.z * Mathf.Abs(terrainScale.z);
        if (width <= 0f || length <= 0f)
            return false;

        float u = (worldX - terrainPosition.x) / width;
        float v = (worldZ - terrainPosition.z) / length;
        float marginU = Mathf.Clamp(edgeMargin, 0f, width * 0.5f) / width;
        float marginV = Mathf.Clamp(edgeMargin, 0f, length * 0.5f) / length;
        if (u < marginU || u > 1f - marginU || v < marginV || v > 1f - marginV)
            return false;

        Vector3 localNormal = terrainData.GetInterpolatedNormal(u, v);
        Vector3 worldNormal = terrain.transform.TransformDirection(localNormal).normalized;
        return Vector3.Angle(worldNormal, Vector3.up) <= maxSlopeAngle;
    }

    static float Hash01(int x, int z, int seed, int salt)
    {
        unchecked
        {
            uint h = (uint)(x * 73856093) ^ (uint)(z * 19349663)
                   ^ (uint)(seed * 83492791) ^ (uint)(salt * 2654435761);
            h ^= h >> 13; h *= 1274126177; h ^= h >> 16;
            return (h & 0xFFFFFF) / (float)0xFFFFFF;
        }
    }

    static void EnsureFolder(string parent, string child)
    {
        if (!AssetDatabase.IsValidFolder($"{parent}/{child}"))
            AssetDatabase.CreateFolder(parent, child);
    }
}
