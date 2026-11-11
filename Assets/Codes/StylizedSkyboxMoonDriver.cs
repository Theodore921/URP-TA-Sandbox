using UnityEngine;

/// <summary>
/// 风格化天空盒（Shader "Skybox/StylizedSkybox"）的月亮驱动。
///
/// 对应知乎《风格化天空球》代码块 #5：
///     Shader.SetGlobalMatrix("_MoonMatrix", m_moonTransform.worldToLocalMatrix);
///
/// 为什么要这个脚本：
///   Shader 里月亮不是靠"屏幕坐标"或"光照方向"画出来的，而是把天空球的顶点变换到
///   **月亮自身的局部空间**，再用这个局部坐标的 xy 去采样月亮贴图（代码块 #6）。
///   只有把月亮的变换矩阵喂给 Shader，月亮才会出现在正确的位置、并随相机旋转而不变形。
///
/// 关键约定 —— 月亮的 +Z（forward）就是它在天球上的位置：
///   Shader 用 moonLocal.xy 做 uv，所以 moonLocal = (0,0) 必须对应月亮中心。
///   本脚本传入的是"世界→月亮局部"的旋转，于是天空中与月亮 forward 同向的那一点
///   正好落在 uv (0.5, 0.5)，也就是贴图中心。
///   想让月亮出现在某个方向，把这个 Transform 的 forward 指向该方向即可，例如：
///       moonTransform.rotation = Quaternion.LookRotation(moonDirection);
///
/// 用法：
///   1. 场景里新建一个空物体（例如 "MoonLight"），挂上本脚本。
///   2. 把它的 forward 指向月亮方位（或直接和昼夜系统里的方向同步）。
///   3. 把天空盒材质拖到 Skybox Material 槽。
///   4. 材质面板上把 _MoonIntensity 交给本脚本驱动（默认已接管）。
///
/// 注意：Shader 里的 _MoonMatrix 是**全局变量**（不是材质属性），所以场景里同时只会有
/// 一个"当前月亮"。多相机/多天空盒需要不同月亮时，这版不适用。
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
[AddComponentMenu("Skybox/Stylized Skybox Moon Driver")]
public class StylizedSkyboxMoonDriver : MonoBehaviour
{
    [Header("月亮")]
    [Tooltip("代表月亮朝向的 Transform，其 forward(+Z) 指向月亮在天球上的位置。留空则用挂本脚本的物体自身。")]
    public Transform moon;

    [Header("月亮位置（以下两项是唯一控制入口）")]
    [Tooltip("月亮在天球上的世界方向，会自动归一化。勾选 Drive Rotation 时由脚本写入 Transform。")]
    public Vector3 moonDirection = Vector3.forward;

    [Tooltip("勾选：由脚本用 moonDirection 驱动 Transform 朝向（推荐，位置只由这里决定）。\n不勾选：直接读取 Transform 自己的 forward，适合在 Scene 视图里手动摆月亮。")]
    public bool driveRotation = false;

    [Header("目标材质（可选）")]
    [Tooltip("天空盒材质。只有在你希望脚本同时接管 _MoonIntensity 时才需要填。")]
    public Material skyboxMaterial;

    [Tooltip("勾选后由脚本把下面的强度写进材质。未接驱动时务必保持材质 _MoonIntensity = 0，否则零矩阵会让整个天空被月亮糊住。")]
    public bool driveMoonIntensity = true;

    [Tooltip("月亮不透明度。0 = 不显示，1 = 完全显示。")]
    [Range(0f, 1f)]
    public float moonIntensity = 1f;

    // 每一帧都查 ID 会浪费，缓存成静态只读
    static readonly int MoonMatrixId   = Shader.PropertyToID("_MoonMatrix");
    static readonly int MoonDirectionId = Shader.PropertyToID("_MoonDirection");
    static readonly int MoonIntensityId = Shader.PropertyToID("_MoonIntensity");

    /// <summary>实际用于计算的月亮 Transform。</summary>
    public Transform MoonTransform => moon != null ? moon : transform;

    void OnEnable()   { Push(); }
    void Update()     { Push(); }   // 月亮会动（昼夜循环），所以每帧推一次；代价只有一次 SetGlobalMatrix
    void OnValidate() { if (isActiveAndEnabled) Push(); }

    void OnDisable()
    {
        // 取消驱动时把强度归零。
        // 否则天空盒会继续用"最后一次写入的矩阵"，一旦月亮物体被删掉，
        // 残留的零矩阵会让 moonLocal.xy 恒为 0，整片天空都变成月亮贴图的中心像素。
        if (driveMoonIntensity && skyboxMaterial != null)
            skyboxMaterial.SetFloat(MoonIntensityId, 0f);
    }

    /// <summary>
    /// 把当前月亮状态推给 Shader。也可在外部手动调用（例如刚改完 transform 想立刻生效）。
    /// </summary>
    public void Push()
    {
        Transform t = MoonTransform;
        if (t == null) return;

        // ① 统一入口：先用 moonDirection 决定"月亮在天球上的方向"
        if (driveRotation)
        {
            Vector3 d = moonDirection.sqrMagnitude > 1e-6f ? moonDirection.normalized : Vector3.forward;

            // 方向与 up 近似平行时 LookRotation 会退化（想指向正头顶就会遇到），换一个参考轴
            Vector3 up = Mathf.Abs(Vector3.Dot(d, Vector3.up)) > 0.999f ? Vector3.forward : Vector3.up;
            Quaternion target = Quaternion.LookRotation(d, up);

            // 只在真的变了才写，否则编辑器里每帧赋值会把场景反复标脏
            if (Quaternion.Angle(t.rotation, target) > 0.01f)
                t.rotation = target;
        }

        // ② 两种方案共用这一个方向来源：
        //    矩阵方案用它的逆旋转，屏幕空间方案直接用方向做投影
        Vector3 moonDirWS = t.forward;

        // 原文用的是 t.worldToLocalMatrix。它会把 Transform 的缩放一并带进矩阵的 3x3 部分，
        // 而 Shader 侧 mul((float3x3)_MoonMatrix, pos) 会把缩放当作镜头畸变 —— 月亮被拉长。
        // 这里只取旋转部分：缩放为 1 时两者完全等价，缩放不为 1 时更安全。
        Shader.SetGlobalMatrix(MoonMatrixId, Matrix4x4.Rotate(Quaternion.Inverse(t.rotation)));
        Shader.SetGlobalVector(MoonDirectionId, moonDirWS);

        if (driveMoonIntensity && skyboxMaterial != null)
        {
            // 只在数值真的变了才写。
            // 每帧无脑 SetFloat 会让编辑器里的材质反复变脏，Unity 一直提示"有未保存的修改"。
            if (!Mathf.Approximately(skyboxMaterial.GetFloat(MoonIntensityId), moonIntensity))
                skyboxMaterial.SetFloat(MoonIntensityId, moonIntensity);
        }
    }
}
