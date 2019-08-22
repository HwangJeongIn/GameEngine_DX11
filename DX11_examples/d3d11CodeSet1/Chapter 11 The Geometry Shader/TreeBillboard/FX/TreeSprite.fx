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

	// �ؽ�ó�� �簢�� ��ü�� ���������� �ؽ�ó ��ǥ�� ����Ѵ�.
	float2 gTexC[4] = 
	{
		float2(0.0f, 1.0f),
		float2(0.0f, 0.0f),
		float2(1.0f, 1.0f),
		float2(1.0f, 0.0f)
	};

};

// Nonnumeric values cannot be added to a cbuffer.
// ������ �� �̿ܿ��� cbuffer�� ������ �� ����.
// C++���� ID3D11Texture2D�� ���� // �Լ��� ����ؼ� �����ؼ� �׷��� ���� ArraySize��� �ڷ����� ����

// �� �ؽ�ó���� �迭�� ������� �ʴ°�?
/*
Texture2D TexArray[4]; 
�̷����ϸ� TexArray[pin.PrinID%4].Sample(samLinear, pin.Text) // []�ȿ��� �ݵ�� ���ͷ��̿����� // �Ұ���!
*/
Texture2DArray gTreeMapArray;

SamplerState samLinear
{
	Filter   = MIN_MAG_MIP_LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

// ���ؽ� ���̴� input
struct VertexIn
{
	float3 PosW  : POSITION;
	float2 SizeW : SIZE;
};

// ���ؽ� ���̴� output
struct VertexOut
{
	float3 CenterW : POSITION;
	float2 SizeW   : SIZE;
};

// ���Ͻ��̴� output
struct GeoOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
    float2 Tex     : TEXCOORD;
    uint   PrimID  : SV_PrimitiveID;
};

// ���Ͻ��̴��� ������� ��ġ�� �Ѱ��ش�.
VertexOut VS(VertexIn vin)
{
	VertexOut vout;

	// Just pass data over to geometry shader.
	// �״�� ���� ������� �ѱ��.
	vout.CenterW = vin.PosW;
	vout.SizeW   = vin.SizeW;

	return vout;
}
 
 // We expand each point into a quad (4 vertices), so the maximum number of vertices
 // we output per geometry shader invocation is 4.
// �ִ������� ���� // �ѹ��� ���࿡�� ����� �ִ� ���� ����
// 1 - 20 �� : �ִ뼺��
// 27 - 40 �� : ������ 50�� ����
[maxvertexcount(4)]
void GS(
	// �Է� �⺻������ ���ΰ���̴�.
	/*
	���� ��� �̷����̴�.
	line VertexOut gin[2]
	triangle VertexOut gin[3]
	*/
	point VertexOut gin[1], 


	/*
	�� �ǹ̼Ҹ� �����ϸ� �Է� ������ �ܰ�� �� �⺻�������� �ڵ����� �⺻���� ID�� ����
	�ѹ��� �׸��� ȣ��� n���� �⺻ ������ �׸��ٰ� �Ҷ�, 0 ~ n-1 // �ѹ��� �׸��� ȣ�⿡ ���ؼ��� ��ȿ
	*/
    uint primID : SV_PrimitiveID,
	
	
	
	// ��������� �׻� ��Ʈ�� �����̸� inout�� �ٴ´�.
	/*
	Point / Line / Triangle Stream
	���� �ﰢ���� ��� ��±⺻������ �׻� ���̴�. // Line / Triangle
	restart�Լ��� ����ؼ� �ﰢ�� ����� ��°���
	*/
    inout TriangleStream<GeoOut> triStream)
{	
	//
	// Compute the local coordinate system of the sprite relative to the world
	// space such that the billboard is aligned with the y-axis and faces the eye.
	//

	// ���� ���� ��������� �ʿ���� ����ü�� ������ǥ�̱� ������ �ٷΰ�����ش�.
	// �佺���̽� ��İ� �������� ����� ���� ���ؼ� ��������.
	// �����尡 y��������� ���ĵȴ�. // �״��� forward(look) ���͸� ���ϰ�, right���͸� ���Ѵ�.
	float3 up = float3(0.0f, 1.0f, 0.0f);
	float3 look = gEyePosW - gin[0].CenterW;
	look.y = 0.0f; // y-axis aligned, so project to xz-plane
	look = normalize(look);
	float3 right = cross(up, look);

	//
	// Compute triangle strip vertices (quad) in world space.
	//
	// ���� ������ ������ �ʺ�� ���̸� ������ش�.
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
		
		// ��½�Ʈ�� ��Ͽ� ������ �߰��Ҷ� ���� append�Լ��� ����Ѵ�.
		triStream.Append(gout);
	}
}

float4 PS(GeoOut pin, uniform int gLightCount, uniform bool gUseTexure, uniform bool gAlphaClip, uniform bool gFogEnabled) : SV_Target
{
	// Interpolating normal can unnormalize it, so normalize it.
	// ���� ������ ������ ���̻� �������Ͱ� �ƴ� �� �����Ƿ� �ٽ� ����ȭ�Ѵ�.
    pin.NormalW = normalize(pin.NormalW);

	// The toEye vector is used in lighting.
	float3 toEye = gEyePosW - pin.PosW;

	// Cache the distance to the eye from this surface point.
	// ������ �� ǥ�� �� ���̸� �Ÿ��� �����صд�.
	float distToEye = length(toEye);

	// Normalize.
	toEye /= distToEye;
   
    // Default to multiplicative identity.
	// ������ �׵�� // ���� �ؽ�ó�� ������� �ʴ´ٸ� �����ȼ� �״�� ����
    float4 texColor = float4(1, 1, 1, 1);
    if(gUseTexure)
	{
		// Sample texture.
		// �ؽ�ó ��ǥ + PrinId ��
		// Texture2DArray���� �迭���� �ϳ��� ǥ���� �����ϱ� ���ؼ��� 3���� ��ǥ������ �ʿ�
		// ���������� 0�̸� 1��° �ؽ�ó ... 3�̸� 4��° �ؽ�ó
		// �̷��� ���ָ� �ؽ�ó�� ���� �����ؼ� �׸����ʰ� ���� �׸��� �ִ�. // �ؽ�ó �迭�� �����ϰ� �ٷ� �׸���.
		float3 uvw = float3(pin.Tex, pin.PrimID%4);
		texColor = gTreeMapArray.Sample( samLinear, uvw );

		if(gAlphaClip)
		{
			// Discard pixel if texture alpha < 0.05.  Note that we do this
			// test as soon as possible so that we can potentially exit the shader 
			// early, thereby skipping the rest of the shader code.

			// ���� ���ļ����� 0.05���� ������ ����Ѵ�.
			// ���� ������ �Ƚᵵ ������ ����� �ȵǱ� ������ �����ϴ�.
			// �� �ڿ��� ���� �׸� �ʿ���� // ���⼭ �ƿ� ����� ���ѵǱ� ������ ������ �� ����� �Ű� �� �ʿ����.
			// ���ΰ��� 0���� ������ �ȼ��� ����
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
		// 0 ~ 1 ���� // 0�϶��� ���̰� 1�϶��� �Ⱥ���
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
