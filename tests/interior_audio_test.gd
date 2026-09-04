extends Node
## Test headless del audio de interior: al entrar el jugador en una Room, el bus "World"
## se amortigua (paso bajo + volumen) y Master gana reverb; al salir se restaura.
##   godot --headless --path . --quit-after 3000 tests/interior_audio_test.tscn

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var world := AudioServer.get_bus_index("World")
	_check(world >= 0, "existe el bus World")
	var lp: AudioEffectLowPassFilter = null
	for i in AudioServer.get_bus_effect_count(world):
		if AudioServer.get_bus_effect(world, i) is AudioEffectLowPassFilter:
			lp = AudioServer.get_bus_effect(world, i)
	_check(lp != null, "World tiene un paso bajo")
	var rv: AudioEffectReverb = null
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectReverb:
			rv = AudioServer.get_bus_effect(0, i)
	_check(rv != null, "Master tiene reverb")
	RoomManager.audio_transition = 0.05

	var room: Room = load("res://scenes/interiors/room.tscn").instantiate()
	room.room_id = &"test_room"
	room.position = Vector3(50, 0, 0)
	add_child(room)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(50, 0, 0)
	add_child(player)
	await _frames(3)
	_check(lp.cutoff_hz > 10000.0 and is_zero_approx(AudioServer.get_bus_volume_db(world)), "fuera: World limpio")

	room.enter(player)
	await _frames(20)
	_check(RoomManager.is_interior_audio(), "dentro: audio de interior activo")
	_check(lp.cutoff_hz < 1000.0, "dentro: paso bajo cerrado (%.0f Hz)" % lp.cutoff_hz)
	_check(AudioServer.get_bus_volume_db(world) < -6.0, "dentro: World mas bajo (%.1f dB)" % AudioServer.get_bus_volume_db(world))
	_check(rv.wet > 0.1, "dentro: reverb en Master")

	room.exit(player)
	await _frames(20)
	_check(not RoomManager.is_interior_audio(), "fuera: audio de interior apagado")
	_check(lp.cutoff_hz > 10000.0, "fuera: paso bajo abierto")
	_check(absf(AudioServer.get_bus_volume_db(world)) < 0.01, "fuera: volumen restaurado")
	_check(is_zero_approx(rv.wet), "fuera: sin reverb")

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
