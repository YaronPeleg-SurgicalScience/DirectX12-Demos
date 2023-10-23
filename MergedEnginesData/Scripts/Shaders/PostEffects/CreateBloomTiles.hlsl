#include "PostShared.h"

#define BLOOM_LEVELS 5

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 1
// * Param_Texture - Texture to compute mip maps for
// Result = Mip maps arranged as tiles
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;

float3 WriteBloomTile(in float2 uv, in float lod) 
{
	// Transform the tile to "atlas space"
	uv -= 1.0 - exp2(1.0 - lod);
	uv *= exp2(lod);

	// Saturate the coord
	if (any(uv <= 0)) return 0;
	if (any(uv >= 1)) return 0;

	// Apply threshold
	float3 color = param_texture.SampleLevel(FilterLinear, uv, lod).xyz;
	return color;
}

float3 MakeBloom(float lod, float2 offset, float2 bCoord) 
{
	float2 pixelSize = param_texture_TexelSize.xy;

	offset += pixelSize;

	float lodFactor = exp2(lod);

	float3 bloom = 0;
	float2 scale = lodFactor * pixelSize;

	float2 coord = (bCoord.xy - offset) * lodFactor;
	float totalWeight = 0;

	if (any(abs(coord - 0.5) >= scale + 0.5))
		return 0;

	for (int i = -5; i < 5; i++)
	{
		for (int j = -5; j < 5; j++) 
		{
			float wg = pow(1.0 - length(float2(i, j)) * 0.125, 6.0);

			float3 color = param_texture.SampleLevel(FilterLinear, float2(i, j) * scale + lodFactor * pixelSize + coord, lod).xyz;
			bloom = color * wg + bloom;
			totalWeight += wg;
		}
	}

	bloom /= totalWeight;

	return bloom;
}

float4 ps_main(PS_IN In) : SV_Target
{
	float2 uv = In.Tex;//In.Pos.xy* param_texture_TexelSize.xy;
#if 1
	float3 blur = 0;
	for (int i = 1; i <= BLOOM_LEVELS; i++) 
		blur.xyz += WriteBloomTile(uv, float(i));
#else
	float3 blur = MakeBloom(2, float2(0.0, 0.0), uv);
	blur += MakeBloom(3, float2(0.3, 0.0), uv);
	blur += MakeBloom(4, float2(0.0, 0.3), uv);
	blur += MakeBloom(5, float2(0.1, 0.3), uv);
	blur += MakeBloom(6, float2(0.2, 0.3), uv);
#endif
	return float4(blur, 1);
}
