//***************************************************************************************
// Octree.cpp by Frank Luna (C) 2011 All Rights Reserved.
//***************************************************************************************

#include "Octree.h"


Octree::Octree()
	: mRoot(0)
{
}

Octree::~Octree()
{
	SafeDelete(mRoot);
}

void Octree::Build(const std::vector<XMFLOAT3>& vertices, const std::vector<UINT>& indices)
{
	// Cache a copy of the vertices.
	// 버텍스들의 캐시
	mVertices = vertices;

	// Build AABB to contain the scene mesh.
	// 씬 메쉬에 대해서 축정렬 바운딩 박스를 생성해준다.
	// 전체 버텍스에 대해서 바운딩 박스를 씌우는 방식은 그 메쉬의 최소와 최대 위치를 구해서 씌워준다.
	XNA::AxisAlignedBox sceneBounds = BuildAABB();
	
	// Allocate the root node and set its AABB to contain the scene mesh.
	mRoot = new OctreeNode();
	mRoot->Bounds = sceneBounds;

	BuildOctree(mRoot, indices);
}

bool Octree::RayOctreeIntersect(FXMVECTOR rayPos, FXMVECTOR rayDir)
{
	return RayOctreeIntersect(mRoot, rayPos, rayDir);
}

XNA::AxisAlignedBox Octree::BuildAABB()
{
	XMVECTOR vmin = XMVectorReplicate(+MathHelper::Infinity);
	XMVECTOR vmax = XMVectorReplicate(-MathHelper::Infinity);
	for(size_t i = 0; i < mVertices.size(); ++i)
	{
		XMVECTOR P = XMLoadFloat3(&mVertices[i]);

		vmin = XMVectorMin(vmin, P);
		vmax = XMVectorMax(vmax, P);
	}

	XNA::AxisAlignedBox bounds;
	XMVECTOR C = 0.5f*(vmin + vmax);
	XMVECTOR E = 0.5f*(vmax - vmin); 

	XMStoreFloat3(&bounds.Center, C); 
	XMStoreFloat3(&bounds.Extents, E); 

	return bounds;
}

void Octree::BuildOctree(OctreeNode* parent, const std::vector<UINT>& indices)
{
	// 삼각형 갯수를 세어준다.
	size_t triCount = indices.size() / 3;

	if(triCount < 60) 
	{
		// 60개 이하면 인덱스들 멤버변수에 넣어준다.
		// 만약 60개 이상이면 8개의 노드를 만들고 바운딩박스를 분할하고 그 아래에 교차되는 삼각형들을 넣어준다.
		// 이렇게 분할했을때 삼각형이 60개 이하가 되면 인덱스들이 저장된다.
		parent->IsLeaf = true;
		parent->Indices = indices;
	}
	else
	{
		parent->IsLeaf = false;

		// sub바운딩 박스를 만들어서
		XNA::AxisAlignedBox subbox[8];
		// 바운딩 박스를 8개로 나눈다. // extends와 center활용해서 생성
		parent->Subdivide(subbox);

		for(int i = 0; i < 8; ++i)
		{
			// Allocate a new subnode.
			// 새로운 노드를 할당하고 바운딩 박스는 앞에서 구했던것으로 초기화
			parent->Children[i] = new OctreeNode();
			parent->Children[i]->Bounds = subbox[i];

			// Find triangles that intersect this node's bounding box.
			// 이 노드의 바운딩 박스와 교차하는 삼각형들을 모두 이노드에 정보를 넣어준다.
			std::vector<UINT> intersectedTriangleIndices;
			for(size_t j = 0; j < triCount; ++j)
			{
				UINT i0 = indices[j*3+0];
				UINT i1 = indices[j*3+1];
				UINT i2 = indices[j*3+2];

				XMVECTOR v0 = XMLoadFloat3(&mVertices[i0]);
				XMVECTOR v1 = XMLoadFloat3(&mVertices[i1]);
				XMVECTOR v2 = XMLoadFloat3(&mVertices[i2]);

				if(XNA::IntersectTriangleAxisAlignedBox(v0, v1, v2, &subbox[i]))
				{
					intersectedTriangleIndices.push_back(i0);
					intersectedTriangleIndices.push_back(i1);
					intersectedTriangleIndices.push_back(i2);
				}
			}

			// Recurse.
			BuildOctree(parent->Children[i], intersectedTriangleIndices);
		}
	}
}

bool Octree::RayOctreeIntersect(OctreeNode* parent, FXMVECTOR rayPos, FXMVECTOR rayDir)
{
	// Recurs until we find a leaf node (all the triangles are in the leaves).
	// 리프노드를 찾을때까지 수행 // 리프노드를 찾으면 그냥 삼각형에 대해서 처리하면 된다.
	if( !parent->IsLeaf )
	{
		for(int i = 0; i < 8; ++i)
		{
			// Recurse down this node if the ray hit the child's box.
			// 돌면서 만약에 교차가 되는 곳이 있으면
			float t;
			// 내부 자식노드들에 들어가서
			if( XNA::IntersectRayAxisAlignedBox(rayPos, rayDir, &parent->Children[i]->Bounds, &t) )
			{
				// If we hit a triangle down this branch, we can bail out that we hit a triangle.
				// 자식노드를 재귀적으로 돌면서 충돌되는 바운딩 박스를 찾는다. // 이를 리프노드를 찾을때까지 반복한다.
				if( RayOctreeIntersect(parent->Children[i], rayPos, rayDir) )
					return true;
			}
		}

		// If we get here. then we did not hit any triangles.
		return false;
	}
	// 리프노드일 때
	else
	{
		// 더이상 아래 노드를 안보고 바로 현재노드 (parent)에서 삼각형들을 살펴본다.
		size_t triCount = parent->Indices.size() / 3;

		for(size_t i = 0; i < triCount; ++i)
		{
			UINT i0 = parent->Indices[i*3+0];
			UINT i1 = parent->Indices[i*3+1];
			UINT i2 = parent->Indices[i*3+2];

			XMVECTOR v0 = XMLoadFloat3(&mVertices[i0]);
			XMVECTOR v1 = XMLoadFloat3(&mVertices[i1]);
			XMVECTOR v2 = XMLoadFloat3(&mVertices[i2]);

			float t;
			// 삼각형들에 대한 교차판정을 해준다.
			if( XNA::IntersectRayTriangle(rayPos, rayDir, v0, v1, v2, &t) )
				return true;
		}

		return false;
	}
}