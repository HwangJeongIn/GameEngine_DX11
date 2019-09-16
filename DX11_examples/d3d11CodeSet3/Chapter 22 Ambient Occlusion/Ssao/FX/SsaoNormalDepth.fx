//=============================================================================
// SsaoNormalsDepth.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Renders view space normals and depth to render target.
//=============================================================================
 
cbuffer cbPerObject
{
	float4x4 gWorldView;
	float4x4 gWorldInvTransposeView;
	float4x4 gWorldViewProj;
	float4x4 gTexTransform;
}; 

// Nonnumeric values cannot be added to a cbuffer.
Texture2D gDiffuseMap;
 
SamplerState samLinear
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};

struct VertexIn
{
	float3 PosL    : POSITION;
	float3 NormalL : NORMAL;
	float2 Tex     : TEXCOORD;
};

struct VertexOut
{
	float4 PosH       : SV_POSITION;
    float3 PosV       : POSITION;
    float3 NormalV    : NORMAL;
	float2 Tex        : TEXCOORD0;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Transform to view space.
	// 일단 뷰스페이스로 바꾼다.
	vout.PosV    = mul(float4(vin.PosL, 1.0f), gWorldView).xyz;

	// 노말도 뷰스페이스 기준으로 계산해준다.
	vout.NormalV = mul(vin.NormalL, (float3x3)gWorldInvTransposeView);
		
	// Transform to homogeneous clip space.
	// 동차 절단공간에 대한 점도 계산해준다.
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj);
	
	// Output vertex attributes for interpolation across triangle.
	vout.Tex = mul(float4(vin.Tex, 0.0f, 1.0f), gTexTransform).xy;

	// 법선 깊이 렌더타겟으로 잡고 했는데, 최종적으로 씬에 있는 가장 가까운 노말과 깊이값이 텍스처에 입력이 될것이다.
 
	return vout;
}
 
float4 PS(VertexOut pin, uniform bool gAlphaClip) : SV_Target
{
	// Interpolating normal can unnormalize it, so normalize it.
	// 보간과정에서 정규벡터가 아닐수도 있기 때문에 정규화시켜준다.
    pin.NormalV = normalize(pin.NormalV);

	if(gAlphaClip)
	{
		float4 texColor = gDiffuseMap.Sample( samLinear, pin.Tex );
		 
		clip(texColor.a - 0.1f);
	}
	
	
	// 추측 : 동차나누기는 하드웨어에서 알아서 해주는데 아마 SV_POSITION 지정해둔 곳에서 해줄듯

	// 최종 뷰스페이스에서의 노말과 z값을 넣어준다.
	// 이렇게 텍스처 픽셀 하나하나에 뷰스페이스의 노말값과 깊이값이 들어간다.
	return float4(pin.NormalV, pin.PosV.z);
}

technique11 NormalDepth
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(false) ) );
    }
}

technique11 NormalDepthAlphaClip
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS(true) ) );
    }
}
