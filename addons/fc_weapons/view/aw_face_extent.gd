extends RefCounted

## How far a mesh's corners reach along a direction, read with engine-side work instead of a script loop over every corner:
## the corners are mapped to their dot with the direction (the same float products a script `p.dot(d)` makes) and sorted natively.
## No `class_name`: preloaded by path.


## `Vector2(least, greatest)` of `p.dot(direction)` over [param faces]'s corners; `Vector2(INF, -INF)` with none.
static func range_along(faces: PackedVector3Array, direction: Vector3) -> Vector2:
	if faces.is_empty():
		return Vector2(INF, -INF)
	var dotted := (Transform3D(Basis(direction, direction, direction).transposed(), Vector3.ZERO) * faces).to_byte_array().to_float32_array()
	dotted.sort()
	return Vector2(dotted[0], dotted[dotted.size() - 1])
