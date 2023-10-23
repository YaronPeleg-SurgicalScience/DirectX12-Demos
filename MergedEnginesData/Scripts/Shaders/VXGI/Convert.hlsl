//////////////////////////////////////////////////////////////////////////
// VXGI - convert packed voxels to rgba voxels (ORENK - 2023)
// NOTE: we must convert to RGBA so we could use HW filtering when tracing!
//////////////////////////////////////////////////////////////////////////
#include "../Shared.h"

cbuffer ShaderConstants0 : register(b0)
{
	int MipDimension;
}

Texture3D<uint> voxelTextureSource : register(t0);
RWTexture3D<float4> voxelTextureDest : register(u1);

[numthreads(8, 8, 8)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	if (dispatchThreadID.x >= MipDimension || dispatchThreadID.y >= MipDimension || dispatchThreadID.z >= MipDimension)
		return;

	int3 sourcePos = dispatchThreadID;
	voxelTextureDest[sourcePos] = uint_to_float4(voxelTextureSource.Load(int4(sourcePos, 0)));
}
