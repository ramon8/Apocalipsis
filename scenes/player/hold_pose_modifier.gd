class_name HoldPoseModifier
extends SkeletonModifier3D
## Layers a static pose (e.g. "hold_pose": arms holding something) on top of whatever the
## AnimationPlayer is playing, but only on the listed bones. Runs after the animation
## (SkeletonModifier3D), so walk/run keep driving legs, torso and head while the arms
## blend towards the hold pose by `influence` (0 = off, 1 = full).

## Single-frame (or any) animation whose rotation tracks define the pose.
@export var pose_animation: Animation:
	set(value):
		pose_animation = value
		_dirty = true
## Bones to override. Others are left to the running animation.
@export var bones: PackedStringArray = ["shoulder.l", "arm.l", "hand.l", "shoulder.r", "arm.r", "hand.r"]:
	set(value):
		bones = value
		_dirty = true
## Time (s) in the clip the pose is sampled at.
@export var sample_time := 0.0:
	set(value):
		sample_time = value
		_dirty = true

var _dirty := true
var _targets: Array = []  # [bone_index, Quaternion]


# Godot 4.7 calls the *_with_delta variant; keep the old one as a fallback.
func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or influence <= 0.0:
		return
	if _dirty:
		_rebuild(skeleton)
	for t in _targets:
		var idx: int = t[0]
		var current := skeleton.get_bone_pose_rotation(idx)
		skeleton.set_bone_pose_rotation(idx, current.slerp(t[1], influence))


func _rebuild(skeleton: Skeleton3D) -> void:
	_dirty = false
	_targets.clear()
	if pose_animation == null:
		return
	for i in pose_animation.get_track_count():
		if pose_animation.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := pose_animation.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(0))
		if not bones.has(bone_name):
			continue
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		_targets.append([idx, pose_animation.rotation_track_interpolate(i, sample_time)])
	if _targets.is_empty():
		push_warning("HoldPoseModifier: none of %s found in the pose animation." % [bones])
