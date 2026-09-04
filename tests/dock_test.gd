extends Node
## Test headless del embarcadero: un cuerpo con capsula sube la rampa andando (con gravedad)
## y acaba sobre el tablero a deck_height. Ejecutar:
##   godot --headless --path . --quit-after 3000 tests/dock_test.tscn

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var dock := Dock.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(8, 0, 0))  # recto hacia +X, rampa en x=0..1.6
	dock.curve = curve
	dock.deck_height = 0.45
	dock.ramp_length = 1.6
	add_child(dock)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, 1, 100)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var body := CharacterBody3D.new()
	var cap := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	cap.shape = capsule
	cap.position.y = 0.85
	body.add_child(cap)
	body.position = Vector3(-1.5, 0.0, 0.0)
	add_child(body)
	await _frames(3)

	var shapes := dock.get_node("Collision").get_child_count()
	_check(shapes >= 8, "cajas de colision a lo largo del tablero (%d)" % shapes)
	var first: CollisionShape3D = dock.get_node("Collision").get_child(0)
	_check(first.transform.basis.determinant() > 0.0, "la caja de la rampa tiene basis dextrogiro")

	# Andar hacia +X a 2 m/s durante 3 s con gravedad: debe subir la rampa sin saltar.
	var max_y := 0.0
	for i in 180:
		body.velocity.x = 2.0
		body.velocity.z = 0.0
		if not body.is_on_floor():
			body.velocity.y -= 9.8 * (1.0 / 60.0)
		else:
			body.velocity.y = 0.0
		body.move_and_slide()
		max_y = maxf(max_y, body.position.y)
		await get_tree().physics_frame
	_check(body.position.x > 3.0, "avanza mas alla de la rampa (x=%.2f)" % body.position.x)
	_check(absf(body.position.y - 0.45) < 0.08, "queda sobre el tablero a deck_height (y=%.2f)" % body.position.y)
	_check(body.is_on_floor(), "esta apoyado en el tablero")

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
