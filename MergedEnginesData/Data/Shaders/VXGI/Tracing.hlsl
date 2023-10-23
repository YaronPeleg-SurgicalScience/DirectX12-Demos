//////////////////////////////////////////////////////////////////////////
// VXGI - voxel based global illumination using cone tracing (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////
#include "../Shared.h"

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 InvViewProj;
	float3 vCameraPos;
	int screenWidth;
	int screenHeight;
}

// VXGI constants
cbuffer VXGIConstants : register(b1)
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
	float fMaxMips;
	float fLerpValue;
}

// samplers
SamplerState FilterLinear;

// G-Buffer
Texture2D TextureGBuffer0 : register(t0);
Texture2D TextureGBuffer1 : register(t1);
Texture2D TextureGBuffer2 : register(t2);
Texture2D TextureGBuffer3 : register(t3);
Texture2D TextureGBuffer4 : register(t4);
// D-Buffer
Texture2D TextureDBuffer0 : register(t5);;
Texture2D TextureDBuffer1 : register(t6);;
Texture2D TextureDBuffer2 : register(t7);;
// VXGI
Texture3D<float4> voxelTexturePosX : register(t8);
Texture3D<float4> voxelTextureNegX : register(t9);
Texture3D<float4> voxelTexturePosY : register(t10);
Texture3D<float4> voxelTextureNegY : register(t11);
Texture3D<float4> voxelTexturePosZ : register(t12);
Texture3D<float4> voxelTextureNegZ : register(t13);
Texture3D<float4> voxelTexture	   : register(t14);

RWTexture2D<float4> result : register(u0);

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
/*
	uint width;
	uint height;
	uint depth;
	voxelTexturePosX.GetDimensions(width, height, depth);

	width >>= anisoLevel;
	height >>= anisoLevel;
	depth >>= anisoLevel;
*/
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
/*
	float3 offset = float3(fVoxelSampleOffset, fVoxelSampleOffset, fVoxelSampleOffset);
	float3 voxelTextureUV = worldPosition / fWorldVoxelScale * 2.0f;
	voxelTextureUV.y = -voxelTextureUV.y;
	voxelTextureUV = voxelTextureUV * 0.5f + 0.5f + offset;
	return GetAnisotropicSample(voxelTextureUV, weight, lod, posX, posY, posZ);
*/
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
		lodLevel = min(lodLevel, fMaxMips);
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
		result += TraceCone(origin, normal, coneDirection, coneAperture, voxelResolution) * diffuseConeWeights[i];
	}
	return fIndirectDiffuseStrength * result;
}

[numthreads(8, 8, 1)]
void cs_main(int3 dispatchThreadID : SV_DispatchThreadID)
{
	if (dispatchThreadID.x >= screenWidth || dispatchThreadID.y >= screenHeight)
		return;

	const float2 screenPos = dispatchThreadID.xy;
	const float2 uv = screenPos / float2(screenWidth, screenHeight);
	float4 prevResult = result[screenPos];

	// sample G-Buffer
	float fPixelDepth = TextureGBuffer0[screenPos].x;
	float3 vWorldPos = GetWorldPosition(fPixelDepth, uv, InvViewProj);
	float4 normalWS_AO = TextureGBuffer1[screenPos];
	float3 normalWS = normalize(normalWS_AO.xyz);
	float4 albedo = TextureGBuffer2[screenPos];
	float4 roughness_metallicness = TextureGBuffer3[screenPos];
	float roughness = roughness_metallicness.x;
	float metallic = roughness_metallicness.y;

	// sample D-Buffer
	float3 decal_normalWS = normalize(TextureDBuffer0[screenPos].xyz * 2 - 1);
	float4 decal_albedo = TextureDBuffer1[screenPos];
	float3 decal_roughness_metallicness = TextureDBuffer2[screenPos].xyz;
	float decal_roughness = decal_roughness_metallicness.x;
	float decal_metallic = decal_roughness_metallicness.y;

	// composite gbuffer and dbuffer
	albedo.xyz = lerp(albedo.xyz, decal_albedo.xyz, decal_albedo.a);
	roughness = lerp(roughness, decal_roughness, decal_albedo.a);
	metallic = lerp(metallic, decal_metallic, decal_albedo.a);
	normalWS = normalize(lerp(normalWS, decal_normalWS, decal_albedo.a));

	uint3 texDimensions;
	voxelTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);

	float3 pos_noise = 0;//InterleavedGradientNoise(screenPos.xy) * 0.5f;

	float4 indirectDiffuse = CalculateIndirectDiffuse(vWorldPos + pos_noise, normalWS, texDimensions.x);
	float4 indirectSpecular = (metallic > 0.0f) ? CalculateIndirectSpecular(vWorldPos + pos_noise, normalWS, roughness, metallic, texDimensions.x) : 0;

	float4 color = 0;
#if 0
	// debug mips
	float3 direction = normalWS;
	float lod = 1;
	lod = min(lod, fMaxMips);
	color = GetVoxel(vWorldPos, direction * direction, lod, direction.x > 0.0, direction.y > 0.0, direction.z > 0.0);
	result[screenPos] = float4(color.xyz, 1);
	return;
#endif
#if 0
	// debug cone tracing
	color = 0;
//	ao = 0;
	for (int i = 0; i < NUM_CONES; ++i)
	{
		float3 coneDirection = normalize(normalWS + diffuseConeDirections[i]);
		coneDirection *= dot(coneDirection, normalWS) < 0 ? -1 : 1;

		float tempAo = 0.0f;
		color += diffuseConeWeights[i] * TraceCone(vWorldPos + normalWS * fVoxelSize * 4, normalWS, coneDirection, coneAperture, texDimensions.x);
//		ao += tempAo * diffuseConeWeights[i];
	}
	result[screenPos] = float4(fIndirectDiffuseStrength * color.xyz, color.a);
	return;
#endif

//	result[screenPos] = float4(normalWS.xyz, 1);
//	result[screenPos] = float4(indirectDiffuse.xyz, indirectDiffuse.a);
//	result[screenPos] = float4(indirectSpecular.xyz, indirectDiffuse.a);

	// ORENK: reduce GI flickering for moving objects, some TAA solution should be done
	//		  TAA needs velocity buffer and all engine rendering stuff MUST maintain correct velocities or other issues will pop :(
	// FOR NOW, IT DOESN'T WORTH THE TIME AND EFEORT 
	float4 currResult = saturate(float4(indirectDiffuse.rgb * albedo.rgb + indirectSpecular.rgb, indirectDiffuse.a));
	result[screenPos] = currResult;//lerp(prevResult, currResult, 0.1);
}
