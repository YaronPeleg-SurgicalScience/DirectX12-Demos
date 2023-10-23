Texture2D ParticleMap : register(t0);
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
	float4x4 invView;
	float deltaTime;
}

// particle data, should be synced with cpu particle struct
struct Particle
{
	float3 position;
	float3 initPosition;
	float3 velocity;
	float3 initVelocity;
	float3 color;
	float lifetime, initTime;
};
RWStructuredBuffer<Particle> particlesBuffer : register(u0);

struct GS_IN
{
	float3 Pos : Vertex;
	float4 Color : Color;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
	float4 Color : Color;
};

float rand(float2 co)
{
	return frac(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
}

[numthreads(256, 1, 1)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	const int index = dispatchThreadID.x;
	const float3 gravity = float3(0, -1, 0);

	particlesBuffer[index].velocity += 0.025 * gravity;
	particlesBuffer[index].position += particlesBuffer[index].velocity * deltaTime;
	particlesBuffer[index].lifetime -= deltaTime;
	if (particlesBuffer[index].lifetime <= 0.0f)
	{
		particlesBuffer[index].lifetime = particlesBuffer[index].initTime;
		particlesBuffer[index].position = particlesBuffer[index].initPosition;
		particlesBuffer[index].velocity = particlesBuffer[index].initVelocity;
		particlesBuffer[index].velocity.y += rand(dispatchThreadID.xy) * 5;
	}
}

GS_IN vs_main(uint vertexID : SV_VertexID)
{
	GS_IN Out = (GS_IN)0;
	Out.Pos.xyz = particlesBuffer[vertexID].position;
	Out.Color = float4(particlesBuffer[vertexID].color, saturate(particlesBuffer[vertexID].lifetime / particlesBuffer[vertexID].initTime));
	return Out;
}

[maxvertexcount(4)]
void gs_main(point GS_IN input[1], inout TriangleStream<PS_IN> OutputStream)
{
	PS_IN output = (PS_IN)0;
	float radius = 0.05f;
	float3 offsets[4] =
	{
		float3(-radius, radius, 0),
		float3(radius, radius, 0),
		float3(-radius, -radius, 0),
		float3(radius, -radius, 0),
	};
	float2 texcoords[4] =
	{
		float2(1,0),
		float2(0,0),
		float2(1,1),
		float2(0,1),
	};
	// create billboard aligned to camera view
	for (uint i = 0; i < 4; i++)
	{
		float3 offset = mul(offsets[i], (float3x3)invView);
		output.Pos = mul(float4(input[0].Pos.xyz + offset, 1), WVP);
		output.Tex = texcoords[i];
		output.Color = input[0].Color;
		OutputStream.Append(output);
	}
	OutputStream.RestartStrip();
}

float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = ParticleMap.Sample(Filter, In.Tex);
	// premultiply alpha
	color.xyz *= In.Color.xyz * In.Color.w;
	return color;
}
