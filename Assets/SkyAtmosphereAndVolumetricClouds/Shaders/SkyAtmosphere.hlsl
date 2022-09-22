#ifndef SKYATMOSPHERE_INCLUDE
#define SKYATMOSPHERE_INCLUDE

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
#include "FastMath.hlsl"

float4 _SkyAtmosphereParams[16];
#define GroundAlbedo _SkyAtmosphereParams[0].xyz
#define EnableAeraialPerspective _SkyAtmosphereParams[0].w
#define RayleighScattering _SkyAtmosphereParams[1].xyz
#define RayleighDensityExpScale _SkyAtmosphereParams[1].w
#define MieScattering _SkyAtmosphereParams[2].x
#define MieAbsorption _SkyAtmosphereParams[2].y
#define MieAnisotropy _SkyAtmosphereParams[2].z
#define MieDensityExpScale _SkyAtmosphereParams[2].w
#define OzoneAbsorption  _SkyAtmosphereParams[3].xyz
#define OzoneAbsorptionTipAltitude _SkyAtmosphereParams[3].w
#define OzoneAbsorptionWidth _SkyAtmosphereParams[4].x
#define TopRadiusKm _SkyAtmosphereParams[4].y
#define BottomRadiusKm _SkyAtmosphereParams[4].z
#define TransmittanceLutSize _SkyAtmosphereParams[5]
#define MultiScatteringLutSize _SkyAtmosphereParams[6]
#define SkyViewLutSize _SkyAtmosphereParams[7]
#define CameraVolumeLutInvSize _SkyAtmosphereParams[8].xyz
#define CameraVolumeLutSlice _SkyAtmosphereParams[8].w
#define LightDiskColor _SkyAtmosphereParams[9].xyz
#define LightDiskCosHalgAngle _SkyAtmosphereParams[9].w
#define CameraVolumeSliceDepthKm _SkyAtmosphereParams[10].x
#define CameraVolumeSliceDepthKmInv _SkyAtmosphereParams[10].y

Texture2D<float> _CameraDepthTexture;
Texture2D<float3> _TransmittanceLut;
Texture2D<float3> _MultiScatteredLut;
Texture2D<float3> _SkyViewLut;
Texture3D<float4> _CameraVolumeLut;

/**
 * Returns near intersection in x, far intersection in y, or both -1 if no intersection.
 * RayDirection does not need to be unit length.
 */
float2 RayIntersectSphere(float3 RayOrigin, float3 RayDirection, float4 Sphere)
{
    float3 LocalPosition = RayOrigin - Sphere.xyz;
    float LocalPositionSqr = dot(LocalPosition, LocalPosition);

    float3 QuadraticCoef;
    QuadraticCoef.x = dot(RayDirection, RayDirection);
    QuadraticCoef.y = 2 * dot(RayDirection, LocalPosition);
    QuadraticCoef.z = LocalPositionSqr - Sphere.w * Sphere.w;

    float Discriminant = QuadraticCoef.y * QuadraticCoef.y - 4 * QuadraticCoef.x * QuadraticCoef.z;

    float2 Intersections = -1;

    // Only continue if the ray intersects the sphere
    [flatten]
    if (Discriminant >= 0)
    {
        float SqrtDiscriminant = sqrt(Discriminant);
        Intersections = (-QuadraticCoef.y + float2(-1, 1) * SqrtDiscriminant) / (2 * QuadraticCoef.x);
    }

    return Intersections;
}

// - RayOrigin: ray origin
// - RayDir: normalized ray direction
// - SphereCenter: sphere center
// - SphereRadius: sphere radius
// - Returns distance from RayOrigin to closest intersecion with sphere,
//   or -1.0 if no intersection.
float RaySphereIntersectNearest(float3 RayOrigin, float3 RayDir, float3 SphereCenter, float SphereRadius)
{
    float2 Sol = RayIntersectSphere(RayOrigin, RayDir, float4(SphereCenter, SphereRadius));
    float Sol0 = Sol.x;
    float Sol1 = Sol.y;
    if (Sol0 < 0.0f && Sol1 < 0.0f)
    {
        return -1.0f;
    }
    if (Sol0 < 0.0f)
    {
        return max(0.0f, Sol1);
    }
    else if (Sol1 < 0.0f)
    {
        return max(0.0f, Sol0);
    }
    return max(0.0f, min(Sol0, Sol1));
}

void UvToLutTransmittanceParams(out float ViewHeight, out float ViewZenithCosAngle, in float2 UV)
{
    float Xmu = UV.x;
    float Xr = UV.y;

    float H = sqrt(TopRadiusKm * TopRadiusKm - BottomRadiusKm * BottomRadiusKm);
    float Rho = H * Xr;
    ViewHeight = sqrt(Rho * Rho + BottomRadiusKm * BottomRadiusKm);

    float Dmin = TopRadiusKm - ViewHeight;
    float Dmax = Rho + H;
    float D = Dmin + Xmu * (Dmax - Dmin);
    ViewZenithCosAngle = D == 0.0f ? 1.0f : (H * H - Rho * Rho - D * D) / (2.0f * ViewHeight * D);
    ViewZenithCosAngle = clamp(ViewZenithCosAngle, -1.0f, 1.0f);
}

void LutTransmittanceParamsToUv(in float ViewHeight, in float ViewZenithCosAngle, out float2 UV)
{
    float H = sqrt(max(0.0f, TopRadiusKm * TopRadiusKm - BottomRadiusKm * BottomRadiusKm));
    float Rho = sqrt(max(0.0f, ViewHeight * ViewHeight - BottomRadiusKm * BottomRadiusKm));

    float Discriminant = ViewHeight * ViewHeight * (ViewZenithCosAngle * ViewZenithCosAngle - 1.0f) + TopRadiusKm * TopRadiusKm;
    float D = max(0.0f, (-ViewHeight * ViewZenithCosAngle + sqrt(Discriminant))); // Distance to atmosphere boundary

    float Dmin = TopRadiusKm - ViewHeight;
    float Dmax = Rho + H;
    float Xmu = (D - Dmin) / (Dmax - Dmin);
    float Xr = Rho / H;

    UV = float2(Xmu, Xr);
}

float2 FromUnitToSubUvs(float2 uv, float4 SizeAndInvSize) { return (uv + 0.5f * SizeAndInvSize.zw) * (SizeAndInvSize.xy / (SizeAndInvSize.xy + 1.0f)); }
float2 FromSubUvsToUnit(float2 uv, float4 SizeAndInvSize) { return (uv - 0.5f * SizeAndInvSize.zw) * (SizeAndInvSize.xy / (SizeAndInvSize.xy - 1.0f)); }

void UvToSkyViewLutParams(out float3 ViewDir, in float ViewHeight, in float2 UV)
{
    // 防止在边缘产生的不连续问题
    UV = FromSubUvsToUnit(UV, SkyViewLutSize);
    
    float Vhorizon = sqrt(ViewHeight * ViewHeight - BottomRadiusKm * BottomRadiusKm);
    float CosBeta = Vhorizon / ViewHeight;
    float Beta = acosFast4(CosBeta);
    float ZenithHorizonAngle = PI - Beta;

    float ViewZenithAngle;
    if (UV.y < 0.5f)
    {
        float Coord = 2.0f * UV.y;
        Coord = 1.0f - Coord;
        Coord *= Coord;
        Coord = 1.0f - Coord;
        ViewZenithAngle = ZenithHorizonAngle * Coord;
    }
    else
    {
        float Coord = UV.y * 2.0f - 1.0f;
        Coord *= Coord;
        ViewZenithAngle = ZenithHorizonAngle + Beta * Coord;
    }
    float CosViewZenithAngle = cos(ViewZenithAngle);
    float SinViewZenithAngle = sqrt(1.0 - CosViewZenithAngle * CosViewZenithAngle) * (ViewZenithAngle > 0.0f ? 1.0f : -1.0f);

    float LongitudeViewCosAngle = UV.x * 2.0f * PI;


    float CosLongitudeViewCosAngle = cos(LongitudeViewCosAngle);
    float SinLongitudeViewCosAngle = sqrt(1.0 - CosLongitudeViewCosAngle * CosLongitudeViewCosAngle) * (LongitudeViewCosAngle <= PI ? 1.0f : -1.0f);
    ViewDir = float3(
        SinViewZenithAngle * CosLongitudeViewCosAngle,
        SinViewZenithAngle * SinLongitudeViewCosAngle,
        CosViewZenithAngle
        );
}

void SkyViewLutParamsToUv(
    in bool IntersectGround, in float ViewZenithCosAngle, in float3 ViewDir, in float ViewHeight, in float BottomRadius, in float4 SkyViewLutSizeAndInvSize,
    out float2 UV)
{
    float Vhorizon = sqrt(ViewHeight * ViewHeight - BottomRadius * BottomRadius);
    float CosBeta = Vhorizon / ViewHeight;
    float Beta = acosFast4(CosBeta);
    float ZenithHorizonAngle = PI - Beta;
    float ViewZenithAngle = acosFast4(ViewZenithCosAngle);

    if (!IntersectGround)
    {
        float Coord = ViewZenithAngle / ZenithHorizonAngle;
        Coord = 1.0f - Coord;
        Coord = sqrt(Coord);
        Coord = 1.0f - Coord;
        UV.y = Coord * 0.5f;
    }
    else
    {
        float Coord = (ViewZenithAngle - ZenithHorizonAngle) / Beta;
        Coord = sqrt(Coord);
        UV.y = Coord * 0.5f + 0.5f;
    }

    {
        UV.x = (atan2Fast(-ViewDir.y, -ViewDir.x) + PI) / (2.0f * PI);
    }

    UV = FromUnitToSubUvs(UV, SkyViewLutSize);
}

float RayleighPhase(float CosTheta)
{
    float Factor = 3.0f / (16.0f * PI);
    return Factor * (1.0f + CosTheta * CosTheta);
}

float3 GetAtmosphereTransmittance(
    float3 WorldPos, float3 WorldDir)
{
    // For each view height entry, transmittance is only stored from zenith to horizon. Earth shadow is not accounted for.
    // It does not contain earth shadow in order to avoid texel linear interpolation artefact when LUT is low resolution.
    // As such, at the most shadowed point of the LUT when close to horizon, pure black with earth shadow is never hit.
    // That is why we analytically compute the virtual planet shadow here.
    const float2 Sol = RayIntersectSphere(WorldPos, WorldDir, float4(float3(0.0f, 0.0f, 0.0f), BottomRadiusKm));
    if (Sol.x > 0.0f || Sol.y > 0.0f)
    {
        return 0.0f;
    }

    const float PHeight = length(WorldPos);
    const float3 UpVector = WorldPos / PHeight;
    const float LightZenithCosAngle = dot(WorldDir, UpVector);
    float2 TransmittanceLutUv;
    LutTransmittanceParamsToUv(PHeight, LightZenithCosAngle, TransmittanceLutUv);
    float3 TransmittanceToLight = _TransmittanceLut.SampleLevel(sampler_LinearClamp, TransmittanceLutUv, 0).rgb;
    return TransmittanceToLight;
}

float HgPhase(float G, float CosTheta)
{
    // Reference implementation (i.e. not schlick approximation). 
    // See http://www.pbr-book.org/3ed-2018/Volume_Scattering/Phase_Functions.html
    float Numer = 1.0f - G * G;
    float Denom = 1.0f + G * G + 2.0f * G * CosTheta;
    return Numer / (4.0f * PI * Denom * sqrt(Denom));
}

// 计算天空大气的坐标系，和Unity中的坐标系不同
float3 UnityDirectionToAtmosphereDirection(float3 v)
{
    float3 v2;
    v2.x = -v.z;
    v2.z = v.y;
    v2.y = v.x;
    return v2;
}

float3 GetLightDiskLuminance(float3 WorldPos, float3 WorldDir)
{
    float t = RaySphereIntersectNearest(WorldPos, WorldDir, float3(0.0f, 0.0f, 0.0f), BottomRadiusKm);
    if (t < 0.0f)												// No intersection with the planet
    {
        float3 AtmosphereLightDirection = UnityDirectionToAtmosphereDirection(_MainLightPosition.xyz);
        const float ViewDotLight = dot(WorldDir, AtmosphereLightDirection);
        const float CosHalfApex = LightDiskCosHalgAngle;
        float3 DiskLight = 0;
        if (ViewDotLight > CosHalfApex)
        {
            const float3 TransmittanceToLight = GetAtmosphereTransmittance( WorldPos, WorldDir);

            DiskLight = TransmittanceToLight * LightDiskColor;
        }
        
        const float HalfCosHalfApex = CosHalfApex + (1.0f - CosHalfApex) * 0.25; // Start fading when at 75% distance from light disk center (in cosine space)

        // Apply smooth fading at edge. This is currently an eye balled fade out that works well in many cases.
        const float Weight = 1.0-saturate((HalfCosHalfApex - ViewDotLight) / (HalfCosHalfApex - CosHalfApex));
        DiskLight = DiskLight * Weight;

        return DiskLight;
    }
    return 0.0f;
}

float4 GetAerialPerspectiveLuminanceTransmittance(float2 ScreenUV, float WorldDepth)
{
    float SliceW = WorldDepth * CameraVolumeSliceDepthKmInv;
    SliceW = sqrt(SliceW);
    float4 AP = _CameraVolumeLut.SampleLevel(sampler_LinearClamp, float3(ScreenUV, SliceW), 0);
    return AP;
}


float GetCameraViewHeight()
{
    //至少从地面5米以上开始计算，
    float ViewHeight = max(_WorldSpaceCameraPos.y * 0.001f, 0.005f) + BottomRadiusKm;
    return ViewHeight;
}

float3 GetWorldDir(float2 UV)
{
    float2 NDCPos = UV * 2 - 1;
#if UNITY_REVERSED_Z
    NDCPos.y = -NDCPos.y;
#endif
    float4 WorldPos = mul(UNITY_MATRIX_I_VP, float4(NDCPos, 0.5f, 1));
    WorldPos /= WorldPos.w;
    return normalize(WorldPos.xyz - _WorldSpaceCameraPos.xyz);
}

#endif