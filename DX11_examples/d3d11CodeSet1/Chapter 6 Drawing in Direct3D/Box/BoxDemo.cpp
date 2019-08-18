//***************************************************************************************
// BoxDemo.cpp by Frank Luna (C) 2011 All Rights Reserved.
//
// Demonstrates rendering a colored box.
//
// Controls:
//		Hold the left mouse button down and move the mouse to rotate.
//      Hold the right mouse button down to zoom in and out.
//
//***************************************************************************************

#include "d3dApp.h"
#include "d3dx11Effect.h"
#include "MathHelper.h"

struct Vertex
{
	XMFLOAT3 Pos;
	XMFLOAT4 Color;
};

class BoxApp : public D3DApp
{
public:
	BoxApp(HINSTANCE hInstance);
	~BoxApp();

	bool Init();
	void OnResize();
	void UpdateScene(float dt);
	void DrawScene(); 

	void OnMouseDown(WPARAM btnState, int x, int y);
	void OnMouseUp(WPARAM btnState, int x, int y);
	void OnMouseMove(WPARAM btnState, int x, int y);

private:
	void BuildGeometryBuffers();
	void BuildFX();
	void BuildVertexLayout();

private:
	// 박스의 인덱스와 버텍스 버퍼
	ID3D11Buffer* mBoxVB;
	ID3D11Buffer* mBoxIB;

	ID3DX11Effect* mFX;
	ID3DX11EffectTechnique* mTech;
	ID3DX11EffectMatrixVariable* mfxWorldViewProj;

	ID3D11InputLayout* mInputLayout;

	// 월드 뷰 프로젝션 행렬
	/*
	
	월드 : 로컬좌표계에서 월드 좌표계로 변환 // 나중에 인스턴싱 활용
	
	뷰 : 카메라 공간을 뷰스페이스 공간으로 변환하는 행렬
	// 카메라의 월드행렬의 역행렬이라고 보면 된다.

	프로젝션 : 투영하기 위한 행렬이다. 종횡비와 가까운 거리와 먼거리 수직 시야각만 있으면 구할 수 있다.
	// 최종적으로 원근 나누기전을 투영공간에 있다고 말하고 원근 나누기 후의 기하구조를 정규화된 장치좌표 NDC에 있다고 한다.

	*/

	XMFLOAT4X4 mWorld;
	XMFLOAT4X4 mView;
	XMFLOAT4X4 mProj;

	float mTheta;
	float mPhi;
	float mRadius;

	POINT mLastMousePos;
};

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE prevInstance,
				   PSTR cmdLine, int showCmd)
{
	// Enable run-time memory check for debug builds.
#if defined(DEBUG) | defined(_DEBUG)
	_CrtSetDbgFlag( _CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF );
#endif

	BoxApp theApp(hInstance);
	
	if( !theApp.Init() )
		return 0;
	
	return theApp.Run();
}
 

BoxApp::BoxApp(HINSTANCE hInstance)
: D3DApp(hInstance), mBoxVB(0), mBoxIB(0), mFX(0), mTech(0),
  mfxWorldViewProj(0), mInputLayout(0), 
  mTheta(1.5f*MathHelper::Pi), mPhi(0.25f*MathHelper::Pi), mRadius(5.0f)
{
	mMainWndCaption = L"Box Demo";
	
	mLastMousePos.x = 0;
	mLastMousePos.y = 0;

	XMMATRIX I = XMMatrixIdentity();
	XMStoreFloat4x4(&mWorld, I);
	XMStoreFloat4x4(&mView, I);
	XMStoreFloat4x4(&mProj, I);
}

BoxApp::~BoxApp()
{
	// 소멸될때 받았던 COM객체들을 릴리즈 시켜준다.
	ReleaseCOM(mBoxVB);
	ReleaseCOM(mBoxIB);
	ReleaseCOM(mFX);
	ReleaseCOM(mInputLayout);
}

bool BoxApp::Init()
{
	if(!D3DApp::Init())
		return false;

	// 3가지를 빌드 시켜준다
	BuildGeometryBuffers();
	BuildFX();
	BuildVertexLayout();

	return true;
}

void BoxApp::OnResize()
{
	D3DApp::OnResize();

	// The window resized, so update the aspect ratio and recompute the projection matrix.
	XMMATRIX P = XMMatrixPerspectiveFovLH(0.25f*MathHelper::Pi, AspectRatio(), 1.0f, 1000.0f);
	XMStoreFloat4x4(&mProj, P);
}

void BoxApp::UpdateScene(float dt)
{
	// Convert Spherical to Cartesian coordinates.
	float x = mRadius*sinf(mPhi)*cosf(mTheta);
	float z = mRadius*sinf(mPhi)*sinf(mTheta);
	float y = mRadius*cosf(mPhi);

	// Build the view matrix.
	XMVECTOR pos    = XMVectorSet(x, y, z, 1.0f);
	XMVECTOR target = XMVectorZero();
	XMVECTOR up     = XMVectorSet(0.0f, 1.0f, 0.0f, 0.0f);

	XMMATRIX V = XMMatrixLookAtLH(pos, target, up);
	XMStoreFloat4x4(&mView, V);
}

void BoxApp::DrawScene()
{
	md3dImmediateContext->ClearRenderTargetView(mRenderTargetView, reinterpret_cast<const float*>(&Colors::LightSteelBlue));
	md3dImmediateContext->ClearDepthStencilView(mDepthStencilView, D3D11_CLEAR_DEPTH|D3D11_CLEAR_STENCIL, 1.0f, 0);

	// 어떤 레이아웃을 사용할지 지정
	md3dImmediateContext->IASetInputLayout(mInputLayout);
	// 입력자료에 대해서 어떤식으로 해석하고 그릴지 설정
    md3dImmediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

	// 여러가시 슬롯을 사용한다면 여러가지 보폭이 배열형식으로 지정되어야 한다.
	UINT stride = sizeof(Vertex);
    UINT offset = 0;

    md3dImmediateContext->IASetVertexBuffers(
		0, // 정점 버퍼들을 붙이기 시작할 입력 슬롯의 인덱스 // 0번슬롯사용
		1, // 입력 슬롯들에 붙이고자하는 버퍼들의 개수 // 0번슬롯부터 1개
		&mBoxVB, // 버텍스 버퍼들을 담은 배열의 첫원소
		&stride, // 보폭들의 배열의 첫원소 포인터 // 여기서 보폭은 해당 정점 버퍼의 한 원소의 바이트 단위 크기
		&offset // 오프셋들의 배열의 첫원소를 가리키는 포인터 // 정점 버퍼당 오프셋하나 i -> i 매칭됨 // 여기서는 오프셋없이 처음부터 읽는다. 

		// 오프셋 : 정점버퍼의 시작위치에서 입력조립기 단계가 정점 자료를 읽기 시작할 정점 버퍼 안 위치까지의 거리
		// 읽기 시작할 위치
	);

	// 최종 파이프라인에 묶어준다.
	// DXGI_FORMAT_R32_UINT // 부호없는 정수형식
	// : A single-component, 32-bit unsigned-integer format that supports 32 bits for the red channel.
	md3dImmediateContext->IASetIndexBuffer(mBoxIB, DXGI_FORMAT_R32_UINT, 0);

	// Set constants
	XMMATRIX world = XMLoadFloat4x4(&mWorld);
	XMMATRIX view  = XMLoadFloat4x4(&mView);
	XMMATRIX proj  = XMLoadFloat4x4(&mProj);
	XMMATRIX worldViewProj = world*view*proj;

	// 세팅해주는 방식
	// 여기서 바로 GPU 메모리에 있는 실제 상수 버퍼가 갱신되지 않는다.
	// 내부 캐시가 갱신되고 실질적인 갱신은 렌더링패스를 수행할때 일어난다. // 한꺼번에 모아서 갱신하기 위해
	// 만약에 3차원 벡터를 사용할 경우 // ->SetRawValue(&mEyePos, 0, sizeof(XMFLOAT3)) 처럼 사용한다. 
	// 받을때 역시 AsVector와 같은 형식없이 사용한다.
	mfxWorldViewProj->SetMatrix(reinterpret_cast<float*>(&worldViewProj));

	// 태크닉 변수를 설명해주는 객체를 얻는다.
    D3DX11_TECHNIQUE_DESC techDesc;
    mTech->GetDesc( &techDesc );

	// 패스의 수만큼 순회한다.
    for(UINT p = 0; p < techDesc.Passes; ++p)
    {

		/*GetPassByIndex : 주어진 인덱스에 해당하는 패스를 나타내는 ID3DX11EffectPass인터페이를 반환해준다.*/
		/*
		Apply : 
		1. GPU 메모리에 저장된 상수버퍼를 새 변수 값으로 갱신
		2. 패스에 설정된 쉐이더 프로그램들을 파이프라인에 묶는다.
		3. 패스에 설정된 렌더상태 적용
		// 두번째 매개변수는 패스가 사용할 장치문맥을 가리키는 포인터
		*/

		// 보통적용하기 전에 상수버퍼를 설정해주고 여러가지 작업을 해준다.
        mTech->GetPassByIndex(p)->Apply(0, md3dImmediateContext);
        
		// 36 indices for the box.
		/*
		1. 그릴 인덱스수
		2. 인덱스 시작 위치
		3. 정점들을 가져오기 전에 이 그리기 호출에서 사용할 인덱스에 더해지는 정수값
		// 여러가지 버텍스 버퍼를 합친다고 생각했을때 기준 버텍스의 위치를 알아야 원하는 범위의 버텍스들에 대해서 그릴수 있다.
		// 예를들어 구와 박스가 합쳐져있는 버퍼에서 박스를 그릴때 박스의 첫번째 버텍스를 설정해주면된다.
		*/
		md3dImmediateContext->DrawIndexed(36, 0, 0);
    }

	HR(mSwapChain->Present(0, 0));
}

void BoxApp::OnMouseDown(WPARAM btnState, int x, int y)
{
	mLastMousePos.x = x;
	mLastMousePos.y = y;

	SetCapture(mhMainWnd);
}

void BoxApp::OnMouseUp(WPARAM btnState, int x, int y)
{
	ReleaseCapture();
}

void BoxApp::OnMouseMove(WPARAM btnState, int x, int y)
{
	if( (btnState & MK_LBUTTON) != 0 )
	{
		// Make each pixel correspond to a quarter of a degree.
		float dx = XMConvertToRadians(0.25f*static_cast<float>(x - mLastMousePos.x));
		float dy = XMConvertToRadians(0.25f*static_cast<float>(y - mLastMousePos.y));

		// Update angles based on input to orbit camera around box.
		mTheta += dx;
		mPhi   += dy;

		// Restrict the angle mPhi.
		mPhi = MathHelper::Clamp(mPhi, 0.1f, MathHelper::Pi-0.1f);
	}
	else if( (btnState & MK_RBUTTON) != 0 )
	{
		// Make each pixel correspond to 0.005 unit in the scene.
		float dx = 0.005f*static_cast<float>(x - mLastMousePos.x);
		float dy = 0.005f*static_cast<float>(y - mLastMousePos.y);

		// Update the camera radius based on input.
		mRadius += dx - dy;

		// Restrict the radius.
		mRadius = MathHelper::Clamp(mRadius, 3.0f, 15.0f);
	}

	mLastMousePos.x = x;
	mLastMousePos.y = y;
}

void BoxApp::BuildGeometryBuffers()
{
	// Create vertex buffer
	// 버텍스 버퍼를 사용하는데 형식은
	// 	XMFLOAT3 Pos; XMFLOAT4 Color;
    Vertex vertices[] =
    {
		{ XMFLOAT3(-1.0f, -1.0f, -1.0f), (const float*)&Colors::White   },
		{ XMFLOAT3(-1.0f, +1.0f, -1.0f), (const float*)&Colors::Black   },
		{ XMFLOAT3(+1.0f, +1.0f, -1.0f), (const float*)&Colors::Red     },
		{ XMFLOAT3(+1.0f, -1.0f, -1.0f), (const float*)&Colors::Green   },
		{ XMFLOAT3(-1.0f, -1.0f, +1.0f), (const float*)&Colors::Blue    },
		{ XMFLOAT3(-1.0f, +1.0f, +1.0f), (const float*)&Colors::Yellow  },
		{ XMFLOAT3(+1.0f, +1.0f, +1.0f), (const float*)&Colors::Cyan    },
		{ XMFLOAT3(+1.0f, -1.0f, +1.0f), (const float*)&Colors::Magenta }
    };
	{/*생성할 버퍼를 서솔하는 객체*/}
    D3D11_BUFFER_DESC vbd;
	// 변경하지 않기 때문에 변하지 않도록 해주었다 // GPU에서 읽기만 제공 // 최적화
    vbd.Usage = D3D11_USAGE_IMMUTABLE;
	// 버텍스 총갯수가 8개이므로 이렇게 설정
    vbd.ByteWidth = sizeof(Vertex) * 8;
	// 버텍스 바인드 플래그 설정
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
	// CPU가 접근하지 않도록 설정 // CPU접근은 최소화하는 편이 좋다 // Dynamic / Staging 으로 Usage를 맞춰야 한다.
    vbd.CPUAccessFlags = 0;
	// 정점버퍼에서 사용 X
    vbd.MiscFlags = 0;
	//  구조적버퍼에 저장된 원소 하나의 크기
	vbd.StructureByteStride = 0;

	{/*초기화에 사용할 자료를 서술하는 객체*/}
    D3D11_SUBRESOURCE_DATA vinitData;
    vinitData.pSysMem = vertices;

    HR(md3dDevice->CreateBuffer
	(
		// 생성할 버퍼를 서술하는 구조체
		&vbd, 
		// 버퍼를 초기화하는데 사용할 자료
		&vinitData, 
		// 생성된 버퍼가 여기 새팅
		&mBoxVB
	)
	);


	// Create the index buffer
	// 인덱스 버퍼를 만들어준다.
	UINT indices[] = {
		// front face
		0, 1, 2,
		0, 2, 3,

		// back face
		4, 6, 5,
		4, 7, 6,

		// left face
		4, 5, 1,
		4, 1, 0,

		// right face
		3, 2, 6,
		3, 6, 7,

		// top face
		1, 5, 6,
		1, 6, 2,

		// bottom face
		4, 0, 3, 
		4, 3, 7
	};

	{/*생성할 버퍼를 서솔하는 객체*/}
	D3D11_BUFFER_DESC ibd;
	// 불변 플래그
    ibd.Usage = D3D11_USAGE_IMMUTABLE;
    // 총 바이트수 // 여기선 삼각형 12개 필요 > 36개
	ibd.ByteWidth = sizeof(UINT) * 36;
	// 인덱스 버퍼로 바인드 플래그 설정
    ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
	// CPU 접근 불가
    ibd.CPUAccessFlags = 0;
	// 인덱스 버퍼에서 사용X
    ibd.MiscFlags = 0;
	// 구조체버퍼에서 사용
	ibd.StructureByteStride = 0;
	{/*초기화에 사용할 자료를 서술하는 객체*/}
    D3D11_SUBRESOURCE_DATA iinitData;
    iinitData.pSysMem = indices;

	// 앞서 만들어주었던 것으로 최종 인덱스 버퍼를 생성
    HR(md3dDevice->CreateBuffer(&ibd, &iinitData, &mBoxIB));
}
 
void BoxApp::BuildFX()
{
	DWORD shaderFlags = 0;
#if defined( DEBUG ) || defined( _DEBUG )
	// 디버그모드에서 컴파일
    shaderFlags |= D3D10_SHADER_DEBUG;
	// 컴파일시 최적화를 사용하지 않음
	shaderFlags |= D3D10_SHADER_SKIP_OPTIMIZATION;
#endif
 
	ID3D10Blob* compiledShader = 0;
	ID3D10Blob* compilationMsgs = 0;

	HRESULT hr = D3DX11CompileFromFile
	(
		// 컴파일할 쉐이더 소스 코드를 담고 있는 .fx파일 이름
		L"FX/color.fx",
		
		// NULL
		0,
		// NULL
		0,

		// 쉐이더 프로그램의 진입점(쉐이더 주 함수의 이름)
		// 쉐이더 프로그램들을 개별적으로 컴파일 할 때만 쓰인다.
		// 효과 프레임워크를 사용하는 경우 효과 파일에 정의된 기법 패스들에 쉐이더 진입정 정의 되어 있음 // 설정 X
		0,

		// 쉐이더 버전
		"fx_5_0",

		// 쉐이더 코드의 컴파일 방식에 영향을 미치는 플래그 지정
		shaderFlags, 

		// NULL
		0,

		// 쉐이더를 비동기적으로 컴파일하기 위한 옵션
		0,

		// 컴파일된 쉐이더를 당믄 ID3D10Blob 구조체를 가리키는 포인터
		&compiledShader,

		//컴파일 오류시 오류 메시지를 담은 문자열을 담은 IDI3D10Blob구조체를 가리키는 포인터를 돌려줌
		&compilationMsgs,

		// 비동기 컴파일 시 오류코드를 조회하는데 사용 // 위 비동기 변수 NULL지정했다면 여기도 NULL
		0
	);

	// compilationMsgs can store errors or warnings.
	// 오류 메시지가 있으면 릴리즈
	if( compilationMsgs != 0 )
	{
		MessageBoxA(0, (char*)compilationMsgs->GetBufferPointer(), 0, 0);
		ReleaseCOM(compilationMsgs);
	}

	// Even if there are no compilationMsgs, check to make sure there were no other errors.
	if(FAILED(hr))
	{
		DXTrace((const WCHAR *)__FILE__, (DWORD)__LINE__, hr, L"D3DX11CompileFromFile", true);
	}

	/*
	ID3D10Blob는 2가지 함수 제공
	1. GetBufferPointer : 자료에 대한 void * 를 돌려준다.
	2. GetBufferSize : 메모리 블록의 바이트 단위 크기를 돌려준다.
	*/

	// 효과파일의 쉐이더들을 성공적으로 컴파일했다면 컴파일 결과물을 가지고
	// ID3DXEffect11인터페이스를 생성한다.

	HR(D3DX11CreateEffectFromMemory(
		// 컴파일된 효과 자료를 가리키는 포인터
		compiledShader->GetBufferPointer(), 
		// 컴파일된 효과 자료의 바이트 단위 크기
		compiledShader->GetBufferSize(), 
		// 플래그 // 쉐이더 컴파일시 NULL로 지정한 부분이므로 여기서도 NULL
		0,
		// 장치
		md3dDevice,
		// 생성된 효과 파일을 가리키는 포인터를 돌려준다.
		&mFX
	)
	);

	// Done with compiled shader.
	// 컴파일된 쉐이더 자료를 다 사용했으므로 해제
	// 비용이 크기 때문에 시작할때 해주어야한다.
	ReleaseCOM(compiledShader);

	// 상수 버퍼 변수들 외에 렌더링을 수행하려면 효과 객체에 있는 기법 객체를 가리키는 포인터도 얻어준다.
	mTech    = mFX->GetTechniqueByName("ColorTech");

	// 상수버퍼의 변수에 대한 포인터를 얻는 방식 // 이름으로 찾아준후 어떤형식으로 받을지 정한다.
	// MatrixVariable
	mfxWorldViewProj = mFX->GetVariableByName("gWorldViewProj")->AsMatrix();
}

void BoxApp::BuildVertexLayout()
{
	// Create the vertex input layout.

	// 레이아웃
	//정점 구조체를 정의했다면 그 정점 구조체의 각 성분이 어떤 용도인지 Direct3D에게 알려주어야 한다.
	
	D3D11_INPUT_ELEMENT_DESC vertexDesc[] =
	{
		/*
		1. 성분에 부여된 문자열 이름 // 이 이름은 정점쉐이더에서 매칭됨 POSITION , 1 => POSITION1
		2. 인덱스를 붙일 수 있다.
		3. 정점 성분의 자료형식을 나타냄
		4. 이 성분의 자료가 공급될 정점 버퍼 슬롯의 인덱스 // 16개 지원 0-15
		5. 같은 입력 슬롯에 대해서 오프셋을 지정해서 어디서 어디까지 그 성분이 쓰이는지 알려준다.
		6. 현재는 버텍스 데이터로 지정했지만 나중에 인스턴싱에서 바뀐다.
		7. 인스턴싱 관련 변수
		*/
		{"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
		{"COLOR",    0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0}
	};

	// Create the input layout
    D3DX11_PASS_DESC passDesc;
    mTech->GetPassByIndex(0)->GetDesc(&passDesc);
	HR(md3dDevice->CreateInputLayout(vertexDesc, 2, passDesc.pIAInputSignature, 
		passDesc.IAInputSignatureSize, &mInputLayout));
}
 