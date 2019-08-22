//***************************************************************************************
// TreeSprite.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Uses the geometry shader to expand a point sprite into a y-axis aligned 
// billboard that faces the camera.
//***************************************************************************************

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
	float4x4 gViewProj;
	Material gMaterial;
};

cbuffer cbFixed
{
	//
	// Compute texture coordinates to stretch texture over quad.
	//

	// 텍스처가 사각형 전체에 입혀지도록 텍스처 좌표를 계산한다.
	float2 gTexC[4] = 
	{
		float2(0.0f, 1.0f),
		float2(0.0f, 0.0f),
		float2(1.0f, 1.0f),
		float2(1.0f, 0.0f)
	};

};

// Nonnumeric values cannot be added to a cbuffer.
// 숫자형 값 이외에는 cbuffer에 저장할 수 없다.
// C++에서 ID3D11Texture2D와 같음 // 함수를 사용해서 생성해서 그렇지 원래 ArraySize라는 자료멤버가 있음

// 왜 텍스처들의 배열로 사용하지 않는가?
/*
Texture2D TexArray[4]; 
이렇게하면 TexArray[pin.PrinID%4].Sample(samLinear, pin.Text) // []안에는 반드시 리터럴이여야함 // 불가능!
*/
Texture2DArray gTreeMapArray;

SamplerState samLinear
{
	Filter   = MIN_MAG_MIP_LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

// 버텍스 쉐이더 input
struct VertexIn
{
	float3 PosW  : POSITION;
	float2 SizeW : SIZE;
};

// 버텍스 쉐이더 output
struct VertexOut
{
	float3 CenterW : POSITION;
	float2 SizeW   : SIZE;
};

// 기하쉐이더 output
struct GeoOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
    float2 Tex     : TEXCOORD;
    uint   PrimID  : SV_PrimitiveID;
};

// 기하쉐이더에 사이즈와 위치만 넘겨준다.
VertexOut VS(VertexIn vin)
{
	VertexOut vout;

	// Just pass data over to geometry shader.
	// 그대로 기하 쉐어더에 넘긴다.
	vout.CenterW = vin.PosW;
	vout.SizeW   = vin.SizeW;

	return vout;
}
 
 // We expand each point into a quad (4 vertices), so the maximum number of vertices
 // we output per geometry shader invocation is 4.
// 최대정점의 개수 // 한번의 실행에서 출력할 최대 정점 개수
// 1 - 20 개 : 최대성능
// 27 - 40 개 : 성능이 50퍼 감소
[maxvertexcount(4)]
void GS(
	// 입력 기본도형이 점인경우이다.
	/*
	예를 들면 이런식이다.
	line VertexOut gin[2]
	triangle VertexOut gin[3]
	*/
	point VertexOut gin[1], 


	/*
	이 의미소를 지정하면 입력 조립기 단계는 각 기본도형마다 자동으로 기본도형 ID를 생성
	한번의 그리기 호출로 n개의 기본 도형을 그린다고 할때, 0 ~ n-1 // 한번의 그리기 호출에 대해서만 유효
	*/
    uint primID : SV_PrimitiveID,
	
	
	
	// 출력형식은 항상 스트림 형식이며 inout이 붙는다.
	/*
	Point / Line / Triangle Stream
	선과 삼각형의 경우 출력기본도형은 항상 띠이다. // Line / Triangle
	restart함수를 사용해서 삼각형 목록을 출력가능
	*/
    inout TriangleStream<GeoOut> triStream)
{	
	//
	// Compute the local coordinate system of the sprite relative to the world
	// space such that the billboard is aligned with the y-axis and faces the eye.
	//

	// 들어온 값이 월드행렬이 필요없는 그자체로 월드좌표이기 때문에 바로계산해준다.
	// 뷰스페이스 행렬과 프로젝션 행렬은 추후 곱해서 내보낸다.
	// 빌보드가 y축기준으로 정렬된다. // 그다음 forward(look) 벡터를 구하고, right벡터를 구한다.
	float3 up = float3(0.0f, 1.0f, 0.0f);
	float3 look = gEyePosW - gin[0].CenterW;
	look.y = 0.0f; // y-axis aligned, so project to xz-plane
	look = normalize(look);
	float3 right = cross(up, look);

	//
	// Compute triangle strip vertices (quad) in world space.
	//
	// 들어온 사이즈 값으로 너비와 높이를 계산해준다.
	float halfWidth  = 0.5f*gin[0].SizeW.x;
	float halfHeight = 0.5f*gin[0].SizeW.y;
	
	float4 v[4];
	v[0] = float4(gin[0].CenterW + halfWidth*right - halfHeight*up, 1.0f);
	v[1] = float4(gin[0].CenterW + halfWidth*right + halfHeight*up, 1.0f);
	v[2] = float4(gin[0].CenterW - halfWidth*right - halfHeight*up, 1.0f);
	v[3] = float4(gin[0].CenterW - halfWidth*right + halfHeight*up, 1.0f);

	//
	// Transform quad vertices to world space and output 
	// them as a triangle strip.
	//
	GeoOut gout;
	[unroll]
	for(int i = 0; i < 4; ++i)
	{
		gout.PosH     = mul(v[i], gViewProj);
		gout.PosW     = v[i].xyz;
		gout.NormalW  = look;
		gout.Tex      = gTexC[i];
		gout.PrimID   = primID;
		
		// 출력스트림 목록에 정점을 추가할때 내정 append함수를 사용한다.
		triStream.Append(gout);
	}
}

float4 PS(GeoOut pin, uniform int gLightCount, uniform bool gUseTexure, uniform bool gAlphaClip, uniform bool gFogEnabled) : SV_Target
{
	// Interpolating normal can unnormalize it, so normalize it.
	// 보간 때문에 법선이 더이상 단위벡터가 아닐 수 있으므로 다시 정규화한다.
    pin.NormalW = normalize(pin.NormalW);

	// The toEye vector is used in lighting.
	float3 toEye = gEyePosW - pin.PosW;

	// Cache the distance to the eye from this surface point.
	// 시점과 이 표면 점 사이를 거리를 보관해둔다.
	float distToEye = length(toEye);

	// Normalize.
	toEye /= distToEye;
   
    // Default to multiplicative identity.
	// 곱셈의 항등원 // 만약 텍스처를 사용하지 않는다면 현재픽셀 그대로 적용
    float4 texColor = float4(1, 1, 1, 1);
    if(gUseTexure)
	{
		// Sample texture.
		// 텍스처 좌표 + PrinId 값
		// Texture2DArray에서 배열에서 하나의 표본을 추출하기 위해서는 3가지 좌표성분이 필요
		// 마지막값이 0이면 1번째 텍스처 ... 3이면 4번째 텍스처
		// 이렇게 해주면 텍스처를 각각 설정해서 그리지않고 쉽게 그릴수 있다. // 텍스처 배열을 설정하고 바로 그린다.
		float3 uvw = float3(pin.Tex, pin.PrimID%4);
		texColor = gTreeMapArray.Sample( samLinear, uvw );

		if(gAlphaClip)
		{
			// Discard pixel if texture alpha < 0.05.  Note that we do this
			// test as soon as possible so that we can potentially exit the shader 
			// early, thereby skipping the rest of the shader code.

			// 만약 알파성분이 0.05보다 작으면 폐기한다.
			// 알파 블렌딩을 안써도 어차피 기록이 안되기 때문에 유용하다.
			// 또 뒤에서 부터 그릴 필요없다 // 여기서 아예 출력이 제한되기 때문에 나머지 뒷 배경을 신경 쓸 필요없다.
			// 내부값이 0보다 작으면 픽셀을 버림
			clip(texColor.a - 0.05f);
		}
	}

	//
	// Lighting.
	//

	float4 litColor = texColor;
	if( gLightCount > 0  )
	{
		// Start with a sum of zero.
		float4 ambient = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 diffuse = float4(0.0f, 0.0f, 0.0f, 0.0f);
		float4 spec    = float4(0.0f, 0.0f, 0.0f, 0.0f);

		// Sum the light contribution from each light source.  
		[unroll]
		for(int i = 0; i < gLightCount; ++i)
		{
			float4 A, D, S;
			ComputeDirectionalLight(gMaterial, gDirLights[i], pin.NormalW, toEye, 
				A, D, S);

			ambient += A;
			diffuse += D;
			spec    += S;
		}

		// Modulate with late add.
		litColor = texColor*(ambient + diffuse) + spec;
	}

	//
	// Fogging
	//

	if( gFogEnabled )
	{
		// 0 ~ 1 제한 // 0일때는 보이고 1일때는 안보임
		float fogLerp = saturate( (distToEye - gFogStart) / gFogRange ); 

		// Blend the fog color and the lit color.
		litColor = lerp(litColor, gFogColor, fogLerp);
	}

	// Common to take alpha from diffuse material and texture.
	litColor.a = gMaterial.Diffuse.a * texColor.a;

    return litColor;
}

//---------------------------------------------------------------------------------------
// Techniques--just define the ones our demo needs; you can define the other 
//   variations as needed.
//---------------------------------------------------------------------------------------
technique11 Light3
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( CompileShader( gs_5_0, GS() ) );
        SetPixelShader( CompileShader( ps_5_0, PS(3, false, false, false) ) );
    }
}

technique11 Light3TexAlphaClip
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( CompileShader( gs_5_0, GS() ) );
        SetPixelShader( CompileShader( ps_5_0, PS(3, true, true, false) ) );
    }
}
            
technique11 Light3TexAlphaClipFog
{
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( CompileShader( gs_5_0, GS() ) );
        SetPixelShader( CompileShader( ps_5_0, PS(3, true, true, true) ) );
    }
}
