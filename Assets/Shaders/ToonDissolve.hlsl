#ifndef ATHENA_TOON_DISSOLVE
#define ATHENA_TOON_DISSOLVE

//* wanghaoyu 按照永雷的方式加宏
#if _TOON_ATHENA_DISSOLVE
    void ApplyDissolve(float2 UV, float3 worldpos)
    {
        half2 newUV = UV * _NoiseTiling;
        half dissolve_value = SAMPLE_TEXTURE2D(_DissolveTexture, sampler_DissolveTexture, newUV).r;
        #if DISSOLVE_ROTATION
            float3 offsetDir = worldpos - _StartingPivot.xyz;
            float dissolveOffset = dot(normalize(_DirVec.xyz), offsetDir);
            float range = remap(_DissolveAmount, float2(0, 1), float2(0 - _DissolveRange - _EdgeWidth, _DissolveDistance * _DissolveRange));
            half alpha = dissolve_value - dissolveOffset * _DissolveRange;
            clip(alpha - range);
        #else
            float range = remap(_DissolveAmount, float2(0, 1), float2(0 - _EdgeWidth, 1 + _EdgeWidth));
            clip(dissolve_value - range);
        #endif
        //float diffInEdgeDarkness = 1 - _EdgeDarkness;
        //diffInDissolveAmount = _DissolveBackDarknessThreshold
        //_EdgeDarkness += _DissolveAmount * diffInEdgeDarkness/_DissolveBackDarknessThreshold;
        //* pwrd zhengyiye : 更新溶解后描边的算法。
        _EdgeColor.a *= saturate(1 - saturate(_DissolveAmount / _DissolveBackDarknessThreshold));
        //* pwrd zhengyiye

    };

    void ApplyDissolveWithEmission(float2 UV, float3 worldpos, inout SurfaceData surfaceData)
    {

        half2 newUV = UV * _NoiseTiling;
        half dissolve_value = SAMPLE_TEXTURE2D(_DissolveTexture, sampler_DissolveTexture, newUV).r;
        #if DISSOLVE_ROTATION
            float3 offsetDir = worldpos - _StartingPivot.xyz;
            float dissolveOffset = dot(normalize(_DirVec.xyz), offsetDir);
            float range = remap(_DissolveAmount, float2(0, 1), float2(0 - _DissolveRange - _EdgeWidth, _DissolveDistance * _DissolveRange));
            half alpha = dissolve_value - dissolveOffset * _DissolveRange;
            half edge = smoothstep(0, _EdgeSmoothness, range - alpha + _EdgeWidth);
            float4 dissolve_color = _DissolveColor * edge;
            surfaceData.emission += dissolve_color.xyz;
            clip(alpha - range);
        #else
            float range = remap(_DissolveAmount, float2(0, 1), float2(0 - _EdgeWidth, 1 + _EdgeWidth));
            float4 emission = _DissolveColor * smoothstep(0, _EdgeSmoothness, range - dissolve_value + _EdgeWidth);
            surfaceData.emission += emission.xyz;
            clip(dissolve_value - range);
        #endif
    };
#endif

#endif
