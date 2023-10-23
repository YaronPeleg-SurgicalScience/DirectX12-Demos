//////////////////////////////////////////////////////////////////////////
// VXGI - anisotrpoic mip map generating prepare pass (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////
#include "../Shared.h"

cbuffer ShaderConstants0 : register(b0)
{
	int MipDimension;
}

//Texture3D<uint> voxelTexture : register(t0);
Texture3D<float4> voxelTexture : register(t0);

//unfortunately, there is no "RWTexture3DArray"
RWTexture3D<float4> voxelTextureResultPosX : register(u1);
RWTexture3D<float4> voxelTextureResultNegX : register(u2);
RWTexture3D<float4> voxelTextureResultPosY : register(u3);
RWTexture3D<float4> voxelTextureResultNegY : register(u4);
RWTexture3D<float4> voxelTextureResultPosZ : register(u5);
RWTexture3D<float4> voxelTextureResultNegZ : register(u6);

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

	int3 sourcePos = dispatchThreadID * 2;
	float4 values[8];
	[unroll]
	for (int i = 0; i < 8; i++)
	{
		//values[i] = UnpackRGBA(voxelTexture.Load(int4(sourcePos + anisoOffsets[i], 0)));
		values[i] = voxelTexture.Load(int4(sourcePos + anisoOffsets[i], 0));
	}

	voxelTextureResultPosX[dispatchThreadID] = 
		(
			(values[4] + values[0] * (1 - values[4].a) + 
			 values[5] + values[1] * (1 - values[5].a) +
			 values[6] + values[2] * (1 - values[6].a) + 
			 values[7] + values[3] * (1 - values[7].a)) * 0.25f);

	voxelTextureResultNegX[dispatchThreadID] = 
		(
			(values[0] + values[4] * (1 - values[0].a) + 
			 values[1] + values[5] * (1 - values[1].a) +
			 values[2] + values[6] * (1 - values[2].a) + 
			 values[3] + values[7] * (1 - values[3].a)) * 0.25f);

	voxelTextureResultPosY[dispatchThreadID] = 
		(
			(values[2] + values[0] * (1 - values[2].a) + 
		 	 values[3] + values[1] * (1 - values[3].a) +
			 values[7] + values[5] * (1 - values[7].a) + 
			 values[6] + values[4] * (1 - values[6].a)) * 0.25f);

	voxelTextureResultNegY[dispatchThreadID] = 
		(
			(values[0] + values[2] * (1 - values[0].a) + 
			 values[1] + values[3] * (1 - values[1].a) +
			 values[5] + values[7] * (1 - values[5].a) + 
			 values[4] + values[6] * (1 - values[4].a)) * 0.25f);

	voxelTextureResultPosZ[dispatchThreadID] = 
		(
			(values[1] + values[0] * (1 - values[1].a) + 
			 values[3] + values[2] * (1 - values[3].a) +
			 values[5] + values[4] * (1 - values[5].a) + 
			 values[7] + values[6] * (1 - values[7].a)) * 0.25f);

	voxelTextureResultNegZ[dispatchThreadID] =
		(
			(values[0] + values[1] * (1 - values[0].a) + 
			 values[2] + values[3] * (1 - values[2].a) +
			 values[4] + values[5] * (1 - values[4].a) + 
			 values[6] + values[7] * (1 - values[6].a)) * 0.25f);
}
