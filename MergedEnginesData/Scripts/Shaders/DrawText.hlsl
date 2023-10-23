Texture2D Texture : register(t0);
SamplerState Filter;

struct PS_IN
{
	float4 Pos : SV_Position;
	float4 Col : Color;
	float2 Tex : TexCoord;
};

PS_IN vs_main(float4 Pos : Vertex, float4 Tex : TexCoord, float4 Col : Color, uint vertexID : SV_VertexID)
{
	PS_IN Out;

	// vert id 0 = 0000, uv = (0, 0)
	// vert id 1 = 0001, uv = (1, 0)
	// vert id 2 = 0010, uv = (0, 1)
	// vert id 3 = 0011, uv = (1, 1)
	float2 uv = float2(vertexID & 1, (vertexID >> 1) & 1);

	// set the position for the vertex based on which vertex it is (uv)
	Out.Pos = float4(Pos.x + (Pos.z * uv.x), Pos.y - (Pos.w * uv.y), 0, 1);
	Out.Col = Col;

	// set the texture coordinate based on which vertex it is (uv)
	Out.Tex = float2(Tex.x + (Tex.z * uv.x), Tex.y + (Tex.w * uv.y));
	return Out;
}

float4 ps_main(PS_IN In) : SV_Target
{
	return float4(In.Col.xyz, In.Col.w * Texture.Sample(Filter, In.Tex).a);
}
