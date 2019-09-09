#include "Vertex.h"
#include "Effects.h"

#pragma region InputLayoutDesc

const D3D11_INPUT_ELEMENT_DESC InputLayoutDesc::InstancedBasic32[8] = 
{
	// �����ڷ�� ���� 0���� �ְ� �ν��Ͻ��� �ڷ�� ����1���� �־���.
	{"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
	{"NORMAL",   0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0},
	{"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D11_INPUT_PER_VERTEX_DATA, 0},
	/*
	������ �θ���� �ν��Ͻ̰� ������ �ִ�.
	D3D11_INPUT_CLASSIFICATION InputSlotClass;
    UINT InstanceDataStepRate;
	ù��°�� �ν��Ͻ��� �ڷ� or ������ �ڷ� �����ϴ� �� // D3D11_INPUT_PER_INSTANCE_DATA ������ְ� 
	�ι�°�� �ν��Ͻ��� �ڷ� ���� �ϳ��� �׸� �ν��Ͻ� ���� // 1�϶��� 1:1 ����
	*/
	{ "WORLD", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 0, D3D11_INPUT_PER_INSTANCE_DATA, 1 },
    { "WORLD", 1, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 16, D3D11_INPUT_PER_INSTANCE_DATA, 1 },
    { "WORLD", 2, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 32, D3D11_INPUT_PER_INSTANCE_DATA, 1 },
    { "WORLD", 3, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 48, D3D11_INPUT_PER_INSTANCE_DATA, 1 },
	{ "COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, 64,  D3D11_INPUT_PER_INSTANCE_DATA, 1 }
};

#pragma endregion

#pragma region InputLayouts

ID3D11InputLayout* InputLayouts::InstancedBasic32 = 0;

void InputLayouts::InitAll(ID3D11Device* device)
{
	D3DX11_PASS_DESC passDesc;

	//
	// InstancedBasic32
	//

	Effects::InstancedBasicFX->Light1Tech->GetPassByIndex(0)->GetDesc(&passDesc);
	HR(device->CreateInputLayout(InputLayoutDesc::InstancedBasic32, 8, passDesc.pIAInputSignature, 
		passDesc.IAInputSignatureSize, &InstancedBasic32));
}

void InputLayouts::DestroyAll()
{
	ReleaseCOM(InstancedBasic32);
}

#pragma endregion
