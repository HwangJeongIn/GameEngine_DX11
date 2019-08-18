//***************************************************************************************
// color.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Transforms and colors geometry.
//***************************************************************************************


// cbuffer == constant buffer
// 쉐이더가 접근할 수 있는 다양한 자료를 저장하는 유연한 자료블록
// 정점마다 바뀌는 것이 아니다.
// C++ 응용프로그램은 효과 프레임 워크를 통해서 상수 버퍼의 내용을 실행시점에서 변경할 수 있다.
// C++ 응용프로그램과 소통하는 수단이 된다.
// 한상수 버퍼를 갱신할때 그 상수 버퍼의 모든 변수를 갱신해야한다. 따라서 버퍼를 적절히 나눠준다.

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
	// VS라는 것은  system value를 뜻한다.
	// 이는 정점 쉐이더의 이 출력이 정점의위치를 담고 있음을 말해준다.
	// 정점 위치는 정점의 다른 특성들은 관여하지 않는 연산들(절단연산 등)에 쓰이기 때문에
	// 다른 특성들과는 다른 방식으로 처리 해야한다.
	float4 PosH  : SV_POSITION;
    float4 Color : COLOR;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;
	
	// Transform to homogeneous clip space.
	// 동차 절단 공간으로 변환한다. // 동차 절단 공간 : 투영행렬까지 적용(원근 나누기 전)
	// 원근 나누기는 나중에 하드웨어가 수행한다.
	// 기하쉐이더를 사용하지 않는 이상 정점쉐이더에서 투영변환를 반드시 수행해야한다.

	// float4(vin.PosL, 1.0f) == {vin.PosL.x, vin.PosL.y, vin.PosL.z, 1.0f}
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj);
	
	// Just pass vertex color into the pixel shader.
	// 색상값은 그냥 넘겨준다.
    vout.Color = vin.Color;
    
    return vout;
}

// 기능은 픽셀 단편의 색상을 계산해 내는 것이다.
// 픽셀 단편은 도중에 기각되어서 후면버퍼까지 도달하지 못할 수도 있다. 
// 픽셀셰이더에서 clip / 깊이값에 의한 가려짐 / 스텐실 판정과 같은 이후 파이프라인에 의해서
// 정점쉐이더의 출력과 픽셀쉐이더의 입력이 정확히 일치해야한다.
// SV_Target는 이 함수의 반환값 형식이 렌더 대상형식과 일치해야 한다는 뜻
float4 PS(VertexOut pin) : SV_Target
{
    return pin.Color;
}

// 렌더상태도 지정가능하다.
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
