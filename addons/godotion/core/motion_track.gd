@tool
@icon("res://addons/godotion/icons/motion_track.svg")
class_name MotionTrack
extends Resource

## One animated property on one node.
##
## A track owns a time-sorted list of [MotionKey]s and knows how to sample
## itself at an arbitrary time. Tracks never touch the scene directly — that is
## [MotionPlayer]'s job — which keeps them usable from the editor panel and at
## runtime with identical results.

## Semantic grouping, used purely for the timeline's accent colouring.
enum Kind {
	TRANSFORM,
	ROTATION,
	SCALE,
	COLOR,
	OPACITY,
	CUSTOM,
}

## Path to the animated node, relative to [member MotionPlayer.root_node].
@export var node_path: NodePath = NodePath():
	set(v):
		node_path = v
		emit_changed()

## Property to drive. Sub-properties use Godot's colon syntax, e.g.
## [code]position:x[/code] or [code]modulate:a[/code].
@export var property: String = "":
	set(v):
		property = v
		_kind_cache = -1
		emit_changed()

@export var enabled: bool = true:
	set(v):
		enabled = v
		emit_changed()

## Time-sorted keys. Prefer [method add_key] over mutating this directly so the
## ordering invariant holds.
##
## May contain [code]null[/code] holes: adding an element in the inspector
## creates an empty slot before the user assigns a resource to it. Read through
## [method get_valid_keys] rather than iterating this directly.
@export var keys: Array[MotionKey] = []:
	set(v):
		keys = v
		sort_keys()

## Overrides the auto-detected [enum Kind] when set to a valid value.
@export var kind_override: int = -1:
	set(v):
		kind_override = v
		_kind_cache = -1
		emit_changed()

var _kind_cache: int = -1
## Null-free, time-sorted view of [member keys], rebuilt on every mutation so
## sampling never pays for filtering.
var _valid_keys: Array[MotionKey] = []


## Returns a [enum Kind] value. Typed as [int] because GDScript rejects casting
## a stored integer back into an enum type.
func get_kind() -> int:
	if kind_override >= 0:
		return kind_override
	if _kind_cache < 0:
		_kind_cache = _detect_kind(property)
	return _kind_cache


static func _detect_kind(prop: String) -> int:
	var p := prop.to_lower()
	if p.begins_with("rotation") or p.contains("quaternion"):
		return Kind.ROTATION
	if p.begins_with("scale"):
		return Kind.SCALE
	if p == "modulate:a" or p == "self_modulate:a" or p.ends_with("alpha") or p.ends_with("opacity"):
		return Kind.OPACITY
	if p.contains("modulate") or p.contains("color"):
		return Kind.COLOR
	if p.begins_with("position") or p.begins_with("global_position") \
			or p.begins_with("offset") or p.begins_with("transform") or p.begins_with("skew"):
		return Kind.TRANSFORM
	return Kind.CUSTOM


func get_display_name() -> String:
	var node_name := String(node_path).get_file()
	if node_name.is_empty():
		node_name = "(root)"
	return node_name


## Null-free, time-sorted keys. Always read through this rather than
## [member keys], which may contain inspector-created holes.
func get_valid_keys() -> Array[MotionKey]:
	return _valid_keys


## Keeps [member keys] ordered by time and refreshes the null-free view.
## Called automatically by the mutators.
func sort_keys() -> void:
	keys.sort_custom(_compare_keys)
	_valid_keys = []
	for key in keys:
		if key != null:
			_valid_keys.append(key)
	emit_changed()


## Sorts by time, with null holes pushed to the end so they never get
## dereferenced mid-sort.
static func _compare_keys(a: MotionKey, b: MotionKey) -> bool:
	if a == null:
		return false
	if b == null:
		return true
	return a.time < b.time


func add_key(key: MotionKey) -> int:
	keys.append(key)
	sort_keys()
	return keys.find(key)


## Inserts a key at [param time], replacing any existing key within
## [param epsilon] seconds. Returns the key that now occupies that slot.
func set_key(time: float, value: Variant, interp: int = MotionKey.Interp.LINEAR, epsilon: float = 0.0005) -> MotionKey:
	var existing := find_key_at(time, epsilon)
	if existing != null:
		existing.value = value
		existing.interp = interp
		emit_changed()
		return existing
	var key := MotionKey.new()
	key.time = time
	key.value = value
	key.interp = interp
	add_key(key)
	return key


func find_key_at(time: float, epsilon: float = 0.0005) -> MotionKey:
	for key in _valid_keys:
		if absf(key.time - time) <= epsilon:
			return key
	return null


func remove_key(key: MotionKey) -> bool:
	var idx := keys.find(key)
	if idx < 0:
		return false
	keys.remove_at(idx)
	emit_changed()
	return true


func get_length() -> float:
	if _valid_keys.is_empty():
		return 0.0
	return _valid_keys[_valid_keys.size() - 1].time


## Samples the track. Returns [code]null[/code] when the track has no keys, so
## callers can distinguish "no opinion" from a keyed [code]0[/code].
func sample(time: float) -> Variant:
	if _valid_keys.is_empty():
		return null
	if _valid_keys.size() == 1 or time <= _valid_keys[0].time:
		return _valid_keys[0].value
	var last := _valid_keys[_valid_keys.size() - 1]
	if time >= last.time:
		return last.value

	var idx := _segment_index(time)
	var from_key := _valid_keys[idx]
	var to_key := _valid_keys[idx + 1]
	var span := to_key.time - from_key.time
	if span <= 0.0:
		return to_key.value

	var t := (time - from_key.time) / span
	var weight: float
	if from_key.interp == MotionKey.Interp.BEZIER:
		var out_h := Vector2(from_key.out_handle.x / span, from_key.out_handle.y)
		var in_h := Vector2(to_key.in_handle.x / span, to_key.in_handle.y)
		weight = MotionEasing.bezier_weight(out_h, in_h, t)
	else:
		weight = MotionEasing.apply(from_key.interp, t)
	return interpolate_values(from_key.value, to_key.value, weight)


## Binary search for the key index whose segment contains [param time].
func _segment_index(time: float) -> int:
	var low := 0
	var high := _valid_keys.size() - 1
	while low < high - 1:
		var mid := (low + high) / 2
		if _valid_keys[mid].time <= time:
			low = mid
		else:
			high = mid
	return low


## Type-aware interpolation. Discrete types snap at the halfway point rather
## than erroring, which keeps bool/String properties usable on a track.
static func interpolate_values(a: Variant, b: Variant, weight: float) -> Variant:
	if typeof(a) != typeof(b):
		return b if weight >= 1.0 else a
	match typeof(a):
		TYPE_FLOAT:
			return lerpf(a, b, weight)
		TYPE_INT:
			return int(roundf(lerpf(float(a), float(b), weight)))
		TYPE_VECTOR2:
			return (a as Vector2).lerp(b, weight)
		TYPE_VECTOR3:
			return (a as Vector3).lerp(b, weight)
		TYPE_VECTOR4:
			return (a as Vector4).lerp(b, weight)
		TYPE_COLOR:
			return (a as Color).lerp(b, weight)
		TYPE_QUATERNION:
			return (a as Quaternion).slerp(b, weight)
		TYPE_TRANSFORM2D:
			return (a as Transform2D).interpolate_with(b, weight)
		TYPE_TRANSFORM3D:
			return (a as Transform3D).interpolate_with(b, weight)
	return b if weight >= 0.5 else a


func duplicate_track() -> MotionTrack:
	var copy := MotionTrack.new()
	copy.node_path = node_path
	copy.property = property
	copy.enabled = enabled
	copy.kind_override = kind_override
	var new_keys: Array[MotionKey] = []
	for key in _valid_keys:
		new_keys.append(key.duplicate_key())
	copy.keys = new_keys
	return copy
