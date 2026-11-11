using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class BlurRenderPassFeature : ScriptableRendererFeature
{
    class BlurRenderPass : ScriptableRenderPass
    {
        const string ProfilerTag = "Blur Pass";

        RenderTargetIdentifier colorBuffer, temporaryBuffer;
        int temporaryBufferID = Shader.PropertyToID("_TemporaryBuffer");

        // 第 1 条：由 Feature 每帧写入，不再依赖 Create() 时的一次性拷贝
        public Material material;
        public int downsample = 1;
        public float blurStrength = 5;

        static readonly int BlurStrengthProperty = Shader.PropertyToID("_BlurStrength");

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.width /= Mathf.Max(1, downsample);
            descriptor.height /= Mathf.Max(1, downsample);

            descriptor.depthBufferBits = 0;
            // 非 MSAA 的普通贴图，避免 MSAA 下 GetTemporaryRT 断言 / 解析问题
            descriptor.msaaSamples = 1;

            colorBuffer = renderingData.cameraData.renderer.cameraColorTarget;

            cmd.GetTemporaryRT(temporaryBufferID, descriptor, FilterMode.Bilinear);
            temporaryBuffer = new RenderTargetIdentifier(temporaryBufferID);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (material == null) return;

            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, new ProfilingSampler(ProfilerTag)))
            {
                material.SetFloat(BlurStrengthProperty, blurStrength);

                // pass 0：用 _FurVector 做定向模糊 + 按 mask 合成，写进临时 RT
                Blit(cmd, colorBuffer, temporaryBuffer, material, 0);

                // 第 2 条：这里不带 material 的 Blit 才会自动把源绑到 _MainTex。
                // 原来写的 Blit(..., material, 1) 走 cmd.Blit + 材质，_MainTex 未被绑定，
                // 会把未定义内容写回 camera color，整屏被破坏。
                Blit(cmd, temporaryBuffer, colorBuffer);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // 第 3 条：补上临时 RT 释放
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null) throw new ArgumentNullException("cmd");
            cmd.ReleaseTemporaryRT(temporaryBufferID);
        }
    }

    BlurRenderPass m_ScriptablePass;
    public Material material;
    [Range(1, 4)] public int downsample = 1;
    [Range(0, 0.2f)] public float blurStrength = 0.01f;
    public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new BlurRenderPass();
        m_ScriptablePass.renderPassEvent = renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 第 1 条：每帧把 Inspector 上的值同步给 pass，运行时改参数立即生效
        m_ScriptablePass.renderPassEvent = renderPassEvent;
        m_ScriptablePass.material = material;
        m_ScriptablePass.downsample = downsample;
        m_ScriptablePass.blurStrength = blurStrength;

        renderer.EnqueuePass(m_ScriptablePass);
    }
}
