#define MAX_OIT_NODE_COUNT 4
//#define USE_INSTANCES	1
#include "Shared.h"

#define PCSS					0	// if 0 use pcf filtering
#define	NUM_SAMPLES				32
#define	NUM_BLOCKER_SAMPLES		(NUM_SAMPLES/2)

RasterizerOrderedTexture2D<uint> clearMask : register(u0);
RasterizerOrderedStructuredBuffer<OITData> fragments : register(u1);

#if (USE_INSTANCES == 1)
struct tInstance
{
	float4x4 World;
	float4x4 WorldIT;
};
StructuredBuffer<tInstance> InstancesBuffer : register(t0);
#endif

// texture resources
Texture2D TextureAlbedo : register(t1);
Texture2D TextureNormal : register(t2);
Texture2D TextureDetailNormal : register(t3);
Texture2D TextureRoughness : register(t4);
Texture2D TextureMetallicness : register(t5);
Texture2D TextureAO : register(t6);
Texture2D TextureAlbedoPainting : register(t7);
Texture2D TextureRMHPainting : register(t8);

// VXGI
Texture3D<float4> voxelTexturePosX : register(t9);
Texture3D<float4> voxelTextureNegX : register(t10);
Texture3D<float4> voxelTexturePosY : register(t11);
Texture3D<float4> voxelTextureNegY : register(t12);
Texture3D<float4> voxelTexturePosZ : register(t13);
Texture3D<float4> voxelTextureNegZ : register(t14);
Texture3D<float4> voxelTexture	   : register(t15);

StructuredBuffer<tSpotLight> arrSpotLights : register(t0, space1);
StructuredBuffer<tPointLight> arrPointLights : register(t0, space2);

// shadow map for all spot lights
Texture2D TextureSpotShadowMap[32] : register(t0, space3);
Texture2D TextureSpotShadowMapColor[32] : register(t0, space4);

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;
SamplerState FilterShadows;
SamplerState FilterShadowsColor;
SamplerState FilterAlbedo;
SamplerState FilterNormal;
SamplerState FilterDetailNormal;
SamplerState FilterRoughness;
SamplerState FilterMetallicness;
SamplerState FilterAO;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float3 vCameraPos;
	float4x4 ViewProj;
	float4x4 World;
	float4x4 WorldIT;
	int screenWidth;
	float fGIPower;
};

cbuffer MaterialConstants : register(b1)
{
	float4 vDiffuseColor;
	float4 vSpecularColor;
	float4 vSubsurfaceColor;	// xyz = subsurface radius, different value per channel, w = subsurface intensity
	float4 vPaintingFactorColor;// painting color factor
	float4 vPaintingFactorRMH;	// painting rmh factor
	float4 vTiling;				// xy = texture tiling, zw = detail normal map tiling
	float fBumpiness;
	float fDetailBumpiness;
	float fRoughness;
	float fMetallicness;
	float fAO;
	float fAlphaRef;	// alpha test ref value
	float fGIStrength;	// global illumination strength value
	float fRefractionIndex; // refraction index
	float fBatchGroup;	// 8 bit value
	uint BatchFlags;	// 8 bit flags
	int4 iChannelORM;	// x = ao, y = roughness, z = metallicness
	int iNormalMapCompression;	// normal map compression type
	int iDetailNormalMapCompression;	// detail normal map compression type
	int iTwoSidedLighting;	// enable/disable two-sided lighting
	int iEnablePainting;	// enable/disable painting
	int iTransparent;		// transparent state (0 = opaque else transparent)
	int iSubsurfaceScattering; // subsurface scattering state
};
cbuffer LightingConstants : register(b2)
{
	int NumSpotLights, NumPointLights;
}
cbuffer VXGIConstants : register(b3)
{
	float3 vCameraCenter;
	float fWorldVoxelScale;
	float fVoxelSize;
	float fIndirectDiffuseStrength;
	float fIndirectSpecularStrength;
	float fMaxConeTraceDistance;
	float fAOFalloff;
	float fSamplingFactor;
	float fVoxelSampleOffset;
	float fDiffuseOffset;
	float fSpecularOffset;
}

// world space to voxel space
float3 WorldToVoxel(in float3 pos, in float lod = 0)
{
	float3 result = pos - vCameraCenter;
	result /= fWorldVoxelScale;
	return result / fVoxelSize;
}

// voxel space to world pace
float3 VoxelToWorld(in float3 pos)
{
	float3 result = pos;
	result *= fVoxelSize * fWorldVoxelScale;
	return result + vCameraCenter;
}

// voxel space to uvw 3d texture space
float3 VoxelToUVW(in float3 pos)
{
	return float3(0.5f * float3(pos.x, -pos.y, pos.z) + float3(0.5f, 0.5f, 0.5f));
}

float4 GetAnisotropicSample(float3 uv, float3 weight, float lod, bool posX, bool posY, bool posZ)
{
	int anisoLevel = max(lod - 1.0f, 0.0f);

	uint width;
	uint height;
	uint depth;
	voxelTexturePosX.GetDimensions(width, height, depth);

	width >>= anisoLevel;
	height >>= anisoLevel;
	depth >>= anisoLevel;

	//	float4 anisoSample =
	//		weight.x * ((posX) ? UnpackRGBA(voxelTexturePosX.Load(int4(uv, anisoLevel))) : UnpackRGBA(voxelTextureNegX.Load(int4(uv, anisoLevel)))) +
	//		weight.y * ((posY) ? UnpackRGBA(voxelTexturePosY.Load(int4(uv, anisoLevel))) : UnpackRGBA(voxelTextureNegY.Load(int4(uv, anisoLevel)))) +
	//		weight.z * ((posZ) ? UnpackRGBA(voxelTexturePosZ.Load(int4(uv, anisoLevel))) : UnpackRGBA(voxelTextureNegZ.Load(int4(uv, anisoLevel))));

	float4 anisoSample =
		weight.x * ((posX) ? voxelTexturePosX.SampleLevel(FilterLinear, uv, anisoLevel) : voxelTextureNegX.SampleLevel(FilterLinear, uv, anisoLevel)) +
		weight.y * ((posY) ? voxelTexturePosY.SampleLevel(FilterLinear, uv, anisoLevel) : voxelTextureNegY.SampleLevel(FilterLinear, uv, anisoLevel)) +
		weight.z * ((posZ) ? voxelTexturePosZ.SampleLevel(FilterLinear, uv, anisoLevel) : voxelTextureNegZ.SampleLevel(FilterLinear, uv, anisoLevel));

	if (lod < 1.0f)
	{
#if 0
		uint3 texDimensions;
		voxelTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);
		float4 baseColor = UnpackRGBA(voxelTexture.Load(int4(floor(texDimensions * uv), 0)));
#else
		float4 baseColor = voxelTexture.SampleLevel(FilterLinear, uv, 0);
#endif
		anisoSample = lerp(baseColor, anisoSample, clamp(lod, 0.0f, 1.0f));
	}

	return anisoSample;
}

float4 GetVoxel(float3 worldPosition, float3 weight, float lod, bool posX, bool posY, bool posZ)
{
	float3 offset = float3(fVoxelSampleOffset, fVoxelSampleOffset, fVoxelSampleOffset);
	float3 voxelTextureUV = VoxelToUVW(WorldToVoxel(worldPosition, lod)) + offset;
	return GetAnisotropicSample(voxelTextureUV, weight, lod, posX, posY, posZ);
}

float4 TraceCone(float3 pos, float3 normal, float3 direction, float aperture, uint voxelResolution)
{
	aperture = max(0.1f, aperture); // inf loop if 0
	float3 color = 0.0f;
	float occlusion = 0.0f;

	// offset start position to avoid self-occlusion but doing so will result in disconnection between nearby surfaces...
	// NOTE: sqrt2 is diagonal voxel half-extent
	float voxelWorldSize = fVoxelSize;// *2.0f * SQRT2;//  fWorldVoxelScale / float(voxelResolution);
	float dist = voxelWorldSize;
	float3 startPos = pos + normal * dist;
	float3 weight = direction * direction;
	while (dist < fMaxConeTraceDistance && occlusion < 1.0f)
	{
		float diameter = 2.0f * aperture * dist;
		float lodLevel = log2(diameter / voxelWorldSize);
		//		lodLevel = min(lodLevel, 6);
		float4 voxelColor = GetVoxel(startPos + direction * dist, weight, lodLevel, direction.x > 0.0, direction.y > 0.0, direction.z > 0.0);
		// front to back blending
		float a = 1 - occlusion;
		color += a * voxelColor.rgb;
		occlusion += (a * voxelColor.a) / (1.0f + fAOFalloff * diameter);
		dist += diameter * fSamplingFactor;
	}

	occlusion = saturate(occlusion);
	return float4(color, occlusion);
}

float4 CalculateIndirectSpecular(float3 worldPos, float3 normal, float roughness, float metallic, uint voxelResolution)
{
	float3 viewDirection = normalize(vCameraPos - worldPos);
	float3 coneDirection = (reflect(-viewDirection, normal));

	float3 origin = worldPos + normal * fVoxelSize * fSpecularOffset;
	float aperture = clamp(CalculateSpecularConeHalfAngle(roughness * roughness), fOneDegree * fMaxDegreesCount, PI);
	float4 result = TraceCone(origin, normal, coneDirection, aperture, voxelResolution);

	return fIndirectSpecularStrength * result * metallic;
}

float4 CalculateIndirectRefraction(float3 worldPos, float3 normal, float roughness, float refractionIndex, float transparency, uint voxelResolution)
{
	float3 viewDirection = normalize(vCameraPos - worldPos);
	float3 coneDirection = refract(-viewDirection, normal, 1.0f / refractionIndex);

	float3 origin = worldPos + normal * fVoxelSize * fSpecularOffset;
	float aperture = clamp(CalculateSpecularConeHalfAngle(roughness * roughness), fOneDegree * fMaxDegreesCount, PI);
	float4 result = TraceCone(origin, normal, coneDirection, aperture, voxelResolution);
//	float4 specCol = lerp(vSpecularColor, 0.5f * (vSpecularColor + 1), transparency);;
	return result;// *specCol;
}

float4 CalculateIndirectDiffuse(in float3 worldPos, in float3 normal, in uint voxelResolution)
{
	float3 coneDirection;

	float3 upDir = float3(0.0f, 1.0f, 0.0f);
	if (abs(dot(normal, upDir)) == 1.0f)
		upDir = float3(0.0f, 0.0f, 1.0f);

	float3 right = normalize(upDir - dot(normal, upDir) * normal);
	float3 up = cross(right, normal);

	float3 origin = worldPos + normal * fVoxelSize * fDiffuseOffset;
	float4 result = 0;
	for (int i = 0; i < NUM_CONES; i++)
	{
		coneDirection = normalize(normal + diffuseConeDirections[i].x * right + diffuseConeDirections[i].z * up);
		//		coneDirection = normalize(normal + diffuseConeDirections[i]);
				// if point on sphere is facing below normal (so it's located on bottom hemisphere), put it on the opposite hemisphere instead:
		//		coneDirection *= dot(coneDirection, normal) < 0 ? -1 : 1;

		result += TraceCone(origin, normal, coneDirection, coneAperture, voxelResolution) * diffuseConeWeights[i];
		//		finalAo += tempAo * diffuseConeWeights[i];
	}

	return fIndirectDiffuseStrength * result;
}

// vs input
struct VS_IN
{
	float4 Pos : Vertex;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
	float2 Tex : TexCoord;
};

// ps input
struct PS_IN
{
	float4 Pos : SV_Position;
	float4 vHPos : HPosition;
	float3 vWorldPos : WorldPos;
	float2 Tex : TexCoord;
	float2 DetailTex : DetailTexCoord;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
};

// vs
PS_IN vs_main(VS_IN In
#if (USE_INSTANCES == 1)
	, uint instanceId : SV_InstanceID
#endif
)
{
	float4x4 matWorld, matWorldIT;
#if (USE_INSTANCES == 1)
	tInstance instance = InstancesBuffer[instanceId];
	matWorld = instance.World;
	matWorldIT = instance.WorldIT;
#else
	matWorld = World;
	matWorldIT = WorldIT;
#endif

	PS_IN Out;
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), matWorld).xyz;
	Out.Pos = mul(float4(Out.vWorldPos.xyz, 1), ViewProj);
	Out.vHPos = Out.Pos;
	Out.Tex = In.Tex * vTiling.xy;
	Out.DetailTex = In.Tex * vTiling.zw;
	Out.Normal = mul(In.Normal.xyz, (float3x3)matWorldIT);
	Out.Tangent = mul(In.Tangent.xyz, (float3x3)matWorldIT);
	Out.Bitangent = mul(In.Bitangent.xyz, (float3x3)matWorldIT);
	return Out;
}

float3 ComputePaintingNormal(in float2 uv, in float fNormalDepth)
{
	float L = abs(GetLuminance(TextureAlbedoPainting.Sample(FilterLinear, uv, int2(-1, 0)).xyz));
	float R = abs(GetLuminance(TextureAlbedoPainting.Sample(FilterLinear, uv, int2(1, 0)).xyz));
	float U = abs(GetLuminance(TextureAlbedoPainting.Sample(FilterLinear, uv, int2(0, -1)).xyz));
	float D = abs(GetLuminance(TextureAlbedoPainting.Sample(FilterLinear, uv, int2(0, 1)).xyz));

	float X = (L - R) * .5;
	float Y = (U - D) * .5;

	return normalize(float3(X, Y, 1.0f / fNormalDepth));
}

float4 ComputeShading(PS_IN In, bool bIsFrontFacing)
{
	// base color
	float4 baseColor = TextureAlbedo.Sample(FilterAlbedo, In.Tex);
	// alpha test
	clip(baseColor.a - fAlphaRef);
	baseColor *= vDiffuseColor;

	// get normal in tangent space
	float3 normalTS = SampleNormalMap(TextureNormal, FilterNormal, In.Tex, iNormalMapCompression).xyz;

	// get detail normal in tangent space
	float3 detailNormalTS = SampleNormalMap(TextureDetailNormal, FilterDetailNormal, In.DetailTex, iDetailNormalMapCompression).xyz;

	// painting
	float4 paintingColor = 0;
	float4 paintingRMH = 0;
	float3 paintingNormal = 0;
	if (iEnablePainting > 0)
	{
		paintingColor = TextureAlbedoPainting.Sample(FilterLinear, In.Tex);
		paintingColor *= vPaintingFactorColor;
		paintingRMH = TextureRMHPainting.Sample(FilterLinear, In.Tex);
		paintingRMH *= vPaintingFactorRMH;
		paintingNormal = ComputePaintingNormal(In.Tex, 0.001f + paintingRMH.z * 255);
	}

	// control bumpiness
	const float3 vSmoothNormal = { 0.0f, 0.0f, 1.0f };
	normalTS = lerp(vSmoothNormal, normalTS.xyz, max(fBumpiness, 0.001f));

	// control detail bumpiness
	detailNormalTS = lerp(vSmoothNormal, detailNormalTS.xyz, max(fDetailBumpiness, 0.001f));

	// blend painting with our normal map
	if (iEnablePainting > 0)
		normalTS = lerp(normalTS, paintingNormal, paintingRMH.w);

	normalTS = NormalBlend_UnpackedRNM(normalTS, detailNormalTS);

	// transform into world space
	float3 normalWS = normalize(normalize(In.Tangent) * normalTS.x + normalize(In.Bitangent) * normalTS.y + normalize(In.Normal) * normalTS.z);
	// get roughness
	float roughness = TextureRoughness.Sample(FilterRoughness, In.Tex)[iChannelORM.y] * fRoughness;
	// get metallicness
	float metallic = TextureMetallicness.Sample(FilterMetallicness, In.Tex)[iChannelORM.z] * fMetallicness;
	// get ao
	float ao = TextureAO.Sample(FilterAO, In.Tex)[iChannelORM.x] * fAO;

	// blend painting
	if (iEnablePainting > 0)
	{
		baseColor.xyz = lerp(baseColor.xyz, paintingColor.xyz, paintingColor.w);
		metallic = lerp(metallic, paintingRMH.y, paintingRMH.w);
		roughness = lerp(roughness, paintingRMH.x, paintingRMH.w);
	}

	float4 albedo = baseColor;

	// VXGI
	uint3 texDimensions;
	voxelTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);

	float4 indirectDiffuse = CalculateIndirectDiffuse(In.vWorldPos, normalWS, texDimensions.x);
	float4 indirectSpecular = (metallic > 0.0f) ? CalculateIndirectSpecular(In.vWorldPos, normalWS, roughness, metallic, texDimensions.x) : 0;
	float3 indirectColor = indirectDiffuse.rgb * albedo.rgb + indirectSpecular.rgb;
	float4 indirectRefraction = (baseColor.a > 0.0f) ? CalculateIndirectRefraction(In.vWorldPos, normalWS, roughness, fRefractionIndex, baseColor.a, texDimensions.x) : 0;
//	indirectColor = indirectRefraction;//lerp(indirectRefraction.rgb, indirectColor.rgb, albedo.a);

	float4 vxgi = saturate(float4(indirectColor, indirectDiffuse.a));
	ao *= (1 - vxgi.w);
	float3 indirectLighting = vxgi.xyz * fGIPower;

	// Lerp with metallic value to find the good diffuse and specular.
	float3 realAlbedo = albedo.xyz - albedo.xyz * metallic;

	// 0.03 default specular value for dielectric.
	float3 realSpecularColor = lerp(0.03f, albedo.xyz, metallic);

	// to eye
	float3 vToEyeNorm = normalize(vCameraPos.xyz - In.vWorldPos);

	float3 finalDiffuse = 0;
	float3 finalSpecular = 0;

	// spot lights
	int i;
	[loop]
	for (i = 0; i < NumSpotLights; ++i)
	{
		const tSpotLight light = arrSpotLights[i];

		// to light
		float3 vToLight = (light.vPosition - In.vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse, specular, subsurface;
		ComputeLight(realAlbedo, realSpecularColor, (iSubsurfaceScattering > 0) ? vSubsurfaceColor : 0, normalWS, roughness, light.vPosition.xyz, light.vDiffuseColor.xyz, light.vSpecularColor.xyz, vToLightNorm, vToEyeNorm, diffuse, specular, subsurface, iTwoSidedLighting > 0);

		// cone att
		float cosIn = light.vData.x;
		float cosOut = light.vData.y;
		float fLightNear = light.vData.z;
		float fLightFar = light.vData.w;
		float cosAng = dot(light.vDirection, -vToLightNorm);
		float conAtt = saturate((cosAng - cosOut) / (cosIn - cosOut));
		conAtt *= conAtt;
		// light att
		float att = pow(saturate(1 - length(vToLight) / fLightFar), 2);
		att *= conAtt;

		// shadow map
		float4 vPosLight = mul(float4(In.vWorldPos.xyz, 1), light.ViewProj);

		// shadow map coord
		float2 uv = 0.5 * vPosLight.xy / vPosLight.w + float2(0.5, 0.5);
		uv.y = 1.0f - uv.y;

		// get current depth value
		float depth = vPosLight.z / vPosLight.w;

		// Compute gradient using ddx/ddy before any branching
		float2 dz_duv = 0;//DepthGradient(uv, depth);

#if (PCSS == 1)
		float zEye = -ZClipToZEye(vPosLight.z / vPosLight.w, fLightNear, fLightFar);
		float3 shadow = PCSS_Shadow(TextureSpotShadowMap[i], FilterShadows, TextureSpotShadowMapColor[i], FilterShadowsColor, uv, depth, zEye, light.fRadiusUV, fLightNear, fLightFar, In.Pos.xy, dz_duv, SHADOWMAP_BIAS, NUM_SAMPLES, NUM_BLOCKER_SAMPLES);
#else
		float3 shadow = GetSpotLightShadowMapSoft(TextureSpotShadowMap[i], FilterShadows, TextureSpotShadowMapColor[i], FilterShadowsColor, uv, depth, In.Pos.xy, 0.005f, dz_duv, SHADOWMAP_BIAS, NUM_SAMPLES);
#endif

		// accumulate
		finalDiffuse += shadow * att * ao * diffuse + att * subsurface;
		finalSpecular += shadow * att * ao * specular;
	}

	// point lights
	[loop]
	for (i = 0; i < NumPointLights; ++i)
	{
		const tPointLight light = arrPointLights[i];

		// to light
		float3 vToLight = (light.vPosition - In.vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse, specular, subsurface;
		ComputeLight(realAlbedo, realSpecularColor, (iSubsurfaceScattering > 0) ? vSubsurfaceColor : 0, normalWS, roughness, light.vPosition.xyz, light.vDiffuseColor.xyz, light.vSpecularColor.xyz, vToLightNorm, vToEyeNorm, diffuse, specular, subsurface, iTwoSidedLighting > 0);

		// att
		float fLightRange = light.vData.w + 0.0000001f;
		float att = 1.0f - saturate(length(vToLight) / fLightRange);

		// accumulate
		finalDiffuse += att * ao * (diffuse + subsurface);
		finalSpecular += att * ao * specular;
	}

	// lighting
	return float4(ao * indirectLighting + finalDiffuse + finalSpecular, albedo.a);
}

[earlydepthstencil]
void ps_main(PS_IN In, bool bIsFrontFacing : SV_IsFrontFace)
{
	// compute pixel shading
	float4 litPixel = ComputeShading(In, bIsFrontFacing);

	uint2 screenPos = uint2(In.Pos.xy);

	// flag to determine if the pixel is clear
	bool clear = clearMask[screenPos];

	// compute offset to structured buffer for this pixel
	uint offsetAddress = (screenWidth * screenPos.y + screenPos.x);

	tTransparentFragment frags[MAX_OIT_NODE_COUNT];

	// compute depth, color and transmission for the new fragment
	const float dist = In.vHPos.z / In.vHPos.w;
	const float fragmentDepth = dist;
	const float3 fragmentColor = litPixel.rgb * litPixel.a;
	const float fragmentTransmission = 1 - litPixel.a;
	int i;

	// if pixel is clear then we need to initialize fragments node array
	if (clear)
	{
		// initialize first fragment
		frags[0].color = fragmentColor;
		frags[0].trans = fragmentTransmission;
		frags[0].depth = fragmentDepth;

		// reset rest of fragments
		for (int i = 1; i < MAX_OIT_NODE_COUNT; i++)
		{
			frags[i].color = 0;
			frags[i].trans = 0;
			frags[i].depth = MAX_OIT_DEPTH;
		}

		// mark the pixel as not clear (so we know it contain fragments)
		clearMask[screenPos] = false;
	}
	else
	{
		// not clear, get our fragments
		frags = fragments[offsetAddress].frags;

		float	depth[MAX_OIT_NODE_COUNT + 1];
		float	trans[MAX_OIT_NODE_COUNT + 1];
		float3	color[MAX_OIT_NODE_COUNT + 1];

		// split data into different arrays
		for (i = 0; i < MAX_OIT_NODE_COUNT; i++)
		{
			depth[i] = frags[i].depth;
			trans[i] = frags[i].trans;
			color[i] = frags[i].color;
		}

		// find position we need to insert the new fragment
		int index = 0;
		float prevTrans = 1;
		for (i = 0; i < MAX_OIT_NODE_COUNT; i++)
		{
			if (fragmentDepth > depth[i])
			{
				index++;
				prevTrans = trans[i];
			}
		}

		// make room for the new fragment. 
		for (i = MAX_OIT_NODE_COUNT - 1; i >= index; i--)
		{
			depth[i + 1] = depth[i];
			trans[i + 1] = trans[i] * fragmentTransmission;
			color[i + 1] = color[i];
		}

		// adjust the fragment transmission 
		const float newFragTrans = fragmentTransmission * prevTrans;

		// insert new fragment
		depth[index] = fragmentDepth;
		trans[index] = newFragTrans;
		color[index] = fragmentColor;

		// combine two last nodes if we have too many (this assure constant memory requirment)
		if (depth[MAX_OIT_NODE_COUNT] < MAX_OIT_DEPTH && MAX_OIT_NODE_COUNT > 1)
		{
			float3 toBeRemovedCol = color[MAX_OIT_NODE_COUNT].rgb;
			float3 toBeAccumulCol = color[MAX_OIT_NODE_COUNT - 1].rgb;

			// combine to new color and trans (make sure trans wont exceed 1)
			float3 newColor = toBeAccumulCol + toBeRemovedCol * min(1, trans[MAX_OIT_NODE_COUNT - 1] * rcp(trans[MAX_OIT_NODE_COUNT - 2]));
			
			// set last fragment node
			color[MAX_OIT_NODE_COUNT - 1] = newColor;
			trans[MAX_OIT_NODE_COUNT - 1] = trans[MAX_OIT_NODE_COUNT];
		}

		// setup data to copy to our structure buffer
		for (int i = 0; i < MAX_OIT_NODE_COUNT; ++i)
		{
			frags[i].depth = depth[i];
			frags[i].trans = trans[i];
			frags[i].color = color[i];
		}
	}
	
	// set pixel fragments
	fragments[offsetAddress].frags = frags;
}
