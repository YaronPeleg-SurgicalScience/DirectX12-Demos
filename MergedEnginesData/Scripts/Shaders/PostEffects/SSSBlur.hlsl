//////////////////////////////////////////////////////////////////////////
// Screen Space Subsurface Scattering Filter (ORENK - 2023)
//////////////////////////////////////////////////////////////////////////

#include "PostShared.h"

//[EDITOR_COMMENTS_BEGIN]
// Shader Parameters Count: 5
// * param_textureScene - scene texture to apply effect on 
// * param_textureDepth - scene depth texture
// * param_direction - direction of the blur
// * param_width - subsurface scattering level or the width of the filter in world space units
// * param_maxDiffScale - depth difference scale factor to prevent bleeding issues
// Result = SSS blurred texture
//[EDITOR_COMMENTS_END]
Texture2D param_textureScene;
Texture2D param_textureDepth;
float4 param_textureScene_TexelSize;
float4 param_textureDepth_TexelSize;
float4 param_direction;
float param_width;
float param_maxDiffScale;

#define SSSS_QUALITY 2

#if SSSS_QUALITY == 2
#define SSSS_N_SAMPLES 25
static const float4 kernel[] = {
	float4(0.530605, 0.613514, 0.739601, 0),
	float4(0.000973794, 1.11862e-005, 9.43437e-007, -3),
	float4(0.00333804, 7.85443e-005, 1.2945e-005, -2.52083),
	float4(0.00500364, 0.00020094, 5.28848e-005, -2.08333),
	float4(0.00700976, 0.00049366, 0.000151938, -1.6875),
	float4(0.0094389, 0.00139119, 0.000416598, -1.33333),
	float4(0.0128496, 0.00356329, 0.00132016, -1.02083),
	float4(0.017924, 0.00711691, 0.00347194, -0.75),
	float4(0.0263642, 0.0119715, 0.00684598, -0.520833),
	float4(0.0410172, 0.0199899, 0.0118481, -0.333333),
	float4(0.0493588, 0.0367726, 0.0219485, -0.1875),
	float4(0.0402784, 0.0657244, 0.04631, -0.0833333),
	float4(0.0211412, 0.0459286, 0.0378196, -0.0208333),
	float4(0.0211412, 0.0459286, 0.0378196, 0.0208333),
	float4(0.0402784, 0.0657244, 0.04631, 0.0833333),
	float4(0.0493588, 0.0367726, 0.0219485, 0.1875),
	float4(0.0410172, 0.0199899, 0.0118481, 0.333333),
	float4(0.0263642, 0.0119715, 0.00684598, 0.520833),
	float4(0.017924, 0.00711691, 0.00347194, 0.75),
	float4(0.0128496, 0.00356329, 0.00132016, 1.02083),
	float4(0.0094389, 0.00139119, 0.000416598, 1.33333),
	float4(0.00700976, 0.00049366, 0.000151938, 1.6875),
	float4(0.00500364, 0.00020094, 5.28848e-005, 2.08333),
	float4(0.00333804, 7.85443e-005, 1.2945e-005, 2.52083),
	float4(0.000973794, 1.11862e-005, 9.43437e-007, 3),
};
#elif SSSS_QUALITY == 1
#define SSSS_N_SAMPLES 17
static const float4 kernel[] = {
	float4(0.536343, 0.624624, 0.748867, 0),
	float4(0.00317394, 0.000134823, 3.77269e-005, -2),
	float4(0.0100386, 0.000914679, 0.000275702, -1.53125),
	float4(0.0144609, 0.00317269, 0.00106399, -1.125),
	float4(0.0216301, 0.00794618, 0.00376991, -0.78125),
	float4(0.0347317, 0.0151085, 0.00871983, -0.5),
	float4(0.0571056, 0.0287432, 0.0172844, -0.28125),
	float4(0.0582416, 0.0659959, 0.0411329, -0.125),
	float4(0.0324462, 0.0656718, 0.0532821, -0.03125),
	float4(0.0324462, 0.0656718, 0.0532821, 0.03125),
	float4(0.0582416, 0.0659959, 0.0411329, 0.125),
	float4(0.0571056, 0.0287432, 0.0172844, 0.28125),
	float4(0.0347317, 0.0151085, 0.00871983, 0.5),
	float4(0.0216301, 0.00794618, 0.00376991, 0.78125),
	float4(0.0144609, 0.00317269, 0.00106399, 1.125),
	float4(0.0100386, 0.000914679, 0.000275702, 1.53125),
	float4(0.00317394, 0.000134823, 3.77269e-005, 2),
};
#elif SSSS_QUALITY == 0
#define SSSS_N_SAMPLES 11
static const float4 kernel[] = {
	float4(0.560479, 0.669086, 0.784728, 0),
	float4(0.00471691, 0.000184771, 5.07566e-005, -2),
	float4(0.0192831, 0.00282018, 0.00084214, -1.28),
	float4(0.03639, 0.0130999, 0.00643685, -0.72),
	float4(0.0821904, 0.0358608, 0.0209261, -0.32),
	float4(0.0771802, 0.113491, 0.0793803, -0.08),
	float4(0.0771802, 0.113491, 0.0793803, 0.08),
	float4(0.0821904, 0.0358608, 0.0209261, 0.32),
	float4(0.03639, 0.0130999, 0.00643685, 0.72),
	float4(0.0192831, 0.00282018, 0.00084214, 1.28),
	float4(0.00471691, 0.000184771, 5.07565e-005, 2),
};
#else
#error Quality must be one of {0,1,2}
#endif

float GetSubsurfaceMask(float2 texcoord)
{
	// use subsurface color alpha
	float4 subsurfaceColor = TextureGBuffer4.Sample(FilterLinear, texcoord);
	return (subsurfaceColor.a > 0.0f) ? 1 : 0.0f;
}

#ifndef SSSS_FOLLOW_SURFACE
#define SSSS_FOLLOW_SURFACE	1
#endif

// IMPORTANT: color texture must be in linear space!
float4 SSSSBlurPS(float2 texcoord, Texture2D colorTex, Texture2D depthTex, float sssWidth, float2 dir, bool initStencil) 
{
	// get color
	float4 colorM = colorTex.SampleLevel(FilterPoint, texcoord, 0);

	// skip pixels if no sss needed
	if (initStencil)
		if (GetSubsurfaceMask(texcoord) == 0.0) return colorM;

	// get linear depth
	float depthM = GetLinearDepthNormalized(depthTex.SampleLevel(FilterPoint, texcoord, 0).r, vProjectionParamsAB);

	// calc the sssWidth scale (1.0 for a unit plane sitting on the projection window)
	float distanceToProjectionWindow = 1.0 / tan(0.5 * radians(fCameraFov));
	float scale = distanceToProjectionWindow / depthM;

	// calc the final step to fetch the surrounding pixels
	float2 finalStep = sssWidth * scale * dir;
	finalStep *= GetSubsurfaceMask(texcoord); // apply mask
	finalStep *= 1.0 / 3.0; // divide by 3 as the kernels range from -3 to 3.

	// accumulate the center sample
	float4 colorBlurred = colorM;
	colorBlurred.rgb *= kernel[0].rgb;

	// cccumulate the other samples
	[unroll]
	for (int i = 1; i < SSSS_N_SAMPLES; i++) 
	{
		// get color and depth for current sample
		float2 offset = texcoord + kernel[i].a * finalStep;
		float4 color = colorTex.SampleLevel(FilterLinear, offset, 0);

#if SSSS_FOLLOW_SURFACE == 1
		// check if the difference in depth is huge, we lerp color back to base color 'colorM'
		float depth = GetLinearDepthNormalized(depthTex.SampleLevel(FilterLinear, offset, 0).r, vProjectionParamsAB);
		float s = saturate(param_maxDiffScale * distanceToProjectionWindow * sssWidth * abs(depthM - depth));
		color.rgb = lerp(color.rgb, colorM.rgb, s);
#endif

		// cccumulate samples
		colorBlurred.rgb += kernel[i].rgb * color.rgb;
	}

	// return sss blurred pixel
	return colorBlurred;
}

float4 ps_main(PS_IN In) : SV_Target
{
	return SSSSBlurPS(In.Tex, param_textureScene, param_textureDepth, param_width, param_direction.xy, true);
}
