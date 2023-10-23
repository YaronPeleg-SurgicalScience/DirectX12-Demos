// shader defines
#define DIST_ADAPT			1	// distance based adaptive tessellation
#define PNTRI				1	// use pn triangle tessellation
#define PHONG				0	// use phone tessellation
#define BF_CULL				1	// use backface culling
#define FRUST_CULL			1	// use frustum culling

// interleaved buffers
Buffer<uint>    g_IndicesBuffer : register(t0);
Buffer<float3>	g_PositionsBuffer : register(t1);
Buffer<float2>	g_UVsBuffer : register(t2);
Buffer<float3>	g_NormalsBuffer : register(t3);
Buffer<float3>	g_TangentsBuffer : register(t4);

// textures
Texture2D		TextureAlbedo : register(t7);
Texture2D		TextureNormal : register(t8);
Texture2D		TextureAO : register(t9);
Texture2D		TextureDisplacment : register(t10);
// sampler
SamplerState	Filter;

// constants
cbuffer ShaderConstants0 : register(b0)
{
	float4x4 matViewProj;
	float4x4 matWorld;
	float3	vEye;				// camera eye
	float3	vView;
	float2	vScreenSize;		// screen resolution ( x=width, y=height )
	float3	vLightPos;
	float	fBumpiness;
	float	fBackFaceEpsilon;
	float	fHeightScale;
	float4  vTessellationFactor;// Edge, inside, minimum tessellation factor and 1/desired triangle size
	float	fFrustumEpsilon;
	float4	vFrustumPlanes[4];	// frustum planes ( x=left, y=right, z=top, w=bottom )
}

// hs input
struct HS_IN
{
	float3 Pos			: Position;
	float3 Normal		: Normal;
	float3 Tangent		: Tangent;
	float2 Tex			: TexCoord;
#if (DIST_ADAPT == 1)
	float  fVertexDistanceFactor : VERTEXDISTANCEFACTOR;
#endif
};

struct HS_ConstantOutput
{
	// Tess factor for the FF HW block
	float Edges[3]  : SV_TessFactor;
	float Inside	: SV_InsideTessFactor;
	float sign		: SIGN;

#if ( PNTRI == 1 )

	// Geometry cubic generated control points
	float3 vB210    : POSITION3;
	float3 vB120    : POSITION4;
	float3 vB021    : POSITION5;
	float3 vB012    : POSITION6;
	float3 vB102    : POSITION7;
	float3 vB201    : POSITION8;
	float3 vB111    : CENTER;

	// Normal quadratic generated control points
	float3 vN110    : NORMAL3;
	float3 vN011    : NORMAL4;
	float3 vN101    : NORMAL5;

	// Tangent quadratic generated control points
	float3 vT110    : TANGENT3;
	float3 vT011    : TANGENT4;
	float3 vT101    : TANGENT5;
#endif
};

// hull shader control point output
struct HS_ControlPointOutput
{
	float3 Pos : Position;
	float3 Normal : Normal;
	float3 Tangent : Tangent;
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

//--------------------------------------------------------------------------------------
// vertex shader main
//--------------------------------------------------------------------------------------
HS_IN vs_main(uint vertexID : SV_VertexID)
{
	uint index = g_IndicesBuffer.Load(vertexID);
	HS_IN Out;
	float3 position = g_PositionsBuffer.Load(index).xyz;
	float4 vPositionWS = mul(float4(position.xyz, 1), matWorld);
	Out.Pos = vPositionWS.xyz;
	Out.Tex = g_UVsBuffer.Load(index);
	float3 normal = g_NormalsBuffer.Load(index);
	Out.Normal = mul(normal, (float3x3)matWorld);
	float3 tangent = g_TangentsBuffer.Load(index);
	Out.Tangent = mul(tangent, (float3x3)matWorld);

#if (DIST_ADAPT == 1)
	// Min and max distance should be chosen according to scene quality requirements
	const float fMinDistance = 1.0f;
	const float fMaxDistance = 10.0f;

	// Calculate distance between vertex and camera, and a vertex distance factor issued from it
	float fDistance = distance(vPositionWS.xyz, vEye);
	Out.fVertexDistanceFactor = 1.0 - clamp(((fDistance - fMinDistance) / (fMaxDistance - fMinDistance)), 0.0, 1.0 - vTessellationFactor.z / vTessellationFactor.x);
#endif

	return Out;
}

//--------------------------------------------------------------------------------------
// Returns the dot product between the viewing vector and the patch edge
//--------------------------------------------------------------------------------------
float GetEdgeDotProduct(
	float3 vEdgeNormal0,   // Normalized normal of the first control point of the given patch edge 
	float3 vEdgeNormal1,   // Normalized normal of the second control point of the given patch edge 
	float3 vView     // Normalized viewing vector
)
{
	float3 vEdgeNormal = normalize((vEdgeNormal0 + vEdgeNormal1) * 0.5f);
	float fEdgeDotProduct = dot(vEdgeNormal, vView);
	return fEdgeDotProduct;
}

//--------------------------------------------------------------------------------------
// Returns back face culling test result (true / false)
//--------------------------------------------------------------------------------------
bool BackFaceCull(
	float fEdgeDotProduct0, // Dot product of edge 0 normal with view vector
	float fEdgeDotProduct1, // Dot product of edge 1 normal with view vector
	float fEdgeDotProduct2, // Dot product of edge 2 normal with view vector
	float fBackFaceEpsilon  // Epsilon to determine cut off value for what is considered back facing
)
{
	float3 vBackFaceCull;
	vBackFaceCull.x = (fEdgeDotProduct0 > fBackFaceEpsilon) ? (1.0f) : (0.0f);
	vBackFaceCull.y = (fEdgeDotProduct1 > fBackFaceEpsilon) ? (1.0f) : (0.0f);
	vBackFaceCull.z = (fEdgeDotProduct2 > fBackFaceEpsilon) ? (1.0f) : (0.0f);
	return all(vBackFaceCull);
}

// orthogonal projection of q onto the plane defined by I.f3Position and I.f3Normal
float3 PI(HS_ControlPointOutput q, HS_ControlPointOutput I)
{
	float3 q_minus_p = q.Pos - I.Pos;
	return q.Pos - dot(q_minus_p, I.Normal) * I.Normal;
}

//--------------------------------------------------------------------------------------
// Returns the distance of a given point from a given plane
//--------------------------------------------------------------------------------------
float DistanceFromPlane(
	float3 vPosition,      // World space position of the patch control point
	float4 vPlaneEquation  // Plane equation of a frustum plane
)
{
	float fDistance = dot(float4(vPosition, 1.0f), vPlaneEquation);
	return fDistance;
}

//--------------------------------------------------------------------------------------
// Returns view frustum Culling test result (true / false)
//--------------------------------------------------------------------------------------
bool TriangleInFrustum(
	float3 vVertexPosition0,        // World space position of patch control point 0
	float3 vVertexPosition1,        // World space position of patch control point 1
	float3 vVertexPosition2,		// World space position of patch control point 2
	float4 vFrustumPlanes[4],		// 4 plane equations (left, right, top, bottom)
	float fCullEpsilon              // Epsilon to determine the distance outside the view frustum is still considered inside
)
{
	float4 vPlaneTest;
	float fPlaneTest;

	// Left clip plane
	vPlaneTest.x = ((DistanceFromPlane(vVertexPosition0, vFrustumPlanes[0]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition1, vFrustumPlanes[0]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition2, vFrustumPlanes[0]) > -fCullEpsilon) ? 1.0f : 0.0f);
	// Right clip plane
	vPlaneTest.y = ((DistanceFromPlane(vVertexPosition0, vFrustumPlanes[1]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition1, vFrustumPlanes[1]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition2, vFrustumPlanes[1]) > -fCullEpsilon) ? 1.0f : 0.0f);
	// Top clip plane
	vPlaneTest.z = ((DistanceFromPlane(vVertexPosition0, vFrustumPlanes[2]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition1, vFrustumPlanes[2]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition2, vFrustumPlanes[2]) > -fCullEpsilon) ? 1.0f : 0.0f);
	// Bottom clip plane
	vPlaneTest.w = ((DistanceFromPlane(vVertexPosition0, vFrustumPlanes[3]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition1, vFrustumPlanes[3]) > -fCullEpsilon) ? 1.0f : 0.0f) +
				   ((DistanceFromPlane(vVertexPosition2, vFrustumPlanes[3]) > -fCullEpsilon) ? 1.0f : 0.0f);

	// Triangle has to pass all 4 plane tests to be visible
	return !all(vPlaneTest);
}

//--------------------------------------------------------------------------------------
// This hull shader passes the tessellation factors through to the HW tessellator, 
// and the 10 (geometry), 6 (normal) control points of the PN-triangular patch to the domain shader
//--------------------------------------------------------------------------------------
HS_ConstantOutput hs_mainConstant(InputPatch<HS_IN, 3> I)
{
	HS_ConstantOutput O = (HS_ConstantOutput)0;
	// Use the tessellation factors as defined in constant space 
	float4 vEdgeTessellationFactors = vTessellationFactor.xxxy;

#if ( FRUST_CULL == 1 )

	// Perform view frustum culling test
	if (TriangleInFrustum(I[0].Pos, I[1].Pos, I[2].Pos, vFrustumPlanes, fFrustumEpsilon) == true)
	{
		// Cull the patch (all the tess factors are set to 0)
		return O;
	}

#endif

#if ( BF_CULL == 1 )

	// Perform back face culling test
	float fEdgeDot[3];

	// Aquire patch edge dot product between patch edge normal and view vector 
	fEdgeDot[0] = GetEdgeDotProduct(I[2].Normal, I[0].Normal, vView.xyz);
	fEdgeDot[1] = GetEdgeDotProduct(I[0].Normal, I[1].Normal, vView.xyz);
	fEdgeDot[2] = GetEdgeDotProduct(I[1].Normal, I[2].Normal, vView.xyz);

	// If all 3 fail the test then back face cull
	if (BackFaceCull(fEdgeDot[0], fEdgeDot[1], fEdgeDot[2], fBackFaceEpsilon) == true)
	{
		// Cull the patch (all the tess factors are set to 0)
		return O;
	}

#endif

#if ( DIST_ADAPT == 1 )

	// Calculate edge scale factor from vertex scale factor: simply compute 
	// average tess factor between the two vertices making up an edge
	vEdgeTessellationFactors.x = 0.5 * (I[2].fVertexDistanceFactor + I[0].fVertexDistanceFactor);
	vEdgeTessellationFactors.y = 0.5 * (I[0].fVertexDistanceFactor + I[1].fVertexDistanceFactor);
	vEdgeTessellationFactors.z = 0.5 * (I[1].fVertexDistanceFactor + I[2].fVertexDistanceFactor);
	vEdgeTessellationFactors.w = vEdgeTessellationFactors.x;

	// Multiply them by global tessellation factor
	vEdgeTessellationFactors *= vTessellationFactor.xxxy;
#endif

#if ( PNTRI == 1 )
	// Now setup the PNTriangle control points...

	// Assign Positions
	float3 vB003 = I[0].Pos;
	float3 vB030 = I[1].Pos;
	float3 vB300 = I[2].Pos;
	// And Normals
	float3 vN002 = I[0].Normal;
	float3 vN020 = I[1].Normal;
	float3 vN200 = I[2].Normal;
	// And Tangents
	float3 vT002 = I[0].Tangent;
	float3 vT020 = I[1].Tangent;
	float3 vT200 = I[2].Tangent;

	// Compute the cubic geometry control points
	// Edge control points
	O.vB210 = ((2.0f * vB003) + vB030 - (dot((vB030 - vB003), vN002) * vN002)) / 3.0f;
	O.vB120 = ((2.0f * vB030) + vB003 - (dot((vB003 - vB030), vN020) * vN020)) / 3.0f;
	O.vB021 = ((2.0f * vB030) + vB300 - (dot((vB300 - vB030), vN020) * vN020)) / 3.0f;
	O.vB012 = ((2.0f * vB300) + vB030 - (dot((vB030 - vB300), vN200) * vN200)) / 3.0f;
	O.vB102 = ((2.0f * vB300) + vB003 - (dot((vB003 - vB300), vN200) * vN200)) / 3.0f;
	O.vB201 = ((2.0f * vB003) + vB300 - (dot((vB300 - vB003), vN002) * vN002)) / 3.0f;
	// Center control point
	float3 vE = (O.vB210 + O.vB120 + O.vB021 + O.vB012 + O.vB102 + O.vB201) / 6.0f;
	float3 vV = (vB003 + vB030 + vB300) / 3.0f;
	O.vB111 = vE + ((vE - vV) / 2.0f);

	// Compute the quadratic normal control points, and rotate into world space
	float fV12 = 2.0f * dot(vB030 - vB003, vN002 + vN020) / dot(vB030 - vB003, vB030 - vB003);
	O.vN110 = normalize(vN002 + vN020 - fV12 * (vB030 - vB003));
	float fV23 = 2.0f * dot(vB300 - vB030, vN020 + vN200) / dot(vB300 - vB030, vB300 - vB030);
	O.vN011 = normalize(vN020 + vN200 - fV23 * (vB300 - vB030));
	float fV31 = 2.0f * dot(vB003 - vB300, vN200 + vN002) / dot(vB003 - vB300, vB003 - vB300);
	O.vN101 = normalize(vN200 + vN002 - fV31 * (vB003 - vB300));

	// Compute the quadratic tangent control points, and rotate into world space
	fV12 = 2.0f * dot(vB030 - vB003, vT002 + vT020) / dot(vB030 - vB003, vB030 - vB003);
	O.vT110 = normalize(vT002 + vT020 - fV12 * (vB030 - vB003));
	fV23 = 2.0f * dot(vB300 - vB030, vT020 + vT200) / dot(vB300 - vB030, vB300 - vB030);
	O.vT011 = normalize(vT020 + vT200 - fV23 * (vB300 - vB030));
	fV31 = 2.0f * dot(vB003 - vB300, vT200 + vT002) / dot(vB003 - vB300, vB003 - vB300);
	O.vT101 = normalize(vT200 + vT002 - fV31 * (vB003 - vB300));
#endif

	float2 t01 = I[1].Tex - I[0].Tex;
	float2 t02 = I[2].Tex - I[0].Tex;
	O.sign = t01.x * t02.y - t01.y * t02.x > 0.0f ? 1 : -1;

	// Assign tessellation levels
	O.Edges[0] = vEdgeTessellationFactors.x;
	O.Edges[1] = vEdgeTessellationFactors.y;
	O.Edges[2] = vEdgeTessellationFactors.z;
	O.Inside   = vEdgeTessellationFactors.w;

	return O;
}

//--------------------------------------------------------------------------------------
// hull shader main
//--------------------------------------------------------------------------------------
[domain("tri")]
[partitioning("fractional_even")]
[outputtopology("triangle_cw")]
[patchconstantfunc("hs_mainConstant")]
[outputcontrolpoints(3)]
[maxtessfactor(64.0f)]
HS_ControlPointOutput hs_main(InputPatch<HS_IN, 3> I, uint uCPID : SV_OutputControlPointID)
{
	HS_ControlPointOutput O = (HS_ControlPointOutput)0;

	// Just pass through inputs = fast pass through mode triggered
	O.Pos = I[uCPID].Pos;
	O.Normal = I[uCPID].Normal;
	O.Tangent = I[uCPID].Tangent;
	O.Tex = I[uCPID].Tex;

	return O;
}

//--------------------------------------------------------------------------------------
// domain shader main, applies contol point weighting to the barycentric coords produced by the FF tessellator 
//--------------------------------------------------------------------------------------
[domain("tri")]
PS_IN ds_main(HS_ConstantOutput HSConstantData, const OutputPatch<HS_ControlPointOutput, 3> I, float3 vBarycentricCoords : SV_DomainLocation)
{
	PS_IN Out = (PS_IN)0;

	// The barycentric coordinates
	float fU = vBarycentricCoords.x;
	float fV = vBarycentricCoords.y;
	float fW = vBarycentricCoords.z;

	// Precompute squares 
	float fUU = fU * fU;
	float fVV = fV * fV;
	float fWW = fW * fW;

#if ( PHONG == 1 )

	float3 vPosition = I[0].Pos * fWW +
		I[1].Pos * fUU +
		I[2].Pos * fVV +
		fW * fU * (PI(I[0], I[1]) + PI(I[1], I[0])) +
		fU * fV * (PI(I[1], I[2]) + PI(I[2], I[1])) +
		fV * fW * (PI(I[2], I[0]) + PI(I[0], I[2]));

	float t = 0.5;

	vPosition = vPosition * t + (I[0].Pos * fW + I[1].Pos * fU + I[2].Pos * fV) * (1 - t);

	float3 vNormal = I[0].Normal * fW + I[1].Normal * fU + I[2].Normal * fV;
	float3 vTangent = I[0].Tangent * fW + I[1].Tangent * fU + I[2].Tangent * fV;
#endif

#if ( PNTRI == 1 )
	// Precompute squares * 3 
	float fUU3 = fUU * 3.0f;
	float fVV3 = fVV * 3.0f;
	float fWW3 = fWW * 3.0f;

	// Compute position from cubic control points and barycentric coords
	float3 vPosition = I[0].Pos * fWW * fW +
		I[1].Pos * fUU * fU +
		I[2].Pos * fVV * fV +
		HSConstantData.vB210 * fWW3 * fU +
		HSConstantData.vB120 * fW * fUU3 +
		HSConstantData.vB201 * fWW3 * fV +
		HSConstantData.vB021 * fUU3 * fV +
		HSConstantData.vB102 * fW * fVV3 +
		HSConstantData.vB012 * fU * fVV3 +
		HSConstantData.vB111 * 6.0f * fW * fU * fV;

	// Compute normal from quadratic control points and barycentric coords
	float3 vNormal = I[0].Normal * fWW + I[1].Normal * fUU + I[2].Normal * fVV;/* +
		HSConstantData.vN110 * fW * fU +
		HSConstantData.vN011 * fU * fV +
		HSConstantData.vN101 * fW * fV;*/

	float3 vTangent = I[0].Tangent * fWW + I[1].Tangent * fUU + I[2].Tangent * fVV;/* +
		HSConstantData.vT110 * fW * fU +
		HSConstantData.vT011 * fU * fV +
		HSConstantData.vT101 * fW * fV;*/
#endif

	// Normalize the interpolated normal    
	vNormal = normalize(vNormal);
	// Normalize the interpolated tangent    
	vTangent = normalize(vTangent);

	// Linearly interpolate the texture coords
	float2 UV = I[0].Tex * fW + I[1].Tex * fU + I[2].Tex * fV;

	float2 displacementTexCoord = UV;

	float fHeight = TextureDisplacment.SampleLevel(Filter, displacementTexCoord, 0).x * 2 - 1;

	UV = displacementTexCoord;

	// handle uv seams and cracks
	bool bDisplace = true;

#if 1
	// shared edges
	if (UV.y == 0) bDisplace = false;
	if (UV.y == 1) bDisplace = false;
	if (UV.x == 0) bDisplace = false;
	if (UV.x == 1) bDisplace = false;

	// Corners
	if (UV.x == 0 && UV.y == 0) bDisplace = false;
	if (UV.x == 1 && UV.y == 0) bDisplace = false;
	if (UV.x == 1 && UV.y == 1) bDisplace = false;
	if (UV.x == 0 && UV.y == 1) bDisplace = false;
#endif
	if (bDisplace)
		vPosition += vNormal * (fHeightScale * (fHeight));

	Out.Pos = mul(float4(vPosition.xyz, 1.0), matViewProj);
	Out.vWorldPos = vPosition.xyz;
	Out.Tex = UV;
	Out.Normal = vNormal.xyz;
	Out.Tangent = vTangent.xyz;
	Out.Bitangent = cross(vTangent, vNormal) * HSConstantData.sign;
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

//--------------------------------------------------------------------------------------
// pixel shader main
//--------------------------------------------------------------------------------------
float4 ps_main(PS_IN In) : SV_Target
{
	// get normal in tangent space
	float3 normalTS = SampleNormalMap(TextureNormal, Filter, In.Tex).xyz;
	// control bumpiness
	const float3 vSmoothNormal = { 0.5f, 0.5f, 1.0f };
	normalTS = lerp(vSmoothNormal, normalTS.xyz, max(fBumpiness, 0.001f));
	normalTS = normalize(normalTS * 2.0 - 1.0);
	// transform into world space
	float3 normalWS = normalize(normalize(In.Tangent) * normalTS.x + normalize(In.Bitangent) * normalTS.y + normalize(In.Normal) * normalTS.z);
	// to light
	float3 vToLight = normalize(vLightPos - In.vWorldPos);
	// to eye
	float3 vToEye = normalize(vEye.xyz - In.vWorldPos);
	// diffuse term
	float ndotl = saturate(dot(normalWS, vToLight) * 0.8f + 0.2f);
	float3 baseColor = TextureAlbedo.Sample(Filter, In.Tex).xyz;
	float3 diffuse = ndotl * baseColor;
	// specular term
	float3 R = reflect(-vToLight, normalWS);
	float RdotV = dot(R, vToEye);
	float3 specular = pow(max(0.0f, RdotV), 32);
	// get ao
	float3 ao = TextureAO.Sample(Filter, In.Tex).xxx;
	// output result
	return float4(ao * (diffuse + specular), 1);
}
