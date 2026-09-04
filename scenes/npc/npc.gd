@tool
class_name Npc
extends StaticBody3D
## NPC estatico con el que se puede hablar. Al acercarse sale el prompt "Hablar" (E);
## las frases de `lines` se muestran una a una en un bocadillo sobre su cabeza
## (SpeechBubble, estilo A Short Hike). E completa la linea o pasa a la siguiente;
## al terminar, o si el jugador se aleja, el bocadillo se cierra.
## Se gira suavemente hacia el jugador mientras habla.

signal dialogue_started
signal dialogue_finished

@export_group("Dialogo")
@export var speaker_name := "Villager"
## Una frase por bocadillo, en orden. Palabras clave entre asteriscos: *asi* (ondulan y
## salen en color); el resto del texto queda quieto.
@export_multiline var lines: Array[String] = [
	"Brr... it's *freezing* out here.",
	"Could you do me a favor and *light the campfire*?",
]

## Marcador "!" sobre la cabeza hasta que el jugador habla con el por primera vez.
@export var show_exclamation := true
## Si esta activo, el "!" reaparece cada vez que un evento le da dialogo nuevo.
@export var exclamation_on_new_dialogue := false

@export_group("Hoguera")
@export var watch_campfire_enabled := true
## Hoguera que vigila. Vacio = la mas cercana (grupo "campfire") dentro de campfire_search_radius.
@export var watch_campfire: NodePath
@export var campfire_search_radius := 30.0
## Lo que dice al hablar con el una vez la hoguera esta encendida (y aun sin pot).
@export_multiline var lines_when_fire_lit: Array[String] = [
	"Could you fetch the *pot* from the *barn* and put it *on the fire*?",
]
## Lo que dice SOLO, automaticamente, en cuanto la hoguera se enciende.
@export_multiline var fire_lit_reaction: Array[String] = [
	"Much better, *thanks*!",
	"Now, would you go into the *barn*, grab the *pot* and put it *on the fire*?",
]
## Lo que dice solo cuando el pot se pone al fuego, y al hablarle despues.
@export_multiline var pot_placed_reaction: Array[String] = ["*Perfect*! Now we can cook something warm."]
@export_multiline var lines_when_pot_on_fire: Array[String] = ["Thanks a lot, friend. Smells *great* already."]
## Solo reacciona si el jugador esta a menos de esta distancia (si no, no se veria).
@export var reaction_distance := 14.0
## Pausa antes de la reaccion automatica (segundos).
@export var reaction_delay := 0.5
## Segundos que se mantiene cada linea automatica antes de pasar a la siguiente.
@export var auto_line_time := 2.6

@export_group("Pot (vigilante)")
## Reacciona cuando el jugador coge un pot cercano (el guardian del granero).
@export var watch_pot_enabled := false
## Pot vigilado. Vacio = el mas cercano dentro de pot_search_radius.
@export var watch_pot: NodePath
@export var pot_search_radius := 12.0
## Primera linea gritada (mas grande, roja, voz grave) + temblor de camara; luego se calma.
@export_multiline var pot_taken_reaction: Array[String] = [
	"Hey! *What are you doing*, THIEF?!",
	"...Oh. Sorry. We were *robbed* recently and I'm a bit paranoid.",
	"You can take it.",
]
@export var pot_taken_shout := true
@export var shout_shake_strength := 0.3
@export var shout_shake_duration := 0.45
## Lo que dice al hablarle despues del susto.
@export_multiline var lines_after_pot_taken: Array[String] = ["Sorry again about the shouting. Take good care of that pot."]

@export_group("Perro")
## Cuando el jugador sale de la habitacion con este room_id, el perro se viene con este
## NPC y se queda sentado a su lado para siempre (vacio = desactivado).
@export var dog_stays_after_leaving_room: StringName = &""
## Donde se sienta el perro, relativo al NPC (x = a su derecha, z = delante).
@export var dog_stay_offset := Vector3(1.3, 0.0, 0.4)

@export_group("Despedida")
## Al salir el jugador de la habitacion, el NPC dice esto (una sola vez) y la salida
## espera a que el jugador pase el dialogo con E.
@export_multiline var farewell_lines: Array[String] = []
## Solo se despide si antes hubo el incidente del pot.
@export var farewell_only_after_pot_taken := true
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
var _prompt: InteractPrompt
var _bubble: SpeechBubble
var _player_in_range: Player
var _talking_to: Player
var _line := -1
var _campfire: Campfire
var _fire_lit := false
var _pot_on_fire := false
var _pot: Node
var _pot_taken := false
var _active_lines: Array[String] = []
var _auto := false  # dialogo automatico (reaccion): avanza solo, sin prompt
var _auto_timer := 0.0
var _shout_first := false
var _farewell_said := false
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
	InteractionManager.changed.connect(_update_prompt)
	_connect_campfire.call_deferred()
	_connect_pot.call_deferred()
	if dog_stays_after_leaving_room != &"":
		RoomManager.occupant_exited.connect(_on_room_exited)


func _on_room_exited(room: Room, body: Node3D) -> void:
	if not (body is Player) or room.room_id != dog_stays_after_leaving_room:
		return
	for dog in get_tree().root.find_children("*", "Dog", true, false):
		var spot := global_position + global_transform.basis * dog_stay_offset
		dog.stay_at(Vector3(spot.x, global_position.y, spot.z))


func _connect_pot() -> void:
	if not watch_pot_enabled:
		return
	if not watch_pot.is_empty():
		_pot = get_node_or_null(watch_pot)
	if _pot == null:
		var best_d := pot_search_radius
		for pot in get_tree().root.find_children("*", "PotCarryable", true, false):
			var d: float = pot.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				_pot = pot
	if _pot:
		_pot.picked_up.connect(_on_pot_picked_up)


func _on_pot_picked_up(player: Player) -> void:
	if _pot_taken or pot_taken_reaction.is_empty():
		return
	_pot_taken = true
	if not _player_can_see_me():
		return
	if player and player.global_position.distance_to(global_position) > reaction_distance:
		return
	if is_talking():
		_end_dialogue()
	if pot_taken_shout:
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig and rig.has_method("shake"):
			rig.shake(shout_shake_strength, shout_shake_duration)
	_start_dialogue(player, pot_taken_reaction, true, pot_taken_shout)


func _connect_campfire() -> void:
	if not watch_campfire_enabled:
		return
	if not watch_campfire.is_empty():
		_campfire = get_node_or_null(watch_campfire) as Campfire
	if _campfire == null:
		var best_d := campfire_search_radius
		for fire in get_tree().get_nodes_in_group("campfire"):
			var d: float = fire.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				_campfire = fire
	if _campfire == null:
		return
	_fire_lit = _campfire.lit
	_pot_on_fire = _campfire.has_pot()
	_campfire.lit_changed.connect(_on_campfire_lit)
	_campfire.pot_changed.connect(_on_campfire_pot_changed)


func _on_campfire_lit(is_lit: bool) -> void:
	_fire_lit = is_lit
	if is_lit:
		_react(fire_lit_reaction)


func _on_campfire_pot_changed(has_pot: bool) -> void:
	_pot_on_fire = has_pot
	if has_pot:
		_react(pot_placed_reaction)


## Despedida al salir de la habitacion: si toca, la dice (automatica) y devuelve true para
## que el edificio retenga la salida `farewell_hold` segundos.
func try_farewell(player: Player) -> bool:
	if _farewell_said or farewell_lines.is_empty():
		return false
	if farewell_only_after_pot_taken and not _pot_taken:
		return false
	_farewell_said = true
	if is_talking():
		_end_dialogue()
	_start_dialogue(player, farewell_lines)  # manual: E para avanzar y salir
	return true


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


## Reaccion automatica a un evento: hay dialogo nuevo; si el jugador esta cerca (y puede
## verme), lo dice solo tras `reaction_delay`.
func _react(what: Array[String]) -> void:
	if exclamation_on_new_dialogue:
		_has_new = true
	if what.is_empty() or not _player_can_see_me():
		return
	var rig := get_tree().get_first_node_in_group("camera_rig")
	var target: Node3D = rig.target if rig else null
	if target and target.global_position.distance_to(global_position) > reaction_distance:
		return
	if reaction_delay > 0.0:
		await get_tree().create_timer(reaction_delay).timeout
	if is_talking():
		_end_dialogue()
	_start_dialogue(target as Player, what, true)


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
	var area := Area3D.new()
	area.name = "TalkArea"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	shape.shape = sphere
	shape.position.y = 0.8
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)
	# Cuerpo fisico basico para que no se le atraviese.
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	body_shape.shape = capsule
	body_shape.position.y = 0.8
	add_child(body_shape)


func _build_ui() -> void:
	_prompt = InteractPrompt.new()
	_prompt.name = "TalkPrompt"
	_prompt.key_text = "E"
	_prompt.action_text = prompt_text
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
	host.add_child(_prompt)
	host.add_child(_bubble)
	host.add_child(_marker)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not Engine.is_editor_hint():
		for n in [_prompt, _bubble, _marker]:
			if is_instance_valid(n) and not is_ancestor_of(n):
				n.queue_free()


func _process(delta: float) -> void:
	if _model == null or Engine.is_editor_hint():
		return
	# Seguir al jugador SOLO con la cabeza mientras esta cerca o hablando; el cuerpo
	# se queda como esta (de pie o sentado).
	var who: Player = _talking_to if _talking_to else _player_in_range
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
		if show_exclamation and _has_new and not is_talking() and not current_lines().is_empty() \
				and _player_can_see_me():
			_marker.show_marker()
		else:
			_marker.hide_marker()


# ------------------------------------------------------------------ interaccion

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = body as Player
		InteractionManager.enter(self, 2)


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		InteractionManager.leave(self)
		if is_talking():
			_end_dialogue()


func is_talking() -> bool:
	return _talking_to != null


func _update_prompt() -> void:
	if _player_in_range and not is_talking() and InteractionManager.is_current(self) \
			and not _player_in_range.is_carrying() and _player_can_see_me():
		_prompt.show_at()
	elif _prompt.visible:
		_prompt.pop_out()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_action_pressed(&"interact"):
		return
	if is_talking():
		get_viewport().set_input_as_handled()
		_advance()
	elif _player_in_range and InteractionManager.is_current(self) and not _player_in_range.is_carrying():
		get_viewport().set_input_as_handled()
		_start_dialogue(_player_in_range, current_lines())


## Lineas que toca decir ahora mismo (segun el estado del mundo).
func current_lines() -> Array[String]:
	if _pot_taken and not lines_after_pot_taken.is_empty():
		return lines_after_pot_taken
	if _pot_on_fire and not lines_when_pot_on_fire.is_empty():
		return lines_when_pot_on_fire
	if _fire_lit and not lines_when_fire_lit.is_empty():
		return lines_when_fire_lit
	return lines


func _start_dialogue(player: Player, what: Array[String], auto := false, shout_first := false) -> void:
	if what.is_empty():
		return
	_talking_to = player
	_active_lines = what
	_auto = auto
	_auto_timer = 0.0
	_shout_first = shout_first
	_line = -1
	_prompt.pop_out()
	if not auto:
		_has_new = false  # el jugador ha venido a oirlo
	if is_instance_valid(player):
		player.lock(_lock_reason)  # mientras te hablan no te mueves
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
	_bubble.close()
	dialogue_finished.emit()
	_update_prompt()
