#ifndef NPR_ZS_PBR_URP_BRDF_INCLUDED
#define NPR_ZS_PBR_URP_BRDF_INCLUDED

#define NPR_PI 3.141592654

float NPR_DDistributionGGX(float3 normal, float3 halfDirection, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float nh = max(dot(normal, halfDirection), 0.0);
    float nh2 = nh * nh;
    float denominator = nh2 * (a2 - 1.0) + 1.0;
    denominator = NPR_PI * denominator * denominator;
    return a2 / max(denominator, 0.0000001);
}

float NPR_GeometrySchlickGGX(float nv, float roughness)
{
    float r = roughness + 1.0;
    float k = r * r / 8.0;
    return nv / max(k + (1.0 - k) * nv, 0.0000001);
}

float NPR_GGeometrySmith(float3 normal, float3 viewDirection, float3 lightDirection, float roughness)
{
    float nv = max(dot(normal, viewDirection), 0.0);
    float nl = max(dot(normal, lightDirection), 0.0);
    return NPR_GeometrySchlickGGX(nv, roughness) *
        NPR_GeometrySchlickGGX(nl, roughness);
}

float3 NPR_FresnelSchlick(float hv, float3 f0)
{
    return f0 + (1.0 - f0) * pow(1.0 - hv, 5.0);
}

float3 NPR_SpecularGGX(
    float3 normal,
    float3 lightDirection,
    float3 halfDirection,
    float3 viewDirection,
    float roughness,
    float3 f0)
{
    float nv = dot(normal, viewDirection);
    float nl = dot(normal, lightDirection);
    float hv = dot(halfDirection, viewDirection);
    float distribution = NPR_DDistributionGGX(normal, halfDirection, roughness);
    float3 fresnel = NPR_FresnelSchlick(hv, f0);
    float geometry = NPR_GGeometrySmith(normal, viewDirection, lightDirection, roughness);
    float3 specular = distribution * fresnel * geometry /
        max(4.0 * nv * nl, 0.001);
    return max(specular, 0.0);
}

struct NPRStylizedSpecularParam
{
    float3 BaseColor;
    float3 Normal;
    float Shininess;
    float Gloss;
    float Threshold;
    float3 dv;
    float3 du;
};

float3 NPR_RotateAroundAxis(float3 original, float3 axis, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    float t = 1.0 - c;
    float3x3 rotation = float3x3(
        t * axis.x * axis.x + c,     t * axis.x * axis.y - s * axis.z, t * axis.x * axis.z + s * axis.y,
        t * axis.x * axis.y + s * axis.z, t * axis.y * axis.y + c,     t * axis.y * axis.z - s * axis.x,
        t * axis.x * axis.z - s * axis.y, t * axis.y * axis.z + s * axis.x, t * axis.z * axis.z + c);
    return mul(rotation, original);
}

void NPR_StylizedSpecularTransform(
    inout float3 halfDirection,
    inout float3 du,
    inout float3 dv,
    float3 normal)
{
    halfDirection = normalize(halfDirection + 0.5 * du);
    du = NPR_RotateAroundAxis(du, normal, 1.57);
    dv = NPR_RotateAroundAxis(dv, normal, 1.57);
    halfDirection = normalize(halfDirection - 0.5 * dot(halfDirection, du) * du);
    halfDirection = normalize(
        halfDirection -
        0.07 * sign(dot(halfDirection, du)) * du -
        0.1 * sign(dot(halfDirection, dv)) * dv);

    float m = min(abs(dot(halfDirection, du)), abs(dot(halfDirection, dv)));
    m = sqrt(sin(2.0 * acos(m)));
    halfDirection = normalize(
        halfDirection - 0.5 * m *
        (dot(halfDirection, du) * du + dot(halfDirection, dv) * dv));
}

float NPR_StylizedSpecularLightBlinPhong(
    NPRStylizedSpecularParam param,
    float3 halfDirection)
{
    NPR_StylizedSpecularTransform(halfDirection, param.du, param.dv, param.Normal);

    float nh = max(0.0, dot(param.Normal, halfDirection));
    float specular = pow(nh, param.Shininess * 128.0) * param.Gloss;
    float width = fwidth(specular);
    return smoothstep(-width, width, specular - param.Threshold);
}

#endif
