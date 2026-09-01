extends Node
## Autoload "InteractionManager": decide QUE entidad interactuable tiene la E y el prompt
## cuando varias estan en rango a la vez. Prioridad = numero menor gana
## (mochila 0, pot 1, hoguera 2; objeto llevado en brazos -1: siempre gana).
## Las entidades llaman enter()/leave() al entrar/salir su area, escuchan `changed`
## y solo muestran su prompt / gestionan la E si is_current(self).

signal changed

var _candidates := {}  # Object -> prioridad (int)


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
