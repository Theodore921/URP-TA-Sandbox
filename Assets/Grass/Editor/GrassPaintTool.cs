using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public class GrassPaintTool : EditorWindow
{
    const int MaskResolution = 512;

    Terrain terrain;
    GrassPaintMask paintMask;
    float brushRadius = 4f;
    float brushStrength = 0.35f;
    float edgeSoftness = 0.5f;
    bool eraseMode;
    bool paintMode;
    bool strokeActive;
    Vector3 previousPoint;
    Color32[] workingPixels;
    Vector2 scroll;

    [MenuItem("Tools/草地/绘制草地分布", false, 7)]
    public static void Open()
    {
        var window = GetWindow<GrassPaintTool>(false, "草地分布绘制", true);
        window.minSize = new Vector2(330, 440);
        window.Show();
    }

    void OnEnable()
    {
        terrain = Terrain.activeTerrain;
        RefreshPaintMask();
        SceneView.duringSceneGui += OnSceneGUI;
        Undo.undoRedoPerformed += OnUndoRedo;
    }

    void OnDisable()
    {
        SceneView.duringSceneGui -= OnSceneGUI;
        Undo.undoRedoPerformed -= OnUndoRedo;
        EndStroke();
        if (paintMask != null && paintMask.distributionMask != null)
            AssetDatabase.SaveAssets();
    }

    void OnGUI()
    {
        scroll = EditorGUILayout.BeginScrollView(scroll);
        EditorGUILayout.HelpBox(
            "先为 Terrain 创建草地分布图，再打开绘制模式，在 Scene 视图中左键拖动涂抹。白色区域按现有密度生成草，黑色区域不生成草；同步 Terrain 图层时也会应用当前草场的距离衰减、道路、坡度和边缘过滤。",
            MessageType.Info);

        EditorGUI.BeginChangeCheck();
        terrain = (Terrain)EditorGUILayout.ObjectField("地形", terrain, typeof(Terrain), true);
        if (EditorGUI.EndChangeCheck())
            RefreshPaintMask();

        if (terrain == null)
        {
            EditorGUILayout.HelpBox("请指定一个 Terrain。", MessageType.Warning);
            EditorGUILayout.EndScrollView();
            return;
        }

        if (paintMask == null || paintMask.distributionMask == null)
        {
            EditorGUILayout.HelpBox("尚未创建绘制图。创建后初始为全黑（无草），可在 Scene 视图中绘制需要长草的区域。",
                                    MessageType.Warning);
            if (GUILayout.Button("创建空白草地分布图"))
                CreatePaintMask();
            EditorGUILayout.EndScrollView();
            return;
        }

        brushRadius = EditorGUILayout.Slider("笔刷半径（米）", brushRadius, 0.25f, 30f);
        brushStrength = EditorGUILayout.Slider("笔刷强度", brushStrength, 0.01f, 1f);
        edgeSoftness = EditorGUILayout.Slider("边缘柔和度", edgeSoftness, 0f, 1f);
        eraseMode = GUILayout.Toolbar(eraseMode ? 1 : 0, new[] { "绘制草地", "擦除草地" }) == 1;
        paintMode = EditorGUILayout.ToggleLeft("启用 Scene 视图绘制", paintMode);

        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("全部填满")) FillMask(255);
            if (GUILayout.Button("全部清空")) FillMask(0);
        }

        if (GUILayout.Button("将草地/道路 Mask 同步到 Terrain 图层"))
            GrassTerrainLayerMaskSync.Sync(terrain);

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("分布图预览", EditorStyles.boldLabel);
        Rect previewRect = GUILayoutUtility.GetAspectRect(1f, GUILayout.MaxWidth(250f));
        EditorGUI.DrawPreviewTexture(previewRect, paintMask.distributionMask, null, ScaleMode.ScaleToFit);
        EditorGUILayout.LabelField($"分辨率：{paintMask.distributionMask.width} × {paintMask.distributionMask.height}");
        EditorGUILayout.HelpBox(
            "绘制完成后同步 Terrain 图层；使用 Tools/草地/烘焙草场更新草实例。",
            MessageType.None);

        EditorGUILayout.EndScrollView();
    }

    void RefreshPaintMask()
    {
        paintMask = terrain != null ? terrain.GetComponent<GrassPaintMask>() : null;
        paintMode = false;
        Repaint();
        SceneView.RepaintAll();
    }

    void CreatePaintMask()
    {
        if (terrain == null || terrain.terrainData == null)
            return;

        if (!AssetDatabase.IsValidFolder("Assets/Grass/Data"))
            AssetDatabase.CreateFolder("Assets/Grass", "Data");

        if (paintMask == null)
            paintMask = Undo.AddComponent<GrassPaintMask>(terrain.gameObject);

        var texture = new Texture2D(MaskResolution, MaskResolution, TextureFormat.RGBA32, false, true)
        {
            name = terrain.name + "_GrassPaint",
            filterMode = FilterMode.Bilinear,
            wrapMode = TextureWrapMode.Clamp
        };
        var pixels = new Color32[MaskResolution * MaskResolution];
        for (int i = 0; i < pixels.Length; i++)
            pixels[i] = new Color32(0, 0, 0, 255);
        texture.SetPixels32(pixels);
        texture.Apply(false);

        string assetPath = AssetDatabase.GenerateUniqueAssetPath(
            $"Assets/Grass/Data/GrassPaint_{terrain.name}.asset");
        AssetDatabase.CreateAsset(texture, assetPath);
        Undo.RecordObject(paintMask, "Assign Grass Distribution Mask");
        paintMask.distributionMask = texture;
        EditorUtility.SetDirty(paintMask);
        EditorSceneManager.MarkSceneDirty(terrain.gameObject.scene);
        AssetDatabase.SaveAssets();
        Repaint();
    }

    void FillMask(byte value)
    {
        if (!HasPaintMask())
            return;

        var texture = paintMask.distributionMask;
        Undo.RegisterCompleteObjectUndo(texture, value == 0 ? "Clear Grass Distribution" : "Fill Grass Distribution");
        var pixels = new Color32[texture.width * texture.height];
        for (int i = 0; i < pixels.Length; i++)
            pixels[i] = new Color32(value, value, value, 255);
        texture.SetPixels32(pixels);
        texture.Apply(false);
        EditorUtility.SetDirty(texture);
        AssetDatabase.SaveAssets();
        Repaint();
        SceneView.RepaintAll();
    }

    void OnSceneGUI(SceneView sceneView)
    {
        if (!paintMode || !HasPaintMask() || terrain.terrainData == null)
            return;

        var terrainCollider = terrain.GetComponent<TerrainCollider>();
        if (terrainCollider == null)
            return;

        Event current = Event.current;
        Ray ray = HandleUtility.GUIPointToWorldRay(current.mousePosition);
        bool hitTerrain = terrainCollider.Raycast(ray, out RaycastHit hit, 10000f);
        int controlId = GUIUtility.GetControlID(FocusType.Passive);
        if (current.type == EventType.Layout && hitTerrain)
            HandleUtility.AddDefaultControl(controlId);

        if (hitTerrain)
        {
            Handles.color = eraseMode
                ? new Color(1f, 0.25f, 0.2f, 0.8f)
                : new Color(0.25f, 1f, 0.35f, 0.8f);
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
        var texture = paintMask.distributionMask;
        Undo.RegisterCompleteObjectUndo(texture, eraseMode ? "Erase Grass Distribution" : "Paint Grass Distribution");
        workingPixels = texture.GetPixels32();
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
        var texture = paintMask.distributionMask;
        var terrainData = terrain.terrainData;
        Vector3 terrainPosition = terrain.transform.position;
        Vector3 scale = terrain.transform.lossyScale;
        float terrainWidth = terrainData.size.x * Mathf.Abs(scale.x);
        float terrainLength = terrainData.size.z * Mathf.Abs(scale.z);
        if (terrainWidth <= 0f || terrainLength <= 0f)
            return;

        float u = (worldPosition.x - terrainPosition.x) / terrainWidth;
        float v = (worldPosition.z - terrainPosition.z) / terrainLength;
        float centerX = u * (texture.width - 1);
        float centerY = v * (texture.height - 1);
        float radiusX = brushRadius / terrainWidth * (texture.width - 1);
        float radiusY = brushRadius / terrainLength * (texture.height - 1);
        int x0 = Mathf.Clamp(Mathf.FloorToInt(centerX - radiusX), 0, texture.width - 1);
        int x1 = Mathf.Clamp(Mathf.CeilToInt(centerX + radiusX), 0, texture.width - 1);
        int y0 = Mathf.Clamp(Mathf.FloorToInt(centerY - radiusY), 0, texture.height - 1);
        int y1 = Mathf.Clamp(Mathf.CeilToInt(centerY + radiusY), 0, texture.height - 1);
        float innerRadius = brushRadius * (1f - edgeSoftness);
        byte target = eraseMode ? (byte)0 : (byte)255;

        for (int y = y0; y <= y1; y++)
        {
            float worldZ = (y / (float)(texture.height - 1) - v) * terrainLength;
            for (int x = x0; x <= x1; x++)
            {
                float worldX = (x / (float)(texture.width - 1) - u) * terrainWidth;
                float distance = Mathf.Sqrt(worldX * worldX + worldZ * worldZ);
                if (distance > brushRadius)
                    continue;

                float falloff = distance <= innerRadius
                    ? 1f
                    : 1f - Mathf.InverseLerp(innerRadius, brushRadius, distance);
                float blend = Mathf.Clamp01(brushStrength * falloff);
                int index = y * texture.width + x;
                byte value = (byte)Mathf.RoundToInt(
                    Mathf.Lerp(workingPixels[index].r, target, blend));
                workingPixels[index] = new Color32(value, value, value, 255);
            }
        }
    }

    void CommitPixels()
    {
        var texture = paintMask.distributionMask;
        texture.SetPixels32(workingPixels);
        texture.Apply(false);
        EditorUtility.SetDirty(texture);
        Repaint();
    }

    void EndStroke()
    {
        if (!strokeActive)
            return;

        strokeActive = false;
        workingPixels = null;
        AssetDatabase.SaveAssets();
        SceneView.RepaintAll();
    }

    void OnUndoRedo()
    {
        workingPixels = null;
        Repaint();
        SceneView.RepaintAll();
    }

    bool HasPaintMask() =>
        paintMask != null && paintMask.distributionMask != null && terrain != null;
}
