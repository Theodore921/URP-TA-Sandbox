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

    Terrain terrain;
    GrassRoadPath path;
    bool pickMode;
    bool paintMode;
    bool eraseMode;
    bool strokeActive;
    float brushRadius = 1.3f;
    float brushStrength = 0.6f;
    float brushSoftness = 0.4f;
    Vector3 previousPoint;
    Color32[] workingPixels;
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
        terrain = Terrain.activeTerrain;
        FindOrCreatePath();
        SceneView.duringSceneGui += OnSceneGUI;
        Undo.undoRedoPerformed += OnUndoRedo;
    }

    void OnDisable()
    {
        SceneView.duringSceneGui -= OnSceneGUI;
        Undo.undoRedoPerformed -= OnUndoRedo;
        EndStroke();
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
                Vector3 scale = terrain.transform.lossyScale;
                Vector3 c = terrain.transform.position + Vector3.Scale(terrain.terrainData.size, scale) * 0.5f;
                path.worldCenter = new Vector2(c.x, c.z);
                path.worldSize = Mathf.Max(terrain.terrainData.size.x * Mathf.Abs(scale.x),
                                           terrain.terrainData.size.z * Mathf.Abs(scale.z));
            }
            EditorSceneManager.MarkSceneDirty(go.scene);
        }
    }

    void OnGUI()
    {
        scroll = EditorGUILayout.BeginScrollView(scroll);

        EditorGUILayout.HelpBox(
            "推荐直接在 Terrain 上拖动绘制道路；也可以继续使用下方路点样条编辑。\n" +
            "绘制完成后会更新地面材质道路外观，重新烘焙草场（②）后道路上不会长草。",
            MessageType.Info);

        path = (GrassRoadPath)EditorGUILayout.ObjectField("道路对象", path, typeof(GrassRoadPath), true);
        if (path == null) FindOrCreatePath();

        if (path == null)
        {
            EditorGUILayout.HelpBox("场景里找不到 GrassRoadPath", MessageType.Warning);
            EditorGUILayout.EndScrollView();
            return;
        }

        terrain = (Terrain)EditorGUILayout.ObjectField("绘制地形", terrain, typeof(Terrain), true);
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("Terrain 笔刷", EditorStyles.boldLabel);
        brushRadius = EditorGUILayout.Slider("笔刷半径（米）", brushRadius, 0.2f, 20f);
        brushStrength = EditorGUILayout.Slider("笔刷强度", brushStrength, 0.05f, 1f);
        brushSoftness = EditorGUILayout.Slider("边缘柔和度", brushSoftness, 0f, 1f);
        paintMode = EditorGUILayout.ToggleLeft("启用 Scene 视图笔刷", paintMode);
        eraseMode = GUILayout.Toolbar(eraseMode ? 1 : 0, new[] { "绘制道路", "擦除道路" }) == 1;
        if (paintMode)
            EditorGUILayout.HelpBox("在 Scene 视图中启用笔刷后按住左键拖动；Esc 退出绘制模式。", MessageType.None);

        if (path.mask == null)
        {
            if (GUILayout.Button("创建空白道路掩码"))
                CreateRoadMask();
        }
        else
        {
            EditorGUILayout.ObjectField("当前道路掩码", path.mask, typeof(Texture2D), false);
            if (!path.mask.isReadable)
                EditorGUILayout.HelpBox("当前道路掩码不可读写，无法直接绘制。", MessageType.Error);
            if (GUILayout.Button("全部清空道路掩码"))
            {
                if (EditorUtility.DisplayDialog("清空道路", "确定清除道路掩码？该操作可通过 Undo 撤销。", "清空", "取消"))
                    ClearRoadMask();
            }
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("路点样条（可选）", EditorStyles.boldLabel);
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

        EditorGUILayout.Space();
        using (new EditorGUI.DisabledScope(path.points.Count < 2))
        {
            if (GUILayout.Button("从样条重建掩码（会覆盖笔刷绘制）", GUILayout.Height(34)) &&
                EditorUtility.DisplayDialog("重建道路掩码",
                    "从路点样条重建会覆盖当前道路掩码和笔刷绘制内容。继续吗？", "重建", "取消"))
                    Rebuild();
        }

        EditorGUILayout.EndScrollView();
    }

    void Rebuild()
    {
        if (!GrassRoadRasterizer.Rebuild(path, MaskPath)) return;

        ApplyMaskToTerrain();
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
        if (paintMode || eraseMode)
        {
            HandlePaintSceneGUI();
            if (Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Escape)
            {
                paintMode = false;
                eraseMode = false;
                Event.current.Use();
                Repaint();
            }
            return;
        }

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

    void CreateRoadMask()
    {
        if (path == null) return;
        if (terrain != null)
            AlignMaskToTerrain();

        int resolution = Mathf.Clamp(path.resolution, 64, 4096);
        var mask = new Texture2D(resolution, resolution, TextureFormat.RGBA32, false, true)
        {
            name = "RoadMask",
            filterMode = FilterMode.Bilinear,
            wrapMode = TextureWrapMode.Clamp
        };
        var pixels = new Color32[resolution * resolution];
        for (int i = 0; i < pixels.Length; i++)
            pixels[i] = new Color32(0, 0, 0, 255);
        mask.SetPixels32(pixels);
        mask.Apply(false);

        if (!AssetDatabase.IsValidFolder("Assets/Grass/Data"))
            AssetDatabase.CreateFolder("Assets/Grass", "Data");
        string assetPath = AssetDatabase.GenerateUniqueAssetPath(MaskPath);
        AssetDatabase.CreateAsset(mask, assetPath);
        Undo.RecordObject(path, "Create Road Mask");
        path.mask = mask;
        EditorUtility.SetDirty(path);
        MarkDirty();
        AssetDatabase.SaveAssets();
        ApplyMaskToTerrain();
    }

    void AlignMaskToTerrain()
    {
        if (terrain == null || terrain.terrainData == null || path == null) return;
        Vector3 scale = terrain.transform.lossyScale;
        Vector3 size = Vector3.Scale(terrain.terrainData.size, scale);
        Vector3 center = terrain.transform.position + size * 0.5f;
        path.worldCenter = new Vector2(center.x, center.z);
        path.worldSize = Mathf.Max(Mathf.Abs(size.x), Mathf.Abs(size.z));
        MarkDirty();
    }

    void ClearRoadMask()
    {
        if (path.mask == null || !path.mask.isReadable) return;
        Undo.RegisterCompleteObjectUndo(path.mask, "Clear Road Mask");
        var pixels = new Color32[path.mask.width * path.mask.height];
        for (int i = 0; i < pixels.Length; i++)
            pixels[i] = new Color32(0, 0, 0, 255);
        path.mask.SetPixels32(pixels);
        path.mask.Apply(false);
        EditorUtility.SetDirty(path.mask);
        AssetDatabase.SaveAssets();
        ApplyMaskToTerrain();
    }

    void HandlePaintSceneGUI()
    {
        if (path == null || path.mask == null || !path.mask.isReadable || terrain == null)
            return;
        var terrainCollider = terrain.GetComponent<TerrainCollider>();
        if (terrainCollider == null) return;

        Event current = Event.current;
        Ray ray = HandleUtility.GUIPointToWorldRay(current.mousePosition);
        bool hitTerrain = terrainCollider.Raycast(ray, out RaycastHit hit, 10000f);
        int controlId = GUIUtility.GetControlID(FocusType.Passive);
        if (current.type == EventType.Layout && hitTerrain)
            HandleUtility.AddDefaultControl(controlId);

        if (hitTerrain)
        {
            Handles.color = eraseMode
                ? new Color(1f, 0.25f, 0.2f, 0.85f)
                : new Color(1f, 0.75f, 0.15f, 0.9f);
            Handles.DrawWireDisc(hit.point, hit.normal, brushRadius);
        }

        if (current.type == EventType.MouseDown && current.button == 0 && hitTerrain)
        {
            GUIUtility.hotControl = controlId;
            StartStroke(hit.point);
            current.Use();
        }
        else if (current.type == EventType.MouseDrag && strokeActive &&
                 GUIUtility.hotControl == controlId && hitTerrain)
        {
            PaintSegment(previousPoint, hit.point);
            previousPoint = hit.point;
            current.Use();
        }
        else if (current.type == EventType.MouseUp && strokeActive &&
                 GUIUtility.hotControl == controlId)
        {
            EndStroke();
            GUIUtility.hotControl = 0;
            current.Use();
        }
    }

    void StartStroke(Vector3 point)
    {
        Undo.RegisterCompleteObjectUndo(path.mask, eraseMode ? "Erase Road" : "Paint Road");
        workingPixels = path.mask.GetPixels32();
        strokeActive = true;
        previousPoint = point;
        Stamp(point);
        CommitPixels();
    }

    void PaintSegment(Vector3 from, Vector3 to)
    {
        float distance = Vector2.Distance(new Vector2(from.x, from.z), new Vector2(to.x, to.z));
        float spacing = Mathf.Max(0.1f, brushRadius * 0.2f);
        int steps = Mathf.Max(1, Mathf.CeilToInt(distance / spacing));
        for (int i = 1; i <= steps; i++)
            Stamp(Vector3.Lerp(from, to, i / (float)steps));
        CommitPixels();
    }

    void Stamp(Vector3 worldPosition)
    {
        Vector2 uv = path.WorldToMaskUV(new Vector2(worldPosition.x, worldPosition.z));
        if (uv.x < 0f || uv.x > 1f || uv.y < 0f || uv.y > 1f) return;

        Texture2D mask = path.mask;
        float centerX = uv.x * (mask.width - 1);
        float centerY = uv.y * (mask.height - 1);
        float pixelRadius = brushRadius / Mathf.Max(path.worldSize, 0.001f) * mask.width;
        int x0 = Mathf.Clamp(Mathf.FloorToInt(centerX - pixelRadius), 0, mask.width - 1);
        int x1 = Mathf.Clamp(Mathf.CeilToInt(centerX + pixelRadius), 0, mask.width - 1);
        int y0 = Mathf.Clamp(Mathf.FloorToInt(centerY - pixelRadius), 0, mask.height - 1);
        int y1 = Mathf.Clamp(Mathf.CeilToInt(centerY + pixelRadius), 0, mask.height - 1);
        float softness = Mathf.Clamp01(brushSoftness);

        for (int y = y0; y <= y1; y++)
        {
            float dy = ((y + 0.5f) / mask.height - uv.y) * path.worldSize;
            for (int x = x0; x <= x1; x++)
            {
                float dx = ((x + 0.5f) / mask.width - uv.x) * path.worldSize;
                float normalizedDistance = Mathf.Sqrt(dx * dx + dy * dy) /
                                           Mathf.Max(brushRadius, 0.001f);
                if (normalizedDistance >= 1f) continue;

                float falloff = softness <= 0.001f
                    ? 1f
                    : Mathf.SmoothStep(0f, 1f,
                        Mathf.Clamp01((1f - normalizedDistance) / softness));
                float blend = Mathf.Clamp01(brushStrength * falloff);
                int index = y * mask.width + x;
                float oldValue = workingPixels[index].r / 255f;
                float newValue = eraseMode
                    ? oldValue * (1f - blend)
                    : Mathf.Lerp(oldValue, 1f, blend);
                byte value = (byte)Mathf.RoundToInt(newValue * 255f);
                workingPixels[index] = new Color32(value, value, value, 255);
            }
        }
    }

    void CommitPixels()
    {
        path.mask.SetPixels32(workingPixels);
        path.mask.Apply(false);
        EditorUtility.SetDirty(path.mask);
        SceneView.RepaintAll();
    }

    void EndStroke()
    {
        if (!strokeActive) return;
        strokeActive = false;
        workingPixels = null;
        AssetDatabase.SaveAssets();
        ApplyMaskToTerrain();
    }

    void ApplyMaskToTerrain()
    {
        var mat = terrain != null ? terrain.materialTemplate : null;
        if (mat == null || !mat.HasProperty("_RoadMask"))
        {
            Debug.LogWarning("[道路] Terrain 材质不是 Grass/Ground，道路掩码未挂到材质上");
            return;
        }

        mat.SetTexture("_RoadMask", path.mask);
        mat.SetVector("_RoadRange",
            new Vector4(path.worldCenter.x, path.worldCenter.y, path.worldSize, 0f));
        EditorUtility.SetDirty(mat);
        AssetDatabase.SaveAssets();
        SceneView.RepaintAll();
    }

    void OnUndoRedo()
    {
        workingPixels = null;
        if (path != null && path.mask != null)
            ApplyMaskToTerrain();
        SceneView.RepaintAll();
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
