 
#include "LightHelper.fx"
 
cbuffer cbPerFrame
{
	DirectionalLight gDirLights[3];
	float3 gEyePosW;

	float  gFogStart;
	float  gFogRange;
	float4 gFogColor;
	
	// When distance is minimum, the tessellation is maximum.
	// When distance is maximum, the tessellation is minimum.
	// 거리가 최소이면 테셀레이션계수는 최대이다.
	// 거리가 최대이면 테셀레이션계수는 최소이다.
	float gMinDist;
	float gMaxDist;

	// Exponents for power of 2 tessellation.  The tessellation
	// range is [2^(gMinTess), 2^(gMaxTess)].  Since the maximum
	// tessellation is 64, this means gMaxTess can be at most 6
	// since 2^6 = 64.

	// 2의 제곱수 형태이 테셀레이션 계수를 위한 지수
	// 테셀레이션 계수의 범위는 2^gMinTess ~ 2^gMaxTess이다
	// 최대계수는 64이므로 gMaxTess는 6을 넘으면 안된다
	// 최소계수는 1이고 그때 gMinTexx값은 0 이다.
	float gMinTess;
	float gMaxTess;
	
	float gTexelCellSpaceU;
	float gTexelCellSpaceV;
	float gWorldCellSpace;
	float2 gTexScale = 50.0f;
	
	float4 gWorldFrustumPlanes[6];
};

cbuffer cbPerObject
{
	// Terrain coordinate specified directly 
	// at center of world space.
	
	float4x4 gViewProj;
	Material gMaterial;
};

// Nonnumeric values cannot be added to a cbuffer.
Texture2DArray gLayerMapArray;
Texture2D gBlendMap;
Texture2D gHeightMap;

SamplerState samLinear
{
	Filter = MIN_MAG_MIP_LINEAR;

	AddressU = WRAP;
	AddressV = WRAP;
};

SamplerState samHeightmap
{
	Filter = MIN_MAG_LINEAR_MIP_POINT;

	AddressU = CLAMP;
	AddressV = CLAMP;
};

struct VertexIn
{
	float3 PosL     : POSITION;
	float2 Tex      : TEXCOORD0;
	float2 BoundsY  : TEXCOORD1;
};

struct VertexOut
{
	float3 PosW     : POSITION;
	float2 Tex      : TEXCOORD0;
	float2 BoundsY  : TEXCOORD1;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Terrain specified directly in world space.
	// 터레인이 월드공간에 지정
	vout.PosW = vin.PosL;

	// Displace the patch corners to world space.  This is to make 
	// the eye to patch distance calculation more accurate.
	// 패치 모통이 정점들을 적절한 높이로 지정한다.
	// 나중에 시점에서 패치까지의 거리 계산이 좀더 정확해진다.

	// DXGI_FORMAT_R16_FLOAT로 지정했기 때문에 r로 빼면 된다.
	vout.PosW.y = gHeightMap.SampleLevel( samHeightmap, vin.Tex, 0 ).r;

	// Output vertex attributes to next stage.
	vout.Tex      = vin.Tex;
	vout.BoundsY  = vin.BoundsY;
	
	return vout;
}
 
float CalcTessFactor(float3 p)
{
	// 들어온 워치와 시점까지의 거리를 계산
	float d = distance(p, gEyePosW);

	// max norm in xz plane (useful to see detail levels from a bird's eye).
	//float d = max( abs(p.x-gEyePosW.x), abs(p.z-gEyePosW.z) );
	
	// 어느정도 위치에 있는지 계산 // 사이에 있으면 0 ~ 1값이 나오고
	// 만약 최소값보다 작아서 -가 나온다면 0 / 최대값보다 멀리 있다면 1이 나온다
	float s = saturate( (d - gMinDist) / (gMaxDist - gMinDist) );
	
	// 최종적인 테셀레이션 계수를 구해준다. s는 항상 0 ~ 1이므로 지수는 gMinTess ~ gMaxTess이다.
	return pow(2, (lerp(gMaxTess, gMinTess, s)) );
}

// Returns true if the box is completely behind (in negative half space) of plane.
bool AabbBehindPlaneTest(float3 center, float3 extents, float4 plane)
{
	// 경계상자가 축정렬되어있어서 편하다.

	float3 n = abs(plane.xyz);
	
	// This is always positive.
	// 이는 평면의 법선에 경계박스의 반지름들을 정사영 내린것의 길이이다.
	/*
	이 각각의 반지름은 축정렬이 되어있다. 
	// a0r0 = (a0 , 0 , 0) / a1r1 = (0 , a1 , 0) / a2r2 = (0 , 0 , a2)
	각각 평면의 법선벡터에 정사영을 내린 길이를 더하면되는데
	예를들어 | (a0r0 dot n) / |n| | 이런식인데 |n|은 1이므로 | a0r0 dot n |이다.
	그러면 | a0 * n0 |으로 변한다.
	그런데 여기서 a0는 길이이기 때문에 항상 양수이므로
	a0 * |n0|로 바꿔 쓸 수 있다.
	즉 a0 * |n0| + a1 * |n1| + a2 * |n2|
	좀더 간단히 나타내면 (a0,a1,a2) dot |n|
	*/
	float r = dot(extents, n);
	
	// signed distance from center point to plane.
	// 점과 평면사이의 거리 음의값도 나올 수 있음 
	// 절댓값안씌웠기 때문에 음인지 양인지로 중점이 어느공간에 있는지 판단한다
	// 
	float s = dot( float4(center, 1.0f), plane );
	
	// If the center point of the box is a distance of e or more behind the
	// plane (in which case s is negative since it is behind the plane),
	// then the box is completely in the negative half space of the plane.

	// 완전히 평면의 음공간에 모든 면이 있어야 컬링을 한다.
	return (s + r) < 0.0f;
}

// Returns true if the box is completely outside the frustum.
bool AabbOutsideFrustumTest(float3 center, float3 extents, float4 frustumPlanes[6])
{
	for(int i = 0; i < 6; ++i)
	{
		// If the box is completely behind any of the frustum planes
		// then it is outside the frustum.
		// 만약 상자가 완전히 절두체 평면의 뒤에 있다면 (음의 공간) 절두체 바깥에 존재하는 것이다.
		if( AabbBehindPlaneTest(center, extents, frustumPlanes[i]) )
		{
			return true;
		}
	}
	
	return false;
}

struct PatchTess
{
	float EdgeTess[4]   : SV_TessFactor;
	float InsideTess[2] : SV_InsideTessFactor;
};

/*
constant hull shader
여기에서는 패치의 중점과 패치의 각 변의 중점에서 이 테셀레이션 계수 계산함수를 적용해서
내부 테셀레이션 계수와 변 테셀레이션 계수들을 결정한다.
*/
PatchTess ConstantHS(InputPatch<VertexOut, 4> patch, uint patchID : SV_PrimitiveID)
{
	PatchTess pt;
	
	//
	// Frustum cull
	//
	
	// We store the patch BoundsY in the first control point.
	float minY = patch[0].BoundsY.x;
	float maxY = patch[0].BoundsY.y;
	
	// Build axis-aligned bounding box.  patch[2] is lower-left corner
	// and patch[1] is upper-right corner.
	/*
					patch[1]	
			* -- *
			l  / l
			* -- *
	patch[2]
	*/
	float3 vMin = float3(patch[2].PosW.x, minY, patch[2].PosW.z);
	float3 vMax = float3(patch[1].PosW.x, maxY, patch[1].PosW.z);
	
	// 상자 중앙점
	float3 boxCenter  = 0.5f*(vMin + vMax);
	// 상자 범위 // 길이 -boxExtents <= 상자길이 <= boxExtents
	float3 boxExtents = 0.5f*(vMax - vMin);
	// 만약 절두체 컬링에 의해서 걸러진 것들은 테셀레이션을 실행하지 않는다.
	// 한패치의 테셀레이션 계수들이 모두 0이면 GPU는 그패치를 폐기한다.
	// 한패치가 테셀레이션되고나서 생긴 삼각형들 절단과정에서 폐가하는 것보다 테셀레이션 부터 막는게 낫다.
	if( AabbOutsideFrustumTest(boxCenter, boxExtents, gWorldFrustumPlanes) )
	{
		// 아예 안보임
		pt.EdgeTess[0] = 0.0f;
		pt.EdgeTess[1] = 0.0f;
		pt.EdgeTess[2] = 0.0f;
		pt.EdgeTess[3] = 0.0f;
		
		pt.InsideTess[0] = 0.0f;
		pt.InsideTess[1] = 0.0f;
		
		return pt;
	}
	//
	// Do normal tessellation based on distance.
	//

	// 기본적인 테셀레이션을 거리기반으로 실행한다.

	else 
	{
		// It is important to do the tess factor calculation based on the
		// edge properties so that edges shared by more than one patch will
		// have the same tessellation factor.  Otherwise, gaps can appear.
		
		// 테셀레이션 계수 계산을 변속성기반으로 수행한다. 
		// 그렇지 않으면 같은 변이 다른 계수를 갖게 되고 틈이 발생한다.
		
		// Compute midpoint on edges, and patch center
		// 각 변의 가운데 점을 계산 / 패치의 중점 계산
		float3 e0 = 0.5f*(patch[0].PosW + patch[2].PosW);
		float3 e1 = 0.5f*(patch[0].PosW + patch[1].PosW);
		float3 e2 = 0.5f*(patch[1].PosW + patch[3].PosW);
		float3 e3 = 0.5f*(patch[2].PosW + patch[3].PosW);
		float3  c = 0.25f*(patch[0].PosW + patch[1].PosW + patch[2].PosW + patch[3].PosW);
		
		// 가운데 점들 기준으로 테셀레이션 계수를 함수로 얻어낸다.
		// 이함수는 눈과의 거리를 계산해서 거리에 따라서 2의 제곱수로 반환하는 함수이다. 최소1 최대 64로 반환된다.
		pt.EdgeTess[0] = CalcTessFactor(e0);
		pt.EdgeTess[1] = CalcTessFactor(e1);
		pt.EdgeTess[2] = CalcTessFactor(e2);
		pt.EdgeTess[3] = CalcTessFactor(e3);
		
		pt.InsideTess[0] = CalcTessFactor(c);
		pt.InsideTess[1] = pt.InsideTess[0];
	
		return pt;
	}
}

struct HullOut
{
	float3 PosW     : POSITION;
	float2 Tex      : TEXCOORD0;
};

[domain("quad")]
[partitioning("fractional_even")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(4)]
[patchconstantfunc("ConstantHS")]
[maxtessfactor(64.0f)]
HullOut HS(InputPatch<VertexOut, 4> p, 
           uint i : SV_OutputControlPointID,
           uint patchId : SV_PrimitiveID)
{
	HullOut hout;
	
	// Pass through shader.
	// 그대로 넘겨준다.
	hout.PosW     = p[i].PosW;
	hout.Tex      = p[i].Tex;
	
	return hout;
}

struct DomainOut
{
	float4 PosH     : SV_POSITION;
    float3 PosW     : POSITION;
	float2 Tex      : TEXCOORD0;
	float2 TiledTex : TEXCOORD1;
};

// The domain shader is called for every vertex created by the tessellator.  
// It is like the vertex shader after tessellation.
[domain("quad")]
DomainOut DS(PatchTess patchTess, 
             float2 uv : SV_DomainLocation, 
             const OutputPatch<HullOut, 4> quad)
{
	DomainOut dout;
	
	// Bilinear interpolation.
	// 겹선 보간
	// 패치 좌표계의 uv값이 나와있기 때문에 그를 이용하여 패치의 월드 좌표계 기준으로 겹선 보간을 해준다.
	dout.PosW = lerp(
		lerp(quad[0].PosW, quad[1].PosW, uv.x),
		lerp(quad[2].PosW, quad[3].PosW, uv.x),
		uv.y); 
	
	dout.Tex = lerp(
		lerp(quad[0].Tex, quad[1].Tex, uv.x),
		lerp(quad[2].Tex, quad[3].Tex, uv.x),
		uv.y); 
		
	// Tile layer textures over terrain.
	// 이는 타일링하기 위한 작업 
	// 이렇게 곱해주면 uv가 gTexScale 배가 되고 samplerstate가 wrap모드이기 떄문에 타일링효과가 나타난다.
	dout.TiledTex = dout.Tex*gTexScale; 
	
	// Displacement mapping
	// 변위 매핑
	dout.PosW.y = gHeightMap.SampleLevel( samHeightmap, dout.Tex, 0 ).r;
	
	// NOTE: We tried computing the normal in the shader using finite difference, 
	// but the vertices move continuously with fractional_even which creates
	// noticable light shimmering artifacts as the normal changes.  Therefore,
	// we moved the calculation to the pixel shader. 
	/*
	원래 여기서 노말을 계산하려고 했으나 // 유한 차분법을 사용해서
	fractional_even(분수 짝수)의 경우 정점들이 끊임 없이 움직이기 때문에
	법선의 변화에 따라 빛이 가물거리는 현상이 두드러졌다.
	따라서 픽셀쉐이더로 옮겼다.
	*/
	
	// Project to homogeneous clip space.
	dout.PosH    = mul(float4(dout.PosW, 1.0f), gViewProj);
	
	return dout;
}

float4 PS(DomainOut pin, 
          uniform int gLightCount, 
		  uniform bool gFogEnabled) : SV_Target
{
	//
	// Estimate normal and tangent using central differences.
	//

	// 접선벡터와 노말벡터를 중심차분법을 이용해서 추정(평가)한다.

	// 이픽셀기준으로 총4개의 주변픽셀들의 uv좌표를 구한다.
	float2 leftTex   = pin.Tex + float2(-gTexelCellSpaceU, 0.0f);
	float2 rightTex  = pin.Tex + float2(gTexelCellSpaceU, 0.0f);
	float2 bottomTex = pin.Tex + float2(0.0f, gTexelCellSpaceV);
	float2 topTex    = pin.Tex + float2(0.0f, -gTexelCellSpaceV);
	
	// 그 주변픽셀들의 높이값들을 구한다.
	float leftY   = gHeightMap.SampleLevel( samHeightmap, leftTex, 0 ).r;
	float rightY  = gHeightMap.SampleLevel( samHeightmap, rightTex, 0 ).r;
	float bottomY = gHeightMap.SampleLevel( samHeightmap, bottomTex, 0 ).r;
	float topY    = gHeightMap.SampleLevel( samHeightmap, topTex, 0 ).r;
	
	// 그 주변픽셀의 기울기를 구하는 것이라고 보면된다. 
	// 단 v는 y값과 방향이 반대이기 때문에 topY-bottomY가 아닌 bottomY-topY이다.
	float3 tangent = normalize(float3(2.0f*gWorldCellSpace, rightY - leftY, 0.0f));
	float3 bitan   = normalize(float3(0.0f, bottomY - topY, -2.0f*gWorldCellSpace)); 
	float3 normalW = cross(tangent, bitan);


	// The toEye vector is used in lighting.
	float3 toEye = gEyePosW - pin.PosW;

	// Cache the distance to the eye from this surface point.
	float distToEye = length(toEye);

	// Normalize.
	toEye /= distToEye;
	
	//
	// Texturing
	//
	
	// Sample layers in texture array.
	// 텍스처 배열의 저장된 텍스처 계층들에서 표본들을 추출한다. // 5장의 텍스처 // 마지막값은 텍스처 인덱스
	float4 c0 = gLayerMapArray.Sample( samLinear, float3(pin.TiledTex, 0.0f) );
	float4 c1 = gLayerMapArray.Sample( samLinear, float3(pin.TiledTex, 1.0f) );
	float4 c2 = gLayerMapArray.Sample( samLinear, float3(pin.TiledTex, 2.0f) );
	float4 c3 = gLayerMapArray.Sample( samLinear, float3(pin.TiledTex, 3.0f) );
	float4 c4 = gLayerMapArray.Sample( samLinear, float3(pin.TiledTex, 4.0f) ); 
	
	// Sample the blend map.
	// 하나의 텍스처에서 총 4장의 혼합맵을 추출한다.
	float4 t  = gBlendMap.Sample( samLinear, pin.Tex ); 
    
    // Blend the layers on top of each other.
	// 가장 기본적인 베이스 텍스처로 일단 입혀주고
    float4 texColor = c0;

	// 그 기본베이스로 혼합맵으로 순차적으로 블렌딩 시켜준다.
	// 이렇게 혼합맵을 색상맵의 알파성분으로 넣지않고 따로 분리해서 관리하는 이유는
	// 여러곳에서 재사용하기 위해서이다.
	// 또 혼합맵은 타일방식으로 적용하는 것이 아니라 지형 표면전체에 늘려서 입힌다.
    texColor = lerp(texColor, c1, t.r);
    texColor = lerp(texColor, c2, t.g);
    texColor = lerp(texColor, c3, t.b);
    texColor = lerp(texColor, c4, t.a);
 
	//
	// Lighting.
	//

	float4 litColor = texColor;
	if( gLightCount > 0  )
	{  
		// Start with a sum of zero. 
		float4 ambient = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 spec    = float4(0.0f, 0.0f, 0.0f, 0.0f);

		// Sum the light contribution from each light source.  
		[unroll]
		for(int i = 0; i < gLightCount; ++i)
		{
			float4 A, D, S;
			ComputeDirectionalLight(gMaterial, gDirLights[i], normalW, toEye, 
				A, D, S);

			ambient += A;
			diffuse += D;
			spec    += S;
		}

		litColor = texColor*(ambient + diffuse) + spec;
	}
 
	//
	// Fogging
	//

	if( gFogEnabled )
	{
		float fogLerp = saturate( (distToEye - gFogStart) / gFogRange ); 

		// Blend the fog color and the lit color.
		litColor = lerp(litColor, gFogColor, fogLerp);
	}

    return litColor;
}

technique11 Light1
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(1, false) ) );
    }
}

technique11 Light2
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(2, false) ) );
    }
}

technique11 Light3
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(3, false) ) );
    }
}

technique11 Light1Fog
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(1, true) ) );
    }
}

technique11 Light2Fog
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(2, true) ) );
    }
}

technique11 Light3Fog
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(3, true) ) );
    }
}
