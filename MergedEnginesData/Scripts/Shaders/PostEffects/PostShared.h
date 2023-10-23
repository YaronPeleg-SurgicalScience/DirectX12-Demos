#include "../Shared.h"

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;

// constants
cbuffer ShaderConstants0
{
	float3 vCameraPos;
	float fCameraFov;			// camera fov in degrees
	float4 vProjectionParamsAB;	// x = proj a, y = proj b, z = near, w = far (used to construct linear depth from z over w)
	float4x4 InvViewProj;
}

// current backbuffer
Texture2D TextureBackbuffer;
float4 TextureBackbuffer_TexelSize;		// x = 1/width, y = 1/height, z = width, w = height

// previous post result
Texture2D TexturePrevious;
// G-Buffer
Texture2D TextureGBuffer0;
Texture2D TextureGBuffer1;
Texture2D TextureGBuffer2;
Texture2D TextureGBuffer3;
Texture2D TextureGBuffer4;
// D-Buffer
Texture2D TextureDBuffer0;
Texture2D TextureDBuffer1;
Texture2D TextureDBuffer2;

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

