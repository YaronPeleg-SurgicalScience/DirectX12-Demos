#include "PostShared.h"

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 1
// * Param_Texture - Texture to appply effect on 
// Result = Tone mapped texture with pixels in [0..255] range
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;

float3 TonemapACES(in float3 color) 
{
	float a = 2.51;
	float b = 0.03;
	float c = 2.43;
	float d = 0.59;
	float e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

float4 ps_main(PS_IN In) : SV_Target
{
	float2 uv = In.Tex;
	float4 result = param_texture.Sample(FilterLinear, uv);
	result.xyz = TonemapACES(result.xyz);
	return result;
}
