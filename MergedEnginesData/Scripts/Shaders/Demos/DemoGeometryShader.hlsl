Texture2D Texture;
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
	float4x4 Proj;
	float4x4 invView;
}

struct GS_IN
{
	float3 Pos : Vertex;
	float2 Tex : TexCoord;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

GS_IN vs_main(uint vertexID : SV_VertexID)
{
	// just pass it to GS
	GS_IN Out = (GS_IN)0;
	return Out;
}

[maxvertexcount(4)]
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
	PS_IN output = (PS_IN)0;
	float radius = 1.0f;
	float3 offsets[4] =
	{
		float3(-radius, radius, 0),
		float3(radius, radius, 0),
		float3(-radius, -radius, 0),
		float3(radius, -radius, 0),
	};
	float2 texcoords[4] =
	{
		float2(1,0),
		float2(0,0),
		float2(1,1),
		float2(0,1),
	};
	// create billboard aligned to camera view
	for (uint i = 0; i < 4; i++)
	{
		float3 pos = mul(offsets[i], (float3x3)invView);
		output.Pos = mul(float4(pos, 1), WVP);
		output.Tex = texcoords[i];
		OutputStream.Append(output);
	}
	OutputStream.RestartStrip();
}

float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = Texture.SampleLevel(Filter, In.Tex, 0);
	return float4(color.xyz, 1);
}
