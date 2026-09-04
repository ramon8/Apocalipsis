@tool
class_name HayPile
extends Node3D
## Pila de heno (monticulo) instanciable: shader de paja suelta, colision convexa
## automatica y, opcionalmente, una horca clavada generada por codigo y configurable.

@export_group("Straw")
@export var straw_light := Color(0.7529412, 0.75686276, 0.53333336):
	set(v):
		straw_light = v
		_set_param("straw_light", v)
@export var straw_dark := Color(0.5254902, 0.3882353, 0.3137255):
	set(v):
		straw_dark = v
		_set_param("straw_dark", v)
@export var straw_green := Color(0.627451, 0.59607846, 0.47058824):
	set(v):
		straw_green = v
		_set_param("straw_green", v)
@export_range(0.0, 1.0, 0.05) var green_amount := 0.25:
	set(v):
		green_amount = v
		_set_param("green_amount", v)
@export_range(0.0, 1.0, 0.05) var base_darkening := 0.45:
	set(v):
		base_darkening = v
		_set_param("base_darkening", v)
@export_range(2.0, 40.0, 1.0) var strand_density := 12.0:
	set(v):
		strand_density = v
		_set_param("strand_density", v)
@export_range(1.0, 20.0, 0.5) var strand_stretch := 6.0:
	set(v):
		strand_stretch = v
		_set_param("strand_stretch", v)
@export_range(0.0, 1.0, 0.05) var strand_contrast := 0.7:
	set(v):
		strand_contrast = v
		_set_param("strand_contrast", v)
@export_range(0.0, 1.0, 0.05) var loose_amount := 0.35:
	set(v):
		loose_amount = v
		_set_param("loose_amount", v)

@export_group("Retro")
@export_range(1.0, 32.0, 1.0) var texels_per_unit := 6.0:
	set(v):
		texels_per_unit = v
		_set_param("texels_per_unit", v)
@export_range(0, 16) var levels := 6:
	set(v):
		levels = v
		_set_param("levels", v)
@export var seed := 0

@export_group("Collision")
@export var collision_enabled := true:
	set(v):
		collision_enabled = v
		_rebuild_collision()

@export_group("Tool (horca clavada)")
@export var tool_enabled := true:
	set(v):
		tool_enabled = v
		_rebuild_tool()
## Donde esta clavada: angulo alrededor de la pila (grados) y distancia al centro (0 = cima).
@export_range(0.0, 360.0, 1.0) var tool_angle_deg := 40.0:
	set(v):
		tool_angle_deg = v
		_rebuild_tool()
@export_range(0.0, 1.0, 0.05) var tool_distance := 0.5:
	set(v):
		tool_distance = v
		_rebuild_tool()
## Inclinacion del mango respecto a la vertical (grados) y giro sobre si misma.
@export_range(0.0, 80.0, 1.0) var tool_tilt_deg := 28.0:
	set(v):
		tool_tilt_deg = v
		_rebuild_tool()
@export_range(0.0, 360.0, 1.0) var tool_yaw_deg := 0.0:
	set(v):
		tool_yaw_deg = v
		_rebuild_tool()
## Largo del mango (m), ancho de la cabeza (m) y grosor (m).
@export_range(0.5, 3.0, 0.05) var tool_length := 1.9:
	set(v):
		tool_length = v
		_rebuild_tool()
@export_range(0.1, 1.0, 0.02) var tool_width := 0.42:
	set(v):
		tool_width = v
		_rebuild_tool()
@export_range(0.02, 0.15, 0.005) var tool_thickness := 0.08:
	set(v):
		tool_thickness = v
		_rebuild_tool()
## Cuanto del mango queda hundido en la paja (m).
@export_range(0.0, 1.0, 0.05) var tool_sink := 0.1:
	set(v):
		tool_sink = v
		_rebuild_tool()
@export_range(2, 5) var tool_tines := 3:
	set(v):
		tool_tines = v
		_rebuild_tool()
@export var handle_color := Color(0.45, 0.3, 0.16):
	set(v):
		handle_color = v
		_rebuild_tool()
@export var head_color := Color(0.28, 0.28, 0.3):
	set(v):
		head_color = v
		_rebuild_tool()

const PILE_SHADER := preload("res://scenes/props/heno/shaders/heno_pile.gdshader")

var _mats: Array[ShaderMaterial] = []
var _mesh: MeshInstance3D
var _collision: StaticBody3D
var _tool: Node3D
var _height := 2.5  # altura del monticulo en unidades del nodo
var _radius := 2.2


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		push_warning("HayPile: falta el hijo 'Model' (instancia de heno_variant.glb).")
		return
	_mesh = model.find_child("*", true, false) as MeshInstance3D
	if _mesh == null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			_mesh = mi
			break
	if _mesh == null:
		return
	var aabb := _mesh.get_aabb()
	var s: Vector3 = model.scale * _mesh.scale
	_height = aabb.end.y * s.y
	_radius = minf(aabb.size.x * s.x, aabb.size.z * s.z) * 0.5
	_apply_materials(aabb)
	_rebuild_collision()
	_rebuild_tool()


func _set_param(pname: String, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(pname, value)


func _apply_materials(aabb: AABB) -> void:
	_mats.clear()
	for i in _mesh.get_surface_override_material_count():
		var sm := ShaderMaterial.new()
		sm.shader = PILE_SHADER
		for p in ["straw_light", "straw_dark", "straw_green", "green_amount", "base_darkening",
				"strand_density", "strand_stretch", "strand_contrast", "loose_amount",
				"texels_per_unit", "levels"]:
			sm.set_shader_parameter(p, get(p))
		sm.set_shader_parameter("pile_height", aabb.end.y)
		var sd := seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
		sm.set_shader_parameter("seed_offset", float(sd % 1000))
		_mesh.set_surface_override_material(i, sm)
		_mats.append(sm)


## Colision convexa a partir de la malla (el export no trae -col).
func _rebuild_collision() -> void:
	if _collision:
		_collision.free()
		_collision = null
	if not collision_enabled or _mesh == null or Engine.is_editor_hint():
		return
	var shape := _mesh.mesh.create_convex_shape(true, true)
	_collision = StaticBody3D.new()
	_collision.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_collision.add_child(cs)
	_mesh.add_child(_collision)  # mismo espacio que la malla (hereda su transform)


## Horca low-poly: mango + travesano + puas, clavada en la ladera segun los exports.
func _rebuild_tool() -> void:
	if _tool:
		_tool.free()
		_tool = null
	if not tool_enabled or _mesh == null:
		return
	_tool = Node3D.new()
	_tool.name = "Pitchfork"
	add_child(_tool)

	# Punto de la superficie: en la ladera del monticulo (aprox. semiesfera).
	var a := deg_to_rad(tool_angle_deg)
	var d := tool_distance * _radius
	var y := _height * sqrt(maxf(1.0 - pow(d / _radius, 2.0), 0.0))
	_tool.position = Vector3(cos(a) * d, y - tool_sink, sin(a) * d)
	# Inclinada hacia fuera del monticulo, mas el giro propio.
	_tool.rotation = Vector3(0.0, -a + deg_to_rad(tool_yaw_deg), 0.0)
	_tool.rotate_object_local(Vector3.BACK, -deg_to_rad(tool_tilt_deg))

	var wood := StandardMaterial3D.new()
	wood.albedo_color = handle_color
	wood.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = head_color
	metal.roughness = 0.6

	var th := tool_thickness
	# Mango (a lo largo de +Y local).
	var handle := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(th, tool_length, th)
	hb.material = wood
	handle.mesh = hb
	handle.position = Vector3(0.0, tool_length * 0.5, 0.0)
	_tool.add_child(handle)
	# Puño en la punta superior.
	var grip := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(th * 3.0, th * 1.2, th * 1.2)
	gb.material = wood
	grip.mesh = gb
	grip.position = Vector3(0.0, tool_length, 0.0)
	_tool.add_child(grip)
	# Travesano metalico en la base + puas hacia abajo (hundidas en la paja).
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(tool_width, th * 1.1, th * 1.1)
	bb.material = metal
	bar.mesh = bb
	bar.position = Vector3(0.0, 0.0, 0.0)
	_tool.add_child(bar)
	var tine_len := tool_width * 0.9
	for i in tool_tines:
		var x := -tool_width * 0.5 + tool_width * (float(i) + 0.5) / float(tool_tines)
		var tine := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(th * 0.8, tine_len, th * 0.8)
		tb.material = metal
		tine.mesh = tb
		tine.position = Vector3(x, -tine_len * 0.5, 0.0)
		_tool.add_child(tine)
