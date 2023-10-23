// texture resources
Texture2D TextureRT[3];
SamplerState FilterPoint;
SamplerState FilterLinear;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 matInvViewProjection;
	float3 cameraPos;
	float3 lightPos;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
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

// z = interpolated z (z/w)
// vTexCoord = current pixel uv
float3 GetWorldPosition(in float z, in float2 vTexCoord)
{
	// get x/w and y/w from the viewport position
	float x = vTexCoord.x * 2 - 1;
	float y = (1 - vTexCoord.y) * 2 - 1;
	float4 vProjectedPos = float4(x, y, z, 1.0f);
	// transform by the inverse viewproj matrix
	float4 vPositionWS = mul(vProjectedPos, matInvViewProjection);
	// divide by w to get the position
	return vPositionWS.xyz / vPositionWS.w;
}

// ps
float4 ps_main(PS_IN In) : SV_Target
{
	// sample data from gbuffer
	float fPixelDepth = TextureRT[0].Sample(FilterPoint, In.Tex).x;
	float3 vWorldPos = GetWorldPosition(fPixelDepth, In.Tex);
	float4 normalWS_AO = TextureRT[1].Sample(FilterLinear, In.Tex) ;
	float3 normalWS = normalize(normalWS_AO.xyz * 2 - 1);
	float3 ao = normalWS_AO.www;
	float4 albedo = TextureRT[2].Sample(FilterLinear, In.Tex);

	// to light
	float3 vToLight = normalize(lightPos - vWorldPos);
	// to eye
	float3 vToEye = normalize(cameraPos.xyz - vWorldPos);
	// diffuse term
	float ndotl = saturate(dot(normalWS, vToLight)*0.8+0.2);
	float3 baseColor = albedo.xyz;
	float3 diffuse = ndotl * baseColor;
	// specular term
	float3 R = reflect(-vToLight, normalWS);
	float RdotV = dot(R, vToEye);
	float3 specular = pow(max(0.0f, RdotV), 8);
	// output result
	return float4(ao * (diffuse + specular), 1);
}
