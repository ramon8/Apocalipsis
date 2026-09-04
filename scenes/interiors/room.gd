@tool
class_name Room
extends Node3D
## Habitacion (interior de un edificio) como escena independiente, identificada por
## `room_id`. Se registra en RoomManager al entrar en el arbol.
##
## Para crear una habitacion: escena heredada de room.tscn (clic derecho -> Nueva escena
## heredada), ponle un room_id unico, decorala añadiendo props como hijos (se colocan
## sobre el suelo de previsualizacion) y asignala al edificio (Molino.interior_scene).
##
## "Estar dentro" es un estado logico de la habitacion (lista de ocupantes + colision de
## paredes), valido para el jugador Y para NPCs. El cambio de vista (void negro, capas de
## render, camara) solo se aplica cuando el ocupante que entra/sale es el jugador.
## En runtime todo el subarbol pasa solo a la capa de render interior: no hay que tocar
## layers de los props.

signal occupant_entered(body: Node3D)
signal occupant_exited(body: Node3D)

const FLOOR_SHADER := preload("res://scenes/interiors/shaders/room_floor.gdshader")
const CORRIDOR_SHADER := preload("res://scenes/interiors/shaders/room_corridor.gdshader")
const INTERIOR_LAYER := 2  # bit 2 de capas de render (modo interior de la camara)

## Identificador unico de la habitacion (para RoomManager, guardado, NPCs...).
@export var room_id: StringName = &""
## Radio del suelo. 0 = lo fija el edificio que la usa (auto por su modelo).
@export var radius := 0.0:
	set(value):
		radius = value
		_rebuild()
## Direccion de la puerta (grados, 0 = +Z local): hueco en las paredes de colision.
@export var door_angle_deg := 0.0:
	set(value):
		door_angle_deg = value
		_rebuild()
@export var door_width := 1.4:
	set(value):
		door_width = value
		_rebuild()

@export_group("Pasillo de salida")
## Suelo corto que sale por la puerta y se funde a negro con el void.
@export var corridor_enabled := true:
	set(value):
		corridor_enabled = value
		_rebuild()
@export var corridor_length := 1.8:
	set(value):
		corridor_length = value
		_rebuild()
@export var corridor_color := Color(0.95, 0.94, 0.9):
	set(value):
		corridor_color = value
		_rebuild()
## Curva del fundido (1 = lineal, >1 = se mantiene claro mas tiempo y cae al final).
@export_range(0.5, 4.0, 0.1) var corridor_fade_power := 1.6:
	set(value):
		corridor_fade_power = value
		_rebuild()

@export_group("Suelo")
@export var floor_base_color := Color(0.32, 0.26, 0.19):
	set(value):
		floor_base_color = value
		_rebuild()
@export var floor_dirt_color := Color(0.16, 0.12, 0.08):
	set(value):
		floor_dirt_color = value
		_rebuild()
@export_range(0.0, 1.0, 0.05) var floor_dirt_amount := 0.55:
	set(value):
		floor_dirt_amount = value
		_rebuild()

@export_group("Vista interior (jugador)")
@export var void_color := Color(0.01, 0.008, 0.006)
@export var ambient_color := Color(1.0, 0.9, 0.75)
@export_range(0.0, 2.0, 0.05) var ambient_energy := 0.55
## Luz propia de la habitacion (el sol NO entra: fuera, el edificio oculto proyectaria
## su sombra sobre el jugador y lo dejaria negro). Omni suave desde arriba.
@export var room_light_enabled := true
@export var room_light_color := Color(1.0, 0.92, 0.78)
@export_range(0.0, 8.0, 0.1) var room_light_energy := 2.2

## Radio que impone el edificio cuando `radius` es 0.
var auto_radius := 3.4
var occupants: Array[Node3D] = []

var _floor: MeshInstance3D
var _walls: StaticBody3D
var _corridor: Node3D
var _view_env: Environment
var _light: OmniLight3D
var _saved_cull := 0xFFFFF
var _saved_env: Environment
var _saved_sun_masks := {}  # DirectionalLight3D -> light_cull_mask previo
var _player_view_active := false


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		_apply_layers(self)
		_set_active(false)


# Registro en enter/exit (no en _ready): RetroRenderer reparenta la escena al arrancar,
# lo que dispara _exit_tree + _enter_tree sin volver a llamar a _ready.
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		RoomManager.register(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		RoomManager.unregister(self)


func effective_radius() -> float:
	return radius if radius > 0.0 else auto_radius


func has_occupant(body: Node3D) -> bool:
	return occupants.has(body)


func is_player_inside() -> bool:
	return _player_view_active


## Mete a un cuerpo (jugador o NPC) en la habitacion. Con el primer ocupante se activan
## las paredes; si es el jugador, ademas cambia la vista al interior.
func enter(body: Node3D) -> void:
	if body == null or occupants.has(body):
		return
	occupants.append(body)
	_set_active(true)
	if body is Player:
		_apply_player_view(body)
	occupant_entered.emit(body)
	RoomManager.occupant_entered.emit(self, body)


func exit(body: Node3D) -> void:
	if not occupants.has(body):
		return
	occupants.erase(body)
	if body is Player:
		_restore_player_view(body)
	if occupants.is_empty():
		_set_active(false)
	occupant_exited.emit(body)
	RoomManager.occupant_exited.emit(self, body)


## Visible + paredes con colision solo mientras hay alguien dentro.
func _set_active(on: bool) -> void:
	visible = on
	if _walls:
		_walls.collision_layer = 1 if on else 0


## Cambio seamless: la camara no se mueve. Solo cambia la mascara de render (mundo
## exterior -> esta habitacion + void negro) y el jugador se añade a la capa interior.
func _apply_player_view(player: Node3D) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _player_view_active:
		return
	if _view_env == null:
		_view_env = Environment.new()
		_view_env.background_mode = Environment.BG_COLOR
		_view_env.background_color = void_color
		_view_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_view_env.ambient_light_color = ambient_color
		_view_env.ambient_light_energy = ambient_energy
	_player_view_active = true
	_saved_cull = cam.cull_mask
	_saved_env = cam.environment
	cam.cull_mask = INTERIOR_LAYER
	cam.environment = _view_env
	# El jugador pasa a estar SOLO en la capa interior, y los soles/lunas dejan de
	# iluminar esa capa: sin luz solar ni sombras del edificio oculto dentro.
	_set_subtree_layer(player, INTERIOR_LAYER)
	_saved_sun_masks.clear()
	for sun in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_saved_sun_masks[sun] = sun.light_cull_mask
		sun.light_cull_mask &= ~INTERIOR_LAYER


func _restore_player_view(player: Node3D) -> void:
	if not _player_view_active:
		return
	_player_view_active = false
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.cull_mask = _saved_cull
		cam.environment = _saved_env
	if is_instance_valid(player):
		_set_subtree_layer(player, 1)
	for sun in _saved_sun_masks:
		if is_instance_valid(sun):
			sun.light_cull_mask = _saved_sun_masks[sun]
	_saved_sun_masks.clear()


func _set_subtree_layer(root: Node, layers: int) -> void:
	for vi in root.find_children("*", "VisualInstance3D", true, false):
		vi.layers = layers


## Todo el subarbol (suelo, pasillo y props de la escena) a la capa interior.
func _apply_layers(node: Node) -> void:
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		vi.layers = INTERIOR_LAYER
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = INTERIOR_LAYER


# ------------------------------------------------------------------ geometria

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in [_floor, _walls, _corridor]:
		if n:
			n.free()
	_floor = null
	_walls = null
	_corridor = null
	var r := effective_radius()

	# Suelo: abanico con el shader de tierra sucia.
	_floor = MeshInstance3D.new()
	_floor.name = "Floor"
	_floor.mesh = _make_floor_mesh(r, 16)
	_floor.position.y = 0.02  # sobre el terreno exterior: al solaparse gana este
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("base_color", floor_base_color)
	mat.set_shader_parameter("dirt_color", floor_dirt_color)
	mat.set_shader_parameter("dirt_amount", floor_dirt_amount)
	mat.set_shader_parameter("floor_radius", r)
	mat.set_shader_parameter("seed_offset", float(hash(String(room_id) + name) % 1000))
	_floor.material_override = mat
	add_child(_floor)

	# Paredes de colision: anillo de segmentos con hueco en la puerta.
	_walls = StaticBody3D.new()
	_walls.name = "Walls"
	_walls.collision_layer = 0
	var segments := 16
	var door_rad := deg_to_rad(door_angle_deg)
	var half_gap: float = asin(clampf(door_width * 0.5 / r, 0.0, 1.0))
	for i in segments:
		var a := TAU * (float(i) + 0.5) / float(segments)
		if absf(angle_difference(a, door_rad)) < half_gap + TAU / float(segments) * 0.5:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var seg_len := TAU * r / float(segments)
		box.size = Vector3(seg_len * 1.15, 4.0, 0.3)
		shape.shape = box
		shape.position = Vector3(sin(a), 0.0, cos(a)) * r + Vector3(0.0, 2.0, 0.0)
		shape.rotation.y = a
		_walls.add_child(shape)
	add_child(_walls)

	if corridor_enabled:
		_build_corridor(door_rad, r)

	# Luz de la habitacion: omni suave sobre el centro, solo para la capa interior.
	if _light:
		_light.free()
		_light = null
	if room_light_enabled and not Engine.is_editor_hint():
		_light = OmniLight3D.new()
		_light.name = "RoomLight"
		_light.light_color = room_light_color
		_light.light_energy = room_light_energy
		_light.omni_range = r * 3.0
		_light.omni_attenuation = 1.2
		_light.light_cull_mask = INTERIOR_LAYER
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, r * 1.1, 0.0)
		add_child(_light)

	if not Engine.is_editor_hint():
		_apply_layers(self)


## Pasillo de salida: suelo claro desde la puerta hacia fuera que se funde a negro
## con el void (sin pared de luz). Solo existe dentro (es parte de la habitacion).
func _build_corridor(door_rad: float, r: float) -> void:
	_corridor = Node3D.new()
	_corridor.name = "ExitCorridor"
	_corridor.position = Vector3(sin(door_rad), 0.0, cos(door_rad)) * r
	_corridor.rotation.y = door_rad
	add_child(_corridor)

	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "CorridorFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(door_width, corridor_length)
	var mat := ShaderMaterial.new()
	mat.shader = CORRIDOR_SHADER
	mat.set_shader_parameter("color", corridor_color)
	mat.set_shader_parameter("length", corridor_length)
	mat.set_shader_parameter("fade_power", corridor_fade_power)
	plane.material = mat
	floor_mi.mesh = plane
	floor_mi.position = Vector3(0.0, 0.03, corridor_length * 0.5)  # local +Z = hacia fuera
	_corridor.add_child(floor_mi)


func _make_floor_mesh(r: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var indices := PackedInt32Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		verts.append(Vector3(sin(a) * r, 0.0, cos(a) * r))
	for i in segments:
		indices.append_array([0, 1 + i, 1 + (i + 1) % segments])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
