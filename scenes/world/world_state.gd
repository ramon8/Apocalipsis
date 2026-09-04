extends Node
## Autoload "WorldState": flags globales del mundo (hoguera encendida, pot robado...).
## Los props los escriben (cada uno tiene un export con el nombre de su flag) y los NPCs
## los leen para elegir dialogo y reaccionar. Nadie busca a nadie por el arbol.
##
##   WorldState.set_flag(&"fire_lit")            -> true
##   WorldState.set_flag(&"fire_lit", false)
##   WorldState.get_flag(&"fire_lit")            -> bool
##   WorldState.flag_changed.connect(func(name, value): ...)

## Solo se emite cuando el valor cambia de verdad.
signal flag_changed(name: StringName, value: Variant)

var _flags: Dictionary = {}  # StringName -> Variant


func set_flag(name: StringName, value: Variant = true, notify := true) -> void:
	if name == &"":
		return
	if _flags.has(name) and _flags[name] == value:
		return
	_flags[name] = value
	if notify:
		flag_changed.emit(name, value)


func get_flag(name: StringName, default: Variant = false) -> Variant:
	return _flags.get(name, default)


func is_set(name: StringName) -> bool:
	return bool(_flags.get(name, false))


func clear_flag(name: StringName) -> void:
	if _flags.erase(name):
		flag_changed.emit(name, null)


## Evalua una condicion "flag" o "!flag" (vacia = siempre cierta).
func check(condition: String) -> bool:
	var c := condition.strip_edges()
	if c.is_empty():
		return true
	if c.begins_with("!"):
		return not is_set(StringName(c.substr(1).strip_edges()))
	return is_set(StringName(c))


## Todas las condiciones de la lista se cumplen.
func check_all(conditions: PackedStringArray) -> bool:
	for c in conditions:
		if not check(c):
			return false
	return true


func all_flags() -> Dictionary:
	return _flags.duplicate()


func reset() -> void:
	_flags.clear()
