extends Node
## Test headless de Lake.depth_at + Wading del jugador: profundidad por distancia a la
## orilla, hundimiento del modelo, freno y pasos con agua. Ejecutar:
##   godot --headless --path . --quit-after 3000 tests/wading_test.tscn

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var lake := Lake.new()
	var curve := Curve3D.new()
	for p in [Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)]:
		curve.add_point(p)
	curve.closed = true
	lake.curve = curve
	lake.wade_distance = 1.0
	lake.wade_depth = 0.3
	lake.wade_speed_factor = 0.5
	add_child(lake)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	player.global_position = Vector3(0, 0, -20)
	add_child(player)
	await _frames(3)

	_check(is_zero_approx(lake.depth_at(Vector2(0, -20))), "fuera del lago: profundidad 0")
	_check(is_equal_approx(lake.depth_at(Vector2(0, -9.5)), 0.15), "a 0.5 m de la orilla: mitad de wade_depth")
	_check(is_equal_approx(lake.depth_at(Vector2(0, 0)), 0.3), "en el centro: wade_depth (tope)")
	_check(lake.clearance_at(Vector2(0, 0)) < 0.0, "el interior sigue vetado para la dispersion")

	var wading: Wading = player.get_node("Wading")
	wading.idle_ripple_interval = 0.0  # sin ondas automaticas: el test cuenta nodos
	var base_y: float = player.get_node("Model").position.y
	_check(not wading.in_water(), "seco al empezar")

	# Dentro del agua: se hunde y frena.
	player.global_position = Vector3(0, 0, -9.5)
	await _frames(40)
	_check(wading.in_water() and is_equal_approx(wading.depth, 0.15), "Wading lee la profundidad del lago")
	_check(is_equal_approx(wading.speed_factor(), 0.75), "freno proporcional a la profundidad")
	var sunk_y: float = player.get_node("Model").position.y
	_check(sunk_y < base_y - 0.1, "el modelo se hunde (y=%.2f, base %.2f)" % [sunk_y, base_y])
	_check(player.get_node("Footsteps").in_water, "los pasos pasan a chapoteo")

	# Onda al pisar.
	var before := get_child_count()
	wading.ripple()
	_check(get_child_count() == before + 1 and get_child(-1) is SplashRipple, "ripple() crea una onda")
	await _frames(70)
	_check(get_child_count() == before, "la onda se libera sola")

	# Fuera otra vez: vuelve a subir y a pasos secos.
	player.global_position = Vector3(0, 0, -20)
	await _frames(60)
	_check(not wading.in_water(), "fuera del agua")
	_check(is_equal_approx(player.get_node("Model").position.y, base_y), "el modelo vuelve a su altura")
	_check(not player.get_node("Footsteps").in_water, "pasos secos de nuevo")

	print("\n%s: %d fallos" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)
