// texture resources
Texture2D TextureAlbedo;
Texture2D TextureNormal;
Texture2D TextureAO;
// samplers
SamplerState FilterAlbedo;
SamplerState FilterNormal;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
	float4x4 World;
	float4x4 WorldIT;
	float3 cameraPos;
	float3 lightPos;
	float fBumpiness;
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
	float3 vWorldPos : WorldPos;
	float2 Tex : TexCoord;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
};

// pos output
struct PS_OUT
{
	float4 RT[3] : SV_Target0;
};

// vs
PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	Out.Pos = mul(float4(In.Pos.xyz, 1), WVP);
	Out.vHPos = Out.Pos;
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), World).xyz;
	Out.Tex = In.Tex;
	Out.Normal = mul(In.Normal.xyz, (float3x3)World);
	Out.Tangent = mul(In.Tangent.xyz, (float3x3)World);
	Out.Bitangent = mul(In.Bitangent.xyz, (float3x3)World);
	return Out;
}

// helper function to sample normal map
#define USE_BG_NORMAL_MAP 1
//#define USE_BC5_NORMAL_MAP 1
float4 SampleNormalMap(in Texture2D texNormalMap, in SamplerState samNormalMap, in float2 vTexCoord)
{
	float4 vNormal;
#if (USE_BG_NORMAL_MAP == 1)
	vNormal.xy = texNormalMap.Sample(samNormalMap, vTexCoord.xy).ag;
	vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy * 2 - 1, vNormal.xy * 2 - 1)));
	vNormal.w = 1;
#elif (USE_BC5_NORMAL_MAP == 1)
	vNormal.xy = texNormalMap.Sample(samNormalMap, vTexCoord.xy).xy;
	vNormal.z = sqrt(saturate(1.0 - dot(vNormal.xy * 2 - 1, vNormal.xy * 2 - 1)));
	vNormal.w = 1;
#else
	vNormal = texNormalMap.Sample(samNormalMap, vTexCoord.xy);
#endif
	return vNormal;
}

// ps
PS_OUT ps_main(PS_IN In)
{
	// get normal in tangent space
	float3 normalTS = SampleNormalMap(TextureNormal, FilterNormal, In.Tex).xyz;
	// control bumpiness
	const float3 vSmoothNormal = { 0.5f, 0.5f, 1.0f };
	normalTS = lerp(vSmoothNormal, normalTS.xyz, max(fBumpiness, 0.001f));
	normalTS = normalize(normalTS * 2.0 - 1.0);
	// transform into world space
	float3 normalWS = normalize(normalize(In.Tangent) * normalTS.x + normalize(In.Bitangent) * normalTS.y + normalize(In.Normal) * normalTS.z);
	float4 albedo = TextureAlbedo.Sample(FilterAlbedo, In.Tex);
	float ao = TextureAO.Sample(FilterAlbedo, In.Tex).x;

	// output result
	PS_OUT Out;
	Out.RT[0] = In.vHPos.z / In.vHPos.w;
	Out.RT[1] = float4(normalWS.xyz * 0.5f + 0.5f, ao);
	Out.RT[2] = albedo;
	return Out;
}
