@tool
class_name MotionEasing
extends RefCounted

## Stateless easing helpers.
##
## Every function maps a normalised segment position [code]t[/code] in the range
## 0..1 to an eased weight, also in 0..1. Value interpolation is handled
## separately in [MotionTrack] so that the same curves apply to floats,
## vectors and colors alike.

## Maximum iterations used when solving a cubic bezier for X. Matches the
## precision Godot's own bezier tracks use closely enough for editor work.
const BEZIER_SOLVE_ITERATIONS := 12
const BEZIER_SOLVE_EPSILON := 0.00001


static func apply(interp: int, t: float) -> float:
	var w := clampf(t, 0.0, 1.0)
	match interp:
		MotionKey.Interp.CONSTANT:
			return 0.0
		MotionKey.Interp.LINEAR:
			return w
		MotionKey.Interp.EASE_IN:
			return w * w * w
		MotionKey.Interp.EASE_OUT:
			var inv := 1.0 - w
			return 1.0 - inv * inv * inv
		MotionKey.Interp.EASE_IN_OUT:
			if w < 0.5:
				return 4.0 * w * w * w
			var f := -2.0 * w + 2.0
			return 1.0 - (f * f * f) / 2.0
	return w


## Evaluates a cubic bezier segment whose control points are expressed as
## offsets from the two surrounding keys, normalised to the segment.
##
## [param out_handle] is the outgoing handle of the left key and
## [param in_handle] the incoming handle of the right key. Both are stored in
## (time, value) space; this function expects them already normalised by the
## segment duration and value delta.
static func bezier_weight(out_handle: Vector2, in_handle: Vector2, t: float) -> float:
	var p1 := Vector2(clampf(out_handle.x, 0.0, 1.0), out_handle.y)
	var p2 := Vector2(clampf(1.0 + in_handle.x, 0.0, 1.0), 1.0 + in_handle.y)
	var u := _solve_bezier_x(p1.x, p2.x, clampf(t, 0.0, 1.0))
	return _cubic(0.0, p1.y, p2.y, 1.0, u)


static func _cubic(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	var inv := 1.0 - u
	return inv * inv * inv * p0 \
		+ 3.0 * inv * inv * u * p1 \
		+ 3.0 * inv * u * u * p2 \
		+ u * u * u * p3


## Bisection solve of the bezier X polynomial. Bisection rather than Newton
## because handles can be authored flat, which drives the derivative to zero
## and makes Newton diverge.
static func _solve_bezier_x(p1x: float, p2x: float, target_x: float) -> float:
	var low := 0.0
	var high := 1.0
	var mid := target_x
	for _i in BEZIER_SOLVE_ITERATIONS:
		mid = (low + high) * 0.5
		var x := _cubic(0.0, p1x, p2x, 1.0, mid)
		var diff := x - target_x
		if absf(diff) < BEZIER_SOLVE_EPSILON:
			return mid
		if diff > 0.0:
			high = mid
		else:
			low = mid
	return mid
