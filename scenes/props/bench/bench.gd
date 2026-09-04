@tool
class_name LogBench
extends StaticBody3D
## Banco de troncos generado por codigo: dos troncos cortos de apoyo y encima uno o
## varios troncos (medio partidos) como asiento; respaldo opcional. Madera procedural
## con la paleta del juego (wood.gdshader). Colision en caja.

@export_group("Forma")
@export_range(0.6, 4.0, 0.05) var length := 1.8:
	set(v):
		length = v
		_rebuild()
## Altura del asiento (m) y radio de los troncos del asiento.
@export_range(0.2, 0.8, 0.01) var seat_height := 0.42:
	set(v):
		seat_height = v
		_rebuild()
@export_range(0.05, 0.3, 0.005) var seat_log_radius := 0.13:
	set(v):
		seat_log_radius = v
		_rebuild()
@export_range(1, 3) var seat_logs := 2:
	set(v):
		seat_logs = v
		_rebuild()
## Radio de los troncos de apoyo (patas).
@export_range(0.05, 0.3, 0.005) var leg_radius := 0.15:
	set(v):
		leg_radius = v
		_rebuild()
@export var backrest := false:
	set(v):
		backrest = v
		_rebuild()
@export_range(0.2, 0.8, 0.01) var backrest_height := 0.4:
	set(v):
		backrest_height = v
		_rebuild()
## Los troncos del asiento van con la cara plana arriba (medio tronco).
@export var split_logs := true:
	set(v):
		split_logs = v
		_rebuild()

@export_group("Madera")
@export var wood_light := Color("a09878"):
	set(v):
		wood_light = v
		_set_param("wood_light", v)
@export var wood_dark := Color("866350"):
	set(v):
		wood_dark = v
		_set_param("wood_dark", v)
@export var bark_color := Color("432015"):
	set(v):
		bark_color = v
		_set_param("bark_color", v)
@export var bark_dark := Color("1c1009"):
	set(v):
		bark_dark = v
		_set_param("bark_dark", v)
@export_range(1.0, 40.0, 0.5) var grain_density := 9.0:
	set(v):
		grain_density = v
		_set_param("grain_density", v)
@export_range(2.0, 40.0, 0.5) var ring_density := 14.0:
	set(v):
		ring_density = v
		_set_param("ring_density", v)
@export var palette_snap := true:
	set(v):
		palette_snap = v
		_set_param("palette_snap", v)
@export var seed := 0:
	set(v):
		seed = v
		_rebuild()

const WOOD_SHADER := preload("res://scenes/props/bench/shaders/wood.gdshader")

var _parts: Node3D
var _shape: CollisionShape3D
var _mats: Array[ShaderMaterial] = []


func _ready() -> void:
	_rebuild()


func _set_param(pname: String, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(pname, value)


func _wood_material(bark: float, seed_off: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD_SHADER
	for p in ["wood_light", "wood_dark", "bark_color", "bark_dark", "grain_density",
			"ring_density", "palette_snap"]:
		m.set_shader_parameter(p, get(p))
	m.set_shader_parameter("bark_amount", bark)
	m.set_shader_parameter("seed_offset", seed_off)
	_mats.append(m)
	return m


func _log(radius: float, len: float, bark: float, seed_off: float, half := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = len
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.material = _wood_material(bark, seed_off)
	mi.mesh = cyl
	if half:
		# Medio tronco: se aplasta un poco en vertical y se hunde para dejar la cara
		# plana arriba (la parte de abajo queda escondida en el apoyo).
		mi.scale = Vector3(1.0, 1.0, 0.72)
	return mi


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _parts:
		_parts.free()
	if _shape:
		_shape.free()
	_mats.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))

	_parts = Node3D.new()
	_parts.name = "Parts"
	add_child(_parts)

	# Patas: dos troncos cortos tumbados a lo ancho (eje Z), uno en cada extremo.
	var leg_len := seat_log_radius * 2.0 * float(seat_logs) + 0.16
	var leg_y := leg_radius
	for sx in [-1.0, 1.0]:
		var leg := _log(leg_radius, leg_len, 1.0, rng.randf() * 100.0)
		leg.rotation.x = PI * 0.5  # eje Y del cilindro -> Z
		leg.position = Vector3(sx * (length * 0.5 - leg_radius * 1.4), leg_y, 0.0)
		_parts.add_child(leg)

	# Asiento: troncos a lo largo (eje X), apoyados sobre las patas.
	var seat_y := leg_radius * 2.0 + seat_log_radius * (0.72 if split_logs else 1.0)
	var total_w := seat_log_radius * 2.0 * float(seat_logs)
	for i in seat_logs:
		var z := -total_w * 0.5 + seat_log_radius + float(i) * seat_log_radius * 2.0
		var log := _log(seat_log_radius, length, 0.0 if split_logs else 1.0, rng.randf() * 100.0, split_logs)
		log.rotation.z = PI * 0.5  # eje Y -> X
		log.position = Vector3(0.0, seat_y, z)
		log.rotation.x = rng.randf_range(-0.03, 0.03)
		_parts.add_child(log)
	# La altura de asiento pedida se respeta escalando las patas si hace falta.
	var actual := seat_y + seat_log_radius * (0.72 if split_logs else 1.0)
	if actual > 0.0:
		_parts.scale.y = seat_height / actual

	if backrest:
		var back := _log(seat_log_radius * 0.8, length, 1.0, rng.randf() * 100.0)
		back.rotation.z = PI * 0.5
		back.position = Vector3(0.0, actual + backrest_height, -total_w * 0.5 - seat_log_radius * 0.6)
		_parts.add_child(back)
		for sx in [-1.0, 1.0]:
			var post := _log(seat_log_radius * 0.6, backrest_height + seat_log_radius, 1.0, rng.randf() * 100.0)
			post.position = Vector3(sx * (length * 0.5 - leg_radius * 1.4), actual + backrest_height * 0.5, -total_w * 0.5 - seat_log_radius * 0.6)
			_parts.add_child(post)

	# Colision: caja del asiento.
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, seat_height, total_w + 0.16)
	_shape.shape = box
	_shape.position = Vector3(0.0, seat_height * 0.5, 0.0)
	add_child(_shape)
