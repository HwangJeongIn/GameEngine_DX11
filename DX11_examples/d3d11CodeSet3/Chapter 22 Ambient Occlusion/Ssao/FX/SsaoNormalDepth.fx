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
	// �ϴ� �佺���̽��� �ٲ۴�.
	vout.PosV    = mul(float4(vin.PosL, 1.0f), gWorldView).xyz;

	// �븻�� �佺���̽� �������� ������ش�.
	vout.NormalV = mul(vin.NormalL, (float3x3)gWorldInvTransposeView);
		
	// Transform to homogeneous clip space.
	// ���� ���ܰ����� ���� ���� ������ش�.
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj);
	
	// Output vertex attributes for interpolation across triangle.
	vout.Tex = mul(float4(vin.Tex, 0.0f, 1.0f), gTexTransform).xy;

	// ���� ���� ����Ÿ������ ��� �ߴµ�, ���������� ���� �ִ� ���� ����� �븻�� ���̰��� �ؽ�ó�� �Է��� �ɰ��̴�.
 
	return vout;
}
 
float4 PS(VertexOut pin, uniform bool gAlphaClip) : SV_Target
{
	// Interpolating normal can unnormalize it, so normalize it.
	// ������������ ���Ժ��Ͱ� �ƴҼ��� �ֱ� ������ ����ȭ�����ش�.
    pin.NormalV = normalize(pin.NormalV);

	if(gAlphaClip)
	{
		float4 texColor = gDiffuseMap.Sample( samLinear, pin.Tex );
		 
		clip(texColor.a - 0.1f);
	}
	
	
	// ���� : ����������� �ϵ����� �˾Ƽ� ���ִµ� �Ƹ� SV_POSITION �����ص� ������ ���ٵ�

	// ���� �佺���̽������� �븻�� z���� �־��ش�.
	// �̷��� �ؽ�ó �ȼ� �ϳ��ϳ��� �佺���̽��� �븻���� ���̰��� ����.
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
