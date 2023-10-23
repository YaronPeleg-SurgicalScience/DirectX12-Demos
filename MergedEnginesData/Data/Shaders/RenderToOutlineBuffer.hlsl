#include "Shared.h"

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
};

// vs input
struct VS_IN
{
	float4 Pos : Vertex;
};

// ps input
struct PS_IN
{
	float4 Pos : SV_Position;
};

// vs
PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	float3 vWorldPos = mul(float4(In.Pos.xyz, 1), World).xyz;
	Out.Pos = mul(float4(vWorldPos.xyz, 1), ViewProj);
	return Out;
}

// ps
float4 ps_main(PS_IN In) : SV_Target
{
	return 1;
}
