using System;
using UnityEngine;

namespace SkyboxTooling
{
    /// <summary>
    /// 天空盒图层的种类。枚举值会被写进 .asset，**不要改已有项的数值**，
    /// 否则已经存好的层栈顺序会错位。
    /// </summary>
    public enum SkyLayerType
    {
        SkyGradient = 0,
        Stars       = 1,
        Moon        = 2,
        Sun         = 3,
        CloudHigh   = 4,
        CloudLow    = 5,
        Ground      = 6,
        Horizon     = 7,
    }

    /// <summary>
    /// 一个图层的静态描述。这里是整个工具的"唯一真源"：
    /// 窗口用它画列表和参数面板，生成器用它决定调用哪个 HLSL 函数。
    /// 想加一层，只需要在这里加一条 + 在 shader 里加一个 LayerOutput LayerXxx(LayerContext)。
    /// </summary>
    [Serializable]
    public class SkyLayerDefinition
    {
        public SkyLayerType type;

        /// <summary>列表里显示的名字。</summary>
        public string displayName;

        /// <summary>shader 里对应的函数名，生成器直接拼进 LayeredSkyboxOrder.hlsl。</summary>
        public string functionName;

        /// <summary>一句话说明，显示在右侧面板顶部。</summary>
        public string summary;

        /// <summary>混合语义标签，仅用于 UI 提示。</summary>
        public string blend;

        /// <summary>排序语义警告，违反时不阻止，只在窗口里提示。</summary>
        public string warning;

        /// <summary>该层在材质上拥有的属性名。右侧参数面板按这个白名单过滤。</summary>
        public string[] properties;
    }

    public static class SkyLayerCatalog
    {
        /// <summary>默认叠放顺序（由远及近），也是新层栈的初始顺序。</summary>
        public static readonly SkyLayerType[] DefaultOrder = new SkyLayerType[]
        {
            SkyLayerType.SkyGradient,
            SkyLayerType.Stars,
            SkyLayerType.Moon,
            SkyLayerType.Sun,
            SkyLayerType.CloudHigh,
            SkyLayerType.CloudLow,
            SkyLayerType.Ground,
            SkyLayerType.Horizon,
        };

        public static readonly SkyLayerDefinition[] All = new SkyLayerDefinition[]
        {
            new SkyLayerDefinition
            {
                type = SkyLayerType.SkyGradient,
                displayName = "天空渐变",
                functionName = "LayerSky",
                summary = "白天/黄昏/夜晚三段配色，按太阳高度混合。",
                blend = "替换",
                warning = "替换式：会盖住排在它之前的所有层，通常应留在最底。",
                properties = new string[]
                {
                    "_SkyTopColor",
                    "_SkyBottomColor",
                    "_SkyTopColorDusk",
                    "_SkyBottomColorDusk",
                    "_SkyTopColorNight",
                    "_SkyBottomColorNight",
                    "_SkyGradientExponent",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.Stars,
                displayName = "星空",
                functionName = "LayerStars",
                summary = "等距柱状投影采样星点，含每颗星独立闪烁与大气消光。",
                blend = "加色",
                warning = "加色层：不会遮挡任何东西，位置基本随意。",
                properties = new string[]
                {
                    "_StarsTex",
                    "_StarMaskTex",
                    "_StarsColor",
                    "_StarsSize",
                    "_StarMaskSize",
                    "_StarsSpeed",
                    "_StarsIntensity",
                    "_StarHorizonFade",
                    "_StarTwinkle",
                    "_StarTwinkleSpeed",
                    "_NightSign",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.Moon,
                displayName = "月亮",
                functionName = "LayerMoon",
                summary = "月亮局部空间投影出的月盘（或屏幕空间方案）。",
                blend = "覆盖",
                warning = "会被“地面”盖住：若月亮在地平线以下且地面排在它前面，月亮会消失。",
                properties = new string[]
                {
                    "_MoonTex",
                    "_MoonColor",
                    "_MoonRadius",
                    "_MoonIntensity",
                    "_MoonScreenSpace",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.Sun,
                displayName = "太阳",
                functionName = "LayerSun",
                summary = "日盘（替换）+ 光晕（加色），两者合并在一个层里。",
                blend = "混合",
                warning = "会被“地面”盖住：日盘落到地平线以下时，地面需要排在它后面才遮得住。",
                properties = new string[]
                {
                    "_SunColor",
                    "_SunHaloColor",
                    "_SunHaloExponent",
                    "_SunHaloIntensity",
                    "_SunRadius",
                    "_SunDiskHQ",
                    "_SunSize",
                    "_SunSizeConvergence",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.CloudHigh,
                displayName = "云 · 高层",
                functionName = "LayerCloudHigh",
                summary = "高空薄卷云：单次采样，无自阴影/无法线，提供视差层次。",
                blend = "覆盖",
                warning = "只在平面投影模式（CLOUD_PLANAR）下有效；旧穹顶模式下该层恒为空。",
                properties = new string[]
                {
                    "_Cloud2Enable",
                    "_Cloud2Height",
                    "_Cloud2Scale",
                    "_Cloud2Coverage",
                    "_Cloud2Softness",
                    "_Cloud2Opacity",
                    "_Cloud2RotationSpeed",
                    "_Cloud2Color",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.CloudLow,
                displayName = "云 · 近层",
                functionName = "LayerCloudLow",
                summary = "平面投影积云：梯度法线 + 自阴影 + 前向散射。",
                blend = "覆盖",
                warning = "排在太阳之前会挡住日盘；放在太阳之后则日盘会盖在云上。",
                properties = new string[]
                {
                    "_CloudTex",
                    "_CloudColor",
                    "_CloudOpacity",
                    "_CloudRotationSpeed",
                    "_CloudCoverage",
                    "_CloudSoftness",
                    "_CloudWarp",
                    "_CloudMacro",
                    "_CloudMacroScale",
                    "_CloudPlanar",
                    "_CloudPlaneHeight",
                    "_CloudScale",
                    "_CloudHorizonFade",
                    "_CloudLitColor",
                    "_CloudShadowColor",
                    "_CloudSunIntensity",
                    "_CloudBumpScale",
                    "_CloudBumpOffset",
                    "_CloudShadowAbsorb",
                    "_CloudShadowFloor",
                    "_CloudShadowStep",
                    "_CloudShadowSlant",
                    "_CloudPhaseG",
                    "_CloudPhaseIntensity",
                    "_CloudHeightFade",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.Ground,
                displayName = "地面",
                functionName = "LayerGround",
                summary = "地平线以下的实心色块，亮度随昼夜变化。",
                blend = "替换",
                warning = "替换式：会把地平线以下的太阳/月亮盖住，通常应排在它们之后。",
                properties = new string[]
                {
                    "_GroundColor",
                    "_GroundSharpness",
                },
            },
            new SkyLayerDefinition
            {
                type = SkyLayerType.Horizon,
                displayName = "地平线",
                functionName = "LayerHorizon",
                summary = "沿地平线打一条亮边，模拟大气散射 / 远处雾光。",
                blend = "覆盖",
                warning = "覆盖式：排在它之后的层会盖住这条亮边，通常应放在最上层。",
                properties = new string[]
                {
                    "_HorizonColor",
                    "_HorizonLineExponent",
                    "_HorizonPower",
                    "_HorizonContribution",
                },
            },
        };

        public static SkyLayerDefinition Get(SkyLayerType type)
        {
            for (int i = 0; i < All.Length; i++)
            {
                if (All[i].type == type) return All[i];
            }
            return null;
        }

        public static string DisplayName(SkyLayerType type)
        {
            SkyLayerDefinition def = Get(type);
            return def != null ? def.displayName : type.ToString();
        }

        public static string[] AllNames
        {
            get
            {
                string[] names = new string[All.Length];
                for (int i = 0; i < All.Length; i++) names[i] = All[i].displayName;
                return names;
            }
        }
    }
}
