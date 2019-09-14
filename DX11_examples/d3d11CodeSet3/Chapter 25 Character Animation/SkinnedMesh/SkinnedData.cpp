

#include "SkinnedData.h"
#include "MeshGeometry.h"

Keyframe::Keyframe()
	: TimePos(0.0f),
	Translation(0.0f, 0.0f, 0.0f),
	Scale(1.0f, 1.0f, 1.0f),
	RotationQuat(0.0f, 0.0f, 0.0f, 1.0f)
{
}

Keyframe::~Keyframe()
{
}
 
float BoneAnimation::GetStartTime()const
{
	// Keyframes are sorted by time, so first keyframe gives start time.
	return Keyframes.front().TimePos;
}

float BoneAnimation::GetEndTime()const
{
	// Keyframes are sorted by time, so last keyframe gives end time.
	float f = Keyframes.back().TimePos;

	return f;
}

void BoneAnimation::Interpolate(float t, XMFLOAT4X4& M)const
{
	// 만약에 시간이 첫번째 시간위치보다 작으면 첫프레임으로 고정
	if( t <= Keyframes.front().TimePos )
	{
		XMVECTOR S = XMLoadFloat3(&Keyframes.front().Scale);
		XMVECTOR P = XMLoadFloat3(&Keyframes.front().Translation);
		XMVECTOR Q = XMLoadFloat4(&Keyframes.front().RotationQuat);

		XMVECTOR zero = XMVectorSet(0.0f, 0.0f, 0.0f, 1.0f);
		XMStoreFloat4x4(&M, XMMatrixAffineTransformation(S, zero, Q, P));
	}
	// 만약 시간이 마지막 시간위치보다 크다면 마지막 프레임으로 고정
	else if( t >= Keyframes.back().TimePos )
	{
		XMVECTOR S = XMLoadFloat3(&Keyframes.back().Scale);
		XMVECTOR P = XMLoadFloat3(&Keyframes.back().Translation);
		XMVECTOR Q = XMLoadFloat4(&Keyframes.back().RotationQuat);

		XMVECTOR zero = XMVectorSet(0.0f, 0.0f, 0.0f, 1.0f);
		XMStoreFloat4x4(&M, XMMatrixAffineTransformation(S, zero, Q, P));
	}
	else
	{
		// 돌면서 어떤시간 안에 있는것인지 확인
		for(UINT i = 0; i < Keyframes.size()-1; ++i)
		{
			
			if( t >= Keyframes[i].TimePos && t <= Keyframes[i+1].TimePos )
			{
				// 특정 프레임 사이라면 그 프래임 사이의 위치를 정해준다.
				float lerpPercent = (t - Keyframes[i].TimePos) / (Keyframes[i+1].TimePos - Keyframes[i].TimePos);

				// 프레임 두개의 각 행렬을 구하고, 그사이를 보간해준다.
				XMVECTOR s0 = XMLoadFloat3(&Keyframes[i].Scale);
				XMVECTOR s1 = XMLoadFloat3(&Keyframes[i+1].Scale);

				XMVECTOR p0 = XMLoadFloat3(&Keyframes[i].Translation);
				XMVECTOR p1 = XMLoadFloat3(&Keyframes[i+1].Translation);

				XMVECTOR q0 = XMLoadFloat4(&Keyframes[i].RotationQuat);
				XMVECTOR q1 = XMLoadFloat4(&Keyframes[i+1].RotationQuat);

				XMVECTOR S = XMVectorLerp(s0, s1, lerpPercent);
				XMVECTOR P = XMVectorLerp(p0, p1, lerpPercent);
				XMVECTOR Q = XMQuaternionSlerp(q0, q1, lerpPercent);

				XMVECTOR zero = XMVectorSet(0.0f, 0.0f, 0.0f, 1.0f);
				XMStoreFloat4x4(&M, XMMatrixAffineTransformation(S, zero, Q, P));

				break;
			}
		}
	}
}

float AnimationClip::GetClipStartTime()const
{
	// Find smallest start time over all bones in this clip.
	float t = MathHelper::Infinity;
	for(UINT i = 0; i < BoneAnimations.size(); ++i)
	{
		t = MathHelper::Min(t, BoneAnimations[i].GetStartTime());
	}

	return t;
}

float AnimationClip::GetClipEndTime()const
{
	// Find largest end time over all bones in this clip.
	float t = 0.0f;
	for(UINT i = 0; i < BoneAnimations.size(); ++i)
	{
		t = MathHelper::Max(t, BoneAnimations[i].GetEndTime());
	}

	return t;
}

void AnimationClip::Interpolate(float t, std::vector<XMFLOAT4X4>& boneTransforms)const
{
	for(UINT i = 0; i < BoneAnimations.size(); ++i)
	{
		BoneAnimations[i].Interpolate(t, boneTransforms[i]);
	}
}

float SkinnedData::GetClipStartTime(const std::string& clipName)const
{
	auto clip = mAnimations.find(clipName);
	return clip->second.GetClipStartTime();
}

float SkinnedData::GetClipEndTime(const std::string& clipName)const
{
	auto clip = mAnimations.find(clipName);
	return clip->second.GetClipEndTime();
}

UINT SkinnedData::BoneCount()const
{
	return mBoneHierarchy.size();
}

void SkinnedData::Set(std::vector<int>& boneHierarchy, 
		              std::vector<XMFLOAT4X4>& boneOffsets,
		              std::map<std::string, AnimationClip>& animations)
{
	mBoneHierarchy = boneHierarchy;
	mBoneOffsets   = boneOffsets;
	mAnimations    = animations;
}
 
void SkinnedData::GetFinalTransforms(const std::string& clipName, float timePos,  std::vector<XMFLOAT4X4>& finalTransforms)const
{
	UINT numBones = mBoneOffsets.size();

	std::vector<XMFLOAT4X4> toParentTransforms(numBones);

	// Interpolate all the bones of this clip at the given time instance.
	// 각뼈대의 행렬을 구해준다. // 오프셋 행렬 // 두 프레임 사이에 있다면 보간을 해준다.
	auto clip = mAnimations.find(clipName);
	clip->second.Interpolate(timePos, toParentTransforms);

	//
	// Traverse the hierarchy and transform all the bones to the root space.
	//

	std::vector<XMFLOAT4X4> toRootTransforms(numBones);

	// The root bone has index 0.  The root bone has no parent, so its toRootTransform
	// is just its local bone transform.
	toRootTransforms[0] = toParentTransforms[0];

	// Now find the toRootTransform of the children.
	for(UINT i = 1; i < numBones; ++i)
	{
		XMMATRIX toParent = XMLoadFloat4x4(&toParentTransforms[i]);

		int parentIndex = mBoneHierarchy[i];
		XMMATRIX parentToRoot = XMLoadFloat4x4(&toRootTransforms[parentIndex]);

		XMMATRIX toRoot = XMMatrixMultiply(toParent, parentToRoot);

		XMStoreFloat4x4(&toRootTransforms[i], toRoot);
	}

	// Premultiply by the bone offset transform to get the final transform.
	for(UINT i = 0; i < numBones; ++i)
	{
		XMMATRIX offset = XMLoadFloat4x4(&mBoneOffsets[i]);
		XMMATRIX toRoot = XMLoadFloat4x4(&toRootTransforms[i]);
		XMStoreFloat4x4(&finalTransforms[i], XMMatrixMultiply(offset, toRoot));
	}
}