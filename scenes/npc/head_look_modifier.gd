class_name HeadLookModifier
extends SkeletonModifier3D
## Gira solo la cabeza (y un poco el cuello) hacia un punto del mundo, encima de la
## animacion que este sonando. Angulos limitados y suavizados; si el objetivo queda
## demasiado atras, la cabeza vuelve al frente en vez de retorcerse.
## Los ejes de giro se calculan en el espacio de cada hueso a partir de los ejes del
## mundo, asi no hace falta saber como esta orientado el rig.

## Huesos que participan y que fraccion del giro total lleva cada uno.
@export var bones: PackedStringArray = ["neck", "head"]
@export var weights: PackedFloat32Array = [0.35, 0.65]
## Direccion "frente" del personaje en el espacio del esqueleto (glTF: -Z).
@export var forward_axis := Vector3(0.0, 0.0, -1.0)
@export_range(0.0, 120.0, 1.0) var max_yaw_deg := 70.0
@export_range(0.0, 60.0, 1.0) var max_pitch_deg := 30.0
## Si el objetivo esta mas atras que esto, se deja de mirar (vuelve al frente).
@export_range(0.0, 180.0, 1.0) var give_up_yaw_deg := 110.0
@export var smoothing := 6.0

## Punto del mundo a mirar. `looking` = false vuelve al frente.
var target := Vector3.ZERO
var looking := false

var _yaw := 0.0
var _pitch := 0.0
var _indices: Array[int] = []
var _resolved := false


func _process_modification_with_delta(delta: float) -> void:
	_apply(delta)


func _process_modification() -> void:
	_apply(get_physics_process_delta_time())


func _apply(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or influence <= 0.0:
		return
	if not _resolved:
		_resolved = true
		for b in bones:
			_indices.append(skeleton.find_bone(b))
	if _indices.is_empty() or _indices[-1] < 0:
		return

	# Angulos deseados, en el espacio del esqueleto (sin la escala del nodo).
	var want_yaw := 0.0
	var want_pitch := 0.0
	if looking:
		var head_pos: Vector3 = skeleton.get_bone_global_pose(_indices[-1]).origin
		var local_target: Vector3 = skeleton.global_transform.affine_inverse() * target
		var d := local_target - head_pos
		var flat := Vector3(d.x, 0.0, d.z)
		if flat.length() > 0.001:
			var fwd := Vector3(forward_axis.x, 0.0, forward_axis.z).normalized()
			var yaw := fwd.signed_angle_to(flat.normalized(), Vector3.UP)
			if absf(yaw) <= deg_to_rad(give_up_yaw_deg):
				want_yaw = clampf(yaw, -deg_to_rad(max_yaw_deg), deg_to_rad(max_yaw_deg))
				want_pitch = clampf(atan2(d.y, flat.length()), -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	var k := 1.0 - exp(-smoothing * delta)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	if absf(_yaw) < 0.0005 and absf(_pitch) < 0.0005:
		return

	# Eje lateral del giro de cabeceo: horizontal, perpendicular a la direccion mirada.
	var look_dir := Vector3(forward_axis.x, 0.0, forward_axis.z).normalized().rotated(Vector3.UP, _yaw)
	var side := Vector3.UP.cross(look_dir).normalized()
	for i in _indices.size():
		var idx := _indices[i]
		if idx < 0:
			continue
		var w: float = weights[i] if i < weights.size() else 1.0 / float(_indices.size())
		var gbasis: Basis = skeleton.get_bone_global_pose(idx).basis.orthonormalized()
		var inv := gbasis.inverse()
		var up_local := (inv * Vector3.UP).normalized()
		var side_local := (inv * side).normalized()
		var rot := Quaternion(up_local, _yaw * w * influence) * Quaternion(side_local, -_pitch * w * influence)
		skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * rot)
