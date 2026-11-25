using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEditorInternal;
using UnityEngine;

namespace SkyboxTooling
{
    /// <summary>
    /// 天空盒图层控制面板。
    ///
    /// 左侧：可拖动排序的图层列表 + 启用开关。
    /// 右侧：选中图层的参数（直接读写目标材质，属性名与 shader 完全一致）。
    /// 顶部：同步状态灯 + 重新生成。
    ///
    /// 排序是"编译期"的：改动顺序后生成 LayeredSkyboxOrder.hlsl，
    /// shader 会重新编译。开关同理——关掉的层会从生成代码里消失。
    /// </summary>
    public class SkyboxLayerStackWindow : EditorWindow
    {
        [SerializeField] SkyLayerStack stack;
        [SerializeField] bool autoGenerate = true;

        SerializedObject serializedStack;
        SerializedProperty layersProp;
        ReorderableList list;

        Vector2 paramScroll;
        int selectedIndex;
        string lastError;

        bool generateQueued;
        GUIStyle richMini;

        /// <summary>需要画成开关（0/1）的浮点属性。其余浮点按普通输入框/滑条画。</summary>
        static readonly HashSet<string> ToggleProps = new HashSet<string>
        {
            "_MoonScreenSpace",
            "_SunDiskHQ",
            "_CloudPlanar",
            "_Cloud2Enable",
        };

        [MenuItem("Window/Skybox/Layer Stack", false, 1000)]
        public static void Open()
        {
            SkyboxLayerStackWindow window = GetWindow<SkyboxLayerStackWindow>("Skybox Layer Stack");
            window.minSize = new Vector2(760f, 460f);
            window.Show();
        }

        void OnEnable()
        {
            // ⚠ 不要在这里创建 GUIStyle：域重载后 EditorStyles 尚未初始化，
            // 访问 EditorStyles.miniLabel 会抛 NullReferenceException。
            // 样式统一在 OnGUI 里惰性创建（见 EnsureStyles）。
            if (stack == null) stack = FindStack();
            if (stack != null) Rebuild();

            if (stack != null && autoGenerate && !SkyboxLayerGenerator.IsUpToDate(stack))
                RequestGenerate();
        }

        /// <summary>惰性创建 GUIStyle。只在 OnGUI 期间调用。</summary>
        void EnsureStyles()
        {
            if (richMini != null) return;
            GUIStyle baseStyle = EditorStyles.miniLabel;
            if (baseStyle == null) return;
            richMini = new GUIStyle(baseStyle) { richText = true };
        }

        void OnDisable()
        {
            EditorApplication.delayCall -= DoQueuedGenerate;
            generateQueued = false;
        }

        // ─────────────────────────────────────────────────────────────
        //  发现 / 重建
        // ─────────────────────────────────────────────────────────────

        static SkyLayerStack FindStack()
        {
            string[] guids;
            try { guids = AssetDatabase.FindAssets("t:SkyLayerStack"); }
            catch { return null; }

            if (guids == null || guids.Length == 0) return null;
            return AssetDatabase.LoadAssetAtPath<SkyLayerStack>(AssetDatabase.GUIDToAssetPath(guids[0]));
        }

        void Rebuild()
        {
            if (stack == null)
            {
                serializedStack = null;
                layersProp = null;
                list = null;
                return;
            }

            serializedStack = new SerializedObject(stack);
            layersProp = serializedStack.FindProperty("layers");

            list = new ReorderableList(serializedStack, layersProp, true, true, true, true);
            list.elementHeight = EditorGUIUtility.singleLineHeight + 8f;
            list.drawHeaderCallback = DrawListHeader;
            list.drawElementCallback = DrawListElement;
            list.onSelectCallback = OnSelectLayer;
            list.onReorderCallback = OnReorder;
            list.onAddCallback = OnAddLayer;
            list.onRemoveCallback = OnRemoveLayer;
            list.onCanRemoveCallback = CanRemoveLayer;
        }

        // ─────────────────────────────────────────────────────────────
        //  列表
        // ─────────────────────────────────────────────────────────────

        void DrawListHeader(Rect rect)
        {
            EditorGUI.LabelField(rect, "图层（上 → 下 = 由远及近，拖动左侧把手排序）", EditorStyles.boldLabel);
        }

        void DrawListElement(Rect rect, int index, bool isActive, bool isFocused)
        {
            if (layersProp == null || index < 0 || index >= layersProp.arraySize) return;

            SerializedProperty element = layersProp.GetArrayElementAtIndex(index);
            SerializedProperty typeProp = element.FindPropertyRelative("type");
            SerializedProperty enabledProp = element.FindPropertyRelative("enabled");

            float lineHeight = EditorGUIUtility.singleLineHeight;
            float y = rect.y + 4f;

            // 启用开关
            Rect toggleRect = new Rect(rect.x, y, 16f, lineHeight);
            bool enabled = EditorGUI.Toggle(toggleRect, enabledProp.boolValue);
            if (enabled != enabledProp.boolValue)
            {
                enabledProp.boolValue = enabled;
                ApplyAndSync();
            }

            SkyLayerType type = (SkyLayerType)typeProp.enumValueIndex;
            SkyLayerDefinition def = SkyLayerCatalog.Get(type);
            string label = def != null ? def.displayName : type.ToString();

            // 名字（关掉时变灰）
            Rect labelRect = new Rect(toggleRect.xMax + 6f, y, rect.width - 90f, lineHeight);
            Color prev = GUI.color;
            if (!enabledProp.boolValue) GUI.color = new Color(1f, 1f, 1f, 0.45f);
            EditorGUI.LabelField(labelRect, label);
            GUI.color = prev;

            // 混合语义标签
            Rect tagRect = new Rect(rect.xMax - 64f, y, 60f, lineHeight);
            Color tagPrev = GUI.color;
            GUI.color = new Color(1f, 1f, 1f, enabledProp.boolValue ? 0.6f : 0.25f);
            EditorGUI.LabelField(tagRect, def != null ? def.blend : string.Empty, EditorStyles.miniLabel);
            GUI.color = tagPrev;
        }

        void OnSelectLayer(ReorderableList l)
        {
            selectedIndex = l.index;
            Repaint();
        }

        void OnReorder(ReorderableList l)
        {
            selectedIndex = l.index;
            ApplyAndSync();
        }

        bool CanRemoveLayer(ReorderableList l)
        {
            return layersProp != null && layersProp.arraySize > 1;
        }

        void OnAddLayer(ReorderableList l)
        {
            if (serializedStack == null) return;

            SkyLayerType unused;
            if (!stack.TryGetUnusedType(out unused))
            {
                lastError = "所有图层都已在列表里，不能重复添加。";
                return;
            }
            lastError = null;

            serializedStack.Update();
            layersProp.InsertArrayElementAtIndex(layersProp.arraySize);
            SerializedProperty element = layersProp.GetArrayElementAtIndex(layersProp.arraySize - 1);
            element.FindPropertyRelative("type").enumValueIndex = (int)unused;
            element.FindPropertyRelative("enabled").boolValue = true;
            serializedStack.ApplyModifiedProperties();

            SyncListCount();
            selectedIndex = layersProp.arraySize - 1;
            ApplyAndSync();
        }

        void OnRemoveLayer(ReorderableList l)
        {
            if (serializedStack == null || layersProp == null) return;
            if (l.index < 0 || l.index >= layersProp.arraySize) return;

            serializedStack.Update();
            layersProp.DeleteArrayElementAtIndex(l.index);
            serializedStack.ApplyModifiedProperties();

            SyncListCount();
            selectedIndex = Mathf.Clamp(l.index, 0, Mathf.Max(0, layersProp.arraySize - 1));
            ApplyAndSync();
        }

        void SyncListCount()
        {
            // ReorderableList.count 是只读的：它每帧从 serializedProperty.arraySize 同步，
            // 所以数组增删之后只要把选中项夹回合法范围，不需要手动改 count。
            if (list == null || layersProp == null) return;
            if (list.index >= layersProp.arraySize) list.index = layersProp.arraySize - 1;
        }

        // ─────────────────────────────────────────────────────────────
        //  面板
        // ─────────────────────────────────────────────────────────────

        void OnGUI()
        {
            EnsureStyles();

            DrawToolbar();
            EditorGUILayout.Space(2f);

            if (stack == null)
            {
                EditorGUILayout.HelpBox(
                    "没有找到 SkyLayerStack 资源。\n" +
                    "点下面的按钮创建一个（默认顺序，全部启用），或者把已有的层栈拖到上面的槽里。",
                    MessageType.Warning);

                if (GUILayout.Button("新建层栈资源", GUILayout.Height(24f)))
                    CreateStackAsset();

                return;
            }

            if (serializedStack == null || layersProp == null || list == null) Rebuild();
            if (serializedStack == null) return;

            serializedStack.Update();

            EditorGUILayout.BeginHorizontal();

            EditorGUILayout.BeginVertical(GUILayout.Width(position.width * 0.40f));
            list.DoLayoutList();
            DrawWarnings();
            EditorGUILayout.EndVertical();

            GUILayout.Space(6f);

            EditorGUILayout.BeginVertical();
            DrawSelectedLayerParams();
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndHorizontal();

            DrawFooter();
        }

        void DrawToolbar()
        {
            EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);

            EditorGUI.BeginChangeCheck();
            SkyLayerStack newStack = (SkyLayerStack)EditorGUILayout.ObjectField(
                stack, typeof(SkyLayerStack), false, GUILayout.Width(200f));
            if (EditorGUI.EndChangeCheck())
            {
                stack = newStack;
                if (stack != null) Rebuild();
                GenerateNow(false);
            }

            if (stack != null)
            {
                EditorGUI.BeginChangeCheck();
                Material newMaterial = (Material)EditorGUILayout.ObjectField(
                    stack.material, typeof(Material), false, GUILayout.Width(200f));
                if (EditorGUI.EndChangeCheck())
                {
                    Undo.RecordObject(stack, "Set Skybox Material");
                    stack.material = newMaterial;
                    EditorUtility.SetDirty(stack);
                }

                GUILayout.FlexibleSpace();
                DrawStatusLight();

                GUILayout.Space(8f);
                using (new EditorGUI.DisabledScope(EditorApplication.isPlaying))
                {
                    if (GUILayout.Button("重新生成", EditorStyles.toolbarButton, GUILayout.Width(70f)))
                        GenerateNow(true);
                }

                autoGenerate = GUILayout.Toggle(autoGenerate, "自动", EditorStyles.toolbarButton, GUILayout.Width(46f));

                if (GUILayout.Button("修复列表", EditorStyles.toolbarButton, GUILayout.Width(64f)))
                {
                    Undo.RecordObject(stack, "Repair Skybox Layer List");
                    if (stack.Repair()) EditorUtility.SetDirty(stack);
                    Rebuild();
                    GenerateNow(true);
                }

                if (GUILayout.Button("恢复默认", EditorStyles.toolbarButton, GUILayout.Width(64f)))
                {
                    Undo.RecordObject(stack, "Reset Skybox Layer Order");
                    stack.ResetToDefault();
                    EditorUtility.SetDirty(stack);
                    Rebuild();
                    GenerateNow(true);
                }
            }
            else
            {
                GUILayout.FlexibleSpace();
            }

            EditorGUILayout.EndHorizontal();
        }

        void DrawStatusLight()
        {
            if (stack == null) return;

            if (EditorApplication.isPlaying)
            {
                GUILayout.Label("● Play 模式下不生成", richMini, GUILayout.Width(120f));
                return;
            }

            if (SkyboxLayerGenerator.IsUpToDate(stack))
                GUILayout.Label(SkyboxLayerGenerator.Colored("● 已同步", "6BCB77"), richMini, GUILayout.Width(70f));
            else
                GUILayout.Label(SkyboxLayerGenerator.Colored("● 待生成", "FFC93C"), richMini, GUILayout.Width(70f));
        }

        void DrawWarnings()
        {
            List<string> problems = stack.Validate();
            for (int i = 0; i < problems.Count; i++)
            {
                if (i > 3) break;   // 别把窗口撑爆
                EditorGUILayout.HelpBox(problems[i], MessageType.Warning);
            }
        }

        void DrawSelectedLayerParams()
        {
            if (stack.material == null)
            {
                EditorGUILayout.HelpBox(
                    "还没有指定目标材质。\n上面那个材质槽应该指向使用 Skybox/LayeredSkybox 的材质。",
                    MessageType.Info);
                return;
            }

            if (stack.layers == null || stack.layers.Count == 0)
            {
                EditorGUILayout.HelpBox("层栈是空的。", MessageType.Info);
                return;
            }

            selectedIndex = Mathf.Clamp(selectedIndex, 0, stack.layers.Count - 1);
            SkyLayerEntry entry = stack.layers[selectedIndex];
            SkyLayerDefinition def = SkyLayerCatalog.Get(entry.type);
            if (def == null) return;

            EditorGUILayout.LabelField(def.displayName + "  —  参数（写入材质）", EditorStyles.boldLabel);
            if (!string.IsNullOrEmpty(def.summary))
                EditorGUILayout.HelpBox(def.summary, MessageType.None);

            if (stack.material.shader == null || stack.material.shader.name != "Skybox/LayeredSkybox")
            {
                EditorGUILayout.HelpBox(
                    "当前材质的 shader 是 " + (stack.material.shader != null ? stack.material.shader.name : "null") +
                    "，不是 Skybox/LayeredSkybox。参数名可能对不上。",
                    MessageType.Warning);
            }

            paramScroll = EditorGUILayout.BeginScrollView(paramScroll);
            DrawMaterialProperties(stack.material, def);
            EditorGUILayout.EndScrollView();
        }

        void DrawFooter()
        {
            if (!string.IsNullOrEmpty(lastError))
                EditorGUILayout.HelpBox(lastError, MessageType.Error);

            EditorGUILayout.LabelField(SampleBudget(), EditorStyles.miniLabel);
        }

        // ─────────────────────────────────────────────────────────────
        //  材质属性绘制（用 ShaderUtil 而不是 MaterialEditor，才能按层过滤）
        // ─────────────────────────────────────────────────────────────

        void DrawMaterialProperties(Material material, SkyLayerDefinition def)
        {
            Shader shader = material.shader;
            if (shader == null || def == null || def.properties == null) return;

            int count = ShaderUtil.GetPropertyCount(shader);
            for (int i = 0; i < count; i++)
            {
                string propertyName = ShaderUtil.GetPropertyName(shader, i);
                if (Array.IndexOf(def.properties, propertyName) < 0) continue;
                DrawOneProperty(material, shader, i, propertyName);
            }
        }

        void DrawOneProperty(Material material, Shader shader, int index, string propertyName)
        {
            string description = ShaderUtil.GetPropertyDescription(shader, index);
            if (string.IsNullOrEmpty(description)) description = propertyName;
            GUIContent label = new GUIContent(description, propertyName);

            ShaderUtil.ShaderPropertyType type = ShaderUtil.GetPropertyType(shader, index);

            if (type == ShaderUtil.ShaderPropertyType.TexEnv)
            {
                EditorGUI.BeginChangeCheck();
                Texture texture = EditorGUILayout.ObjectField(
                    label, material.GetTexture(propertyName), typeof(Texture), false) as Texture;
                if (EditorGUI.EndChangeCheck())
                {
                    Undo.RecordObject(material, "Skybox " + propertyName);
                    material.SetTexture(propertyName, texture);
                    EditorUtility.SetDirty(material);
                }
                return;
            }

            if (type == ShaderUtil.ShaderPropertyType.Color)
            {
                EditorGUI.BeginChangeCheck();
                Color color = EditorGUILayout.ColorField(label, material.GetColor(propertyName));
                if (EditorGUI.EndChangeCheck())
                {
                    Undo.RecordObject(material, "Skybox " + propertyName);
                    material.SetColor(propertyName, color);
                    EditorUtility.SetDirty(material);
                }
                return;
            }

            if (type == ShaderUtil.ShaderPropertyType.Vector)
            {
                EditorGUI.BeginChangeCheck();
                Vector4 vector = EditorGUILayout.Vector4Field(description, material.GetVector(propertyName));
                if (EditorGUI.EndChangeCheck())
                {
                    Undo.RecordObject(material, "Skybox " + propertyName);
                    material.SetVector(propertyName, vector);
                    EditorUtility.SetDirty(material);
                }
                return;
            }

            if (type == ShaderUtil.ShaderPropertyType.Float || type == ShaderUtil.ShaderPropertyType.Range)
            {
                bool isToggle = ToggleProps.Contains(propertyName);

                if (isToggle)
                {
                    EditorGUI.BeginChangeCheck();
                    bool on = EditorGUILayout.Toggle(label, material.GetFloat(propertyName) > 0.5f);
                    if (EditorGUI.EndChangeCheck())
                        WriteFloat(material, propertyName, on ? 1f : 0f);
                    return;
                }

                if (type == ShaderUtil.ShaderPropertyType.Range)
                {
                    // 用引擎侧 API 取区间：ShaderUtil.GetRangeLimits 的重载在 2021.3 里
                    // 只有 (Shader,int,int) 一个，会抛 "Property type is not Range"，
                    // 而 Shader.GetPropertyRangeLimits(index) 是稳定可用的。
                    Vector2 limits = shader.GetPropertyRangeLimits(index);

                    EditorGUI.BeginChangeCheck();
                    float value = EditorGUILayout.Slider(label, material.GetFloat(propertyName), limits.x, limits.y);
                    if (EditorGUI.EndChangeCheck()) WriteFloat(material, propertyName, value);
                    return;
                }

                EditorGUI.BeginChangeCheck();
                float plain = EditorGUILayout.FloatField(label, material.GetFloat(propertyName));
                if (EditorGUI.EndChangeCheck()) WriteFloat(material, propertyName, plain);
                return;
            }

            EditorGUILayout.LabelField(description, "（此类型暂不支持在此编辑）");
        }

        void WriteFloat(Material material, string propertyName, float value)
        {
            Undo.RecordObject(material, "Skybox " + propertyName);
            material.SetFloat(propertyName, value);
            EditorUtility.SetDirty(material);
        }

        // ─────────────────────────────────────────────────────────────
        //  生成调度
        // ─────────────────────────────────────────────────────────────

        void ApplyAndSync()
        {
            if (serializedStack == null) return;

            serializedStack.ApplyModifiedProperties();
            EditorUtility.SetDirty(stack);
            RequestGenerate();
            Repaint();
        }

        void RequestGenerate()
        {
            if (!autoGenerate) return;
            if (EditorApplication.isPlaying) return;
            if (generateQueued) return;

            generateQueued = true;
            EditorApplication.delayCall += DoQueuedGenerate;
        }

        void DoQueuedGenerate()
        {
            EditorApplication.delayCall -= DoQueuedGenerate;
            generateQueued = false;

            if (this == null || stack == null) return;
            if (EditorApplication.isPlaying) return;

            GenerateNow(false);
        }

        void GenerateNow(bool logToConsole)
        {
            if (stack == null) return;

            string error = SkyboxLayerGenerator.Generate(stack, logToConsole);
            lastError = error;

            if (error == null && logToConsole) SceneView.RepaintAll();
            Repaint();
        }

        // ─────────────────────────────────────────────────────────────
        //  杂项
        // ─────────────────────────────────────────────────────────────

        void CreateStackAsset()
        {
            string path = EditorUtility.SaveFilePanelInProject(
                "创建天空盒层栈", "SkyLayerStack", "asset", "选择保存位置");

            if (string.IsNullOrEmpty(path)) return;

            SkyLayerStack created = CreateInstance<SkyLayerStack>();
            created.ResetToDefault();

            AssetDatabase.CreateAsset(created, path);
            AssetDatabase.SaveAssets();

            stack = created;
            Rebuild();
            GenerateNow(true);
            EditorGUIUtility.PingObject(created);
        }

        /// <summary>粗略统计：改动顺序后能直观看到"这一层值多少次采样"。</summary>
        string SampleBudget()
        {
            if (stack == null) return string.Empty;

            int samples = 0;
            int enabledCount = 0;
            List<SkyLayerType> enabledTypes = stack.EnabledTypes();

            for (int i = 0; i < enabledTypes.Count; i++)
            {
                enabledCount++;
                switch (enabledTypes[i])
                {
                    case SkyLayerType.Stars:     samples += 2; break;   // 星点 + 遮罩
                    case SkyLayerType.Moon:      samples += 1; break;
                    case SkyLayerType.CloudHigh: samples += 1; break;
                    case SkyLayerType.CloudLow:  samples += 8; break;   // 中心+2 梯度+1 宏观+4 自阴影
                    default: break;
                }
            }

            return "启用 " + enabledCount + " 层 / 约 " + samples + " 次纹理采样每像素"
                 + "（不含散射相位等纯数学运算）";
        }
    }
}
