using UnityEngine;

[DisallowMultipleComponent]
[AddComponentMenu("草地/Grass Paint Mask")]
public class GrassPaintMask : MonoBehaviour
{
    [Tooltip("草地分布绘制图。黑色不生成草，白色使用当前密度设置。")]
    public Texture2D distributionMask;
}
