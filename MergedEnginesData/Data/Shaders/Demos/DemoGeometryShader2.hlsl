Texture2D Texture;
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float2 screen_size;	// screen size
	float2 grid_size;	// virtual grid size
}

struct GS_IN
{
	float2 Pos : Vertex;
	float2 Tex : TexCoord;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float4 Color : Color;
};

uint2 IndexToXY(uint index, uint width)
{
	return uint2(index % width, index / width);
}

GS_IN vs_main(uint vertexID : SV_VertexID)
{
	// get xy position from vertex index (in screen space)
	float2 grid_pos = IndexToXY(vertexID, uint(grid_size.x));
	// convert to uv space [0..1]
	float2 uv = grid_pos / (grid_size - 1);
	// convert to clip space [-1..1]
	float2 pos_2d = uv * 2.0f - 1.0f;
	// just pass it to GS
	GS_IN Out = (GS_IN)0;
	Out.Pos = pos_2d;
	Out.Tex = float2(uv.x, 1 - uv.y);
	return Out;
}

[maxvertexcount(4)]
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
	PS_IN output = (PS_IN)0;
	float2 offsets[4] =
	{
		float2(-1, 1),
		float2(1, 1),
		float2(-1, -1),
		float2(1, -1),
	};
	// compute quad size
	float2 quadSize = (1.0f / grid_size) * 1.1;
	// set pixel position
	float2 pixelPos = input[0].Pos;
	// sample quad color from texture
	float4 color = Texture.SampleLevel(Filter, input[0].Tex, 0);
	// create screen space quad to match texture pixel at our uv
	for (uint i = 0; i < 4; i++)
	{
		float2 pos = pixelPos + offsets[i] * quadSize;
		output.Pos = float4(pos.xy, 0, 1);
		output.Color = color;
		OutputStream.Append(output);
	}
	OutputStream.RestartStrip();
}

float4 ps_main(PS_IN In) : SV_Target
{
	return float4(In.Color.xyz, 1);
}
