// URP 平面反射：用一台镜像相机把场景渲染到 RT，水面按屏幕 UV 采样
// 关键点：
//   1. 反射相机放在水面镜像位置，投影矩阵保持主相机一致
//   2. 用斜裁剪近平面（CalculateObliqueMatrix）裁掉水面以下的几何，否则会看到地面背面
//   3. 镜像会翻转三角形绕序，渲染期间要 invertCulling
//   4. 水面自己所在图层要从反射相机的 cullingMask 里排除，避免无限递归
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Water
{
    [ExecuteAlways]
    [RequireComponent(typeof(MeshRenderer))]
    public class PlanarReflection : MonoBehaviour
    {
        [Header("渲染")]
        [Tooltip("反射贴图相对屏幕的分辨率倍率")]
        [Range(0.1f, 1f)] public float resolutionScale = 0.5f;
        [Tooltip("反射贴图最大边长")]
        public int maxResolution = 1024;
        [Tooltip("斜裁剪近平面，裁掉水面以下的几何")]
        public bool useObliqueClipping = true;
        [Tooltip("反射相机剔除的图层（默认用本物体所在图层）")]
        public bool excludeOwnLayer = true;

        [Header("调试")]
        public bool showReflectionCamera = false;

        private Camera reflectionCamera;
        private RenderTexture reflectionRT;
        private static bool s_renderingReflection = false;

        private void OnEnable()
        {
            CreateCamera();
            RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering;
        }

        private void OnDisable()
        {
            RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
            ReleaseResources();
        }

        private void OnValidate()
        {
            if (reflectionCamera != null)
            {
                reflectionCamera.enabled = showReflectionCamera;
            }
        }

        private void CreateCamera()
        {
            if (reflectionCamera != null) return;

            var go = new GameObject("~PlanarReflectionCamera");
            go.hideFlags = HideFlags.HideAndDontSave;
            go.transform.SetParent(null);
            reflectionCamera = go.AddComponent<Camera>();
            reflectionCamera.enabled = false;
            reflectionCamera.cameraType = CameraType.Reflection;
            reflectionCamera.clearFlags = CameraClearFlags.SolidColor;
            reflectionCamera.backgroundColor = Color.black;
            reflectionCamera.allowHDR = true;
            reflectionCamera.allowMSAA = false;
            reflectionCamera.useOcclusionCulling = false;
        }

        private void ReleaseResources()
        {
            if (reflectionRT != null)
            {
                reflectionRT.Release();
                DestroyImmediate(reflectionRT);
                reflectionRT = null;
            }
            if (reflectionCamera != null)
            {
                DestroyImmediate(reflectionCamera.gameObject);
                reflectionCamera = null;
            }
            Shader.SetGlobalFloat("_PlanarReflectionOn", 0f);
        }

        private void EnsureRT(int width, int height)
        {
            int w = Mathf.Max(16, Mathf.RoundToInt(width * resolutionScale));
            int h = Mathf.Max(16, Mathf.RoundToInt(height * resolutionScale));
            w = Mathf.Min(w, maxResolution);
            h = Mathf.Min(h, maxResolution);

            if (reflectionRT != null && reflectionRT.width == w && reflectionRT.height == h) return;

            if (reflectionRT != null)
            {
                reflectionRT.Release();
                DestroyImmediate(reflectionRT);
            }
            reflectionRT = new RenderTexture(w, h, 24, RenderTextureFormat.DefaultHDR)
            {
                name = "~PlanarReflectionRT",
                hideFlags = HideFlags.HideAndDontSave,
                useMipMap = false,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };
            reflectionRT.Create();
        }

        private void OnBeginCameraRendering(ScriptableRenderContext context, Camera cam)
        {
            if (s_renderingReflection) return;
            if (cam == reflectionCamera) return;
            if (cam.cameraType != CameraType.Game && cam.cameraType != CameraType.SceneView) return;
            if (reflectionCamera == null) CreateCamera();

            // 水面本身上下翻转后再反射就看不见了，直接排除本图层
            int mask = cam.cullingMask;
            if (excludeOwnLayer) mask &= ~(1 << gameObject.layer);
            reflectionCamera.cullingMask = mask;
            reflectionCamera.backgroundColor = cam.backgroundColor;
            reflectionCamera.clearFlags = cam.clearFlags;

            EnsureRT(cam.pixelWidth, cam.pixelHeight);
            reflectionCamera.targetTexture = reflectionRT;

            Vector3 normal = transform.up;
            Vector3 planePos = transform.position;

            // 镜像矩阵：R = I - 2*n*n^T, 平移 -2*d*n
            float d = -Vector3.Dot(normal, planePos);
            Matrix4x4 refl = Matrix4x4.identity;
            refl.m00 = 1f - 2f * normal.x * normal.x;
            refl.m01 = -2f * normal.x * normal.y;
            refl.m02 = -2f * normal.x * normal.z;
            refl.m03 = -2f * d * normal.x;
            refl.m10 = -2f * normal.y * normal.x;
            refl.m11 = 1f - 2f * normal.y * normal.y;
            refl.m12 = -2f * normal.y * normal.z;
            refl.m13 = -2f * d * normal.y;
            refl.m20 = -2f * normal.z * normal.x;
            refl.m21 = -2f * normal.z * normal.y;
            refl.m22 = 1f - 2f * normal.z * normal.z;
            refl.m23 = -2f * d * normal.z;
            refl.m33 = 1f;

            Vector3 camPos = refl.MultiplyPoint(cam.transform.position);
            Vector3 camFwd = refl.MultiplyVector(cam.transform.forward);
            Vector3 camUp = refl.MultiplyVector(cam.transform.up);

            reflectionCamera.transform.SetPositionAndRotation(camPos, Quaternion.LookRotation(camFwd, camUp));
            // 关键：镜像后的基是左手系，Quaternion 表达不精确，会导致倒影整体偏移。
            // 直接给视图矩阵 = 主相机视图矩阵 × 镜像矩阵
            reflectionCamera.worldToCameraMatrix = cam.worldToCameraMatrix * refl;
            reflectionCamera.nearClipPlane = cam.nearClipPlane;
            reflectionCamera.farClipPlane = cam.farClipPlane;
            reflectionCamera.fieldOfView = cam.fieldOfView;
            reflectionCamera.aspect = cam.aspect;
            reflectionCamera.orthographic = cam.orthographic;
            reflectionCamera.orthographicSize = cam.orthographicSize;

            if (useObliqueClipping)
            {
                Vector4 clipPlane = CameraSpacePlane(reflectionCamera, planePos, normal, 1f);
                reflectionCamera.projectionMatrix = cam.CalculateObliqueMatrix(clipPlane);
            }
            else
            {
                reflectionCamera.projectionMatrix = cam.projectionMatrix;
            }

            // 镜像会翻转绕序
            GL.invertCulling = true;
            s_renderingReflection = true;
            try
            {
                UniversalRenderPipeline.RenderSingleCamera(context, reflectionCamera);
            }
            finally
            {
                s_renderingReflection = false;
                GL.invertCulling = false;
            }

            Shader.SetGlobalTexture("_PlanarReflectionTex", reflectionRT);
            Shader.SetGlobalFloat("_PlanarReflectionOn", 1f);
        }

        private static Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
        {
            Matrix4x4 m = cam.worldToCameraMatrix;
            Vector3 cpos = m.MultiplyPoint(pos);
            Vector3 cnormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
        }

        private void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(0.2f, 0.8f, 1f, 0.6f);
            Gizmos.DrawWireCube(transform.position, new Vector3(10f, 0.01f, 10f));
        }
    }
}
