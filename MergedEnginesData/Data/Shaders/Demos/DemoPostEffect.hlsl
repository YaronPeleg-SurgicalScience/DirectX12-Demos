Texture2D Texture;
SamplerState Filter;

#define TWO_PI 6.28318530718

cbuffer ShaderConstants0 : register(b0)
{
	float fTime;
	int effect;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

PS_IN vs_main(uint vertexID : SV_VertexID)
{
	PS_IN Out;
	/*
		orenk: fullscreen triangle 
		note: VP = viewport
	    B(-1,3)
	        |\ 
	        |  \
	        |----\
	        | VP | \ 
	        |____|___\
	    A(-1,-1)    C(3,-1) 
	*/
	Out.Pos = float4((float)(vertexID >> 1) * 4.0f - 1.0f, (float)(vertexID % 2) * 4.0f - 1.0f, 0, 1);
	Out.Tex = float2((float)(vertexID >> 1) * 2.0f, 1.0f - (float)(vertexID % 2) * 2.0f);;
	return Out;
}

float4 EdgeDetectionSobel(const float2 uv)
{
	// top
	float3 TL = Texture.SampleLevel(Filter, uv, 0, int2(-1, 1)).xyz;
	float3 TM = Texture.SampleLevel(Filter, uv, 0, int2(0, 1)).xyz;
	float3 TR = Texture.SampleLevel(Filter, uv, 0, int2(1, 1)).xyz;
	// middle
	float3 ML = Texture.SampleLevel(Filter, uv, 0, int2(-1, 0)).xyz;
	float3 MR = Texture.SampleLevel(Filter, uv, 0, int2(1, 0)).xyz;
	// bottom
	float3 BL = Texture.SampleLevel(Filter, uv, 0, int2(-1, -1)).xyz;
	float3 BM = Texture.SampleLevel(Filter, uv, 0, int2(0, -1)).xyz;
	float3 BR = Texture.SampleLevel(Filter, uv, 0, int2(1, -1)).xyz;

	// sobelX,sobelY
	float3 sobelX = -TL + TR - 2.0 * ML + 2.0 * MR - BL + BR;
	float3 sobelY = TL + 2.0 * TM + TR - BL - 2.0 * BM - BR;
	float3 sobel = sobelX + sobelY;
	float3 lum = sobel;//dot(sobel, float3(0.299, 0.587, 0.114));
	return float4(lum, 1);
}

float4 CircularBlur(const float2 uv, const float Directions, const float Quality, const float Size)
{
	const float dstep = TWO_PI / Directions;	// direction step
	const float qstep = 1.0f / Quality;			// quality step
	const float2 Radius = Size;
	float4 res = Texture.SampleLevel(Filter, uv, 0);
	for (float d = 0.0; d < TWO_PI; d += dstep)
	{
		float2 csd;
		sincos(d, csd.x, csd.y);
		csd *= Radius;
		for (float i = qstep; i <= 1.0; i += qstep)
		{
			res += Texture.SampleLevel(Filter, uv + csd * i, 0);
		}
	}
	// Output to screen
	res /= Quality * Directions - (Directions-1);
	return res;
}

float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = Texture.SampleLevel(Filter, In.Tex, 0);
	if (effect == 1)
		color.xyz = dot(color.xyz, float3(0.299, 0.587, 0.114));
	else if (effect == 2)
		color = EdgeDetectionSobel(In.Tex);
	else if (effect == 3)
		color = CircularBlur(In.Tex, 24, 8, 0.025f);
	return float4(color.xyz, 1);
}
