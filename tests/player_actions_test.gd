extends Node
## Test headless de la maquina de estados del jugador. Ejecutar:
##   godot --headless --path . tests/player_actions_test.tscn

var _events: Array[String] = []
var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.action_started.connect(func(k): _events.append("started:%s" % k))
	player.action_apex.connect(func(k): _events.append("apex:%s" % k))
	player.action_finished.connect(func(k): _events.append("finished:%s" % k))
	player.state_changed.connect(func(a, b): _events.append("state:%s->%s" % [Player.State.keys()[a], Player.State.keys()[b]]))

	_check(player.state == Player.State.LOCOMOTION, "arranca en LOCOMOTION")

	# --- crouch_grab: start -> apex al acabar start -> end -> finished
	var grab: PlayerAction = load("res://scenes/player/actions/crouch_grab.tres")
	_check(player.start_action(grab), "start_action(crouch_grab)")
	_check(player.is_action_playing(), "is_action_playing durante la accion")
	_check(not player.start_action(grab), "no se puede encadenar otra accion")
	await _wait_until(func(): return player.state != Player.State.ACTION, 6.0)
	_check_events(["state:LOCOMOTION->ACTION", "started:crouch_grab", "apex:crouch_grab",
			"state:ACTION->LOCOMOTION", "finished:crouch_grab"], "secuencia crouch_grab")

	# --- crouch: start -> idle (espera) -> stop_action -> end -> finished
	_check(player.start_action(player.crouch_action), "start_action(crouch)")
	await _wait_until(func(): return player.is_crouching() and player._phase == Player.Phase.IDLE, 6.0)
	_check(player.is_crouching(), "is_crouching en idle")
	player.stop_action()
	_check(not player.is_crouching(), "is_crouching false en fase END")
	await _wait_until(func(): return player.state != Player.State.ACTION, 6.0)
	_check_events(["state:LOCOMOTION->ACTION", "started:crouch", "apex:crouch",
			"state:ACTION->LOCOMOTION", "finished:crouch"], "secuencia crouch")

	# --- light_fire: idle + strike
	var fire: PlayerAction = load("res://scenes/player/actions/light_fire.tres")
	_check(player.start_action(fire), "start_action(light_fire)")
	await _wait_until(func(): return player._phase == Player.Phase.IDLE, 6.0)
	player.strike()
	_check(player._phase == Player.Phase.STRIKE, "strike pasa a STRIKE")
	await _wait_until(func(): return player._phase == Player.Phase.IDLE, 6.0)
	_check(player._phase == Player.Phase.IDLE, "tras el golpe vuelve a IDLE")
	player.stop_action()
	await _wait_until(func(): return player.state != Player.State.ACTION, 6.0)
	_events.clear()

	# --- pickup backpack: apex a mitad del clip (fraccion 0.5) y show_backpack
	player.show_backpack = false
	var pickup: PlayerAction = load("res://scenes/player/actions/pickup_backpack.tres")
	_check(player.start_action(pickup), "start_action(pickup_backpack)")
	await _wait_until(func(): return "apex:pickup_backpack" in _events, 6.0)
	_check(player.show_backpack, "la mochila aparece en el apex")
	_check(player.state == Player.State.ACTION, "el apex llega antes de terminar el clip")
	await _wait_until(func(): return player.state != Player.State.ACTION, 6.0)
	_events.clear()

	# --- lock durante una accion: al terminar queda LOCKED, unlock libera
	_check(player.start_action(grab), "start_action(crouch_grab) con lock pendiente")
	player.lock(&"test")
	_check(player.state == Player.State.ACTION, "lock no interrumpe la accion")
	await _wait_until(func(): return player.state != Player.State.ACTION, 6.0)
	_check(player.state == Player.State.LOCKED, "tras la accion queda LOCKED")
	_check(not player.start_action(grab), "LOCKED no permite acciones")
	player.unlock(&"test")
	_check(player.state == Player.State.LOCOMOTION, "unlock vuelve a LOCOMOTION")

	# --- lock en marcha: el clip debe volver a Idle al frenar (bug: se quedaba en Walk/Run)
	player._speed = player.run_speed
	player._current_anim = player.run_animation
	player._anim.play(player.run_animation)
	player.lock(&"talk")
	await _wait_until(func(): return player._current_anim == player.idle_animation, 3.0)
	_check(player._current_anim == player.idle_animation, "LOCKED en marcha termina en Idle")
	_check(player.state == Player.State.LOCKED, "sigue LOCKED tras frenar")
	player.unlock(&"talk")

	# --- dos razones de bloqueo
	player.lock(&"a")
	player.lock(&"b")
	player.unlock(&"a")
	_check(player.state == Player.State.LOCKED, "sigue LOCKED con una razon pendiente")
	player.unlock(&"b")
	_check(player.state == Player.State.LOCOMOTION, "libre sin razones")

	# --- sentarse
	_check(player.sit_down(), "sit_down")
	_check(player.is_sitting(), "is_sitting")
	_check(not player.start_action(grab), "sentado no permite acciones")
	player.stand_up()
	_check(player.state == Player.State.LOCOMOTION, "stand_up vuelve a LOCOMOTION")

	print("\n%s: %d fallos" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	if t >= timeout:
		_fail("timeout esperando condicion")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fail(what)


func _check_events(expected: Array, what: String) -> void:
	var got := _events.duplicate()
	_events.clear()
	if got == expected:
		print("  ok   ", what)
	else:
		_fail("%s\n       esperado %s\n       obtenido %s" % [what, expected, got])


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL ", what)
