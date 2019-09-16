//=============================================================================
// Ssao.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Computes SSAO map.
//=============================================================================

cbuffer cbPerFrame
{
	float4x4 gViewToTexSpace; // Proj*Texture
	float4   gOffsetVectors[14];
	float4   gFrustumCorners[4];

	// Coordinates given in view space.
	float    gOcclusionRadius    = 0.5f;
	float    gOcclusionFadeStart = 0.2f;
	float    gOcclusionFadeEnd   = 2.0f;
	float    gSurfaceEpsilon     = 0.05f;
};
 
// Nonnumeric values cannot be added to a cbuffer.
Texture2D gNormalDepthMap;
Texture2D gRandomVecMap;
 
SamplerState samNormalDepth
{
	Filter = MIN_MAG_LINEAR_MIP_POINT;

	// Set a very far depth value if sampling outside of the NormalDepth map
	// so we do not get false occlusions.
	AddressU = BORDER;
	AddressV = BORDER;
	BorderColor = float4(0.0f, 0.0f, 0.0f, 1e5f);
};

SamplerState samRandomVec
{
	Filter = MIN_MAG_LINEAR_MIP_POINT;
	AddressU  = WRAP;
    AddressV  = WRAP;
};

struct VertexIn
{
	float3 PosL            : POSITION;
	float3 ToFarPlaneIndex : NORMAL;
	float2 Tex             : TEXCOORD;
};

struct VertexOut
{
    float4 PosH       : SV_POSITION;
    float3 ToFarPlane : TEXCOORD0;
	float2 Tex        : TEXCOORD1;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Already in NDC space.
	// 이미 ndc공간 안에 있다. // 가장면평면
	vout.PosH = float4(vin.PosL, 1.0f);

	// We store the index to the frustum corner in the normal x-coord slot.
	// 실제 뷰스페이스에서의 먼평면에 대한 꼭짓점이다. // 너비 높이 깊이 다 NDC가 아님
	// 절대체의 모서리 인덱스를 노말의 x슬롯에 넣는다.
	// 이는 꼭짓점 벡터이다. 
	// 픽셀쉐이더에서는 각 픽셀에 대해서 보간되어 시점에서 먼 면에 대한 각 방향벡터를 구할 수 있다.
	vout.ToFarPlane = gFrustumCorners[vin.ToFarPlaneIndex.x].xyz;

	// Pass onto pixel shader.
	// 텍스처 좌표는 그대로 픽셀 쉐이더로 넘겨준다.
	vout.Tex = vin.Tex;
	
    return vout;
}

// Determines how much the sample point q occludes the point p as a function
// of distZ.
float OcclusionFunction(float distZ)
{
	//
	// If depth(q) is "behind" depth(p), then q cannot occlude p.  Moreover, if 
	// depth(q) and depth(p) are sufficiently close, then we also assume q cannot
	// occlude p because q needs to be in front of p by Epsilon to occlude p.
	//
	// We use the following function to determine the occlusion.  
	// 
	//
	//       1.0     -------------\
	//               |           |  \
	//               |           |    \
	//               |           |      \ 
	//               |           |        \
	//               |           |          \
	//               |           |            \
	//  ------|------|-----------|-------------|---------|--> zv
	//        0     Eps          z0            z1        
	//

	// 만약에 q의 깊이값이 p보다 크다면 가리지 못하는 것이고 / 만약 엄청가깝다고 해도 가리지 못한다. 
	// epsilon만큼 앞에 있어야 한다.

	
	float occlusion = 0.0f;
	// 엡실론 보다 클때 처리
	if(distZ > gSurfaceEpsilon)
	{
		// 흐리기 길이 측정
		float fadeLength = gOcclusionFadeEnd - gOcclusionFadeStart;
		
		// Linearly decrease occlusion from 1 to 0 as distZ goes 
		// from gOcclusionFadeStart to gOcclusionFadeEnd.

		// 선형적인 차폐감소[1,0]는 start ~ end 로부터 계산된다.
		occlusion = saturate( (gOcclusionFadeEnd-distZ)/fadeLength );
	}
	
	return occlusion;	
}

float4 PS(VertexOut pin, uniform int gSampleCount) : SV_Target
{
	/*
	1. 기존에 만들어 뒀던 노말 뎁스맵을 가지고 현재 시점에서 가장 가까운 z성분을 얻는다.
	
	2. 추출한 시야공간 z성분 pz와 보간된 먼 평면 꼭짓점까지의 벡터 v를 
	이용하여 현재 픽셀의 위치를 구한다. (px, py, pz) // 현재는 z값밖에 모른다.
	
	3. 먼 평면 꼭짓점 벡터v는 p를 통과한다 >> v = tp / 그런데  vz = t * pz이므로 / t = vz / pz

	.... 아래에 이어서 주석
	*/

	// 주변광 차폐를 하는 포인트
	// p -- the point we are computing the ambient occlusion for.
	
	// p에 대한 노멀벡터
	// n -- normal vector at p.
	
	// p에서 랜덤하게 떨어진 q // 레이중 하나
	// q -- a random offset from p.
	
	// p를 차폐할 수도 있는 잠재적인 차폐기
	// r -- a potential occluder that might occlude p.

	// Get viewspace normal and z-coord of this pixel.  The tex-coords for
	// the fullscreen quad we drew are already in uv-space.

	// 뷰스페이스에서의 노말값과 깊이 값이다. // r값
	float4 normalDepth = gNormalDepthMap.SampleLevel(samNormalDepth, pin.Tex, 0.0f);
 
	// 현재 픽셀에 대해서 뷰스페이스의 노말벡터는 텍셀의 xyz에 저장되어있다.
	float3 n = normalDepth.xyz;
	// 현재 픽셀에 대해서 뷰스페이스의 깊이값은 텍셀의 w에 저장되어 있다.
	float pz = normalDepth.w;

	//
	// Reconstruct full view space position (x,y,z).
	// Find t such that p = t*pin.ToFarPlane.
	// p.z = t*pin.ToFarPlane.z
	// t = p.z / pin.ToFarPlane.z
	//

	// 실제 p를 추출
	float3 p = (pz/pin.ToFarPlane.z)*pin.ToFarPlane;
	
	// Extract random vector and map from [0,1] --> [-1, +1].
	// 기존 만들었던 랜덤벡터들은 [0,1]이므로 [-1,1]로 변환해준다.
	float3 randVec = 2.0f*gRandomVecMap.SampleLevel(samRandomVec, 4.0f*pin.Tex, 0.0f).rgb - 1.0f;

	// 여기까지 하면 p주위의 무작위 표본점 q들이 마련되었다. 그런데 이들이 그냥 빈 공간에 있는점인지 
	// 빛을 가리는 고형물체에 속하는 점인지 모른다. // 법선 깊이 맵에서 깊이정보를 가지고 와야한다.


	float occlusionSum = 0.0f;
	
	// Sample neighboring points about p in the hemisphere oriented by n.
	[unroll]
	for(int i = 0; i < gSampleCount; ++i)
	{
		// Are offset vectors are fixed and uniformly distributed (so that our offset vectors
		// do not clump in the same direction).  If we reflect them about a random vector
		// then we get a random uniform distribution of offset vectors.

		// 오프셋 벡터는 고정되고 균일하게 분포되어있으므로 같은 방향으로 뭉치지 않음
		// 랜덤 벡터에 대해 그것들을 반영하면 오프셋 벡터의 임의의 균일한 분포를 얻음

		// 반사광을 얻을 때 사용 // 첫 번째 인자로 입사광의 방향벡터를 두 번째 인자로 반사면의 법선을 받음
		// reflect에 대해서 알아보면
		/*
		This function calculates the reflection vector using the following formula: v = i - 2 * n * dot(i n) .
		*/
		float3 offset = reflect(gOffsetVectors[i].xyz, randVec);
	
		// Flip offset vector if it is behind the plane defined by (p, n).
		// sign(x) : 부호에 따라 음수이면 -1, 0이면 0, 양수이면 1을 리턴 
		
		/*
		각도가 90도 이하 : 1
		각도가 90도 : 0
		각도가 90도 이상 : -1
		*/
		float flip = sign( dot(offset, n) );
		
		// Sample a point near p within the occlusion radius.
		// 만약에 각도가 90도이상(법선벡터 반구에 없으면) 뒤집힌다
		float3 q = p + flip * gOcclusionRadius * offset;
		
		// Project q and generate projective tex-coords. 
		// 기존 뷰공간 >(투영행렬)> 투영 >> 동차나누기 >(w로 나누기)> NDC공간[-1,1][-1,1][0,1] >(toTexture행렬)> 텍스처 공간 [0,1][0,1]
		float4 projQ = mul(float4(q, 1.0f), gViewToTexSpace);
		projQ /= projQ.w;

		// Find the nearest depth value along the ray from the eye to q (this is not
		// the depth of q, as q is just an arbitrary point near p and might
		// occupy empty space).  To find the nearest depth we look it up in the depthmap.

		// 현재 q에 대한 텍스처 공간으로 들어갔기 때문에 법선깊이맵에서 깊이값을 뽑아낼 수 있다.
		float rz = gNormalDepthMap.SampleLevel(samNormalDepth, projQ.xy, 0.0f).a;

		// Reconstruct full view space position r = (rx,ry,rz).  We know r
		// lies on the ray of q, so there exists a t such that r = t*q.
		// r.z = t*q.z ==> t = r.z / q.z

		// r과 q는 동일 선상에 있으므로 다음과 같은 공식이 성립한다.
		// r = t*q / r.z = t*q.z ==> t = r.z / q.z
		// 최종적인 r의 위치를 구해준다.
		float3 r = (rz / q.z) * q;
		
		//
		// Test whether r occludes p.
		//   * The product dot(n, normalize(r - p)) measures how much in front
		//     of the plane(p,n) the occluder point r is.  The more in front it is, the
		//     more occlusion weight we give it.  This also prevents self shadowing where 
		//     a point r on an angled plane (p,n) could give a false occlusion since they
		//     have different depth values with respect to the eye.
		//   * The weight of the occlusion is scaled based on how far the occluder is from
		//     the point we are computing the occlusion of.  If the occluder r is far away
		//     from p, then it does not occlude it.
		// 

		// 점 r이 p를 가리는 것에 대한 판정 
		/*
		1. dot(n, normalize(r - p))은 r이 얼마나 평면으로 부터 앞에있나 측정한다.
		더 앞에 있을 수록 더 차폐도를 크게 잡는다. 이는 직각인 평면에서 눈에 대한 깊이값이 다름으로인해서 잘못된 차폐 판정을 막아준다. 

		2. 차폐의 가중치는 우리가 차폐를 계산하려는 지점으로부터의 거리에 기반한다.
		만약 거리가 멀다면 차폐하지 않는다.

		*/
		
		float distZ = p.z - r.z;
		float dp = max(dot(n, normalize(r - p)), 0.0f);
		float occlusion = dp * OcclusionFunction(distZ);
		
		occlusionSum += occlusion;
	}
	
	occlusionSum /= gSampleCount;
	
	float access = 1.0f - occlusionSum;

	// Sharpen the contrast of the SSAO map to make the SSAO affect more dramatic.
	// 드라마틱한 효과를 주기 위해,  극명한 대조를 준다.
	return saturate(pow(access, 4.0f));
}

technique11 Ssao
{
    pass P0
    {
		SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(14) ) );
    }
}
 