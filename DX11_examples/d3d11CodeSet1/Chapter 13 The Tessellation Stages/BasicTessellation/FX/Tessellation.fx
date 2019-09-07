 
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
 
// 상수 덮개 쉐이더 constant hull shader는 항상 테셀레이션 계수들을 출력해야한다.
struct PatchTess
{
	// 각변에 대한 세분정도를 제어하는 테셀레이션 계수
	float EdgeTess[4]   : SV_TessFactor;
	// 사각형 패치 내부의 세분 정도를 제어하는 테셀레이션 계수
	float InsideTess[2] : SV_InsideTessFactor;
};

// 상수 덮개 쉐이더
PatchTess ConstantHS(
	// 정점쉐이더를 가쳐온 정점과 한 패치당 몇개의 제어점을 가지고 있는지
	InputPatch<VertexOut, 4> patch,
	// 패치의 아이디
	uint patchID : SV_PrimitiveID )
{
	PatchTess pt;
	
	// 패치 공간에서 패치의 중점을 구한다.
	float3 centerL = 0.25f*(patch[0].PosL + patch[1].PosL + patch[2].PosL + patch[3].PosL);
	// 월드 공간으로 변환한다.
	float3 centerW = mul(float4(centerL, 1.0f), gWorld).xyz;
	
	// 눈과 거리를 따진다.
	float d = distance(centerW, gEyePosW);

	// Tessellate the patch based on distance from the eye such that
	// the tessellation is 0 if d >= d1 and 60 if d <= d0.  The interval
	// [d0, d1] defines the range we tessellate in.
	
	const float d0 = 20.0f;
	const float d1 = 100.0f;


	// 눈과의 거리에 따라서 패치를 테셀레이션 한다. 만약 d >= d1이면 // 제일 멀때
	// 테셀레이션 계수를 0으로 하고 d <= d0이면 64로 한다. // 제일 가까울때
	float tess = 64.0f*saturate((d1 - d) / (d1 - d0)) + 1.0f; // 1이면 그대로 렌더링

	// Uniformly tessellate the patch.
	// 패치를 균일하게 테셀레이트
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


// pass through 형식으로 그래로 통과하도록 설정하였다.
// 제어점 수정없이 그대로 넘겨주는 제어점 덮개 쉐이더

// 패치의 종류 유효 : tri, quad, isoline // 영역 / 범위  
[domain("quad")]

// 테셀레이션 세분 모드 지정 : integer(새 정점들이 정수 테셀레이션 계수 값들에서만 추가 / 제거 소수 무시)
// fractional_even / fractional_odd : 분수 테셀레이션에 해당하는 것으로 새정점들이 정수 테셀레이션 계수 값에 따라서 추가 제거
// 그러나 테셀레이션 계수의 분수에 따라서 점진적으로 진입 // 매끄럽게 전이가능
[partitioning("integer")]

// 세분에 의해 만들어진 삼각형들의 정점 감김 순서
[outputtopology("triangle_cw")]

// hull shader가 출력할 제어점의 수 / 이는 곧 하나의 입력 패치에 대한 제어점 덮개 쉐이더 실행횟수
// SV_OutputControlPointID 은 현재 제어점 덮개 쉐이더가 다루고 있는 출력 제어점을 식별하는 색인 제공
[outputcontrolpoints(4)]

// 상수 덮개 쉐이더로 쓰일 함수의 이름
[patchconstantfunc("ConstantHS")]

// 쉐이더가 사용할 테셀레이션 계수의 최댓값을 구동기에게 귀띔
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
// 테셀레이션 단계가 있는 경우 기존 정점쉐이더는 컨트롤 포인트에 대한 정점쉐이더로 작용하고
// 도메인 쉐이더가 실질적으로 테셀레이션 과정을 거진 버텍스들의 버텍스 쉐이더가 된다.
// 이곳에서 정점들을 동차 절단 공간으로 변환한다.

// 테셀레이션 이후에 실행되는 정점 쉐이더
[domain("quad")]
DomainOut DS(PatchTess patchTess, 
			 // 패치 영역안에서의 좌표
             float2 uv : SV_DomainLocation, 
             const OutputPatch<HullOut, 4> quad)
{
	DomainOut dout;
	
	// Bilinear interpolation.
	// 이중 선형 보간법 사용
	// 먼저 x(0~1사이 factor)에 대해서 두가지 값을 구해주고
	// 그값을 가지고 최종적으로 y를 이용해서 위치를 정해준다.
	float3 v1 = lerp(quad[0].PosL, quad[1].PosL, uv.x); 
	float3 v2 = lerp(quad[2].PosL, quad[3].PosL, uv.x); 
	float3 p  = lerp(v1, v2, uv.y); 
	
	// Displacement mapping
	// 변위 매핑 // 이로인해 언덕같은 지형이 만들어진다.
	p.y = 0.3f*( p.z*sin(p.x) + p.x*cos(p.z) );
	
	// 동차 절단 공간
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
