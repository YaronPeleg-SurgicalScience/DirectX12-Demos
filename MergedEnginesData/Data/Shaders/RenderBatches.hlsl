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
	float4x4 ViewProj;
	float4x4 World;
	float4x4 WorldIT;
	float3 cameraPos;
	float3 lightPos;
};

cbuffer MaterialConstants : register(b1)
{
	float4 vDiffuseColor;
	float4 vSpecularColor;
	float fBumpiness;
};

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
	float3 vWorldPos : WorldPos;
	float2 Tex : TexCoord;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
};

// vs
PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), World).xyz;
	Out.Pos = mul(float4(Out.vWorldPos.xyz, 1), ViewProj);
	Out.Tex = In.Tex;
	Out.Normal = mul(In.Normal.xyz, (float3x3)WorldIT);
	Out.Tangent = mul(In.Tangent.xyz, (float3x3)WorldIT);
	Out.Bitangent = mul(In.Bitangent.xyz, (float3x3)WorldIT);
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
float4 ps_main(PS_IN In) : SV_Target
{
	// get normal in tangent space
	float3 normalTS = SampleNormalMap(TextureNormal, FilterNormal, In.Tex).xyz;
	// control bumpiness
	const float3 vSmoothNormal = { 0.5f, 0.5f, 1.0f };
	normalTS = lerp(vSmoothNormal, normalTS.xyz, max(fBumpiness, 0.001f));
	normalTS = normalize(normalTS * 2.0 - 1.0);
	// transform into world space
	float3 normalWS = normalize(normalize(In.Tangent) * normalTS.x + normalize(In.Bitangent) * normalTS.y + normalize(In.Normal) * normalTS.z);
//	normalWS = normalize(In.Normal);
	// to light
	float3 vToLight = normalize(lightPos - In.vWorldPos);
	// to eye
	float3 vToEye = normalize(cameraPos.xyz - In.vWorldPos);
	// diffuse term
	float ndotl = saturate(dot(normalWS, vToLight)*0.8+0.2);
	float3 baseColor = TextureAlbedo.Sample(FilterAlbedo, In.Tex).xyz;
	float3 diffuse = ndotl * baseColor * vDiffuseColor.xyz;
	// specular term
//	float3 H = normalize(vToLight + vToEye);
//	float3 specular = max(0.0f, pow(dot(normalWS, H), 32)) * vSpecularColor.xyz;
	float3 R = reflect(-vToLight, normalWS);
	float RdotV = dot(R, vToEye);
	float3 specular = pow(max(0.0f, RdotV), 32) * vSpecularColor.xyz;
	// get ao
	float3 ao = TextureAO.Sample(FilterAlbedo, In.Tex).xxx;
	// output result
	return float4(ao * (diffuse + specular), 1);
}
