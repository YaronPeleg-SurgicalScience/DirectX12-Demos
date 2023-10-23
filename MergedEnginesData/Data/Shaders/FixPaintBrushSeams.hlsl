#include "Shared.h"

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;

Texture2D TexturePaintBrushColor : register(t0);
Texture2D TexturePaintBrushRM : register(t1);

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

struct PS_OUT
{
	float4 RT[2] : SV_Target0;
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

PS_OUT ps_main(PS_IN In)
{
	const int2 offsets[8] =
	{
		int2(-1,-1),
		int2(0,-1),
		int2(1,-1),
		int2(-1, 0),
		// int2( 0, 0),
		int2(1, 0),
		int2(-1, 1),
		int2(0, 1),
		int2(1, 1)
	};
	float4 color = TexturePaintBrushColor.SampleLevel(FilterLinear, In.Tex, 0);
	float4 rm = TexturePaintBrushRM.SampleLevel(FilterLinear, In.Tex, 0);
	for (int i = 0; i < 8; ++i)
	{
		float4 sampleColor = TexturePaintBrushColor.SampleLevel(FilterLinear, In.Tex, 0, offsets[i]);
		float4 sampleRM = TexturePaintBrushRM.SampleLevel(FilterLinear, In.Tex, 0, offsets[i]);
		color = max(color, sampleColor);
		rm = max(rm, sampleRM);
	}
	PS_OUT Out;
	Out.RT[0] = color;
	Out.RT[1] = rm;
	return Out;
}
