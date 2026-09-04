class_name SplashRipple
extends MeshInstance3D
## Onda de chapoteo: quad plano con anillos que se expanden y se apagan; se libera solo.
## Uso: SplashRipple.spawn(parent, world_pos, size)

const SHADER := preload("res://scenes/environment/lake/shaders/ripple.gdshader")

var duration := 0.9
var _t := 0.0
var _mat: ShaderMaterial


static func spawn(parent: Node, world_pos: Vector3, size := 1.0, life := 0.9) -> SplashRipple:
	var r := SplashRipple.new()
	r.duration = life
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	r.mesh = quad
	r._mat = ShaderMaterial.new()
	r._mat.shader = SHADER
	r.material_override = r._mat
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
