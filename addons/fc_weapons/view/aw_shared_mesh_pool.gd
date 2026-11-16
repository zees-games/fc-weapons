class_name AwSharedMeshPool
extends DotFxMeshPool
## The quads every remote shooter's flash, tracer and impact is drawn on, in one pool for the whole crowd.
##
## A pool per shooter held a dozen hidden quads each however little that shooter fired; with sixty-three remote
## players that was most of a thousand scene nodes. This one is as big as the most effects ever in the air at
## once and no bigger, builds on demand, and ignores [member DotFxMeshPool.max_idle] (a game's per-shooter trim,
## which would free and rebuild quads every burst here). [member idle_limit] trims it; 0 never does.

## Most idle quads kept after a burst; 0 keeps every one built.
var idle_limit := 0


## Returns a quad for reuse, hidden; frees it instead when more than [member idle_limit] already wait.
func release(m: MeshInstance3D) -> void:
	if not is_instance_valid(m) or _free.has(m):
		return
	m.visible = false
	if idle_limit > 0 and _free.size() >= idle_limit:
		_all.erase(m)
		m.queue_free()
		return
	_free.append(m)
