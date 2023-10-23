// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 matWVP;
}

// vs input
struct VS_IN
{
	float4 Pos : Vertex;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
	float2 Tex : TexCoord;
};

// ps input
struct PS_IN
{
	float4 Pos : SV_Position;
	float4 vHPos : HPosition;
};

// vs
PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	Out.Pos = mul(float4(In.Pos.xyz, 1), matWVP);
	Out.vHPos = Out.Pos;
	return Out;
}

// ps
float4 ps_main(PS_IN In) : SV_Target
{
	return In.vHPos.z / In.vHPos.w;
}
