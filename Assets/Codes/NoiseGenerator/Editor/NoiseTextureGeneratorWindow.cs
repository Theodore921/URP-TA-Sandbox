using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

/// <summary>
/// 噪声贴图生成器窗口。算法在 Assets/Codes/NoiseTextureGenerator.cs（运行时程序集），
/// 这里只负责参数界面和导出，所以可以自由使用 UnityEditor API。
///
/// 入口：Tools ▸ Noise Texture Generator（Ctrl/Cmd + Shift + N）
///
/// 注意：参数用 [SerializeField] 直接存在 EditorWindow 上。不要把它们放进一个
/// HideFlags.HideAndDontSave 的临时 ScriptableObject —— 那种对象不参与常规序列化，
/// SerializedObject.Update() 每帧会把修改覆盖回默认值，字段看起来就是改不动的。
/// </summary>
public class NoiseTextureGeneratorWindow : EditorWindow
{
    [SerializeField] NoiseTextureGenerator.Params _params = NoiseTextureGenerator.Params.Default;
    [SerializeField] int _previewSize = 256;
    [SerializeField] bool _autoRegenerate = true;
    [SerializeField] bool _showSettings = true;

    SerializedObject _so;
    Texture2D _preview;

    [MenuItem("Tools/Noise Texture Generator %#n", false, 1000)]
    static void Open()
    {
        var win = GetWindow<NoiseTextureGeneratorWindow>("Noise Generator");
        win.minSize = new Vector2(350f, 540f);
        win.Show();
    }

    void OnEnable()
    {
        _so = new SerializedObject(this);
        Regenerate();
    }

    void OnDisable()
    {
        DestroyPreview();
    }

    void OnGUI()
    {
        _so.Update();

        if (_so.targetObject == null)
        {
            // 域重载后窗口状态丢失时的兜底
            _so = new SerializedObject(this);
            _so.Update();
        }

        _showSettings = EditorGUILayout.Foldout(_showSettings, "参数", true);
        bool changed = false;
        if (_showSettings)
        {
            EditorGUI.indentLevel++;
            changed |= Field("size");
            changed |= Field("mode");
            changed |= Field("octaves");
            changed |= Field("frequency");
            changed |= Field("persistence");
            changed |= Field("seed");
            changed |= Field("tileable");
            changed |= Field("inverse");
            changed |= Field("generateMipmaps");
            EditorGUI.indentLevel--;
        }

        // 必须先 Apply 再生成，否则预览用的是上一帧的旧参数
        _so.ApplyModifiedProperties();

        if (changed && _autoRegenerate) Regenerate();

        EditorGUILayout.Space(6f);
        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("重新生成", GUILayout.Height(26f))) Regenerate();
            if (GUILayout.Button("生成并保存 PNG…", GUILayout.Height(26f))) GenerateAndSave();
        }

        using (new EditorGUILayout.HorizontalScope())
        {
            _autoRegenerate = EditorGUILayout.ToggleLeft("改参数自动重生成", _autoRegenerate);
            GUILayout.FlexibleSpace();
            if (GUILayout.Button("重置默认值", GUILayout.Width(90f)))
            {
                _params = NoiseTextureGenerator.Params.Default;
                _so.Update();
                Regenerate();
            }
        }

        EditorGUILayout.Space(8f);
        EditorGUILayout.LabelField("预览", EditorStyles.boldLabel);
        _previewSize = EditorGUILayout.IntSlider("预览尺寸", _previewSize, 64, 512);

        if (_preview != null)
        {
            var rect = GUILayoutUtility.GetRect(_previewSize, _previewSize);
            EditorGUI.DrawPreviewTexture(rect, _preview, null, ScaleMode.ScaleToFit);
            EditorGUILayout.LabelField($"{_preview.width} × {_preview.height}", EditorStyles.miniLabel);
        }

        EditorGUILayout.Space(4f);
        EditorGUILayout.HelpBox(
            "保存出的 PNG 会以线性、不压缩、关闭 sRGB 的设置自动导入，适合当遮罩用。",
            MessageType.Info);
    }

    /// <summary>画一个字段，返回它是否被改动。</summary>
    bool Field(string name)
    {
        var prop = _so.FindProperty(name);
        if (prop == null)
        {
            EditorGUILayout.HelpBox($"找不到字段 {name}", MessageType.Warning);
            return false;
        }

        EditorGUI.BeginChangeCheck();
        EditorGUILayout.PropertyField(prop, new GUIContent(ObjectNames.NicifyVariableName(name)), true);
        return EditorGUI.EndChangeCheck();
    }

    void Regenerate()
    {
        DestroyPreview();
        _preview = NoiseTextureGenerator.Generate(_params);
        Repaint();
    }

    void GenerateAndSave()
    {
        string path = EditorUtility.SaveFilePanelInProject(
            "保存噪声贴图", $"noise_{_params.mode}_{_params.size}", "png",
            "选择保存位置");
        if (string.IsNullOrEmpty(path)) return;

        // 不在 OnGUI 事件里做生成和文件写入，避免 GUI 事件期间出问题
        EditorApplication.delayCall += () => SaveTo(path);
    }

    void SaveTo(string path)
    {
        var tex = NoiseTextureGenerator.Generate(_params);
        File.WriteAllBytes(path, tex.EncodeToPNG());
        DestroyImmediate(tex);
        AssetDatabase.Refresh();
        ApplyMaskImportSettings(path, _params.tileable);

        var saved = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        if (saved != null) EditorGUIUtility.PingObject(saved);
        Regenerate();
    }

    /// <summary>把导入设置调成适合当遮罩用的状态。</summary>
    internal static void ApplyMaskImportSettings(string path, bool tileable)
    {
        var importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer == null) return;

        importer.textureType = TextureImporterType.Default;
        importer.sRGBTexture = false;                  // 关键：遮罩必须是线性数据
        importer.mipmapEnabled = false;
        importer.textureCompression = TextureImporterCompression.Uncompressed;
        importer.wrapMode = tileable ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
        importer.SaveAndReimport();
    }

    void DestroyPreview()
    {
        if (_preview != null)
        {
            DestroyImmediate(_preview);
            _preview = null;
        }
    }
}
