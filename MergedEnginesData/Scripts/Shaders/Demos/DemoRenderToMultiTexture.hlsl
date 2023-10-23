Texture2D Texture[4];
SamplerState Filter;

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
};

struct PS_OUT
{
	float4 RT[4] : SV_Target0;
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
	PS_OUT Out;
	for (int i=0; i<4; ++i)
		Out.RT[i] = Texture[i].Sample(Filter, In.Tex);
	return Out;
}
