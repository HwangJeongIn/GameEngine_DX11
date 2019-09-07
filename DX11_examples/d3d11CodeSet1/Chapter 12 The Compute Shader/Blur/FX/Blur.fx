//=============================================================================
// Blur.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Performs a separable blur with a blur radius of 5.  
//=============================================================================

cbuffer cbSettings
{
	// 미리 수학식을 통해 가중치를 계산해 두었다.
	float gWeights[11] = 
	{
		0.05f, 0.05f, 0.1f, 0.1f, 0.1f, 0.2f, 0.1f, 0.1f, 0.1f, 0.05f, 0.05f,
	};
};

cbuffer cbFixed
{
	static const int gBlurRadius = 5;
};

// 원본자료와 출력

// 입력은 읽기 전용
Texture2D gInput;
// 출력은 읽고 쓰기로 설정한다 RW = read / write
// 뒤의 숫자는 차원을 의미한다 4 = 4차원
RWTexture2D<float4> gOutput;

// 스레드 그룹당 256개의 스레드를 갖도록 하였다.
#define N 256
// 스레드 그룹당 공유하는 메모리의 사이즈는 256에 말단 스레드의 주변 픽셀까지 합쳐서 256 + 흐림 반지름 * 2 이다.
#define CacheSize (N + 2*gBlurRadius)
groupshared float4 gCache[CacheSize];

// 스레드 그룹 하나의 스레드 개수와 구성 / 한 그룹의 스레드들을 1 2 3차원 격자형식으로 표현가능
[numthreads(N, 1, 1)]
// 스레드 식별을 위한 매개변수
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
	// N개의 스레드에서 여분의 2*흐림반지름 픽셀을 얻기 위해서
	// 2*흐림반지름 만큼의 스레드가 1개의 픽셀을 더 추출
	if(groupThreadID.x < gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		// 만약에 0보다 작은 범위로 들어오면 // 이미지 왼쪽 경계
		// 잘라낸다
		int x = max(dispatchThreadID.x - gBlurRadius, 0);
		gCache[groupThreadID.x] = gInput[int2(x, dispatchThreadID.y)];
	}
	if(groupThreadID.x >= N-gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		// 만약에 이미지 오른쪽 경계에 닿으면 잘라낸다.
		int x = min(dispatchThreadID.x + gBlurRadius, gInput.Length.x-1);
		gCache[groupThreadID.x+2*gBlurRadius] = gInput[int2(x, dispatchThreadID.y)];
	}

	// Clamp out of bound samples that occur at image borders.
	// 세로 가로 이미지 크기로 한정 // 수평 스레드일 경우 가로로 남고 수직 스레드일경우 세로로 남는다.
	gCache[groupThreadID.x+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];

	// Wait for all threads to finish.
	// 모든 스레드 작업이 끝나면 캐시에 필요한 모든 픽셀의 값들이 기록된다.
	GroupMemoryBarrierWithGroupSync();
	
	//
	// Now blur each pixel.
	//

	// 각픽셀을 흐린다.
	float4 blurColor = float4(0, 0, 0, 0);
	
	[unroll]
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.x + gBlurRadius + i;
		// 기존 저장해뒀던 공유메모리 사용
		blurColor += gWeights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}

// 스레드를 세로로 배치
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
	// 앞에서 반지름 만큼의 스레드
	if(groupThreadID.y < gBlurRadius)
	{
		// Clamp out of bound samples that occur at image borders.
		int y = max(dispatchThreadID.y - gBlurRadius, 0);
		gCache[groupThreadID.y] = gInput[int2(dispatchThreadID.x, y)];
	}
	// 뒤에서 반지름 만큼의 스레드
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
