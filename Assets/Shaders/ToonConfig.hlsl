#ifndef ATHENA_TOON_CONFIG
#define ATHENA_TOON_CONFIG

// 配置Toon相关设置，方便配置全局属性。

#if defined(USE_MATCAP)

    // 开启Matcap的时候就会把镜面反射高光关掉。
    #define _SPECULARHIGHLIGHTS_OFF 1
    //* wanghaoyu 百万,平行光强度影响matcap
    #define _LIGHTAFFECTMATCAP 1

#endif


// 配置由程序动态修改的场景的效果，比如受击和传送

#if defined(USE_TOONGAMEEFFECT)

    // 开启动态的切换角色整体边缘光。方便制作打击和选择效果。
    #define ENABLE_OVERRIDERIMLIGHT 1
    #define ENABLE_DISSOLVE 1

#endif

// 是否全局支持额外光源风格化
#if _TOON_ATHENA_LIGHTING_ADDITIONAL

    #define _ADDITIONAL_LIGHTS_TOON 1
    //* wanghaoyu 百万,对于额外光希望不依赖法线,让角色显得更平,且需要更明确的面部SDF阴影
    #define _ADDITIONAL_LIGHTS_TOON_FLAT 1

#endif

// 深度边缘光需要屏幕坐标
#define _NeedScreenPos 1

// 需要开启Dither抖动
#define ENABLE_DITHER 1

// 需要开启随VdotL改变的明暗交界线变化
#define ENABLE_NDOTL_MOVE_BY_VDOTL 1

// 判断是否使用UV内描边
//#define ENABLE_INNER_LINE 1

#define _TOON_ATHENA_EDGE 1

// 判断是否需要判断SDF脸部需要区分出不使用SDF的部分（通过Grading Map来控制，只有比0.9高的部分才使用SDF，百万组的需求，他们需要在一个材质里控制脸，以及不受SDF控制的口腔）
#define _USE_GRADING_MAP_TO_MASK_SDF 1

#endif  //ATHENA_TOON_CONFIG
