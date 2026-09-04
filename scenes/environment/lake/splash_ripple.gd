class_name SplashRipple
extends MeshInstance3D
## Onda de chapoteo: quad plano con anillos que se expanden y se apagan; se libera solo.
## Uso: SplashRipple.spawn(parent, world_pos, size)

const SHADER := preload("res://scenes/environment/lake/shaders/ripple.gdshader")

var duration := 0.9
var _t := 0.0
var _mat: ShaderMaterial


## `lake`: si se pasa, la onda se recorta con su mascara y no se dibuja sobre tierra.
static func spawn(parent: Node, world_pos: Vector3, size := 1.0, life := 0.9, rings := 1, lake: Node = null) -> SplashRipple:
	var r := SplashRipple.new()
	r.duration = life
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	r.mesh = quad
	r._mat = ShaderMaterial.new()
	r._mat.shader = SHADER
	# Transparente sobre otro transparente (el agua): Godot ordena por distancia del origen a
	# la camara y el centro del lago suele quedar "delante". La prioridad fuerza la onda encima.
	r._mat.render_priority = 2
	r.material_override = r._mat
	r._mat.set_shader_parameter("rings", float(rings))
	if lake and lake.has_method("mask_texture") and lake.mask_texture():
		r._mat.set_shader_parameter("clip_enabled", true)
		r._mat.set_shader_parameter("clip_mask", lake.mask_texture())
		var reg: Rect2 = lake.mask_region_local()
		r._mat.set_shader_parameter("clip_region", Vector4(reg.position.x, reg.position.y, reg.size.x, reg.size.y))
		r._mat.set_shader_parameter("clip_inverse", (lake as Node3D).global_transform.affine_inverse())
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(r)
	r.global_position = world_pos
	r.rotation.x = -PI * 0.5  # quad tumbado sobre el agua
	return r


func _process(delta: float) -> void:
	_t += delta
	var p := _t / duration
	if p >= 1.0:
		queue_free()
		return
	_mat.set_shader_parameter("progress", p)
