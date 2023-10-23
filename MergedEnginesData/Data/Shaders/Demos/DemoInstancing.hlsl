Texture2D Texture;
SamplerState Filter;

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 WVP;
}

struct VS_IN
{
	float3 Pos : Vertex;
	float2 Tex : TexCoord;
	float3 InstancePos : InstancePos;
	float4 InstanceColor : InstanceColor;
	float4 InstanceRotation : InstanceRotation;
};

struct PS_IN
{
	float4 Pos : SV_Position;
	float2 Tex : TexCoord;
	float4 Color : Color;
};

// convert quaternion to rotation matrix
float3x3 quaternion_to_matrix(float4 quat)
{
	float x = quat.x, y = quat.y, z = quat.z, w = quat.w;
	float x2 = x + x, y2 = y + y, z2 = z + z;
	float xx = x * x2, xy = x * y2, xz = x * z2;
	float yy = y * y2, yz = y * z2, zz = z * z2;
	float wx = w * x2, wy = w * y2, wz = w * z2;
	float3x3 m;

	m[0][0] = 1.0 - (yy + zz);
	m[0][1] = xy - wz;
	m[0][2] = xz + wy;

	m[1][0] = xy + wz;
	m[1][1] = 1.0 - (xx + zz);
	m[1][2] = yz - wx;

	m[2][0] = xz - wy;
	m[2][1] = yz + wx;
	m[2][2] = 1.0 - (xx + yy);

	return m;
}

PS_IN vs_main(VS_IN In)
{
	// get object position
	float3 pos = In.Pos.xyz;
	// apply instance rotation
	pos = mul(pos, quaternion_to_matrix(In.InstanceRotation));
	// apply instance position
	pos += In.InstancePos;

	PS_IN Out;
	Out.Pos = mul(float4(pos, 1), WVP);
	Out.Tex = In.Tex;
	Out.Color = In.InstanceColor;
	return Out;
}

float4 ps_main(PS_IN In) : SV_Target
{
	return In.Color * Texture.Sample(Filter, In.Tex);
}
