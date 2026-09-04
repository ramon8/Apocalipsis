extends Node
## Test headless de InteractionZone + InteractionManager: rango, prioridad, captura de la E.
## Ejecutar:  godot --headless --path . tests/interaction_zone_test.tscn

var _failures := 0


## Prop de prueba: cuenta las interacciones y deja configurar can_interact / prompt.
class Prop extends Node3D:
	var zone: InteractionZone
	var hits := 0
	var last_player: Player
	var allow := true
	var label := "x"
	func _init(radius: float, priority: int, label_: String) -> void:
		label = label_
		zone = InteractionZone.new()
		zone.radius = radius
		zone.interact_priority = priority
		zone.height = 0.0
		add_child(zone)
	func can_interact(_p: Player) -> bool:
		return allow
	func interaction_prompt(_p: Player) -> String:
		return label
	func interact_with(p: Player) -> void:
		hits += 1
		last_player = p


func _ready() -> void:
	_run()


func _run() -> void:
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	var near := Prop.new(1.5, 2, "near")   # el jugador dentro
	var far := Prop.new(1.5, 0, "far")     # fuera de rango aunque tenga mas prioridad
	near.position = Vector3(0.5, 0, 0)
	far.position = Vector3(10, 0, 0)
	add_child(near)
	add_child(far)
	await _frames(4)

	_check(near.zone.player_in_range == player, "el jugador entra en la zona cercana")
	_check(far.zone.player_in_range == null, "la zona lejana no ve al jugador")
	_check(near.zone.is_current(), "la zona cercana es la actual")

	_press()
	_check(near.hits == 1 and near.last_player == player, "E llama a interact_with del padre")
	_check(far.hits == 0, "la lejana no recibe la E")

	# can_interact del padre bloquea
	near.allow = false
	_press()
	_check(near.hits == 1, "can_interact=false bloquea la E")
	near.allow = true

	# Prioridad: una segunda zona en rango con numero menor gana
	var prio := Prop.new(1.5, 0, "prio")
	prio.position = Vector3(-0.5, 0, 0)
	add_child(prio)
	await _frames(4)
	_check(prio.zone.is_current() and not near.zone.is_current(), "menor prioridad numerica gana")
	_press()
	_check(prio.hits == 1 and near.hits == 1, "la E va solo a la zona actual")

	# hold(): objeto en mano con prioridad -1 gana a todo sin necesitar area
	far.zone.hold(player)
	_check(far.zone.is_current(), "hold() convierte la zona en actual")
	_press()
	_check(far.hits == 1, "la E llega a la zona en mano")
	far.zone.release()
	_check(prio.zone.is_current(), "release() devuelve la E a la mejor zona en rango")

	# Captura: la E va a la zona capturada aunque no sea la actual ni permita interactuar
	near.allow = false
	InteractionManager.capture(near.zone, player)
	_press()
	_check(near.hits == 2, "captura: la E va a la zona capturada saltando can_interact")
	_check(prio.hits == 1, "captura: la zona actual no recibe la E")
	InteractionManager.release(near.zone)
	near.allow = true
	_press()
	_check(prio.hits == 2, "tras release() la E vuelve a la zona actual")

	# Llevando algo: blocked_while_carrying bloquea salvo que la zona lo desactive
	var dummy := Node3D.new()
	player.carry_slot.add_child(dummy)
	_check(player.is_carrying(), "is_carrying con un hijo en CarrySlot")
	_press()
	_check(prio.hits == 2, "con algo en brazos no se interactua")
	prio.zone.blocked_while_carrying = false
	_press()
	_check(prio.hits == 3, "blocked_while_carrying=false permite interactuar llevando algo")
	dummy.queue_free()

	# Salir del rango
	player.global_position = Vector3(50, 0, 0)
	await _frames(4)
	_check(near.zone.player_in_range == null and prio.zone.player_in_range == null, "al alejarse salen del rango")
	_check(InteractionManager.current() == null, "sin zonas en rango no hay actual")

	# enabled=false desregistra
	player.global_position = Vector3(0, 0, 0)
	await _frames(4)
	_check(prio.zone.is_current(), "de vuelta en rango")
	prio.zone.enabled = false
	_check(near.zone.is_current(), "enabled=false cede la E a la siguiente zona")

	print("\n%s: %d fallos" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _press() -> void:
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	InteractionManager._unhandled_input(ev)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)
