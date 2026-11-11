#ifndef ATHENA_TOON_DATA_STRUCT
#define ATHENA_TOON_DATA_STRUCT

// ToonData 的基本结构，提取出来方便复用

struct ToonData
{
    #if !defined(_Mode_Kajiya_Kay)
    half3 darkColor;
    half isPBR;

    half diffuseGrading;
    half diffuseIntensity;

    //* pwrd fanxingtong: Athena/Toon/Hair Cast Stencil Shadow中将MixTex的Alpha通道作为KK模型的Mask
    #else
    half KajiyaKayMask;
    #endif

    half rimMask;

    half3 lightDirToonWS;

    half NdotL;
    half NdotV;
    half VdotL;
    half SSNdotL;   // Screen Space N dot L

    // 设定光源的上限
    half3 clampedLightColor;

    #ifdef USE_MATCAP
    half matcapMask;
    #endif

    // SDF结构
    half sdf;

    // 在lighting中修改光照的影子信息
    half mainLightAtten;
};

#endif  //ATHENA_TOON_DATA_STRUCT
