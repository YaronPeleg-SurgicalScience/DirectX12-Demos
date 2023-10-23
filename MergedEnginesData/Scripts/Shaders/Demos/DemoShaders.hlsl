Texture2D Texture;
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float4 scale_bias;
	float fTime;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

PS_IN vs_main(float4 Pos : Vertex, float2 Tex : TexCoord, uint vertexID : SV_VertexID)
{
	PS_IN Out;
	Out.Pos = float4(Pos.xy * scale_bias.xy + scale_bias.zw, 0, 1);
	// create 2d rotation matrix
	float a = radians(fTime * 20);
	float2x2 matRot = float2x2(cos(a), -sin(a), sin(a), +cos(a));
	float2 uv = Tex;
	// rotate uv
	uv -= 0.5f;
	uv = mul(uv, matRot);
	uv += 0.5f;
	// set uv
	Out.Tex = uv;
	return Out;
}
float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = Texture.SampleLevel(Filter, In.Tex, 0);
//	clip(color.w - 0.5f);
	return float4(color.xyz, 1);
}
