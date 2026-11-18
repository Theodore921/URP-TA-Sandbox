using UnityEngine;

[ExecuteAlways]
[DisallowMultipleComponent]
[RequireComponent(typeof(Terrain))]
public sealed class CliffTerrainBlendBinder : MonoBehaviour
{
    private static readonly int HeightMapId = Shader.PropertyToID("_CliffTerrainHeightMap");
    private static readonly int OriginId = Shader.PropertyToID("_CliffTerrainOrigin");
    private static readonly int SizeId = Shader.PropertyToID("_CliffTerrainSize");

    private Terrain terrain;
    private Texture boundHeightMap;
    private Vector4 boundOrigin;
    private Vector4 boundSize;
    private bool hasBinding;

    private void OnEnable()
    {
        terrain = GetComponent<Terrain>();
        if (terrain == null)
        {
            Debug.LogError("CliffTerrainBlendBinder requires a Terrain component.", this);
            enabled = false;
            return;
        }

        UpdateBinding();
    }

    private void Update()
    {
        UpdateBinding();
    }

    private void OnDisable()
    {
        Shader.SetGlobalTexture(HeightMapId, Texture2D.blackTexture);
        Shader.SetGlobalVector(OriginId, Vector4.zero);
        Shader.SetGlobalVector(SizeId, Vector4.one);
        hasBinding = false;
    }

    private void UpdateBinding()
    {
        if (terrain == null || terrain.terrainData == null)
            return;

        Texture heightMap = terrain.terrainData.heightmapTexture;
        if (heightMap == null)
            return;
        Vector3 position = terrain.transform.position;
        Vector3 terrainSize = terrain.terrainData.size;
        Vector4 origin = new Vector4(position.x, position.y, position.z, 0);
        Vector4 size = new Vector4(terrainSize.x, terrainSize.y, terrainSize.z, 0);

        if (hasBinding && heightMap == boundHeightMap && origin == boundOrigin && size == boundSize)
            return;

        Shader.SetGlobalTexture(HeightMapId, heightMap);
        Shader.SetGlobalVector(OriginId, origin);
        Shader.SetGlobalVector(SizeId, size);
        boundHeightMap = heightMap;
        boundOrigin = origin;
        boundSize = size;
        hasBinding = true;
    }
}
