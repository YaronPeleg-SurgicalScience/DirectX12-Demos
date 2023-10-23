//////////////////////////////////////////////////////////////////////////
// VXGI - debug rendering of scene voxels (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////
#include "../Shared.h"

//Texture3D<uint> voxelTexture;
Texture3D<float4> voxelTexture;

// samplers
SamplerState FilterLinear;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 ViewProj;
	float4x4 World;
	float4x4 WorldVoxelCube;
	float3 vCameraCenter;
	float fWorldVoxelScale;
	float fVoxelSize;
};

// vs input
struct VS_IN
{
	uint vertexID : SV_VertexID;
};

// ps input
struct PS_IN
{
	float4 Pos : SV_Position;
	float4 Color : Color;
};

struct GS_IN
{
	float4 vVoxelPos : VoxelPos;
	float4 Color : Color;
};

struct PS_OUT
{
	float4 Result : SV_Target0;
};

// vs
GS_IN vs_main(VS_IN In)
{
	GS_IN Out = (GS_IN)0;

	uint3 texDimensions;
	voxelTexture.GetDimensions(texDimensions.x, texDimensions.y, texDimensions.z);

	// compute voxel pos in [0..VolumeSize] range
	float3 centerVoxelPos;
	centerVoxelPos.x = In.vertexID % texDimensions.x;
	centerVoxelPos.y = In.vertexID / (texDimensions.x * texDimensions.x);
	centerVoxelPos.z = (In.vertexID / texDimensions.x) % texDimensions.x;

	// set voxel pos in [-VolumeSize/2..VolumeSize/2] range
	Out.vVoxelPos = float4(centerVoxelPos - fWorldVoxelScale, 1.0f);
	Out.vVoxelPos.y = -Out.vVoxelPos.y;
	// sample voxel color
//	Out.Color = UnpackRGBA(voxelTexture.Load(int4(centerVoxelPos, 0)));
	Out.Color = voxelTexture.Load(int4(centerVoxelPos, 0));
	Out.Color.xyz *= Out.Color.a;
//	Out.Color = voxelTexture.SampleLevel(FilterLinear, centerVoxelPos / float3(texDimensions), 0);
	return Out;
}

// http://www.asmcommunity.net/forums/topic/?id=6284
static const int INDICES[14] =
{
   4, 3, 7, 8, 5, 3, 1, 4, 2, 7, 6, 5, 2, 1,
};

// gs
[maxvertexcount(14)] 
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
#if 1
	// eraly exit if voxel is empty
	if (input[0].Color.a < 0.01f)
		return;
#endif
#if 1
	input[0].vVoxelPos.xyz *= fVoxelSize;
	input[0].vVoxelPos.xyz += vCameraCenter;

	// discard voxel outside the viewing volume
	float4 vPos = mul(float4(input[0].vVoxelPos.xyz, 1), ViewProj);
	float w = vPos.w + fVoxelSize * SQRT2;
	if (abs(vPos.z) > w || abs(vPos.x) > w || abs(vPos.y) > w)
		return;

	float4 v[8];
	float fS = fVoxelSize * 0.5f;
	v[0] = (input[0].vVoxelPos + float4(-fS, +fS, -fS, 0));
	v[1] = (input[0].vVoxelPos + float4(+fS, +fS, -fS, 0));
	v[2] = (input[0].vVoxelPos + float4(-fS, +fS, +fS, 0));
	v[3] = (input[0].vVoxelPos + float4(+fS, +fS, +fS, 0));
	v[4] = (input[0].vVoxelPos + float4(-fS, -fS, -fS, 0));
	v[5] = (input[0].vVoxelPos + float4(+fS, -fS, -fS, 0));
	v[6] = (input[0].vVoxelPos + float4(+fS, -fS, +fS, 0));
	v[7] = (input[0].vVoxelPos + float4(-fS, -fS, +fS, 0));

	PS_IN output = (PS_IN)0;
	//  Indices are off by one, so we just let the optimizer fix it
	[unroll]
	for (int i = 0; i < 14; i++)
	{
		output.Pos = mul(float4(v[INDICES[i] - 1].xyz, 1), ViewProj);
		output.Color = input[0].Color;
		OutputStream.Append(output);
	}
#else

	PS_IN output[36];
	for (int i = 0; i < 36; i++)
	{
		output[i] = (PS_IN)0;
		output[i].Color = input[0].Color;
	}
	input[0].vVoxelPos.xyz *= 0.5f;
	float fS = 0.25f;

	float4 v1 = mul((input[0].vVoxelPos + float4(-fS, fS, fS, 0)), WorldVoxelCube);
	float4 v2 = mul((input[0].vVoxelPos + float4( fS, fS, fS, 0)), WorldVoxelCube);
	float4 v3 = mul((input[0].vVoxelPos + float4(-fS,-fS, fS, 0)), WorldVoxelCube);
	float4 v4 = mul((input[0].vVoxelPos + float4( fS,-fS, fS, 0)), WorldVoxelCube);
	float4 v5 = mul((input[0].vVoxelPos + float4(-fS, fS,-fS, 0)), WorldVoxelCube);
	float4 v6 = mul((input[0].vVoxelPos + float4( fS, fS,-fS, 0)), WorldVoxelCube);
	float4 v7 = mul((input[0].vVoxelPos + float4(-fS,-fS,-fS, 0)), WorldVoxelCube);
	float4 v8 = mul((input[0].vVoxelPos + float4( fS,-fS,-fS, 0)), WorldVoxelCube);

	v1 = mul(v1, ViewProj);
	v2 = mul(v2, ViewProj);
	v3 = mul(v3, ViewProj);
	v4 = mul(v4, ViewProj);
	v5 = mul(v5, ViewProj);
	v6 = mul(v6, ViewProj);
	v7 = mul(v7, ViewProj);
	v8 = mul(v8, ViewProj);

	// +Z
	output[0].Pos = v4;
	OutputStream.Append(output[0]);
	output[1].Pos = v3;
	OutputStream.Append(output[1]);
	output[2].Pos = v1;
	OutputStream.Append(output[2]);
	OutputStream.RestartStrip();

	output[3].Pos = v2;
	OutputStream.Append(output[3]);
	output[4].Pos = v4;
	OutputStream.Append(output[4]);
	output[5].Pos = v1;
	OutputStream.Append(output[5]);
	OutputStream.RestartStrip();

	// -Z
	output[6].Pos = v7;
	OutputStream.Append(output[6]);
	output[7].Pos = v8;
	OutputStream.Append(output[7]);
	output[8].Pos = v6;
	OutputStream.Append(output[8]);
	OutputStream.RestartStrip();

	output[9].Pos = v5;
	OutputStream.Append(output[9]);
	output[10].Pos = v7;
	OutputStream.Append(output[10]);
	output[11].Pos = v6;
	OutputStream.Append(output[11]);
	OutputStream.RestartStrip();

	// +X
	output[12].Pos = v8;
	OutputStream.Append(output[12]);
	output[13].Pos = v4;
	OutputStream.Append(output[13]);
	output[14].Pos = v2;
	OutputStream.Append(output[14]);
	OutputStream.RestartStrip();

	output[15].Pos = v6;
	OutputStream.Append(output[15]);
	output[16].Pos = v8;
	OutputStream.Append(output[16]);
	output[17].Pos = v2;
	OutputStream.Append(output[17]);
	OutputStream.RestartStrip();

	// -X
	output[18].Pos = v3;
	OutputStream.Append(output[18]);
	output[19].Pos = v7;
	OutputStream.Append(output[19]);
	output[20].Pos = v5;
	OutputStream.Append(output[20]);
	OutputStream.RestartStrip();

	output[21].Pos = v1;
	OutputStream.Append(output[21]);
	output[22].Pos = v3;
	OutputStream.Append(output[22]);
	output[23].Pos = v5;
	OutputStream.Append(output[23]);
	OutputStream.RestartStrip();

	// +Y
	output[24].Pos = v2;
	OutputStream.Append(output[24]);
	output[25].Pos = v1;
	OutputStream.Append(output[25]);
	output[26].Pos = v5;
	OutputStream.Append(output[26]);
	OutputStream.RestartStrip();

	output[27].Pos = v6;
	OutputStream.Append(output[27]);
	output[28].Pos = v2;
	OutputStream.Append(output[28]);
	output[29].Pos = v5;
	OutputStream.Append(output[29]);
	OutputStream.RestartStrip();
	
	// -Y
	output[30].Pos = v8;
	OutputStream.Append(output[30]);
	output[31].Pos = v7;
	OutputStream.Append(output[31]);
	output[32].Pos = v3;
	OutputStream.Append(output[32]);
	OutputStream.RestartStrip();

	output[33].Pos = v4;
	OutputStream.Append(output[33]);
	output[34].Pos = v8;
	OutputStream.Append(output[34]);
	output[35].Pos = v3;
	OutputStream.Append(output[35]);
	OutputStream.RestartStrip();
#endif
}

// ps
PS_OUT ps_main(PS_IN In)
{
	PS_OUT Out = (PS_OUT)0;

	Out.Result = float4(In.Color.rgb, 1);
	return Out;
}
