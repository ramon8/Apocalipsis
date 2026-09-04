extends Node
## Autoload: registro de habitaciones por `room_id` y señales globales de ocupacion.
## Uso: RoomManager.get_room(&"molino_norte").enter(npc)  /  .exit(npc)
##      RoomManager.room_of(body) -> Room o null
##      RoomManager.player_room() -> Room en la que esta el jugador, o null

signal occupant_entered(room: Room, body: Node3D)
signal occupant_exited(room: Room, body: Node3D)

var _rooms: Dictionary = {}  # StringName -> Room

## Audio de interior: al entrar el jugador en una habitacion, el bus "World" (sonidos del
## exterior: hoguera, viento, perro, arboles) se amortigua con un paso bajo y baja de
## volumen, y Master gana una reverb corta de habitacion. Todo con transicion.
@export var interior_audio_enabled := true
@export_range(200.0, 4000.0, 50.0) var muffle_cutoff_hz := 700.0
@export_range(-40.0, 0.0, 0.5) var muffle_volume_db := -12.0
@export_range(0.0, 1.0, 0.05) var reverb_wet := 0.18
@export_range(0.05, 2.0, 0.05) var audio_transition := 0.5

const OPEN_CUTOFF := 20500.0
var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _world_bus := -1
var _master_bus := 0
var _audio_tween: Tween
var _inside := false


func _ready() -> void:
	occupant_entered.connect(_on_audio_occupant_entered)
	occupant_exited.connect(_on_audio_occupant_exited)
	_setup_audio()


func _setup_audio() -> void:
	_world_bus = AudioServer.get_bus_index("World")
	if _world_bus < 0:
		push_warning("RoomManager: no existe el bus 'World' (default_bus_layout.tres); sin audio de interior.")
		return
	for i in AudioServer.get_bus_effect_count(_world_bus):
		var fx := AudioServer.get_bus_effect(_world_bus, i)
		if fx is AudioEffectLowPassFilter:
			_lowpass = fx
	for i in AudioServer.get_bus_effect_count(_master_bus):
		var fx := AudioServer.get_bus_effect(_master_bus, i)
		if fx is AudioEffectReverb:
			_reverb = fx
	if _lowpass:
		_lowpass.cutoff_hz = OPEN_CUTOFF
	if _reverb:
		_reverb.wet = 0.0
	AudioServer.set_bus_volume_db(_world_bus, 0.0)


func _on_audio_occupant_entered(_room: Room, body: Node3D) -> void:
	if body is Player:
		_set_interior_audio(true)


func _on_audio_occupant_exited(_room: Room, body: Node3D) -> void:
	if body is Player and player_room() == null:
		_set_interior_audio(false)


func _set_interior_audio(inside: bool) -> void:
	if not interior_audio_enabled or _world_bus < 0 or inside == _inside:
		return
	_inside = inside
	if _audio_tween and _audio_tween.is_valid():
		_audio_tween.kill()
	_audio_tween = create_tween().set_parallel(true)
	var t := audio_transition
	if _lowpass:
		_audio_tween.tween_property(_lowpass, "cutoff_hz", muffle_cutoff_hz if inside else OPEN_CUTOFF, t) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_audio_tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(_world_bus, v),
			AudioServer.get_bus_volume_db(_world_bus), muffle_volume_db if inside else 0.0, t)
	if _reverb:
		_audio_tween.tween_property(_reverb, "wet", reverb_wet if inside else 0.0, t)


func is_interior_audio() -> bool:
	return _inside


func register(room: Room) -> void:
	if room.room_id == &"":
		push_warning("Room '%s' sin room_id: no se registra (asignale uno en la escena heredada)." % room.get_path())
		return
	if _rooms.has(room.room_id) and _rooms[room.room_id] != room:
		push_warning("room_id duplicado '%s' (%s y %s)." % [room.room_id, _rooms[room.room_id].get_path(), room.get_path()])
	_rooms[room.room_id] = room


func unregister(room: Room) -> void:
	if _rooms.get(room.room_id) == room:
		_rooms.erase(room.room_id)


func get_room(id: StringName) -> Room:
	return _rooms.get(id)


func all_rooms() -> Array:
	return _rooms.values()


func room_of(body: Node3D) -> Room:
	for room in _rooms.values():
		if room.has_occupant(body):
			return room
	return null


func player_room() -> Room:
	for room in _rooms.values():
		if room.is_player_inside():
			return room
	return null
