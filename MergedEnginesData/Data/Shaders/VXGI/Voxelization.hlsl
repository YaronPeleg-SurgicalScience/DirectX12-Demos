//////////////////////////////////////////////////////////////////////////
// VXGI - Scene Voxelization (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////
//#define USE_INSTANCES	1

#include "../Shared.h"

RWTexture3D<uint> outputTexture : register(u0);
//RasterizerOrderedTexture3D<float4> outputTexture : register(u0);

#if (USE_INSTANCES == 1)
struct tInstance
{
	float4x4 World;
	float4x4 WorldIT;
};
StructuredBuffer<tInstance> InstancesBuffer : register(t0);
#endif

// G-Buffer
Texture2D TextureAlbedo : register(t1);
Texture2D TextureNormal : register(t2);
Texture2D TextureMetallicness : register(t3);
Texture2D TextureAlbedoPainting : register(t4);
Texture2D TextureRMHPainting : register(t5);

// D-Buffer
Texture2D TextureDBuffer0 : register(t6);
Texture2D TextureDBuffer1 : register(t7);
Texture2D TextureDBuffer2 : register(t8);

// lights
StructuredBuffer<tSpotLight> arrSpotLights : register(t0, space1);
StructuredBuffer<tPointLight> arrPointLights : register(t0, space2);

// shadow map for all spot lights
Texture2D TextureSpotShadowMap[32] : register(t0, space3);
Texture2D TextureSpotShadowMapColor[32] : register(t0, space4);

// samplers
SamplerState FilterLinear;
SamplerState FilterShadows;
SamplerState FilterShadowsColor;
SamplerState FilterAlbedo;
SamplerState FilterNormal;
SamplerState FilterMetallicness;


struct AABB
{
	float3 c, e;
};

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
	float4x4 WorldIT;
	float3 vCameraCenter;
	float fWorldVoxelScale;
	float fVoxelSize;
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
	float3 vPos : Position;
	float4 vHPos : HPosition;
	float3 Normal: Normal;
	float3 vWorldPos : WorldPos;
	centroid float2 Tex : TexCoord;
	centroid float3 vVoxelPos : VoxelPos;
};

struct GS_IN
{
	float3 vWorldPos : WorldPos;
	float4 vHPos : HPosition;
	float3 Normal: Normal;
	float2 Tex : TexCoord;
};

// world space to voxel space
float3 WorldToVoxel(in float3 pos)
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

// vs
GS_IN vs_main(VS_IN In
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
	GS_IN Out;
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), matWorld).xyz;
	Out.vHPos = mul(float4(Out.vWorldPos, 1), ViewProj);
	Out.Normal = mul(In.Normal.xyz, (float3x3)matWorldIT);
	Out.Tex = In.Tex;
	return Out;
}

// gs
[maxvertexcount(3)]
void gs_main(triangle GS_IN input[3], inout TriangleStream<PS_IN> OutputStream)
{
	PS_IN output[3];
	output[0] = (PS_IN)0;
	output[1] = (PS_IN)0;
	output[2] = (PS_IN)0;

//	float3 faceN = normalize(input[0].Normal.xyz + input[1].Normal.xyz + input[2].Normal.xyz);
	float3 faceN = normalize(cross(input[1].vWorldPos.xyz - input[0].vWorldPos.xyz, input[2].vWorldPos.xyz - input[0].vWorldPos.xyz));
	float3 n = abs(faceN);
	float axis = max(n.x, max(n.y, n.z));

	int i;
	[unroll]
	for (i = 0; i < 3; i++)
	{
		// world space to voxel space
		output[i].vVoxelPos = WorldToVoxel(input[i].vWorldPos.xyz);//((input[i].vWorldPos.xyz - vCameraCenter) / fWorldVoxelScale) / fVoxelSize;
		// project onto dominant axis
		if (axis == n.z)
			output[i].Pos = float4(output[i].vVoxelPos.xyz, 1);
		else if (axis == n.y)
			output[i].Pos = float4(output[i].vVoxelPos.xzy, 1);
		else
			output[i].Pos = float4(output[i].vVoxelPos.yzx, 1);

		output[i].vWorldPos = input[i].vWorldPos;
		output[i].Normal = input[i].Normal;
		output[i].Tex = input[i].Tex;
		output[i].vPos = output[i].Pos.xyz;
		output[i].vHPos = input[i].vHPos;
		OutputStream.Append(output[i]);
	}
	OutputStream.RestartStrip();
}

// reference https://www.seas.upenn.edu/~pcozzi/OpenGLInsights/OpenGLInsights-SparseVoxelization.pdf & https://github.com/LeifNode/Novus-Engine 
void ImageAtomicRGBA8Avg(RWTexture3D<uint> imgUI, uint3 coords, float4 val)
{
	uint newVal = float4_to_uint(val);
	uint prevStoredVal = 0;
	uint curStoredVal = 0;
	uint numIterations = 0;
	#define MAX_ITERS 255
	[allow_uav_condition] do
	{
		InterlockedCompareExchange(imgUI[coords], prevStoredVal, newVal, curStoredVal);

		if (curStoredVal == prevStoredVal || numIterations >= MAX_ITERS)
			break;

		prevStoredVal = curStoredVal;
		float4 rval = uint_to_float4(curStoredVal);
		rval.xyz = (rval.xyz * rval.w);	// Denormalize	
		float4 curValF = (rval + val);	// Add
		curValF.rgb /= curValF.a;       // Renormalize
		newVal = float4_to_uint(curValF);
		++numIterations;
	} while (true);
}

// ps
void ps_main(PS_IN In, bool IsFrontFace : SV_IsFrontFace)
{
	// eraly exist if gi strength is too low
	if (fGIStrength < 0.0001f)
		discard;

	// base color
	float4 baseColor = TextureAlbedo.Sample(FilterAlbedo, In.Tex);
	// alpha test
	clip(baseColor.a - fAlphaRef);
	baseColor *= vDiffuseColor;

	float3 vVoxelPos = In.vVoxelPos.xyz;

	int3 texDimensions;
	outputTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);
	int3 finalVoxelPos = floor(texDimensions.xyz * VoxelToUVW(vVoxelPos));

	float4 prevCol = outputTexture[finalVoxelPos];

	// get metallicness
	float metallicness = TextureMetallicness.Sample(FilterMetallicness, In.Tex)[iChannelORM.z] * fMetallicness;

	// generate screen uv
	float2 vScreenUV = GetScreenSpaceUV(In.vHPos);

	// sample D-Buffer
	// IMPORTANT: we sample decal info from D-buffer so when tracing the voxels if decals isn't visible we wont see it effecting the trace!
	//			  to make it effect the trace we need to rasterize the decal geometry BUT its not worth the extra ms
	float4 decal_albedo = TextureDBuffer1.Sample(FilterLinear, vScreenUV);
	float3 decal_roughness_metallicness = TextureDBuffer2.Sample(FilterLinear, vScreenUV).xyz;
	float decal_roughness = decal_roughness_metallicness.x;
	float decal_metallic = decal_roughness_metallicness.y;

	// composite gbuffer and dbuffer
	baseColor.xyz = lerp(baseColor.xyz, decal_albedo.xyz, decal_albedo.a);
	metallicness = lerp(metallicness, decal_metallic, decal_albedo.a);
	float3 normalWS = normalize(In.Normal);

	// painting
	if (iEnablePainting > 0)
	{
		float4 paintingColor = TextureAlbedoPainting.Sample(FilterLinear, In.Tex);
		paintingColor *= vPaintingFactorColor;
		float4 paintingRMH = TextureRMHPainting.Sample(FilterLinear, In.Tex);
		paintingRMH *= vPaintingFactorRMH;

		baseColor.xyz = lerp(baseColor.xyz, paintingColor.xyz, paintingColor.w);
		metallicness = lerp(metallicness, paintingRMH.y, paintingRMH.w);
	}

	///////////////////////////////////////////////////////////////
	// calculate direct lighting onto voxel
	///////////////////////////////////////////////////////////////

	float3 vWorldPos = In.vWorldPos;
//	float3 vWorldPos = VoxelToWorld(vVoxelPos);

	// Lerp with metallic value to find the good diffuse and specular.
	float3 realAlbedo = baseColor.xyz - baseColor.xyz * metallicness;

	// to eye
	float3 vToEyeNorm = normalize(vCameraCenter.xyz - vWorldPos);

	float3 finalDiffuse = 0;

	// spot lights
	float3 shadowAccum = 0.0f;
	int i;

	[loop]
	for (i = 0; i < NumSpotLights; ++i)
	{
		const tSpotLight light = arrSpotLights[i];

		// to light
		float3 vToLight = (light.vPosition - vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse = 0, subsurface = 0;
		//ComputeDiffuseLight(realAlbedo, normalWS, light.vDiffuseColor.xyz, vToLightNorm, diffuse, iTwoSidedLighting > 0);
		ComputeDiffuseLight(realAlbedo, normalWS, light.vDiffuseColor.xyz, vToLightNorm, diffuse);
		if (iSubsurfaceScattering > 0)
			ComputeSubsurfaceScattering(realAlbedo, vSubsurfaceColor, normalWS, vToLightNorm, subsurface);

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
		float4 vPosLight = mul(float4(vWorldPos.xyz, 1), light.ViewProj);
		float3 shadow = GetSpotLightShadowMapFast(TextureSpotShadowMap[i], FilterShadows, TextureSpotShadowMapColor[i], FilterShadowsColor, vPosLight, SHADOWMAP_BIAS);

		// accumulate
		finalDiffuse += shadow * att * diffuse + att * subsurface;
	}

	// point lights
	[loop]
	for (i = 0; i < NumPointLights; ++i)
	{
		const tPointLight light = arrPointLights[i];

		// to light
		float3 vToLight = (light.vPosition - vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse = 0, subsurface = 0;
		//ComputeDiffuseLight(realAlbedo, normalWS, light.vDiffuseColor.xyz, vToLightNorm, diffuse, iTwoSidedLighting > 0);
		ComputeDiffuseLight(realAlbedo, normalWS, light.vDiffuseColor.xyz, vToLightNorm, diffuse);
		if (iSubsurfaceScattering > 0)
			ComputeSubsurfaceScattering(realAlbedo, vSubsurfaceColor, normalWS, vToLightNorm, subsurface);

		// att
		float fLightRange = light.vData.w + 0.0000001f;
		float att = 1.0f - saturate(length(vToLight) / fLightRange);

		// accumulate
		finalDiffuse += att * (diffuse + subsurface);
	}

	if (all(finalVoxelPos <= texDimensions.xyz) && all(finalVoxelPos >= 0))
	{
		float4 writeCol = float4(finalDiffuse.xyz * fGIStrength, 1);
		writeCol.xyz *= (iTransparent > 0) ? baseColor.a : 1;
		// write color
		// IMPORTANT: avoid voxel flickering by using atomic max (because multiple pixels can be mapped to the same voxel cell creating race condition!)
		InterlockedMax(outputTexture[finalVoxelPos], float4_to_uint(writeCol));
//		ImageAtomicRGBA8Avg(outputTexture, finalVoxelPos, writeCol);
	}
}
