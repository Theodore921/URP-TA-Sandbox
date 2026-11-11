using System.Collections.Generic;
using UnityEngine;

// ============================================================================
//  GrassRoadPath —— 草地场景里的"路"
//
//  只存数据，不做绘制：
//    · points    : 世界的路点（Scene 视图里点出来的）
//    · 形状参数  : 路宽 / 边缘噪声 / 柔和度
//    · mask      : 由工具烘焙出来的掩码贴图（R 通道，1 = 路面）
//
//  谁在用它：
//    · Ground.shader  → 按掩码把地面混成泥土（更暗、更粗糙、法线更强）
//    · GrassBaker     → 按掩码剔除路面上的草（带噪声抖动，边界呈锯齿状）
//
//  掩码和「草地密度图」共用同一套世界坐标约定：
//      uv = (worldXZ - worldCenter) / worldSize + 0.5
// ============================================================================

[ExecuteAlways]
[AddComponentMenu("草地/Grass Road Path")]
public class GrassRoadPath : MonoBehaviour
{
    [Header("路径点（世界坐标）")]
    public List<Vector3> points = new List<Vector3>();

    [Header("形状")]
    [Tooltip("路的宽度（米）")]
    public float width = 2.6f;
    [Tooltip("路宽度的噪声扰动：0 = 一条光滑的路，越大边缘越不规则")]
    [Range(0f, 1f)] public float edgeNoise = 0.35f;
    [Tooltip("边缘噪声的空间频率（越大越细碎）")]
    public float edgeNoiseScale = 0.45f;
    [Tooltip("边缘柔和度：越小边界越硬")]
    [Range(0.01f, 1f)] public float softness = 0.35f;

    [Header("掩码")]
    [Tooltip("烘焙出来的掩码贴图（由工具生成，不要手动改）")]
    public Texture2D mask;
    public Vector2 worldCenter = Vector2.zero;
    public float worldSize = 120f;
    public int resolution = 1024;

    [Header("草地剔除")]
    [Tooltip("掩码超过这个值就不长草（越小路面越宽）")]
    [Range(0f, 1f)] public float grassCutThreshold = 0.45f;
    [Tooltip("边界抖动：让路面上的草呈锯齿状，而不是一条干净的线")]
    [Range(0f, 0.5f)] public float grassEdgeJitter = 0.22f;

    /// <summary>把掩码 UV 换算成世界 XZ（给烘焙/调试用）。</summary>
    public Vector2 MaskUVToWorld(Vector2 uv) => uv * worldSize + worldCenter;
    public Vector2 WorldToMaskUV(Vector2 worldXZ) =>
        (worldXZ - worldCenter) / Mathf.Max(worldSize, 0.001f) + new Vector2(0.5f, 0.5f);

    void OnDrawGizmos()
    {
        if (points == null || points.Count < 2) return;

        Gizmos.color = new Color(0.95f, 0.75f, 0.25f, 0.9f);
        for (int i = 0; i < points.Count; i++)
        {
            Gizmos.DrawSphere(points[i], 0.15f);
            if (i + 1 < points.Count) Gizmos.DrawLine(points[i], points[i + 1]);
        }

        // 画出路面范围，方便在 Scene 视图里判断宽度
        Gizmos.color = new Color(0.95f, 0.75f, 0.25f, 0.35f);
        for (int i = 0; i < points.Count; i++)
        {
            Vector3 a = points[i];
            Vector3 dir = i + 1 < points.Count ? (points[i + 1] - a) : (a - points[i - 1]);
            dir.y = 0f;
            if (dir.sqrMagnitude < 1e-6f) continue;
            dir.Normalize();
            Vector3 side = new Vector3(-dir.z, 0f, dir.x) * (width * 0.5f);
            Gizmos.DrawLine(a - side, a + side);
        }
    }
}
