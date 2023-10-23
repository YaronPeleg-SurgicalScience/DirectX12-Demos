#define NUM_BOUNCES		4
#define PI				3.14159265f
#define EPSILON			0.001f
#define ENABLE_ENVMAP	1	// enable/disable envmap sky

cbuffer ShaderConstants0 : register(b0)
{
	float4x4 matInvProj;
	float4x4 matInvView;
	float2 vPixelOffset;
	float3 vDirLight;
	float fSeed;
	float fSample;
}

// ray trace data
struct Ray
{
	float3 origin;
	float3 direction;
	float3 energy;
};

// ray intersection data
struct RayHit
{
	float3 position;
	float distance;
	float3 normal;
	float3 albedo;
	float3 specular;
	float smoothness;
	float3 emission;
};

// sphere primitive data
struct Sphere
{
	float3 position;
	float radius;
	float3 albedo;
	float3 specular;
	float smoothness;
	float3 emission;
};
RWTexture2D<float4>	result : register(u0);
StructuredBuffer<Sphere> spheres : register(t1);
Texture2D<float4> envmap : register(t2);
SamplerState Filter;

// create ray from origin and direction
Ray CreateRay(float3 origin, float3 direction)
{
	Ray ray;
	ray.origin = origin;
	ray.direction = direction;
	ray.energy = float3(1.0f, 1.0f, 1.0f);
	return ray;
}

// create empty/default ray hit
RayHit CreateRayHit()
{
	RayHit hit;
	hit.position = float3(0.0f, 0.0f, 0.0f);
	hit.distance = 1.#INF;
	hit.normal = float3(0.0f, 0.0f, 0.0f);
	hit.albedo = float3(0.0f, 0.0f, 0.0f);
	hit.specular = float3(0.0f, 0.0f, 0.0f);
	hit.smoothness = 0.0f;
	hit.emission = float3(0.0f, 0.0f, 0.0f);
	return hit;
}

// create ray from uv [-1..1]
Ray CreateCameraRay(float2 uv)
{
	// Transform the camera origin to world space
	float3 origin = mul(float4(0.0f, 0.0f, 0.0f, 1.0f), matInvView).xyz;

	// Invert the perspective projection of the view-space position
	float3 direction = mul(float4(uv, 0.0f, 1.0f), matInvProj).xyz;
	// Transform the direction from camera to world space and normalize
	direction = mul(float4(direction, 0.0f), matInvView).xyz;
	direction = normalize(direction);

	return CreateRay(origin, direction);
}

// simple x dot y with a factor
float sdot(float3 x, float3 y, float f = 1.0f)
{
	return saturate(f * dot(x, y));
}

// just average the color channels
float energy(float3 color)
{
	return dot(color, 1.0f / 3.0f);
}

// simple random for 2d coord with seed value
float rand(in float2 pixel)
{
	float result = frac(sin(fSeed * dot(pixel, float2(12.9898f, 78.233f))) * 43758.5453f);
	return result;
}

float SmoothnessToPhongAlpha(float s)
{
	return pow(1000.0f, s * s);
}

float3x3 GetTangentSpace(float3 normal)
{
	// Choose a helper vector for the cross product
	float3 helper = float3(1.0f, 0.0f, 0.0f);
	if (abs(normal.x) > 0.99f)
	{
		helper = float3(0.0f, 0.0f, 1.0f);
	}

	// Generate vectors
	float3 tangent = normalize(cross(normal, helper));
	float3 binormal = normalize(cross(normal, tangent));
	return float3x3(tangent, binormal, normal);
}

float3 SampleHemisphere(in float2 pixel, float3 normal, float alpha)
{
	// Uniformly sample hemisphere direction
	float cosTheta = pow(rand(pixel), 1.0f / (1.0f + alpha));
	float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
	float phi = 2.0f * PI * rand(pixel) * 100;
	float3 tangentSpaceDir = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

	// Transform direction to world space
	return mul(tangentSpaceDir, GetTangentSpace(normal));
}

void IntersectGroundPlane(Ray ray, inout RayHit bestHit)
{
	// Calculate the distance along the ray where the ground plane is intersected
	float t = -ray.origin.y / ray.direction.y;
	if (t > 0.0f && t < bestHit.distance)
	{
		bestHit.distance = t;
		bestHit.position = ray.origin + t * ray.direction;
		bestHit.normal = float3(0.0f, 1.0f, 0.0f);
		bestHit.albedo = 0.0f;
		bestHit.specular = 1.0f;
		bestHit.smoothness = 0.5f;
		bestHit.emission = 0.0f;
	}
}

void IntersectSphere(Ray ray, inout RayHit bestHit, Sphere sphere)
{
	// Calculate the distance along the ray where the sphere is intersected
	float3 d = ray.origin - sphere.position;
	float p1 = -dot(ray.direction, d);
	float p2sqr = p1 * p1 - dot(d, d) + sphere.radius * sphere.radius;
	if (p2sqr < 0.0f)
	{
		return;
	}

	float p2 = sqrt(p2sqr);
	float t = p1 - p2 > 0.0f ? p1 - p2 : p1 + p2;
	if (t > 0.0f && t < bestHit.distance)
	{
		bestHit.distance = t;
		bestHit.position = ray.origin + t * ray.direction;
		bestHit.normal = normalize(bestHit.position - sphere.position);
		bestHit.albedo = sphere.albedo;
		bestHit.specular = sphere.specular;
		bestHit.smoothness = sphere.smoothness;
		bestHit.emission = sphere.emission;
	}
}

// based on Gentlemen Tomas Akenine-Möller and Ben Trumbore in 1997
bool IntersectTriangle(Ray ray, float3 vert0, float3 vert1, float3 vert2, uniform bool backfacecull, inout float t, inout float u, inout float v)
{
	// find vectors for two edges sharing vert0
	float3 edge1 = vert1 - vert0;
	float3 edge2 = vert2 - vert0;

	// begin calculating determinant - also used to calculate U parameter
	float3 pvec = cross(ray.direction, edge2);

	// if determinant is near zero, ray lies in plane of triangle
	float det = dot(edge1, pvec);

	// use backface culling
	if (backfacecull && det < EPSILON)
		return false;

	float inv_det = 1.0f / det;

	// calculate distance from vert0 to ray origin
	float3 tvec = ray.origin - vert0;

	// calculate U parameter and test bounds
	u = dot(tvec, pvec) * inv_det;
	if (u < 0.0 || u > 1.0f)
		return false;

	// prepare to test V parameter
	float3 qvec = cross(tvec, edge1);

	// calculate V parameter and test bounds
	v = dot(ray.direction, qvec) * inv_det;
	if (v < 0.0 || u + v > 1.0f)
		return false;

	// calculate t, ray intersects triangle
	t = dot(edge2, qvec) * inv_det;

	return true;
}

RayHit Trace(Ray ray)
{
	RayHit bestHit = CreateRayHit();
	uint count, stride, i;

	IntersectGroundPlane(ray, bestHit);

	spheres.GetDimensions(count, stride);
	for (i = 0; i < count; i++)
	{
		IntersectSphere(ray, bestHit, spheres[i]);
	}

	// Trace single triangle
	float3 vertices[4] =
	{
		float3(-80, 0, 45),
		float3(-80, 30, 45),
		float3(80, 30, 45),
		float3(80, 0, 45)
	};
	int indices[6] = { 0, 1, 2, 0, 2, 3 };
	for (i = 0; i < 2; ++i)
	{
		int index = i * 3;
		float3 v0 = vertices[indices[index]];
		float3 v1 = vertices[indices[index+1]];
		float3 v2 = vertices[indices[index+2]];
		float t, u, v;
		if (IntersectTriangle(ray, v0, v1, v2, false, t, u, v))
		{
			if (t > 0 && t < bestHit.distance)
			{
				bestHit.distance = t;
				bestHit.position = ray.origin + t * ray.direction;
				bestHit.normal = normalize(cross(v1 - v0, v2 - v0));
				bestHit.albedo = 0;
				bestHit.specular = 0.6f;
				bestHit.smoothness = 1.0f;
				bestHit.emission = 0.2;
			}
		}
	}

	return bestHit;
}

float3 Shade(in float2 pixel, inout Ray ray, RayHit hit)
{
	if (hit.distance < 1.#INF)
	{
#if 1
		// apply shadows
		float3 dirLight = vDirLight;
		// add randomness (for softness)
		dirLight.xz += (rand(pixel) * 2 - 1) * 0.05;
		Ray shadowRay = CreateRay(hit.position + hit.normal * EPSILON, -1 * dirLight.xyz);
		RayHit shadowHit = Trace(shadowRay);
		if (shadowHit.distance < 1.#INF)
		{
			ray.energy *= 0.5;
			hit.emission *= 0.5f;
		}
#endif
		// calc the changes of diffuse and specular reflection
		hit.albedo = min(1.0f - hit.specular, hit.albedo);
		float specChance = energy(hit.specular);
		float diffChance = energy(hit.albedo);

		// do roulette-select the ray path
		float roulette = rand(pixel);
		if (roulette < specChance)
		{
			// Specular reflection
			ray.origin = hit.position + hit.normal * EPSILON;
			float alpha = SmoothnessToPhongAlpha(hit.smoothness);
			ray.direction = SampleHemisphere(pixel, reflect(ray.direction, hit.normal), alpha);
			float f = (alpha + 2.0f) / (alpha + 1.0f);
			ray.energy *= (1.0f / specChance) * hit.specular * sdot(hit.normal, ray.direction, f);
		}
		else if (diffChance > 0.0f && roulette < specChance + diffChance)
		{
			// Diffuse reflection
			ray.origin = hit.position + hit.normal * EPSILON;
			ray.direction = SampleHemisphere(pixel, hit.normal, 1.0f);
			ray.energy *= (1.0f / diffChance) * hit.albedo;
		}
		else
		{
			// Terminate the ray
			ray.energy = 0.0f;
		}

		return hit.emission;
	}
	else
	{
		// clear energy - the sky doesnt reflect anything
		ray.energy = 0;

#if ENABLE_ENVMAP
		// sample envmap sky
		float theta = acos(ray.direction.y) / PI;
		float phi = atan2(ray.direction.x, -ray.direction.z) / PI * 0.5f;
		return envmap.SampleLevel(Filter, float2(phi, theta), 0).xyz;
#else
		// simple gradient skycolor
		uint width, height;
		result.GetDimensions(width, height);
		return float3(0, pixel.y/height, 1.0);
#endif
	}
}

[numthreads(8, 8, 1)]
void cs_main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
	float2 pixel = dispatchThreadID.xy;
	int width, height;
	result.GetDimensions(width, height);
	if (pixel.x >= width || pixel.y >= height)
		return;

	// create pixel uv in [-1, 1] range
	float2 uv = 2.0f * (float2(pixel.xy + vPixelOffset) / float2(width, height)) - 1.0f;
	uv.y *= -1;

	// create ray from uv
	Ray ray = CreateCameraRay(uv);

	// trace and shade pixel
	float3 color = 0;
	for (int i = 0; i < NUM_BOUNCES; i++)
	{
		RayHit hit = Trace(ray);
		color += ray.energy * Shade(pixel, ray, hit);
		if (!any(ray.energy))
			break;
	}
	
	// output result
	result[pixel] = float4(color, 1.0f);
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

float4 ps_main(PS_IN In) : SV_Target
{
	float4 color = result[int2(In.Pos.xy)];	
	return float4(color.xyz, 1.0f / (fSample + 1.0f));
}


