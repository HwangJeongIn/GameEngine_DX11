//=============================================================================
// VecAdd.fx by Frank Luna (C) 2011 All Rights Reserved.
//=============================================================================

struct Data
{
	float3 v1;
	float2 v2;
};

// 구조적 버퍼 // 같은 형식의 원소들을 담는 버퍼
// 생성방식은 보통의 버퍼와 비슷하나 플래그지정과 / 저장할 원소의 바이트 단위크기를 지정해야한다.
StructuredBuffer<Data> gInputA;
StructuredBuffer<Data> gInputB;
RWStructuredBuffer<Data> gOutput;

// 1차원으로 사용 // 32스레드 1그룹
[numthreads(32, 1, 1)]
void CS(int3 dtid : SV_DispatchThreadID)
{
	// 두개의 입력을 더해서 설정 // 두개의 입력에 대해서는 응용프로그램 레벨에서 설정되어서
	// 쉐이더로 올라온다.
	gOutput[dtid.x].v1 = gInputA[dtid.x].v1 + gInputB[dtid.x].v1;
	gOutput[dtid.x].v2 = gInputA[dtid.x].v2 + gInputB[dtid.x].v2;
}

technique11 VecAdd
{
    pass P0
    {
		SetVertexShader( NULL );
        SetPixelShader( NULL );
		SetComputeShader( CompileShader( cs_5_0, CS() ) );
    }
}
