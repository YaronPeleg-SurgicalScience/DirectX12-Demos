Texture2D GrassBlade : register(t0);
Texture2D HeightMap : register(t1);
Texture2D TerrainColor : register(t2);
SamplerState Filter;

#define PI      3.14159265358979323846f
#define HALF_PI	1.57079632679489661923f

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
	float2 vWindDir;
	float terrainHeight;
	float fTime;
	int grassCount;
	int terrainSize;
	int colorTechnique;
}

struct GS_IN
{
	float3 Pos : Vertex;
	float2 Tex : TexCoord;
	float Var : Variance;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float3 Normal : Normal;
	float2 Tex : TexCoord;
	float2 Tex2 : TexCoord2;
	float Var : Color;
};

float rand(float seed) { return frac(sin(seed * (91.3458)) * 47453.5453); }
float rand(float2 seed) { return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453); }
float rand(float3 seed) { return frac(sin(dot(seed.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453); }

// Rotation with angle (in radians) and axis
float3x3 AngleAxis3x3(float angle, float3 axis)
{
	float c, s;
	sincos(angle, s, c);

	float t = 1 - c;
	float x = axis.x;
	float y = axis.y;
	float z = axis.z;

	return float3x3(
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c
		);
}

uint2 IndexToXY(uint index, uint width)
{
	return uint2(index % width, index / width);
}

GS_IN vs_main(uint vertexID : SV_VertexID)
{
	GS_IN Out = (GS_IN)0;

	float2 grid_pos = IndexToXY(vertexID, grassCount);
	// convert to uv space [0..1]
	float2 uv = grid_pos / (grassCount - 1);
	// generate position on terrain
	float3 startPosition = 0;
	float randomizedZDistance = (uv.y * terrainSize) + ((rand(uv.xy)*2-1) * 0.5f);
	float randomizedXDistance = (uv.x * terrainSize) + ((rand(uv.yx)*2-1) * 0.5f);
	int indexX = (int)((startPosition.x + randomizedXDistance));
	int indexZ = (int)((startPosition.z + randomizedZDistance));
	indexX = min(indexX, terrainSize - 1);
	indexZ = min(indexZ, terrainSize - 1);
	float3 Pos = float3(startPosition.x + (randomizedXDistance), HeightMap.Load(int3(indexX, indexZ, 0)).x * terrainHeight, startPosition.z + randomizedZDistance);
	Out.Pos = Pos;
	Out.Var = rand(Pos.xyz);
	Out.Tex = float2(uv.x, 1 - uv.y);
	return Out;
}

[maxvertexcount(30)]
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
	const float fWindStrength = 0.5f;
	const int vertexCount = 8;	// max 12
	float fGrassHeight = 2;		// grass height
	float fGrassWidth = 0.05;	// grass width

	float3 root = input[0].Pos;
	// add some randomness to grass size
	float random = rand(root.xz);
	fGrassWidth += (random / 100);
	fGrassHeight += (random / 6);

	float3x3 matRot = AngleAxis3x3(random * PI, float3(0, 1, 0));
	float currentV = 0;
	float offsetV = 1.0f / ((vertexCount / 2) - 1);

	float currentHeightOffset = 0;
	float currentVertexHeight = 0;
	float windCoEff = 0;

	PS_IN v[vertexCount];
	for (int i = 0; i < vertexCount; i++)
	{
		v[i].Normal = float3(0, 0, 1);
		
		if (fmod(i, 2) == 0)
		{
			v[i].Pos = float4(root.x - fGrassWidth, root.y + currentVertexHeight, root.z, 1);
			v[i].Tex = float2(0, 1-currentV);
		}
		else
		{
			v[i].Pos = float4(root.x + fGrassWidth, root.y + currentVertexHeight, root.z, 1);
			v[i].Tex = float2(1, 1-currentV);

			currentV += offsetV;
			currentVertexHeight = currentV * fGrassHeight;
		}
		// apply random rotation to grass blade
		v[i].Pos.xyz -= root;
		v[i].Pos.xyz = mul(v[i].Pos.xyz, matRot);
		v[i].Pos.xyz += root;

		// add wind
		float r = rand(root.xz);
		float2 wind = float2(sin(fTime + root.x * 0.5), cos(fTime + root.z * 0.5)) * fWindStrength * sin(fTime + r);
		wind += vWindDir;

		v[i].Pos.xz += wind.xy * windCoEff;
		v[i].Pos.y -= length(wind) * windCoEff * 0.5;
		v[i].Var = input[0].Var;
		v[i].Tex2 = input[0].Tex;

		v[i].Pos = mul(float4(v[i].Pos.xyz, 1), WVP);

		if (fmod(i, 2) == 1) 
		{
			windCoEff += offsetV * currentV;
		}
	}

	for (int p = 0; p < (vertexCount - 2); p++) 
	{
		// build triangles
		OutputStream.Append(v[p]);
		OutputStream.Append(v[p + 2]);
		OutputStream.Append(v[p + 1]);
	}
	OutputStream.RestartStrip();
}

float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = GrassBlade.Sample(Filter, In.Tex);
	clip(color.a - 0.5f);
	float4 tcolor = TerrainColor.Sample(Filter, In.Tex2);
	float colorVar = lerp(0.85, 1, In.Var);
	return lerp(color, tcolor, colorTechnique) * colorVar;
}
