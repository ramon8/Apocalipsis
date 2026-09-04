class_name CarrySlot
extends Node3D
## Ancla para objetos llevados en brazos. Cada frame se coloca en el punto medio entre
## las dos manos del esqueleto (y asi acompana a la animacion); sin huesos usa un
## anclaje fijo delante del personaje. Reparenta el objeto aqui para "cogerlo".

## Huesos de las manos.
@export var bones: PackedStringArray = ["hand.l", "hand.r"]
## Ajuste local sobre el punto medio (-Z = hacia delante del personaje).
@export var offset := Vector3(0.0, -0.2, -0.3)
## Anclaje de reserva (sin huesos): distancia delante y altura.
@export var fallback_forward := 0.55
@export var fallback_height := 0.75

var _skeleton: Skeleton3D
var _model: Node3D
var _yaw_offset := 0.0
var _bone_a := -1
var _bone_b := -1


func setup(skeleton: Skeleton3D, model: Node3D, model_yaw_offset_deg: float) -> void:
	_model = model
	_yaw_offset = deg_to_rad(model_yaw_offset_deg)
	if skeleton and bones.size() == 2:
		_bone_a = skeleton.find_bone(bones[0])
		_bone_b = skeleton.find_bone(bones[1])
		if _bone_a >= 0 and _bone_b >= 0:
			_skeleton = skeleton


func is_carrying() -> bool:
	return get_child_count() > 0


## Direccion (mundo, XZ) hacia la que mira el modelo.
func facing_direction() -> Vector3:
	var yaw := _model.rotation.y - _yaw_offset if _model else 0.0
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _model == null or not is_carrying():
		return
	rotation.y = _model.rotation.y - _yaw_offset
	if _skeleton:
		var a := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone_a).origin
		var b := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone_b).origin
		global_position = (a + b) * 0.5 + global_transform.basis * offset
	else:
		position = facing_direction() * fallback_forward + Vector3(0.0, fallback_height, 0.0)
