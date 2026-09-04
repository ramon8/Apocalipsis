extends Node
## Autoload "InteractionManager": decide QUE zona (InteractionZone) tiene la E y el prompt
## cuando varias estan en rango a la vez, y procesa la tecla `interact` UNA sola vez.
## Prioridad = numero menor gana (mochila 0, pot 1, hoguera/NPC/puerta 2; objeto llevado
## en brazos -1: siempre gana).
##
## Captura: mientras una zona tiene la E capturada (dialogo en curso, minijuego), la tecla
## va a esa zona aunque el jugador no este en rango o haya otra con mas prioridad.

signal changed

@export var interact_action: StringName = &"interact"

var _candidates := {}  # Object -> prioridad (int)
var _captured: InteractionZone
var _captured_player: Player


func enter(entity: Object, priority: int) -> void:
	_candidates[entity] = priority
	changed.emit()


func leave(entity: Object) -> void:
	if _candidates.erase(entity):
		changed.emit()


func current() -> Object:
	var best: Object = null
	var best_prio := 1 << 30
	for entity in _candidates:
		if not is_instance_valid(entity):
			continue
		var prio: int = _candidates[entity]
		if prio < best_prio:
			best_prio = prio
			best = entity
	return best


func is_current(entity: Object) -> bool:
	return current() == entity


## La E va a `zone` (con `player`) hasta release(). Llamar al empezar un dialogo o minijuego.
func capture(zone: InteractionZone, player: Player) -> void:
	_captured = zone
	_captured_player = player
	changed.emit()


func release(zone: InteractionZone) -> void:
	if _captured == zone:
		_captured = null
		_captured_player = null
		changed.emit()


func is_captured() -> bool:
	return is_instance_valid(_captured)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(interact_action):
		return
	if is_instance_valid(_captured):
		_captured.try_interact(_captured_player, true)
		get_viewport().set_input_as_handled()
		return
	var zone := current() as InteractionZone
	if zone and zone.try_interact():
		get_viewport().set_input_as_handled()
