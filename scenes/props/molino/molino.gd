@tool
class_name Molino
extends Node3D
## Molino de viento instanciable. Las aspas ("Elices" en el GLB) giran sobre su eje a
## `blade_speed` rpm; el resto es estatico (ambas mallas traen colision del import -col).

## Velocidad de las aspas en vueltas por minuto. Negativo = sentido contrario.
@export_range(-30.0, 30.0, 0.1) var blade_speed_rpm := 6.0
## Girar tambien en el editor para previsualizar.
@export var spin_in_editor := true
## Nombre del nodo de las aspas dentro del modelo importado.
@export var blades_node_name := "Elices"
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

@export_group("Interior")
## Generar interior visitable (E en la puerta para entrar).
@export var interior_enabled := true
## Habitacion de ESTE edificio: escena heredada de scenes/interiors/room.tscn con su
## room_id (organizalas por carpetas, p. ej. scenes/interiors/molinos/).
@export var interior_scene: PackedScene = preload("res://scenes/interiors/room.tscn")
## Radio del suelo interior en unidades locales. 0 = auto desde el AABB de la torre
## (la habitacion puede fijar el suyo propio con Room.radius > 0).
@export var interior_radius := 0.0
## Direccion de la puerta en grados (local, 0 = +Z). Ajustar hasta que coincida con la textura.
@export var door_angle_deg := 0.0
## Ancho del hueco de la puerta (m).
@export var door_width := 1.4
@export var prompt_enter_text := "Entrar"
@export var prompt_exit_text := "Salir"

const WEATHER_SHADER := preload("res://scenes/props/molino/shaders/molino_weathered.gdshader")

var _blades: Node3D
var _weather_mats: Array[ShaderMaterial] = []
var _room: Room
var _radius := 2.0
var _door: InteractionZone
var _player_inside: Player
var _exit_hold := false  # despedida en curso: la salida espera


func _ready() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		push_warning("Molino: falta el hijo 'Model' (instancia de Molino.glb).")
		return
	_blades = model.find_child(blades_node_name, true, false)
	if _blades == null:
		push_warning("Molino: no encuentro el nodo de aspas '%s' en el modelo." % blades_node_name)
	_refresh_materials()
	if interior_enabled and not Engine.is_editor_hint():
		_build_interior()


func _refresh_materials() -> void:
	var model := get_node_or_null("Model")
	if model == null or not is_inside_tree():
		return
	_weather_mats.clear()
	_apply_materials(model)


func _set_weather_param(pname: String, value: float) -> void:
	for m in _weather_mats:
		m.set_shader_parameter(pname, value)


func _process(delta: float) -> void:
	if _blades != null and (not Engine.is_editor_hint() or spin_in_editor):
		# El nodo de las aspas viene del GLB con su pivote en el buje; su eje local Y
		# (tras la rotacion X+90 del export) es el eje del buje.
		_blades.rotate_object_local(Vector3.UP, blade_speed_rpm * TAU / 60.0 * delta)
	# Salida automatica: el jugador sale ANDANDO por el pasillo; al llegar al fondo
	# (donde el suelo ya se ha fundido a negro) restauramos el exterior.
	if _is_player_inside():
		var local := to_local(_player_inside.global_position)
		if Vector2(local.x, local.z).length() > _radius + _room.corridor_length * 0.8:
			_exit_interior()


# ------------------------------------------------------------------ interior

func _build_interior() -> void:
	# Radio: auto desde el AABB de la malla de la torre (en unidades locales del Molino).
	var model := get_node_or_null("Model")
	var tower: MeshInstance3D = model.find_child("Molino", true, false)
	if interior_radius > 0.0:
		_radius = interior_radius
	elif tower:
		var aabb := tower.get_aabb()
		var s: Vector3 = model.scale * tower.scale
		_radius = minf(aabb.size.x * s.x, aabb.size.z * s.z) * 0.5 * 0.92

	# La habitacion es una escena propia (heredada de room.tscn); oculta hasta entrar.
	var scene := interior_scene if interior_scene else preload("res://scenes/interiors/room.tscn")
	_room = scene.instantiate() as Room
	if _room == null:
		push_warning("Molino: interior_scene no es una Room (heredala de scenes/interiors/room.tscn).")
		return
	_room.name = "Interior"
	_room.auto_radius = _radius
	_room.door_angle_deg = door_angle_deg
	_room.door_width = door_width
	add_child(_room)
	_radius = _room.effective_radius()  # la habitacion puede imponer el suyo
	_room.occupant_entered.connect(_on_room_occupant_changed)
	_room.occupant_exited.connect(_on_room_occupant_changed)

	var door_rad := deg_to_rad(door_angle_deg)
	# Zona de la puerta (dentro Y fuera): prompt Entrar/Salir. Cuelga del Molino, no de
	# la habitacion, para estar activa tambien estando fuera.
	_door = InteractionZone.new()
	_door.name = "DoorZone"
	_door.radius = 1.7
	_door.height = 0.0
	_door.interact_priority = 2
	_door.position = Vector3(sin(door_rad), 0.5, cos(door_rad)) * _radius
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
## la puerta: apaga la colision de la torre mientras haya alguien dentro.
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
	_set_tower_collision(_room.occupants.is_empty())
	_door.refresh_prompt()


func _set_tower_collision(active: bool) -> void:
	var model := get_node_or_null("Model")
	for body in model.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 1 if active else 0


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
				# Patron distinto por molino, estable entre sesiones.
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
