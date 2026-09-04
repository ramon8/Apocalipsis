extends Node
## Test headless de WorldState + DialogueEntry en el NPC: seleccion por flags y prioridad,
## reacciones automaticas, `once` y despedida. Ejecutar:
##   godot --headless --path . tests/dialogue_test.tscn

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	WorldState.reset()
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	var villager: Npc = load("res://scenes/npc/npc.tscn").instantiate()
	villager.reaction_delay = 0.0
	villager.position = Vector3(3, 0, 0)  # cerca del jugador, fuera de la zona de hablar
	add_child(villager)
	var farmer: Npc = load("res://scenes/npc/npc_barn_keeper.tscn").instantiate()
	farmer.reaction_delay = 0.0
	farmer.position = Vector3(-3, 0, 0)
	add_child(farmer)
	await _frames(3)

	# --- WorldState
	_check(not WorldState.is_set(&"fire_lit"), "flag no definido = false")
	_check(WorldState.check("!fire_lit") and WorldState.check(""), "check() con negacion y vacio")
	var changes := []
	WorldState.flag_changed.connect(func(n, v): changes.append([n, v]))
	WorldState.set_flag(&"x")
	WorldState.set_flag(&"x")
	_check(changes.size() == 1, "flag_changed solo cuando cambia el valor")
	WorldState.set_flag(&"y", true, false)
	_check(changes.size() == 1 and WorldState.is_set(&"y"), "set_flag sin notificar")

	# --- Seleccion TALK por flags y prioridad
	_check(_id(villager) == &"villager_default", "villager: bloque por defecto")
	_check(_id(farmer) == &"barn_default", "farmer: bloque por defecto")
	WorldState.set_flag(&"fire_lit")
	await _frames(2)
	_check(_id(villager) == &"villager_fire_lit", "villager: fire_lit sube de prioridad")
	_check(villager.is_talking(), "villager reacciona solo al encenderse la hoguera")
	_check(not farmer.is_talking(), "farmer no reacciona a fire_lit")
	villager._end_dialogue()
	WorldState.set_flag(&"pot_on_fire")
	await _frames(2)
	_check(_id(villager) == &"villager_pot_on_fire", "villager: pot_on_fire gana a fire_lit")
	_check(villager.is_talking(), "villager reacciona al pot en el fuego")
	villager._end_dialogue()

	# --- Reaccion `once` + shout + despedida condicionada
	_check(not farmer.try_farewell(player), "sin pot_taken no hay despedida")
	WorldState.set_flag(&"pot_taken")
	await _frames(2)
	_check(farmer.is_talking(), "farmer grita al coger el pot")
	_check(farmer._shout_first, "la reaccion es un grito")
	farmer._end_dialogue()
	_check(_id(farmer) == &"barn_after_pot_taken", "farmer: dialogo tras el robo")
	_check(_id(villager) == &"villager_pot_on_fire", "villager: pot_taken no le afecta")
	WorldState.set_flag(&"pot_taken", false)
	WorldState.set_flag(&"pot_taken", true)
	await _frames(2)
	_check(not farmer.is_talking(), "once: la reaccion no se repite")
	_check(farmer.try_farewell(player), "con pot_taken hay despedida")
	_check(farmer.is_talking() and not farmer._auto, "la despedida es manual (E)")
	farmer._end_dialogue()
	_check(not farmer.try_farewell(player), "la despedida es once")

	# --- Reaccion lejos del jugador: no habla
	villager._end_dialogue()
	villager.position = Vector3(100, 0, 0)
	WorldState.set_flag(&"fire_lit", false)
	WorldState.set_flag(&"fire_lit", true)
	await _frames(2)
	_check(not villager.is_talking(), "lejos del jugador no reacciona en voz alta")

	print("\n%s: %d fallos" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _id(npc: Npc) -> StringName:
	var e := npc.current_entry()
	return e.id if e else &""


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)
