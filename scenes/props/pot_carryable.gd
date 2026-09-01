class_name PotCarryable
extends StaticBody3D
## Objeto que se puede coger y llevar en las manos (pose hold) y soltar en el suelo.
## Coger: E -> crouch_start; al terminar, el objeto pasa al CarrySlot del jugador y
## crouch_end devuelve el control. Soltar: E de nuevo -> misma secuencia, y al terminar
## crouch_start el objeto queda en el suelo delante del jugador.

signal picked_up(player: Player)
signal dropped(player: Player)

@export_group("Interaction")
@export_range(0.5, 6.0, 0.1) var interaction_radius := 1.0
@export var interact_action: StringName = &"interact"
@export var prompt_key_text := "E"
@export var prompt_pick_text := "Coger"
@export var prompt_drop_text := "Soltar"
@export var prompt_place_text := "Poner al fuego"
## Donde cae al soltarlo, delante del jugador (metros).
@export var drop_forward := 0.9

@export_group("Audio")
## Suena al cogerlo y al dejarlo.
@export var lift_stream: AudioStream = preload("res://assets/audio/pot_lift.mp3")
@export_range(-40.0, 6.0, 0.5) var lift_volume_db := -12.0
## Tono base: bien por debajo de 1.0 para que suene grave y con peso.
@export_range(0.3, 2.0, 0.05) var lift_pitch := 0.55
## Variacion aleatoria de tono por uso (1.15 = +-15%) para que no suene identico.
@export_range(1.0, 2.0, 0.01) var lift_random_pitch := 1.15
@export_range(0.0, 12.0, 0.5) var lift_random_volume_db := 3.0

var _prompt: InteractPrompt
var _area: Area3D
var _player_in_range: Player
var _carrier: Player
var _busy := false  # secuencia de coger/soltar en curso
var _resting_fire: Node3D  # hoguera sobre la que descansa, si alguna
var _lift_player: AudioStreamPlayer3D


func _ready() -> void:
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.collision_layer = 0
	_area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	shape.shape = sphere
	shape.position.y = 0.5
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)
	InteractionManager.changed.connect(_update_prompt)

	if lift_stream:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.add_stream(0, lift_stream)
		randomizer.random_pitch = lift_random_pitch
		randomizer.random_volume_offset_db = lift_random_volume_db
		_lift_player = AudioStreamPlayer3D.new()
		_lift_player.name = "LiftSound"
		_lift_player.stream = randomizer
		_lift_player.volume_db = lift_volume_db
		_lift_player.pitch_scale = lift_pitch
		add_child(_lift_player)

	_prompt = InteractPrompt.new()
	_prompt.name = "Prompt"
	_prompt.key_text = prompt_key_text
	var renderer := get_node_or_null("/root/RetroRenderer")
	if renderer and renderer.get("hud_layer") != null:
		renderer.hud_layer.add_child(_prompt)
	else:
		var layer := CanvasLayer.new()
		layer.add_child(_prompt)
		add_child(layer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_prompt) and not is_ancestor_of(_prompt):
		_prompt.queue_free()


func is_carried() -> bool:
	return _carrier != null


func _on_body_entered(body: Node3D) -> void:
	if is_carried() or not (body is Player):
		return
	_player_in_range = body as Player
	InteractionManager.enter(self, 1)


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if not is_carried():
			InteractionManager.leave(self)


func _update_prompt() -> void:
	if not InteractionManager.is_current(self):
		if _prompt.visible:
			_prompt.pop_out()
		return
	if _busy:
		return
	if is_carried():
		_prompt.action_text = prompt_place_text if _find_lit_campfire() else prompt_drop_text
		_prompt.show_at()
	elif _player_in_range and not _player_in_range.is_carrying():
		_prompt.action_text = prompt_pick_text
		_prompt.show_at()
	elif _prompt.visible:
		_prompt.pop_out()


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not event.is_action_pressed(interact_action) or not InteractionManager.is_current(self):
		return
	if is_carried():
		if _carrier.is_action_playing():
			return
		get_viewport().set_input_as_handled()
		_begin_drop()
	elif _player_in_range and not _player_in_range.is_action_playing() and not _player_in_range.is_carrying():
		get_viewport().set_input_as_handled()
		_begin_pickup(_player_in_range)


func _begin_pickup(player: Player) -> void:
	if not player.play_crouch_action():
		return
	if _lift_player:
		_lift_player.play()
	_busy = true
	InteractionManager.leave(self)
	_prompt.pop_out()
	player.channel_apex.connect(_on_pickup_apex.bind(player), CONNECT_ONE_SHOT)


func _on_pickup_apex(_kind: String, player: Player) -> void:
	_carrier = player
	InteractionManager.enter(self, -1)  # llevado: siempre es el interactuable actual
	if is_instance_valid(_resting_fire):
		_resting_fire.remove_pot()
		_resting_fire = null
	_set_physics_active(false)
	reparent(player.carry_slot, false)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	player.holding = true
	player.pickup_finished.connect(_on_sequence_done, CONNECT_ONE_SHOT)
	picked_up.emit(player)
	_prompt.action_text = prompt_drop_text
	_prompt.show_at()


func _begin_drop() -> void:
	var player := _carrier
	if not player.play_crouch_action():
		return
	if _lift_player:
		_lift_player.play()
	_busy = true
	_prompt.pop_out()
	player.channel_apex.connect(_on_drop_apex.bind(player), CONNECT_ONE_SHOT)


func _on_drop_apex(_kind: String, player: Player) -> void:
	var fire := _find_lit_campfire()  # antes de soltar _carrier: la busqueda lo usa
	_carrier = null
	InteractionManager.leave(self)
	player.holding = false
	var world := player.get_parent()
	reparent(world, false)
	if fire:
		# Sobre la hoguera: centrado, a la altura de los troncos.
		_resting_fire = fire
		global_position = fire.global_position + Vector3(0.0, fire.pot_rest_height, 0.0)
		fire.place_pot(self)
	else:
		var pos := player.global_position + player._facing_direction() * drop_forward
		global_position = Vector3(pos.x, 0.0, pos.z)
	global_rotation = Vector3(0.0, player._model.global_rotation.y, 0.0)
	_set_physics_active(true)
	player.pickup_finished.connect(_on_sequence_done, CONNECT_ONE_SHOT)
	dropped.emit(player)


## Hoguera encendida cuyo area de interaccion contiene al portador.
func _find_lit_campfire() -> Node3D:
	if _carrier == null:
		return null
	for fire in get_tree().get_nodes_in_group("campfire"):
		if fire.lit and fire._player_in_range == _carrier and not fire.has_pot():
			return fire
	return null


func _on_sequence_done() -> void:
	_busy = false
	_update_prompt()


func _set_physics_active(active: bool) -> void:
	collision_layer = 1 if active else 0
	_area.monitoring = active
