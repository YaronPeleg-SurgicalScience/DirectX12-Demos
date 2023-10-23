#define BIT(x)			(1<<x)
#define PI				3.1415926535897932384626433832795
#define TWO_PI			6.283185307179586476925286766559
#define SQRT2			1.41421356237309504880

#define SHADOWMAP_BIAS 	0.00015f

#if (MAX_OIT_NODE_COUNT != 0)
#define MAX_OIT_DEPTH		999999999999.0f
//#define MAX_OIT_NODE_COUNT	8	// set from code while compiling the shader
struct tTransparentFragment
{
	float3 color;
	float trans;
	float depth;
};
struct OITData
{
	tTransparentFragment frags[MAX_OIT_NODE_COUNT];
};
#endif

// define should match 'ENUM_PaintBrushPaintFlags'
#define E_PBPF_NONE			0
#define E_PBPF_COLOR		BIT(0)
#define E_PBPF_ROUGHNESS	BIT(1)
#define E_PBPF_METALLICNESS BIT(2)
#define E_PBPF_HEIGHT		BIT(3)
#define E_PBPF_ALL			(E_PBPF_COLOR | E_PBPF_ROUGHNESS | E_PBPF_METALLICNESS | E_PBPF_HEIGHT)
#define E_PBPF_PAINT		BIT(4)
#define E_PBPF_ERASE		BIT(5)

struct tPaintBrush
{
	float3 vPosition;
	float4 vColor;
	float fRadius;
	float fHardness;
	float fStrength;
	float fRoughness;
	float fMetallicness;
	float fHeight;
	int iPaintFlags;
};
struct tSpotLight
{
	float3 vPosition;
	float3 vDirection;
	float4 vDiffuseColor;
	float4 vSpecularColor;
	float4x4 ViewProj;
	float4 vData;		// x = cos inner cone, y = cos outer cone, z = near plane, w = far plane
	float fRadiusUV;
};
struct tPointLight
{
	float3 vPosition;
	float4 vDiffuseColor;
	float4 vSpecularColor;
	float4 vData;		// xyz = radius, w = range
};
// VXGI
#define NUM_CONES 6
static const float coneAperture = 0.577f; // 6 cones, 60deg each, tan(30deg) = aperture
static const float diffuseConeWeights[NUM_CONES] = { 0.25, 0.15, 0.15, 0.15, 0.15, 0.15 };
static const float3 diffuseConeDirections[NUM_CONES] =
{
	float3(0.0f, 1.0f, 0.0f),
	float3(0.0f, 0.5f, 0.866025f),
	float3(0.823639f, 0.5f, 0.267617f),
	float3(0.509037f, 0.5f, -0.7006629f),
	float3(-0.50937f, 0.5f, -0.7006629f),
	float3(-0.823639f, 0.5f, 0.267617f)
};

static const float fOneDegree = 0.0174533f; //in radians
static const int fMaxDegreesCount = 1;

//Based off of GGX roughness; gets angle that encompasses 90% of samples in the IBL image approximation
float CalculateSpecularConeHalfAngle(float roughness2)
{
	//	float aperture = clamp(tan(PI * 0.5 * roughness), fOneDegree * fMaxDegreesCount, PI);
	return acos(sqrt(0.11111f / (roughness2 * roughness2 + 0.11111f)));
}
//

// ue4 normal blending
float3 NormalBlend_UE(in float3 n1, in float3 n2)
{
	return normalize(float3(n1.xy + n2.xy, n1.z));
}

// normal map blending using reoriented normal maps (assume normal maps already unpacked)
float3 NormalBlend_UnpackedRNM(in float3 n1, in float3 n2)
{
	n1 += float3(0, 0, 1);
	n2 *= float3(-1, -1, 1);
	return n1 * dot(n1, n2) / n1.z - n2;
}

// return vogel disk 2d sample from sample index, count and phi
float2 GetVogelDiskSample(in int sampleIndex, in int sampleCount, in float phi)
{
	float GoldenAngle = 2.4f;
	float r = sqrt(float(sampleIndex) + 0.5f) / sqrt(float(sampleCount));
	float theta = float(sampleIndex) * GoldenAngle + phi;
	float sine, cosine;
	sincos(theta, sine, cosine);
	return float2(r * cosine, r * sine);
}

// return interleaved gradient noise from screen position
float InterleavedGradientNoise(in float2 vScreenPos)
{
	float3 magic = float3(0.06711056f, 0.00583715f, 52.9829189f);
	return frac(magic.z * frac(dot(vScreenPos, magic.xy)));
}

// vPositionClipSpace (in homogeneous projection space) - meaning the input position multiply with WorldViewProj matrix
// return the uv in screen space of specify vPositionClipSpace
float2 GetScreenSpaceUV(in float4 vPositionClipSpace)
{
	/// screen space uv render target
	float2 ssUV = vPositionClipSpace.xy / vPositionClipSpace.w; // perspective divide    
	// move into texture space
	return (float2(ssUV.x, -ssUV.y) + 1.0) * 0.5;
}


// approximates luminance from an rgb color value
float GetLuminance(in float3 color)
{
	return dot(color, float3(0.299f, 0.587f, 0.114f));
}

// get linear depth from interpolated depth (Z/W)
// result in range [Near..Far]
float GetLinearDepth(in float zOverW, in float4 vProjectionParamsAB)
{
	return vProjectionParamsAB.y / (zOverW - vProjectionParamsAB.x);
}

// get normalized linear depth from interpolated depth (Z/W)
// result in range [0..1]
float GetLinearDepthNormalized(in float zOverW, in float4 vProjectionParamsAB)
{
	float depth = GetLinearDepth(zOverW, vProjectionParamsAB);
	return (depth - vProjectionParamsAB.z) / (vProjectionParamsAB.w - vProjectionParamsAB.z);
}

// z = interpolated z (z/w)
// vTexCoord = current pixel uv
float3 GetWorldPosition(in float z, in float2 vTexCoord, in float4x4 matInvViewProjection)
{
	// get x/w and y/w from the viewport position
	float x = vTexCoord.x * 2 - 1;
	float y = (1 - vTexCoord.y) * 2 - 1;
	float4 vProjectedPos = float4(x, y, z, 1.0f);
	// transform by the inverse viewproj matrix
	float4 vPositionWS = mul(vProjectedPos, matInvViewProjection);
	// divide by w to get the position
	return vPositionWS.xyz / vPositionWS.w;
}

// helper function to sample normal map
float3 SampleNormalMap(in Texture2D texNormalMap, in SamplerState samNormalMap, in float2 vTexCoord, in int iCompressionType = 0)
{
	float3 vNormal;
	if (iCompressionType == 1)
	{
		vNormal.xy = texNormalMap.Sample(samNormalMap, vTexCoord.xy).ag * 2 - 1;
		vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy, vNormal.xy)));
	}
	else if (iCompressionType == 2)
	{
		vNormal.xy = texNormalMap.Sample(samNormalMap, vTexCoord.xy).xy * 2 - 1;
		vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy, vNormal.xy)));
	}
	else
	{
		vNormal = texNormalMap.Sample(samNormalMap, vTexCoord.xy).xyz * 2 - 1;
	}
	return vNormal;
}

float4 SampleGradNormalMap(in Texture2D texNormalMap, in SamplerState samNormalMap, in float2 vTexCoord, in float2 dx, in float2 dy, in int iCompressionType = 0)
{
	float4 vNormal;
//#if (USE_BG_NORMAL_MAP == 1)
	if (iCompressionType == 1)
	{
		vNormal.xy = texNormalMap.SampleGrad(samNormalMap, vTexCoord.xy, dx, dy).ag * 2 - 1;
		vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy, vNormal.xy)));
		vNormal.w = 1;
	}
//#elif (USE_BC5_NORMAL_MAP == 1)
	else if (iCompressionType == 2)
	{
		vNormal.xy = texNormalMap.SampleGrad(samNormalMap, vTexCoord.xy, dx, dy).xy * 2 - 1;
		vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy, vNormal.xy)));
		vNormal.w = 1;
	}
//#else
	else
	{
		vNormal = texNormalMap.SampleGrad(samNormalMap, vTexCoord.xy, dx, dy) * 2 - 1;
	}
//#endif
	return vNormal;
}

// Normal distribution functions

float NormalDistribution_GGX(float a, float NdH)
{
	// Isotropic ggx.
	float a2 = a * a;
	float NdH2 = NdH * NdH;

	float denominator = NdH2 * (a2 - 1.0f) + 1.0f;
	denominator *= denominator;
	denominator *= PI;

	return a2 / denominator;
}

// Geometric shadowing functions
float Geometric_Smith_Schlick_GGX(float a, float NdV, float NdL)
{
	// Smith schlick-GGX.
	float k = a * 0.5f;
	float GV = NdV / (NdV * (1 - k) + k);
	float GL = NdL / (NdL * (1 - k) + k);

	return GV * GL;
}

// Fresnel functions

float3 Fresnel_Schlick(float3 specularColor, float3 h, float3 v)
{
	return (specularColor + (1.0f - specularColor) * pow((1.0f - saturate(dot(v, h))), 5));
}

float Specular_D(float a, float NdH)
{
	return NormalDistribution_GGX(a, NdH);
}

float3 Specular_F(float3 specularColor, float3 h, float3 v)
{
	return Fresnel_Schlick(specularColor, h, v);
}

float3 Specular_F_Roughness(float3 specularColor, float a, float3 h, float3 v)
{
	// Sclick using roughness to attenuate fresnel.
	return (specularColor + (max(1.0f - a, specularColor) - specularColor) * pow((1 - saturate(dot(v, h))), 5));
}

float Specular_G(float a, float NdV, float NdL, float NdH, float VdH, float LdV)
{
	return Geometric_Smith_Schlick_GGX(a, NdV, NdL);
}

float3 Specular(float3 specularColor, float3 h, float3 v, float3 l, float a, float NdL, float NdV, float NdH, float VdH, float LdV)
{
	return ((Specular_D(a, NdH) * Specular_G(a, NdV, NdL, NdH, VdH, LdV)) * Specular_F(specularColor, v, h)) / (4.0f * NdL * NdV + 0.0001f);
}

// diffuse function
float3 Diffuse(float3 pAlbedo)
{
	return pAlbedo / PI;
}

void ComputeLight(float3 albedoColor,
	float3 specularColor,
	float4 subsurfaceColor,
	float3 normal, 
	float roughness,
	float3 lightPosition, 
	float3 lightDiffuseColor, 
	float3 lightSpecularColor, 
	float3 lightDir, 
	float3 viewDir,
	out float3 diffuse, 
	out float3 specular,
	out float3 subsurface,
	uniform bool bTwoSided = false)
{
	// Compute some useful values.
	float NdL = dot(normal, lightDir);
	float PNdL = clamp(NdL, 0.0f, 1.0f);	// positive ndl
	float NNdL = clamp(-NdL, 0.0f, 1.0f);	// negative ndl
	float NdV = saturate(dot(normal, viewDir));
	float3 h = normalize(lightDir + viewDir);
	float NdH = saturate(dot(normal, h));
	float VdH = saturate(dot(viewDir, h));
	float LdV = saturate(dot(lightDir, viewDir));
	float a = max(0.001f, roughness * roughness);

	float3 cDiff = PNdL * Diffuse(albedoColor);
	float3 cSpec = PNdL * Specular(specularColor, h, viewDir, lightDir, a, PNdL, NdV, NdH, VdH, LdV);
	diffuse = lightDiffuseColor * cDiff;// *(1.0f - cSpec);
	specular = lightSpecularColor * cSpec;

	if (bTwoSided)
	{
		float realNdL = PNdL;

		viewDir = -viewDir;
		normal = -normal;

		// Compute some useful values.
		float NdL = saturate(dot(normal, lightDir));
		float NdV = saturate(dot(normal, viewDir));
		float3 h = normalize(lightDir + viewDir);
		float NdH = saturate(dot(normal, h));
		float VdH = saturate(dot(viewDir, h));
		float LdV = saturate(dot(lightDir, viewDir));
		float a = max(0.001f, roughness * roughness);

		float3 cDiff = NdL * Diffuse(albedoColor);
		float3 cSpec = NdL * Specular(specularColor, h, viewDir, lightDir, a, NdL, NdV, NdH, VdH, LdV);
		float3 diffuse2 = lightDiffuseColor * cDiff * (1.0f - cSpec);
		float3 specular2 = lightSpecularColor * cSpec;

		diffuse = lerp(diffuse2, diffuse, realNdL);
		specular = lerp(specular2, specular, realNdL);
	}

	// add subsurface scattering
	float3 sssColor = subsurfaceColor.xyz;
	float3 sssRadius = subsurfaceColor.w;
	// gaussian distribution 
	float3 sss = 0.2f * exp(-3.0f * (NNdL + PNdL) / (sssRadius + 0.001f));
	subsurface = Diffuse(albedoColor) * (sssColor * sssRadius * sss);
}

void ComputeSubsurfaceScattering(float3 albedoColor, float4 subsurfaceColor, float3 normal, float3 lightDir, out float3 subsurface)
{
	float NdL = dot(normal, lightDir);
	float PNdL = clamp(NdL, 0.0f, 1.0f);	// positive ndl
	float NNdL = clamp(-NdL, 0.0f, 1.0f);	// negative ndl

	// add subsurface scattering
	float3 sssColor = subsurfaceColor.xyz;
	float3 sssRadius = subsurfaceColor.w;
	// gaussian distribution 
	float3 sss = 0.2f * exp(-3.0f * (NNdL + PNdL) / (sssRadius + 0.001f));
	subsurface = Diffuse(albedoColor) * (sssColor * sssRadius * sss);
}

void ComputeDiffuseLight(float3 albedoColor, float3 normal, float3 lightDiffuseColor, float3 lightDir, out float3 diffuse, uniform bool bTwoSided = false)
{
	// Compute some useful values.
	float NdL = saturate(dot(normal, lightDir));

	float3 cDiff = NdL * Diffuse(albedoColor);
	diffuse = lightDiffuseColor * cDiff;

	if (bTwoSided)
	{
		float realNdL = NdL;
		normal = -normal;

		// Compute some useful values.
		float NdL = saturate(dot(normal, lightDir));

		float3 cDiff = NdL * Diffuse(albedoColor);
		float3 diffuse2 = lightDiffuseColor * cDiff;

		diffuse = lerp(diffuse2, diffuse, realNdL);
	}
}

// takes a float RGB value and converts it to a float RGB value with a shared exponent
float4 ToRGBE(float4 inColor)
{
	float base = max(inColor.r, max(inColor.g, inColor.b));
	int e;
	float m = frexp(base, e);
	return float4(saturate(inColor.rgb / exp2(e)), e + 127);
}

// takes a float RGB value with a shared exponent and converts it to a float RGB value
float4 FromRGBE(float4 inColor)
{
	return float4(inColor.rgb * exp2(inColor.a - 127), inColor.a);
}

// takes a uint value and packs it to a float4
float4 uint_to_float4(uint packedInput)
{
	float4 unpackedOutput;
	uint4 p = uint4((packedInput & 0xFFUL),
		(packedInput >> 8UL) & 0xFFUL,
		(packedInput >> 16UL) & 0xFFUL,
		(packedInput >> 24UL));

	unpackedOutput = ((float4)p) / float4(255, 255, 255, 255);
	return unpackedOutput;
}

// takes a float4 value and packs it into a UINT (8 bits / float)
uint float4_to_uint(float4 unpackedInput)
{
	uint4 u = (uint4)(unpackedInput * float4(255, 255, 255, 255));
	uint packedOutput = (u.w << 24UL) | (u.z << 16UL) | (u.y << 8UL) | u.x;
	return packedOutput;
}

// takes a float (RGBA 8 bit) value and unpacks it to a float4
inline float4 float_to_float4(float fValue)
{
	uint uiValue = asuint(fValue);
	float4 f4Value;
	f4Value.r = ((uiValue & 0xFF000000) >> 24) / 255.0f;
	f4Value.g = ((uiValue & 0x00FF0000) >> 16) / 255.0f;
	f4Value.b = ((uiValue & 0x0000FF00) >> 8) / 255.0f;
	f4Value.a = ((uiValue & 0x000000FF)) / 255.0f;
	return f4Value;
}

// takes float4 value and packs it to float (RGBA 8 bit)
inline float float4_to_float(float4 f4Value)
{
	uint r, g, b, a;
	float fValue;
	r = uint(f4Value.r * 255.0f) << 24;
	g = uint(f4Value.g * 255.0f) << 16;
	b = uint(f4Value.b * 255.0f) << 8;
	a = uint(f4Value.a * 255.0f);
	fValue = asfloat(r | g | b | a);
	return fValue;
}

// Derivatives of light-space depth with respect to texture coordinates
float2 DepthGradient(float2 uv, float z)
{
	float3 texCoordDX = ddx_fine(float3(uv, z));
	float3 texCoordDY = ddy_fine(float3(uv, z));
	float2 biasUV;
	biasUV.x = texCoordDY.y * texCoordDX.z - texCoordDX.y * texCoordDY.z;
	biasUV.y = texCoordDX.x * texCoordDY.z - texCoordDY.x * texCoordDX.z;
	biasUV *= 1.0f / ((texCoordDX.x * texCoordDY.y) - (texCoordDX.y * texCoordDY.x));
	return biasUV;
}

float BiasedZ(float z0, float2 dz_duv, float2 offset)
{
	return z0 + dot(dz_duv, offset);
}

// shadows
float3 GetSpotLightShadowMapFast(in Texture2D shadowTexture, in SamplerState shadowSampler, 
	in Texture2D shadowColorTexture, in SamplerState shadowColorSampler, in float4 vPosLight, in float fBias)
{
	float2 vShadowMapSize;
	shadowTexture.GetDimensions(vShadowMapSize.x, vShadowMapSize.y);
	// shadow map
	float2 ShadowTexC = 0.5 * vPosLight.xy / vPosLight.w + float2(0.5, 0.5);
	ShadowTexC.y = 1.0f - ShadowTexC.y;
	float shadowMapDepth = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0).x;
	float4 shadowMapColor = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0);
	float currDepth = vPosLight.z / vPosLight.w - fBias;
	float shadowComp = currDepth < shadowMapDepth.x;
	float shadowCompTrans = currDepth < shadowMapColor.a;
	// apply color shadows only if secondary depth failed (this prevent self shadowing of transparent object to receiving its own color shadows!)
	if (shadowCompTrans < 1.0)
		return shadowComp * shadowMapColor.xyz;

	return shadowComp;
}
/*
float3 GetSpotLightShadowMap(in Texture2D shadowTexture, in SamplerState shadowSampler, in float4 vPosLight, in float fBias)
{
	float2 vShadowMapSize;
	shadowTexture.GetDimensions(vShadowMapSize.x, vShadowMapSize.y);
	// shadow map
	float2 ShadowTexC = 0.5 * vPosLight.xy / vPosLight.w + float2(0.5, 0.5);
	ShadowTexC.y = 1.0f - ShadowTexC.y;
	float2 texelpos = vShadowMapSize * ShadowTexC;
	float2 lerps = frac(texelpos);

	float4 shadowMapDepth;
	shadowMapDepth.x = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0, int2(0, 0)).x;
	shadowMapDepth.y = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0, int2(1, 0)).x;
	shadowMapDepth.z = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0, int2(0, 1)).x;
	shadowMapDepth.w = shadowTexture.SampleLevel(shadowSampler, ShadowTexC, 0, int2(1, 1)).x;
	float currDepth = vPosLight.z / vPosLight.w;
	float4 shadowComp = currDepth.xxxx < shadowMapDepth + fBias;
	// lerp between the shadow values to calculate our light amount
	float shadow = lerp(lerp(shadowComp[0], shadowComp[1], lerps.x),
		lerp(shadowComp[2], shadowComp[3], lerps.x),
		lerps.y);

	return shadow;
}
*/
float SpotLightShadowMapRandom(float4 seed)
{
	float dot_product = dot(seed, float4(12.9898, 78.233, 45.164, 94.673));
	return frac(sin(dot_product) * 43758.5453);
}

float3 GetSpotLightShadowMapSoft(in Texture2D shadowTexture, in SamplerState shadowSampler,
								 in Texture2D shadowColorTexture, in SamplerState shadowColorSampler, in float2 uv, in float depth, in float2 vScreenPos, const float2 vRadius, float2 dz_duv, in float fBias, uniform int NUM_SAMPLES)
{
	float theta = TWO_PI * SpotLightShadowMapRandom(float4(uv, vScreenPos));
	float2x2 rot = float2x2(cos(theta), sin(theta), -sin(theta), cos(theta));

	// sample shadow map
	float shadow = 0.0f;
	float shadowTrans = 0.0f;
	float3 shadowColor = 0.0f;
	[loop]
	for (int i = 0; i < NUM_SAMPLES; ++i)
	{
		// generate shadow sample offset
		float2 offset = mul(GetVogelDiskSample(i, NUM_SAMPLES, 1.6), rot) * vRadius;
		float shadowMapDepth = shadowTexture.SampleLevel(shadowSampler, uv + offset, 0).x;
		float4 shadowMapColor = shadowColorTexture.SampleLevel(shadowColorSampler, uv + offset, 0);
		// compare
		float z = BiasedZ(depth, dz_duv, offset) - fBias;
		float shadowComp = z < shadowMapDepth.x;
		float shadowCompTrans = z < shadowMapColor.a;
		// accumulate result
		shadow += shadowComp;
		shadowTrans += shadowCompTrans;
		shadowColor += shadowMapColor.xyz;
	}
	shadow /= float(NUM_SAMPLES);
	shadowTrans /= float(NUM_SAMPLES);
	shadowColor /= float(NUM_SAMPLES);

	// apply color shadows only if secondary depth failed (this prevent self shadowing of transparent object to receiving its own color shadows!)
	if (shadowTrans < 1.0)
		return shadow * shadowColor.xyz;

	return shadow;
}

// Using similar triangles from the surface point to the area light
float2 SearchRegionRadiusUV(float zWorld, float2 fLightRadiusUV, float fLightZNear)
{
	return fLightRadiusUV * (zWorld - fLightZNear) / zWorld;
}

// Using similar triangles between the area light, the blocking plane and the surface point
float2 PenumbraRadiusUV(float zReceiver, float zBlocker, float2 fLightRadiusUV)
{
	return fLightRadiusUV * (zReceiver - zBlocker) / zBlocker;
}

// Project UV size to the near plane of the light
float2 ProjectToLightUV(float2 sizeUV, float zWorld, float fLightZNear)
{
	return sizeUV * fLightZNear / zWorld;
}

float ZClipToZEye(float zClip, float fLightZNear, float fLightZFar)
{
	return fLightZFar * fLightZNear / (fLightZFar - zClip * (fLightZFar - fLightZNear));
}

// Returns average blocker depth in the search region, as well as the number of found blockers.
// Blockers are defined as shadow-map samples between the surface point and the light.
void FindBlocker(out float avgBlockerDepth,
	out float numBlockers,
	in Texture2D shadowTexture,
	in SamplerState shadowSampler,
	float2 uv,
	float z0,
	float2 dz_duv,
	float2 searchRegionRadiusUV,
	float2 vScreenPos,
	in float fBias,
	uniform int NUM_BLOCKER_SAMPLES)
{
	float blockerSum = 0;
	numBlockers = 0;

	float theta = TWO_PI * SpotLightShadowMapRandom(float4(uv, vScreenPos));
	float2x2 rot = float2x2(cos(theta), sin(theta), -sin(theta), cos(theta));

	// sample shadow map
	[loop]
	for (int i = 0; i < NUM_BLOCKER_SAMPLES; ++i)
	{
		// generate shadow sample offset
		float2 offset = mul(GetVogelDiskSample(i, NUM_BLOCKER_SAMPLES, 1.6), rot) * searchRegionRadiusUV;
		float shadowMapDepth = shadowTexture.SampleLevel(shadowSampler, uv + offset, 0).x;
		// compare
		float z = BiasedZ(z0, dz_duv, offset) - fBias;
		if (z < shadowMapDepth)
		{
			blockerSum += shadowMapDepth;
			numBlockers++;
		}
	}
	avgBlockerDepth = blockerSum / numBlockers;
}

float3 PCSS_Shadow(in Texture2D shadowTexture, in SamplerState shadowSampler,
	in Texture2D shadowColorTexture, in SamplerState shadowColorSampler, 
	in float2 uv, in float depth, float zEye, float2 fLightRadiusUV, float fLightZNear, float fLightZFar, in float2 vScreenPos, in float2 dz_duv, in float fBias, uniform int NUM_SAMPLES, uniform int NUM_BLOCKER_SAMPLES)
{
	// ------------------------
	// STEP 1: blocker search
	// ------------------------
	float avgBlockerDepth = 0;
	float numBlockers = 0;
	float2 searchRegionRadiusUV = SearchRegionRadiusUV(zEye, fLightRadiusUV, fLightZNear);
	FindBlocker(avgBlockerDepth, numBlockers, shadowTexture, shadowSampler, uv, depth, dz_duv, searchRegionRadiusUV, vScreenPos, fBias, NUM_BLOCKER_SAMPLES);

	// Early out if no blocker found
	if (numBlockers < 1)
		return 1.0;

	// ------------------------
	// STEP 2: penumbra size
	// ------------------------
	float avgBlockerDepthWorld = ZClipToZEye(avgBlockerDepth, fLightZNear, fLightZFar);
	float2 penumbraRadiusUV = PenumbraRadiusUV(zEye, avgBlockerDepthWorld, fLightRadiusUV);
	float2 filterRadiusUV = ProjectToLightUV(penumbraRadiusUV, zEye, fLightZNear);

	// ------------------------
	// STEP 3: filtering
	// ------------------------
	return GetSpotLightShadowMapSoft(shadowTexture, shadowSampler, shadowColorTexture, shadowColorSampler, uv, depth, vScreenPos, filterRadiusUV, dz_duv, fBias, NUM_SAMPLES);
}

float3 ComputePaintingNormal(in Texture2D Tex, in SamplerState Filter, in float2 uv, in float fNormalDepth)
{
#if 0
	float M = abs(GetLuminance(Tex.Sample(Filter, uv, int2(0, 0)).xyz));
	float L = abs(GetLuminance(Tex.Sample(Filter, uv, int2(1, 0)).xyz));
	float R = abs(GetLuminance(Tex.Sample(Filter, uv, int2(-1, 0)).xyz));
	float U = abs(GetLuminance(Tex.Sample(Filter, uv, int2(0, 1)).xyz));
	float D = abs(GetLuminance(Tex.Sample(Filter, uv, int2(0, -1)).xyz));
	float X = ((R - M) + (M - L)) * .5;
	float Y = ((D - M) + (M - U)) * .5;
#else
	float M = abs(Tex.Sample(Filter, uv, int2(0, 0)).w);
	float L = abs(Tex.Sample(Filter, uv, int2(1, 0)).w);
	float R = abs(Tex.Sample(Filter, uv, int2(-1, 0)).w);
	float U = abs(Tex.Sample(Filter, uv, int2(0, 1)).w);
	float D = abs(Tex.Sample(Filter, uv, int2(0, -1)).w);
	float X = ((R - M) + (M - L)) * .5;
	float Y = ((D - M) + (M - U)) * .5;
#endif

	return normalize(float3(X, Y, 1.0f / fNormalDepth));
}

float3 ApplySRGBCurve(float3 x)
{
	// Approximately pow(x, 1.0 / 2.2)
	return x < 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

float3 RemoveSRGBCurve(float3 x)
{
	// Approximately pow(x, 2.2)
	return x < 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
}
