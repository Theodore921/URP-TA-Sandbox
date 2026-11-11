using System;
using UnityEngine;

// ============================================================================
//  GrassFieldData —— 烘焙后的草场数据（Unity 里替代 PCG 产物的东西）
//
//  数据存成二进制 TextAsset（.bytes）而不是 struct 数组：
//    300k 株 → 9.6MB 二进制；同样的东西如果用 struct 数组走 YAML 序列化，
//    会膨胀到 35MB 以上，而且每次刷新都要重新导入。
//
//  内存布局（和 Grass.shader 里的 GrassInstance 严格一致，32 字节/株）：
//      a = (世界坐标 xyz, 朝向弧度)
//      b = (统一缩放, 随机0, 随机1, 色调)
//  读取时用 Buffer.BlockCopy 直接重解释，不需要逐字段转换。
// ============================================================================

[Serializable]
public struct GrassInstance
{
    public Vector4 a;   // xyz = 世界坐标, w = 朝向（弧度）
    public Vector4 b;   // x = 缩放, y = Rand0, z = Rand1, w = 色调偏移
}

[Serializable]
public class GrassChunk
{
    public Vector2Int coord;    // 分块坐标（32m 一格）
    public Vector3 center;
    public float radius;
    public int start;
    public int count;
}

[CreateAssetMenu(fileName = "GrassField", menuName = "草地/草场数据", order = 1)]
public class GrassFieldData : ScriptableObject
{
    public const int Stride = 32;

    [Header("撒点信息（只读，供调试查看）")]
    public Vector3 fieldCenter;
    public Vector2 fieldSize;
    public float densityNear;
    public float densityFar;
    public float radiusNear;
    public float radiusFar;
    public float clumpSize;
    public int seed;

    [Header("数据")]
    [Tooltip("二进制实例数据，32 字节/株")]
    public TextAsset binary;
    public GrassChunk[] chunks = Array.Empty<GrassChunk>();

    [NonSerialized] GrassInstance[] _cache;
    [NonSerialized] byte[] _bytes;

    /// <summary>二进制原始数据（缓存一份，避免每次访问都复制）。</summary>
    public byte[] GetBytes()
    {
        if (_bytes == null && binary != null) _bytes = binary.bytes;
        return _bytes;
    }

    public int InstanceCount
    {
        get
        {
            var b = GetBytes();
            return b != null ? b.Length / Stride : 0;
        }
    }

    /// <summary>重新烘焙后必须调用，否则会读到旧的缓存。</summary>
    public void InvalidateCache()
    {
        _cache = null;
        _bytes = null;
    }

    /// <summary>取出实例数组（首次调用时从二进制解包并缓存）。</summary>
    public GrassInstance[] GetInstances()
    {
        if (_cache != null) return _cache;

        var bytes = GetBytes();
        if (bytes == null) { _cache = Array.Empty<GrassInstance>(); return _cache; }

        int n = bytes.Length / Stride;
        var arr = new GrassInstance[n];

        if (n > 0)
        {
            // Buffer.BlockCopy 只接受基元数组，所以先解到 float[] 再拼结构体
            var floats = new float[n * 8];
            Buffer.BlockCopy(bytes, 0, floats, 0, n * Stride);
            for (int i = 0; i < n; i++)
            {
                int o = i * 8;
                arr[i].a = new Vector4(floats[o + 0], floats[o + 1], floats[o + 2], floats[o + 3]);
                arr[i].b = new Vector4(floats[o + 4], floats[o + 5], floats[o + 6], floats[o + 7]);
            }
        }

        _cache = arr;
        return _cache;
    }

    /// <summary>整个草场的包围盒（给 DrawMeshInstancedIndirect 用）。</summary>
    public Bounds ComputeBounds()
    {
        if (chunks == null || chunks.Length == 0)
            return new Bounds(fieldCenter, new Vector3(1, 4, 1));

        Bounds b = new Bounds(chunks[0].center, Vector3.one);
        for (int i = 1; i < chunks.Length; i++)
        {
            var c = chunks[i];
            b.Encapsulate(new Bounds(c.center, new Vector3(c.radius * 2f, c.radius * 2f, c.radius * 2f)));
        }
        b.Expand(new Vector3(0, 3f, 0));
        return b;
    }

    void OnDisable() { _cache = null; }
}
