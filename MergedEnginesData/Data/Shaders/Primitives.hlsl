cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
	float4 Color;
}
Texture2D Texture;
SamplerState Filter;

#if (USE_COLORED == 1)
struct PS_IN
{
	float4 Pos : SV_Position;
};
#else
struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};
#endif

#if (USE_COLORED == 1)
// colored
PS_IN vs_main(float4 Pos : Vertex)
{
	PS_IN Out;
	Out.Pos = mul(Pos, WVP);
	return Out;
}
float4 ps_main(PS_IN In) : SV_Target
{
	return Color;
}
#else // textured
PS_IN vs_main(float4 Pos : Vertex, float2 Tex : TexCoord)
{
	PS_IN Out;
	Out.Pos = mul(Pos, WVP);
	Out.Tex = Tex;
	return Out;
}
float4 ps_main(PS_IN In) : SV_Target
{
	return Color * Texture.SampleLevel(Filter, In.Tex, 0);
}
#endif
