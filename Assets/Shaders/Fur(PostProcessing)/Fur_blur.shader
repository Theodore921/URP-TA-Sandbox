Shader "HLSL/Fur_blur"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white"
        _SampleCount("SampleCount",Float) = 64
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
     

        TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
        float4 _MainTex_TexelSize;
        float4 _MainTex_ST;

        TEXTURE2D(_FurVector);           SAMPLER(sampler_FurVector);

        float _BlurStrength;
        float _SampleCount;

         ENDHLSL
       
        Pass
        {
            HLSLPROGRAM
            #pragma vertex BlurPassVertex
            #pragma fragment BlurPassFragment
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };
            
            Varyings BlurPassVertex(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }
            
            half4 BlurPassFragment(Varyings IN) : SV_TARGET
            {
                //rg- dir,b - len,a-mask
                float4 furVector =  SAMPLE_TEXTURE2D(_FurVector, sampler_FurVector, IN.uv).rgba;
                float mask = furVector.a;
                float2 motionVector =  furVector.rg;
                motionVector = (motionVector *2.0 - 1.0) * _BlurStrength  * furVector.b;
                
                float3 sceneColor = SampleSceneColor(IN.uv);
                if (length(motionVector) < 0.001)
                    return float4(sceneColor,1);

                float4 accumulatedColor = float4(0, 0, 0, 0);
                float totalWeight = 0.0;
                    
                float centerWeight = 1.0;
                accumulatedColor.rgb += SampleSceneColor(IN.uv) * centerWeight;
                totalWeight += centerWeight;
                    
                int sampleCount = _SampleCount;
                UNITY_LOOP
                for (int j = -sampleCount; j <= sampleCount; j++)
                {
                    if (j == 0) continue; // 跳过中心点
                        
                    float2 sampleUV = IN.uv + motionVector * (float)j / sampleCount;
                    float weight = exp(-(j * j) / (2.0 * sampleCount * sampleCount));
                    accumulatedColor.rgb += SampleSceneColor(sampleUV) * weight;
                    totalWeight += weight;
                }
                float3 baseColor = accumulatedColor.rgb / totalWeight;
                //todo 这里mask快速验证，待改成stencil
                float3 finalColor = lerp(sceneColor,baseColor,mask);
                return float4(finalColor,1);
            }    
            ENDHLSL
        }
        // Pass 1：普通拷贝（_MainTex -> 目标）。
        // 注意：BlurRenderPassFeature 现在用 Blit(cmd, temporaryBuffer, colorBuffer) 走内置拷贝，
        // 不再引用这个 Pass；保留它只是为了不影响其他使用该材质的场合。
        Pass
        {
            HLSLPROGRAM
            #pragma vertex BlurPassVertex
            #pragma fragment BlurPassFragment
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

          

            Varyings BlurPassVertex(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }
            
            half4 BlurPassFragment(Varyings IN) : SV_TARGET
            {
                return  SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv );
            }
            ENDHLSL
        }
    }
}