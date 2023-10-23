#define USE_BG_NORMAL_MAP 1
//#define USE_INSTANCES	1

#include "Shared.h"

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
Texture2D TextureSSS : register(t7);
Texture2D TextureAlbedoPainting : register(t8);
Texture2D TextureRMHPainting : register(t9);

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;
SamplerState FilterAlbedo;
SamplerState FilterNormal;
SamplerState FilterDetailNormal;
SamplerState FilterRoughness;
SamplerState FilterMetallicness;
SamplerState FilterAO;
SamplerState FilterSSS;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
	float4x4 WorldIT;
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

struct PS_OUT
{
	float4 RT[5] : SV_Target0;
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

// ps
PS_OUT ps_main(PS_IN In)
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
		paintingNormal = ComputePaintingNormal(TextureRMHPainting, FilterLinear, In.Tex, 0.001f + paintingRMH.z * 50);
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
	float metallicness = TextureMetallicness.Sample(FilterMetallicness, In.Tex)[iChannelORM.z] * fMetallicness;
	// get ao
	float ao = TextureAO.Sample(FilterAO, In.Tex)[iChannelORM.x] * fAO;
	// get sss
	float4 sss = TextureSSS.Sample(FilterSSS, In.Tex);

	// blend painting
	if (iEnablePainting > 0)
	{
		baseColor.xyz = lerp(baseColor.xyz, paintingColor.xyz, paintingColor.w);
		metallicness = lerp(metallicness, paintingRMH.y, paintingRMH.w);
		roughness = lerp(roughness, paintingRMH.x, paintingRMH.w);
	}

	// output result
	PS_OUT Out;
	Out.RT[0] = In.vHPos.z / In.vHPos.w;
	Out.RT[1] = float4(normalWS.xyz, ao);
	Out.RT[2] = float4(baseColor.xyz, iTwoSidedLighting);
	Out.RT[3] = float4(roughness, metallicness, saturate(fBatchGroup / 255.0f), BatchFlags);
	Out.RT[4] = (iSubsurfaceScattering > 0) ? (vSubsurfaceColor * sss) : 0;
	return Out;
}
