//***************************************************************************************
// color.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Transforms and colors geometry.
//***************************************************************************************


// cbuffer == constant buffer
// ���̴��� ������ �� �ִ� �پ��� �ڷḦ �����ϴ� ������ �ڷ���
// �������� �ٲ�� ���� �ƴϴ�.
// C++ �������α׷��� ȿ�� ������ ��ũ�� ���ؼ� ��� ������ ������ ����������� ������ �� �ִ�.
// C++ �������α׷��� �����ϴ� ������ �ȴ�.
// �ѻ�� ���۸� �����Ҷ� �� ��� ������ ��� ������ �����ؾ��Ѵ�. ���� ���۸� ������ �����ش�.

cbuffer cbPerObject
{
	float4x4 gWorldViewProj; 
};

struct VertexIn
{
	float3 PosL  : POSITION;
    float4 Color : COLOR;
};

struct VertexOut
{
	// VS��� ����  system value�� ���Ѵ�.
	// �̴� ���� ���̴��� �� ����� ��������ġ�� ��� ������ �����ش�.
	// ���� ��ġ�� ������ �ٸ� Ư������ �������� �ʴ� �����(���ܿ��� ��)�� ���̱� ������
	// �ٸ� Ư������� �ٸ� ������� ó�� �ؾ��Ѵ�.
	float4 PosH  : SV_POSITION;
    float4 Color : COLOR;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Transform to homogeneous clip space.
	// ���� ���� �������� ��ȯ�Ѵ�. // ���� ���� ���� : ������ı��� ����(���� ������ ��)
	// ���� ������� ���߿� �ϵ��� �����Ѵ�.
	// ���Ͻ��̴��� ������� �ʴ� �̻� �������̴����� ������ȯ�� �ݵ�� �����ؾ��Ѵ�.

	// float4(vin.PosL, 1.0f) == {vin.PosL.x, vin.PosL.y, vin.PosL.z, 1.0f}
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj);
	
	// Just pass vertex color into the pixel shader.
	// ������ �׳� �Ѱ��ش�.
    vout.Color = vin.Color;
    
    return vout;
}

// ����� �ȼ� ������ ������ ����� ���� ���̴�.
// �ȼ� ������ ���߿� �Ⱒ�Ǿ �ĸ���۱��� �������� ���� ���� �ִ�. 
// �ȼ����̴����� clip / ���̰��� ���� ������ / ���ٽ� ������ ���� ���� ���������ο� ���ؼ�
// �������̴��� ��°� �ȼ����̴��� �Է��� ��Ȯ�� ��ġ�ؾ��Ѵ�.
// SV_Target�� �� �Լ��� ��ȯ�� ������ ���� ������İ� ��ġ�ؾ� �Ѵٴ� ��
float4 PS(VertexOut pin) : SV_Target
{
    return pin.Color;
}

// �������µ� ���������ϴ�.
RasterizerState WireframeRS
{
	FillMode = Wireframe;
	CullMode = Back;// Front;
	FrontCounterClockwise = false;
};

technique11 ColorTech
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS() ) );

		SetRasterizerState(WireframeRS);
    }
}
