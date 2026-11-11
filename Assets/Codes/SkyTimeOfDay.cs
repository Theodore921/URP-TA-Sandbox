using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// 天空球昼夜时间驱动。
///
/// 一个 timeOfDay(0~24 小时) 同时驱动四样东西：
///   1. 太阳方向      —— 旋转 Directional Light，天空球里的太阳会自动跟随
///                        （shader 的 GetSunDirection() 读的是 URP 的 _MainLightPosition）
///   2. 月亮方向/强度 —— 交给 StylizedSkyboxMoonDriver（月亮与太阳大致相对）
///   3. 太阳光         —— 强度与颜色随仰角变化（低角度偏橙红）
///   4. 环境光 / 曝光 —— 环境光切到 Trilight 手工驱动（Skybox 模式的环境光是静态烘焙的，
///                        运行时太阳一动它不会跟着变）
///
/// 时间轴约定：
///   0:00 → 太阳在天底(仰角 -90°)
///   6:00 → 日出(仰角 0°)
///  12:00 → 正午(仰角 +90°，再被 sunTilt 压低)
///  18:00 → 日落(仰角 0°，方位与日出相反)
///
/// 注意：本脚本会改写 RenderSettings.ambientMode。取消 driveAmbient 后，
///       环境光模式不会自动还原，需要手动在 Lighting 面板改回 Skybox。
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
[AddComponentMenu("Skybox/Sky Time Of Day")]
public class SkyTimeOfDay : MonoBehaviour
{
    [Header("时间")]
    [Tooltip("当前时间（小时）。0 = 午夜，6 = 日出，12 = 正午，18 = 日落")]
    [Range(0f, 24f)] public float timeOfDay = 10f;

    [Tooltip("勾选后自动推进时间（仅运行时生效）")]
    public bool autoAdvance = false;

    [Tooltip("一个完整昼夜循环对应的真实秒数")]
    [Min(1f)] public float dayLengthSeconds = 120f;

    [Header("天体")]
    [Tooltip("平行光的 Transform，太阳方向由它决定")]
    public Transform sun;
    [Tooltip("平行光组件，用于驱动强度与颜色")]
    public Light sunLight;

    [Tooltip("太阳轨道倾角：>0 时正午太阳不会正对头顶")]
    [Range(0f, 60f)] public float sunTilt = 25f;

    [Tooltip("日出方位的基准角度（绕 Y 轴，度）")]
    public float sunAzimuth = 180f;

    [Tooltip("可选：月亮驱动脚本，会自动同步月亮方向与强度")]
    public StylizedSkyboxMoonDriver moonDriver;

    [Header("太阳光")]
    public float maxSunIntensity = 1.2f;
    [Tooltip("夜间保底强度，不能为 0。URP 在强度为 0 时会认为没有主光，"
           + "把 _MainLightPosition 重置为默认 (0,0,1)，天空球读到的太阳方向就会错成永远黄昏。")]
    [Min(0.001f)] public float minSunIntensity = 0.05f;
    [Tooltip("太阳较高时的光色")]
    public Color sunColorDay = new Color(1f, 0.96f, 0.84f, 1f);
    [Tooltip("太阳贴近地平线时的光色")]
    public Color sunColorSunset = new Color(1f, 0.55f, 0.28f, 1f);
    [Tooltip("夜间光色（偏冷的月光）")]
    public Color sunColorNight = new Color(0.45f, 0.58f, 0.95f, 1f);

    [Header("环境光")]
    [Tooltip("启用后会切换 ambientMode 为 Trilight 并手工驱动三色")]
    public bool driveAmbient = true;
    public Color ambientSkyDay = new Color(0.42f, 0.55f, 0.78f, 1f);
    public Color ambientSkySunset = new Color(0.55f, 0.38f, 0.35f, 1f);
    public Color ambientSkyNight = new Color(0.05f, 0.07f, 0.13f, 1f);
    [Tooltip("环境光整体倍数（同时作用于三色）")]
    public float ambientIntensity = 1f;

    [Header("天空材质")]
    [Tooltip("天空盒材质，用于驱动 _Exposure")]
    public Material skyMaterial;
    public float exposureDay = 1f;
    public float exposureNight = 0.35f;

    // 只在数值变化时才写入，避免编辑器里每帧把场景标脏
    float _lastTime = float.NaN;
    bool _lastAuto;

    static readonly int ExposureId = Shader.PropertyToID("_Exposure");

    void OnEnable()  { Push(force: true); }
    void OnValidate() { _lastTime = float.NaN; Push(force: true); }

    void Update()
    {
        if (autoAdvance && Application.isPlaying)
        {
            timeOfDay += (24f / Mathf.Max(1f, dayLengthSeconds)) * Time.deltaTime;
            if (timeOfDay >= 24f) timeOfDay -= 24f;
        }

        // 时间没动就不重复写
        if (!Mathf.Approximately(_lastTime, timeOfDay) || _lastAuto != autoAdvance)
            Push(force: true);
    }

    /// <summary>把当前时间应用到太阳/月亮/光照/环境光。</summary>
    public void Push(bool force = false)
    {
        _lastTime = timeOfDay;
        _lastAuto = autoAdvance;

        // ── ① 太阳方向 ────────────────────────────────────────────────
        //   elevation：0:00 = -90°(天底) → 6:00 = 0°(地平线) → 12:00 = +90°(天顶) → 18:00 = 180°(另一侧地平线)
        float elevationDeg = (timeOfDay / 24f) * 360f - 90f;
        // Unity 中绕 X 正角度是"向下俯"，所以仰角要取负号，否则整条轨道上下颠倒
        Vector3 toSun = Quaternion.Euler(-elevationDeg, sunAzimuth, 0f) * Vector3.forward;
        toSun = Quaternion.Euler(0f, 0f, -sunTilt) * toSun;   // 整体倾斜，压低正午高度
        toSun.Normalize();

        if (sun != null)
        {
            // 平行光的 forward 是"照射方向"，所以指向上方要取反
            Vector3 lightDir = -toSun;
            Vector3 up = Mathf.Abs(Vector3.Dot(lightDir, Vector3.up)) > 0.999f
                       ? Vector3.forward : Vector3.up;
            sun.rotation = Quaternion.LookRotation(lightDir, up);
        }

        // ── ② 时段权重 ────────────────────────────────────────────────
        float dayW   = Mathf.Clamp01(toSun.y * 3f);
        float nightW = Mathf.Clamp01(-toSun.y * 3f);
        float duskW  = Mathf.Clamp01(1f - dayW - nightW);

        // ── ③ 太阳光强度/颜色 ─────────────────────────────────────────
        if (sunLight != null)
        {
            float up01 = Mathf.Clamp01(toSun.y);
            // 开方让日出日落附近的光衰变更柔和
            // ⚠ 必须留一个正的保底强度：强度为 0 时 URP 会认为没有主光，
            //    _MainLightPosition 会被重置为 (0,0,1)，天空球的太阳方向随之错乱
            sunLight.intensity = Mathf.Max(minSunIntensity, maxSunIntensity * Mathf.Sqrt(up01));

            Color c = Color.Lerp(sunColorSunset, sunColorDay, dayW);
            c = Color.Lerp(c, sunColorNight, nightW);
            sunLight.color = c;
        }

        // ── ④ 环境光 ─────────────────────────────────────────────────
        if (driveAmbient)
        {
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientIntensity = ambientIntensity;

            Color sky = Color.Lerp(ambientSkyNight, ambientSkySunset, Mathf.Clamp01(duskW + dayW));
            sky = Color.Lerp(sky, ambientSkyDay, dayW);

            RenderSettings.ambientSkyColor     = sky;
            RenderSettings.ambientEquatorColor = sky * 0.75f;
            RenderSettings.ambientGroundColor  = sky * 0.35f;
        }

        // ── ⑤ 曝光 ───────────────────────────────────────────────────
        if (skyMaterial != null && skyMaterial.HasProperty(ExposureId))
            skyMaterial.SetFloat(ExposureId, Mathf.Lerp(exposureNight, exposureDay, dayW));

        // ── ⑥ 月亮 ───────────────────────────────────────────────────
        if (moonDriver != null)
        {
            moonDriver.driveRotation = true;
            moonDriver.driveMoonIntensity = true;      // 否则 Push() 不会写 _MoonIntensity
            moonDriver.moonDirection = -toSun;          // 与太阳大致相对
            moonDriver.moonIntensity = nightW;          // 白天不显示，夜晚淡入
            moonDriver.Push();
        }
    }
}
