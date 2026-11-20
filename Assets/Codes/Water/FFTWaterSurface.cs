using System;
using UnityEngine;
using UnityEngine.Rendering;
#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
#endif

[ExecuteAlways]
[DisallowMultipleComponent]
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class FFTWaterSurface : MonoBehaviour
{
    private const int ThreadGroupSize = 32;
    private const double EditorPreviewInterval = 1.0 / 15.0;

    [Header("FFT Simulation")]
    public ComputeShader fftComputeShader;
    [Tooltip("FFT texture resolution. Must be a power of two and a multiple of 32.")]
    [Min(32)] public int resolution = 256;
    [Tooltip("Water mesh subdivisions per side. Higher values show finer geometry but cost more.")]
    [Min(1)] public int meshSegments = 256;
    [Tooltip("Physical width, in meters, represented by one repeating FFT tile.")]
    [Min(1f)] public float realLength = 200f;
    [Tooltip("Scales the computed FFT height into Unity world units.")]
    [Min(0f)] public float waveHeight = 5000f;
    [Tooltip("Multiplier for wave animation speed. Set to zero to freeze the current wave.")]
    [Min(0f)] public float waveSpeed = 1f;
    public Vector2 windDirection = new Vector2(1f, 0.25f);
    [Tooltip("Wind speed controls the dominant wavelength in the Phillips spectrum.")]
    [Min(0.1f)] public float windSpeed = 10f;
    [Tooltip("Phillips spectrum amplitude. This controls the raw FFT height before Wave Height scaling.")]
    [Min(0f)] public float phillipsAmplitude = 0.00002f;
    public int randomSeed = 127;
    [Header("Editor Preview")]
    [Tooltip("Run the FFT in edit mode so wave settings can be tuned without entering Play mode.")]
    public bool previewInEditMode = true;

    private MeshFilter meshFilter;
    private MeshRenderer meshRenderer;
    private Mesh originalMesh;
    private Mesh generatedMesh;
    private RenderTexture spectrumTexture;
    private RenderTexture horizontalPing;
    private RenderTexture horizontalPong;
    private RenderTexture verticalPing;
    private RenderTexture verticalPong;
    private RenderTexture heightTexture;
    private ComputeBuffer spectrumBuffer;
    private MaterialPropertyBlock propertyBlock;
    private int updateSpectrumKernel;
    private int horizontalBitReverseKernel;
    private int horizontalFftKernel;
    private int verticalBitReverseKernel;
    private int verticalFftKernel;
    private int updateHeightKernel;
    private bool reinitializeRequested;
    private bool spectrumRefreshRequested;
    private bool meshRefreshRequested;
    private int initializedResolution;
    private int initializedMeshSegments;
    private ComputeShader initializedComputeShader;
    private float initializedRealLength;
    private float initializedWindSpeed;
    private float initializedPhillipsAmplitude;
    private Vector2 initializedWindDirection;
    private int initializedRandomSeed;
    private double lastEditorUpdateTime;
    private float simulationTime;
#if UNITY_EDITOR
    private bool restorePreviewMeshAfterSave;
#endif

    private static readonly int WaveMapId = Shader.PropertyToID("_FFTWaveMap");
    private static readonly int HeightScaleId = Shader.PropertyToID("_FFTHeightScale");
    private static readonly int RealLengthId = Shader.PropertyToID("_FFTRealLength");

    private struct SpectrumEntry
    {
        public Vector2 k;
        public Vector4 coefficients;
    }

    private void OnEnable()
    {
        meshFilter = GetComponent<MeshFilter>();
        meshRenderer = GetComponent<MeshRenderer>();
        originalMesh = meshFilter.sharedMesh;
        propertyBlock = new MaterialPropertyBlock();
#if UNITY_EDITOR
        EditorApplication.update -= EditorUpdate;
        EditorApplication.update += EditorUpdate;
        EditorSceneManager.sceneSaving -= OnSceneSaving;
        EditorSceneManager.sceneSaving += OnSceneSaving;
        EditorSceneManager.sceneSaved -= OnSceneSaved;
        EditorSceneManager.sceneSaved += OnSceneSaved;
        lastEditorUpdateTime = EditorApplication.timeSinceStartup;
#endif
        if (Application.isPlaying)
            InitializeIfNeeded();
    }

    private void Start()
    {
        InitializeIfNeeded();
    }

    private void Update()
    {
        if (!Application.isPlaying)
            return;

        InitializeIfNeeded();
        TickSimulation(Time.time);
    }

#if UNITY_EDITOR
    private void EditorUpdate()
    {
        if (Application.isPlaying || !isActiveAndEnabled || !previewInEditMode)
            return;

        double now = EditorApplication.timeSinceStartup;
        if (now - lastEditorUpdateTime < EditorPreviewInterval)
            return;

        float deltaTime = (float)(now - lastEditorUpdateTime);
        lastEditorUpdateTime = now;
        if (restorePreviewMeshAfterSave)
        {
            if (meshFilter != null && generatedMesh != null)
                meshFilter.sharedMesh = generatedMesh;
            restorePreviewMeshAfterSave = false;
        }

        InitializeIfNeeded();
        simulationTime += deltaTime;
        TickSimulation(simulationTime);
        SceneView.RepaintAll();
    }

    private void OnSceneSaving(UnityEngine.SceneManagement.Scene scene, string path)
    {
        if (meshFilter == null || generatedMesh == null || meshFilter.sharedMesh != generatedMesh)
            return;

        meshFilter.sharedMesh = originalMesh;
        restorePreviewMeshAfterSave = true;
    }

    private void OnSceneSaved(UnityEngine.SceneManagement.Scene scene)
    {
        restorePreviewMeshAfterSave = generatedMesh != null;
    }
#endif

    private void InitializeIfNeeded()
    {
        if (spectrumBuffer == null)
        {
            if (!ValidateConfiguration())
                return;

            InitializeSimulation();
            return;
        }

        if (resolution != initializedResolution || fftComputeShader != initializedComputeShader)
            reinitializeRequested = true;
        else
        {
            if (meshSegments != initializedMeshSegments || !Mathf.Approximately(realLength, initializedRealLength))
                meshRefreshRequested = true;
            if (!Mathf.Approximately(realLength, initializedRealLength) ||
                !Mathf.Approximately(windSpeed, initializedWindSpeed) ||
                !Mathf.Approximately(phillipsAmplitude, initializedPhillipsAmplitude) ||
                windDirection != initializedWindDirection || randomSeed != initializedRandomSeed)
                spectrumRefreshRequested = true;
        }

        if (reinitializeRequested)
        {
            ReleaseSimulation();
            reinitializeRequested = false;
            if (!ValidateConfiguration())
                return;
            InitializeSimulation();
            return;
        }

        if (spectrumRefreshRequested)
        {
            UpdateSpectrumBuffer();
            spectrumRefreshRequested = false;
        }

        if (meshRefreshRequested)
        {
            CreateWaterMesh();
            meshRefreshRequested = false;
        }
    }

    private bool ValidateConfiguration()
    {
        if (!SystemInfo.supportsComputeShaders)
        {
            Debug.LogError("FFTWaterSurface requires compute shader support.", this);
            return false;
        }

        if (fftComputeShader == null)
        {
            Debug.LogError("Assign an FFT compute shader to FFTWaterSurface.", this);
            return false;
        }

        if (originalMesh == null)
        {
            Debug.LogError("FFTWaterSurface requires a source mesh.", this);
            return false;
        }

        if (resolution < ThreadGroupSize || resolution % ThreadGroupSize != 0 ||
            (resolution & (resolution - 1)) != 0)
        {
            Debug.LogError("FFT resolution must be a power of two and a multiple of 32.", this);
            return false;
        }

        if (meshSegments < 2 || realLength <= 0f || windSpeed <= 0f)
        {
            Debug.LogError("Mesh segments must be at least 2; real length and wind speed must be positive.", this);
            return false;
        }

        return true;
    }

    private void TickSimulation(float time)
    {
        if (spectrumBuffer == null)
            return;

        simulationTime = time;
        fftComputeShader.SetFloat("_SimulationTime", simulationTime);
        fftComputeShader.SetFloat("_WaveSpeed", waveSpeed);
        fftComputeShader.SetInt("texN", resolution);
        fftComputeShader.SetInt("maxStage", Mathf.RoundToInt(Mathf.Log(resolution, 2)));

        fftComputeShader.SetBuffer(updateSpectrumKernel, "buffer", spectrumBuffer);
        fftComputeShader.SetTexture(updateSpectrumKernel, "spectrumTex", spectrumTexture);
        Dispatch(updateSpectrumKernel);

        fftComputeShader.SetTexture(horizontalBitReverseKernel, "spectrumTex", spectrumTexture);
        fftComputeShader.SetTexture(horizontalBitReverseKernel, "horizontalTexPing", horizontalPing);
        Dispatch(horizontalBitReverseKernel);

        RunFftStages(horizontalFftKernel, "horizontalTexPing", "horizontalTexPong",
            ref horizontalPing, ref horizontalPong);

        fftComputeShader.SetTexture(verticalBitReverseKernel, "horizontalTexPing", horizontalPing);
        fftComputeShader.SetTexture(verticalBitReverseKernel, "verticalTexPing", verticalPing);
        Dispatch(verticalBitReverseKernel);

        RunFftStages(verticalFftKernel, "verticalTexPing", "verticalTexPong",
            ref verticalPing, ref verticalPong);

        fftComputeShader.SetTexture(updateHeightKernel, "verticalTexPing", verticalPing);
        fftComputeShader.SetTexture(updateHeightKernel, "heightTex", heightTexture);
        Dispatch(updateHeightKernel);

        meshRenderer.GetPropertyBlock(propertyBlock);
        propertyBlock.SetTexture(WaveMapId, heightTexture);
        propertyBlock.SetFloat(HeightScaleId, waveHeight);
        propertyBlock.SetFloat(RealLengthId, realLength);
        meshRenderer.SetPropertyBlock(propertyBlock);
    }

    private void OnValidate()
    {
        resolution = Mathf.Max(ThreadGroupSize, resolution);
        meshSegments = Mathf.Max(2, meshSegments);
        realLength = Mathf.Max(1f, realLength);
        windSpeed = Mathf.Max(0.1f, windSpeed);
        waveHeight = Mathf.Max(0f, waveHeight);
        waveSpeed = Mathf.Max(0f, waveSpeed);
        phillipsAmplitude = Mathf.Max(0f, phillipsAmplitude);
    }

    private void InitializeSimulation()
    {
        updateSpectrumKernel = fftComputeShader.FindKernel("UpdateSpectrum");
        horizontalBitReverseKernel = fftComputeShader.FindKernel("IFFT_Horizontal_BitReverse");
        horizontalFftKernel = fftComputeShader.FindKernel("IFFT_Horizontal_FFT");
        verticalBitReverseKernel = fftComputeShader.FindKernel("IFFT_Vertical_BitReverse");
        verticalFftKernel = fftComputeShader.FindKernel("IFFT_Vertical_FFT");
        updateHeightKernel = fftComputeShader.FindKernel("UpdateHeight");

        spectrumTexture = CreateTexture(RenderTextureFormat.RGFloat);
        horizontalPing = CreateTexture(RenderTextureFormat.RGFloat);
        horizontalPong = CreateTexture(RenderTextureFormat.RGFloat);
        verticalPing = CreateTexture(RenderTextureFormat.RGFloat);
        verticalPong = CreateTexture(RenderTextureFormat.RGFloat);
        heightTexture = CreateTexture(RenderTextureFormat.RFloat);

        UpdateSpectrumBuffer();

        CreateWaterMesh();
        CacheConfiguration();
    }

    private void UpdateSpectrumBuffer()
    {
        if (spectrumBuffer != null)
        {
            spectrumBuffer.Release();
            spectrumBuffer = null;
        }

        SpectrumEntry[] spectrum = CreateSpectrum();
        spectrumBuffer = new ComputeBuffer(spectrum.Length, sizeof(float) * 6);
        spectrumBuffer.SetData(spectrum);
        CacheSpectrumConfiguration();
    }

    private void CacheConfiguration()
    {
        initializedResolution = resolution;
        initializedMeshSegments = meshSegments;
        initializedRealLength = realLength;
        initializedComputeShader = fftComputeShader;
        CacheSpectrumConfiguration();
    }

    private void CacheSpectrumConfiguration()
    {
        initializedRealLength = realLength;
        initializedWindSpeed = windSpeed;
        initializedPhillipsAmplitude = phillipsAmplitude;
        initializedWindDirection = windDirection;
        initializedRandomSeed = randomSeed;
    }

    private SpectrumEntry[] CreateSpectrum()
    {
        var random = new System.Random(randomSeed);
        var h0 = new Vector2[resolution * resolution];
        Vector2 normalizedWind = windDirection.sqrMagnitude > 0.0001f
            ? windDirection.normalized
            : Vector2.right;
        float waveLength = windSpeed * windSpeed / 9.8f;
        float deltaK = 2f * Mathf.PI / realLength;

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                float kx = (x - resolution / 2) * deltaK;
                float ky = (y - resolution / 2) * deltaK;
                Vector2 k = new Vector2(kx, ky);
                float kLength = k.magnitude;
                if (kLength < 0.00001f)
                    continue;

                float kWind = Vector2.Dot(k / kLength, normalizedWind);
                float kL = kLength * waveLength;
                float spectrum = phillipsAmplitude *
                    Mathf.Exp(-1f / (kL * kL)) *
                    Mathf.Pow(kWind, 2f) /
                    Mathf.Pow(kLength, 4f);

                float sigma = Mathf.Sqrt(Mathf.Max(0f, spectrum) * 0.5f);
                int index = y * resolution + x;
                h0[index] = new Vector2(NextGaussian(random) * sigma, NextGaussian(random) * sigma);
            }
        }

        var entries = new SpectrumEntry[h0.Length];
        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                int mirrorX = (resolution - x) % resolution;
                int mirrorY = (resolution - y) % resolution;
                Vector2 k = new Vector2(
                    (x - resolution / 2) * deltaK,
                    (y - resolution / 2) * deltaK);
                Vector2 h0K = h0[y * resolution + x];
                Vector2 h0NegativeK = h0[mirrorY * resolution + mirrorX];
                int index = y * resolution + x;

                entries[index].k = k;
                entries[index].coefficients = new Vector4(
                    h0K.x, h0K.y, h0NegativeK.x, -h0NegativeK.y);
            }
        }

        return entries;
    }

    private static float NextGaussian(System.Random random)
    {
        double u1 = Math.Max(random.NextDouble(), 1e-12);
        double u2 = random.NextDouble();
        return (float)(Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2));
    }

    private void CreateWaterMesh()
    {
        Bounds sourceBounds = originalMesh.bounds;
        float width = sourceBounds.size.x;
        float depth = sourceBounds.size.z;
        float tileX = width * Mathf.Abs(transform.lossyScale.x) / realLength;
        float tileY = depth * Mathf.Abs(transform.lossyScale.z) / realLength;
        int side = meshSegments + 1;
        var vertices = new Vector3[side * side];
        var uv = new Vector2[vertices.Length];
        var triangles = new int[meshSegments * meshSegments * 6];

        for (int z = 0; z <= meshSegments; z++)
        {
            for (int x = 0; x <= meshSegments; x++)
            {
                int index = z * side + x;
                float u = (float)x / meshSegments;
                float v = (float)z / meshSegments;
                vertices[index] = new Vector3(
                    Mathf.Lerp(sourceBounds.min.x, sourceBounds.max.x, u),
                    sourceBounds.center.y,
                    Mathf.Lerp(sourceBounds.min.z, sourceBounds.max.z, v));
                uv[index] = new Vector2(u * tileX, v * tileY);
            }
        }

        int triangle = 0;
        for (int z = 0; z < meshSegments; z++)
        {
            for (int x = 0; x < meshSegments; x++)
            {
                int i = z * side + x;
                triangles[triangle++] = i;
                triangles[triangle++] = i + side;
                triangles[triangle++] = i + 1;
                triangles[triangle++] = i + 1;
                triangles[triangle++] = i + side;
                triangles[triangle++] = i + side + 1;
            }
        }

        generatedMesh = new Mesh
        {
            name = originalMesh.name + " FFT Grid",
            indexFormat = IndexFormat.UInt32,
            vertices = vertices,
            uv = uv,
            triangles = triangles
        };
        generatedMesh.RecalculateNormals();
        Bounds bounds = sourceBounds;
        bounds.Expand(new Vector3(0f, Mathf.Max(waveHeight * 0.001f, 1f) /
            Mathf.Max(Mathf.Abs(transform.lossyScale.y), 0.001f), 0f));
        generatedMesh.bounds = bounds;
        meshFilter.sharedMesh = generatedMesh;
    }

    private RenderTexture CreateTexture(RenderTextureFormat format)
    {
        var texture = new RenderTexture(resolution, resolution, 0, format)
        {
            enableRandomWrite = true,
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear
        };
        texture.Create();
        return texture;
    }

    private void Dispatch(int kernel)
    {
        int groups = resolution / ThreadGroupSize;
        fftComputeShader.Dispatch(kernel, groups, groups, 1);
    }

    private void RunFftStages(int kernel, string pingName, string pongName,
        ref RenderTexture ping, ref RenderTexture pong)
    {
        int stages = Mathf.RoundToInt(Mathf.Log(resolution, 2));
        for (int stage = 1; stage <= stages; stage++)
        {
            fftComputeShader.SetInt("stage", stage);
            fftComputeShader.SetTexture(kernel, pingName, ping);
            fftComputeShader.SetTexture(kernel, pongName, pong);
            Dispatch(kernel);

            RenderTexture swap = ping;
            ping = pong;
            pong = swap;
        }
    }

    private void OnDisable()
    {
#if UNITY_EDITOR
        EditorApplication.update -= EditorUpdate;
        EditorSceneManager.sceneSaving -= OnSceneSaving;
        EditorSceneManager.sceneSaved -= OnSceneSaved;
#endif
        ReleaseSimulation();
    }

    private void ReleaseSimulation()
    {
        if (meshRenderer != null)
        {
            meshRenderer.GetPropertyBlock(propertyBlock);
            propertyBlock.SetFloat(HeightScaleId, 0f);
            meshRenderer.SetPropertyBlock(propertyBlock);
        }

        if (meshFilter != null && generatedMesh != null)
            meshFilter.sharedMesh = originalMesh;

        Release(ref spectrumBuffer);
        Release(ref spectrumTexture);
        Release(ref horizontalPing);
        Release(ref horizontalPong);
        Release(ref verticalPing);
        Release(ref verticalPong);
        Release(ref heightTexture);
        DestroyUnityObject(generatedMesh);
        generatedMesh = null;
        initializedResolution = 0;
        initializedMeshSegments = 0;
        initializedComputeShader = null;
    }

    private static void Release(ref ComputeBuffer buffer)
    {
        if (buffer == null)
            return;

        buffer.Release();
        buffer = null;
    }

    private static void Release(ref RenderTexture texture)
    {
        if (texture == null)
            return;

        texture.Release();
        DestroyUnityObject(texture);
        texture = null;
    }

    private static void DestroyUnityObject(UnityEngine.Object target)
    {
        if (target == null)
            return;

        if (Application.isPlaying)
            Destroy(target);
        else
            DestroyImmediate(target);
    }
}
