//***************************************************************************************
// RenderStates.cpp by Frank Luna (C) 2011 All Rights Reserved.
//***************************************************************************************

#include "RenderStates.h"

ID3D11RasterizerState* RenderStates::WireframeRS     = 0;
ID3D11RasterizerState* RenderStates::NoCullRS        = 0;
ID3D11RasterizerState* RenderStates::CullClockwiseRS = 0;
	 
ID3D11BlendState*      RenderStates::AlphaToCoverageBS      = 0;
ID3D11BlendState*      RenderStates::TransparentBS          = 0;
ID3D11BlendState*      RenderStates::NoRenderTargetWritesBS = 0;

// 마킹하는 렌더상태 // 거울을 렌더링할때 깊이판정에 의해서 가려지는 경우 말고는 모두 들어온 값(1)로 변경한다.
ID3D11DepthStencilState* RenderStates::MarkMirrorDSS     = 0;
ID3D11DepthStencilState* RenderStates::DrawReflectionDSS = 0;
ID3D11DepthStencilState* RenderStates::NoDoubleBlendDSS  = 0;

void RenderStates::InitAll(ID3D11Device* device)
{
	//
	// WireframeRS
	//
	D3D11_RASTERIZER_DESC wireframeDesc;
	ZeroMemory(&wireframeDesc, sizeof(D3D11_RASTERIZER_DESC));
	wireframeDesc.FillMode = D3D11_FILL_WIREFRAME;
	wireframeDesc.CullMode = D3D11_CULL_BACK;
	wireframeDesc.FrontCounterClockwise = false;
	wireframeDesc.DepthClipEnable = true;

	HR(device->CreateRasterizerState(&wireframeDesc, &WireframeRS));

	//
	// NoCullRS
	//
	D3D11_RASTERIZER_DESC noCullDesc;
	ZeroMemory(&noCullDesc, sizeof(D3D11_RASTERIZER_DESC));
	noCullDesc.FillMode = D3D11_FILL_SOLID;
	noCullDesc.CullMode = D3D11_CULL_NONE;
	noCullDesc.FrontCounterClockwise = false;
	noCullDesc.DepthClipEnable = true;

	HR(device->CreateRasterizerState(&noCullDesc, &NoCullRS));

	//
	// CullClockwiseRS
	//

	// Note: Define such that we still cull backfaces by making front faces CCW.
	// If we did not cull backfaces, then we have to worry about the BackFace
	// property in the D3D11_DEPTH_STENCIL_DESC.
	
	// 반시계방향을 전면 삼각형으로 간주해서 후면삼각형들을 선별한다. // 원래는 시계방향이 앞면
	// 기존 면과 반대의 면이 뒷면으로 간주되어서 컬링된다
	D3D11_RASTERIZER_DESC cullClockwiseDesc;
	ZeroMemory(&cullClockwiseDesc, sizeof(D3D11_RASTERIZER_DESC));
	cullClockwiseDesc.FillMode = D3D11_FILL_SOLID;
	cullClockwiseDesc.CullMode = D3D11_CULL_BACK;
	cullClockwiseDesc.FrontCounterClockwise = true;
	cullClockwiseDesc.DepthClipEnable = true;

	HR(device->CreateRasterizerState(&cullClockwiseDesc, &CullClockwiseRS));

	//
	// AlphaToCoverageBS
	//

	D3D11_BLEND_DESC alphaToCoverageDesc = {0};
	alphaToCoverageDesc.AlphaToCoverageEnable = true;
	alphaToCoverageDesc.IndependentBlendEnable = false;
	alphaToCoverageDesc.RenderTarget[0].BlendEnable = false;
	alphaToCoverageDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;

	HR(device->CreateBlendState(&alphaToCoverageDesc, &AlphaToCoverageBS));

	//
	// TransparentBS
	//

	D3D11_BLEND_DESC transparentDesc = {0};
	transparentDesc.AlphaToCoverageEnable = false;
	transparentDesc.IndependentBlendEnable = false;

	transparentDesc.RenderTarget[0].BlendEnable = true;
	transparentDesc.RenderTarget[0].SrcBlend       = D3D11_BLEND_SRC_ALPHA;
	transparentDesc.RenderTarget[0].DestBlend      = D3D11_BLEND_INV_SRC_ALPHA;
	transparentDesc.RenderTarget[0].BlendOp        = D3D11_BLEND_OP_ADD;
	transparentDesc.RenderTarget[0].SrcBlendAlpha  = D3D11_BLEND_ONE;
	transparentDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
	transparentDesc.RenderTarget[0].BlendOpAlpha   = D3D11_BLEND_OP_ADD;
	transparentDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;

	HR(device->CreateBlendState(&transparentDesc, &TransparentBS));

	//
	// NoRenderTargetWritesBS
	//
	
	// 스텐실 버퍼에 가시적인 거울의 픽셀을 담기 위해서 후면 버퍼를 꺼놔야한다.

	D3D11_BLEND_DESC noRenderTargetWritesDesc = {0};
	noRenderTargetWritesDesc.AlphaToCoverageEnable = false;
	// 렌더타겟 첫번째 원소만 사용
	noRenderTargetWritesDesc.IndependentBlendEnable = false;

	noRenderTargetWritesDesc.RenderTarget[0].BlendEnable    = false;
	noRenderTargetWritesDesc.RenderTarget[0].SrcBlend       = D3D11_BLEND_ONE;
	noRenderTargetWritesDesc.RenderTarget[0].DestBlend      = D3D11_BLEND_ZERO;
	noRenderTargetWritesDesc.RenderTarget[0].BlendOp        = D3D11_BLEND_OP_ADD;
	noRenderTargetWritesDesc.RenderTarget[0].SrcBlendAlpha  = D3D11_BLEND_ONE;
	noRenderTargetWritesDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
	noRenderTargetWritesDesc.RenderTarget[0].BlendOpAlpha   = D3D11_BLEND_OP_ADD;

	// 모든값들에대해서 블록한다. // 즉 후면버퍼에 아무것도 그려지지않는다.
	noRenderTargetWritesDesc.RenderTarget[0].RenderTargetWriteMask = 0;

	HR(device->CreateBlendState(&noRenderTargetWritesDesc, &NoRenderTargetWritesBS));

	//
	// MarkMirrorDSS
	//
	// 거울 스텐실에 넣기

	// 깊이 스텐실 상태 정의
	D3D11_DEPTH_STENCIL_DESC mirrorDesc;
	// 깊이 판정 허용
	mirrorDesc.DepthEnable      = true;
	// 깊이 판정은 하되, 쓰기는 하지 않는다. // 0x00와 같이 생각하면될듯 // 이값일때 모든 값들은 &연산에서 통과하지 못한다.
	mirrorDesc.DepthWriteMask   = D3D11_DEPTH_WRITE_MASK_ZERO;
    // 깊이 판정을 할때는 작은게 그려지도록
	mirrorDesc.DepthFunc        = D3D11_COMPARISON_LESS;

	// 스텐실 판정 허용
    mirrorDesc.StencilEnable    = true;
	// 읽고 쓰는 스텐실 판정 마스킹하는값 없음
    mirrorDesc.StencilReadMask  = 0xff;
    mirrorDesc.StencilWriteMask = 0xff;

	// 앞면에 대해서
	// 스텐실성공 && 깊이실패 / 스텐실 실패 : 유지
	// 스텐실성공 : 들어온 레퍼런스 값으로 변경

	// 스텐실 판정에 대해서 항상 성공 
	// 거울을 특정적으로 렌더링하기 때문에 모두 허용한다. 
	// 단, 깊이판정에 의해서 거울을 가리는것은 걸러줘야 한다.
    
	mirrorDesc.FrontFace.StencilFailOp      = D3D11_STENCIL_OP_KEEP;
	mirrorDesc.FrontFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
	mirrorDesc.FrontFace.StencilPassOp      = D3D11_STENCIL_OP_REPLACE;
	mirrorDesc.FrontFace.StencilFunc        = D3D11_COMPARISON_ALWAYS;

	// We are not rendering backfacing polygons, so these settings do not matter.
	// 후면삼각형에 대해서는 따로 신경안써줘도 된다.
    mirrorDesc.BackFace.StencilFailOp       = D3D11_STENCIL_OP_KEEP;
	mirrorDesc.BackFace.StencilDepthFailOp  = D3D11_STENCIL_OP_KEEP;
	mirrorDesc.BackFace.StencilPassOp       = D3D11_STENCIL_OP_REPLACE;
	mirrorDesc.BackFace.StencilFunc         = D3D11_COMPARISON_ALWAYS;

	HR(device->CreateDepthStencilState(&mirrorDesc, &MarkMirrorDSS));

	//
	// DrawReflectionDSS
	//

	D3D11_DEPTH_STENCIL_DESC drawReflectionDesc;
	// 깊이 판정 허용
	drawReflectionDesc.DepthEnable      = true;
	// 깊이 버퍼 쓰기 활성화
	// 0xff와 같이 생각하면될듯 // 이값일때 모든 값들은 &연산에서 통과한다.
	drawReflectionDesc.DepthWriteMask   = D3D11_DEPTH_WRITE_MASK_ALL;
	drawReflectionDesc.DepthFunc        = D3D11_COMPARISON_LESS; 
	drawReflectionDesc.StencilEnable    = true;
    // 읽고 쓰는 스텐실 모든 비트에 대해서 허용
	drawReflectionDesc.StencilReadMask  = 0xff;
    drawReflectionDesc.StencilWriteMask = 0xff;

	// 모두 유지
	drawReflectionDesc.FrontFace.StencilFailOp      = D3D11_STENCIL_OP_KEEP;
	drawReflectionDesc.FrontFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
	drawReflectionDesc.FrontFace.StencilPassOp = D3D11_STENCIL_OP_KEEP;
	// 같을때 판정성공
	drawReflectionDesc.FrontFace.StencilFunc   = D3D11_COMPARISON_EQUAL;

	// We are not rendering backfacing polygons, so these settings do not matter.
	drawReflectionDesc.BackFace.StencilFailOp      = D3D11_STENCIL_OP_KEEP;
	drawReflectionDesc.BackFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
	drawReflectionDesc.BackFace.StencilPassOp = D3D11_STENCIL_OP_KEEP;
	drawReflectionDesc.BackFace.StencilFunc   = D3D11_COMPARISON_EQUAL;

	HR(device->CreateDepthStencilState(&drawReflectionDesc, &DrawReflectionDSS));

	//
	// NoDoubleBlendDSS
	//

	// 이중혼합을 방지

	D3D11_DEPTH_STENCIL_DESC noDoubleBlendDesc;
	// 거울예제처럼 반사된 해골이 거울에 가려질일이 없기 때문에 깊이 쓰기 허용
	noDoubleBlendDesc.DepthEnable      = true;
	noDoubleBlendDesc.DepthWriteMask   = D3D11_DEPTH_WRITE_MASK_ALL;
	noDoubleBlendDesc.DepthFunc        = D3D11_COMPARISON_LESS; 
	noDoubleBlendDesc.StencilEnable    = true;
    noDoubleBlendDesc.StencilReadMask  = 0xff;
    noDoubleBlendDesc.StencilWriteMask = 0xff;
	
	// 같으면 증가시켜서 더이상 스텐실 테스트를 통과하지 못한다.
	noDoubleBlendDesc.FrontFace.StencilFailOp      = D3D11_STENCIL_OP_KEEP;
	noDoubleBlendDesc.FrontFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
	noDoubleBlendDesc.FrontFace.StencilPassOp = D3D11_STENCIL_OP_INCR;
	noDoubleBlendDesc.FrontFace.StencilFunc   = D3D11_COMPARISON_EQUAL;

	// We are not rendering backfacing polygons, so these settings do not matter.
	noDoubleBlendDesc.BackFace.StencilFailOp      = D3D11_STENCIL_OP_KEEP;
	noDoubleBlendDesc.BackFace.StencilDepthFailOp = D3D11_STENCIL_OP_KEEP;
	noDoubleBlendDesc.BackFace.StencilPassOp = D3D11_STENCIL_OP_INCR;
	noDoubleBlendDesc.BackFace.StencilFunc   = D3D11_COMPARISON_EQUAL;

	HR(device->CreateDepthStencilState(&noDoubleBlendDesc, &NoDoubleBlendDSS));
}

void RenderStates::DestroyAll()
{
	ReleaseCOM(WireframeRS);
	ReleaseCOM(NoCullRS);
	ReleaseCOM(CullClockwiseRS);

	ReleaseCOM(AlphaToCoverageBS);
	ReleaseCOM(TransparentBS);
	ReleaseCOM(NoRenderTargetWritesBS);

	ReleaseCOM(MarkMirrorDSS);
	ReleaseCOM(DrawReflectionDSS);
	ReleaseCOM(NoDoubleBlendDSS);
}