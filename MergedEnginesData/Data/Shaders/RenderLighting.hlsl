#include "Shared.h"

// samplers
SamplerState FilterPoint;
SamplerState FilterLinear;
SamplerState FilterShadows;
SamplerState FilterShadowsColor;

#define PCSS					0	// if 0 use pcf filtering
#define	NUM_SAMPLES				32
#define	NUM_BLOCKER_SAMPLES		(NUM_SAMPLES/2)

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float3 vCameraPos;
	float4x4 InvViewProj;
	float2 vShadowMapSize;
	float fGIPower;
}
cbuffer LightingConstants : register(b1)
{
	int NumSpotLights, NumPointLights;
}

// G-Buffer
Texture2D TextureGBuffer0 : register(t2);
Texture2D TextureGBuffer1 : register(t3);
Texture2D TextureGBuffer2 : register(t4);
Texture2D TextureGBuffer3 : register(t5);
Texture2D TextureGBuffer4 : register(t6);
// D-Buffer
Texture2D TextureDBuffer0 : register(t7);
Texture2D TextureDBuffer1 : register(t8);
Texture2D TextureDBuffer2 : register(t9);
// VXGI
Texture2D<float4> TextureVXGIBuffer : register(t10);

StructuredBuffer<tSpotLight> arrSpotLights : register(t0, space1);
StructuredBuffer<tPointLight> arrPointLights : register(t0, space2);

// shadow map for all spot lights
Texture2D TextureSpotShadowMap[32] : register(t0, space3);
Texture2D TextureSpotShadowMapColor[32] : register(t0, space4);

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

struct PS_OUT
{
	float4 Diffuse : SV_Target0;
	float4 Specular : SV_Target1;
};

PS_IN vs_main(uint vertexID : SV_VertexID)
{
	PS_IN Out;
	/*
		orenk: fullscreen triangle 
		note: VP = viewport
	    B(-1,3)
	        |\ 
	        |  \
	        |----\
	        | VP | \ 
	        |____|___\
	    A(-1,-1)    C(3,-1) 
	*/
	Out.Pos = float4((float)(vertexID >> 1) * 4.0f - 1.0f, (float)(vertexID % 2) * 4.0f - 1.0f, 0, 1);
	Out.Tex = float2((float)(vertexID >> 1) * 2.0f, 1.0f - (float)(vertexID % 2) * 2.0f);;
	return Out;
}

PS_OUT ps_main(PS_IN In)
{
	// sample G-Buffer
	float fPixelDepth = TextureGBuffer0.SampleLevel(FilterPoint, In.Tex, 0).x;
	float3 vWorldPos = GetWorldPosition(fPixelDepth, In.Tex, InvViewProj);
	float4 normalWS_AO = TextureGBuffer1.Sample(FilterLinear, In.Tex);
	float3 normalWS = normalize(normalWS_AO.xyz);
	float ao = normalWS_AO.w;
	float4 albedo = TextureGBuffer2.Sample(FilterLinear, In.Tex);
	float4 roughness_metallicness = TextureGBuffer3.Sample(FilterLinear, In.Tex);
	float4 subsurfaceColor = TextureGBuffer4.Sample(FilterLinear, In.Tex);
	float roughness = roughness_metallicness.x;
	float metallic = roughness_metallicness.y;
	float iTwoSidedLighting = albedo.a;

	// sample D-Buffer
	float3 decal_normalWS = normalize(TextureDBuffer0.Sample(FilterLinear, In.Tex).xyz*2-1);
	float4 decal_albedo = TextureDBuffer1.Sample(FilterLinear, In.Tex);
	float3 decal_roughness_metallicness = TextureDBuffer2.Sample(FilterLinear, In.Tex).xyz;
	float decal_roughness = decal_roughness_metallicness.x;
	float decal_metallic = decal_roughness_metallicness.y;
	float decal_ao = decal_roughness_metallicness.z;

	// composite gbuffer and dbuffer
	albedo.xyz = lerp(albedo.xyz, decal_albedo.xyz, decal_albedo.a);
	roughness = lerp(roughness, decal_roughness, decal_albedo.a);
	metallic = lerp(metallic, decal_metallic, decal_albedo.a);
	ao = lerp(ao, decal_ao, decal_albedo.a);
	normalWS = normalize(lerp(normalWS, decal_normalWS, decal_albedo.a));

	// VXGI
	float4 vxgi = TextureVXGIBuffer.Sample(FilterLinear, In.Tex);
	ao *= (1 - vxgi.w);
	float3 indirectLighting = vxgi.xyz * fGIPower;

	// Lerp with metallic value to find the good diffuse and specular.
	float3 realAlbedo = albedo.xyz - albedo.xyz * metallic;

	// 0.03 default specular value for dielectric.
	float3 realSpecularColor = lerp(0.03f, albedo.xyz, metallic);

	// to eye
	float3 vToEyeNorm = normalize(vCameraPos.xyz - vWorldPos);

	float3 finalDiffuse = 0;
	float3 finalSpecular = 0;

	// spot lights
	int i;
	[loop]
	for (i = 0; i < NumSpotLights; ++i)
	{
		const tSpotLight light = arrSpotLights[i];

		// to light
		float3 vToLight = (light.vPosition - vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse, specular, subsurface;
		ComputeLight(realAlbedo, realSpecularColor, subsurfaceColor, normalWS, roughness, light.vPosition.xyz, light.vDiffuseColor.xyz, light.vSpecularColor.xyz, vToLightNorm, vToEyeNorm, diffuse, specular, subsurface, iTwoSidedLighting > 0);

		// cone att
		float cosIn = light.vData.x;
		float cosOut = light.vData.y;
		float fLightNear = light.vData.z;
		float fLightFar = light.vData.w;
		float cosAng = dot(light.vDirection, -vToLightNorm);
		float conAtt = saturate((cosAng - cosOut) / (cosIn - cosOut));
		conAtt *= conAtt;
		// light att
		float att = pow(saturate(1 - length(vToLight) / fLightFar), 2);
		att *= conAtt;

		// shadow map
		float4 vPosLight = mul(float4(vWorldPos.xyz, 1), light.ViewProj);

		// shadow map coord
		float2 uv = 0.5 * vPosLight.xy / vPosLight.w + float2(0.5, 0.5);
		uv.y = 1.0f - uv.y;

		// get current depth value
		float depth = vPosLight.z / vPosLight.w;

		// Compute gradient using ddx/ddy before any branching
		float2 dz_duv = 0;//DepthGradient(uv, depth);

#if (PCSS == 1)
		float zEye = -ZClipToZEye(vPosLight.z / vPosLight.w, fLightNear, fLightFar);
		float3 shadow = PCSS_Shadow(TextureSpotShadowMap[i], FilterShadows, TextureSpotShadowMapColor[i], FilterShadowsColor, uv, depth, zEye, light.fRadiusUV, fLightNear, fLightFar, In.Pos.xy, dz_duv, SHADOWMAP_BIAS, NUM_SAMPLES, NUM_BLOCKER_SAMPLES);
#else
		float3 shadow = GetSpotLightShadowMapSoft(TextureSpotShadowMap[i], FilterShadows, TextureSpotShadowMapColor[i], FilterShadowsColor, uv, depth, In.Pos.xy, 0.005f, dz_duv, SHADOWMAP_BIAS, NUM_SAMPLES);
#endif

		// accumulate
		finalDiffuse += shadow * att * diffuse + att * subsurface;
		finalSpecular += shadow * att * specular;
	}

	// point lights
	[loop]
	for (i = 0; i < NumPointLights; ++i)
	{
		const tPointLight light = arrPointLights[i];

		// to light
		float3 vToLight = (light.vPosition - vWorldPos);
		float3 vToLightNorm = normalize(vToLight);

		float3 diffuse, specular, subsurface;
		ComputeLight(realAlbedo, realSpecularColor, subsurfaceColor, normalWS, roughness, light.vPosition.xyz, light.vDiffuseColor.xyz, light.vSpecularColor.xyz, vToLightNorm, vToEyeNorm, diffuse, specular, subsurface, iTwoSidedLighting > 0);

		// att
		float fLightRange = light.vData.w + 0.0000001f;
		float att = 1.0f - saturate(length(vToLight) / fLightRange);

		// accumulate
		finalDiffuse += att * (diffuse + subsurface);
		finalSpecular += att * specular;
	}

	PS_OUT Output;
	// lighting
	Output.Diffuse = float4(ao * indirectLighting + finalDiffuse, 1);
	Output.Specular = float4(ao * indirectLighting + finalSpecular, 1);
//	return float4(ao * (finalDiffuse + finalSpecular), 1);
//	return float4(ao * indirectLighting + finalDiffuse + finalSpecular, 1);
	return Output;
}
