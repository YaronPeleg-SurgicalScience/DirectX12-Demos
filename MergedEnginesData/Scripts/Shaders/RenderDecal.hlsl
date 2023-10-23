#define USE_BG_NORMAL_MAP 1
#include "Shared.h"

// G-Buffer
Texture2D TextureBuffer0 : register(t0);	// need depth
Texture2D TextureBuffer3 : register(t1);	// need group

// texture resources
Texture2D TextureAlbedo : register(t2);
Texture2D TextureNormal : register(t3);
Texture2D TextureDetailNormal : register(t4);
Texture2D TextureRoughness : register(t5);
Texture2D TextureMetallicness : register(t6);
Texture2D TextureAO : register(t7);

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;
SamplerState FilterAlbedo;
SamplerState FilterNormal;
SamplerState FilterDetailNormal;
SamplerState FilterRoughness;
SamplerState FilterMetallicness;
SamplerState FilterAO;

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 InvViewProj;
	float4x4 World;
	float4x4 InvWorld;
	float4 vEntityValues;
	float2 vInvRTSize;
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

struct GS_IN
{
	float3 Pos : Vertex;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float4 vHPos : HPosition;
};

GS_IN vs_main(uint vertexID : SV_VertexID)
{
	// just pass it to GS
	GS_IN Out = (GS_IN)0;
	return Out;
}

void GenerateTransformedBox(out float4 v[8])
{
	float4 center = World[3];
	float4 X = float4(World[0].xyz, 0);
	float4 Y = float4(World[1].xyz, 0);
	float4 Z = float4(World[2].xyz, 0);
	center = mul(center, ViewProj);
	X = mul(X, ViewProj);
	Y = mul(Y, ViewProj);
	Z = mul(Z, ViewProj);

	float4 t1 = center - X - Z;
	float4 t2 = center + X - Z;
	float4 t3 = center - X + Z;
	float4 t4 = center + X + Z;
	v[0] = t1 + Y;
	v[1] = t2 + Y;
	v[2] = t3 + Y;
	v[3] = t4 + Y;
	v[4] = t1 - Y;
	v[5] = t2 - Y;
	v[6] = t4 - Y;
	v[7] = t3 - Y;
}

// http://www.asmcommunity.net/forums/topic/?id=6284
static const int INDICES[14] =
{
   4, 3, 7, 8, 5, 3, 1, 4, 2, 7, 6, 5, 2, 1,
};

[maxvertexcount(14)]
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
	PS_IN output = (PS_IN)0;
	float4 v[8];
	GenerateTransformedBox(v);

	//  Indices are off by one, so we just let the optimizer fix it
	[unroll]
	for (int i = 0; i < 14; i++)
	{
		output.Pos = v[INDICES[i] - 1];
		output.vHPos = output.Pos;
		OutputStream.Append(output);
	}
}

struct PS_OUT
{
	float4 RT[3] : SV_Target0;
};

float2 ComputeDecalUVFromWorldPosition(in float3 vWorldPos)
{
	// compute object space position which tells us if position inside (or not) of our 1x1x1 cube centered at (0, 0, 0)
	float4 objectPos = mul(float4(vWorldPos.xyz, 1), InvWorld);

	// multiple by 0.5 to convert our decal box (generated from GS) from [-1..1] to [-0.5..0.5]
	objectPos *= 0.5f;

	// reject anything outside
	clip(0.5 - abs(objectPos.xyz));

	// generate texcoords by adding 0.5
	float2 vTexCoord = objectPos.xz + 0.5f;
	// fix orientation
	vTexCoord.y = 1 - vTexCoord.y;
	return vTexCoord;
}

//float4 ps_main(PS_IN In) : SV_Target
PS_OUT ps_main(PS_IN In)
{
	PS_OUT Out = (PS_OUT)0;

	// generate screen uv
	float2 vScreenUV = GetScreenSpaceUV(In.vHPos);

	// reject decal using batch group
	float4 gbuffer_roughness_metallicness = TextureBuffer3.Sample(FilterLinear, vScreenUV);
	int gbuffer_group = int(gbuffer_roughness_metallicness.z * 255 + 0.5f);
	int decal_group = int(fBatchGroup);
	clip(decal_group == gbuffer_group ? 1 : -1);

	// get world position of our pixel
	float d = TextureBuffer0.SampleLevel(FilterPoint, vScreenUV, 0).x;
	float3 vWorldPos = GetWorldPosition(d, vScreenUV, InvViewProj);
	float2 vTexCoord = ComputeDecalUVFromWorldPosition(vWorldPos);

#if 1
	float dx0 = TextureBuffer0.SampleLevel(FilterPoint, vScreenUV, 0, int2(-1, 0)).x;
	float dx1 = TextureBuffer0.SampleLevel(FilterPoint, vScreenUV, 0, int2(+1, 0)).x;
	float dy0 = TextureBuffer0.SampleLevel(FilterPoint, vScreenUV, 0, int2(0, -1)).x;
	float dy1 = TextureBuffer0.SampleLevel(FilterPoint, vScreenUV, 0, int2(0, +1)).x;

	float3 vWorldPos_x, vWorldPos_y;

	// find suitable neighbor world positions in x and y so we can compute correct gradients for sampling decal textures
	// compute world position on x,y based on the smallest different in depth
	float4 screen_pos_x, screen_pos_y;
	if (abs(dx0 - d) < abs(dx1 - d))
		vWorldPos_x = GetWorldPosition(dx0, vScreenUV + int2(-1,0) * vInvRTSize, InvViewProj);
	else
		vWorldPos_x = GetWorldPosition(dx1, vScreenUV + int2(+1, 0) * vInvRTSize, InvViewProj);

	if (abs(dy0 - d) < abs(dy1 - d))
		vWorldPos_y = GetWorldPosition(dy0, vScreenUV + int2(0, -1) * vInvRTSize, InvViewProj);
	else
		vWorldPos_y = GetWorldPosition(dy1, vScreenUV + int2(0, +1) * vInvRTSize, InvViewProj);

	float2 vTexCoord_x = ComputeDecalUVFromWorldPosition(vWorldPos_x);
	float2 vTexCoord_y = ComputeDecalUVFromWorldPosition(vWorldPos_y);
	// compute correct gradients
	float2 dx = vTexCoord - vTexCoord_x;
	float2 dy = vTexCoord - vTexCoord_y;
#else
	float2 dx = ddx_fine(vTexCoord);
	float2 dy = ddy_fine(vTexCoord);
#endif

	// sample decal textures
	float4 albedo = TextureAlbedo.SampleGrad(FilterAlbedo, vTexCoord, dx, dy) * vDiffuseColor;

	// get ao
	float roughness = TextureRoughness.SampleGrad(FilterRoughness, vTexCoord, dx, dy)[iChannelORM .y] * fRoughness;
	// get ao
	float metallicness = TextureMetallicness.SampleGrad(FilterMetallicness, vTexCoord, dx, dy)[iChannelORM.z] * fMetallicness;

	// get ao
	float ao = TextureAO.SampleGrad(FilterAO, vTexCoord, dx, dy)[iChannelORM.x] * fAO;

	float decal_alpha = saturate(albedo.w * vEntityValues.x);

	// get normal in tangent space
	float3 normalTS = SampleGradNormalMap(TextureNormal, FilterNormal, vTexCoord, dx, dy, iNormalMapCompression).xyz;
	// control bumpiness
	const float3 vSmoothNormal = { 0.0f, 0.0f, 1.0f };
	normalTS = lerp(vSmoothNormal, normalTS.xyz, max(fBumpiness * decal_alpha, 0.001f));

	float3 pixelTangent = mul(float3(1,0,0), (float3x3)World);
	float3 pixelBitangent = mul(float3(0, 0, 1), (float3x3)World);
	float3 pixelNormal = mul(float3(0, 1, 0), (float3x3)World);

	float3 normalWS = normalize(pixelTangent) * normalTS.x + normalize(pixelBitangent) * normalTS.y + normalize(pixelNormal) * normalTS.z;
	normalWS = normalize(normalWS);

	Out.RT[0] = float4(normalWS*0.5f+0.5f, decal_alpha);
	Out.RT[1] = float4(albedo.xyz, decal_alpha);
	Out.RT[2] = float4(roughness, metallicness, ao, decal_alpha);

	return Out;
}
