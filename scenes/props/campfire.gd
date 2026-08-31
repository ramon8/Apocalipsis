@tool
class_name Campfire
extends Node3D
## Hoguera con dos estados: encendida (llama + humo procedurales estilo pixel + luz con
## parpadeo) y apagada (troncos carbonizados). La base son troncos (cajas con la textura
## `log`) cruzados en estrella. Todo se construye en código: cambia un export y se
## reconstruye en vivo en el editor.

const FIRE_SHADER := preload("res://scenes/props/campfire_fire.gdshader")
const SMOKE_SHADER := preload("res://scenes/props/campfire_smoke.gdshader")

## Estado. También en runtime: campfire.lit = true / toggle().
@export var lit := true:
	set(value):
		lit = value
		_apply_state()

@export_group("Logs")
@export var log_texture: Texture2D = preload("res://assets/textures/log.png"):
	set(value):
		log_texture = value
		_rebuild()
@export_range(3, 8) var log_count := 5:
	set(value):
		log_count = value
		_rebuild()
@export_range(0.3, 2.0, 0.05) var log_length := 0.85:
	set(value):
		log_length = value
		_rebuild()
@export_range(0.03, 0.2, 0.005) var log_radius := 0.07:
	set(value):
		log_radius = value
		_rebuild()
## Tinte de los troncos apagados (carbonizados).
@export var charred_tint := Color(0.35, 0.32, 0.3)

@export_group("Fire")
@export_range(0.2, 3.0, 0.05) var fire_height := 0.9:
	set(value):
		fire_height = value
		_rebuild()
@export_range(0.2, 2.0, 0.05) var fire_width := 0.65:
	set(value):
		fire_width = value
		_rebuild()
@export_range(0.0, 1.5, 0.05) var fire_intensity := 1.0:
	set(value):
		fire_intensity = value
		_update_shader_params()

@export_group("Smoke")
@export var smoke_enabled := true:
	set(value):
		smoke_enabled = value
		_apply_state()
@export_range(0.5, 12.0, 0.1) var smoke_height := 5.0:
	set(value):
		smoke_height = value
		_rebuild()
@export_range(0.2, 6.0, 0.1) var smoke_width := 2.2:
	set(value):
		smoke_width = value
		_rebuild()
@export_range(0.0, 1.0, 0.05) var smoke_density := 0.55:
	set(value):
		smoke_density = value
		_update_shader_params()

@export_group("Light")
@export var light_color := Color(1.0, 0.6, 0.25):
	set(value):
		light_color = value
		if _light:
			_light.light_color = light_color
@export_range(0.0, 8.0, 0.1) var light_energy := 2.2
@export_range(1.0, 20.0, 0.5) var light_range := 6.0:
	set(value):
		light_range = value
		if _light:
			_light.omni_range = light_range
@export_range(0.0, 1.0, 0.05) var flicker_amount := 0.25
@export var light_casts_shadows := true:
	set(value):
		light_casts_shadows = value
		if _light:
			_light.shadow_enabled = light_casts_shadows

var _logs: Node3D
var _fire: Node3D
var _smoke: Node3D
var _light: OmniLight3D
var _fire_mat: ShaderMaterial
var _smoke_mat: ShaderMaterial
var _log_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if not lit or _light == null or Engine.is_editor_hint():
		return
	_t += delta
	var flicker := sin(_t * 9.0) * 0.5 + sin(_t * 23.0 + 1.7) * 0.3 + sin(_t * 5.3 + 4.0) * 0.2
	_light.light_energy = light_energy * (1.0 + flicker * flicker_amount)


func toggle() -> void:
	lit = not lit


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in [_logs, _fire, _smoke, _light]:
		if child:
			child.queue_free()

	# --- Troncos en estrella: cajas alargadas, el extremo exterior en el suelo y el
	# interior apoyado sobre el montón (inclinados hacia el centro).
	_logs = Node3D.new()
	_logs.name = "Logs"
	_log_mat = StandardMaterial3D.new()
	_log_mat.albedo_texture = log_texture
	_log_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_log_mat.roughness = 1.0
	_log_mat.uv1_scale = Vector3(1.0, 3.0, 1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(log_radius * 2.0, log_radius * 2.0, log_length)
	mesh.material = _log_mat
	for i in log_count:
		var log := MeshInstance3D.new()
		log.name = "Log%d" % i
		log.mesh = mesh
		var yaw := TAU * float(i) / float(log_count) + float(i) * 0.37
		log.rotation.y = yaw
		log.rotation.x = -0.45  # inner end raised onto the pile
		log.position = Vector3(sin(yaw), 0.0, cos(yaw)) * log_length * -0.18
		log.position.y = log_radius + log_length * 0.16
		_logs.add_child(log)
	add_child(_logs)

	# --- Llama: un solo quad, el shader lo billboardea hacia la cámara.
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = FIRE_SHADER
	_fire = _make_billboard_quad("Fire", fire_width, fire_height, log_radius * 2.5, _fire_mat)
	add_child(_fire)

	# --- Humo: pluma grande y suave encima de la llama.
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = SMOKE_SHADER
	_smoke = _make_billboard_quad("Smoke", smoke_width, smoke_height, fire_height * 0.7, _smoke_mat)
	add_child(_smoke)

	# --- Luz.
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.position.y = 0.6
	_light.shadow_enabled = light_casts_shadows
	add_child(_light)

	_update_shader_params()
	_apply_state()


func _make_billboard_quad(quad_name: String, width: float, height: float, base_y: float, mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = quad_name
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.y = base_y + height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El shader recoloca los vértices (billboard Y); AABB generosa para que no se recorte.
	mi.custom_aabb = AABB(Vector3(-width - 2.0, -height, -width - 2.0), Vector3(width * 2.0 + 4.0, height * 2.0, width * 2.0 + 4.0))
	root.add_child(mi)
	return root


func _update_shader_params() -> void:
	if _fire_mat:
		_fire_mat.set_shader_parameter("intensity", fire_intensity)
	if _smoke_mat:
		_smoke_mat.set_shader_parameter("density", smoke_density)


func _apply_state() -> void:
	if _fire == null:
		return
	_fire.visible = lit
	_smoke.visible = lit and smoke_enabled
	_light.visible = lit
	_log_mat.albedo_color = Color.WHITE if lit else charred_tint
