using UnityEditor;
using UnityEngine;

// ============================================================================
//  GrassBladeMeshBuilder —— 程序化生成草叶网格（对齐 UE 的 Rectangle）
//
//  为什么是 3 列 × 5 行：
//    列（3 个）：中间那一列是必须的 —— 内折法线要在 u=0.5 处做出"中脉"的下凹，
//               只有 2 列就没有中心顶点，法线插值做不出束状明暗。
//    行（5 个）：贝塞尔弯曲 + 尖端收窄要足够平滑，4 段足够。
//    3 × 5 = 15 顶点 / 16 三角，正好和 UE 那边的 Rectangle（18 顶点 / 16 三角）
//    同样的三角形数，形状一致。
//
//  网格约定（和 Grass.shader 强绑定）：
//    X ∈ [-0.5, 0.5]  叶片宽度方向
//    Y ∈ [0, 1]       从根部到尖端
//    UV.x = X + 0.5, UV.y = Y
//    Pivot 在根部中心 —— 草是绕着根部旋转的
// ============================================================================

public static class GrassBladeMeshBuilder
{
    const int Cols = 3;
    const int Rows = 5;

    [MenuItem("Tools/草地/① 生成草叶网格", false, 1)]
    public static void Build()
    {
        EnsureFolder("Assets/Grass", "Meshes");

        var mesh = new Mesh { name = "GrassBlade" };
        mesh.hideFlags = HideFlags.None;

        var verts = new Vector3[Cols * Rows];
        var uvs = new Vector2[Cols * Rows];
        var normals = new Vector3[Cols * Rows];

        for (int r = 0; r < Rows; r++)
        {
            float v = r / (float)(Rows - 1);
            for (int c = 0; c < Cols; c++)
            {
                float u = c / (float)(Cols - 1);
                int i = r * Cols + c;
                verts[i] = new Vector3(u - 0.5f, v, 0f);
                uvs[i] = new Vector2(u, v);
                normals[i] = new Vector3(0f, 0f, -1f);   // 真正的法线在 shader 里算
            }
        }

        var tris = new int[(Cols - 1) * (Rows - 1) * 6];
        int t = 0;
        for (int r = 0; r < Rows - 1; r++)
        {
            for (int c = 0; c < Cols - 1; c++)
            {
                int i0 = r * Cols + c;
                int i1 = i0 + 1;
                int i2 = i0 + Cols;
                int i3 = i2 + 1;

                tris[t++] = i0; tris[t++] = i2; tris[t++] = i1;
                tris[t++] = i1; tris[t++] = i2; tris[t++] = i3;
            }
        }

        mesh.vertices = verts;
        mesh.uv = uvs;
        mesh.normals = normals;
        mesh.triangles = tris;
        mesh.RecalculateBounds();

        string path = "Assets/Grass/Meshes/GrassBlade.asset";
        // 重建资产（保证网格一定是最新的），然后把场景里的 GrassField 重新指回来，
        // 否则会留下 Missing 引用
        AssetDatabase.DeleteAsset(path);
        AssetDatabase.CreateAsset(mesh, path);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        RelinkMeshes(AssetDatabase.LoadAssetAtPath<Mesh>(path));

        Selection.activeObject = AssetDatabase.LoadAssetAtPath<Mesh>(path);
        Validate(mesh);
        Debug.Log($"[草地] 草叶网格已生成：{path}  顶点 {mesh.vertexCount} / 三角 {mesh.triangles.Length / 3}");
    }

    static void Validate(Mesh mesh)
    {
        var b = mesh.bounds;
        Debug.Log($"[草地] 网格包围盒 center={b.center} size={b.size}" +
                  $"（期望 center=(0,0.5,0) size=(1,1,0)，pivot 在根部）");
    }

    [MenuItem("Tools/草地/①b 生成草地材质", false, 2)]
    public static void BuildMaterial()
    {
        EnsureFolder("Assets/Grass", "Materials");

        // 复用工程里已有的噪声贴图（fbm_2x2 / PerlinNoise 都在 Assets/Textures）
        Texture2D noise = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/PerlinNoise.jpg");
        if (noise == null) noise = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/fbm_2x2.png");

        var shader = Shader.Find("Grass/GrassField");
        if (shader == null)
        {
            Debug.LogError("[草地] 找不到 shader Grass/GrassField，先让 Unity 编译完 shader 再执行");
            return;
        }

        string path = "Assets/Grass/Materials/Grass_Mat.mat";

        // 每次重建：这样 shader 里改过的默认值（颜色/宽度/高度）才会真的生效
        AssetDatabase.DeleteAsset(path);
        var mat = new Material(shader) { name = "Grass_Mat" };
        if (noise != null) mat.SetTexture("_WindNoise", noise);
        mat.enableInstancing = true;
        AssetDatabase.CreateAsset(mat, path);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        RelinkMaterials(mat);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();

        Selection.activeObject = mat;
        Debug.Log($"[草地] 材质已生成：{path}  噪声贴图={(noise != null ? noise.name : "无")}");
    }

    /// <summary>重建资产后把场景里的 GrassField 重新指向新网格。</summary>
    static void RelinkMeshes(Mesh mesh)
    {
        var fields = Object.FindObjectsOfType<GrassField>(true);
        foreach (var f in fields)
        {
            f.mesh = mesh;
            EditorUtility.SetDirty(f);
        }
        if (fields.Length > 0)
            Debug.Log($"[草地] 已重新关联 {fields.Length} 个 GrassField 的网格");
    }

    /// <summary>重建资产后把场景里的 GrassField 重新指向新材质。</summary>
    static void RelinkMaterials(Material mat)
    {
        var fields = Object.FindObjectsOfType<GrassField>(true);
        foreach (var f in fields)
        {
            f.material = mat;
            EditorUtility.SetDirty(f);
        }
        if (fields.Length > 0)
            Debug.Log($"[草地] 已重新关联 {fields.Length} 个 GrassField 的材质");
    }

    static void EnsureFolder(string parent, string child)
    {
        if (!AssetDatabase.IsValidFolder($"{parent}/{child}"))
            AssetDatabase.CreateFolder(parent, child);
    }
}
