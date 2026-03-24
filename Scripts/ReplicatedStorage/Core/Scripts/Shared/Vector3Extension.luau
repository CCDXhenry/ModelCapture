local Vector3Extension = {}

--获取两个向量的距离的平方
function Vector3Extension.GetSqrMagnitude(vector1: Vector3, vector2: Vector3): number
	return (vector1.X - vector2.X) ^ 2 + (vector1.Y - vector2.Y) ^ 2 + (vector1.Z - vector2.Z) ^ 2
end

--获取两个向量水平距离的平方
function Vector3Extension.GetHorizontalSqrMagnitude(vector1: Vector3, vector2: Vector3): number
	return (vector1.X - vector2.X) ^ 2 + (vector1.Z - vector2.Z) ^ 2
end

return Vector3Extension