using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class GrassTerrainLayerMaskSync
{
    [MenuItem("Tools/草地/从 Mask 同步 Terrain 图层", false, 8)]
    static void SyncActiveTerrain()
    {
        var terrain = Terrain.activeTerrain;
        if (terrain == null)
        {
            Debug.LogError("[草地] 场景中没有启用的 Terrain，无法同步图层。");
            return;
        }

        Sync(terrain);
    }

    public static bool Sync(Terrain terrain)
    {
        if (terrain == null || terrain.terrainData == null)
        {
            Debug.LogError("[草地] Terrain 或 TerrainData 为空，无法同步图层。");
            return false;
        }

        var terrainData = terrain.terrainData;
        var layers = terrainData.terrainLayers;
        if (layers == null || layers.Length == 0 || layers.Length > 4)
        {
            Debug.LogError("[草地] Terrain 必须配置 1 到 4 个 Terrain Layer 才能同步。", terrain);
            return false;
        }

        int groundIndex = FindLayer(layers, "Ground");
        int grassIndex = FindLayer(layers, "Grass");
        int roadIndex = FindLayer(layers, "Road");
        if (groundIndex < 0 || grassIndex < 0 || roadIndex < 0)
        {
            Debug.LogError(
                "[草地] Terrain Layers 中必须包含名称为 Ground、Grass、Road 的图层。",
                terrain);
            return false;
        }

        if (layers[grassIndex].diffuseTexture == null || layers[roadIndex].diffuseTexture == null)
        {
            Debug.LogError(
                "[草地] 请先给 Grass 和 Road Terrain Layer 指定漫反射贴图，" +
                "否则同步后这些区域无法显示正确材质。",
                terrain);
            return false;
        }

        var paintMask = terrain.GetComponent<GrassPaintMask>();
        if (paintMask == null || paintMask.distributionMask == null)
        {
            Debug.LogError("[草地] Terrain 上没有可用的 GrassPaintMask 分布图。", terrain);
            return false;
        }

        var grassField = Object.FindObjectOfType<GrassField>();
        if (grassField == null || grassField.data == null)
        {
            Debug.LogError("[草地] 场景中没有已烘焙的 GrassField 数据。", terrain);
            return false;
        }

        var roadPath = Object.FindObjectOfType<GrassRoadPath>();
        if (roadPath == null || roadPath.mask == null)
        {
            Debug.LogError("[草地] 场景中没有可用的 GrassRoadPath 道路掩码。", terrain);
            return false;
        }

        Color32[] grassPixels;
        Color32[] roadPixels;
        try
        {
            grassPixels = paintMask.distributionMask.GetPixels32();
            roadPixels = roadPath.mask.GetPixels32();
        }
        catch (System.Exception exception)
        {
            Debug.LogError("[草地] 读取地表分布图失败：" + exception.Message, terrain);
            return false;
        }

        if (grassPixels.Length != paintMask.distributionMask.width * paintMask.distributionMask.height ||
            roadPixels.Length != roadPath.mask.width * roadPath.mask.height)
        {
            Debug.LogError("[草地] 地表分布图像素数据不完整，未修改 Terrain。", terrain);
            return false;
        }

        var oldWeights = terrainData.GetAlphamaps(
            0, 0, terrainData.alphamapWidth, terrainData.alphamapHeight);
        int width = terrainData.alphamapWidth;
        int height = terrainData.alphamapHeight;
        var weights = new float[height, width, layers.Length];

        Vector3 position = terrain.transform.position;
        Vector3 scale = terrain.transform.lossyScale;
        float terrainWidth = terrainData.size.x * Mathf.Abs(scale.x);
        float terrainLength = terrainData.size.z * Mathf.Abs(scale.z);
        if (terrainWidth <= 0f || terrainLength <= 0f)
        {
            Debug.LogError("[草地] Terrain 的世界尺寸无效，未修改 Terrain。", terrain);
            return false;
        }

        var fieldData = grassField.data;
        if (fieldData.radiusFar <= fieldData.radiusNear || fieldData.radiusNear < 0f ||
            fieldData.densityNear <= 0f)
        {
            Debug.LogError("[草地] GrassField 的撒草范围或密度数据无效，未修改 Terrain。", terrain);
            return false;
        }

        float maxSlopeAngle = Mathf.Clamp(
            EditorPrefs.GetFloat("GrassScatter.maxSlopeAngle", 45f), 0f, 89.9f);
        float edgeMargin = Mathf.Max(0f, EditorPrefs.GetFloat("GrassScatter.edgeMargin", 1f));
        float farDensityRatio = Mathf.Clamp01(fieldData.densityFar / fieldData.densityNear);
        float marginU = Mathf.Clamp(edgeMargin, 0f, terrainWidth * 0.5f) / terrainWidth;
        float marginV = Mathf.Clamp(edgeMargin, 0f, terrainLength * 0.5f) / terrainLength;

        for (int y = 0; y < height; y++)
        {
            float v = (y + 0.5f) / height;
            float worldZ = position.z + v * terrainLength;
            for (int x = 0; x < width; x++)
            {
                float u = (x + 0.5f) / width;
                float worldX = position.x + u * terrainWidth;

                float grass = SampleMask(
                    grassPixels,
                    paintMask.distributionMask.width,
                    paintMask.distributionMask.height,
                    u,
                    v);

                if (u < marginU || u > 1f - marginU || v < marginV || v > 1f - marginV)
                {
                    grass = 0f;
                }
                else
                {
                    Vector3 localNormal = terrainData.GetInterpolatedNormal(u, v);
                    Vector3 worldNormal = terrain.transform.TransformDirection(localNormal).normalized;
                    if (Vector3.Angle(worldNormal, Vector3.up) > maxSlopeAngle)
                    {
                        grass = 0f;
                    }
                    else
                    {
                        float dx = worldX - fieldData.fieldCenter.x;
                        float dz = worldZ - fieldData.fieldCenter.z;
                        float distance = Mathf.Sqrt(dx * dx + dz * dz);
                        if (distance >= fieldData.radiusFar)
                        {
                            grass = 0f;
                        }
                        else if (distance > fieldData.radiusNear)
                        {
                            float fade = Mathf.InverseLerp(
                                fieldData.radiusNear, fieldData.radiusFar, distance);
                            grass *= Mathf.Lerp(1f, farDensityRatio, fade);
                        }
                    }
                }

                Vector2 roadUV = roadPath.WorldToMaskUV(new Vector2(worldX, worldZ));
                float road = SampleMask(
                    roadPixels,
                    roadPath.mask.width,
                    roadPath.mask.height,
                    roadUV.x,
                    roadUV.y);

                grass *= 1f - road;
                float remaining = 1f - grass - road;

                float oldOtherTotal = 0f;
                for (int i = 0; i < layers.Length; i++)
                {
                    if (i != groundIndex && i != grassIndex && i != roadIndex)
                        oldOtherTotal += oldWeights[y, x, i];
                }

                weights[y, x, grassIndex] = grass;
                weights[y, x, roadIndex] = road;
                if (oldOtherTotal > 1e-5f)
                {
                    for (int i = 0; i < layers.Length; i++)
                    {
                        if (i != groundIndex && i != grassIndex && i != roadIndex)
                            weights[y, x, i] = remaining * oldWeights[y, x, i] / oldOtherTotal;
                    }

                    weights[y, x, groundIndex] = 0f;
                }
                else
                {
                    weights[y, x, groundIndex] = remaining;
                }
            }
        }

        Undo.RegisterCompleteObjectUndo(terrainData, "Sync Terrain Layers From Masks");
        terrainData.SetAlphamaps(0, 0, weights);
        EditorUtility.SetDirty(terrainData);
        EditorSceneManager.MarkSceneDirty(terrain.gameObject.scene);
        Debug.Log(
            $"[草地] Terrain 图层已从 Mask 同步：Grass ← {paintMask.distributionMask.name}，" +
            $"Road ← {roadPath.mask.name}。支持 Undo，记得保存场景。",
            terrain);
        return true;
    }

    static int FindLayer(TerrainLayer[] layers, string layerName)
    {
        for (int i = 0; i < layers.Length; i++)
            if (layers[i] != null && layers[i].name == layerName)
                return i;
        return -1;
    }

    static float SampleMask(Color32[] pixels, int width, int height, float u, float v)
    {
        if (u < 0f || u > 1f || v < 0f || v > 1f)
            return 0f;

        float x = u * (width - 1);
        float y = v * (height - 1);
        int x0 = Mathf.FloorToInt(x);
        int y0 = Mathf.FloorToInt(y);
        int x1 = Mathf.Min(x0 + 1, width - 1);
        int y1 = Mathf.Min(y0 + 1, height - 1);
        float tx = x - x0;
        float ty = y - y0;
        float a = Mathf.Lerp(pixels[y0 * width + x0].r, pixels[y0 * width + x1].r, tx);
        float b = Mathf.Lerp(pixels[y1 * width + x0].r, pixels[y1 * width + x1].r, tx);
        return Mathf.Lerp(a, b, ty) / 255f;
    }
}
