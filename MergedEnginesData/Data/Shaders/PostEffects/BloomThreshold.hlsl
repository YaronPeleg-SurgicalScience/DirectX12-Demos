#include "PostShared.h"

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 2
// * Param_Texture - Texture to extract brightest pixels passing threshold value
// * Param_Threshold - Float value to compare pixel brightness against
// Result = Pixels with Luminance(pixel) > Thrshold
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;
float param_threshold;

float Luminance(in float3 c)
{
	return dot(c.xyz, float3(0.299, 0.587, 0.114));
}

float4 ps_main(PS_IN In) : SV_Target
{
	float2 screen_uv = In.Pos.xy * param_texture_TexelSize.xy;

#if 1
	// IMPORTANT: bloom flickering filter 
	// apply bloom threshold and weight it by color luminance (the larger the luminance value the smaller the weight)
	float2 offsets[] = 
	{
		float2(0.0, 0.0),
		float2(-1.0, -1.0), float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0),
		float2(-1.0, 0.0), float2(1.0, 0.0), float2(0.0, -1.0), float2(0.0, 1.0)
	};
	float3 color = 0.0;
	float weightSum = 0.0;
	for (int i = 0; i < 9; i++)
	{
		// sample texture
		float3 c = param_texture.Sample(FilterLinear, screen_uv + offsets[i] * param_texture_TexelSize.xy * 2.0).rgb;
		// apply threshold
		c = saturate(c - param_threshold);
		// weight by luminance
		float w = 1.0 / (Luminance(c) + 1.0);
		color += c * w;
		// accumulate weights
		weightSum += w;
	}
	// apply weight avg
	color /= weightSum;
	return float4(color, 1.0);

#else

	// naive bloom threshold (no weights => strong flickering)
	float3 c = param_texture.Sample(FilterLinear, screen_uv).xyz;
	c *= saturate(Luminance(c) - param_threshold);

	return float4(c, 1);
#endif
}
