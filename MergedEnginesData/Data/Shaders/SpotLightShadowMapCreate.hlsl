#include "Shared.h"
//#define USE_INSTANCES	1

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

// samplers
SamplerState FilterPoint;
SamplerState FilterAlbedo;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
}

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
	float2 Tex : TexCoord;
};

struct PS_OUTPUT
{
	float4 RT[2] : SV_Target0;
};

// vs
PS_IN vs_main(VS_IN In
#if (USE_INSTANCES == 1)
	, uint instanceId : SV_InstanceID
#endif
)
{
	float4x4 matWorld;
#if (USE_INSTANCES == 1)
	tInstance instance = InstancesBuffer[instanceId];
	matWorld = instance.World;
#else
	matWorld = World;
#endif

	PS_IN Out;
	float3 vWorldPos = mul(float4(In.Pos.xyz, 1), matWorld).xyz;
	Out.Pos = mul(float4(vWorldPos.xyz, 1), ViewProj);
	Out.vHPos = Out.Pos;
	Out.Tex = In.Tex;
	return Out;
}

// ps
PS_OUTPUT ps_main(PS_IN In)
{
	PS_OUTPUT Out;
	// base color
	float4 baseColor = TextureAlbedo.Sample(FilterAlbedo, In.Tex);
	// alpha test
	clip(baseColor.a - fAlphaRef);
	baseColor *= vDiffuseColor;
#if 0
	return (In.vHPos.z / In.vHPos.w) * 0.01f;
#endif	
	// gamma correction fix
	baseColor.xyz = pow(baseColor.xyz, 1.0f / 2.2f);
	// store shadow map depth
	Out.RT[0] = In.vHPos.z / In.vHPos.w;
	// store color and secondary depth in alpha for corrent ordering of transparent shadows
	Out.RT[1] = (iTransparent > 0) ? float4(baseColor.xyz * baseColor.w, In.vHPos.z / In.vHPos.w) : float4(1, 1, 1, 1);
	return Out;
}
