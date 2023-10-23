Texture2D Texture;
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

PS_IN vs_main(float4 Pos : Vertex, float2 Tex : TexCoord)
{
	PS_IN Out;
	Out.Pos = mul(float4(Pos.xyz, 1), WVP);
	Out.Tex = Tex;
	return Out;
}
float4 ps_main(PS_IN In, bool isFrontFace : SV_IsFrontFace) : SV_Target
{
	float4 color = Texture.Sample(Filter, In.Tex);
	color = lerp(float4(In.Tex, 0, 1), color, (float)isFrontFace);
	return float4(color.xyz, 1);
}
