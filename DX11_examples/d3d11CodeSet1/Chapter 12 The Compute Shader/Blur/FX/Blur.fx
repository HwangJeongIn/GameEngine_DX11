//=============================================================================
// Blur.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Performs a separable blur with a blur radius of 5.  
//=============================================================================

cbuffer cbSettings
{
	// �̸� ���н��� ���� ����ġ�� ����� �ξ���.
	float gWeights[11] = 
	{
		0.05f, 0.05f, 0.1f, 0.1f, 0.1f, 0.2f, 0.1f, 0.1f, 0.1f, 0.05f, 0.05f,
	};
};

cbuffer cbFixed
{
	static const int gBlurRadius = 5;
};

// �����ڷ�� ���

// �Է��� �б� ����
Texture2D gInput;
// ����� �а� ����� �����Ѵ� RW = read / write
// ���� ���ڴ� ������ �ǹ��Ѵ� 4 = 4����
RWTexture2D<float4> gOutput;

// ������ �׷�� 256���� �����带 ������ �Ͽ���.
#define N 256
// ������ �׷�� �����ϴ� �޸��� ������� 256�� ���� �������� �ֺ� �ȼ����� ���ļ� 256 + �帲 ������ * 2 �̴�.
#define CacheSize (N + 2*gBlurRadius)
groupshared float4 gCache[CacheSize];

// ������ �׷� �ϳ��� ������ ������ ���� / �� �׷��� ��������� 1 2 3���� ������������ ǥ������
[numthreads(N, 1, 1)]
// ������ �ĺ��� ���� �Ű�����
void HorzBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	//
	// Fill local thread storage to reduce bandwidth.  To blur 
	// N pixels, we will need to load N + 2*BlurRadius pixels
	// due to the blur radius.
	//
	
	// This thread group runs N threads.  To get the extra 2*BlurRadius pixels, 
	// have 2*BlurRadius threads sample an extra pixel.
	// N���� �����忡�� ������ 2*�帲������ �ȼ��� ��� ���ؼ�
	// 2*�帲������ ��ŭ�� �����尡 1���� �ȼ��� �� ����
	if(groupThreadID.x < gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		// ���࿡ 0���� ���� ������ ������ // �̹��� ���� ���
		// �߶󳽴�
		int x = max(dispatchThreadID.x - gBlurRadius, 0);
		gCache[groupThreadID.x] = gInput[int2(x, dispatchThreadID.y)];
	}
	if(groupThreadID.x >= N-gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		// ���࿡ �̹��� ������ ��迡 ������ �߶󳽴�.
		int x = min(dispatchThreadID.x + gBlurRadius, gInput.Length.x-1);
		gCache[groupThreadID.x+2*gBlurRadius] = gInput[int2(x, dispatchThreadID.y)];
	}

	// Clamp out of bound samples that occur at image borders.
	// ���� ���� �̹��� ũ��� ���� // ���� �������� ��� ���η� ���� ���� �������ϰ�� ���η� ���´�.
	gCache[groupThreadID.x+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];

	// Wait for all threads to finish.
	// ��� ������ �۾��� ������ ĳ�ÿ� �ʿ��� ��� �ȼ��� ������ ��ϵȴ�.
	GroupMemoryBarrierWithGroupSync();
	
	//
	// Now blur each pixel.
	//

	// ���ȼ��� �帰��.
	float4 blurColor = float4(0, 0, 0, 0);
	
	[unroll]
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.x + gBlurRadius + i;
		// ���� �����ص״� �����޸� ���
		blurColor += gWeights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}

// �����带 ���η� ��ġ
[numthreads(1, N, 1)]
void VertBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	//
	// Fill local thread storage to reduce bandwidth.  To blur 
	// N pixels, we will need to load N + 2*BlurRadius pixels
	// due to the blur radius.
	//
	
	// This thread group runs N threads.  To get the extra 2*BlurRadius pixels, 
	// have 2*BlurRadius threads sample an extra pixel.
	// �տ��� ������ ��ŭ�� ������
	if(groupThreadID.y < gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		int y = max(dispatchThreadID.y - gBlurRadius, 0);
		gCache[groupThreadID.y] = gInput[int2(dispatchThreadID.x, y)];
	}
	// �ڿ��� ������ ��ŭ�� ������
	if(groupThreadID.y >= N-gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		int y = min(dispatchThreadID.y + gBlurRadius, gInput.Length.y-1);
		gCache[groupThreadID.y+2*gBlurRadius] = gInput[int2(dispatchThreadID.x, y)];
	}
	
	// Clamp out of bound samples that occur at image borders.
	gCache[groupThreadID.y+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];


	// Wait for all threads to finish.
	GroupMemoryBarrierWithGroupSync();
	
	//
	// Now blur each pixel.
	//

	float4 blurColor = float4(0, 0, 0, 0);
	
	[unroll]
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.y + gBlurRadius + i;
		
		blurColor += gWeights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}

technique11 HorzBlur
{
    pass P0
    {
		SetVertexShader( NULL );
        SetPixelShader( NULL );
		SetComputeShader( CompileShader( cs_5_0, HorzBlurCS() ) );
    }
}

technique11 VertBlur
{
    pass P0
    {
		SetVertexShader( NULL );
        SetPixelShader( NULL );
		SetComputeShader( CompileShader( cs_5_0, VertBlurCS() ) );
    }
}
