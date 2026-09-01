class_name OverlayAnimModifier
extends SkeletonModifier3D
## Plays a looping clip on the listed bones ON TOP of whatever the AnimationPlayer is
## playing (same idea as HoldPoseModifier, but with an advancing clock instead of a static
## frame). Runs after the animation, so Walk/Run keep driving the body while e.g. the tail
## wags or the head sniffs. `influence` is the master weight; play()/stop() fade in/out.

## Bones to override. Others are left to the running animation.
@export var bones: PackedStringArray = []:
	set(value):
		bones = value
		_dirty = true
## Seconds to fade the overlay in on play() and out on stop().
@export_range(0.0, 2.0, 0.05) var fade_time := 0.25
## Playback rate of the overlay clip.
@export_range(0.1, 3.0, 0.05) var speed_scale := 1.0

var _anim: Animation
var _tracks: Array = []  # [track_index, bone_index]
var _time := 0.0
var _weight := 0.0  # 0..1 fade, multiplied by `influence`
var _playing := false
var _dirty := true


## Starts (or switches to) an overlay clip. Restarting the same clip is a no-op.
func play(anim: Animation) -> void:
	if anim == null:
		stop()
		return
	if anim != _anim:
		_anim = anim
		_dirty = true
		_time = 0.0
	_playing = true


func stop() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


# Godot 4.7 calls the *_with_delta variant; keep the old one as a fallback.
func _process_modification_with_delta(delta: float) -> void:
	_apply(delta)


func _process_modification() -> void:
	_apply(get_physics_process_delta_time())


func _apply(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_weight = move_toward(_weight, 1.0 if _playing else 0.0, delta / maxf(fade_time, 0.001))
	if _weight <= 0.0 or _anim == null or influence <= 0.0:
		return
	if _dirty:
		_rebuild(skeleton)
	_time = fposmod(_time + delta * speed_scale, maxf(_anim.length, 0.001))
	var w := _weight * influence
	for t in _tracks:
		var rot := _anim.rotation_track_interpolate(t[0], _time)
		var current := skeleton.get_bone_pose_rotation(t[1])
		skeleton.set_bone_pose_rotation(t[1], current.slerp(rot, w))


func _rebuild(skeleton: Skeleton3D) -> void:
	_dirty = false
	_tracks.clear()
	for i in _anim.get_track_count():
		if _anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := _anim.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(0))
		if not bones.has(bone_name):
			continue
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			_tracks.append([i, idx])
	if _tracks.is_empty():
		push_warning("OverlayAnimModifier: none of %s found in clip '%s'." % [bones, _anim.resource_name])
