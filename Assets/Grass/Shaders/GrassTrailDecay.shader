// ============================================================================
//  GrassTrailDecay.shader —— 推力场的逐帧衰减
//
//  每帧把整张推力场乘一个小于 1 的系数，草就会慢慢回弹。
//  同时做一次 [-1,1] 的钳制：站着不动时推力会不断累加，
//  不钳制的话局部会冲到几千，草会直接翻过去。
// ============================================================================

Shader "Hidden/Grass/GrassTrailDecay"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float _Decay;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
            };

            v2f vert(appdata_img v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.texcoord;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float2 c = tex2D(_MainTex, i.uv).rg;
                c = clamp(c, -1.0, 1.0) * _Decay;
                return float4(c, 0.0, 0.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
