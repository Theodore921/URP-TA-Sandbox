using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// ============================================================================
//  GrassSceneSetup —— 一键搭好草地演示场景
//
//  做三件事：
//    1. 建一块 120×120m 的平面 Terrain（URP 需要手动给 Terrain 指定 Lit 材质，
//       默认材质在 URP 下会渲染成粉色）
//    2. 建一个 GrassField 物体，把网格/材质/ComputeShader/数据自动挂上
//    3. 把相机、光照留在原处（天空球的东西一概不动）
// ============================================================================

public static class GrassSceneSetup
{
    const float TerrainSize = 120f;
    const float TerrainHeight = 30f;

    [MenuItem("Tools/草地/③ 在当前场景创建草地对象", false, 4)]
    public static void Setup()
    {
        // ── 1. Terrain ──────────────────────────────────────────────────────
        var terrain = Object.FindObjectOfType<Terrain>();
        if (terrain == null)
        {
            var td = new TerrainData
            {
                heightmapResolution = 513,
                size = new Vector3(TerrainSize, TerrainHeight, TerrainSize)
            };
            // 全平面：高度图默认全 0，正好符合"先用自带平面 Terrain"
            td.SetHeights(0, 0, new float[513, 513]);

            var go = Terrain.CreateTerrainGameObject(td);
            go.name = "GrassTerrain";
            go.transform.position = new Vector3(-TerrainSize * 0.5f, 0f, -TerrainSize * 0.5f);

            terrain = go.GetComponent<Terrain>();
            EditorSceneManager.MarkSceneDirty(go.scene);
            Debug.Log("[草地] 已创建 120×120m 平面 Terrain");
        }
        else
        {
            Debug.Log("[草地] 场景里已有 Terrain，跳过创建");
        }

        // 地形外观每次都重新确认：材质 + 图层 + alphamap 三样缺一就会画成棋盘格
        terrain.materialTemplate = GetOrCreateTerrainMaterial();
        // ⚠ Draw Instanced 必须关掉：它要求 shader 有完整的 instancing 变体，
        //   我们自定义的 Grass/Ground 即使加了 multi_compile_instancing 也不渲染
        //   （表现为整个地形消失、只看到天空球的地面）。
        //   地形网格本来就只是一个平面，关掉它对性能没有可见影响。
        terrain.drawInstanced = false;
        ApplyTerrainLayer(terrain.terrainData);

        // ── 2. GrassField ───────────────────────────────────────────────────
        var host = GameObject.Find("GrassField");
        if (host == null)
        {
            host = new GameObject("GrassField");
            EditorSceneManager.MarkSceneDirty(host.scene);
        }

        var field = host.GetComponent<GrassField>();
        if (field == null) field = host.AddComponent<GrassField>();

        field.mesh = AssetDatabase.LoadAssetAtPath<Mesh>("Assets/Grass/Meshes/GrassBlade.asset");
        field.material = AssetDatabase.LoadAssetAtPath<Material>("Assets/Grass/Materials/Grass_Mat.mat");
        field.cullShader = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/Grass/Shaders/GrassCull.compute");
        field.data = AssetDatabase.LoadAssetAtPath<GrassFieldData>("Assets/Grass/Data/GrassField.asset");

        var missing = "";
        if (field.mesh == null)        missing += " 草叶网格(①)";
        if (field.material == null)    missing += " 材质(①b)";
        if (field.cullShader == null)  missing += " 剔除ComputeShader";
        if (field.data == null)        missing += " 草场数据(②)";
        if (missing.Length > 0)
            Debug.LogWarning("[草地] 还缺：" + missing + " —— 按菜单顺序执行即可");

        // ── 3. 相机放在草地中间、平视 ----------------------------------------
        var cam = Camera.main;
        if (cam != null)
        {
            cam.transform.position = new Vector3(0f, 1.6f, -18f);
            cam.transform.rotation = Quaternion.Euler(8f, 0f, 0f);
            cam.farClipPlane = Mathf.Max(cam.farClipPlane, 500f);
        }

        // ── 4. 雾（只作用于本场景）：让远处的草和天空地平线融在一起 ─────────
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.ExponentialSquared;
        RenderSettings.fogDensity = 0.0075f;
        RenderSettings.fogColor = new Color(0.62f, 0.68f, 0.76f, 1f);

        Selection.activeGameObject = host;
        Debug.Log("[草地] 场景搭建完成。下一步：Tools/草地/② 烘焙草场");
    }

    static Material GetOrCreateTerrainMaterial()
    {
        const string path = "Assets/Grass/Materials/Terrain_Mat.mat";
        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);

        // 地面用自定义的 Grass/Ground：它按草地密度图压暗自己（接触阴影）。
        // 早期版本用的是 Terrain/Lit（棋盘格）或 URP Lit（没有接触阴影），检测到就重建。
        var groundShader = Shader.Find("Grass/Ground");
        if (groundShader == null)
        {
            Debug.LogError("[草地] 找不到 shader Grass/Ground");
            return mat;
        }

        if (mat != null && mat.shader != groundShader)
        {
            AssetDatabase.DeleteAsset(path);
            mat = null;
        }

        if (!AssetDatabase.IsValidFolder("Assets/Grass/Materials"))
            AssetDatabase.CreateFolder("Assets/Grass", "Materials");

        bool isNew = mat == null;
        if (isNew) mat = new Material(groundShader) { name = "Terrain_Mat" };

        // 每次执行都重新挂一遍贴图，避免改了贴图导入设置后材质里还是旧的引用
        var color = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/Ground/Ground003_1K-JPG_Color.jpg");
        var normal = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/Ground/Ground003_1K-JPG_NormalGL.jpg");
        var rough = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/Ground/Ground003_1K-JPG_Roughness.jpg");
        var height = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/Ground/Ground003_1K-JPG_Displacement.jpg");

        if (mat.HasProperty("_BaseMap") && color != null) mat.SetTexture("_BaseMap", color);
        if (mat.HasProperty("_NormalMap") && normal != null) mat.SetTexture("_NormalMap", normal);
        if (mat.HasProperty("_RoughnessMap") && rough != null) mat.SetTexture("_RoughnessMap", rough);
        if (mat.HasProperty("_HeightMap") && height != null) mat.SetTexture("_HeightMap", height);

        if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", new Color(0.62f, 0.58f, 0.50f, 1f));
        if (mat.HasProperty("_TilingMeters")) mat.SetFloat("_TilingMeters", 4.0f);
        if (mat.HasProperty("_MacroTiling")) mat.SetFloat("_MacroTiling", 7.0f);
        if (mat.HasProperty("_MacroStrength")) mat.SetFloat("_MacroStrength", 0.25f);
        if (mat.HasProperty("_NormalScale")) mat.SetFloat("_NormalScale", 1.0f);
        if (mat.HasProperty("_RoughnessMin")) mat.SetFloat("_RoughnessMin", 0.55f);
        if (mat.HasProperty("_RoughnessMax")) mat.SetFloat("_RoughnessMax", 1.0f);
        if (mat.HasProperty("_SpecIntensity")) mat.SetFloat("_SpecIntensity", 0.55f);
        if (mat.HasProperty("_HeightDetail")) mat.SetFloat("_HeightDetail", 1.2f);
        if (mat.HasProperty("_HeightAO")) mat.SetFloat("_HeightAO", 0.45f);
        mat.enableInstancing = true;

        if (isNew) AssetDatabase.CreateAsset(mat, path);
        else EditorUtility.SetDirty(mat);

        AssetDatabase.SaveAssets();
        return mat;
    }

    /// <summary>
    /// 确保基础地面、草地和道路图层存在；已有图层权重保持不变。
    /// </summary>
    static void ApplyTerrainLayer(TerrainData td)
    {
        var oldLayers = td.terrainLayers ?? new TerrainLayer[0];
        var oldAlphamaps = oldLayers.Length > 0
            ? td.GetAlphamaps(0, 0, td.alphamapWidth, td.alphamapHeight)
            : null;

        var ground = GetOrCreateTerrainLayer(
            "Assets/Grass/Materials/Ground.terrainlayer",
            "Ground",
            new Vector2(4f, 4f),
            AssetDatabase.LoadAssetAtPath<Texture2D>(
                "Assets/Textures/Ground/Ground003_1K-JPG_Color.jpg"),
            AssetDatabase.LoadAssetAtPath<Texture2D>(
                "Assets/Textures/Ground/Ground003_1K-JPG_NormalGL.jpg"));
        var grass = GetOrCreateTerrainLayer(
            "Assets/Grass/Materials/Grass.terrainlayer", "Grass", new Vector2(4f, 4f));
        var road = GetOrCreateTerrainLayer(
            "Assets/Grass/Materials/Road.terrainlayer", "Road", new Vector2(3f, 3f));

        var requiredLayers = new[] { ground, grass, road };
        var layers = new System.Collections.Generic.List<TerrainLayer>(requiredLayers);
        foreach (var layer in oldLayers)
        {
            if (layers.Contains(layer))
                continue;

            layers.Add(layer);
        }

        if (layers.Count > 4)
        {
            Debug.LogError(
                "[草地] Grass/Ground 当前支持最多 4 个 Terrain Layer；" +
                "请先移除多余图层，再运行场景搭建。");
            return;
        }

        bool layersChanged = oldLayers.Length != layers.Count;
        for (int i = 0; !layersChanged && i < oldLayers.Length; i++)
            layersChanged = oldLayers[i] != layers[i];
        if (!layersChanged)
            return;

        td.terrainLayers = layers.ToArray();
        int res = td.alphamapResolution;
        var alpha = new float[res, res, layers.Count];
        if (oldAlphamaps != null)
        {
            for (int y = 0; y < res; y++)
            for (int x = 0; x < res; x++)
            {
                float sum = 0f;
                for (int oldIndex = 0; oldIndex < oldLayers.Length; oldIndex++)
                {
                    int newIndex = layers.IndexOf(oldLayers[oldIndex]);
                    if (newIndex < 0 || oldIndex >= oldAlphamaps.GetLength(2))
                        continue;

                    float weight = oldAlphamaps[y, x, oldIndex];
                    alpha[y, x, newIndex] = weight;
                    sum += weight;
                }

                if (sum > 1e-5f)
                {
                    for (int i = 0; i < layers.Count; i++)
                        alpha[y, x, i] /= sum;
                }
                else
                {
                    alpha[y, x, 0] = 1f;
                }
            }
        }
        else
        {
            for (int y = 0; y < res; y++)
                for (int x = 0; x < res; x++)
                    alpha[y, x, 0] = 1f;
        }

        td.SetAlphamaps(0, 0, alpha);

        EditorUtility.SetDirty(td);
        AssetDatabase.SaveAssets();
    }

    static TerrainLayer GetOrCreateTerrainLayer(
        string path,
        string layerName,
        Vector2 tileSize,
        Texture2D diffuse = null,
        Texture2D normal = null)
    {
        var layer = AssetDatabase.LoadAssetAtPath<TerrainLayer>(path);
        if (layer != null)
            return layer;

        layer = new TerrainLayer
        {
            name = layerName,
            diffuseTexture = diffuse,
            normalMapTexture = normal,
            tileSize = tileSize,
            smoothness = 0.05f,
            metallic = 0f
        };
        AssetDatabase.CreateAsset(layer, path);
        return layer;
    }
}
