class_name XrayVisibility
extends Node
## Silueta plana del personaje cuando queda oculto tras geometria. Aplica `material`
## como material_overlay a todas las mallas del modelo y, si `only_when_fully_hidden`,
## lanza un rayo por cada punto de sondeo desde el lado de la camara: la silueta solo se
## enciende cuando TODOS estan tapados. El dueno llama a tick() cada frame de fisica.

@export var enabled := true
## Material de la silueta. Color, alpha y patron se editan en el recurso.
@export var material: ShaderMaterial = preload("res://scenes/player/shaders/xray_silhouette.tres")
## Solo mostrar la silueta cuando el personaje esta completamente oculto.
## Apagado = se ve en cualquier pixel tapado.
@export var only_when_fully_hidden := true
## Capas de fisica que cuentan como oclusores visuales
## (1 = mundo, 4 = props, 8 = areas oclusoras de follaje de BillboardTree).
@export_flags_3d_physics var occluder_mask := 1 | 4 | 8
## Puntos del cuerpo (locales, metros) que deben estar TODOS tapados.
@export var probe_points: PackedVector3Array = PackedVector3Array([
	Vector3(0.0, 1.6, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.3, 0.0),
	Vector3(0.3, 1.1, 0.0), Vector3(-0.3, 1.1, 0.0), Vector3(0.0, 1.1, 0.3), Vector3(0.0, 1.1, -0.3)])
@export_range(0.0, 1.0, 0.05) var fade_time := 0.15

var _body: CollisionObject3D
var _mat: ShaderMaterial
var _full_alpha := 0.75
var _hidden := false
var _tween: Tween


## true si el modelo debe escribir stencil (la silueta salta la auto-oclusion).
func is_active() -> bool:
	return enabled and material != null


## Copia el material (el alpha se anima por instancia) y lo aplica como overlay.
func setup(body: CollisionObject3D, model: Node) -> void:
	if not is_active():
		return
	_body = body
	_mat = material.duplicate() as ShaderMaterial
	_full_alpha = float(_mat.get_shader_parameter("alpha"))
	if only_when_fully_hidden:
		_mat.set_shader_parameter("alpha", 0.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _mat
	if model is MeshInstance3D:
		(model as MeshInstance3D).material_overlay = _mat


func tick() -> void:
	if _mat == null or _body == null or not only_when_fully_hidden:
		return
	var cam := _body.get_viewport().get_camera_3d()
	if cam == null:
		return
	var space := _body.get_world_3d().direct_space_state
	var forward := -cam.global_transform.basis.z
	var all_hidden := true
	for offset in probe_points:
		var target: Vector3 = _body.global_position + offset
		var origin := target - forward * 60.0
		var query := PhysicsRayQueryParameters3D.create(origin, target, occluder_mask, [_body.get_rid()])
		query.collide_with_areas = true
		query.collide_with_bodies = true
		if space.intersect_ray(query).is_empty():
			all_hidden = false
			break
	if all_hidden == _hidden:
		return
	_hidden = all_hidden
	if _tween and _tween.is_valid():
		_tween.kill()
	var target_alpha := _full_alpha if all_hidden else 0.0
	if fade_time <= 0.0:
		_mat.set_shader_parameter("alpha", target_alpha)
		return
	_tween = create_tween()
	_tween.tween_method(func(a: float) -> void: _mat.set_shader_parameter("alpha", a),
			float(_mat.get_shader_parameter("alpha")), target_alpha, fade_time)
