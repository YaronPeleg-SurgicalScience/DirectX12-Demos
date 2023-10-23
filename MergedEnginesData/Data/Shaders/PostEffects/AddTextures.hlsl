#include "PostShared.h"

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 3
// * Param_Texture0 - First texture
// * Param_Texture1 - Second texture
// * Param_Scale - First and Second texture scales
// Result = Texture0 * Scale.x + Texture1 * Scale.y
// NOTE: Can be used as copy if setting one texture with scale.x = 1
//[EDITOR_COMMENTS_END]
Texture2D param_texture0;
Texture2D param_texture1;
float2 param_scale;

float4 ps_main(PS_IN In) : SV_Target
{
	float4 t0 = param_texture0.SampleLevel(FilterLinear, In.Tex, 0);
	float4 t1 = param_texture1.SampleLevel(FilterLinear, In.Tex, 0);
	return (t0 * param_scale.x + t1 * param_scale.y);
}
