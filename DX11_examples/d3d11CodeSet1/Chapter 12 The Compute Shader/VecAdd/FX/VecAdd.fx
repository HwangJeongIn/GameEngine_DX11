//=============================================================================
// VecAdd.fx by Frank Luna (C) 2011 All Rights Reserved.
//=============================================================================

struct Data
{
	float3 v1;
	float2 v2;
};

// ������ ���� // ���� ������ ���ҵ��� ��� ����
// ��������� ������ ���ۿ� ����ϳ� �÷��������� / ������ ������ ����Ʈ ����ũ�⸦ �����ؾ��Ѵ�.
StructuredBuffer<Data> gInputA;
StructuredBuffer<Data> gInputB;
RWStructuredBuffer<Data> gOutput;

// 1�������� ��� // 32������ 1�׷�
[numthreads(32, 1, 1)]
void CS(int3 dtid : SV_DispatchThreadID)
{
	// �ΰ��� �Է��� ���ؼ� ���� // �ΰ��� �Է¿� ���ؼ��� �������α׷� �������� �����Ǿ
	// ���̴��� �ö�´�.
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
