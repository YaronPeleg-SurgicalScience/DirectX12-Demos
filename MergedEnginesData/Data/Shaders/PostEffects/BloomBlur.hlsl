#include "PostShared.h"

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 2
// * Param_Texture - Texture to apply effect on 
// * Param_Direction - Direction vector of blur
// Result = Directional blur texture
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;
float4 param_direction;

#define BLOOM_QUALITY 9 // 3 - Low; 5 - Normal; 7 - High; 9 - Ultra

float3 textureBlur(in float2 uv, in int size) 
{
	float lod = ceil(-log2(1.0 - uv.x));

	float2 tileCoord = uv;
	tileCoord -= 1.0 - exp2(1.0 - lod);
	tileCoord *= exp2(lod);

	// Saturate the coord
	if (any(tileCoord <= 0)) return 0;
	if (any(tileCoord >= 1)) return 0;

	float maxLength = length(float2(size, size));

	float4 color = 0;
	for (int i = -size; i <= size; i++) 
	{
		float2 offset = param_direction.xy * i;
		float weight = 1.0 - smoothstep(0.0, 1.0, sqrt(length(offset) / maxLength));

		float2 sampleCoord = uv + param_texture_TexelSize.xy * offset;

		color.xyz += param_texture.Sample(FilterLinear, sampleCoord).xyz * weight;
		color.w += weight;
	}
	return color.xyz / color.w;
}

float4 ps_main(PS_IN In) : SV_Target
{
	return float4(textureBlur(In.Tex, BLOOM_QUALITY), 1);
}
