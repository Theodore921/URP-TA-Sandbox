using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// ============================================================================
//  GrassRoadTool —— 道路绘制工具
//
//  用法：
//    1. 菜单 Tools/草地/⑤ 道路绘制工具
//    2. 勾上「点选模式」，在 Scene 视图里沿路径点几下（左键加点，右键结束）
//    3. 调路宽 / 边缘噪声
//    4. 点「重建掩码」→ 生成 RoadMask 并自动挂到地面材质上
//    5. 重新烘焙草场（②）让路面长不出草
//
//  坐标约定与草地密度图一致：uv = (worldXZ - worldCenter) / worldSize + 0.5
// ============================================================================

public class GrassRoadTool : EditorWindow
{
    const string MaskPath = "Assets/Grass/Data/RoadMask.asset";

    GrassRoadPath path;
    bool pickMode;
    Vector2 scroll;

    [MenuItem("Tools/草地/⑤ 道路绘制工具", false, 6)]
    public static void Open()
    {
        var w = GetWindow<GrassRoadTool>(false, "道路绘制", true);
        w.minSize = new Vector2(360, 480);
        w.Show();
    }

    void OnEnable()
    {
        FindOrCreatePath();
        SceneView.duringSceneGui += OnSceneGUI;
    }

    void OnDisable()
    {
        SceneView.duringSceneGui -= OnSceneGUI;
    }

    void FindOrCreatePath()
    {
        if (path != null) return;

        path = Object.FindObjectOfType<GrassRoadPath>();
        if (path == null)
        {
            var go = GameObject.Find("GrassRoad") ?? new GameObject("GrassRoad");
            path = go.GetComponent<GrassRoadPath>() ?? go.AddComponent<GrassRoadPath>();

            var terrain = Terrain.activeTerrain;
            if (terrain != null)
            {
                Vector3 c = terrain.transform.position + terrain.terrainData.size * 0.5f;
                path.worldCenter = new Vector2(c.x, c.z);
                path.worldSize = Mathf.Min(terrain.terrainData.size.x, terrain.terrainData.size.z);
            }
            EditorSceneManager.MarkSceneDirty(go.scene);
        }
    }

    void OnGUI()
    {
        scroll = EditorGUILayout.BeginScrollView(scroll);

        EditorGUILayout.HelpBox(
            "在 Scene 视图里点出路点（左键加点，右键结束）。\n" +
            "点完后按「重建掩码」，地面材质会自动接上；\n" +
            "再重新烘焙草场（Tools/草地/② 烘焙草场）路面就不会长草了。",
            MessageType.Info);

        path = (GrassRoadPath)EditorGUILayout.ObjectField("道路对象", path, typeof(GrassRoadPath), true);
        if (path == null) FindOrCreatePath();

        if (path == null)
        {
            EditorGUILayout.HelpBox("场景里找不到 GrassRoadPath", MessageType.Warning);
            EditorGUILayout.EndScrollView();
            return;
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("路径", EditorStyles.boldLabel);
        EditorGUILayout.LabelField("路点数", path.points.Count.ToString());

        pickMode = EditorGUILayout.ToggleLeft("点选模式（在 Scene 视图里点击加路点）", pickMode);
        if (pickMode)
            EditorGUILayout.HelpBox("左键：加路点    右键：结束点选", MessageType.None);

        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("撤销最后一个点"))
            {
                if (path.points.Count > 0) path.points.RemoveAt(path.points.Count - 1);
                MarkDirty();
            }
            if (GUILayout.Button("清空"))
            {
                path.points.Clear();
                MarkDirty();
            }
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("形状", EditorStyles.boldLabel);
        EditorGUI.BeginChangeCheck();
        path.width = EditorGUILayout.Slider("路宽（米）", path.width, 0.3f, 12f);
        path.edgeNoise = EditorGUILayout.Slider("边缘噪声", path.edgeNoise, 0f, 1f);
        path.edgeNoiseScale = EditorGUILayout.Slider("噪声频率", path.edgeNoiseScale, 0.05f, 2f);
        path.softness = EditorGUILayout.Slider("边缘柔和度", path.softness, 0.02f, 1f);
        if (EditorGUI.EndChangeCheck()) MarkDirty();

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("草地剔除", EditorStyles.boldLabel);
        EditorGUI.BeginChangeCheck();
        path.grassCutThreshold = EditorGUILayout.Slider("剔除阈值", path.grassCutThreshold, 0.05f, 0.95f);
        path.grassEdgeJitter = EditorGUILayout.Slider("边界抖动", path.grassEdgeJitter, 0f, 0.5f);
        if (EditorGUI.EndChangeCheck()) MarkDirty();

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("掩码", EditorStyles.boldLabel);
        path.resolution = EditorGUILayout.IntPopup("分辨率", path.resolution,
            new[] { "512", "1024", "2048" }, new[] { 512, 1024, 2048 });
        EditorGUILayout.Vector2Field("世界中心", path.worldCenter);
        path.worldSize = EditorGUILayout.FloatField("世界尺寸", path.worldSize);
        EditorGUILayout.ObjectField("当前掩码", path.mask, typeof(Texture2D), false);

        EditorGUILayout.Space();
        using (new EditorGUI.DisabledScope(path.points.Count < 2))
        {
            if (GUILayout.Button("重建掩码（并挂到地面材质）", GUILayout.Height(34)))
                Rebuild();
        }

        EditorGUILayout.EndScrollView();
    }

    void Rebuild()
    {
        if (!GrassRoadRasterizer.Rebuild(path, MaskPath)) return;

        // 把掩码和范围推给地面材质
        var terrain = Terrain.activeTerrain;
        var mat = terrain != null ? terrain.materialTemplate : null;
        if (mat != null && mat.HasProperty("_RoadMask"))
        {
            mat.SetTexture("_RoadMask", path.mask);
            mat.SetVector("_RoadRange",
                new Vector4(path.worldCenter.x, path.worldCenter.y, path.worldSize, 0f));
            EditorUtility.SetDirty(mat);
            Debug.Log("[道路] 掩码已挂到地形材质");
        }
        else
        {
            Debug.LogWarning("[道路] 地形材质不是 Grass/Ground，掩码没有挂上去");
        }

        AssetDatabase.SaveAssets();
        SceneView.RepaintAll();
    }

    void MarkDirty()
    {
        if (path == null) return;
        EditorUtility.SetDirty(path);
        EditorSceneManager.MarkSceneDirty(path.gameObject.scene);
        SceneView.RepaintAll();
    }

    // ── Scene 视图交互 ─────────────────────────────────────────────────────
    void OnSceneGUI(SceneView sceneView)
    {
        if (!pickMode || path == null) return;

        int controlId = GUIUtility.GetControlID(FocusType.Passive);
        HandleUtility.AddDefaultControl(controlId);

        Event e = Event.current;

        if (e.type == EventType.MouseDown && e.button == 0)
        {
            Vector3 pos = PickGround(e.mousePosition);
            path.points.Add(pos);
            MarkDirty();
            e.Use();
        }
        else if (e.type == EventType.MouseDown && e.button == 1)
        {
            pickMode = false;
            e.Use();
            Repaint();
        }
    }

    /// <summary>视线与地面求交（优先命中碰撞体，没有就退回 y=0 平面）。</summary>
    static Vector3 PickGround(Vector2 guiPos)
    {
        Ray ray = HandleUtility.GUIPointToWorldRay(guiPos);

        if (Physics.Raycast(ray, out RaycastHit hit, 5000f))
            return hit.point;

        // 兜底：y = 0 平面
        if (Mathf.Abs(ray.direction.y) > 1e-4f)
        {
            float t = -ray.origin.y / ray.direction.y;
            if (t > 0f) return ray.origin + ray.direction * t;
        }
        return ray.origin + ray.direction * 20f;
    }
}
