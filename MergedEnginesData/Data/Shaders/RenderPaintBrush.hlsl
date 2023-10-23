#include "Shared.h"

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
};
cbuffer PaintingConstants : register(b1)
{
	int NumPaintBrushes;
}
StructuredBuffer<tPaintBrush> arrPaintBrushes : register(t0);

// vs input
struct VS_IN
{
	float4 Pos : Vertex;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
	float2 Tex : TexCoord;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float3 vWorldPos : WorldPos;
	float2 Tex : TexCoord;
};

struct PS_OUT
{
	float4 RT[2] : SV_Target0;
};

PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), World).xyz;
	float2 uv = float2(In.Tex.x, 1 - In.Tex.y);
	Out.Pos = float4(uv * 2 - 1, 0, 1);	// unwrap
	Out.Tex = In.Tex;;
	return Out;
}

float SphereMask(in float3 position, in float3 center, in float radius, in float hardness)
{
	return saturate((radius - distance(position, center)) / (1 - saturate(hardness)));
}

PS_OUT ps_main(PS_IN In)
{
	float4 color = 0;
	float4 rmh = 0;

	for (int i = 0; i < NumPaintBrushes; ++i)
	{
		const tPaintBrush brush = arrPaintBrushes[i];
		float falloff = SphereMask(In.vWorldPos.xyz, brush.vPosition.xyz, brush.fRadius, brush.fHardness);
		float alpha = falloff * brush.fStrength;
		bool bPaintColor = (brush.iPaintFlags & E_PBPF_COLOR) != 0;
		bool bPaintR = (brush.iPaintFlags & E_PBPF_ROUGHNESS) != 0;
		bool bPaintM = (brush.iPaintFlags & E_PBPF_METALLICNESS) != 0;
		bool bPaintH = (brush.iPaintFlags & E_PBPF_HEIGHT) != 0;
		bool bErase = (brush.iPaintFlags & E_PBPF_ERASE) != 0;

		if (alpha > 0.0f)
		{
			if (bPaintColor)
			{
				color.xyz = brush.vColor.xyz;
				color.w = brush.vColor.w * alpha;
			}
			if (bPaintM)
			{
				rmh.y = brush.fMetallicness;
				rmh.w = alpha;
			}
			if (bPaintR)
			{
				rmh.x = brush.fRoughness;
				rmh.w = alpha;
			}
			if (bPaintH)
			{
				rmh.z = brush.fHeight;
				rmh.w = alpha;
			}
		}
		if (bErase)
		{
			// premultiply alpha to fix black edges
			color.xyz *= alpha;
			rmh.xyz *= alpha;
		}
	}

	PS_OUT Out;
	Out.RT[0] = color;
	Out.RT[1] = rmh;
	return Out;
}
