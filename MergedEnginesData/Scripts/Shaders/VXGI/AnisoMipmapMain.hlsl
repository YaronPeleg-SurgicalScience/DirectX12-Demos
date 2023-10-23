//////////////////////////////////////////////////////////////////////////
// VXGI - anisotrpoic mip map generating main pass (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////
#include "../Shared.h"

cbuffer ShaderConstants0 : register(b0)
{
	int MipDimension;
	int MipLevel;
}

Texture3D<float4> voxelTextureSrcPosX : register(t0);
Texture3D<float4> voxelTextureSrcNegX : register(t1);
Texture3D<float4> voxelTextureSrcPosY : register(t2);
Texture3D<float4> voxelTextureSrcNegY : register(t3);
Texture3D<float4> voxelTextureSrcPosZ : register(t4);
Texture3D<float4> voxelTextureSrcNegZ : register(t5);

RWTexture3D<float4> voxelTextureResultPosX : register(u6);
RWTexture3D<float4> voxelTextureResultNegX : register(u7);
RWTexture3D<float4> voxelTextureResultPosY : register(u8);
RWTexture3D<float4> voxelTextureResultNegY : register(u9);
RWTexture3D<float4> voxelTextureResultPosZ : register(u10);
RWTexture3D<float4> voxelTextureResultNegZ : register(u11);

static const int3 anisoOffsets[8] =
{
	int3(1, 1, 1),
	int3(1, 1, 0),
	int3(1, 0, 1),
	int3(1, 0, 0),
	int3(0, 1, 1),
	int3(0, 1, 0),
	int3(0, 0, 1),
	int3(0, 0, 0)
};

[numthreads(8, 8, 8)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	if (dispatchThreadID.x >= MipDimension || dispatchThreadID.y >= MipDimension || dispatchThreadID.z >= MipDimension)
		return;

	if (MipLevel == 0)
	{
		voxelTextureResultPosX[dispatchThreadID] = voxelTextureSrcPosX[dispatchThreadID];
		voxelTextureResultNegX[dispatchThreadID] = voxelTextureSrcNegX[dispatchThreadID];
		voxelTextureResultPosY[dispatchThreadID] = voxelTextureSrcPosY[dispatchThreadID];
		voxelTextureResultNegY[dispatchThreadID] = voxelTextureSrcNegY[dispatchThreadID];
		voxelTextureResultPosZ[dispatchThreadID] = voxelTextureSrcPosZ[dispatchThreadID];
		voxelTextureResultNegZ[dispatchThreadID] = voxelTextureSrcNegZ[dispatchThreadID];
		return;
	}

	int3 sourcePos = dispatchThreadID * 2;
	float4 values[8];
	int i;

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcPosX.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultPosX[dispatchThreadID] = (
		(values[4] + values[0] * (1 - values[4].a) + 
			values[5] + values[1] * (1 - values[5].a) +
			values[6] + values[2] * (1 - values[6].a) +
			values[7] + values[3] * (1 - values[7].a)) * 0.25f);

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcNegX.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultNegX[dispatchThreadID] = (
		(values[0] + values[4] * (1 - values[0].a) + 
			values[1] + values[5] * (1 - values[1].a) +
			values[2] + values[6] * (1 - values[2].a) + 
			values[3] + values[7] * (1 - values[3].a)) * 0.25f);

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcPosY.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultPosY[dispatchThreadID] = (
		(values[2] + values[0] * (1 - values[2].a) + 
			values[3] + values[1] * (1 - values[3].a) +
			values[7] + values[5] * (1 - values[7].a) +
			values[6] + values[4] * (1 - values[6].a)) * 0.25f);

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcNegY.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultNegY[dispatchThreadID] = (
		(values[0] + values[2] * (1 - values[0].a) +
			values[1] + values[3] * (1 - values[1].a) +
			values[5] + values[7] * (1 - values[5].a) + 
			values[4] + values[6] * (1 - values[4].a)) * 0.25f);

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcPosZ.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultPosZ[dispatchThreadID] = (
		(values[1] + values[0] * (1 - values[1].a) + 
			values[3] + values[2] * (1 - values[3].a) +
			values[5] + values[4] * (1 - values[5].a) + 
			values[7] + values[6] * (1 - values[7].a)) * 0.25f);

	[unroll]
	for (i = 0; i < 8; i++)
		values[i] = (voxelTextureSrcNegZ.Load(int4(sourcePos + anisoOffsets[i], MipLevel - 1)));
	
	voxelTextureResultNegZ[dispatchThreadID] = (
		(values[0] + values[1] * (1 - values[0].a) + 
			values[2] + values[3] * (1 - values[2].a) +
			values[4] + values[5] * (1 - values[4].a) +
			values[6] + values[7] * (1 - values[6].a)) * 0.25f);
}
