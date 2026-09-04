extends Node
## Test headless de Fence + FenceGate: hueco en la valla, apertura hacia el lado contrario
## al jugador y colision solo cuando esta cerrada. Ejecutar:
##   godot --headless --path . --quit-after 3000 tests/fence_gate_test.tscn

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var fence := Fence.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(-6, 0, 0))
	curve.add_point(Vector3(6, 0, 0))  # valla recta a lo largo de X
	fence.curve = curve
	fence.post_spacing = 2.0
	add_child(fence)
	var gate := FenceGate.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 0, 0.5)  # cerca de la curva: se pega a (0,0,0)
	gate.swing_time = 0.1
	fence.add_child(gate)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	await _frames(3)

	_check(gate.position.is_equal_approx(Vector3.ZERO), "la puerta se pega a la curva")
	# En headless el MultiMesh no devuelve transforms (renderer dummy): se comprueba el hueco
	# por las cajas de colision, una por tramo entre postes.
	var intervals := []
	for shape in fence.get_node("Collision").get_children():
		var c: Vector3 = shape.position
		var half: float = (shape.shape as BoxShape3D).size.z * 0.5
		intervals.append([snappedf(c.x - half, 0.01), snappedf(c.x + half, 0.01)])
	var crossing := intervals.filter(func(iv): return iv[0] < -0.01 and iv[1] > 0.01)
	_check(crossing.is_empty(), "ningun tramo cruza el hueco")
	var left_end := -INF
	var right_start := INF
	for iv in intervals:
		if iv[1] <= 0.0:
			left_end = maxf(left_end, iv[1])
		if iv[0] >= 0.0:
			right_start = minf(right_start, iv[0])
	_check(is_equal_approx(left_end, -0.8) and is_equal_approx(right_start, 0.8), "los tramos terminan justo en los postes del hueco (ancho 1.6)")
	var body: StaticBody3D = gate.get_node("Leaf/Collision")
	_check(body.collision_layer == 1, "cerrada: la hoja colisiona")

	# Jugador en +Z (dentro): la punta de la hoja debe irse a -Z.
	player.global_position = Vector3(0, 0, 2)
	gate.interact_with(player)
	_check(gate.open, "interact_with abre")
	_check(body.collision_layer == 0, "abierta: sin colision desde el primer frame")
	await _frames(12)
	var tip: Vector3 = gate.get_node("Leaf").global_transform * Vector3(1.48, 0, 0)
	_check(tip.z < -0.5, "jugador en +Z: la hoja se abre hacia -Z (lejos)")

	gate.interact_with(player)
	_check(not gate.open, "segundo interact cierra")
	_check(body.collision_layer == 0, "mientras se cierra sigue sin colision")
	await _frames(12)
	_check(body.collision_layer == 1, "cerrada del todo: colision de vuelta")

	# Jugador en -Z (fuera): la punta se va a +Z.
	player.global_position = Vector3(0, 0, -2)
	gate.interact_with(player)
	await _frames(12)
	tip = gate.get_node("Leaf").global_transform * Vector3(1.48, 0, 0)
	_check(tip.z > 0.5, "jugador en -Z: la hoja se abre hacia +Z (lejos)")

	# Bisagra derecha: misma regla.
	gate.interact_with(player)
	await _frames(12)
	gate.hinge_right = true
	player.global_position = Vector3(0, 0, 2)
	gate.interact_with(player)
	await _frames(12)
	tip = gate.get_node("Leaf").global_transform * Vector3(-1.48, 0, 0)
	_check(tip.z < -0.5, "bisagra derecha, jugador en +Z: la hoja se va a -Z")

	print("\n%s: %d fallos" % ["OK" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)
