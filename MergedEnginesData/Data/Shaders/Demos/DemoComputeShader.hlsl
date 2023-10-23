cbuffer ShaderConstants0 : register(b0)
{
	int blockSize;
	int resultWidth;
	int resultHeight;
}

Texture2D<float4> input : register(t0);
RWTexture2D<float4> result : register(u0);

#define AVG	// use avg color vs single color

[numthreads(32, 32, 1)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	if (dispatchThreadID.x >= resultWidth || dispatchThreadID.y >= resultHeight)
		return;

	const float2 startPos = dispatchThreadID.xy * blockSize;
	if (startPos.x >= resultWidth || startPos.y >= resultHeight)
		return;

	const int blockWidth = min(blockSize, resultWidth - startPos.x);
	const int blockHeight = min(blockSize, resultHeight - startPos.y);
	const int numPixels = blockHeight * blockWidth;

	int i;
#ifdef AVG
	float4 color = 0;
	for (i = 0; i < blockWidth; ++i)
	{
		for (int j = 0; j < blockHeight; ++j)
		{
			const uint2 pixelPos = uint2(startPos.x + i, startPos.y + j);
			color += input[pixelPos];
		}
	}
	color /= numPixels;
#else
	float4 color = input[startPos];
#endif

	for (i = 0; i < blockWidth; ++i)
	{
		for (int j = 0; j < blockHeight; ++j)
		{
			const uint2 pixelPos = uint2(startPos.x + i, startPos.y + j);
			result[pixelPos] = color;
		}
	}
}
