// texture resources
Texture2D TextureAlbedo;
Texture2D TextureNormal;
Texture2D TextureAO;
Texture2D TextureShadowMap;
// samplers
SamplerState FilterAlbedo;
SamplerState FilterNormal;
SamplerState FilterShadowMap;

#define TWOPI			6.283185307179586476925286766559f
#define SHADOWMAP_BIAS 	0.000015f
//#define FILTER_SIZE		8

#if (FILTER_SIZE == 8)
static const float2 poisson8[8] =
{
	float2(-0.517305, -0.088537),
	float2(0.323062, -0.011652),
	float2(0.695463, 0.545146),
	float2(-0.246473, 0.642339),
	float2(0.857886, -0.307449),
	float2(-0.860246, 0.430376),
	float2(-0.282363, -0.669955),
	float2(0.432540, -0.647950)
};
#define POISSON_SAMPLES	poisson8
#elif (FILTER_SIZE == 16)
static const float2 poisson16[16] =
{
	float2(-0.376812, 0.649265),
	float2(-0.076855, -0.632508),
	float2(-0.833781, -0.268513),
	float2(0.398413, 0.027787),
	float2(0.360999, 0.766915),
	float2(0.584715, -0.809986),
	float2(-0.238882, 0.067867),
	float2(0.824410, 0.543863),
	float2(0.883033, -0.143517),
	float2(-0.581550, -0.809760),
	float2(-0.682282, 0.223546),
	float2(0.438031, -0.405749),
	float2(0.045340, 0.428813),
	float2(-0.311559, -0.328006),
	float2(-0.054146, 0.935302),
	float2(0.723339, 0.196795)
};
#define POISSON_SAMPLES	poisson16
#elif (FILTER_SIZE == 32)
static const float2 poisson32[32] =
{
	float2(-0.397889, 0.542226),
	float2(-0.414755, -0.394183),
	float2(0.131764, -0.713506),
	float2(0.551543, 0.554334),
	float2(0.317522, -0.088899),
	float2(0.927145, 0.283128),
	float2(0.141766, 0.672284),
	float2(-0.626308, 0.079957),
	float2(-0.379704, -0.823208),
	float2(-0.165635, 0.116704),
	float2(0.477730, -0.835368),
	float2(0.823137, -0.082292),
	float2(-0.254509, 0.914898),
	float2(-0.029949, -0.332681),
	float2(-0.735420, 0.649945),
	float2(0.269829, 0.337499),
	float2(0.589355, 0.188804),
	float2(0.495027, -0.463772),
	float2(0.430761, 0.880621),
	float2(-0.740073, -0.226115),
	float2(-0.843081, 0.319486),
	float2(-0.118380, 0.503956),
	float2(-0.103058, -0.967695),
	float2(-0.989892, 0.031239),
	float2(-0.650113, -0.657721),
	float2(-0.395081, -0.071884),
	float2(-0.409406, 0.272306),
	float2(0.112218, 0.112523),
	float2(0.258025, -0.346162),
	float2(0.105651, 0.945739),
	float2(-0.164829, -0.660185),
	float2(0.700367, -0.693439)
};
#define POISSON_SAMPLES	poisson32
#endif

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 matWVP;
	float4x4 matWorld;
	float4x4 matWorldIT;
	float4x4 matLightWVP;
	float2 vShadowMapSize;
	float3 vCameraPos;
	float3 vLightPos;
	float3 vLightDir;
	float fBumpiness;
	float fLightRange;
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
	float3 vWorldPos : WorldPos;
	float2 Tex : TexCoord;
	float3 Normal: Normal;
	float3 Tangent: Tangent;
	float3 Bitangent: Bitangent;
	float4 vPosLight: PosLight;
};

// vs
PS_IN vs_main(VS_IN In)
{
	PS_IN Out;
	Out.Pos = mul(float4(In.Pos.xyz, 1), matWVP);
	Out.vWorldPos = mul(float4(In.Pos.xyz, 1), matWorld).xyz;
	Out.Tex = In.Tex;
	Out.Normal = mul(In.Normal.xyz, (float3x3)matWorld);
	Out.Tangent = mul(In.Tangent.xyz, (float3x3)matWorld);
	Out.Bitangent = mul(In.Bitangent.xyz, (float3x3)matWorld);
	Out.vPosLight = mul(float4(In.Pos.xyz, 1), matLightWVP);
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

float GetShadowMap(in float4 vPosLight, in float2 pos)
{
	// shadow map
	float2 ShadowTexC = 0.5 * vPosLight.xy / vPosLight.w + float2(0.5, 0.5);
	ShadowTexC.y = 1.0f - ShadowTexC.y;
	float2 texelpos = vShadowMapSize * ShadowTexC;
	float2 lerps = frac(texelpos);

	float4 shadowMapDepth;
	shadowMapDepth.x = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC, int2(0, 0)).x;
	shadowMapDepth.y = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC, int2(1, 0)).x;
	shadowMapDepth.z = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC, int2(0, 1)).x;
	shadowMapDepth.w = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC, int2(1, 1)).x;
	float currDepth = vPosLight.z / vPosLight.w;
	float4 shadowComp = currDepth.xxxx < shadowMapDepth + SHADOWMAP_BIAS;
	// lerp between the shadow values to calculate our light amount
	float shadow = lerp(lerp(shadowComp[0], shadowComp[1], lerps.x),
		lerp(shadowComp[2], shadowComp[3], lerps.x),
		lerps.y);

	return shadow;
}

float rand(float seed) { return frac(sin(seed * (91.3458)) * 47453.5453); }
float rand(float2 seed) { return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453); }
float rand(float3 seed) { return frac(sin(dot(seed.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453); }

float2x2 jitter(float a, float x, float y)
{
	float s = sin(a);
	float c = cos(a);
	float2x2 rot = float2x2(c, -s, s, c);
	float2x2 scale = float2x2(x, 0, 0, y);
	return scale * rot;
}

float GetShadowMapPoisson(in float4 vPosLight, in float3 pos)
{
	// shadow map coords
	vPosLight /= vPosLight.w;
	float2 ShadowTexC = 0.5 * vPosLight.xy + float2(0.5, 0.5);
	ShadowTexC.y = 1.0f - ShadowTexC.y;

#if (FILTER_SIZE == 0)
	// no filtering, hard shadows
	float shadowMapDepth = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC).x;
	return vPosLight.z < shadowMapDepth + SHADOWMAP_BIAS;

#else
	// apply filter
	float radius = 0.005f;
	float2x2 matJitter = jitter(rand(pos) * TWOPI, radius, radius);
	float sum = 0.0f;
	for (int i = 0; i < FILTER_SIZE; ++i)
	{
		float2 offset = mul(POISSON_SAMPLES[i], matJitter);
		float shadowMapDepth = TextureShadowMap.Sample(FilterShadowMap, ShadowTexC + offset).x;
		sum += vPosLight.z < shadowMapDepth + SHADOWMAP_BIAS;
	}
	return sum / float(FILTER_SIZE);
#endif
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
	// to light
	float3 vToLight = (vLightPos - In.vWorldPos);
	float3 vToLightNorm = normalize(vToLight);
	// to eye
	float3 vToEye = normalize(vCameraPos.xyz - In.vWorldPos);
	// diffuse term
	float ndotl = saturate(dot(normalWS, vToLightNorm) * 0.8f + 0.2f);
	float3 baseColor = TextureAlbedo.Sample(FilterAlbedo, In.Tex).xyz;
	float3 diffuse = ndotl * baseColor;

	// cone att
	float cosIn = 0.9;
	float cosOut = 0.5;
	float cosAng = dot(vLightDir, -vToLightNorm);
	float conAtt = saturate((cosAng - cosOut) / (cosIn - cosOut));
	conAtt *= conAtt;
	// light att
	float att = pow(saturate(1 - length(vToLight) / fLightRange), 2);
	att *= conAtt;
	
	// shadow map
	float shadow;
	if (ndotl <= 0)
		shadow = 0;
	else
		shadow = GetShadowMapPoisson(In.vPosLight, In.vWorldPos.xyz);

	// specular term
	float3 R = reflect(-vToLightNorm, normalWS);
	float RdotV = dot(R, vToEye);
	float3 specular = pow(max(0.0f, RdotV), 8);
	// get ao
	float3 ao = TextureAO.Sample(FilterAlbedo, In.Tex).xxx;
	// output result
	return float4(shadow * att * ao * (diffuse + specular), 1);
}
