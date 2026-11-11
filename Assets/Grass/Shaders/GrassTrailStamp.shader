// ============================================================================
//  GrassTrailStamp.shader —— 画一个"脚印"到推力场
//
//  用全屏四边形绘制，圆心/半径/强度都通过 uniform 传进来，
//  所以不依赖任何矩阵或正交投影，画到哪里完全由参数决定。
//
//  推力场是 RG 两个半精度通道的世界空间二维向量：
//      R = 推力.x（世界 X）
//      G = 推力.y（世界 Z）
//  加法混合累积，草被踩向四周。
// ============================================================================

Shader "Hidden/Grass/GrassTrailStamp"
{
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Overlay" }

        Pass
        {
            Blend One One
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            float2 _Center;     // 圆心（推力场 UV，0~1）
            float2 _Radius;     // 半径（UV 空间，xy 分开可以做椭圆）
            float  _Angle;      // 椭圆旋转（弧度，沿速度方向拉伸）
            float  _Strength;   // 推力强度
            float  _Softness;   // 边缘柔和度

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = UnityObjectToClipPos(v.positionOS);
                o.uv = v.uv;
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float2 d = i.uv - _Center;

                // 把偏移转到椭圆自己的坐标系里判形状（沿着速度方向拉长）
                float ca = cos(_Angle);
                float sa = sin(_Angle);
                float2 rot = float2(d.x * ca + d.y * sa, -d.x * sa + d.y * ca);
                float2 e = rot / max(_Radius, 1e-5);

                float r = length(e);
                if (r >= 1.0) return float4(0, 0, 0, 0);

                float mask = pow(1.0 - r, _Softness);

                // 推力方向用世界空间的径向（不受椭圆拉伸影响）
                float2 dir = normalize(d + 1e-5);

                return float4(dir * (mask * _Strength), 0.0, 0.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
