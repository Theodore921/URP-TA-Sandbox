// 把"入水物体"的信息批量推给水面 shader（最多 8 个）：
//   _WaterActors[i]      = (worldX, worldY, worldZ, radius)
//   _WaterActorSpeed[i]  = 平滑后的水平速度
//   _WaterActorCount     = 当前有效数量
// 对应 shader 里的 WaterNormalWS()：用距离 + 方向推开波纹、生成扩散环
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Water
{
    [ExecuteAlways]
    [DisallowMultipleComponent]
    public class WaterInteraction : MonoBehaviour
    {
        [Header("水面")]
        [Tooltip("用来取水位的对象（通常是水面平面）")]
        public Transform waterPlane;

        [Header("交互体")]
        [Tooltip("自动用渲染器包围盒推算半径，关掉则用下面的固定值")]
        public bool autoRadius = true;
        [Tooltip("自动半径的缩放系数")]
        public float radiusScale = 1.0f;
        [Range(0.1f, 8f)] public float radius = 1.2f;
        [Tooltip("脚部没入水超过这个深度就不算在水中")]
        public float maxDepth = 2.0f;

        [Header("速度")]
        public float smooth = 8f;
        public float speedMultiplier = 1f;
        [Tooltip("编辑模式下预览波纹用的假速度（运行时不影响）")]
        public float debugSpeed = 0f;

        private Vector3 lastPosition;
        private float smoothSpeed;
        private bool initialized;

        private static readonly List<WaterInteraction> s_instances = new List<WaterInteraction>();
        private static readonly Vector4[] s_positions = new Vector4[8];
        private static readonly float[] s_speeds = new float[8];

        private static readonly int ActorsID = Shader.PropertyToID("_WaterActors");
        private static readonly int SpeedsID = Shader.PropertyToID("_WaterActorSpeed");
        private static readonly int CountID = Shader.PropertyToID("_WaterActorCount");

        private void OnEnable()
        {
            if (!s_instances.Contains(this)) s_instances.Add(this);
            lastPosition = transform.position;
            initialized = true;
            // 编辑模式下 LateUpdate 不一定被调用，靠"相机渲染前"保证数据新鲜
            RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
            RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering;
            Upload();
        }

        private void OnDisable()
        {
            s_instances.Remove(this);
            RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
            Upload();
        }

        private static void OnBeginCameraRendering(ScriptableRenderContext context, Camera camera)
        {
            Upload();
        }

        private void LateUpdate()
        {
            if (!initialized)
            {
                lastPosition = transform.position;
                initialized = true;
            }

            float dt = Mathf.Max(Time.deltaTime, 1f / 120f);
            Vector3 position = transform.position;
            Vector3 delta = position - lastPosition;
            delta.y = 0f;
            lastPosition = position;

            float instantSpeed = delta.magnitude / dt;
            smoothSpeed = Mathf.Lerp(smoothSpeed, instantSpeed, 1f - Mathf.Exp(-smooth * dt));

            Upload();
        }

        private bool IsInWater(out float depth)
        {
            float waterY = waterPlane != null ? waterPlane.position.y : 0f;
            depth = waterY - transform.position.y;
            return depth > -0.05f && depth < maxDepth;
        }

        private float ResolveRadius()
        {
            if (!autoRadius) return radius;
            var r = GetComponentInChildren<Renderer>();
            if (r == null) return radius;
            Bounds b = r.bounds;
            float ext = Mathf.Max(b.extents.x, b.extents.z);
            return Mathf.Max(0.15f, ext * radiusScale);
        }

        private static void Upload()
        {
            int n = 0;
            for (int i = 0; i < s_instances.Count && n < 8; i++)
            {
                var inst = s_instances[i];
                if (inst == null || !inst.isActiveAndEnabled) continue;

                float depth;
                if (!inst.IsInWater(out depth)) continue;

                Vector3 p = inst.transform.position;
                s_positions[n] = new Vector4(p.x, p.y, p.z, inst.ResolveRadius());
                float spd = inst.smoothSpeed * inst.speedMultiplier;
                s_speeds[n] = Mathf.Max(spd, inst.debugSpeed);
                n++;
            }

            Shader.SetGlobalVectorArray(ActorsID, s_positions);
            Shader.SetGlobalFloatArray(SpeedsID, s_speeds);
            Shader.SetGlobalFloat(CountID, n);
        }

        private void OnDrawGizmosSelected()
        {
            float r = ResolveRadius();
            Vector3 p = new Vector3(transform.position.x,
                                    waterPlane != null ? waterPlane.position.y : 0f,
                                    transform.position.z);
            Gizmos.color = new Color(0.3f, 0.9f, 1f, 0.7f);
            Gizmos.DrawWireSphere(p, r);
        }
    }
}
