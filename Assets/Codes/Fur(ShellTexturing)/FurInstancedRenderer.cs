using UnityEngine;

[ExecuteAlways]
public class FurInstancedRenderer : MonoBehaviour
{
    [Header("Render Assets")]
    public Mesh mesh;
    public Material furMaterial;

    [Header("Fur Settings")]
    [Range(1, 100)] 
    public int shellCount = 40;

    private Matrix4x4[] matrices;
    private float[] layerRatios;
    private MaterialPropertyBlock propertyBlock;

    void Update()
    {
        // 确保资源与参数有效
        if (mesh == null || furMaterial == null || shellCount <= 0) return;

        // 初始化或当层数改变时，重新分配内存
        if (matrices == null || matrices.Length != shellCount)
        {
            matrices = new Matrix4x4[shellCount];
            layerRatios = new float[shellCount];
            propertyBlock = new MaterialPropertyBlock();

            for (int i = 0; i < shellCount; i++)
            {
                // 计算当前层级的比例：0.0 (底层) -> 1.0 (最外层)
                layerRatios[i] = (float)i / (shellCount - 1);
            }
            // 将比例数组一次性传入材质属性块
            propertyBlock.SetFloatArray("_LayerRatio", layerRatios);
        }

        // 更新矩阵：所有层叠在同一位置，跟随当前物体的 Transform
        Matrix4x4 currentMatrix = transform.localToWorldMatrix;
        for (int i = 0; i < shellCount; i++)
        {
            matrices[i] = currentMatrix;
        }

        // 提交 Instancing 渲染请求 (限制: 单批次最大 1023 个实例)
        Graphics.DrawMeshInstanced(mesh, 0, furMaterial, matrices, shellCount, propertyBlock);
    }
}