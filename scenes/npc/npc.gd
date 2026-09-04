@tool
class_name Npc
extends StaticBody3D
## NPC estatico con el que se puede hablar. Al acercarse sale el prompt "Hablar" (E);
## las frases se muestran una a una en un bocadillo sobre su cabeza (SpeechBubble,
## estilo A Short Hike). E completa la linea o pasa a la siguiente; al terminar, o si el
## jugador se aleja, el bocadillo se cierra. Sigue al jugador con la cabeza.
##
## Lo que dice y cuando lo dice viene de `dialogue` (Array[DialogueEntry]): bloques con
## condiciones sobre los flags de WorldState y un disparador (hablar, cambio de flag,
## salir de la habitacion). El NPC no conoce a la hoguera ni al pot: solo lee flags.

signal dialogue_started
signal dialogue_finished

@export_group("Dialogo")
@export var speaker_name := "Villager"
## Bloques de dialogo (ver DialogueEntry). Lo normal: uno TALK por defecto, otros TALK con
## condiciones y mas prioridad, y reacciones FLAG a eventos del mundo.
@export var dialogue: Array[DialogueEntry] = []
## Marcador "!" sobre la cabeza hasta que el jugador habla con el por primera vez.
@export var show_exclamation := true
## Las reacciones automaticas solo saltan si el jugador esta a menos de esta distancia
## (si no, no se verian).
@export var reaction_distance := 14.0
## Pausa antes de la reaccion automatica (segundos).
@export var reaction_delay := 0.5
## Segundos que se mantiene cada linea automatica antes de pasar a la siguiente.
@export var auto_line_time := 2.6
## Temblor de camara al gritar (DialogueEntry.shout).
@export var shout_shake_strength := 0.3
@export var shout_shake_duration := 0.45

@export_group("Perro")
## Cuando el jugador sale de la habitacion con este room_id, el perro se viene con este
## NPC y se queda sentado a su lado para siempre (vacio = desactivado).
@export var dog_stays_after_leaving_room: StringName = &""
## Donde se sienta el perro, relativo al NPC (x = a su derecha, z = delante).
@export var dog_stay_offset := Vector3(1.3, 0.0, 0.4)

@export_group("Bocadillo")
## Mostrar el nombre en negrita al principio de la primera linea.
@export var show_name := true
@export var chars_per_second := 32.0
@export var prompt_text := "Hablar"
## Voz animalese: tono base de ESTE personaje (1 = medio; 1.3 agudo, 0.8 grave).
@export var voice_enabled := true
@export_range(0.5, 2.0, 0.01) var voice_pitch := 1.0
@export var bubble_font: Font
@export_range(6, 32, 1) var bubble_font_size := 9

@export_group("Cuerpo")
## Modelo (escena GLB) del NPC. Por defecto reutiliza el del personaje.
@export var model_scene: PackedScene = preload("res://assets/models/character/character.glb")
@export var model_scale := 0.3
## Yaw extra si el modelo mira a +Z en vez de -Z.
@export var model_yaw_offset_deg := 180.0
@export var idle_animation := "Idle"
## Sentado en el suelo (usa sit_animation en bucle y no gira hacia el jugador).
@export var sit_on_floor := false:
	set(v):
		sit_on_floor = v
		if is_inside_tree():
			_build_model()
@export var sit_animation := "Sit_floor"
## Altura del bocadillo cuando esta sentado (la cabeza queda mas baja).
@export var sit_head_height := 1.05
## Altura sobre el suelo donde se ancla el bocadillo (cabeza).
@export var head_height := 1.85
@export_range(0.5, 6.0, 0.1) var interaction_radius := 2.2
## Sigue al jugador con la cabeza (solo cuello + cabeza, el cuerpo no se mueve).
@export var face_player := true
@export_range(0.0, 120.0, 1.0) var head_max_yaw_deg := 70.0
@export_range(0.0, 60.0, 1.0) var head_max_pitch_deg := 30.0
@export var head_turn_smoothing := 6.0
## Huesos del giro de cabeza y peso de cada uno.
@export var head_bones: PackedStringArray = ["neck", "head"]
@export var head_bone_weights: PackedFloat32Array = [0.35, 0.65]
@export var nearest_texture_filter := true
@export var outline_enabled := true
@export var outline_color := Color(0.03, 0.02, 0.02)

@export_group("Colores")
## Recolorear la ropa (y un poco la piel) al azar para que cada NPC sea distinto.
@export var randomize_colors := true:
	set(v):
		randomize_colors = v
		if is_inside_tree():
			_build_model()
## 0 = semilla por posicion (estable entre sesiones); otro valor = fija ese look.
@export var color_seed := 0:
	set(v):
		color_seed = v
		if is_inside_tree():
			_build_model()
## Cuanto se aleja la saturacion/valor de la ropa del original (0 = solo cambia el tono).
@export_range(0.0, 0.6, 0.05) var cloth_variation := 0.25
## Variacion de la piel: tono muy leve y claridad (0 = piel original).
@export_range(0.0, 0.5, 0.05) var skin_variation := 0.2
## Nombres de malla que son piel (el resto se trata como ropa).
@export var skin_mesh_names: PackedStringArray = ["Head"]
## Mallas que se ocultan en el NPC (p. ej. la mochila del modelo del jugador).
@export var hidden_mesh_names: PackedStringArray = ["Backpack"]

var _model: Node3D
var _anim: AnimationPlayer
var _head_look: HeadLookModifier
var _zone: InteractionZone
var _bubble: SpeechBubble
var _talking_to: Player
var _line := -1
var _active_lines: Array[String] = []
var _auto := false  # dialogo automatico (reaccion): avanza solo, sin prompt
var _auto_timer := 0.0
var _shout_first := false
var _said: Dictionary = {}  # DialogueEntry -> true (para `once`)
var _marker: ExclamationMarker
var _has_new := true  # tiene dialogo nuevo que el jugador aun no ha oido (marcador "!")
## Razon con la que este NPC bloquea al jugador mientras le habla (una por NPC: dos
## dialogos no se pisan el desbloqueo).
@onready var _lock_reason: StringName = StringName("npc_%d" % get_instance_id())


func _ready() -> void:
	_build_model()
	if Engine.is_editor_hint():
		return  # en el editor solo se previsualiza el modelo
	_build_area()
	_build_ui()
	WorldState.flag_changed.connect(_on_flag_changed)
	if dog_stays_after_leaving_room != &"":
		RoomManager.occupant_exited.connect(_on_room_exited)


func _on_room_exited(room: Room, body: Node3D) -> void:
	if not (body is Player) or room.room_id != dog_stays_after_leaving_room:
		return
	for dog in get_tree().root.find_children("*", "Dog", true, false):
		var spot := global_position + global_transform.basis * dog_stay_offset
		dog.stay_at(Vector3(spot.x, global_position.y, spot.z))


# ------------------------------------------------------------------ dialogo por datos

## Bloque TALK que toca decir ahora (mayor prioridad entre las disponibles), o null.
func current_entry() -> DialogueEntry:
	var best: DialogueEntry = null
	for e in dialogue:
		if e == null or e.trigger != DialogueEntry.Trigger.TALK:
			continue
		if e.once and _said.has(e):
			continue
		if not e.is_available():
			continue
		if best == null or e.priority >= best.priority:
			best = e
	return best


func _on_flag_changed(flag: StringName, value: Variant) -> void:
	if not bool(value):
		return
	for e in dialogue:
		if e == null or e.trigger != DialogueEntry.Trigger.FLAG or e.trigger_flag != flag:
			continue
		if e.once and _said.has(e):
			continue
		if e.is_available():
			_react(e)


## Despedida al salir de la habitacion: si hay un bloque ROOM_EXIT disponible lo dice
## (manual: E para avanzar) y devuelve true para que el edificio retenga la salida.
func try_farewell(player: Player) -> bool:
	for e in dialogue:
		if e == null or e.trigger != DialogueEntry.Trigger.ROOM_EXIT:
			continue
		if e.once and _said.has(e):
			continue
		if not e.is_available():
			continue
		if is_talking():
			_end_dialogue()
		_start_dialogue(player, e)
		return true
	return false


## Habitacion (Room) en la que vive el NPC, o null si esta al aire libre.
func _my_room() -> Room:
	var n := get_parent()
	while n:
		if n is Room:
			return n
		n = n.get_parent()
	return null


## El jugador puede verme: al aire libre, solo si el jugador tambien esta fuera; dentro
## de una habitacion, solo si esta en ESA habitacion. Si no, ni marcador, ni bocadillos,
## ni reacciones (desde dentro no se ve el exterior y viceversa).
func _player_can_see_me() -> bool:
	var room := _my_room()
	if room == null:
		return RoomManager.player_room() == null
	return room.is_player_inside()


## Reaccion automatica a un evento: si el jugador esta cerca y puede verme, lo dice solo
## tras `reaction_delay`. Si no, solo cuenta como dicho (y puede reponer el "!").
func _react(entry: DialogueEntry) -> void:
	if entry.mark_new:
		_has_new = true
	if not _player_can_see_me():
		return
	var player := _nearby_player()
	if player == null:
		return
	_said[entry] = true
	if reaction_delay > 0.0:
		await get_tree().create_timer(reaction_delay).timeout
		if not is_inside_tree() or not is_instance_valid(player):
			return
	if is_talking():
		_end_dialogue()
	if entry.shout:
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig and rig.has_method("shake"):
			rig.shake(shout_shake_strength, shout_shake_duration)
	_start_dialogue(player, entry, true)


## El jugador si esta a menos de reaction_distance, o null.
func _nearby_player() -> Player:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		var rig := get_tree().get_first_node_in_group("camera_rig")
		player = rig.target as Player if rig and rig.get("target") is Player else null
	if player == null or player.global_position.distance_to(global_position) > reaction_distance:
		return null
	return player


func _build_model() -> void:
	if model_scene == null:
		return
	if _model:
		_model.free()
	_model = model_scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
	_model.rotation.y = deg_to_rad(model_yaw_offset_deg)
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	if _anim:
		var wanted := sit_animation if sit_on_floor else idle_animation
		var name := wanted
		for n in _anim.get_animation_list():
			if String(n).to_lower() == wanted.to_lower():
				name = String(n)
		if _anim.has_animation(name):
			_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
			_anim.play(name)
		else:
			push_warning("Npc: animacion '%s' no encontrada (hay: %s)." % [wanted, _anim.get_animation_list()])
	_prepare_materials(_model)
	_head_look = null
	if face_player and not Engine.is_editor_hint():
		var skeleton: Skeleton3D = _model.find_child("Skeleton3D", true, false)
		if skeleton:
			_head_look = HeadLookModifier.new()
			_head_look.name = "HeadLook"
			_head_look.bones = head_bones
			_head_look.weights = head_bone_weights
			_head_look.max_yaw_deg = head_max_yaw_deg
			_head_look.max_pitch_deg = head_max_pitch_deg
			_head_look.smoothing = head_turn_smoothing
			# El modelo (glTF) mira a -Z propio; model_yaw_offset 180 lo pone de cara a +Z del NPC.
			_head_look.forward_axis = Vector3(0.0, 0.0, -1.0)
			skeleton.add_child(_head_look)


func _prepare_materials(node: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed if color_seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
	# Un tono para la parte de arriba (torso + brazos), otro para las piernas, y la piel
	# casi igual. Las mallas se agrupan por nombre; lo desconocido va con el torso.
	var top_hue := rng.randf()
	var legs_hue := rng.randf()
	var top_sv := Vector2(rng.randf_range(1.0 - cloth_variation, 1.0 + cloth_variation),
			rng.randf_range(1.0 - cloth_variation * 0.6, 1.0 + cloth_variation * 0.4))
	var legs_sv := Vector2(rng.randf_range(1.0 - cloth_variation, 1.0 + cloth_variation),
			rng.randf_range(1.0 - cloth_variation * 0.6, 1.0 + cloth_variation * 0.4))
	var skin_hue := rng.randf_range(-0.02, 0.02) * skin_variation / 0.2
	var skin_val := rng.randf_range(1.0 - skin_variation, 1.0 + skin_variation * 0.5)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if hidden_mesh_names.has(mi.name):
			mi.visible = false
			continue
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.get_active_material(i)
			var base := mat as BaseMaterial3D
			if base == null:
				continue
			var outline: ShaderMaterial = ModelMaterials.make_outline(outline_color) if outline_enabled else null
			if randomize_colors and base.albedo_texture:
				var tint := ShaderMaterial.new()
				tint.shader = preload("res://scenes/npc/shaders/npc_tint.gdshader")
				tint.set_shader_parameter("albedo_tex", base.albedo_texture)
				# Piel: por nombre de malla (cabeza) o, dentro de las demas, por tono del texel.
				tint.set_shader_parameter("skin_hue_shift", skin_hue)
				tint.set_shader_parameter("skin_val_mul", skin_val)
				if skin_mesh_names.has(mi.name):
					tint.set_shader_parameter("hue_shift", skin_hue)
					tint.set_shader_parameter("val_mul", skin_val)
				elif mi.name.to_lower().contains("leg"):
					tint.set_shader_parameter("hue_shift", legs_hue)
					tint.set_shader_parameter("sat_mul", legs_sv.x)
					tint.set_shader_parameter("val_mul", legs_sv.y)
				else:
					tint.set_shader_parameter("hue_shift", top_hue)
					tint.set_shader_parameter("sat_mul", top_sv.x)
					tint.set_shader_parameter("val_mul", top_sv.y)
				tint.next_pass = outline
				mi.set_surface_override_material(i, tint)
			else:
				var setup := ModelMaterials.new()
				setup.nearest = nearest_texture_filter
				if outline_enabled:
					setup.with_outline(outline_color)
				mi.set_surface_override_material(i, setup.prepare(base))


func _build_area() -> void:
	_zone = InteractionZone.new()
	_zone.name = "TalkZone"
	_zone.radius = interaction_radius
	_zone.height = 0.8
	_zone.interact_priority = 2
	_zone.key_text = "E"
	_zone.action_text = prompt_text
	_zone.player_exited.connect(_on_player_exited)
	add_child(_zone)
	# Cuerpo fisico basico para que no se le atraviese.
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	body_shape.shape = capsule
	body_shape.position.y = 0.8
	add_child(body_shape)


func _build_ui() -> void:
	_bubble = SpeechBubble.new()
	_bubble.name = "SpeechBubble"
	_bubble.chars_per_second = chars_per_second
	_bubble.voice_pitch = voice_pitch
	if not voice_enabled:
		_bubble.voice_streams = []
	_marker = ExclamationMarker.new()
	_marker.name = "Exclamation"
	_bubble.font = bubble_font
	_bubble.font_size = bubble_font_size
	var renderer := get_node_or_null("/root/RetroRenderer")
	var host: Node = renderer.hud_layer if renderer and renderer.get("hud_layer") != null else null
	if host == null:
		host = CanvasLayer.new()
		add_child(host)
	host.add_child(_bubble)
	host.add_child(_marker)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not Engine.is_editor_hint():
		for n in [_bubble, _marker]:
			if is_instance_valid(n) and not is_ancestor_of(n):
				n.queue_free()


func _process(delta: float) -> void:
	if _model == null or Engine.is_editor_hint():
		return
	# Seguir al jugador SOLO con la cabeza mientras esta cerca o hablando; el cuerpo
	# se queda como esta (de pie o sentado).
	var who: Player = _talking_to if _talking_to else _zone.player_in_range
	if _head_look:
		_head_look.looking = who != null
		if who:
			_head_look.target = who.global_position + Vector3(0.0, 1.5, 0.0)
	if _bubble.visible:
		_bubble.anchor = global_position + Vector3(0.0, sit_head_height if sit_on_floor else head_height, 0.0)
		_bubble.camera = get_viewport().get_camera_3d()
	# Dialogo automatico: cada linea se mantiene un rato una vez escrita y avanza sola.
	if _auto and is_talking() and not _bubble.is_typing():
		_auto_timer += delta
		if _auto_timer >= auto_line_time:
			_auto_timer = 0.0
			_advance()
	# Marcador "!": algo nuevo que decir y no esta hablando ahora mismo.
	if _marker:
		var head := global_position + Vector3(0.0, sit_head_height if sit_on_floor else head_height, 0.0)
		_marker.anchor = head
		_marker.camera = get_viewport().get_camera_3d()
		if show_exclamation and _has_new and not is_talking() and current_entry() != null \
				and _player_can_see_me():
			_marker.show_marker()
		else:
			_marker.hide_marker()


# ------------------------------------------------------------------ interaccion

func _on_player_exited(_player: Player) -> void:
	if is_talking():
		_end_dialogue()


func is_talking() -> bool:
	return _talking_to != null


# La E llega por la InteractionZone; durante el dialogo la zona tiene la E capturada.
func can_interact(_player: Player) -> bool:
	return not is_talking() and _player_can_see_me() and current_entry() != null


func interact_with(player: Player) -> void:
	if is_talking():
		_advance()
	else:
		var entry := current_entry()
		if entry:
			_start_dialogue(player, entry)


func _start_dialogue(player: Player, entry: DialogueEntry, auto := false) -> void:
	if entry == null or entry.lines.is_empty():
		return
	_said[entry] = true
	_talking_to = player
	_active_lines = entry.lines
	_auto = auto
	_auto_timer = 0.0
	_shout_first = entry.shout
	_line = -1
	_zone.hide_prompt()
	if not auto:
		_has_new = false  # el jugador ha venido a oirlo
	if is_instance_valid(player):
		player.lock(_lock_reason)  # mientras te hablan no te mueves
		InteractionManager.capture(_zone, player)  # E = avanzar el dialogo
	dialogue_started.emit()
	_advance()


## E: si la linea se esta escribiendo, la completa; si no, pasa a la siguiente o cierra.
func _advance() -> void:
	if _bubble.is_typing():
		_bubble.complete()
		return
	_line += 1
	if _line >= _active_lines.size():
		_end_dialogue()
		return
	_auto_timer = 0.0
	var text := _active_lines[_line]
	if show_name and _line == 0 and not speaker_name.is_empty():
		text = "[b]%s:[/b] %s" % [speaker_name, text]
	_bubble.anchor = global_position + Vector3(0.0, sit_head_height if sit_on_floor else head_height, 0.0)
	_bubble.camera = get_viewport().get_camera_3d()
	_bubble.say(text, _shout_first and _line == 0)


func _end_dialogue() -> void:
	if is_instance_valid(_talking_to):
		_talking_to.unlock(_lock_reason)
	_talking_to = null
	_line = -1
	_auto = false
	InteractionManager.release(_zone)
	_bubble.close()
	dialogue_finished.emit()
	_zone.refresh_prompt()
