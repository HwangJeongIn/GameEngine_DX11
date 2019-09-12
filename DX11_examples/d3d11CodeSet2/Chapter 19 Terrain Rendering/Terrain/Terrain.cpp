//***************************************************************************************
// Terrain.cpp by Frank Luna (C) 2011 All Rights Reserved.
//***************************************************************************************

#include "Terrain.h"
#include "Camera.h"
#include "LightHelper.h"
#include "Effects.h"
#include "Vertex.h"
#include <fstream>
#include <sstream>

Terrain::Terrain() : 
	mQuadPatchVB(0), 
	mQuadPatchIB(0), 
	mLayerMapArraySRV(0), 
	mBlendMapSRV(0), 
	mHeightMapSRV(0),
	mNumPatchVertices(0),
	mNumPatchQuadFaces(0),
	mNumPatchVertRows(0),
	mNumPatchVertCols(0)
{
	XMStoreFloat4x4(&mWorld, XMMatrixIdentity());

	mMat.Ambient  = XMFLOAT4(1.0f, 1.0f, 1.0f, 1.0f);
	mMat.Diffuse  = XMFLOAT4(1.0f, 1.0f, 1.0f, 1.0f);
	mMat.Specular = XMFLOAT4(0.0f, 0.0f, 0.0f, 64.0f);
	mMat.Reflect  = XMFLOAT4(0.0f, 0.0f, 0.0f, 1.0f);
}

Terrain::~Terrain()
{
	ReleaseCOM(mQuadPatchVB);
	ReleaseCOM(mQuadPatchIB);
	ReleaseCOM(mLayerMapArraySRV);
	ReleaseCOM(mBlendMapSRV);
	ReleaseCOM(mHeightMapSRV);
}

float Terrain::GetWidth()const
{
	// Total terrain width.
	// 여기서 하이트맵의 너비는 최대로 테셀레이션되었을 때의 버텍스 수 이다.
	return (mInfo.HeightmapWidth-1)*mInfo.CellSpacing;
}

float Terrain::GetDepth()const
{
	// Total terrain depth.
	// 여기서 하이트 맵의 깊이는 최대로 테셀레이션되었을 때의 버텍스 수 이다.
	return (mInfo.HeightmapHeight-1)*mInfo.CellSpacing;
}

float Terrain::GetHeight(float x, float z)const
{
	// Transform from terrain local space to "cell" space.
	// 이때 x z는 터레인좌표계안에 있다. 인덱스를 구하기위해서 터레인의 원점기준으로 바꿔준다. 원점이 0,0
	// 인덱스에 -가 없기 때문이다.
	// 그다음에 한칸당간격으로 나눈후 버림해서 왼쪽위 쿼드 기준으로 인덱스를 잡아준다.
	// ex> 12.1 인덱스 같은 값이 나온다.
	float c = (x + 0.5f*GetWidth()) /  mInfo.CellSpacing;
	float d = (z - 0.5f*GetDepth()) / -mInfo.CellSpacing;

	// Get the row and column we are in.
	int row = (int)floorf(d);
	int col = (int)floorf(c);

	// Grab the heights of the cell we are in.
	// A*--*B
	//  | /|
	//  |/ |
	// C*--*D
	// 왼쪽위 기준
	float A = mHeightmap[row*mInfo.HeightmapWidth + col];
	float B = mHeightmap[row*mInfo.HeightmapWidth + col + 1];
	float C = mHeightmap[(row+1)*mInfo.HeightmapWidth + col];
	float D = mHeightmap[(row+1)*mInfo.HeightmapWidth + col + 1];

	// Where we are relative to the cell.
	// 버렸던 인덱스 소수점을 복원
	float s = c - (float)col;
	float t = d - (float)row;

	// If upper triangle ABC.
	// 그 소수점을 더해서 왼쪽위 기준 삼각형인지 오른쪽아래 삼각형인지 정해준다.

	// 각각 보간
	if( s + t <= 1.0f)
	{
		float uy = B - A;
		float vy = C - A;
		return A + s*uy + t*vy;
	}
	else // lower triangle DCB.
	{
		float uy = C - D;
		float vy = B - D;
		return D + (1.0f-s)*uy + (1.0f-t)*vy;
	}
}

XMMATRIX Terrain::GetWorld()const
{
	return XMLoadFloat4x4(&mWorld);
}

void Terrain::SetWorld(CXMMATRIX M)
{
	XMStoreFloat4x4(&mWorld, M);
}

void Terrain::Init(ID3D11Device* device, ID3D11DeviceContext* dc, const InitInfo& initInfo)
{
	mInfo = initInfo;

	// Divide heightmap into patches such that each patch has CellsPerPatch.
	// 전체 하이트맵의 원소를 패치의 셀의갯수로 나눠서 몇행 몇열인지 알아낸다.
	mNumPatchVertRows = ((mInfo.HeightmapHeight-1) / CellsPerPatch) + 1;
	mNumPatchVertCols = ((mInfo.HeightmapWidth-1) / CellsPerPatch) + 1;

	// 총 패치의 버텍스들의 갯수와 패치면들의 갯수를 알아낸다.
	mNumPatchVertices  = mNumPatchVertRows*mNumPatchVertCols;
	mNumPatchQuadFaces = (mNumPatchVertRows-1)*(mNumPatchVertCols-1);

	// 하이트맵을 로딩한다.
	LoadHeightmap();

	// 일정한 값들이 잘려서 나오기 떄문에 평탄화 작업 // 주변 값들의 평균
	Smooth();

	// 모든 패치에 대한 최소경계와 최대경계를 구하는 함수이다.
	CalcAllPatchBoundsY();

	BuildQuadPatchVB(device);
	BuildQuadPatchIB(device);
	BuildHeightmapSRV(device);

	std::vector<std::wstring> layerFilenames;
	layerFilenames.push_back(mInfo.LayerMapFilename0);
	layerFilenames.push_back(mInfo.LayerMapFilename1);
	layerFilenames.push_back(mInfo.LayerMapFilename2);
	layerFilenames.push_back(mInfo.LayerMapFilename3);
	layerFilenames.push_back(mInfo.LayerMapFilename4);
	mLayerMapArraySRV = d3dHelper::CreateTexture2DArraySRV(device, dc, layerFilenames);

	HR(D3DX11CreateShaderResourceViewFromFile(device, 
		mInfo.BlendMapFilename.c_str(), 0, 0, &mBlendMapSRV, 0));
}

void Terrain::Draw(ID3D11DeviceContext* dc, const Camera& cam, DirectionalLight lights[3])
{
	dc->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_4_CONTROL_POINT_PATCHLIST);
	dc->IASetInputLayout(InputLayouts::Terrain);

	UINT stride = sizeof(Vertex::Terrain);
    UINT offset = 0;
    dc->IASetVertexBuffers(0, 1, &mQuadPatchVB, &stride, &offset);
	dc->IASetIndexBuffer(mQuadPatchIB, DXGI_FORMAT_R16_UINT, 0);

	XMMATRIX viewProj = cam.ViewProj();
	XMMATRIX world  = XMLoadFloat4x4(&mWorld);
	XMMATRIX worldInvTranspose = MathHelper::InverseTranspose(world);
	XMMATRIX worldViewProj = world*viewProj;

	XMFLOAT4 worldPlanes[6];
	// view proj행렬을 가지고 절두체 면들을 구해준다.
	ExtractFrustumPlanes(worldPlanes, viewProj);

	// Set per frame constants.
	Effects::TerrainFX->SetViewProj(viewProj);
	Effects::TerrainFX->SetEyePosW(cam.GetPosition());
	Effects::TerrainFX->SetDirLights(lights);
	Effects::TerrainFX->SetFogColor(Colors::Silver);
	Effects::TerrainFX->SetFogStart(15.0f);
	Effects::TerrainFX->SetFogRange(175.0f);
	// 최대 최소 거리 설정
	Effects::TerrainFX->SetMinDist(20.0f);
	Effects::TerrainFX->SetMaxDist(500.0f);
	// 최대 최소 테셀레이션 계수 설정
	Effects::TerrainFX->SetMinTess(0.0f);
	Effects::TerrainFX->SetMaxTess(6.0f);
	Effects::TerrainFX->SetTexelCellSpaceU(1.0f / mInfo.HeightmapWidth);
	Effects::TerrainFX->SetTexelCellSpaceV(1.0f / mInfo.HeightmapHeight);
	Effects::TerrainFX->SetWorldCellSpace(mInfo.CellSpacing);
	Effects::TerrainFX->SetWorldFrustumPlanes(worldPlanes);
	
	Effects::TerrainFX->SetLayerMapArray(mLayerMapArraySRV);
	Effects::TerrainFX->SetBlendMap(mBlendMapSRV);
	Effects::TerrainFX->SetHeightMap(mHeightMapSRV);

	Effects::TerrainFX->SetMaterial(mMat);

	ID3DX11EffectTechnique* tech = Effects::TerrainFX->Light1Tech;
    D3DX11_TECHNIQUE_DESC techDesc;
    tech->GetDesc( &techDesc );

    for(UINT i = 0; i < techDesc.Passes; ++i)
    {
        ID3DX11EffectPass* pass = tech->GetPassByIndex(i);
		pass->Apply(0, dc);

		dc->DrawIndexed(mNumPatchQuadFaces*4, 0, 0);
	}	

	// FX sets tessellation stages, but it does not disable them.  So do that here
	// to turn off tessellation.
	dc->HSSetShader(0, 0, 0);
	dc->DSSetShader(0, 0, 0);
}

void Terrain::LoadHeightmap()
{
	// A height for each vertex
	// 각 정점의 높이를 담는 배열
	// 8비트형식으로 저장되기 때문에 unsigned char형으로 받는다. // 0 - 255
	// 내부 높이과 너비값은 하드코딩으로 들어온다.
	std::vector<unsigned char> in( mInfo.HeightmapWidth * mInfo.HeightmapHeight );

	// Open the file.
	std::ifstream inFile;
	// binary형식으로 열어준다.
	inFile.open(mInfo.HeightMapFilename.c_str(), std::ios_base::binary);

	if(inFile)
	{
		// Read the RAW bytes.
		// 만약 파일이 열렸다면 읽어준다. // 기존 높이값 개수만큼 읽어준다.
		inFile.read((char*)&in[0], (std::streamsize)in.size());

		// Done with file.
		inFile.close();
	}

	// Copy the array data into a float array and scale it.
	mHeightmap.resize(mInfo.HeightmapHeight * mInfo.HeightmapWidth, 0);
	for(UINT i = 0; i < mInfo.HeightmapHeight * mInfo.HeightmapWidth; ++i)
	{
		// 기존에 읽었던 것들을 0 ~ 1사이로 변환시켜준다.
		mHeightmap[i] = (in[i] / 255.0f)*mInfo.HeightScale;
	}
}

void Terrain::Smooth()
{
	std::vector<float> dest( mHeightmap.size() );

	for(UINT i = 0; i < mInfo.HeightmapHeight; ++i)
	{
		for(UINT j = 0; j < mInfo.HeightmapWidth; ++j)
		{
			// 9개의 픽셀의 평균을 구해서  거친면을 평탄화 시킨다.
			dest[i*mInfo.HeightmapWidth+j] = Average(i,j);
		}
	}

	// Replace the old heightmap with the filtered one.
	// 최종적으로 하이트맵을 평탄화 하였다.
	mHeightmap = dest;
}

bool Terrain::InBounds(int i, int j)
{
	// True if ij are valid indices; false otherwise.
	// i j 로 표현되는 인덱스가 하이트맵의 범위 내부인지 확인한다.
	return 
		i >= 0 && i < (int)mInfo.HeightmapHeight && 
		j >= 0 && j < (int)mInfo.HeightmapWidth;
}

float Terrain::Average(int i, int j)
{
	// Function computes the average height of the ij element.
	// It averages itself with its eight neighbor pixels.  Note
	// that if a pixel is missing neighbor, we just don't include it
	// in the average--that is, edge pixels don't have a neighbor pixel.
	//
	// ----------
	// | 1| 2| 3|
	// ----------
	// |4 |ij| 6|
	// ----------
	// | 7| 8| 9|
	// ----------

	float avg = 0.0f;
	float num = 0.0f;

	// Use int to allow negatives.  If we use UINT, @ i=0, m=i-1=UINT_MAX
	// and no iterations of the outer for loop occur.
	for(int m = i-1; m <= i+1; ++m)
	{
		for(int n = j-1; n <= j+1; ++n)
		{
			if( InBounds(m,n) )
			{
				avg += mHeightmap[m*mInfo.HeightmapWidth + n];
				num += 1.0f;
			}
		}
	}

	// 최종적으로 하이트맵 내부에 있는 위치가 아닌경우을 제외한것들의 평균을 구한다.
	// 가장자리가 아닌이상 num = 9가된다.
	return avg / num;
}

void Terrain::CalcAllPatchBoundsY()
{
	mPatchBoundsY.resize(mNumPatchQuadFaces);

	// For each patch
	for(UINT i = 0; i < mNumPatchVertRows-1; ++i)
	{
		for(UINT j = 0; j < mNumPatchVertCols-1; ++j)
		{
			CalcPatchBoundsY(i, j);
		}
	}
}

void Terrain::CalcPatchBoundsY(UINT i, UINT j)
{
	// Scan the heightmap values this patch covers and compute the min/max height.

	// 패치기준으로 왼쪽위가 기준점이기 때문에
	// 그다음 패치전까지 범위를 두고 가장 큰 Y값과 작은 Y값을 구해준다.
	UINT x0 = j*CellsPerPatch;
	UINT x1 = (j+1)*CellsPerPatch;

	UINT y0 = i*CellsPerPatch;
	UINT y1 = (i+1)*CellsPerPatch;

	float minY = +MathHelper::Infinity;
	float maxY = -MathHelper::Infinity;
	for(UINT y = y0; y <= y1; ++y)
	{
		for(UINT x = x0; x <= x1; ++x)
		{
			UINT k = y*mInfo.HeightmapWidth + x;
			minY = MathHelper::Min(minY, mHeightmap[k]);
			maxY = MathHelper::Max(maxY, mHeightmap[k]);
		}
	}

	// 최종적으로 그패치에 맞는 인덱스에 BoundY 값을 최소 최대값으로 넣어준다.
	// 이러면 한 패치에 대한 최소와 최대 경계를 알 수 있다.
	UINT patchID = i*(mNumPatchVertCols-1)+j;
	mPatchBoundsY[patchID] = XMFLOAT2(minY, maxY);
}

void Terrain::BuildQuadPatchVB(ID3D11Device* device)
{
	// 패치의 버텍스 만큼 버텍스를 만들어준다. // 세부적으로 나뉘는 것은 나중에 테셀레이션 단계에서
	std::vector<Vertex::Terrain> patchVertices(mNumPatchVertRows*mNumPatchVertCols);

	// 높이반과 너비 반을 구해준다. // cellSpacing * (총 높이값을 가진 버텍스 -1 == 높이값을 가진 면들 == 테셀레이션 최대일때 면들)
	float halfWidth = 0.5f*GetWidth();
	float halfDepth = 0.5f*GetDepth();

	// 한패치의 너비와 깊이를 구해준다. // 한패치는 64 * 64개의 작은 면들로 이루어져있다.
	float patchWidth = GetWidth() / (mNumPatchVertCols-1);
	float patchDepth = GetDepth() / (mNumPatchVertRows-1);

	// 그를 기반으로 uv값을 구해준다.
	float du = 1.0f / (mNumPatchVertCols-1);
	float dv = 1.0f / (mNumPatchVertRows-1);

	for(UINT i = 0; i < mNumPatchVertRows; ++i)
	{
		// 원점이 터레인의 중심이라고 생각했을때 패치의 깊이 좌표
		float z = halfDepth - i*patchDepth;
		for(UINT j = 0; j < mNumPatchVertCols; ++j)
		{

			// 원점이 터레인의 중심이라고 생각했을때 패치의 너비 좌표
			float x = -halfWidth + j*patchWidth;

			// 높이를 제외한 나머지 값들을 넣어준다 // 텍스처도 같이
			patchVertices[i*mNumPatchVertCols+j].Pos = XMFLOAT3(x, 0.0f, z);

			// Stretch texture over grid.
			patchVertices[i*mNumPatchVertCols+j].Tex.x = j*du;
			patchVertices[i*mNumPatchVertCols+j].Tex.y = i*dv;
		}
	}

	// Store axis-aligned bounding box y-bounds in upper-left patch corner.
	// 축정렬 경계상자의 y경계들을 왼쪽위 모퉁이 패치에 저장해둔다. // 기존에 했던것을 그냥 복사한다.
	// 이것으로 버텍스 버퍼를 만들어서 쉐이더로 올리기 떄문
	for(UINT i = 0; i < mNumPatchVertRows-1; ++i)
	{
		for(UINT j = 0; j < mNumPatchVertCols-1; ++j)
		{
			UINT patchID = i*(mNumPatchVertCols-1)+j;
			patchVertices[i*mNumPatchVertCols+j].BoundsY = mPatchBoundsY[patchID];
		}
	}

    D3D11_BUFFER_DESC vbd;
    vbd.Usage = D3D11_USAGE_IMMUTABLE;
	vbd.ByteWidth = sizeof(Vertex::Terrain) * patchVertices.size();
    vbd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    vbd.CPUAccessFlags = 0;
    vbd.MiscFlags = 0;
	vbd.StructureByteStride = 0;

	D3D11_SUBRESOURCE_DATA vinitData;
    vinitData.pSysMem = &patchVertices[0];
    HR(device->CreateBuffer(&vbd, &vinitData, &mQuadPatchVB));
}

void Terrain::BuildQuadPatchIB(ID3D11Device* device)
{
	std::vector<USHORT> indices(mNumPatchQuadFaces*4); // 4 indices per quad face

	// Iterate over each quad and compute indices.
	int k = 0;
	// 1씩 작게 돌아서 오버플로우가 안나게 한다.
	for(UINT i = 0; i < mNumPatchVertRows-1; ++i)
	{
		for(UINT j = 0; j < mNumPatchVertCols-1; ++j)
		{
			// Top row of 2x2 quad patch
			indices[k]   = i*mNumPatchVertCols+j;
			indices[k+1] = i*mNumPatchVertCols+j+1;

			// Bottom row of 2x2 quad patch
			indices[k+2] = (i+1)*mNumPatchVertCols+j;
			indices[k+3] = (i+1)*mNumPatchVertCols+j+1;

			k += 4; // next quad
		}
	}

	D3D11_BUFFER_DESC ibd;
    ibd.Usage = D3D11_USAGE_IMMUTABLE;
	ibd.ByteWidth = sizeof(USHORT) * indices.size();
    ibd.BindFlags = D3D11_BIND_INDEX_BUFFER;
    ibd.CPUAccessFlags = 0;
    ibd.MiscFlags = 0;
	ibd.StructureByteStride = 0;

    D3D11_SUBRESOURCE_DATA iinitData;
    iinitData.pSysMem = &indices[0];
    HR(device->CreateBuffer(&ibd, &iinitData, &mQuadPatchIB));
}

// 쉐이더 리소스 뷰를 만들어준다.
void Terrain::BuildHeightmapSRV(ID3D11Device* device)
{
	D3D11_TEXTURE2D_DESC texDesc;
	texDesc.Width = mInfo.HeightmapWidth;
	texDesc.Height = mInfo.HeightmapHeight;
    texDesc.MipLevels = 1;
	texDesc.ArraySize = 1;
	// 16비트형 float형을 사용한다. // 메모리 절약을 위해서
	texDesc.Format    = DXGI_FORMAT_R16_FLOAT;
	texDesc.SampleDesc.Count   = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Usage = D3D11_USAGE_DEFAULT;
	texDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	texDesc.CPUAccessFlags = 0;
	texDesc.MiscFlags = 0;

	// HALF is defined in xnamath.h, for storing 16-bit float.
	// 16비트 float형을 저장하기 위해서 HALF를 이용한다 // HALF는 unsigned short이다.

	// 기존 mHeightmap(32비트) > 16비트 float형으로 변경하기 위한 과정
	std::vector<HALF> hmap(mHeightmap.size());
	std::transform(mHeightmap.begin(), mHeightmap.end(), hmap.begin(), XMConvertFloatToHalf);
	
	D3D11_SUBRESOURCE_DATA data;
	data.pSysMem = &hmap[0];
    data.SysMemPitch = mInfo.HeightmapWidth*sizeof(HALF);
    data.SysMemSlicePitch = 0;

	ID3D11Texture2D* hmapTex = 0;
	HR(device->CreateTexture2D(&texDesc, &data, &hmapTex));

	D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc;
	srvDesc.Format = texDesc.Format;
	srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = -1;
	HR(device->CreateShaderResourceView(hmapTex, &srvDesc, &mHeightMapSRV));

	// SRV saves reference.
	ReleaseCOM(hmapTex);
}