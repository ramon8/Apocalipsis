extends Node
## Captura la escena principal a un PNG y sale. Requiere renderer real (sin --headless):
##   godot --path . tests/screenshot.tscn
## Ruta de salida: variable de entorno SCREENSHOT_PATH, o user://screenshot.png.
## Opcional: SCREENSHOT_POS="x,z" para colocar al jugador (y la camara) en ese punto,
## SCREENSHOT_FRAMES para esperar mas frames (por defecto 40), SCREENSHOT_ZOOM para el zoom
## de la camara (menor = mas cerca).

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var frames := int(OS.get_environment("SCREENSHOT_FRAMES")) if OS.get_environment("SCREENSHOT_FRAMES") != "" else 40
	var pos_s := OS.get_environment("SCREENSHOT_POS")
	if pos_s != "":
		var parts := pos_s.split(",")
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and parts.size() == 2:
			player.global_position = Vector3(float(parts[0]), player.global_position.y, float(parts[1]))
	# SCREENSHOT_ENTER="House1": mete al jugador en el interior de ese edificio.
	var enter_s := OS.get_environment("SCREENSHOT_ENTER")
	if enter_s != "":
		var b := get_tree().root.find_child(enter_s, true, false)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if b and pl and b.get("_room"):
			pl.global_position = b._room.global_position + Vector3(0.0, 0.0, 0.5)
			b._enter_interior(pl)
	var zoom_s := OS.get_environment("SCREENSHOT_ZOOM")
	if zoom_s != "":
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig:
			rig.set("zoom", float(zoom_s))
	# SCREENSHOT_SET="NodeName:prop=value;Other:prop=value" (valor parseado con str_to_var;
	# el nodo se busca por nombre en todo el arbol).
	var sets := OS.get_environment("SCREENSHOT_SET")
	if sets != "":
		for item in sets.split(";", false):
			var node_prop := item.split(":", false)
			if node_prop.size() != 2:
				continue
			var prop_val := node_prop[1].split("=", false)
			var node := get_tree().root.find_child(node_prop[0], true, false)
			if node and prop_val.size() == 2:
				node.set(prop_val[0], str_to_var(prop_val[1]))
	# SCREENSHOT_MOVE="vx,vz": desplaza al jugador a esa velocidad (m/s) durante la espera.
	var move := Vector2.ZERO
	var move_s := OS.get_environment("SCREENSHOT_MOVE")
	if move_s != "":
		var mp := move_s.split(",")
		if mp.size() == 2:
			move = Vector2(float(mp[0]), float(mp[1]))
	var mover := get_tree().get_first_node_in_group("player") as Node3D
	for i in frames:
		if move != Vector2.ZERO and mover:
			var dt := get_process_delta_time()
			mover.global_position += Vector3(move.x, 0.0, move.y) * dt
		await get_tree().process_frame
	var mask_path := OS.get_environment("SCREENSHOT_MASK")
	if mask_path != "":
		var gp := get_tree().root.find_child("GroundPaths", true, false)
		if gp and gp._viewport:
			var m: Image = gp._viewport.get_texture().get_image()
			print("mask: ", mask_path, " region=", gp.ground.material_override.get_shader_parameter("path_region"), " err=", m.save_png(mask_path))
	var wake_path := OS.get_environment("SCREENSHOT_WAKE")
	if wake_path != "":
		var lk := get_tree().get_first_node_in_group("lake")
		if lk and lk._wake_viewport:
			var wimg: Image = lk._wake_viewport.get_texture().get_image()
			print("wake: ", wake_path, " size=", wimg.get_size(), " err=", wimg.save_png(wake_path))
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("SCREENSHOT_PATH")
	if path == "":
		path = "user://screenshot.png"
	var err := img.save_png(path)
	print("screenshot: ", path, " (", img.get_width(), "x", img.get_height(), ") err=", err)
	get_tree().quit(0 if err == OK else 1)
