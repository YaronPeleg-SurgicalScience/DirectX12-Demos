#include "PostShared.h"

// NOTE: based on FXAA tutorial from http://blog.simonrodriguez.fr/articles/30-07-2016_implementing_fxaa.html

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 1
// * Param_Texture - Texture to apply the effect on
// Result = Soft and smooth anti-aliased texture
//[EDITOR_COMMENTS_END]
Texture2D param_texture;
float4 param_texture_TexelSize;

/* pixel index in 3*3 kernel
	+---+---+---+
	| 0 | 1 | 2 |
	+---+---+---+
	| 3 | 4 | 5 |
	+---+---+---+
	| 6 | 7 | 8 |
	+---+---+---+
*/
#define TOP_LEFT     0
#define TOP          1
#define TOP_RIGHT    2
#define LEFT         3
#define CENTER       4
#define RIGHT        5
#define BOTTOM_LEFT  6
#define BOTTOM       7
#define BOTTOM_RIGHT 8
static const float2 KERNEL_STEP_MAT[9] =
{
	float2(-1.0, 1.0), float2(0.0, 1.0), float2(1.0, 1.0),
	float2(-1.0, 0.0), float2(0.0, 0.0), float2(1.0, 0.0),
	float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0)
};

/* in order to accelerate exploring along tangent bidirectional, step by an increasing amount of pixels QUALITY(i)
   the max step count is 12
	+-----------------+---+---+---+---+---+---+---+---+---+---+---+---+
	|step index       | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |10 |11 |
	+-----------------+---+---+---+---+---+---+---+---+---+---+---+---+
	|step pixels count|1.0|1.0|1.0|1.0|1.0|1.5|2.0|2.0|2.0|2.0|4.0|8.0|
	+-----------------+---+---+---+---+---+---+---+---+---+---+---+---+
*/
#define STEP_COUNT_MAX   12
float QUALITY(int i) 
{
	if (i < 5) return 1.0;
	if (i == 5) return 1.5;
	if (i < 10) return 2.0;
	if (i == 10) return 4.0;
	if (i == 11) return 8.0;
	return 1.0;
}

// L = 0.299 * R + 0.587 * G + 0.114 * B
float RGB2LUMA(in float3 color) 
{
	return dot(float3(0.299, 0.578, 0.114), color);
}

#define EDGE_THRESHOLD_MIN  0.0312
#define EDGE_THRESHOLD_MAX  0.125
#define SUBPIXEL_QUALITY    0.75
#define GRADIENT_SCALE      0.25

float4 FXAA311(in float2 uv, in float2 uv_step)
{
	int i;
	// get luma of kernel
	float luma_mat[9];
	[loop]
	for (i = 0; i < 9; i++) 
		luma_mat[i] = RGB2LUMA(param_texture.Sample(FilterLinear, uv + uv_step * KERNEL_STEP_MAT[i]).xyz);

	// detecting where to apply FXAA, return the pixel color if not
	float luma_min = min(luma_mat[CENTER], min(min(luma_mat[TOP], luma_mat[BOTTOM]), min(luma_mat[LEFT], luma_mat[RIGHT])));
	float luma_max = max(luma_mat[CENTER], max(max(luma_mat[TOP], luma_mat[BOTTOM]), max(luma_mat[LEFT], luma_mat[RIGHT])));
	float luma_range = luma_max - luma_min;
	if (luma_range < max(EDGE_THRESHOLD_MIN, luma_max * EDGE_THRESHOLD_MAX))
		return param_texture.Sample(FilterLinear, uv);

	// choosing edge tangent
	// horizontal: |(upleft-left)-(left-downleft)|+2*|(up-center)-(center-down)|+|(upright-right)-(right-downright)|
	// vertical: |(upright-up)-(up-upleft)|+2*|(right-center)-(center-left)|+|(downright-down)-(down-downleft)|
	float luma_horizontal =
		abs(luma_mat[TOP_LEFT] + luma_mat[BOTTOM_LEFT] - 2.0 * luma_mat[LEFT])
		+ 2.0 * abs(luma_mat[TOP] + luma_mat[BOTTOM] - 2.0 * luma_mat[CENTER])
		+ abs(luma_mat[TOP_RIGHT] + luma_mat[BOTTOM_RIGHT] - 2.0 * luma_mat[RIGHT]);
	float luma_vertical =
		abs(luma_mat[TOP_LEFT] + luma_mat[TOP_RIGHT] - 2.0 * luma_mat[TOP])
		+ 2.0 * abs(luma_mat[LEFT] + luma_mat[RIGHT] - 2.0 * luma_mat[CENTER])
		+ abs(luma_mat[BOTTOM_LEFT] + luma_mat[BOTTOM_RIGHT] - 2.0 * luma_mat[BOTTOM]);
	bool is_horizontal = luma_horizontal > luma_vertical;

	// choosing edge normal 
	float gradient_down_left = (is_horizontal ? luma_mat[BOTTOM] : luma_mat[LEFT]) - luma_mat[CENTER];
	float gradient_up_right = (is_horizontal ? luma_mat[TOP] : luma_mat[RIGHT]) - luma_mat[CENTER];
	bool is_down_left = abs(gradient_down_left) > abs(gradient_up_right);

	// get the tangent uv step vector and the normal uv step vector
	float2 step_tangent = (is_horizontal ? float2(1.0, 0.0) : float2(0.0, 1.0)) * uv_step;
	float2 step_normal = (is_down_left ? -1.0 : 1.0) * (is_horizontal ? float2(0.0, 1.0) : float2(1.0, 0.0)) * uv_step;

	// get the change rate of gradient in normal per pixel
	float gradient = is_down_left ? gradient_down_left : gradient_up_right;

	// start at middle point of tangent edge
	float2 uv_start = uv + 0.5 * step_normal;
	float luma_average_start = luma_mat[CENTER] + 0.5 * gradient;

	// explore along tangent bidirectional until reach the edge both
	float2 uv_pos = uv_start + step_tangent;
	float2 uv_neg = uv_start - step_tangent;

	float delta_luma_pos = RGB2LUMA(param_texture.Sample(FilterLinear, uv_pos).rgb) - luma_average_start;
	float delta_luma_neg = RGB2LUMA(param_texture.Sample(FilterLinear, uv_neg).rgb) - luma_average_start;

	bool reached_pos = abs(delta_luma_pos) > GRADIENT_SCALE * abs(gradient);
	bool reached_neg = abs(delta_luma_neg) > GRADIENT_SCALE * abs(gradient);
	bool reached_both = reached_pos && reached_neg;

	if (!reached_pos) uv_pos += step_tangent;
	if (!reached_neg) uv_neg -= step_tangent;

	if (!reached_both)
	{
		[loop]
		for (i = 2; i < STEP_COUNT_MAX; i++)
		{			
			if (!reached_pos) delta_luma_pos = RGB2LUMA(param_texture.Sample(FilterLinear, uv_pos).rgb) - luma_average_start;
			if (!reached_neg) delta_luma_neg = RGB2LUMA(param_texture.Sample(FilterLinear, uv_neg).rgb) - luma_average_start;

			bool reached_pos = abs(delta_luma_pos) > GRADIENT_SCALE * abs(gradient);
			bool reached_neg = abs(delta_luma_neg) > GRADIENT_SCALE * abs(gradient);
			bool reached_both = reached_pos && reached_neg;

			if (!reached_pos) uv_pos += (QUALITY(i) * step_tangent);
			if (!reached_neg) uv_neg -= (QUALITY(i) * step_tangent);

			if (reached_both) 
				break;
		}
	}

	// estimating offset
	float length_pos = max(abs(uv_pos - uv_start).x, abs(uv_pos - uv_start).y);
	float length_neg = max(abs(uv_neg - uv_start).x, abs(uv_neg - uv_start).y);
	bool is_pos_near = length_pos < length_neg;

	float pixel_offset = -1.0 * (is_pos_near ? length_pos : length_neg) / (length_pos + length_neg) + 0.5;

	// no offset if the bidirectional point is too far
	if (((is_pos_near ? delta_luma_pos : delta_luma_neg) < 0.0) == (luma_mat[CENTER] < luma_average_start)) pixel_offset = 0.0;

	// subpixel antialiasing
	float luma_average_center = 0.0;
	float average_weight_mat[9] =
	{
		1.0, 2.0, 1.0,
		2.0, 0.0, 2.0,
		1.0, 2.0, 1.0
	};
	[loop]
	for (i = 0; i < 9; i++) 
		luma_average_center += average_weight_mat[i] * luma_mat[i];
	luma_average_center /= 12.0;

	float subpixel_luma_range = clamp(abs(luma_average_center - luma_mat[CENTER]) / luma_range, 0.0, 1.0);
	float subpixel_offset = (-2.0 * subpixel_luma_range + 3.0) * subpixel_luma_range * subpixel_luma_range;
	subpixel_offset = subpixel_offset * subpixel_offset * SUBPIXEL_QUALITY;

	// use the max offset between subpixel offset with before
	pixel_offset = max(pixel_offset, subpixel_offset);

	return param_texture.Sample(FilterLinear, uv + pixel_offset * step_normal);
}

float4 ps_main(PS_IN In) : SV_Target
{
	float2 screen_uv = In.Pos.xy * param_texture_TexelSize.xy;
	return FXAA311(screen_uv, param_texture_TexelSize.xy);
}
