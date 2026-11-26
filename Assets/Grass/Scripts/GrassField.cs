using UnityEngine;
using UnityEngine.Rendering;

// ============================================================================
//  GrassField —— 草地渲染器
//
//  一帧只做三件事：
//    1. 把实例数据/可见索引/风时间推给材质
//    2. 用 compute shader 做视锥剔除 + 距离降密度，把可见索引压进一个缓冲
//    3. 用 DrawMeshInstancedIndirect 一次画完整个草场
//
//  为什么用 Indirect 而不是 DrawMeshInstanced：
//    DrawMeshInstanced 每批最多 1023 个实例、且每批都要 CPU 提交；
//    20 万株就是 ~196 次提交。Indirect 让整片草变成 1 次 draw，
//    实例数量由 GPU 上的 args 缓冲决定，CPU 完全不参与。
//
//  注意：compute 剔除用的是「实例根部点 + 1.5m 余量」的保守测试，
//        草叶只有 1m 高，不会出现边缘突然缺一块。
// ============================================================================

[ExecuteAlways]
[DisallowMultipleComponent]
[AddComponentMenu("草地/Grass Field")]
public class GrassField : MonoBehaviour
{
    [Header("资源")]
    [Tooltip("烘焙出来的草场数据（Tools/草地/烘焙草场）")]
    public GrassFieldData data;
    [Tooltip("草叶网格（Tools/草地/生成草叶网格）")]
    public Mesh mesh;
    [Tooltip("草地材质（Grass/GrassField）")]
    public Material material;
    [Tooltip("剔除用的 ComputeShader")]
    public ComputeShader cullShader;

    [Header("剔除")]
    [Tooltip("关掉后会画全部实例（只用于调试对比）")]
    public bool enableCulling = true;
    [Tooltip("超过这个距离的草完全不画")]
    public float maxDistance = 42f;
    [Tooltip("从这个距离开始降密度")]
    public float densityStart = 15f;
    [Tooltip("到这个距离密度降到 farKeep")]
    public float densityEnd = 40f;
    [Range(0f, 1f)]
    [Tooltip("远处保留比例：0.35 表示 35% 的草")]
    public float farKeep = 0.35f;

    [Header("阴影")]
    [Tooltip("草影很贵（等于再画一遍草），1080p 40 系显卡建议先关，最后再开")]
    public bool castShadows = false;
    public bool receiveShadows = true;

    [Header("与天空球联动")]
    [Tooltip("远处草的颜色向天空球的地面色融合，避免地平线出现硬边")]
    public bool linkHorizonToSky = true;
    public Color horizonFallback = new Color(0.22f, 0.21f, 0.19f);
    [Range(0f, 4f)] public float horizonAmbientScale = 1.6f;
    [Tooltip("雾色跟着时段走（否则日落/夜里远处是一片死灰）")]
    public bool linkFogToSky = true;
    [Tooltip("天光补光强度：日落/夜里主光几乎没了，靠这层让草不至于全黑")]
    [Range(0f, 3f)] public float ambientTintScale = 1.0f;
    [Tooltip("夜间亮度地板：环境光低于这个值时会被抬上来，保证月亮下能看见草")]
    [Range(0f, 0.3f)] public float nightFloor = 0.055f;

    [Header("调试")]
    public bool showStats = false;

    [Tooltip("冻结剔除：始终用 frozenCullCamera 计算视锥，而不是当前渲染的相机。\n" +
             "配合 Scene 视图飞出去，就能看到「Game 相机视锥内的那片草」。")]
    public bool freezeCull = false;
    [Tooltip("冻结时用作视锥来源的相机（留空则冻结时自动取 Camera.main）")]
    public Camera frozenCullCamera;

    [ContextMenu("冻结为当前主相机")]
    void FreezeToMainCamera()
    {
        frozenCullCamera = Camera.main;
        freezeCull = true;
        Debug.Log($"[草地] 剔除已冻结到 {frozenCullCamera?.name}，现在把 Scene 视图飞出去就能看到视锥内实际提交的草");
    }

    [ContextMenu("取消冻结")]
    void UnfreezeCull()
    {
        freezeCull = false;
        Debug.Log("[草地] 剔除已恢复为「每台相机各自计算」");
    }

    // ── 运行时 ──────────────────────────────────────────────────────────────
    ComputeBuffer _instances;
    ComputeBuffer _visible;
    ComputeBuffer _identity;     // enableCulling=false 时用的恒等索引
    ComputeBuffer _args;
    int _kernelReset, _kernelCull;
    Bounds _bounds;
    Camera _cam;
    int _total;
    bool _ready;

    static readonly int InstancesId = Shader.PropertyToID("_Instances");
    static readonly int VisibleId = Shader.PropertyToID("_VisibleIndices");

    /// <summary>compute 输出实例的字节数：a/b/c 三个 float4。</summary>
    public const int OutStride = 48;
    static readonly int WindTimeId = Shader.PropertyToID("_GrassWindTime");
    static readonly int HorizonId = Shader.PropertyToID("_GrassHorizonColor");
    static readonly int AmbientTintId = Shader.PropertyToID("_GrassAmbientTint");
    static readonly int PixelScaleId = Shader.PropertyToID("_GrassPixelScale");
    static readonly int ContactShadowId = Shader.PropertyToID("_GrassContactShadow");

    void OnEnable()
    {
        Rebuild();
        // 逐帧工作挂在渲染回调上，而不是 Update：
        // 编辑器空闲时 Update 可能不跑（画面就"消失"了），而只要在渲染就一定会回调。
        RenderPipelineManager.beginCameraRendering += OnBeginCamera;

        // 草地开着 → 地面上的"草根接触阴影"也开着
        Shader.SetGlobalFloat(ContactShadowId, 1f);
    }

    void OnDisable()
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCamera;
        Release();

        // 草地关掉 → 把地面上的接触阴影一起关掉。
        // 否则地面会留着一大团按密度图压暗的黑斑（看起来像阴影出错）。
        Shader.SetGlobalFloat(ContactShadowId, 0f);
    }

    void OnValidate()
    {
        if (!isActiveAndEnabled) return;
        Rebuild();
    }

    /// <summary>数据变了之后重建 GPU 缓冲（也可以在 Inspector 右键菜单手动调用）。</summary>
    [ContextMenu("重建缓冲")]
    public void Rebuild()
    {
        Release();
        if (data == null || mesh == null || material == null || cullShader == null) return;

        _total = data.InstanceCount;
        if (_total <= 0) return;

        // 32 字节/株，布局必须和 compute 里的 GrassInstance 一致
        var instances = data.GetInstances();
        _instances = new ComputeBuffer(_total, GrassFieldData.Stride, ComputeBufferType.Structured);
        _instances.SetData(instances);

        // compute 的输出：压缩后的实例 + 推力向量（48 字节/株）
        _visible = new ComputeBuffer(_total, OutStride, ComputeBufferType.Structured);

        _args = new ComputeBuffer(5, sizeof(uint), ComputeBufferType.IndirectArguments);
        _args.SetData(new[]
        {
            (uint)mesh.GetIndexCount(0),
            0u,
            (uint)mesh.GetIndexStart(0),
            (uint)mesh.GetBaseVertex(0),
            0u
        });

        _kernelReset = cullShader.FindKernel("ResetArgs");
        _kernelCull = cullShader.FindKernel("Cull");

        _bounds = data.ComputeBounds();
        _ready = true;

        if (showStats)
            Debug.Log($"[草地] 缓冲就绪：{_total:N0} 株，{_total * 32f / 1048576f:F1} MB");
    }

    void Release()
    {
        _instances?.Release(); _instances = null;
        _visible?.Release(); _visible = null;
        _args?.Release(); _args = null;
        _ready = false;
    }

    void OnBeginCamera(ScriptableRenderContext context, Camera cam)
    {
        // 数据是后挂上的（比如先建物体后烘焙），这里做一次自愈重建
        if (!_ready)
        {
            if (data != null && data.InstanceCount > 0) Rebuild();
            if (!_ready) return;
        }

        // 资源被删/被替换时（编辑器里重新生成资产），引用会变成 destroyed，
        // 这里兜一层，避免每帧抛 MissingReferenceException
        if (material == null || mesh == null)
        {
            _ready = false;
            return;
        }

        // 预览/反射相机不参与（否则探针烘焙时也会把草画一遍）
        if (cam.cameraType == CameraType.Preview || cam.cameraType == CameraType.Reflection) return;

        // ── 推参数 ──────────────────────────────────────────────────────────
        material.SetFloat(WindTimeId,
            Application.isPlaying ? Time.time : Time.realtimeSinceStartup);

        // 「1 米在屏幕上占多少像素」的换算系数，shader 用它把远处的草叶加宽，
        // 避免亚像素宽度的薄片每帧跳采样点（远处闪烁的主因）
        float pixelScale = 2f * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad)
                         / Mathf.Max(cam.pixelHeight, 1);
        material.SetFloat(PixelScaleId, pixelScale);

        if (linkHorizonToSky)
            material.SetColor(HorizonId, ResolveHorizonColor());
        else
            material.SetColor(HorizonId, horizonFallback);

        // 天光补光 + 雾色：这两样必须每帧跟着时段走，否则日落后草会黑成一片
        material.SetColor(AmbientTintId, ResolveAmbientTint());
        if (linkFogToSky)
            RenderSettings.fogColor = material.GetColor(HorizonId);

        // ── 剔除 + 交互采样（全部在 compute 里做）────────────────────────────
        // 不管开不开剔除，绑给材质的都是 compute 的输出缓冲：
        // 它带 c 通道（推力向量），而顶点阶段要做交互只能靠它。
        if (cullShader != null)
        {
            // 冻结时始终用 frozenCullCamera 计算视锥：
            // 这样 Scene 视图飞到哪看到都是「Game 相机那一片」
            Camera cullCam = (freezeCull && frozenCullCamera != null) ? frozenCullCamera : cam;
            DispatchCull(cullCam);
            material.SetBuffer(InstancesId, _visible);
        }

        // ── 提交（只对这个相机）─────────────────────────────────────────────
        Graphics.DrawMeshInstancedIndirect(
            mesh, 0, material, _bounds, _args, 0, null,
            castShadows ? ShadowCastingMode.On : ShadowCastingMode.Off,
            receiveShadows, gameObject.layer, cam);
    }

    /// <summary>
    /// 读回当前这一帧实际提交的实例数（会造成一次 GPU 同步，只在调试时调用）。
    /// </summary>
    public int ReadVisibleCount()
    {
        if (_args == null) return 0;
        var buf = new uint[5];
        _args.GetData(buf);
        return (int)buf[1];
    }

    /// <summary>
    /// 冻结剔除时，在 Scene 视图里画出被锁定的那个视锥，
    /// 这样把视角飞出去以后还能知道"这片草是按哪个视锥剔出来的"。
    /// </summary>
    void OnDrawGizmos()
    {
        if (!freezeCull || frozenCullCamera == null) return;

        var cam = frozenCullCamera;
        Gizmos.color = new Color(1f, 0.85f, 0.2f, 0.9f);
        Gizmos.matrix = Matrix4x4.TRS(cam.transform.position, cam.transform.rotation, Vector3.one);
        Gizmos.DrawFrustum(Vector3.zero, cam.fieldOfView, cam.farClipPlane, cam.nearClipPlane, cam.aspect);
        Gizmos.matrix = Matrix4x4.identity;
    }

    void DispatchCull(Camera cam)
    {
        // 1) 清零实例计数（单线程 kernel，比 CPU SetData 省一次上传）
        cullShader.SetBuffer(_kernelReset, "_Args", _args);
        cullShader.Dispatch(_kernelReset, 1, 1, 1);

        // 2) 传视锥平面 + 相机 + 距离参数
        var planes = GeometryUtility.CalculateFrustumPlanes(cam);
        var packed = new Vector4[6];
        for (int i = 0; i < 6; i++)
            packed[i] = new Vector4(planes[i].normal.x, planes[i].normal.y,
                                    planes[i].normal.z, planes[i].distance);

        cullShader.SetVectorArray("_FrustumPlanes", packed);
        cullShader.SetVector("_CameraPos", cam.transform.position);
        cullShader.SetFloat("_MaxDistance", maxDistance);
        cullShader.SetFloat("_DensityStart", densityStart);
        cullShader.SetFloat("_DensityEnd", densityEnd);
        cullShader.SetFloat("_FarKeep", farKeep);
        cullShader.SetInt("_InstanceCount", _total);
        cullShader.SetInt("_CullEnabled", enableCulling ? 1 : 0);

        // 交互推力场：由 GrassTrailSystem 维护，这里把它和范围传给 compute
        var trail = GrassTrailSystem.Instance;
        if (trail != null && trail.FieldTexture != null)
        {
            cullShader.SetTexture(_kernelCull, "_TrailTex", trail.FieldTexture);
            cullShader.SetVector("_GrassTrailRange",
                new Vector4(trail.worldCenter.x, trail.worldCenter.y, trail.worldSize, 0f));
        }
        else
        {
            // 没有交互系统时也要绑一张图，否则 compute 会报 "_TrailTex is not set"
            cullShader.SetTexture(_kernelCull, "_TrailTex", Texture2D.blackTexture);
            cullShader.SetVector("_GrassTrailRange", new Vector4(0f, 0f, 1f, 0f));
        }

        cullShader.SetBuffer(_kernelCull, "_Instances", _instances);
        cullShader.SetBuffer(_kernelCull, "_VisibleInstances", _visible);
        cullShader.SetBuffer(_kernelCull, "_Args", _args);

        int groups = Mathf.CeilToInt(_total / 256f);
        cullShader.Dispatch(_kernelCull, groups, 1, 1);
    }

    /// <summary>
    /// 远处融合色：优先取天空球材质的 _GroundColor（和天空严丝合缝），
    /// 再按环境光/太阳强度做亮度匹配，让白天亮、夜里暗。
    /// </summary>
    Color ResolveHorizonColor()
    {
        Color ground = horizonFallback;
        var sky = RenderSettings.skybox;
        if (sky != null && sky.HasProperty("_GroundColor"))
            ground = sky.GetColor("_GroundColor");

        Color amb = RenderSettings.ambientSkyColor;
        float sun = RenderSettings.sun != null ? Mathf.Clamp01(RenderSettings.sun.intensity) : 1f;
        float sunK = Mathf.Lerp(0.45f, 1.35f, sun);

        Color c = (ground * 0.75f + amb * 0.5f * horizonAmbientScale) * sunK;
        c.a = 1f;
        return c;
    }

    /// <summary>
    /// 天光补光色。
    /// 日落后主光强度会掉到 minSunIntensity（0.05），只靠 SH 的话草几乎全黑；
    /// 这里把「环境光 + 主光」合成一个补光色，再给一个夜间亮度地板，
    /// 保证月亮下草仍然能看到轮廓，而不是一片黑。
    /// </summary>
    Color ResolveAmbientTint()
    {
        Color amb = RenderSettings.ambientSkyColor * RenderSettings.ambientIntensity;

        var sun = RenderSettings.sun;
        float sunI = sun != null ? sun.intensity : 1f;
        Color sunC = sun != null ? sun.color : Color.white;

        Color c = amb * 1.15f + sunC * (sunI * 0.55f);

        // 亮度地板：夜里整体太暗就整体抬上来
        float lum = 0.2126f * c.r + 0.7152f * c.g + 0.0722f * c.b;
        if (lum < nightFloor)
            c *= nightFloor / Mathf.Max(lum, 1e-4f);

        c.a = 1f;
        return c * ambientTintScale;
    }
}
