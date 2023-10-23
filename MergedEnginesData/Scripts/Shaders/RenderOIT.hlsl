#include "Shared.h"

cbuffer ShaderConstants0 : register(b0)
{
	int screenWidth;
	int screenHeight;
}

StructuredBuffer<OITData> fragments : register(t0);
RWTexture2D<float4> mainRT : register(u0);
RWTexture2D<uint> clearMask : register(u1);

[numthreads(8, 8, 1)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	if (dispatchThreadID.x >= screenWidth || dispatchThreadID.y >= screenHeight)
		return;

	const uint2 screenPos = dispatchThreadID.xy;

	// get pixel clear state to see if we fragments data
	bool clear = clearMask[screenPos];

	// get current frame buffer color  
	float3 background = mainRT[screenPos].rgb;

	float3 color = background;
	if (!clear)
	{
		uint offsetAddress = (screenWidth * screenPos.y + screenPos.x);
		// read fragments array for current pixel
		OITData data = fragments[offsetAddress];

		float trans = 1;
		color = 0;

		// blend out fragments
		uint i = 0;
		while (i < MAX_OIT_NODE_COUNT && data.frags[i].depth < MAX_OIT_DEPTH)
		{
			color += trans * data.frags[i].color.rgb;
			trans = data.frags[i].trans;
			i++;
		}
		// blend the background color
		color.rgb += background * trans;
		//color.rgb = float(i) / MAX_OIT_NODE_COUNT;

		// dont with pixel so clear it for next frame
		clearMask[screenPos] = true;
	}
	
	mainRT[screenPos] = float4(color.rgb, 1);
}
