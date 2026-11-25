using System.Collections.Generic;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace SkyboxTooling
{
    /// <summary>
    /// 把层栈编译成一段 HLSL，写进 LayeredSkyboxOrder.hlsl。
    ///
    /// 为什么用"代码生成"而不是运行时数组循环：
    ///   · 各层参数高度异构（近层云 20 多个），塞不进统一的 uniform 数组；
    ///   · 天空盒是全屏像素，静态展开后每层互不干扰，寄存器压力小；
    ///   · 关掉的层会真正从代码里消失，不只是跳过分支。
    ///
    /// 生成物只有 8 行调用，不含任何层的实现 —— 层实现永远留在手写的 shader 里，
    /// 所以生成器不可能覆盖你手写的代码。
    /// </summary>
    public static class SkyboxLayerGenerator
    {
        public const string ShaderPath = "Assets/Shaders/Skybox/LayeredSkybox.shader";
        public const string OrderPath  = "Assets/Shaders/Skybox/LayeredSkyboxOrder.hlsl";

        /// <summary>生成状态行的前缀，用于回读"当前文件是按什么顺序生成的"。</summary>
        const string SignaturePrefix = "//  生成状态: order=";

        const string IncludeExpect = "#include \"LayeredSkyboxOrder.hlsl\"";

        const int SeparatorWidth = 76;

        /// <summary>把层栈拼成 include 文件的完整内容。</summary>
        public static string BuildText(SkyLayerStack stack)
        {
            List<SkyLayerType> enabledTypes = stack != null ? stack.EnabledTypes() : new List<SkyLayerType>();
            string separator = "// " + new string('=', SeparatorWidth);

            StringBuilder sb = new StringBuilder();
            sb.Append(separator).Append('\n');
            sb.Append("//  LayeredSkyboxOrder.hlsl —— 天空盒图层顺序（自动生成，请勿手改）\n");
            sb.Append("//\n");
            sb.Append("//  生成器：Assets/Editor/Skybox/SkyboxLayerGenerator.cs\n");
            sb.Append("//  入口  ：Window > Skybox > Layer Stack\n");
            sb.Append("//  被包含：Assets/Shaders/Skybox/LayeredSkybox.shader\n");
            sb.Append("//\n");
            sb.Append("//  这个文件只负责\"按什么顺序调用哪些层\"，不含任何层的实现。\n");
            sb.Append("//  层的实现都在 LayeredSkybox.shader 里，参数都在材质上。\n");
            sb.Append("//  想改顺序或开关某层，请用上面那个窗口，改完点「重新生成」。\n");
            sb.Append("//\n");
            sb.Append(SignaturePrefix).Append(stack != null ? stack.Signature() : string.Empty).Append('\n');
            sb.Append(separator).Append('\n');
            sb.Append('\n');
            sb.Append("void ComposeLayerStack(inout half3 color, LayerContext ctx)\n");
            sb.Append("{\n");

            if (enabledTypes.Count == 0)
            {
                sb.Append("    // 层栈里没有任何启用的图层：保持传入的颜色不变（默认是黑色）。\n");
            }

            for (int i = 0; i < enabledTypes.Count; i++)
            {
                SkyLayerDefinition def = SkyLayerCatalog.Get(enabledTypes[i]);
                string fn = def != null ? def.functionName : "LayerSky";
                sb.Append("    color = ComposeLayer(color, ").Append(fn).Append("(ctx));\n");
            }

            sb.Append("}\n");
            return sb.ToString();
        }

        /// <summary>回读生成文件里的顺序签名；文件不存在或格式不对时返回 null。</summary>
        public static string ReadGeneratedSignature()
        {
            if (!System.IO.File.Exists(OrderPath)) return null;

            string[] lines = System.IO.File.ReadAllLines(OrderPath);
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i].TrimEnd();
                if (line.StartsWith(SignaturePrefix))
                    return line.Substring(SignaturePrefix.Length).Trim();
            }
            return null;
        }

        /// <summary>当前文件是否已经与层栈一致。</summary>
        public static bool IsUpToDate(SkyLayerStack stack)
        {
            if (stack == null) return false;
            string generated = ReadGeneratedSignature();
            if (generated == null) return false;
            return generated == stack.Signature();
        }

        /// <summary>
        /// 生成并落盘。返回 null 表示成功，否则返回给用户看的错误信息。
        /// </summary>
        public static string Generate(SkyLayerStack stack, bool logToConsole)
        {
            if (stack == null) return "层栈为空。";

            if (!System.IO.File.Exists(ShaderPath))
                return "找不到 shader：" + ShaderPath;

            // 防止有人把 include 删掉后还在困惑"为什么重新生成没反应"
            string shaderText = System.IO.File.ReadAllText(ShaderPath);
            if (shaderText.IndexOf(IncludeExpect, System.StringComparison.Ordinal) < 0)
            {
                return "shader 里找不到 " + IncludeExpect + "\n"
                     + "生成器只会写 include 文件，不会改写 shader，请先把这一行加回去。";
            }

            string text = BuildText(stack);

            // 内容没变就不写盘，避免无意义的 shader 重编译
            bool changed = true;
            if (System.IO.File.Exists(OrderPath))
                changed = System.IO.File.ReadAllText(OrderPath) != text;

            if (changed)
            {
                System.IO.File.WriteAllText(OrderPath, text, new UTF8Encoding(false));

                // include 文件的改动不一定触发 .shader 重新导入，这里强制一次
                AssetDatabase.ImportAsset(OrderPath, ImportAssetOptions.ForceUpdate);
                AssetDatabase.ImportAsset(ShaderPath, ImportAssetOptions.ForceUpdate);

                if (logToConsole)
                    Debug.Log("[Skybox] 已重新生成图层顺序：" + (stack.Signature().Length > 0 ? stack.Signature() : "(空)")
                              + "\n→ " + OrderPath);
            }

            return null;
        }

        /// <summary>把一段文字包成 Unity 的富文本着色，供窗口里的状态灯使用。</summary>
        public static string Colored(string text, string hex)
        {
            return "<color=#" + hex + ">" + text + "</color>";
        }
    }
}
