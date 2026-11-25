using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;

namespace SkyboxTooling
{
    /// <summary>层栈里的一项：图层类型 + 是否启用。参数不在这里，参数在材质上。</summary>
    [Serializable]
    public class SkyLayerEntry
    {
        public SkyLayerType type = SkyLayerType.SkyGradient;
        public bool enabled = true;
    }

    /// <summary>
    /// 天空盒层栈：只保存「顺序 + 开关」和「目标材质」。
    ///
    /// 为什么不把参数也搬进来：
    ///   SkyTimeOfDay / StylizedSkyboxMoonDriver 等脚本是靠 material.SetFloat 驱动参数的，
    ///   参数留在材质上，这些脚本一行都不用改；而且材质本身就是天空盒的最终使用方。
    /// </summary>
    [CreateAssetMenu(fileName = "SkyLayerStack", menuName = "Skybox/Layer Stack", order = 0)]
    public class SkyLayerStack : ScriptableObject
    {
        [Tooltip("要应用图层顺序的天空盒材质。参数面板也读写这个材质。")]
        public Material material;

        [Tooltip("从上到下 = 由远及近。列表顺序就是 shader 里的调用顺序。")]
        public List<SkyLayerEntry> layers = new List<SkyLayerEntry>();

        /// <summary>启用中的层，按当前顺序返回类型。生成器与状态检查都以此为准。</summary>
        public List<SkyLayerType> EnabledTypes()
        {
            List<SkyLayerType> result = new List<SkyLayerType>(layers.Count);
            for (int i = 0; i < layers.Count; i++)
            {
                if (layers[i] != null && layers[i].enabled) result.Add(layers[i].type);
            }
            return result;
        }

        /// <summary>
        /// 生成状态签名：形如 "0,1,2,3,4,5,6,7"。
        /// 只记录启用中的层 —— 关掉的层不产生代码，所以它的位置无关，
        /// 两个只有"关闭层位置不同"的配置得到同一个签名，这是正确的。
        /// </summary>
        public string Signature()
        {
            List<SkyLayerType> enabledTypes = EnabledTypes();
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < enabledTypes.Count; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append((int)enabledTypes[i]);
            }
            return sb.ToString();
        }

        /// <summary>恢复成默认顺序，全部启用。</summary>
        public void ResetToDefault()
        {
            layers.Clear();
            for (int i = 0; i < SkyLayerCatalog.DefaultOrder.Length; i++)
            {
                layers.Add(new SkyLayerEntry
                {
                    type = SkyLayerCatalog.DefaultOrder[i],
                    enabled = true,
                });
            }
        }

        /// <summary>
        /// 自检并修复：去重（保留先出现的那个），补齐缺失的层（按默认顺序追加到末尾）。
        /// 用于"新增了一种图层类型"或"手动改坏了列表"的情况。
        /// 返回是否做过修改。
        /// </summary>
        public bool Repair()
        {
            bool changed = false;

            if (layers == null)
            {
                layers = new List<SkyLayerEntry>();
                changed = true;
            }

            // 去掉空项和重复项
            HashSet<SkyLayerType> seen = new HashSet<SkyLayerType>();
            for (int i = layers.Count - 1; i >= 0; i--)
            {
                SkyLayerEntry entry = layers[i];
                if (entry == null)
                {
                    layers.RemoveAt(i);
                    changed = true;
                    continue;
                }
                if (!seen.Add(entry.type))
                {
                    layers.RemoveAt(i);
                    changed = true;
                }
            }

            // 补齐缺失项
            for (int i = 0; i < SkyLayerCatalog.DefaultOrder.Length; i++)
            {
                SkyLayerType type = SkyLayerCatalog.DefaultOrder[i];
                if (!seen.Contains(type))
                {
                    layers.Add(new SkyLayerEntry { type = type, enabled = true });
                    changed = true;
                }
            }

            return changed;
        }

        /// <summary>校验：返回需要提示给用户的问题（空列表 = 没问题）。</summary>
        public List<string> Validate()
        {
            List<string> problems = new List<string>();

            if (material == null)
                problems.Add("还没有指定目标材质。");

            if (layers == null || layers.Count == 0)
            {
                problems.Add("层栈是空的，生成出来会是一整片黑色。");
                return problems;
            }

            int enabledCount = EnabledTypes().Count;
            if (enabledCount == 0)
                problems.Add("所有图层都被关掉了，生成出来会是一整片黑色。");

            // 顺序语义提示
            int skyIndex = IndexOf(SkyLayerType.SkyGradient);
            if (skyIndex >= 0 && IsEnabled(SkyLayerType.SkyGradient) && skyIndex > 0)
                problems.Add("「天空渐变」是替换式，放在第 " + (skyIndex + 1) + " 位会盖住它上面所有层。");

            int groundIndex = IndexOf(SkyLayerType.Ground);
            if (groundIndex >= 0 && IsEnabled(SkyLayerType.Ground))
            {
                int sunIndex = IndexOf(SkyLayerType.Sun);
                int moonIndex = IndexOf(SkyLayerType.Moon);
                if ((IsEnabled(SkyLayerType.Sun) && sunIndex > groundIndex) ||
                    (IsEnabled(SkyLayerType.Moon) && moonIndex > groundIndex))
                {
                    problems.Add("「地面」排在太阳/月亮之前，地平线以下的日盘和月盘会浮在地面之上。");
                }
            }

            return problems;
        }

        public int IndexOf(SkyLayerType type)
        {
            if (layers == null) return -1;
            for (int i = 0; i < layers.Count; i++)
            {
                if (layers[i] != null && layers[i].type == type) return i;
            }
            return -1;
        }

        public bool IsEnabled(SkyLayerType type)
        {
            int index = IndexOf(type);
            return index >= 0 && layers[index].enabled;
        }

        /// <summary>第一个还没被用到的图层类型；全都用上了就返回 false。</summary>
        public bool TryGetUnusedType(out SkyLayerType unusedType)
        {
            for (int i = 0; i < SkyLayerCatalog.DefaultOrder.Length; i++)
            {
                SkyLayerType candidate = SkyLayerCatalog.DefaultOrder[i];
                if (IndexOf(candidate) < 0)
                {
                    unusedType = candidate;
                    return true;
                }
            }
            unusedType = SkyLayerType.SkyGradient;
            return false;
        }
    }
}
