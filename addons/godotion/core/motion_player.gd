@tool
@icon("res://addons/godotion/icons/motion_player.svg")
class_name MotionPlayer
extends Node

## Runtime evaluator for a [MotionTimeline].
##
## Add one to your scene, assign a timeline, and every frame it resolves each
## track's node path relative to [member root_node] and writes the sampled
## value. Node resolution is cached; call [method invalidate_cache] if you
## reparent or rename animated nodes at runtime.

signal started()
signal finished()
signal looped()
## Emitted whenever the playhead moves, including editor scrubbing.
signal time_changed(time: float)

@export var timeline: MotionTimeline:
	set(v):
		if timeline == v:
			return
		timeline = v
		invalidate_cache()
		_time = 0.0
		update_configuration_warnings()

## Nodes in the timeline are resolved relative to this node. Defaults to the
## MotionPlayer's own parent, matching how AnimationPlayer behaves in practice.
@export var root_node: NodePath = NodePath(".."):
	set(v):
		root_node = v
		invalidate_cache()

## Play as soon as the node enters the tree (not in the editor).
@export var autoplay: bool = false

@export_range(0.0, 8.0, 0.01, "or_greater") var speed_scale: float = 1.0

## Apply values while stopped too. Useful for scrub-driven scenes.
@export var apply_when_stopped: bool = true

var _time: float = 0.0
var _playing: bool = false
var _node_cache: Dictionary = {}
var _warned_paths: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	if autoplay and timeline != null:
		play()
	set_process(_playing)


func _process(delta: float) -> void:
	if not _playing or timeline == null:
		return
	var previous := _time
	_time += delta * speed_scale

	if timeline.is_finished(_time):
		_time = timeline.duration
		apply_at(_time)
		stop(false)
		finished.emit()
		return

	if timeline.loop_mode != MotionTimeline.LoopMode.NONE and _time >= timeline.duration and previous < timeline.duration:
		looped.emit()

	apply_at(_time)
	time_changed.emit(_time)


## Current playhead position in seconds.
func get_time() -> float:
	return _time


func is_playing() -> bool:
	return _playing


func play(from: float = -1.0) -> void:
	if timeline == null:
		push_warning("MotionPlayer '%s' has no timeline assigned." % name)
		return
	if from >= 0.0:
		_time = from
	_playing = true
	set_process(true)
	started.emit()


func pause() -> void:
	_playing = false
	set_process(false)


func stop(reset: bool = true) -> void:
	_playing = false
	set_process(false)
	if reset:
		_time = 0.0
		if apply_when_stopped:
			apply_at(_time)


## Moves the playhead without changing the play state.
func seek(time: float, apply: bool = true) -> void:
	if timeline == null:
		return
	_time = clampf(time, 0.0, timeline.duration)
	if apply and (apply_when_stopped or _playing):
		apply_at(_time)
	time_changed.emit(_time)


## Writes every enabled track's sampled value into the scene.
func apply_at(time: float) -> void:
	if timeline == null:
		return
	var root := _resolve_root()
	if root == null:
		return
	var local_time := timeline.wrap_time(time)
	for track in timeline.get_valid_tracks():
		if not track.enabled or track.property.is_empty():
			continue
		var value: Variant = track.sample(local_time)
		if value == null:
			continue
		var node := _resolve_node(root, track.node_path)
		if node == null:
			continue
		_apply_value(node, track, value)


func _apply_value(node: Node, track: MotionTrack, value: Variant) -> void:
	# set_indexed handles both plain properties and sub-paths like "position:x".
	# It fails silently on unknown paths, so we probe once and warn.
	var path := NodePath(track.property)
	if not _warned_paths.has(track.property):
		var current: Variant = node.get_indexed(path)
		if current == null:
			_warned_paths[track.property] = true
			push_warning("Godotion: node '%s' has no property '%s'." % [node.name, track.property])
			return
	node.set_indexed(path, value)


func _resolve_root() -> Node:
	if root_node.is_empty():
		return self
	var node := get_node_or_null(root_node)
	if node == null and not _warned_paths.has("__root__"):
		_warned_paths["__root__"] = true
		push_warning("Godotion: MotionPlayer '%s' cannot resolve root_node '%s'." % [name, root_node])
	return node


func _resolve_node(root: Node, path: NodePath) -> Node:
	if _node_cache.has(path):
		var cached: Node = _node_cache[path]
		if is_instance_valid(cached):
			return cached
		_node_cache.erase(path)
	var node: Node = root if path.is_empty() else root.get_node_or_null(path)
	if node == null:
		if not _warned_paths.has(path):
			_warned_paths[path] = true
			push_warning("Godotion: cannot resolve animated node '%s' under '%s'." % [path, root.name])
		return null
	_node_cache[path] = node
	return node


## Drops cached node lookups. Call after reparenting animated nodes.
func invalidate_cache() -> void:
	_node_cache.clear()
	_warned_paths.clear()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if timeline == null:
		warnings.append("Assign a MotionTimeline resource to animate anything.")
	elif timeline.get_valid_tracks().is_empty():
		warnings.append("The assigned MotionTimeline has no tracks yet.")
	if root_node.is_empty():
		warnings.append("root_node is empty; animated node paths will resolve against the MotionPlayer itself.")
	elif get_node_or_null(root_node) == null:
		warnings.append("root_node '%s' does not resolve to a node." % root_node)
	return warnings
