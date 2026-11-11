using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class FurRenderPassFeature : ScriptableRendererFeature
{
    class FurRenderPass : ScriptableRenderPass
    {
        const string m_ProfilerTag = "Fur Vector";

        // 固定名字的临时 RT：所有相机共用同一个 handle，
        // 各相机在 Configure 里按自己的尺寸重新 GetTemporaryRT，在 OnCameraCleanup 释放
        static readonly RenderTargetHandle s_Destination = InitHandle();

        private ProfilingSampler _profilingSampler = new ProfilingSampler(m_ProfilerTag);

        private FilteringSettings filteringSettings;
        private static readonly List<ShaderTagId> k_Fur = new List<ShaderTagId> { new ShaderTagId("FurVector") };

        private static RenderTargetHandle InitHandle()
        {
            var handle = new RenderTargetHandle();
            handle.Init("_FurVector");
            return handle;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            _profilingSampler = new ProfilingSampler(m_ProfilerTag);
            filteringSettings = new FilteringSettings(RenderQueueRange.opaque);

            RenderTextureDescriptor descriptor = cameraTextureDescriptor;
            descriptor.colorFormat = RenderTextureFormat.ARGBHalf;
            descriptor.depthBufferBits = 0;
            // 非 MSAA 的普通贴图，避免 MSAA 下 GetTemporaryRT 断言 / 解析问题
            descriptor.msaaSamples = 1;

            // GetTemporaryRT 按 id 去重，重复分配同一 id 本身是安全的
            cmd.GetTemporaryRT(s_Destination.id, descriptor, FilterMode.Bilinear);

            // color 指向 _FurVector；深度仍沿用 Renderer 当前激活的深度附件，
            // 所以毛发物体的深度测试行为和原来一致
            ConfigureTarget(s_Destination.Identifier(), BuiltinRenderTextureType.CameraTarget);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                // Clear 必须「先提交、再画」：
                //   ClearRenderTarget 只是记录进 cmd，而 context.DrawRenderers 是立即执行的。
                //   原顺序（先 DrawRenderers、后 ExecuteCommandBuffer）等于每帧画完立刻把
                //   _FurVector 清掉，模糊端永远只读到清屏常量 → 每像素提前 return → 毛发从不生效。
                //
                // 清屏值 (0.5, 0.5, 0, 0) 三个通道都表示「这里没有毛发」：
                //   rg = 0.5 -> 解码后方向为 0；b = 0 -> 长度为 0；a = 0 -> mask 为 0。
                cmd.ClearRenderTarget(true, true, new Color(0.5f, 0.5f, 0, 0));
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(k_Fur, ref renderingData, sortingCriteria);
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

                cmd.SetGlobalTexture("_FurVector", s_Destination.Identifier());
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        // 第 3 条：原来 FrameCleanup 是空的，_FurVector 每帧泄漏一张全屏 RT
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null) return;
            cmd.ReleaseTemporaryRT(s_Destination.id);
        }
    }

    FurRenderPass m_ScriptablePass;
    public RenderPassEvent PassEvent = RenderPassEvent.AfterRenderingOpaques;

    public override void Create()
    {
        m_ScriptablePass = new FurRenderPass();
        m_ScriptablePass.renderPassEvent = PassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // 第 1 条：每次入队前同步 Inspector 上的事件点，运行时不重启也生效
        m_ScriptablePass.renderPassEvent = PassEvent;
        renderer.EnqueuePass(m_ScriptablePass);
    }
}
