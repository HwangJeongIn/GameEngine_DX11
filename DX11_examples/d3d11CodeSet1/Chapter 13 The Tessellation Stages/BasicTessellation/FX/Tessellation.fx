 
#include "LightHelper.fx"
 
cbuffer cbPerFrame
{
	DirectionalLight gDirLights[3];
	float3 gEyePosW;

	float  gFogStart;
	float  gFogRange;
	float4 gFogColor;
};

cbuffer cbPerObject
{
	float4x4 gWorld;
	float4x4 gWorldInvTranspose;
	float4x4 gWorldViewProj;
	float4x4 gTexTransform;
	Material gMaterial;
};

// Nonnumeric values cannot be added to a cbuffer.
Texture2D gDiffuseMap;

SamplerState samAnisotropic
{
	Filter = ANISOTROPIC;
	MaxAnisotropy = 4;

	AddressU = WRAP;
	AddressV = WRAP;
};

struct VertexIn
{
	float3 PosL    : POSITION;
};

struct VertexOut
{
	float3 PosL    : POSITION;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	vout.PosL = vin.PosL;

	return vout;
}
 
// ��� ���� ���̴� constant hull shader�� �׻� �׼����̼� ������� ����ؾ��Ѵ�.
struct PatchTess
{
	// ������ ���� ���������� �����ϴ� �׼����̼� ���
	float EdgeTess[4]   : SV_TessFactor;
	// �簢�� ��ġ ������ ���� ������ �����ϴ� �׼����̼� ���
	float InsideTess[2] : SV_InsideTessFactor;
};

// ��� ���� ���̴�
PatchTess ConstantHS(
	// �������̴��� ���Ŀ� ������ �� ��ġ�� ��� �������� ������ �ִ���
	InputPatch<VertexOut, 4> patch,
	// ��ġ�� ���̵�
	uint patchID : SV_PrimitiveID )
{
	PatchTess pt;
	
	// ��ġ �������� ��ġ�� ������ ���Ѵ�.
	float3 centerL = 0.25f*(patch[0].PosL + patch[1].PosL + patch[2].PosL + patch[3].PosL);
	// ���� �������� ��ȯ�Ѵ�.
	float3 centerW = mul(float4(centerL, 1.0f), gWorld).xyz;
	
	// ���� �Ÿ��� ������.
	float d = distance(centerW, gEyePosW);

	// Tessellate the patch based on distance from the eye such that
	// the tessellation is 0 if d >= d1 and 60 if d <= d0.  The interval
	// [d0, d1] defines the range we tessellate in.
	
	const float d0 = 20.0f;
	const float d1 = 100.0f;


	// ������ �Ÿ��� ���� ��ġ�� �׼����̼� �Ѵ�. ���� d >= d1�̸� // ���� �ֶ�
	// �׼����̼� ����� 0���� �ϰ� d <= d0�̸� 64�� �Ѵ�. // ���� ����ﶧ
	float tess = 64.0f*saturate((d1 - d) / (d1 - d0)) + 1.0f; // 1�̸� �״�� ������

	// Uniformly tessellate the patch.
	// ��ġ�� �����ϰ� �׼�����Ʈ
	pt.EdgeTess[0] = tess;
	pt.EdgeTess[1] = tess;
	pt.EdgeTess[2] = tess;
	pt.EdgeTess[3] = tess;
	
	pt.InsideTess[0] = tess;
	pt.InsideTess[1] = tess;
	
	return pt;
}

struct HullOut
{
	float3 PosL : POSITION;
};


// pass through �������� �׷��� ����ϵ��� �����Ͽ���.
// ������ �������� �״�� �Ѱ��ִ� ������ ���� ���̴�

// ��ġ�� ���� ��ȿ : tri, quad, isoline // ���� / ����  
[domain("quad")]

// �׼����̼� ���� ��� ���� : integer(�� �������� ���� �׼����̼� ��� ���鿡���� �߰� / ���� �Ҽ� ����)
// fractional_even / fractional_odd : �м� �׼����̼ǿ� �ش��ϴ� ������ ���������� ���� �׼����̼� ��� ���� ���� �߰� ����
// �׷��� �׼����̼� ����� �м��� ���� ���������� ���� // �Ų����� ���̰���
[partitioning("integer")]

// ���п� ���� ������� �ﰢ������ ���� ���� ����
[outputtopology("triangle_cw")]

// hull shader�� ����� �������� �� / �̴� �� �ϳ��� �Է� ��ġ�� ���� ������ ���� ���̴� ����Ƚ��
// SV_OutputControlPointID �� ���� ������ ���� ���̴��� �ٷ�� �ִ� ��� �������� �ĺ��ϴ� ���� ����
[outputcontrolpoints(4)]

// ��� ���� ���̴��� ���� �Լ��� �̸�
[patchconstantfunc("ConstantHS")]

// ���̴��� ����� �׼����̼� ����� �ִ��� �����⿡�� �Ͷ�
[maxtessfactor(64.0f)]
HullOut HS(InputPatch<VertexOut, 4> p, 
           uint i : SV_OutputControlPointID,
           uint patchId : SV_PrimitiveID)
{
	HullOut hout;
	
	hout.PosL = p[i].PosL;
	
	return hout;
}

struct DomainOut
{
	float4 PosH : SV_POSITION;
};

// The domain shader is called for every vertex created by the tessellator.  
// It is like the vertex shader after tessellation.
// �׼����̼� �ܰ谡 �ִ� ��� ���� �������̴��� ��Ʈ�� ����Ʈ�� ���� �������̴��� �ۿ��ϰ�
// ������ ���̴��� ���������� �׼����̼� ������ ���� ���ؽ����� ���ؽ� ���̴��� �ȴ�.
// �̰����� �������� ���� ���� �������� ��ȯ�Ѵ�.

// �׼����̼� ���Ŀ� ����Ǵ� ���� ���̴�
[domain("quad")]
DomainOut DS(PatchTess patchTess, 
			 // ��ġ �����ȿ����� ��ǥ
             float2 uv : SV_DomainLocation, 
             const OutputPatch<HullOut, 4> quad)
{
	DomainOut dout;
	
	// Bilinear interpolation.
	// ���� ���� ������ ���
	// ���� x(0~1���� factor)�� ���ؼ� �ΰ��� ���� �����ְ�
	// �װ��� ������ ���������� y�� �̿��ؼ� ��ġ�� �����ش�.
	float3 v1 = lerp(quad[0].PosL, quad[1].PosL, uv.x); 
	float3 v2 = lerp(quad[2].PosL, quad[3].PosL, uv.x); 
	float3 p  = lerp(v1, v2, uv.y); 
	
	// Displacement mapping
	// ���� ���� // �̷����� ������� ������ ���������.
	p.y = 0.3f*( p.z*sin(p.x) + p.x*cos(p.z) );
	
	// ���� ���� ����
	dout.PosH = mul(float4(p, 1.0f), gWorldViewProj);
	
	return dout;
}

float4 PS(DomainOut pin) : SV_Target
{
    return float4(1.0f, 1.0f, 1.0f, 1.0f);
}

technique11 Tess
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetHullShader( CompileShader( hs_5_0, HS() ) );
        SetDomainShader( CompileShader( ds_5_0, DS() ) );
        SetPixelShader( CompileShader( ps_5_0, PS() ) );
    }
}
