using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// ============================================================================
//  GrassInteractionSetup —— 一键搭好草地交互的测试环境
//
//  做四件事：
//    1. 生成盖印 / 衰减两个材质
//    2. 建 GrassTrail 物体（推力场系统），把草地材质和范围接上
//    3. 建 WASD 胶囊体，挂上控制器和 GrassTrailEmitter
//    4. 保存场景
//
//  用法：Tools/草地/④ 添加交互测试（WASD）
// ============================================================================

public static class GrassInteractionSetup
{
    [MenuItem("Tools/草地/④ 添加交互测试（WASD）", false, 5)]
    public static void Setup()
    {
        var terrain = Terrain.activeTerrain;
        Vector2 center = Vector2.zero;
        float size = 120f;
        if (terrain != null)
        {
            Vector3 tCenter = terrain.transform.position + terrain.terrainData.size * 0.5f;
            center = new Vector2(tCenter.x, tCenter.z);
            size = Mathf.Min(terrain.terrainData.size.x, terrain.terrainData.size.z);
        }

        var grassMat = AssetDatabase.LoadAssetAtPath<Material>("Assets/Grass/Materials/Grass_Mat.mat");
        if (grassMat == null)
            Debug.LogWarning("[草地] 找不到 Grass_Mat，先执行 ①b 生成草地材质");

        // ── 1. 材质 ─────────────────────────────────────────────────────────
        var stampMat = GetOrCreateMaterial("Assets/Grass/Materials/GrassTrailStamp.mat",
                                          "Hidden/Grass/GrassTrailStamp");

        // ── 2. 推力场系统 ───────────────────────────────────────────────────
        var trailGo = GameObject.Find("GrassTrail");
        if (trailGo == null)
        {
            trailGo = new GameObject("GrassTrail");
            EditorSceneManager.MarkSceneDirty(trailGo.scene);
        }

        var trail = trailGo.GetComponent<GrassTrailSystem>();
        if (trail == null) trail = trailGo.AddComponent<GrassTrailSystem>();
        trail.grassMaterial = grassMat;
        trail.stampMaterial = stampMat;
        trail.worldCenter = center;
        trail.worldSize = size;
        trail.stampStrength = 0.45f;   // 每个脚印的推力（会叠加）
        trail.stampLifetime = 2f;      // 脚印存活时间

        // ── 3. WASD 胶囊体 ──────────────────────────────────────────────────
        var player = GameObject.Find("Player");
        if (player == null)
        {
            player = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            player.name = "Player";
            // 自带的 CapsuleCollider 和 CharacterController 会打架，去掉
            var col = player.GetComponent<CapsuleCollider>();
            if (col != null) Object.DestroyImmediate(col);
            EditorSceneManager.MarkSceneDirty(player.scene);
        }

        var cc = player.GetComponent<CharacterController>();
        if (cc == null) cc = player.AddComponent<CharacterController>();
        cc.height = 1.8f;
        cc.radius = 0.35f;
        cc.center = new Vector3(0f, 0.1f, 0f);
        cc.slopeLimit = 50f;
        cc.stepOffset = 0.35f;

        var ctrl = player.GetComponent<GrassPlayerController>();
        if (ctrl == null) ctrl = player.AddComponent<GrassPlayerController>();

        var emitter = player.GetComponent<GrassTrailEmitter>();
        if (emitter == null) emitter = player.AddComponent<GrassTrailEmitter>();
        emitter.radius = 0.7f;
        emitter.strength = 1f;

        // 落在草场中心稍高的位置
        float groundY = terrain != null ? terrain.SampleHeight(new Vector3(center.x, 0f, center.y)) + terrain.transform.position.y : 0f;
        player.transform.position = new Vector3(center.x, groundY + 1.05f, center.y);
        player.transform.rotation = Quaternion.identity;

        // ── 4. 相机初始位置 ─────────────────────────────────────────────────
        var cam = Camera.main;
        if (cam != null)
        {
            cam.transform.position = player.transform.position + new Vector3(0f, 2.6f, -5.0f);
            cam.transform.rotation = Quaternion.Euler(12f, 0f, 0f);
        }

        EditorSceneManager.SaveScene(player.scene);

        Selection.activeGameObject = player;
        Debug.Log("[草地] 交互测试环境就绪：Play 后用 WASD（Shift 冲刺）走动，草会被压弯并慢慢回弹");
    }

    static Material GetOrCreateMaterial(string path, string shaderName)
    {
        var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
        var shader = Shader.Find(shaderName);
        if (shader == null)
        {
            Debug.LogError($"[草地] 找不到 shader {shaderName}");
            return existing;
        }

        if (existing != null && existing.shader == shader) return existing;

        if (existing != null) AssetDatabase.DeleteAsset(path);
        var mat = new Material(shader) { name = System.IO.Path.GetFileNameWithoutExtension(path) };
        AssetDatabase.CreateAsset(mat, path);
        AssetDatabase.SaveAssets();
        return mat;
    }
}
