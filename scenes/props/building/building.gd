@tool
class_name Building
extends Node3D
## Edificio con interior visitable: base comun de casas, molinos, iglesia... Espera un hijo
## "Model" (instancia del GLB, con colision -col). Se encarga de:
##  - materiales: shader de envejecido (mugre, descolorido, humedad en la base) sobre la
##    textura del import, o nearest si `weathered` esta apagado
##  - interior: una Room (escena heredada de room.tscn) centrada en el AABB del modelo, con
##    el radio que cabe dentro, y la zona de la puerta (E: Entrar/Salir) en la cara `door_angle_deg`
##  - abre la puerta apagando la colision del modelo mientras hay alguien dentro, y pide la
##    despedida a los NPC de la habitacion al salir
## Las subclases (Molino) anaden lo suyo (aspas) y pueden fijar `bounds_mesh_name`.

const WEATHER_SHADER := preload("res://scenes/props/molino/shaders/molino_weathered.gdshader")

## Pixeles nitidos, como el resto de props.
@export var nearest_texture_filter := true

@export_group("Weathering")
## Aplicar el shader de viejo/ruinoso (mugre y suciedad procedurales).
@export var weathered := true:
	set(value):
		weathered = value
		_refresh_materials.call_deferred()
## Manchas de mugre.
@export_range(0.0, 1.0, 0.05) var grime_amount := 0.35:
	set(value):
		grime_amount = value
		_set_weather_param("grime_amount", value)
## Descolorido general por el sol.
@export_range(0.0, 1.0, 0.05) var weathering_amount := 0.25:
	set(value):
		weathering_amount = value
		_set_weather_param("weathering", value)
## Suciedad/humedad que sube desde la base.
@export_range(0.0, 1.0, 0.05) var dirt_amount := 0.4:
	set(value):
		dirt_amount = value
		_set_weather_param("dirt_amount", value)
## Altura (unidades del modelo) hasta la que sube la suciedad de la base.
@export_range(0.0, 40.0, 0.5) var dirt_height := 6.0:
	set(value):
		dirt_height = value
		_set_weather_param("dirt_height", value)

@export_group("Interior")
## Generar interior visitable (E en la puerta para entrar).
@export var interior_enabled := true
## Habitacion de ESTE edificio: escena heredada de scenes/interiors/room.tscn con su
## room_id (organizalas por carpetas, p. ej. scenes/interiors/molinos/).
@export var interior_scene: PackedScene = preload("res://scenes/interiors/room.tscn")
## Planta del interior: rectangulo (casas) o circulo (torres). Rectangulo = la del modelo.
@export var interior_shape := Room.Shape.RECTANGLE
## Radio del suelo interior en metros (circulo). 0 = auto: el mayor circulo que cabe en la
## planta (la habitacion puede fijar el suyo propio con Room.radius > 0).
@export var interior_radius := 0.0
## Encogimiento de la planta rectangular respecto al modelo (paredes con grosor).
@export_range(0.5, 1.0, 0.01) var interior_rect_fit := 0.9
## Direccion de la puerta en grados (local, 0 = +Z). Ajustar hasta que coincida con el modelo.
@export var door_angle_deg := 0.0
## Ancho del hueco de la puerta (m).
@export var door_width := 1.4
## Malla del modelo que define la planta (vacio = todas las mallas). Sirve para excluir
## partes que sobresalen, como las aspas de un molino.
@export var bounds_mesh_name := ""
@export var prompt_enter_text := "Entrar"
@export var prompt_exit_text := "Salir"

var _weather_mats: Array[ShaderMaterial] = []
var _room: Room
var _radius := 2.0
var _centre := Vector3.ZERO  # centro de la planta (local)
var _half := Vector2(2.0, 2.0)  # semiejes de la planta (local, XZ)
var _door: InteractionZone
var _player_inside: Player
var _exit_hold := false  # despedida en curso: la salida espera


func _ready() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		push_warning("%s: falta el hijo 'Model' (instancia del GLB)." % name)
		return
	_setup_model(model)
	_refresh_materials()
	if interior_enabled and not Engine.is_editor_hint():
		_build_interior()


## Gancho para subclases (buscar nodos del modelo, etc.).
func _setup_model(_model: Node) -> void:
	pass


func _process(_delta: float) -> void:
	# Salida automatica: el jugador sale ANDANDO por el pasillo; al llegar al fondo
	# (donde el suelo ya se ha fundido a negro) restauramos el exterior.
	if _is_player_inside():
		var local := to_local(_player_inside.global_position) - _centre
		if Vector2(local.x, local.z).length() > _room.door_distance() + _room.corridor_length * 0.8:
			_exit_interior()


# ------------------------------------------------------------------ materiales

func _refresh_materials() -> void:
	var model := get_node_or_null("Model")
	if model == null or not is_inside_tree():
		return
	_weather_mats.clear()
	_apply_materials(model)


func _set_weather_param(pname: String, value: float) -> void:
	for m in _weather_mats:
		m.set_shader_parameter(pname, value)


## Sustituye los materiales del import: shader de envejecido (con la textura original
## como albedo) o, si weathered esta apagado, la BaseMaterial3D con filtro nearest.
func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			var base := mat as BaseMaterial3D
			if base == null and mat is ShaderMaterial:
				mi.set_surface_override_material(i, null)  # reevaluar el del import
				base = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			if weathered:
				var sm := ShaderMaterial.new()
				sm.shader = WEATHER_SHADER
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				sm.set_shader_parameter("grime_amount", grime_amount)
				sm.set_shader_parameter("weathering", weathering_amount)
				sm.set_shader_parameter("dirt_amount", dirt_amount)
				sm.set_shader_parameter("dirt_height", dirt_height)
				# Patron distinto por edificio, estable entre sesiones.
				sm.set_shader_parameter("seed_offset", float(hash(global_position.snapped(Vector3.ONE * 0.01)) % 1000))
				mi.set_surface_override_material(i, sm)
				_weather_mats.append(sm)
			else:
				var copy := base.duplicate() as BaseMaterial3D
				if nearest_texture_filter:
					copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mi.set_surface_override_material(i, copy)
	for child in node.get_children():
		_apply_materials(child)


# ------------------------------------------------------------------ interior

## Planta del edificio en coordenadas locales de este nodo: centro y semiejes XZ, desde el
## AABB de `bounds_mesh_name` (o de todas las mallas).
func _compute_footprint(model: Node3D) -> void:
	var meshes: Array[Node] = []
	if bounds_mesh_name != "":
		var m := model.find_child(bounds_mesh_name, true, false)
		if m is MeshInstance3D:
			meshes.append(m)
	if meshes.is_empty():
		meshes = model.find_children("*", "MeshInstance3D", true, false)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in meshes:
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()
		var xf := global_transform.affine_inverse() * mi.global_transform  # malla -> local del edificio
		for i in 8:
			var corner := xf * aabb.get_endpoint(i)
			lo = lo.min(corner)
			hi = hi.max(corner)
	if lo.x == INF:
		return
	_centre = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.z + hi.z) * 0.5)
	_half = Vector2((hi.x - lo.x) * 0.5, (hi.z - lo.z) * 0.5)


## Distancia del centro al borde de la planta (rectangulo) en la direccion `dir` (XZ).
func _edge_distance(dir: Vector2) -> float:
	var tx := INF if absf(dir.x) < 0.0001 else _half.x / absf(dir.x)
	var tz := INF if absf(dir.y) < 0.0001 else _half.y / absf(dir.y)
	return minf(tx, tz)


func _build_interior() -> void:
	var model := get_node_or_null("Model") as Node3D
	_compute_footprint(model)
	_radius = interior_radius if interior_radius > 0.0 else minf(_half.x, _half.y) * 0.92

	# La habitacion es una escena propia (heredada de room.tscn); oculta hasta entrar.
	var scene := interior_scene if interior_scene else preload("res://scenes/interiors/room.tscn")
	_room = scene.instantiate() as Room
	if _room == null:
		push_warning("%s: interior_scene no es una Room (heredala de scenes/interiors/room.tscn)." % name)
		return
	_room.name = "Interior"
	_room.shape = interior_shape
	_room.auto_radius = _radius
	_room.auto_rect = _half * 2.0 * interior_rect_fit
	_room.door_angle_deg = door_angle_deg
	_room.door_width = door_width
	_room.position = _centre
	add_child(_room)
	_radius = _room.effective_radius()  # la habitacion puede imponer el suyo
	_room.occupant_entered.connect(_on_room_occupant_changed)
	_room.occupant_exited.connect(_on_room_occupant_changed)

	# Zona de la puerta (dentro Y fuera) en el punto de la puerta de la habitacion: prompt
	# Entrar/Salir. Cuelga del edificio, no de la habitacion, para estar activa tambien fuera.
	var dp := _room.door_point()
	_door = InteractionZone.new()
	_door.name = "DoorZone"
	_door.radius = 1.7
	_door.height = 0.0
	_door.interact_priority = 2
	_door.position = _centre + Vector3(dp.x, 0.5, dp.y)
	add_child(_door)


func _is_player_inside() -> bool:
	return _room != null and is_instance_valid(_player_inside) and _room.has_occupant(_player_inside)


# ------------------------------------------------------------------ InteractionZone

func can_interact(_player: Player) -> bool:
	return not _exit_hold


func interaction_prompt(_player: Player) -> String:
	return prompt_exit_text if _is_player_inside() else prompt_enter_text


func interact_with(player: Player) -> void:
	if _is_player_inside():
		_exit_interior()
	else:
		_enter_interior(player)


## La habitacion gestiona la vista (void, capas) y sus paredes; el edificio solo abre
## la puerta: apaga la colision del modelo mientras haya alguien dentro.
func _enter_interior(player: Player) -> void:
	_player_inside = player
	_room.enter(player)


func _exit_interior() -> void:
	if _exit_hold:
		return
	var player := _player_inside
	# Despedidas: si un NPC de la habitacion tiene algo que decir, el jugador se queda en
	# la puerta escuchando (E para avanzar) y sale cuando termina el dialogo.
	if is_instance_valid(player):
		for npc in _room.find_children("*", "Npc", true, false):
			if npc.try_farewell(player):
				_exit_hold = true
				npc.dialogue_finished.connect(_finish_exit, CONNECT_ONE_SHOT)
				return
	_finish_exit()


func _finish_exit() -> void:
	_exit_hold = false
	if is_instance_valid(_player_inside):
		_room.exit(_player_inside)
	_player_inside = null


func _on_room_occupant_changed(_body: Node3D) -> void:
	_set_model_collision(_room.occupants.is_empty())
	_door.refresh_prompt()


func _set_model_collision(active: bool) -> void:
	var model := get_node_or_null("Model")
	for body in model.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 1 if active else 0
