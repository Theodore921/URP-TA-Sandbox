// ============================================================================
//  LayeredSkyboxOrder.hlsl —— 天空盒图层顺序（自动生成，请勿手改）
//
//  生成器：Assets/Editor/Skybox/SkyboxLayerGenerator.cs
//  入口  ：Window > Skybox > Layer Stack
//  被包含：Assets/Shaders/Skybox/LayeredSkybox.shader
//
//  这个文件只负责"按什么顺序调用哪些层"，不含任何层的实现。
//  层的实现都在 LayeredSkybox.shader 里，参数都在材质上。
//  想改顺序或开关某层，请用上面那个窗口，改完点「重新生成」。
//
//  生成状态: order=0,1,2,3,4,5,6,7
// ============================================================================

void ComposeLayerStack(inout half3 color, LayerContext ctx)
{
    color = ComposeLayer(color, LayerSky(ctx));
    color = ComposeLayer(color, LayerStars(ctx));
    color = ComposeLayer(color, LayerMoon(ctx));
    color = ComposeLayer(color, LayerSun(ctx));
    color = ComposeLayer(color, LayerCloudHigh(ctx));
    color = ComposeLayer(color, LayerCloudLow(ctx));
    color = ComposeLayer(color, LayerGround(ctx));
    color = ComposeLayer(color, LayerHorizon(ctx));
}
