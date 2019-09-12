//=============================================================================
// Fire.fx by Frank Luna (C) 2011 All Rights Reserved.
//
// Fire particle system.  Particles are emitted directly in world space.
//=============================================================================


//***********************************************
// GLOBALS                                      *
//***********************************************

cbuffer cbPerFrame
{
	float3 gEyePosW;
	
	// for when the emit position/direction is varying
	float3 gEmitPosW;
	float3 gEmitDirW;
	
	float gGameTime;
	float gTimeStep;
	float4x4 gViewProj; 
};

cbuffer cbFixed
{
	// Net constant acceleration used to accerlate the particles.
	float3 gAccelW = {0.0f, 7.8f, 0.0f};
	
	// Texture coordinates used to stretch texture over quad 
	// when we expand point particle into a quad.
	float2 gQuadTexC[4] = 
	{
		float2(0.0f, 1.0f),
		float2(1.0f, 1.0f),
		float2(0.0f, 0.0f),
		float2(1.0f, 0.0f)
	};
};
 
// Array of textures for texturing the particles.
Texture2DArray gTexArray;

// Random texture used to generate random numbers in shaders.
Texture1D gRandomTex;
 
SamplerState samLinear
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};
 
DepthStencilState DisableDepth
{
    DepthEnable = FALSE;
    DepthWriteMask = ZERO;
};

DepthStencilState NoDepthWrites
{
    DepthEnable = TRUE;
    DepthWriteMask = ZERO;
};

BlendState AdditiveBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = TRUE;

	// C = a(s) * C(src) + C(dst)
    SrcBlend = SRC_ALPHA;
    DestBlend = ONE;
	// 연기같은 경우는 점점더 어두워져야 되기 때문에 감소로 설정해둬야 한다.
    BlendOp = ADD;

    SrcBlendAlpha = ZERO;
    DestBlendAlpha = ZERO;
    BlendOpAlpha = ADD;
    RenderTargetWriteMask[0] = 0x0F;
};

//***********************************************
// HELPER FUNCTIONS                             *
//***********************************************
// 단위구의 한 무작위 벡터를 얻는데 쓰이는 쉐이더 함수
float3 RandUnitVec3(float offset)
{
	// Use game time plus offset to sample random texture.
	// 외부에서 들어온 게임 시간과 오프셋을 더해서 인덱스를 만듬
	float u = (gGameTime + offset);
	
	// coordinates in [-1,1]
	// 텍스처를 생성할떄 그렇게 만들었음 // 게임시간은 게임 토탈시간인데, wrap모드이기 때문에 반복된다.
	float3 v = gRandomTex.SampleLevel(samLinear, u, 0).xyz;
	
	// project onto unit sphere
	// 받은 텍스처를 정규화
	return normalize(v);
}
 
//***********************************************
// STREAM-OUT TECH                              *
//***********************************************

// emitter particle // 방출기 입자
#define PT_EMITTER 0
#define PT_FLARE 1
 
struct Particle
{
	float3 InitialPosW : POSITION;
	float3 InitialVelW : VELOCITY;
	float2 SizeW       : SIZE;
	float Age          : AGE;
	uint Type          : TYPE;
};
  
Particle StreamOutVS(Particle vin)
{
	return vin;
}

// The stream-out GS is just responsible for emitting 
// new particles and destroying old particles.  The logic
// programed here will generally vary from particle system
// to particle system, as the destroy/spawn rules will be 
// different.

// 스트림출력 geometry shader는 새로운입자를 생성 / 소멸시킨다
[maxvertexcount(2)]
void StreamOutGS(point Particle gin[1], 
                 inout PointStream<Particle> ptStream)
{	
	gin[0].Age += gTimeStep;
	
	// 방출기일때
	if( gin[0].Type == PT_EMITTER )
	{	
		// time to emit a new particle?
		// 방출기의 age가 0.005 이상일때 생성
		if( gin[0].Age > 0.005f )
		{
			float3 vRandom = RandUnitVec3(0.0f);
			// 상대적으로 y값의 절댓값이 크다
			// 좁고 긴 불이 만들어진다.
			vRandom.x *= 0.5f;
			vRandom.z *= 0.5f;
			
			Particle p;
			// 처음위치는 방출기 위치에서
			p.InitialPosW = gEmitPosW.xyz;
			// 처음 속도는 렌덤값으로 뽑혔다.
			p.InitialVelW = 4.0f*vRandom;
			p.SizeW       = float2(3.0f, 3.0f);
			p.Age         = 0.0f;
			p.Type        = PT_FLARE;
			
			// 생성한 불꽃을 넣어준다.
			ptStream.Append(p);
			
			// reset the time to emit
			gin[0].Age = 0.0f;
		}
		
		// always keep emitters
		ptStream.Append(gin[0]);
	}
	else
	{
		// Specify conditions to keep particle; this may vary from system to system.
		// age가 1.0f이하일때만 다시 소멸하지않고 다시 넣어준다.
		if( gin[0].Age <= 1.0f )
			ptStream.Append(gin[0]);
	}		
}

// GeometryShader 정의 방법 출력스트림 사용할떄
GeometryShader gsStreamOut = ConstructGSWithSO(
	// 컴파일된 GeometryShader 프로그램
	CompileShader( gs_5_0, StreamOutGS() ),
	// 스트림으로 출력할 정점들의 형식
	// 다음과 같은 정점형식에 해당한다.
	
	/*
		struct Particle
		{
			float3 InitialPosW : POSITION;
			float3 InitialVelW : VELOCITY;
			float2 SizeW       : SIZE;
			float Age          : AGE;
			uint Type          : TYPE;
		};
	*/
	"POSITION.xyz; VELOCITY.xyz; SIZE.xy; AGE.x; TYPE.x" );
	
technique11 StreamOutTech
{
	// 스트림 출력을 사용하는 경우 특별한 설정이 없는 한 기하 쉐이더에서 출력한정점은
	// 래스터화기로도 입력된다. 자료를 스트림으로만 출력하기만하고 렌더링하지 않는 기법에서는
	// 픽셀쉐이더와 깊이 스텐실 버퍼를 비활성화 해야한다.
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, StreamOutVS() ) );
        SetGeometryShader( gsStreamOut );
        
        // disable pixel shader for stream-out only
		// 스트림출력만으로 사용하기 위해서 픽셀쉐이더를 비활성화
        SetPixelShader(NULL);
        
        // we must also disable the depth buffer for stream-out only
		// 스트림 출력으로만 사용하기 위해서 깊이버퍼도 비활성화
        SetDepthStencilState( DisableDepth, 0 );
    }
}

//***********************************************
// DRAW TECH                                    *
//***********************************************

struct VertexOut
{
	float3 PosW  : POSITION;
	float2 SizeW : SIZE;
	float4 Color : COLOR;
	uint   Type  : TYPE;
};

VertexOut DrawVS(Particle vin)
{
	VertexOut vout;
	
	float t = vin.Age;
	
	// constant acceleration equation
	// 가속도는 위로 되어있음 // 속도도 상대적으로 y값의 절댓값이 크다.
	vout.PosW = 0.5f*t*t*gAccelW + t*vin.InitialVelW + vin.InitialPosW;
	
	// fade color with time
	// 시간에 따른 감소 1 - (0 ~ 1) // 최대나이일때 불투명도는 0이 된다
	float opacity = 1.0f - smoothstep(0.0f, 1.0f, t/1.0f);
	vout.Color = float4(1.0f, 1.0f, 1.0f, opacity);
	
	vout.SizeW = vin.SizeW;
	vout.Type  = vin.Type;
	
	return vout;
}

struct GeoOut
{
	float4 PosH  : SV_Position;
	float4 Color : COLOR;
	float2 Tex   : TEXCOORD;
};

// The draw GS just expands points into camera facing quads.
[maxvertexcount(4)]
void DrawGS(point VertexOut gin[1], 
	// 추후 autoDraw로 그린다.
            inout TriangleStream<GeoOut> triStream)
{	
	// do not draw emitter particles.
	if( gin[0].Type != PT_EMITTER )
	{
		//
		// Compute world matrix so that billboard faces the camera.
		//

		// 시점을 바라보는 방향으로
		float3 look  = normalize(gEyePosW.xyz - gin[0].PosW);
		// 외적으로 나머지를 구해준다.
		float3 right = normalize(cross(float3(0,1,0), look));
		float3 up    = cross(look, right);
		
		//
		// Compute triangle strip vertices (quad) in world space.
		//
		float halfWidth  = 0.5f*gin[0].SizeW.x;
		float halfHeight = 0.5f*gin[0].SizeW.y;
	
		float4 v[4];
		v[0] = float4(gin[0].PosW + halfWidth*right - halfHeight*up, 1.0f);
		v[1] = float4(gin[0].PosW + halfWidth*right + halfHeight*up, 1.0f);
		v[2] = float4(gin[0].PosW - halfWidth*right - halfHeight*up, 1.0f);
		v[3] = float4(gin[0].PosW - halfWidth*right + halfHeight*up, 1.0f);
		
		//
		// Transform quad vertices to world space and output 
		// them as a triangle strip.
		//
		GeoOut gout;
		[unroll]
		for(int i = 0; i < 4; ++i)
		{
			gout.PosH  = mul(v[i], gViewProj);
			gout.Tex = gQuadTexC[i];
			gout.Color = gin[0].Color;
			triStream.Append(gout);
		}	
	}
}

float4 DrawPS(GeoOut pin) : SV_TARGET
{
	return gTexArray.Sample(samLinear, float3(pin.Tex, 0))*pin.Color;
}

technique11 DrawTech
{
    pass P0
    {
        SetVertexShader(   CompileShader( vs_5_0, DrawVS() ) );
        SetGeometryShader( CompileShader( gs_5_0, DrawGS() ) );
        SetPixelShader(    CompileShader( ps_5_0, DrawPS() ) );
        
        SetBlendState(AdditiveBlending, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xffffffff);
        SetDepthStencilState( NoDepthWrites, 0 );
    }
}