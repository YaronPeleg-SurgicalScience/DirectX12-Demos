#include "PostShared.h"

#define BLOOM_LEVELS 5

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 3
// * Param_Texture - Texture containing mip maps stored as tiles
// * Param_Strength - Bloom strength value
// * Param_Falloff - Mip map fall of value
// Result = Bloom effect on current backbuffer
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;
float param_strength;
float param_falloff;

float3 ReadBloomTile(in float2 uv, in float lod) 
{
	// Calculate those values to compute both tile transform and sampling bounds
	float offset = 1.0 - exp2(1.0 - lod);
	float width = exp2(-lod);

	// Inverse atlas transform
	uv *= width; // /= exp2(lod)
	uv += offset;

	// The single-texel margin is needed to account for linear atlas filtering issues
	// Can be removed if set to nearest, but the bloom will look blocky and awful
	// The bounding without margin is not needed at all, so both shall be removed together
	float2 bounds = float2(offset, offset + width);
	float margin = max(param_texture_TexelSize.x, param_texture_TexelSize.y);
	bounds.x += margin;
	bounds.y -= margin;
	uv = clamp(uv, bounds.x, bounds.y);

	return param_texture.Sample(FilterLinear, uv).xyz;
}

float3 GetBloom(in float2 uv) 
{
	float weight = 1.0;
	float4 color = 0;
	for (int i = 1; i <= BLOOM_LEVELS; i++) 
	{
		color.xyz += ReadBloomTile(uv, float(i)) * weight;
		color.w += weight;
		weight *= param_falloff;
	}
	return color.xyz / color.w;
}

float3 BloomTile(float lod, float2 offset, float2 uv) 
{
	return param_texture.Sample(FilterLinear, uv * exp2(-lod) + offset).xyz;
}

float3 GetBloomTiles(float2 uv) 
{
	float3 blur = 0;
	blur = BloomTile(2, float2(0.0, 0.0), uv) + blur * param_falloff;
	blur = BloomTile(3, float2(0.3, 0.0), uv) * 0.3 + blur * param_falloff;
	blur = BloomTile(4, float2(0.0, 0.3), uv) * 0.6 + blur * param_falloff;
	blur = BloomTile(5, float2(0.1, 0.3), uv) * 0.9 + blur * param_falloff;
	blur = BloomTile(6, float2(0.2, 0.3), uv) * 1.2 + blur * param_falloff;
	return blur;
}

float4 ps_main(PS_IN In) : SV_Target
{
	float2 uv = In.Tex;//In.Pos.xy* param_texture_TexelSize.xy;
	float4 result;
	result = TextureBackbuffer.Sample(FilterLinear, uv);
#if 1
	float3 bloom = GetBloom(uv) * param_strength;
#else
	float3 bloom = GetBloomTiles(uv) * param_strength;
#endif
	result.xyz += bloom;

	return result;
}
