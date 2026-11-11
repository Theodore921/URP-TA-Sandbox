Shader "Custom/URP_StaticInstancedFur"
{
    Properties
    {
        [Header(Color Settings)]
        _BaseColor ("Base Color (Root)", Color) = (0.1, 0.05, 0.02, 1)
        _FurColor ("Fur Tip Color", Color) = (0.8, 0.4, 0.1, 1)
        
        [Header(Shape and Density)]
        _NoiseTex ("Fur Noise Mask", 2D) = "white" {}
        _NoiseTiling ("Noise Tiling (Global Multiplier)", Float) = 30.0
        _MaxDensity ("Global Max Density", Range(0.0, 1.0)) = 1.0 
        _Density ("Root Density (Base)", Range(0.0, 1.0)) = 1.0
        _TipCutoff ("Tip Thinness (Cutoff)", Range(0.0, 1.0)) = 0.9
        _ThicknessCurve ("Taper Curve (Root to Tip)", Range(0.1, 5.0)) = 1.5
        
        [Header(Fur Length)]
        _FurLength ("Max Fur Length (Global)", Float) = 0.2
        _LengthMap ("Length Mask (R Channel)", 2D) = "white" {} 
        
        [Header(Physics and Natural)]
        _Gravity ("Gravity / Droop", Range(0.0, 1.0)) = 0.2 
        _Messiness ("Messiness (Tangle/Curl)", Range(0.0, 1.0)) = 0.3
        _CombDir ("Comb Direction (X, Y, Z)", Vector) = (0.0, -0.5, 0.5, 0.0) 
    }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }
        Cull Off 

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing // 必须开启以支持 GPU Instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalWS     : NORMAL;
                float layerRatio    : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);
            TEXTURE2D(_LengthMap); SAMPLER(sampler_LengthMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _FurColor;
                float4 _NoiseTex_ST; 
                float4 _LengthMap_ST; 
                float _NoiseTiling;
                float _MaxDensity;    
                float _Density;
                float _TipCutoff;   
                float _ThicknessCurve;
                float _FurLength;
                float _Gravity;
                float _Messiness;
                float4 _CombDir; 
            CBUFFER_END

            // 声明实例化属性池
            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _LayerRatio)
            UNITY_INSTANCING_BUFFER_END(Props)

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // 读取当前层的比例
                float ratio = UNITY_ACCESS_INSTANCED_PROP(Props, _LayerRatio);
                output.layerRatio = ratio;

                // 遮罩与长度计算
                float2 lengthUV = TRANSFORM_TEX(input.uv, _LengthMap);
                float lengthMask = SAMPLE_TEXTURE2D_LOD(_LengthMap, sampler_LengthMap, lengthUV, 0).r;
                float actualFurLength = _FurLength * lengthMask;

                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                // 1. 法线向外推移
                float extrusion = ratio * actualFurLength;
                posWS += normalWS * extrusion;
                
                // 2. 物理与梳毛方向 (二次曲线实现非线性刚度)
                float3 baseDrop = float3(0, -1, 0) * _Gravity; 
                float3 combOffset = _CombDir.xyz + baseDrop;
                float3 dirOffset = combOffset * actualFurLength * (ratio * ratio);
                posWS += dirOffset;

                // 3. 凌乱与卷曲扰动
                float3 messOffset = sin(posWS * 30.0) * (_Messiness * actualFurLength * 0.5) * (ratio * ratio);
                posWS += messOffset;

                output.positionCS = TransformWorldToHClip(posWS);
                output.uv = TRANSFORM_TEX(input.uv, _NoiseTex); 
                // 混合重力与卷曲后的新法线
                output.normalWS = normalize(normalWS + dirOffset + messOffset);

                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float ratio = input.layerRatio;

                // 配合网格形变的 UV 扰动增强乱发感
                float2 uvOffset = sin(input.uv * 50.0) * (_Messiness * 0.02 * ratio);
                float2 noiseUV = (input.uv + uvOffset) * _NoiseTiling; 
                float noiseVal = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, noiseUV).r;
                
                float shapeCurve = pow(ratio, _ThicknessCurve);
                
                // 计算 Alpha Test 的阈值
                float rootCutoff = 1.0 - _Density;
                float cutoff = lerp(rootCutoff, _TipCutoff, shapeCurve);
                
                // 防夹断保护
                float minCutoffLimit = 1.0 - _MaxDensity;
                cutoff = max(cutoff, minCutoffLimit);
                
                // 强制保留最底层，防止走光
                if (ratio > 0.02)
                {
                    clip(noiseVal - cutoff); // 多层裁剪核心
                }

                // 光照计算
                float3 albedo = lerp(_BaseColor.rgb, _FurColor.rgb, ratio);
                Light mainLight = GetMainLight();
                float NdotL = saturate(dot(normalize(input.normalWS), normalize(mainLight.direction)));
                
                float3 ambient = float3(0.2, 0.25, 0.3) * albedo; 
                float3 finalColor = albedo * mainLight.color * NdotL + ambient;

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}