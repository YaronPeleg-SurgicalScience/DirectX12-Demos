#include "Shared.h"

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;
Texture2D Texture0 : register(t0);

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


float4 ps_main(PS_IN In) : SV_Target0
{
	return Texture0.SampleLevel(FilterPoint, In.Tex, 0);
}
