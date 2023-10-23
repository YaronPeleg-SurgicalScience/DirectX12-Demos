// material struct
struct Material
{
	int textureIndex;
	float4 diffuseColor;
};

SamplerState Filter;
// instances position
StructuredBuffer<float2> arrInstancePosition : register(t0, space1);
// material per instance
StructuredBuffer<Material> arrMaterials : register(t0, space2);
// bindless textures used by materials
Texture2D arrTextures[] : register(t0, space3);

cbuffer ShaderConstants0 : register(b0)
{
	float4 scale_bias;
	float3 vPanAndZoom;
	float fTime;
	int num_materials;
}

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
	nointerpolation int material : MateriaID;
};

PS_IN vs_main(float4 Pos : Vertex, float2 Tex : TexCoord, uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID)
{
	float2 instancePosition = arrInstancePosition[instanceID];
	PS_IN Out;
	Out.Pos = float4(Pos.xy * scale_bias.xy + scale_bias.zw, 0, 1);
	Out.Pos.xy += instancePosition;
	Out.Pos.xy *= vPanAndZoom.z;
	Out.Pos.xy += vPanAndZoom.xy;
	Out.Tex = Tex;
	Out.material = instanceID % num_materials;
	return Out;
}
float4 ps_main(PS_IN In) : SV_Target
{
	const Material matData = arrMaterials[NonUniformResourceIndex(In.material)];
	Texture2D albedoTexture = arrTextures[matData.textureIndex];
	return albedoTexture.SampleLevel(Filter, In.Tex, 0) * matData.diffuseColor;
}
