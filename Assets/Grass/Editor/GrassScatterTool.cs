using UnityEditor;
using UnityEngine;

// ============================================================================
//  GrassScatterTool —— 撒点烘焙窗口（参数面板 + 调用 GrassBaker）
//
//  用法：Tools/草地/② 烘焙草场
//  逻辑都在 GrassBaker 里，这里只负责收集参数和显示预估。
// ============================================================================

public class GrassScatterTool : EditorWindow
{
    Terrain terrain;

    float densityNear = 160f;
    float densityFar = 28f;
    float radiusNear = 14f;
    float radiusFar = 40f;

    float scaleMin = 0.6f;
    float scaleMax = 1.15f;
    float clumpSize = 2.5f;
    float clumpYawSpread = 0.6f;

    int seed = 20261024;
    float sinkIntoGround = 0.03f;
    string assetPath = "Assets/Grass/Data/GrassField.asset";

    Vector2 scroll;

    [MenuItem("Tools/草地/② 烘焙草场", false, 3)]
    public static void Open()
    {
        var w = GetWindow<GrassScatterTool>(false, "草地烘焙", true);
        w.minSize = new Vector2(380, 560);
        w.Show();
    }

    /// <summary>用默认参数直接烘焙（不想开窗口时用这个，也方便脚本调用）。</summary>
    [MenuItem("Tools/草地/②b 用默认参数烘焙", false, 4)]
    public static void BakeDefault()
    {
        var t = Terrain.activeTerrain;
        if (t == null)
        {
            Debug.LogError("[草地] 场景里没有 Terrain，先执行 ③ 创建草地对象");
            return;
        }

        var data = GrassBaker.Bake(new GrassBakeParams
        {
            terrain = t,
            densityNear = 160f,
            densityFar = 28f,
            radiusNear = 14f,
            radiusFar = 40f,
            scaleMin = 0.6f,
            scaleMax = 1.15f,
            clumpSize = 2.5f,
            clumpYawSpread = 0.6f,
            seed = 20261024,
            sinkIntoGround = 0.03f,
            assetPath = "Assets/Grass/Data/GrassField.asset"
        });
        if (data != null) Selection.activeObject = data;
    }

    void OnEnable()
    {
        if (terrain == null) terrain = Terrain.activeTerrain;
        LoadPrefs();
    }

    void OnDisable() { SavePrefs(); }

    // 窗口参数用 EditorPrefs 持久化：否则每次关掉再打开都会回到默认值，
    // 调好的密度/分簇参数一重开就没了。
    void LoadPrefs()
    {
        densityNear     = EditorPrefs.GetFloat("GrassScatter.densityNear", densityNear);
        densityFar      = EditorPrefs.GetFloat("GrassScatter.densityFar", densityFar);
        radiusNear      = EditorPrefs.GetFloat("GrassScatter.radiusNear", radiusNear);
        radiusFar       = EditorPrefs.GetFloat("GrassScatter.radiusFar", radiusFar);
        scaleMin        = EditorPrefs.GetFloat("GrassScatter.scaleMin", scaleMin);
        scaleMax        = EditorPrefs.GetFloat("GrassScatter.scaleMax", scaleMax);
        clumpSize       = EditorPrefs.GetFloat("GrassScatter.clumpSize", clumpSize);
        clumpYawSpread  = EditorPrefs.GetFloat("GrassScatter.clumpYawSpread", clumpYawSpread);
        sinkIntoGround  = EditorPrefs.GetFloat("GrassScatter.sink", sinkIntoGround);
        seed            = EditorPrefs.GetInt("GrassScatter.seed", seed);
        assetPath       = EditorPrefs.GetString("GrassScatter.path", assetPath);
    }

    void SavePrefs()
    {
        EditorPrefs.SetFloat("GrassScatter.densityNear", densityNear);
        EditorPrefs.SetFloat("GrassScatter.densityFar", densityFar);
        EditorPrefs.SetFloat("GrassScatter.radiusNear", radiusNear);
        EditorPrefs.SetFloat("GrassScatter.radiusFar", radiusFar);
        EditorPrefs.SetFloat("GrassScatter.scaleMin", scaleMin);
        EditorPrefs.SetFloat("GrassScatter.scaleMax", scaleMax);
        EditorPrefs.SetFloat("GrassScatter.clumpSize", clumpSize);
        EditorPrefs.SetFloat("GrassScatter.clumpYawSpread", clumpYawSpread);
        EditorPrefs.SetFloat("GrassScatter.sink", sinkIntoGround);
        EditorPrefs.SetInt("GrassScatter.seed", seed);
        EditorPrefs.SetString("GrassScatter.path", assetPath);
    }

    GrassBakeParams BuildParams() => new GrassBakeParams
    {
        terrain = terrain,
        densityNear = densityNear,
        densityFar = densityFar,
        radiusNear = radiusNear,
        radiusFar = radiusFar,
        scaleMin = scaleMin,
        scaleMax = scaleMax,
        clumpSize = clumpSize,
        clumpYawSpread = clumpYawSpread,
        seed = seed,
        sinkIntoGround = sinkIntoGround,
        assetPath = assetPath
    };

    void OnGUI()
    {
        scroll = EditorGUILayout.BeginScrollView(scroll);

        EditorGUILayout.HelpBox(
            "按密度在地形上撒点并烘焙成 GrassFieldData。\n" +
            "密度用「离中心距离」做径向衰减：近处密、远处稀，总量直接决定性能。",
            MessageType.Info);

        terrain = (Terrain)EditorGUILayout.ObjectField("地形", terrain, typeof(Terrain), true);
        if (terrain == null)
        {
            EditorGUILayout.HelpBox("场景里没有 Terrain。先执行 Tools/草地/③ 在当前场景创建草地对象。",
                                    MessageType.Warning);
            EditorGUILayout.EndScrollView();
            return;
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("密度", EditorStyles.boldLabel);
        densityNear = EditorGUILayout.FloatField("近处密度（株/m²）", densityNear);
        densityFar = EditorGUILayout.FloatField("远处密度（株/m²）", densityFar);
        radiusNear = EditorGUILayout.FloatField("近处半径（米）", radiusNear);
        radiusFar = EditorGUILayout.FloatField("远处半径（米）", radiusFar);

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("随机与分簇", EditorStyles.boldLabel);
        clumpSize = EditorGUILayout.FloatField("簇尺寸（米）", clumpSize);
        clumpYawSpread = EditorGUILayout.Slider("簇内朝向离散", clumpYawSpread, 0f, 3.14f);
        scaleMin = EditorGUILayout.FloatField("最小缩放", scaleMin);
        scaleMax = EditorGUILayout.FloatField("最大缩放", scaleMax);

        EditorGUILayout.Space();
        seed = EditorGUILayout.IntField("随机种子", seed);
        sinkIntoGround = EditorGUILayout.FloatField("陷入地面（米）", sinkIntoGround);
        assetPath = EditorGUILayout.TextField("输出资产", assetPath);

        EditorGUILayout.Space();
        float estimate = GrassBaker.EstimateCount(BuildParams());
        EditorGUILayout.HelpBox($"预计撒点：约 {estimate:N0} 株", MessageType.None);

        EditorGUILayout.Space();
        if (GUILayout.Button("开始烘焙", GUILayout.Height(36)))
        {
            var data = GrassBaker.Bake(BuildParams());
            if (data != null) Selection.activeObject = data;
        }

        EditorGUILayout.EndScrollView();
    }
}
