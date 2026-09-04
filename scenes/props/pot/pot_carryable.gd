class_name PotCarryable
extends StaticBody3D
## Objeto que se puede coger y llevar en las manos (pose hold) y soltar en el suelo.
## Coger: E -> crouch_start; al terminar, el objeto pasa al CarrySlot del jugador y
## crouch_end devuelve el control. Soltar: E de nuevo -> misma secuencia, y al terminar
## crouch_start el objeto queda en el suelo delante del jugador (o sobre una hoguera
## encendida si el portador esta en su zona).
## La E y el prompt los gestiona la InteractionZone hija; mientras se lleva, la zona
## queda "en mano" (prioridad -1) para que la E siga llegando aqui.

signal picked_up(player: Player)
signal dropped(player: Player)

@export_group("Interaction")
@export_range(0.5, 6.0, 0.1) var interaction_radius := 1.0
@export var prompt_key_text := "E"
@export var prompt_pick_text := "Coger"
@export var prompt_drop_text := "Soltar"
@export var prompt_place_text := "Poner al fuego"
## Donde cae al soltarlo, delante del jugador (metros).
@export var drop_forward := 0.9
## Accion del jugador al coger y al soltar (agacharse: el apex es el momento del cambio).
@export var grab_action: PlayerAction = preload("res://scenes/player/actions/crouch_grab.tres")
## Flag de WorldState que se pone a true la primera vez que alguien lo coge (vacio = no).
@export var taken_flag: StringName = &"pot_taken"

@export_group("Audio")
## Suena al cogerlo y al dejarlo.
@export var lift_stream: AudioStream = preload("res://assets/audio/pot_lift.mp3")
@export_range(-40.0, 6.0, 0.5) var lift_volume_db := -18.0
## Tono base: bien por debajo de 1.0 para que suene grave y con peso.
@export_range(0.3, 2.0, 0.05) var lift_pitch := 0.55
## Variacion aleatoria de tono por uso (1.15 = +-15%) para que no suene identico.
@export_range(1.0, 2.0, 0.01) var lift_random_pitch := 1.15
@export_range(0.0, 12.0, 0.5) var lift_random_volume_db := 3.0

var _zone: InteractionZone
var _carrier: Player
var _busy := false  # secuencia de coger/soltar en curso
var _resting_fire: Node3D  # hoguera sobre la que descansa, si alguna
var _lift_player: AudioStreamPlayer3D


func _ready() -> void:
	_zone = InteractionZone.new()
	_zone.name = "InteractionZone"
	_zone.radius = interaction_radius
	_zone.height = 0.5
	_zone.interact_priority = 1
	_zone.key_text = prompt_key_text
	_zone.blocked_while_carrying = false  # lo comprobamos aqui: llevado, la E es nuestra
	add_child(_zone)

	if lift_stream:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(0, lift_stream)
		randomizer.random_pitch = lift_random_pitch
		randomizer.random_volume_offset_db = lift_random_volume_db
		_lift_player = AudioStreamPlayer3D.new()
		_lift_player.bus = &"World"
		_lift_player.name = "LiftSound"
		_lift_player.stream = randomizer
		_lift_player.volume_db = lift_volume_db
		_lift_player.pitch_scale = lift_pitch
		add_child(_lift_player)


func is_carried() -> bool:
	return _carrier != null


# ------------------------------------------------------------------ InteractionZone

func can_interact(player: Player) -> bool:
	if _busy or player.is_action_playing():
		return false
	return is_carried() or not player.is_carrying()


func interaction_prompt(_player: Player) -> String:
	if not is_carried():
		return prompt_pick_text
	return prompt_place_text if _find_lit_campfire() else prompt_drop_text


func interact_with(player: Player) -> void:
	if is_carried():
		_begin_drop()
	else:
		_begin_pickup(player)


# ------------------------------------------------------------------ coger / soltar

func _begin_pickup(player: Player) -> void:
	if not player.start_action(grab_action):
		return
	if _lift_player:
		_lift_player.play()
	_busy = true
	_zone.release()  # durante la animacion, otras zonas pueden tomar la E
	player.action_apex.connect(_on_pickup_apex.bind(player), CONNECT_ONE_SHOT)


func _on_pickup_apex(_kind: StringName, player: Player) -> void:
	_carrier = player
	if is_instance_valid(_resting_fire):
		_resting_fire.remove_pot()
		_resting_fire = null
	_set_physics_active(false)
	reparent(player.carry_slot, false)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	player.holding = true
	player.action_finished.connect(_on_sequence_done, CONNECT_ONE_SHOT)
	picked_up.emit(player)
	WorldState.set_flag(taken_flag)
	_zone.hold(player)  # llevado: siempre es el interactuable actual


func _begin_drop() -> void:
	var player := _carrier
	if not player.start_action(grab_action):
		return
	if _lift_player:
		_lift_player.play()
	_busy = true
	_zone.hide_prompt()
	player.action_apex.connect(_on_drop_apex.bind(player), CONNECT_ONE_SHOT)


func _on_drop_apex(_kind: StringName, player: Player) -> void:
	var fire := _find_lit_campfire()  # antes de soltar _carrier: la busqueda lo usa
	_carrier = null
	_zone.release()
	player.holding = false
	var world := player.get_parent()
	reparent(world, false)
	if fire:
		# Sobre la hoguera: centrado, a la altura de los troncos.
		_resting_fire = fire
		global_position = fire.global_position + Vector3(0.0, fire.pot_rest_height, 0.0)
		fire.place_pot(self)
	else:
		var pos := player.global_position + player.facing_direction() * drop_forward
		global_position = Vector3(pos.x, 0.0, pos.z)
	global_rotation = Vector3(0.0, player.facing_yaw(), 0.0)
	_set_physics_active(true)
	player.action_finished.connect(_on_sequence_done, CONNECT_ONE_SHOT)
	dropped.emit(player)


## Hoguera encendida cuya zona de interaccion contiene al portador.
func _find_lit_campfire() -> Node3D:
	if _carrier == null:
		return null
	for fire in get_tree().get_nodes_in_group("campfire"):
		if fire.lit and fire.is_player_in_range(_carrier) and not fire.has_pot():
			return fire
	return null


func _on_sequence_done(_kind: StringName) -> void:
	_busy = false
	_zone.refresh_prompt()


func _set_physics_active(active: bool) -> void:
	collision_layer = 1 if active else 0
	_zone.set_deferred("monitoring", active)
