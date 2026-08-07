@tool
class_name MotionKey
extends Resource

## A single keyframe on a [MotionTrack].
##
## The stored [member value] is a Variant so one key type covers floats,
## vectors, colors and booleans. [member interp] describes how the segment
## *leaving* this key behaves; the segment arriving at a key is owned by the
## previous key.

enum Interp {
	CONSTANT, ## Hold this value until the next key, then snap.
	LINEAR,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	BEZIER, ## Uses [member out_handle] and the next key's [member in_handle].
}

## Position of the key on the timeline, in seconds.
@export var time: float = 0.0:
	set(v):
		time = maxf(0.0, v)
		emit_changed()

## Keyed value. Must match the type of the animated property.
@export_storage var value: Variant = 0.0

## Interpolation used for the segment starting at this key.
@export var interp: Interp = Interp.LINEAR:
	set(v):
		interp = v
		emit_changed()

## Incoming bezier handle, in (seconds, value-fraction) offsets from this key.
@export var in_handle: Vector2 = Vector2(-0.25, 0.0)

## Outgoing bezier handle, in (seconds, value-fraction) offsets from this key.
@export var out_handle: Vector2 = Vector2(0.25, 0.0)


func duplicate_key() -> MotionKey:
	var copy := MotionKey.new()
	copy.time = time
	copy.value = value
	copy.interp = interp
	copy.in_handle = in_handle
	copy.out_handle = out_handle
	return copy
