using UnityEngine;

/// <summary>
/// 噪声贴图的参数与算法本体。纯运行时脚本，不引用 UnityEditor，因此可以安全参与打包。
///
/// 编辑器入口（菜单 + 窗口）见 Assets/Codes/Editor/NoiseTextureGeneratorWindow.cs。
/// 运行时调用示例：
///   var tex = NoiseTextureGenerator.Generate(NoiseTextureGenerator.Params.Default);
///   // 用完记得 Object.Destroy(tex);
///
/// 关于无缝：Perlin 噪声的梯度表周期是 256，直接给采样坐标加常数或按 UV 周期取模都
/// 不会让它平铺（倍频把采样点挪了 f 个晶格，而 P[X+f] != P[X]）。这里改为在**晶格坐标**
/// 上按该层周期取模，于是每层都严格以 1 个 UV 为周期，任意频率都能无缝。
/// 代价是开启 tileable 时 frequency 会被量化到整数晶格。
/// </summary>
public static class NoiseTextureGenerator
{
    public enum Mode { FBM, Ridged, Cellular }

    [System.Serializable]
    public struct Params
    {
        public int size;
        public Mode mode;
        public int octaves;
        public float frequency;
        public float persistence;
        public int seed;
        public bool tileable;
        public bool inverse;
        public bool generateMipmaps;

        public static Params Default => new Params
        {
            size = 512,
            mode = Mode.FBM,
            octaves = 5,
            frequency = 4f,
            persistence = 0.5f,
            seed = 1337,
            tileable = true,
            inverse = false,
            generateMipmaps = false,
        };
    }

    /// <summary>生成一张新的噪声贴图。调用方负责在不用时 Object.Destroy 掉它。</summary>
    public static Texture2D Generate(Params p)
    {
        int octaves = Mathf.Clamp(p.octaves, 1, 12);
        float frequency = Mathf.Max(0.25f, p.frequency);
        float persistence = Mathf.Clamp(p.persistence, 0.01f, 1f);
        int res = Mathf.Clamp(Mathf.ClosestPowerOfTwo(p.size), 8, 4096);

        // 无缝模式：量化到整数晶格，这样每层的周期都是整数
        if (p.tileable) frequency = Mathf.Max(1f, Mathf.Round(frequency));

        var tex = new Texture2D(res, res, TextureFormat.R8, p.generateMipmaps, true); // 线性数据，sRGB 关闭
        tex.name = $"Noise_{p.mode}_{res}";
        tex.wrapMode = p.tileable ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
        tex.filterMode = FilterMode.Bilinear;

        var px = new Color32[res * res];

        // 按振幅总和归一化，避免 fBm/Ridged 的输出偏向某一端
        float ampSum = 0f;
        for (int i = 0; i < octaves; i++) ampSum += Mathf.Pow(persistence, i);
        if (ampSum <= 0f) ampSum = 1f;

        for (int y = 0; y < res; y++)
        {
            for (int x = 0; x < res; x++)
            {
                float u = (float)x / res;
                float v = (float)y / res;

                float n = p.mode == Mode.Cellular
                    ? Cellular(u, v, frequency, p.seed, p.tileable)
                    : Fractal(u, v, frequency, persistence, octaves, p.seed, ampSum,
                              p.mode == Mode.Ridged, p.tileable);

                if (p.inverse) n = 1f - n;
                byte b = (byte)Mathf.Clamp(Mathf.RoundToInt(n * 255f), 0, 255);
                px[y * res + x] = new Color32(b, b, b, 255);
            }
        }

        tex.SetPixels32(px);
        tex.Apply(p.generateMipmaps);
        return tex;
    }

    /// <summary>FBM / Ridged 共用的多倍频叠加。ridged 为真时把每层折成山脊。</summary>
    static float Fractal(float u, float v, float frequency, float persistence,
                         int octaves, int seed, float ampSum, bool ridged, bool tileable)
    {
        float sum = 0f, amp = 1f, f = frequency;
        for (int i = 0; i < octaves; i++)
        {
            // 每层整数晶格周期就是 f（frequency 已量化），每层换一个整数相位，
            // 这样不同 seed / 不同倍频得到不同图案，同时周期不被破坏。
            int period = Mathf.Max(1, Mathf.RoundToInt(f));
            int phase = HashInt(seed, i);
            float n = tileable
                ? PerlinPeriodic(u * f, v * f, period, phase)
                : PerlinShifted(u * f, v * f, seed + i);

            sum += amp * (ridged ? 1f - Mathf.Abs(n * 2f - 1f) : n);
            amp *= persistence;
            f *= 2f;
        }
        return Mathf.Clamp01(sum / ampSum);
    }

    // ---- Perlin 梯度表（与 Unity 内置 Mathf.PerlinNoise 相同的经典表） ----

    static readonly int[] Perm =
    {
        151,160,137, 91, 90, 15,131, 13,201, 95, 96, 53,194,233,  7,225,140, 36,103, 30, 69,
        142,  8, 99, 37,240, 21, 10, 23,190,  6,148,247,120,234, 75,  0, 26,197, 62, 94,252,
        219,203,117, 35, 11, 32, 57,177, 33, 88,237,149, 56, 87,174, 20,125,136,171,168, 68,
        175, 74,165, 71,134,139, 48, 27,166, 77,146,158,231, 83,111,229,122, 60,211,133,230,
        220,105, 92, 41, 55, 46,245, 40,244,102,143, 54, 65, 25, 63,161,  1,216, 80, 73,209,
         76,132,187,208, 89, 18,169,200,196,135,130,116,188,159, 86,164,100,109,198,173,186,
          3, 64, 52,217,226,250,124,123,  5,202, 38,147,118,126,255, 82, 85,212,207,206, 59,
        227, 47, 16, 58, 17,182,189, 28, 42,223,183,170,213,119,248,152,  2, 44,154,163, 70,
        221,153,101,155,167, 43,172,  9,129, 22, 39,253, 19, 98,108,110, 79,113,224,232,178,
        185,112,104,218,246, 97,228,251, 34,242,193,238,210,144, 12,191,179,162,241, 81, 51,
        145,235,249, 14,239,107, 49,192,214, 31,181,199,106,157,184, 84,204,176,115,121, 50,
         45,127,  4,150,254,138,236,205, 93,222,114, 67, 29, 24, 72,243,141,128,195, 78, 66,
        215, 61,156,180
    };

    static readonly int[] Perm512 = BuildPerm512();

    static int[] BuildPerm512()
    {
        var r = new int[512];
        for (int i = 0; i < 512; i++) r[i] = Perm[i & 255];
        return r;
    }

    static float Fade(float t) => t * t * t * (t * (t * 6f - 15f) + 10f);

    static float Grad(int hash, float x, float y)
    {
        int h = hash & 15;
        float u = h < 8 ? x : y;
        float v = h < 4 ? y : (h == 12 || h == 14 ? x : 0f);
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
    }

    /// <summary>
    /// 周期性 Perlin：晶格索引按 period 取模，所以 f(x + period) == f(x)。
    /// phase 是整数，用来给不同 seed / 倍频换图案；整数平移不破坏周期性。
    /// </summary>
    static float PerlinPeriodic(float x, float y, int period, int phase)
    {
        if (period < 1) period = 1;

        float xf = Mathf.Floor(x), yf = Mathf.Floor(y);
        int xi = (int)xf, yi = (int)yf;
        x -= xf;
        y -= yf;

        int x0 = WrapIndex(xi, period, phase), x1 = WrapIndex(xi + 1, period, phase);
        int y0 = WrapIndex(yi, period, phase + 101), y1 = WrapIndex(yi + 1, period, phase + 101);

        float u = Fade(x), v = Fade(y);
        float n00 = Grad(Perm512[(Perm512[x0] + y0) & 511], x, y);
        float n10 = Grad(Perm512[(Perm512[x1] + y0) & 511], x - 1f, y);
        float n01 = Grad(Perm512[(Perm512[x0] + y1) & 511], x, y - 1f);
        float n11 = Grad(Perm512[(Perm512[x1] + y1) & 511], x - 1f, y - 1f);

        float nx0 = Mathf.Lerp(n00, n10, u);
        float nx1 = Mathf.Lerp(n01, n11, u);
        // 幅值约 ±0.7，映射到 [0,1]
        return Mathf.Clamp01(Mathf.Lerp(nx0, nx1, v) * 0.7f + 0.5f);
    }

    /// <summary>非无缝模式：直接用内置 Perlin，seed 只做采样平移。</summary>
    static float PerlinShifted(float x, float y, int seed)
    {
        float o = (seed % 512) * 7.13f;
        return Mathf.PerlinNoise(x + o, y + o);
    }

    /// <summary>把晶格索引折到 [0, period)，对负数也返回非负值。</summary>
    static int WrapIndex(int v, int period, int phase)
    {
        int m = (v + phase) % period;
        return m < 0 ? m + period : m;
    }

    /// <summary>由 seed 和倍频序号得到一个稳定的整数相位。</summary>
    static int HashInt(int seed, int i)
    {
        unchecked
        {
            int h = seed * 73856093 ^ i * 19349663;
            return h & 0x7FFFFFF;
        }
    }

    /// <summary>Worley / 细胞噪声：到最近特征点的距离。</summary>
    static float Cellular(float u, float v, float frequency, int seed, bool tileable)
    {
        float f = Mathf.Max(1f, Mathf.Round(frequency));
        float xu = u * frequency, yv = v * frequency;
        int cx = Mathf.FloorToInt(xu), cy = Mathf.FloorToInt(yv);
        float best = float.MaxValue;
        int ph = seed * 131;

        for (int oy = -1; oy <= 1; oy++)
        {
            for (int ox = -1; ox <= 1; ox++)
            {
                int gx = cx + ox, gy = cy + oy;
                // 特征点落在整数格点上；tileable 时把格点折回周期，边缘就接得上
                int hx = tileable ? WrapIndex(gx, (int)f, ph) : gx;
                int hy = tileable ? WrapIndex(gy, (int)f, ph + 57) : gy;
                var pt = new Vector2(gx + Hash01(hx, hy, 0), gy + Hash01(hx, hy, 1));
                float d = (pt - new Vector2(xu, yv)).sqrMagnitude;
                if (d < best) best = d;
            }
        }

        // sqrt(best) 已经是「以单元胞为单位」的距离（实测范围约 0.00–0.98，与 frequency 无关），
        // 所以这里不需要再乘 frequency。乘了反而会让中位数冲到 1.7、被 Clamp01 截成大片纯白。
        // 传统 F1 观感是「细胞内部亮、边界暗」，故取 1 - d。
        return Mathf.Clamp01(1f - Mathf.Sqrt(best));
    }

    /// <summary>整数格点上的确定性伪随机数，返回 [0,1)。</summary>
    static float Hash01(int x, int y, int salt)
    {
        unchecked
        {
            uint h = (uint)(x * 374761393 + y * 668265263 + salt * 1274126177);
            h = (h ^ (h >> 13)) * 1274126177u;
            h ^= h >> 16;
            return (h & 0xFFFFFF) / 16777216f;
        }
    }
}
