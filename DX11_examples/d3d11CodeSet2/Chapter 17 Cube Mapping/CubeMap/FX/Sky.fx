//=============================================================================
// Sky.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Effect used to shade sky dome.
//=============================================================================

cbuffer cbPerFrame
{
	float4x4 gWorldViewProj;
};
 
// Nonnumeric values cannot be added to a cbuffer.
// 입방체 맵으로 받는다. // 이런 3D텍스처의 텍셀 값을 받아올 때는 조회벡터를 사용한다.
TextureCube gCubeMap;

SamplerState samTriLinearSam
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Wrap;
	AddressV = Wrap;
};

struct VertexIn
{
	float3 PosL : POSITION;
};

struct VertexOut
{
	float4 PosH : SV_POSITION;
    float3 PosL : POSITION;
};
 
VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Set z = w so that z/w = 1 (i.e., skydome always on far plane).
	// z/w = 1 이 되어야 한다.
	/*
	이렇게 해야하는 이유는 투영행렬까지 적용했을때 기존 z값이 w로 들어가는데 이값으로 변환된 z값을 나눴을때 0~1이 나오게 된다.
	그렇기 때문에 가장 먼 절두체평면으로 설정하기 위해서 z/w = 1이 나오게 해준다. // z = w // xyww반환
	이렇게되면 항상 가장 멀리 존재 아무리 멀리가도 절두체에 의해서 컬링되는 경우는 없다
	그리고 항상 맨뒤에 있다는게 보장된다.
	단 스카이 돔을 멀리서 보게되면 앞면과 뒷면이 경쟁하게 되어서 줄무늬가 생긴다.
	*/
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj).xyww;
	
	// Use local vertex position as cubemap lookup vector.
	// 로컬 정점 위치는 조회벡터이다. // 그 이유는 로컬에서는 원점이 돔의 원점이다.
	vout.PosL = vin.PosL;
	
	return vout;
}

float4 PS(VertexOut pin) : SV_Target
{
	// 조회벡터를 이용해서 큐브맵을 추출한다.
	return gCubeMap.Sample(samTriLinearSam, pin.PosL);
}

RasterizerState NoCull
{
    CullMode = None;
};

DepthStencilState LessEqualDSS
{
	// Make sure the depth function is LESS_EQUAL and not just LESS.  
	// Otherwise, the normalized depth values at z = 1 (NDC) will 
	// fail the depth test if the depth buffer was cleared to 1.
	// 환경맵 자체가 1의 깊이를 가지기 때문에 1도 포함해서 렌더링 해야한다.
    DepthFunc = LESS_EQUAL;
};

technique11 SkyTech
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS() ) );
        
        SetRasterizerState(NoCull);
        SetDepthStencilState(LessEqualDSS, 0);
    }
}
