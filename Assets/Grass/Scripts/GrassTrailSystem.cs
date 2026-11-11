using System.Collections.Generic;
using UnityEngine;

// ============================================================================
//  GrassTrailSystem —— 草地交互的"推力场"
//
//  一张覆盖整个草场的正视 RT（RG 两个半精度通道 = 世界空间二维推力向量）：
//      R = 推力.x（世界 X）
//      G = 推力.y（世界 Z）
//
//  ── 为什么不用"衰减回写 + 盖印"的写法 ──────────────────────────────────
//  最初实现是每帧 Blit(旧图 → 新图) 乘一个衰减系数，再往新图上盖印（乒乓）。
//  实测下来 RT 会变成一整片平均值、几乎不衰减 —— 读回/写同一张半精度 RT
//  的反馈路径在 URP 下不稳定，而且盖印被平均掉，看起来就是"没有效果"。
//
//  现在改成无反馈的确定做法：
//      每帧清空 RT → 把最近 N 个脚印按时间淡出重新画一遍
//  没有读-写同一目标的反馈，行为完全可预测；代价是每帧多画 N 个全屏四边形
//  （N ≤ 上限，且每个都极便宜，实测可忽略）。
//
//  为什么存"向量"而不是"强度"：
//      只存强度的话，着色器只能拿"草的位置 - 玩家位置"当方向，
//      玩家一移动，已倒伏的草会跟着转向，像被磁铁吸着转。
// ============================================================================

[ExecuteAlways]
[AddComponentMenu("草地/Grass Trail System")]
public class GrassTrailSystem : MonoBehaviour
{
    struct Stamp
    {
        public Vector2 centerUV;
        public Vector2 radiusUV;
        public float angle;      // 弧度（沿速度拉伸的方向）
        public float strength;
        public float birthTime;
    }

    public static GrassTrailSystem Instance { get; private set; }

    [Header("推力场")]
    [Tooltip("RT 分辨率：1024 在 120m 范围约 12cm/纹素")]
    public int resolution = 1024;
    [Tooltip("推力场覆盖的世界范围中心（XZ）")]
    public Vector2 worldCenter = Vector2.zero;
    [Tooltip("推力场覆盖的世界尺寸（米）")]
    public float worldSize = 120f;

    [Header("脚印")]
    [Tooltip("最多保留多少个脚印（每帧全部重画）")]
    public int maxStamps = 512;
    [Tooltip("走多远留一个脚印（米）")]
    public float stampSpacing = 0.18f;
    [Tooltip("每个脚印的推力（会叠加）")]
    public float stampStrength = 0.45f;
    [Tooltip("脚印存活时间（秒）")]
    public float stampLifetime = 2.0f;
    [Tooltip("边缘柔和度：1 = 线性，越大边缘越硬")]
    public float stampSoftness = 1.4f;
    [Tooltip("按速度拉伸的最大倍数")]
    public float maxStretch = 2.0f;
    [Tooltip("达到最大拉伸所需速度（米/秒）")]
    public float stretchSpeed = 4f;

    [Header("材质")]
    public Material grassMaterial;
    public Material stampMaterial;

    [Header("调试")]
    [Tooltip("Update 执行次数（用来确认逐帧循环真的在跑）")]
    public int _debugTicks;

    static readonly List<GrassTrailEmitter> Emitters = new List<GrassTrailEmitter>();

    readonly List<Stamp> _stamps = new List<Stamp>();
    readonly Dictionary<GrassTrailEmitter, Vector2> _lastStampPos = new Dictionary<GrassTrailEmitter, Vector2>();

    RenderTexture _rt;
    Mesh _quad;

    /// <summary>推力场纹理（供 GrassField 的 compute 采样）。</summary>
    public Texture FieldTexture => _rt;
    public Vector2 WorldCenter => worldCenter;
    public float WorldSize => worldSize;

    static readonly int TrailTexId = Shader.PropertyToID("_TrailTex");
    static readonly int TrailRangeId = Shader.PropertyToID("_GrassTrailRange");

    public static void Register(GrassTrailEmitter e)
    {
        if (e != null && !Emitters.Contains(e)) Emitters.Add(e);
    }

    public static void Unregister(GrassTrailEmitter e)
    {
        Emitters.Remove(e);
    }

    void OnEnable()
    {
        Instance = this;
        EnsureTarget();
        BindToGrass();
    }

    void OnDisable()
    {
        if (Instance == this) Instance = null;
        ReleaseTarget();
        if (grassMaterial != null) grassMaterial.SetTexture(TrailTexId, null);
    }

    void EnsureTarget()
    {
        if (_rt != null) return;

        int res = Mathf.Clamp(resolution, 64, 4096);
        // 用 ARGBHalf 而不是 RGHalf：两通道的 RT 在顶点着色器里采样时，
        // 部分平台/驱动会读回全 0（实测草完全不响应），四通道稳。
        var desc = new RenderTextureDescriptor(res, res, RenderTextureFormat.ARGBHalf, 0)
        {
            msaaSamples = 1,
            useMipMap = false,
            autoGenerateMips = false,
            sRGB = false
        };

        _rt = new RenderTexture(desc)
        {
            name = "GrassTrail",
            filterMode = FilterMode.Bilinear,
            wrapMode = TextureWrapMode.Clamp
        };
        _rt.Create();

        ClearTarget();

        if (_quad == null) _quad = BuildQuad();
    }

    void ReleaseTarget()
    {
        if (_rt != null) { _rt.Release(); DestroyImmediate(_rt); _rt = null; }
    }

    void ClearTarget()
    {
        var prev = RenderTexture.active;
        Graphics.SetRenderTarget(_rt);
        GL.Clear(false, true, Color.clear);
        RenderTexture.active = prev;
    }

    void BindToGrass()
    {
        // 推力场现在由 GrassField 的 compute 采样，这里不需要再绑材质。
        // （预留：将来如果要画调试视图，可以把 _rt 绑到某个调试材质上）
    }

    void Update()
    {
        _debugTicks++;
        if (_rt == null) EnsureTarget();
        if (_rt == null || stampMaterial == null) return;

        PushStamps();
        RenderTrail();
        BindToGrass();
    }

    /// <summary>走够一定距离就往缓冲里塞一个新脚印。</summary>
    void PushStamps()
    {
        float now = Time.time;

        for (int i = 0; i < Emitters.Count; i++)
        {
            var e = Emitters[i];
            if (e == null || !e.isActiveAndEnabled) continue;

            Vector3 p = e.transform.position;
            Vector2 xz = new Vector2(p.x, p.z);

            // 世界坐标 → 推力场 UV
            Vector2 uv = (xz - worldCenter) / worldSize + new Vector2(0.5f, 0.5f);
            if (uv.x < -0.1f || uv.x > 1.1f || uv.y < -0.1f || uv.y > 1.1f) continue;

            // 距离节流：走出一小步才留一个印
            if (_lastStampPos.TryGetValue(e, out var last) &&
                Vector2.Distance(last, xz) < stampSpacing)
                continue;
            _lastStampPos[e] = xz;

            Vector3 vel = e.Velocity;
            float speed = new Vector2(vel.x, vel.z).magnitude;
            float stretch = 1f + Mathf.Clamp01(speed / Mathf.Max(stretchSpeed, 0.01f)) * (maxStretch - 1f);
            float angle = Mathf.Atan2(vel.z, vel.x);

            float radiusUV = Mathf.Max(e.radius, 0.05f) / worldSize;

            _stamps.Add(new Stamp
            {
                centerUV = uv,
                radiusUV = new Vector2(radiusUV * stretch, radiusUV),
                angle = angle,
                strength = stampStrength * e.strength,
                birthTime = now
            });
        }

        // 移除过期 / 超出上限
        for (int i = _stamps.Count - 1; i >= 0; i--)
            if (now - _stamps[i].birthTime > stampLifetime)
                _stamps.RemoveAt(i);

        if (_stamps.Count > maxStamps)
            _stamps.RemoveRange(0, _stamps.Count - maxStamps);
    }

    /// <summary>清空推力场，把还活着的脚印按时间淡出重画一遍。</summary>
    void RenderTrail()
    {
        var prev = RenderTexture.active;
        Graphics.SetRenderTarget(_rt);
        GL.Clear(false, true, Color.clear);
        GL.PushMatrix();
        GL.LoadOrtho();

        float now = Time.time;
        float angle, ca, sa;
        for (int i = 0; i < _stamps.Count; i++)
        {
            var s = _stamps[i];
            float age = Mathf.Clamp01((now - s.birthTime) / Mathf.Max(stampLifetime, 0.01f));
            float fade = 1f - age;
            fade *= fade;                       // 尾巴收得更快

            stampMaterial.SetVector("_Center", new Vector4(s.centerUV.x, s.centerUV.y, 0f, 0f));
            stampMaterial.SetVector("_Radius", new Vector4(s.radiusUV.x, s.radiusUV.y, 0f, 0f));
            stampMaterial.SetFloat("_Angle", s.angle);
            stampMaterial.SetFloat("_Strength", s.strength * fade);
            stampMaterial.SetFloat("_Softness", stampSoftness);

            if (stampMaterial.SetPass(0))
                Graphics.DrawMeshNow(_quad, Matrix4x4.identity);
        }

        GL.PopMatrix();
        Graphics.SetRenderTarget(prev);
    }

    static Mesh BuildQuad()
    {
        // 0~1 的全屏四边形：GL.LoadOrtho 下直接铺满整个 RT
        var mesh = new Mesh { name = "GrassTrailQuad", hideFlags = HideFlags.HideAndDontSave };
        mesh.vertices = new[]
        {
            new Vector3(0f, 0f, 0f),
            new Vector3(1f, 0f, 0f),
            new Vector3(1f, 1f, 0f),
            new Vector3(0f, 1f, 0f)
        };
        mesh.uv = new[]
        {
            new Vector2(0f, 0f), new Vector2(1f, 0f),
            new Vector2(1f, 1f), new Vector2(0f, 1f)
        };
        mesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
        mesh.RecalculateBounds();
        return mesh;
    }
}
