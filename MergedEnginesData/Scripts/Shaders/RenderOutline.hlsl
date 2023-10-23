#include "Shared.h"

// texture resources
Texture2D Texture0 : register(t0);

// samplers
SamplerState FilterPoint;

// constants
cbuffer ShaderConstants0
{
	float3 vOutlineColor;
	float fOutlineSize;
	int iOutlineSteps;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

PS_IN vs_main(uint vertexID : SV_VertexID)
{
	PS_IN Out;
	/*
		orenk: fullscreen triangle 
		note: VP = viewport
	    B(-1,3)
	        |\ 
	        |  \
	        |----\
	        | VP | \ 
	        |____|___\
	    A(-1,-1)    C(3,-1) 
	*/
	Out.Pos = float4((float)(vertexID >> 1) * 4.0f - 1.0f, (float)(vertexID % 2) * 4.0f - 1.0f, 0, 1);
	Out.Tex = float2((float)(vertexID >> 1) * 2.0f, 1.0f - (float)(vertexID % 2) * 2.0f);;
	return Out;
}

float4 DrawOutline(in float2 uv, const float4 outline_color, in float outlineSize, const int steps)
{
	// check if we have something
	float curr_val = Texture0.Sample(FilterPoint, uv, int2(0, 0)).w;
	clip(curr_val - 0.0000001f); // early out

	const float total = float(steps) / TWO_PI;
	for (int i = 0; i < steps; i++) 
	{
		// sample in a circular pattern
		float j = float(i) / total;
		float comp_val = Texture0.SampleLevel(FilterPoint, uv + float2(sin(j), cos(j)) * outlineSize, 0).w;
		// check current sample with circular sample
		if (curr_val != comp_val) 
			return outline_color;	// found diff so its an outline
	}
	return 0;
}

float4 ps_main(PS_IN In) : SV_Target
{
	// outline
	return DrawOutline(In.Tex, float4(vOutlineColor,1), fOutlineSize, iOutlineSteps);
}
