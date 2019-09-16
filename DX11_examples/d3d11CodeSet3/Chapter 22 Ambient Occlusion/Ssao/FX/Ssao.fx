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
	// �̹� ndc���� �ȿ� �ִ�. // ��������
	vout.PosH = float4(vin.PosL, 1.0f);

	// We store the index to the frustum corner in the normal x-coord slot.
	// ���� �佺���̽������� ����鿡 ���� �������̴�. // �ʺ� ���� ���� �� NDC�� �ƴ�
	// ����ü�� �𼭸� �ε����� �븻�� x���Կ� �ִ´�.
	// �̴� ������ �����̴�. 
	// �ȼ����̴������� �� �ȼ��� ���ؼ� �����Ǿ� �������� �� �鿡 ���� �� ���⺤�͸� ���� �� �ִ�.
	vout.ToFarPlane = gFrustumCorners[vin.ToFarPlaneIndex.x].xyz;

	// Pass onto pixel shader.
	// �ؽ�ó ��ǥ�� �״�� �ȼ� ���̴��� �Ѱ��ش�.
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

	// ���࿡ q�� ���̰��� p���� ũ�ٸ� ������ ���ϴ� ���̰� / ���� ��û�����ٰ� �ص� ������ ���Ѵ�. 
	// epsilon��ŭ �տ� �־�� �Ѵ�.

	
	float occlusion = 0.0f;
	// ���Ƿ� ���� Ŭ�� ó��
	if(distZ > gSurfaceEpsilon)
	{
		// �帮�� ���� ����
		float fadeLength = gOcclusionFadeEnd - gOcclusionFadeStart;
		
		// Linearly decrease occlusion from 1 to 0 as distZ goes 
		// from gOcclusionFadeStart to gOcclusionFadeEnd.

		// �������� ���󰨼�[1,0]�� start ~ end �κ��� ���ȴ�.
		occlusion = saturate( (gOcclusionFadeEnd-distZ)/fadeLength );
	}
	
	return occlusion;	
}

float4 PS(VertexOut pin, uniform int gSampleCount) : SV_Target
{
	/*
	1. ������ ����� �״� �븻 �������� ������ ���� �������� ���� ����� z������ ��´�.
	
	2. ������ �þ߰��� z���� pz�� ������ �� ��� ������������ ���� v�� 
	�̿��Ͽ� ���� �ȼ��� ��ġ�� ���Ѵ�. (px, py, pz) // ����� z���ۿ� �𸥴�.
	
	3. �� ��� ������ ����v�� p�� ����Ѵ� >> v = tp / �׷���  vz = t * pz�̹Ƿ� / t = vz / pz

	.... �Ʒ��� �̾ �ּ�
	*/

	// �ֺ��� ���� �ϴ� ����Ʈ
	// p -- the point we are computing the ambient occlusion for.
	
	// p�� ���� ��ֺ���
	// n -- normal vector at p.
	
	// p���� �����ϰ� ������ q // ������ �ϳ�
	// q -- a random offset from p.
	
	// p�� ������ ���� �ִ� �������� �����
	// r -- a potential occluder that might occlude p.

	// Get viewspace normal and z-coord of this pixel.  The tex-coords for
	// the fullscreen quad we drew are already in uv-space.

	// �佺���̽������� �븻���� ���� ���̴�. // r��
	float4 normalDepth = gNormalDepthMap.SampleLevel(samNormalDepth, pin.Tex, 0.0f);
 
	// ���� �ȼ��� ���ؼ� �佺���̽��� �븻���ʹ� �ؼ��� xyz�� ����Ǿ��ִ�.
	float3 n = normalDepth.xyz;
	// ���� �ȼ��� ���ؼ� �佺���̽��� ���̰��� �ؼ��� w�� ����Ǿ� �ִ�.
	float pz = normalDepth.w;

	//
	// Reconstruct full view space position (x,y,z).
	// Find t such that p = t*pin.ToFarPlane.
	// p.z = t*pin.ToFarPlane.z
	// t = p.z / pin.ToFarPlane.z
	//

	// ���� p�� ����
	float3 p = (pz/pin.ToFarPlane.z)*pin.ToFarPlane;
	
	// Extract random vector and map from [0,1] --> [-1, +1].
	// ���� ������� �������͵��� [0,1]�̹Ƿ� [-1,1]�� ��ȯ���ش�.
	float3 randVec = 2.0f*gRandomVecMap.SampleLevel(samRandomVec, 4.0f*pin.Tex, 0.0f).rgb - 1.0f;

	// ������� �ϸ� p������ ������ ǥ���� q���� ���õǾ���. �׷��� �̵��� �׳� �� ������ �ִ������� 
	// ���� ������ ������ü�� ���ϴ� ������ �𸥴�. // ���� ���� �ʿ��� ���������� ������ �;��Ѵ�.


	float occlusionSum = 0.0f;
	
	// Sample neighboring points about p in the hemisphere oriented by n.
	[unroll]
	for(int i = 0; i < gSampleCount; ++i)
	{
		// Are offset vectors are fixed and uniformly distributed (so that our offset vectors
		// do not clump in the same direction).  If we reflect them about a random vector
		// then we get a random uniform distribution of offset vectors.

		// ������ ���ʹ� �����ǰ� �����ϰ� �����Ǿ������Ƿ� ���� �������� ��ġ�� ����
		// ���� ���Ϳ� ���� �װ͵��� �ݿ��ϸ� ������ ������ ������ ������ ������ ����

		// �ݻ籤�� ���� �� ��� // ù ��° ���ڷ� �Ի籤�� ���⺤�͸� �� ��° ���ڷ� �ݻ���� ������ ����
		// reflect�� ���ؼ� �˾ƺ���
		/*
		This function calculates the reflection vector using the following formula: v = i - 2 * n * dot(i n) .
		*/
		float3 offset = reflect(gOffsetVectors[i].xyz, randVec);
	
		// Flip offset vector if it is behind the plane defined by (p, n).
		// sign(x) : ��ȣ�� ���� �����̸� -1, 0�̸� 0, ����̸� 1�� ���� 
		
		/*
		������ 90�� ���� : 1
		������ 90�� : 0
		������ 90�� �̻� : -1
		*/
		float flip = sign( dot(offset, n) );
		
		// Sample a point near p within the occlusion radius.
		// ���࿡ ������ 90���̻�(�������� �ݱ��� ������) ��������
		float3 q = p + flip * gOcclusionRadius * offset;
		
		// Project q and generate projective tex-coords. 
		// ���� ����� >(�������)> ���� >> ���������� >(w�� ������)> NDC����[-1,1][-1,1][0,1] >(toTexture���)> �ؽ�ó ���� [0,1][0,1]
		float4 projQ = mul(float4(q, 1.0f), gViewToTexSpace);
		projQ /= projQ.w;

		// Find the nearest depth value along the ray from the eye to q (this is not
		// the depth of q, as q is just an arbitrary point near p and might
		// occupy empty space).  To find the nearest depth we look it up in the depthmap.

		// ���� q�� ���� �ؽ�ó �������� ���� ������ �������̸ʿ��� ���̰��� �̾Ƴ� �� �ִ�.
		float rz = gNormalDepthMap.SampleLevel(samNormalDepth, projQ.xy, 0.0f).a;

		// Reconstruct full view space position r = (rx,ry,rz).  We know r
		// lies on the ray of q, so there exists a t such that r = t*q.
		// r.z = t*q.z ==> t = r.z / q.z

		// r�� q�� ���� ���� �����Ƿ� ������ ���� ������ �����Ѵ�.
		// r = t*q / r.z = t*q.z ==> t = r.z / q.z
		// �������� r�� ��ġ�� �����ش�.
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

		// �� r�� p�� ������ �Ϳ� ���� ���� 
		/*
		1. dot(n, normalize(r - p))�� r�� �󸶳� ������� ���� �տ��ֳ� �����Ѵ�.
		�� �տ� ���� ���� �� ���󵵸� ũ�� ��´�. �̴� ������ ��鿡�� ���� ���� ���̰��� �ٸ��������ؼ� �߸��� ���� ������ �����ش�. 

		2. ������ ����ġ�� �츮�� ���� ����Ϸ��� �������κ����� �Ÿ��� ����Ѵ�.
		���� �Ÿ��� �ִٸ� �������� �ʴ´�.

		*/
		
		float distZ = p.z - r.z;
		float dp = max(dot(n, normalize(r - p)), 0.0f);
		float occlusion = dp * OcclusionFunction(distZ);
		
		occlusionSum += occlusion;
	}
	
	occlusionSum /= gSampleCount;
	
	float access = 1.0f - occlusionSum;

	// Sharpen the contrast of the SSAO map to make the SSAO affect more dramatic.
	// ���ƽ�� ȿ���� �ֱ� ����,  �ظ��� ������ �ش�.
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
 