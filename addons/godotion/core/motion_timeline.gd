@tool
@icon("res://addons/godotion/icons/motion_timeline.svg")
class_name MotionTimeline
extends Resource

## A saveable collection of [MotionTrack]s plus playback metadata.
##
## Save as a [code].tres[/code] next to your scene and point a [MotionPlayer]
## at it. The same resource is what the Godotion bottom panel edits.

enum LoopMode {
	NONE,
	LOOP,
	PING_PONG,
}

@export var timeline_name: String = "Timeline":
	set(v):
		timeline_name = v
		emit_changed()

## Authored length in seconds. Playback clamps to this even if keys extend
## past it, so shortening the timeline is non-destructive.
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration: float = 5.0:
	set(v):
		duration = maxf(0.1, v)
		emit_changed()

## Frame rate used for snapping and ruler subdivisions in the editor.
@export_range(1, 240, 1) var fps: int = 60:
	set(v):
		fps = maxi(1, v)
		emit_changed()

@export var loop_mode: LoopMode = LoopMode.NONE:
	set(v):
		loop_mode = v
		emit_changed()

@export var tracks: Array[MotionTrack] = []:
	set(v):
		tracks = v
		emit_changed()


func add_track(track: MotionTrack) -> int:
	tracks.append(track)
	emit_changed()
	return tracks.size() - 1


func remove_track(track: MotionTrack) -> bool:
	var idx := tracks.find(track)
	if idx < 0:
		return false
	tracks.remove_at(idx)
	emit_changed()
	return true


func find_track(node_path: NodePath, property: String) -> MotionTrack:
	for track in tracks:
		if track.node_path == node_path and track.property == property:
			return track
	return null


## Returns the existing track for this node/property pair, creating it if
## needed. Does not push an undo step — callers in the editor must do that.
func get_or_create_track(node_path: NodePath, property: String) -> MotionTrack:
	var track := find_track(node_path, property)
	if track != null:
		return track
	track = MotionTrack.new()
	track.node_path = node_path
	track.property = property
	add_track(track)
	return track


## Longest keyed time across all tracks, ignoring [member duration].
func get_keyed_length() -> float:
	var longest := 0.0
	for track in tracks:
		longest = maxf(longest, track.get_length())
	return longest


func snap_to_frame(time: float) -> float:
	return roundf(time * float(fps)) / float(fps)


## Maps a raw playback position onto the timeline according to [member loop_mode].
func wrap_time(time: float) -> float:
	if duration <= 0.0:
		return 0.0
	match loop_mode:
		LoopMode.LOOP:
			return fposmod(time, duration)
		LoopMode.PING_PONG:
			var cycle := fposmod(time, duration * 2.0)
			return cycle if cycle <= duration else duration * 2.0 - cycle
	return clampf(time, 0.0, duration)


## Returns [code]true[/code] once a non-looping timeline has run past its end.
func is_finished(time: float) -> bool:
	return loop_mode == LoopMode.NONE and time >= duration
