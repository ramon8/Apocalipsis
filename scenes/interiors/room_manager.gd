extends Node
## Autoload: registro de habitaciones por `room_id` y señales globales de ocupacion.
## Uso: RoomManager.get_room(&"molino_norte").enter(npc)  /  .exit(npc)
##      RoomManager.room_of(body) -> Room o null
##      RoomManager.player_room() -> Room en la que esta el jugador, o null

signal occupant_entered(room: Room, body: Node3D)
signal occupant_exited(room: Room, body: Node3D)

var _rooms: Dictionary = {}  # StringName -> Room


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
