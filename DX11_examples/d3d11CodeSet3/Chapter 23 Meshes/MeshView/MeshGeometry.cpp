#include "MeshGeometry.h"

MeshGeometry::MeshGeometry()
	: mVB(0), mIB(0), 
	mIndexBufferFormat(DXGI_FORMAT_R16_UINT), 
	mVertexStride(0)
{
}

MeshGeometry::~MeshGeometry()
{
	ReleaseCOM(mVB);
	ReleaseCOM(mIB);
}

void MeshGeometry::SetIndices(ID3D11Device* device, const USHORT* indices, UINT count)
{
	D3D11_BUFFER_DESC ibd;
    ibd.Usage = D3D11_USAGE_IMMUTABLE;
    ibd.ByteWidth = sizeof(USHORT) * count;
    ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
    ibd.CPUAccessFlags = 0;
    ibd.MiscFlags = 0;
	ibd.StructureByteStride = 0;

    D3D11_SUBRESOURCE_DATA iinitData;
    iinitData.pSysMem = indices;

    HR(device->CreateBuffer(&ibd, &iinitData, &mIB));
}

void MeshGeometry::SetSubsetTable(std::vector<Subset>& subsetTable)
{
	mSubsetTable = subsetTable;
}

void MeshGeometry::Draw(ID3D11DeviceContext* dc, UINT subsetId)
{
    UINT offset = 0;
	// dc->IASetVertexBuffers(0, 1, &mVB, 0, 0);
	dc->IASetVertexBuffers(0, 1, &mVB, &mVertexStride, &offset);
	dc->IASetIndexBuffer(mIB, mIndexBufferFormat, 0);

	// 시작버텍스와 버텍스 카운트는 별로 상관없는듯
	dc->DrawIndexed(
		mSubsetTable[subsetId].FaceCount*3, 
		mSubsetTable[subsetId].FaceStart*3, 
		0);
}