//***************************************************************************************
// ParticleSystem.cpp by Frank Luna (C) 2011 All Rights Reserved.
//***************************************************************************************

#include "ParticleSystem.h"
#include "TextureMgr.h"
#include "Vertex.h"
#include "Effects.h"
#include "Camera.h"
 
ParticleSystem::ParticleSystem()
: mInitVB(0), mDrawVB(0), mStreamOutVB(0), mTexArraySRV(0), mRandomTexSRV(0)
{
	mFirstRun = true;
	mGameTime = 0.0f;
	mTimeStep = 0.0f;
	mAge      = 0.0f;

	mEyePosW  = XMFLOAT3(0.0f, 0.0f, 0.0f);
	mEmitPosW = XMFLOAT3(0.0f, 0.0f, 0.0f);
	mEmitDirW = XMFLOAT3(0.0f, 1.0f, 0.0f);
}

ParticleSystem::~ParticleSystem()
{
	ReleaseCOM(mInitVB);
	ReleaseCOM(mDrawVB);
	ReleaseCOM(mStreamOutVB);
}

float ParticleSystem::GetAge()const
{
	return mAge;
}

void ParticleSystem::SetEyePos(const XMFLOAT3& eyePosW)
{
	mEyePosW = eyePosW;
}

void ParticleSystem::SetEmitPos(const XMFLOAT3& emitPosW)
{
	mEmitPosW = emitPosW;
}

void ParticleSystem::SetEmitDir(const XMFLOAT3& emitDirW)
{
	mEmitDirW = emitDirW;
}

void ParticleSystem::Init(ID3D11Device* device, ParticleEffect* fx, ID3D11ShaderResourceView* texArraySRV, 
	                      ID3D11ShaderResourceView* randomTexSRV, UINT maxParticles)
{
	mMaxParticles = maxParticles;

	mFX = fx;

	mTexArraySRV  = texArraySRV;
	mRandomTexSRV = randomTexSRV; 

	BuildVB(device);
}

void ParticleSystem::Reset()
{
	mFirstRun = true;
	mAge      = 0.0f;
}

void ParticleSystem::Update(float dt, float gameTime)
{
	mGameTime = gameTime;
	mTimeStep = dt;

	mAge += dt;
}

void ParticleSystem::Draw(ID3D11DeviceContext* dc, const Camera& cam)
{
	XMMATRIX VP = cam.ViewProj();

	//
	// Set constants.
	//
	// 상수들 설정
	mFX->SetViewProj(VP);
	mFX->SetGameTime(mGameTime);
	mFX->SetTimeStep(mTimeStep);
	mFX->SetEyePosW(mEyePosW);
	mFX->SetEmitPosW(mEmitPosW);
	mFX->SetEmitDirW(mEmitDirW);
	mFX->SetTexArray(mTexArraySRV);
	mFX->SetRandomTex(mRandomTexSRV);

	//
	// Set IA stage.
	//
	dc->IASetInputLayout(InputLayouts::Particle);
    dc->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_POINTLIST);

	UINT stride = sizeof(Vertex::Particle);
    UINT offset = 0;

	// On the first pass, use the initialization VB.  Otherwise, use
	// the VB that contains the current particle list.
	// 처음일때는 초기 버퍼를 사용
	// 처음일때는 방출기 버퍼를 넣어준다. // 그게 아니면 맥스 크기의 파티클 버퍼를 넣어준다
	if( mFirstRun )
		dc->IASetVertexBuffers(0, 1, &mInitVB, &stride, &offset);
	else
		dc->IASetVertexBuffers(0, 1, &mDrawVB, &stride, &offset);

	//
	// Draw the current particle list using stream-out only to update them.  
	// The updated vertices are streamed-out to the target VB. 
	//
	// 현재 파티클리스트를 스트림 출력을 사용해서 업데이트한다.
	// 업데이트된 버텍스들은 타겟버퍼에 출력되어 나온다.
	dc->SOSetTargets(
		// 1개
		1,
		// 타겟 스트림 출력 버텍스 버퍼
		&mStreamOutVB,
		// 스트림 출력 단계가 정점들을 기록하기 시작할 위치를 나타내는 오프셋들(정점버퍼당 하나)
		&offset);

    D3DX11_TECHNIQUE_DESC techDesc;
	mFX->StreamOutTech->GetDesc( &techDesc );
    for(UINT p = 0; p < techDesc.Passes; ++p)
    {
        mFX->StreamOutTech->GetPassByIndex( p )->Apply(0, dc);
        
		if( mFirstRun )
		{
			// 처음에는 방출기 하나이므로 그냥 하나만 그린다. 
			// 참고로 방출기는 스트림 출력에서 시간이 지났으면 파티클을 방출한다.
			dc->Draw(1, 0);
			mFirstRun = false;
		}
		else
		{
			// 방출기 방출역할
			// 파티클 업데이트
			dc->DrawAuto();
		}
    }

	// done streaming-out--unbind the vertex buffer
	// 스트림 출력이 완료되었으므로 언바인드 시킨다.

	// 이렇게 언바인드 시키는 이유는 하나의 정점 버퍼를
	// 스트림 출력단계와 입력 조립기 단계에 동시에 묶을 수 없다.
	ID3D11Buffer* bufferArray[1] = {0};
	dc->SOSetTargets(1, bufferArray, &offset);

	// ping-pong the vertex buffers
	// 출력으로 받은 것들을 그릴것으로 넣어준다. 그러면 출력스트림에는 다시 이전의 상태의 버텍스들이 들어간다.
	std::swap(mDrawVB, mStreamOutVB);

	//
	// Draw the updated particle system we just streamed-out. 
	//
	// 가변적인 버텍스들을 바로 그리기 위한 조건이다.
	/*
	1. DrawAuto함수를 호출하기 전에 반드시 정점버퍼(스트림 출력 대상이였던 것)를 입력조립기 단계의 슬롯0에 묶어두어야 한다.
	2. 스트림 출력된 정점버퍼를 자동으로 그릴때도 정점 버퍼의 정점들의 입력 배치는 명시적 offset stride 등
	3. DrawAuto 메서드는 인덱스를 사용하지 않으므로 기하 쉐이더는 기본도형들 전부를 정점 목록 형태로 출력해야한다.
	*/
	dc->IASetVertexBuffers(0, 1, &mDrawVB, &stride, &offset);

	mFX->DrawTech->GetDesc( &techDesc );
    for(UINT p = 0; p < techDesc.Passes; ++p)
    {
        mFX->DrawTech->GetPassByIndex( p )->Apply(0, dc);
        
		// 가변적인 버텍스들을 어떻게 그릴까? // 이렇게 그리면 된다.
		dc->DrawAuto();
    }
}

void ParticleSystem::BuildVB(ID3D11Device* device)
{
	//
	// Create the buffer to kick-off the particle system.
	//

    D3D11_BUFFER_DESC vbd;
    vbd.Usage = D3D11_USAGE_DEFAULT;
	vbd.ByteWidth = sizeof(Vertex::Particle) * 1;
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    vbd.CPUAccessFlags = 0;
    vbd.MiscFlags = 0;
	vbd.StructureByteStride = 0;

	// The initial particle emitter has type 0 and age 0.  The rest
	// of the particle attributes do not apply to an emitter.
	// 처음 파티클은 타입이 방출기(emitter)이다 / age 도 0 
	// 여기서는 방출기가 하나지만 여러가지 효과를 구현하기 위해서 방출기가 여러개가 될 수 있다.
	// 미사일이 발사되고 터지고 불꽃들이 튀는 효과 등
	Vertex::Particle p;
	ZeroMemory(&p, sizeof(Vertex::Particle));
	p.Age  = 0.0f;
	p.Type = 1; 
 
    D3D11_SUBRESOURCE_DATA vinitData;
    vinitData.pSysMem = &p;

	HR(device->CreateBuffer(&vbd, &vinitData, &mInitVB));
	
	//
	// Create the ping-pong buffers for stream-out and drawing.
	//
	vbd.ByteWidth = sizeof(Vertex::Particle) * mMaxParticles;
	
	// 버텍스버퍼형식과 스트림 출력형식 둘다로 바인딩 해준다. 
	// 블러 예제와 마찬가지로 출력된것을 다시 입력으로 사용하기 때문이다.
	// 그렇기 때문에 두가지 플래그를 지정한다.
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER | D3D11_BIND_STREAM_OUTPUT;

    HR(device->CreateBuffer(&vbd, 0, &mDrawVB));
	HR(device->CreateBuffer(&vbd, 0, &mStreamOutVB));
}