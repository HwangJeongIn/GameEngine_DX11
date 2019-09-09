//***************************************************************************************
// PickingDemo.cpp by Frank Luna (C) 2011 All Rights Reserved.
//
// Demonstrates picking.
//
// Controls:
//		Hold the left mouse button down and move the mouse to rotate.
//      Hold the right mouse button down to zoom in and out.
//
//      Hold '1' for wireframe mode.
//
//***************************************************************************************

#include "d3dApp.h"
#include "d3dx11Effect.h"
#include "GeometryGenerator.h"
#include "MathHelper.h"
#include "LightHelper.h"
#include "Effects.h"
#include "Vertex.h"
#include "Camera.h"
#include "RenderStates.h"
#include "xnacollision.h"

class PickingApp : public D3DApp 
{
public:
	PickingApp(HINSTANCE hInstance);
	~PickingApp();

	bool Init();
	void OnResize();
	void UpdateScene(float dt);
	void DrawScene(); 

	void OnMouseDown(WPARAM btnState, int x, int y);
	void OnMouseUp(WPARAM btnState, int x, int y);
	void OnMouseMove(WPARAM btnState, int x, int y);

private:
	void BuildMeshGeometryBuffers();
	void Pick(int sx, int sy);

private:

	ID3D11Buffer* mMeshVB;
	ID3D11Buffer* mMeshIB;

	// Keep system memory copies of the Mesh geometry for picking.
	std::vector<Vertex::Basic32> mMeshVertices;
	std::vector<UINT> mMeshIndices;

	XNA::AxisAlignedBox mMeshBox;

	DirectionalLight mDirLights[3];
	Material mMeshMat;
	Material mPickedTriangleMat;

	// Define transformations from local spaces to world space.
	XMFLOAT4X4 mMeshWorld;

	UINT mMeshIndexCount;

	UINT mPickedTriangle;

	Camera mCam;

	POINT mLastMousePos;
};

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE prevInstance,
				   PSTR cmdLine, int showCmd)
{
	// Enable run-time memory check for debug builds.
#if defined(DEBUG) | defined(_DEBUG)
	_CrtSetDbgFlag( _CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF );
#endif

	PickingApp theApp(hInstance);
	
	if( !theApp.Init() )
		return 0;
	
	return theApp.Run();
}
 

PickingApp::PickingApp(HINSTANCE hInstance)
: D3DApp(hInstance), mMeshVB(0), mMeshIB(0), mMeshIndexCount(0), mPickedTriangle(-1)
{
	mMainWndCaption = L"Picking Demo";
	
	mLastMousePos.x = 0;
	mLastMousePos.y = 0;

	mCam.SetPosition(0.0f, 2.0f, -15.0f);

	XMMATRIX MeshScale = XMMatrixScaling(0.5f, 0.5f, 0.5f);
	XMMATRIX MeshOffset = XMMatrixTranslation(0.0f, 1.0f, 0.0f);
	XMStoreFloat4x4(&mMeshWorld, XMMatrixMultiply(MeshScale, MeshOffset));

	mDirLights[0].Ambient  = XMFLOAT4(0.2f, 0.2f, 0.2f, 1.0f);
	mDirLights[0].Diffuse  = XMFLOAT4(0.5f, 0.5f, 0.5f, 1.0f);
	mDirLights[0].Specular = XMFLOAT4(0.5f, 0.5f, 0.5f, 1.0f);
	mDirLights[0].Direction = XMFLOAT3(0.57735f, -0.57735f, 0.57735f);

	mDirLights[1].Ambient  = XMFLOAT4(0.0f, 0.0f, 0.0f, 1.0f);
	mDirLights[1].Diffuse  = XMFLOAT4(0.20f, 0.20f, 0.20f, 1.0f);
	mDirLights[1].Specular = XMFLOAT4(0.25f, 0.25f, 0.25f, 1.0f);
	mDirLights[1].Direction = XMFLOAT3(-0.57735f, -0.57735f, 0.57735f);

	mDirLights[2].Ambient  = XMFLOAT4(0.0f, 0.0f, 0.0f, 1.0f);
	mDirLights[2].Diffuse  = XMFLOAT4(0.2f, 0.2f, 0.2f, 1.0f);
	mDirLights[2].Specular = XMFLOAT4(0.0f, 0.0f, 0.0f, 1.0f);
	mDirLights[2].Direction = XMFLOAT3(0.0f, -0.707f, -0.707f);

	mMeshMat.Ambient  = XMFLOAT4(0.4f, 0.4f, 0.4f, 1.0f);
	mMeshMat.Diffuse  = XMFLOAT4(0.8f, 0.8f, 0.8f, 1.0f);
	mMeshMat.Specular = XMFLOAT4(0.8f, 0.8f, 0.8f, 16.0f);

	mPickedTriangleMat.Ambient  = XMFLOAT4(0.0f, 0.8f, 0.4f, 1.0f);
	mPickedTriangleMat.Diffuse  = XMFLOAT4(0.0f, 0.8f, 0.4f, 1.0f);
	mPickedTriangleMat.Specular = XMFLOAT4(0.0f, 0.0f, 0.0f, 16.0f);
}

PickingApp::~PickingApp()
{
	ReleaseCOM(mMeshVB);
	ReleaseCOM(mMeshIB);

	Effects::DestroyAll();
	InputLayouts::DestroyAll(); 
}

bool PickingApp::Init()
{
	if(!D3DApp::Init())
		return false;

	// Must init Effects first since InputLayouts depend on shader signatures.
	Effects::InitAll(md3dDevice);
	InputLayouts::InitAll(md3dDevice);
	RenderStates::InitAll(md3dDevice);

	BuildMeshGeometryBuffers();

	return true;
}

void PickingApp::OnResize()
{
	D3DApp::OnResize();

	mCam.SetLens(0.25f*MathHelper::Pi, AspectRatio(), 1.0f, 1000.0f);
}

void PickingApp::UpdateScene(float dt)
{
	//
	// Control the camera.
	//
	if( GetAsyncKeyState('W') & 0x8000 )
		mCam.Walk(10.0f*dt);

	if( GetAsyncKeyState('S') & 0x8000 )
		mCam.Walk(-10.0f*dt);

	if( GetAsyncKeyState('A') & 0x8000 )
		mCam.Strafe(-10.0f*dt);

	if( GetAsyncKeyState('D') & 0x8000 )
		mCam.Strafe(10.0f*dt);
}

void PickingApp::DrawScene()
{
	md3dImmediateContext->ClearRenderTargetView(mRenderTargetView, reinterpret_cast<const float*>(&Colors::Silver));
	md3dImmediateContext->ClearDepthStencilView(mDepthStencilView, D3D11_CLEAR_DEPTH|D3D11_CLEAR_STENCIL, 1.0f, 0);

	md3dImmediateContext->IASetInputLayout(InputLayouts::Basic32);
    md3dImmediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
 
	UINT stride = sizeof(Vertex::Basic32);
    UINT offset = 0;

	mCam.UpdateViewMatrix();
 
	XMMATRIX view     = mCam.View();
	XMMATRIX proj     = mCam.Proj();
	XMMATRIX viewProj = mCam.ViewProj();


	

	// Set per frame constants.
	Effects::BasicFX->SetDirLights(mDirLights);
	Effects::BasicFX->SetEyePosW(mCam.GetPosition());
 
	ID3DX11EffectTechnique* activeMeshTech = Effects::BasicFX->Light3Tech;

	D3DX11_TECHNIQUE_DESC techDesc;
	activeMeshTech->GetDesc( &techDesc );
	for(UINT p = 0; p < techDesc.Passes; ++p)
    {
		// Draw the Mesh.

		if( GetAsyncKeyState('1') & 0x8000 )
			md3dImmediateContext->RSSetState(RenderStates::WireframeRS);

		md3dImmediateContext->IASetVertexBuffers(0, 1, &mMeshVB, &stride, &offset);
		md3dImmediateContext->IASetIndexBuffer(mMeshIB, DXGI_FORMAT_R32_UINT, 0);

		XMMATRIX world = XMLoadFloat4x4(&mMeshWorld);
		XMMATRIX worldInvTranspose = MathHelper::InverseTranspose(world);
		XMMATRIX worldViewProj = world*view*proj;

		Effects::BasicFX->SetWorld(world);
		Effects::BasicFX->SetWorldInvTranspose(worldInvTranspose);
		Effects::BasicFX->SetWorldViewProj(worldViewProj);
		Effects::BasicFX->SetMaterial(mMeshMat);

		activeMeshTech->GetPassByIndex(p)->Apply(0, md3dImmediateContext);
		md3dImmediateContext->DrawIndexed(mMeshIndexCount, 0, 0);

		// Restore default
		md3dImmediateContext->RSSetState(0);

		// Draw just the picked triangle again with a different material to highlight it.
		// 선택된 삼각형을 다른 재질로 그려준다.
		if(mPickedTriangle != -1)
		{
			// Change depth test from < to <= so that if we draw the same triangle twice, it will still pass
			// the depth test.  This is because we redraw the picked triangle with a different material
			// to highlight it.  
			// 같은 삼각형을 두번 그리는 것이므로 깊이 판정을  < 에서 <= 로 바꾼다
			// 그래야 삼각형이 깊이 판정을 통과 / 삼각형을 두번 그리는 이유는 강조하기 위해서
			md3dImmediateContext->OMSetDepthStencilState(RenderStates::LessEqualDSS, 0);

			Effects::BasicFX->SetMaterial(mPickedTriangleMat);
			activeMeshTech->GetPassByIndex(p)->Apply(0, md3dImmediateContext);
			// 삼각형 인덱스만큼 띄워주고 3개를 그려준다.
			md3dImmediateContext->DrawIndexed(3, 3*mPickedTriangle, 0);

			// restore default
			md3dImmediateContext->OMSetDepthStencilState(0, 0);
		}
	}

	


	HR(mSwapChain->Present(0, 0));
}

void PickingApp::OnMouseDown(WPARAM btnState, int x, int y)
{
	if( (btnState & MK_LBUTTON) != 0 )
	{
		mLastMousePos.x = x;
		mLastMousePos.y = y;

		SetCapture(mhMainWnd);
	}
	else if( (btnState & MK_RBUTTON) != 0 )
	{
		Pick(x, y);
	}
}

void PickingApp::OnMouseUp(WPARAM btnState, int x, int y)
{
	ReleaseCapture();
}

void PickingApp::OnMouseMove(WPARAM btnState, int x, int y)
{
	if( (btnState & MK_LBUTTON) != 0 )
	{
		// Make each pixel correspond to a quarter of a degree.
		float dx = XMConvertToRadians(0.25f*static_cast<float>(x - mLastMousePos.x));
		float dy = XMConvertToRadians(0.25f*static_cast<float>(y - mLastMousePos.y));

		mCam.Pitch(dy);
		mCam.RotateY(dx);
	}

	mLastMousePos.x = x;
	mLastMousePos.y = y;
}
 
void PickingApp::BuildMeshGeometryBuffers()
{
	std::ifstream fin("Models/car.txt");
	
	if(!fin)
	{
		MessageBox(0, L"Models/car.txt not found.", 0, 0);
		return;
	}

	UINT vcount = 0;
	UINT tcount = 0;
	std::string ignore;

	fin >> ignore >> vcount;
	fin >> ignore >> tcount;
	fin >> ignore >> ignore >> ignore >> ignore;
	
	XMFLOAT3 vMinf3(+MathHelper::Infinity, +MathHelper::Infinity, +MathHelper::Infinity);
	XMFLOAT3 vMaxf3(-MathHelper::Infinity, -MathHelper::Infinity, -MathHelper::Infinity);
	
	XMVECTOR vMin = XMLoadFloat3(&vMinf3);
	XMVECTOR vMax = XMLoadFloat3(&vMaxf3);
	mMeshVertices.resize(vcount);
	for(UINT i = 0; i < vcount; ++i)
	{
		fin >> mMeshVertices[i].Pos.x >> mMeshVertices[i].Pos.y >> mMeshVertices[i].Pos.z;
		fin >> mMeshVertices[i].Normal.x >> mMeshVertices[i].Normal.y >> mMeshVertices[i].Normal.z;
		
		XMVECTOR P = XMLoadFloat3(&mMeshVertices[i].Pos);
		
		vMin = XMVectorMin(vMin, P);
		vMax = XMVectorMax(vMax, P);
	}
	
	// 메쉬의 로컬공간내에서 바운딩박스를 씌워준다.
	XMStoreFloat3(&mMeshBox.Center, 0.5f*(vMin+vMax));
	XMStoreFloat3(&mMeshBox.Extents, 0.5f*(vMax-vMin));

	fin >> ignore;
	fin >> ignore;
	fin >> ignore;

	mMeshIndexCount = 3*tcount;
	mMeshIndices.resize(mMeshIndexCount);
	for(UINT i = 0; i < tcount; ++i)
	{
		fin >> mMeshIndices[i*3+0] >> mMeshIndices[i*3+1] >> mMeshIndices[i*3+2];
	}

	fin.close();

    D3D11_BUFFER_DESC vbd;
    vbd.Usage = D3D11_USAGE_IMMUTABLE;
	vbd.ByteWidth = sizeof(Vertex::Basic32) * vcount;
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    vbd.CPUAccessFlags = 0;
    vbd.MiscFlags = 0;
    D3D11_SUBRESOURCE_DATA vinitData;
    vinitData.pSysMem = &mMeshVertices[0];
    HR(md3dDevice->CreateBuffer(&vbd, &vinitData, &mMeshVB));

	//
	// Pack the indices of all the meshes into one index buffer.
	//

	D3D11_BUFFER_DESC ibd;
    ibd.Usage = D3D11_USAGE_IMMUTABLE;
	ibd.ByteWidth = sizeof(UINT) * mMeshIndexCount;
    ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
    ibd.CPUAccessFlags = 0;
    ibd.MiscFlags = 0;
    D3D11_SUBRESOURCE_DATA iinitData;
	iinitData.pSysMem = &mMeshIndices[0];
    HR(md3dDevice->CreateBuffer(&ibd, &iinitData, &mMeshIB));
}

void PickingApp::Pick(int sx, int sy)
{
	// 먼저 투영행렬을 가지고 온다. 이 투영행렬의 00 11 성분이 필요하다
	XMMATRIX P = mCam.Proj();

	// Compute picking ray in view space.
	// 뷰포트에서 뷰 스페이스로의 변환을 시작한다.
	// 이는 각각 x와 y의 기울기인데 최종적으로 z = 1로 설정되면 반직선을 만들 수 있다.
	float vx = (+2.0f*sx/mClientWidth  - 1.0f)/P(0,0);
	float vy = (-2.0f*sy/mClientHeight + 1.0f)/P(1,1);

	// Ray definition in view space.
	XMVECTOR rayOrigin = XMVectorSet(0.0f, 0.0f, 0.0f, 1.0f);
	XMVECTOR rayDir    = XMVectorSet(vx, vy, 1.0f, 0.0f);

	// Tranform ray to local space of Mesh.
	// 만들어진 반직선을 메쉬 로컬스페이스로 보내야 한다.
	// 그러기 위해서는 기존 뷰스페이스에서 월드공간으로 변환한후 월드공간에서 메쉬 공간으로 들어가야 한다.
	XMMATRIX V = mCam.View();
	XMMATRIX invView = XMMatrixInverse(&XMMatrixDeterminant(V), V);

	XMMATRIX W = XMLoadFloat4x4(&mMeshWorld);
	XMMATRIX invWorld = XMMatrixInverse(&XMMatrixDeterminant(W), W);

	// 뷰 >(뷰행렬의 역행렬)> 월드 >(메쉬의 월드 역행렬)> 메쉬
	// 메쉬 >(메쉬의 월드 행렬)> 월드 >(뷰행렬)> 뷰 // 이방법을 쓰지 않는 이유는 메쉬에 많은 정점들에대해서 적용해야하기 때문에 성능이 떨어진다.
	XMMATRIX toLocal = XMMatrixMultiply(invView, invWorld);

	// 점에 대해서는 XMVector3TransformCoord // w = 1
	rayOrigin = XMVector3TransformCoord(rayOrigin, toLocal);
	// 방향에 대해서는 XMVector3TransformNormal // w = 0
	rayDir = XMVector3TransformNormal(rayDir, toLocal);

	// Make the ray direction unit length for the intersection tests.
	// 교차 판정을 위해 방향을 정규화시켜준다
	rayDir = XMVector3Normalize(rayDir);

	// If we hit the bounding box of the Mesh, then we might have picked a Mesh triangle,
	// so do the ray/triangle tests.
	//
	// 반직선이 메쉬의 바운딩 박스를 타격한다면 우리는 메쉬의 삼각형들을 돌면서 반직선과 삼각형 테스트를 한다.

	// If we did not hit the bounding box, then it is impossible that we hit 
	// the Mesh, so do not waste effort doing ray/triangle tests.
	// 바운딩 박스를 치지않았다면 테스트하지 않는다.

	// 러프하게 바운딩박스 테스트 > 실제 삼각형들에 대해서 확인

	// Assume we have not picked anything yet, so init to -1.
	// 만약 우리가 아무것도 찾지 못했다면 -1로 설정
	mPickedTriangle = -1;
	float tmin = 0.0f;

	// 바운딩박스 충돌 체크 // 현재 반직선이 메쉬 로컬공간안으로 들어왔기 때문에 가능
	if(XNA::IntersectRayAxisAlignedBox(rayOrigin, rayDir, &mMeshBox, &tmin))
	{
		// Find the nearest ray/triangle intersection.
		// 제일 가까운 ray/triangle 교차점을 찾는다.
		tmin = MathHelper::Infinity;
		for(UINT i = 0; i < mMeshIndices.size()/3; ++i)
		{
			// Indices for this triangle.
			UINT i0 = mMeshIndices[i*3+0];
			UINT i1 = mMeshIndices[i*3+1];
			UINT i2 = mMeshIndices[i*3+2];

			// Vertices for this triangle.
			// 메시의 기하구조의 본사본을 시스템 메모리에 유지해야 한다.
			XMVECTOR v0 = XMLoadFloat3(&mMeshVertices[i0].Pos);
			XMVECTOR v1 = XMLoadFloat3(&mMeshVertices[i1].Pos);
			XMVECTOR v2 = XMLoadFloat3(&mMeshVertices[i2].Pos);

			// We have to iterate over all the triangles in order to find the nearest intersection.
			// 모든 삼각형에 대해서 순회해야한다 // 가장 가까운 교차점을 찾기 위해서
			float t = 0.0f;

			if(XNA::IntersectRayTriangle(rayOrigin, rayDir, v0, v1, v2, &t))
			{
				// 더 가까운 거리에 있는 삼각형이라면 갱신후 초기화 시켜준다.
				if( t < tmin )
				{
					// This is the new nearest picked triangle.
					tmin = t;
					mPickedTriangle = i;
				}
			}
		}
	}
}