@tool
class_name Campfire
extends Node3D
## Hoguera con dos estados: encendida (llama + humo procedurales estilo pixel + luz con
## parpadeo) y apagada (troncos carbonizados). La base son troncos (cajas con la textura
## `log`) cruzados en estrella. Todo se construye en código: cambia un export y se
## reconstruye en vivo en el editor.

const FIRE_SHADER := preload("res://scenes/props/campfire/shaders/campfire_fire.gdshader")
const SMOKE_SPRITE := preload("res://assets/textures/fx/smoke_puff.png")

signal lit_changed(is_lit: bool)
signal pot_changed(has_pot: bool)

## Estado. También en runtime: campfire.lit = true / toggle().
@export var lit := false:
	set(value):
		var changed := lit != value
		lit = value
		_apply_state()
		if changed:
			lit_changed.emit(lit)

## Segundos que tarda el fuego en crecer hasta su estado final al encenderse.
@export_range(0.0, 10.0, 0.1) var ignite_time := 3.0
## Segundos que tarda en morir al apagarse (el humo restante se disipa solo).
@export_range(0.0, 10.0, 0.1) var extinguish_time := 1.5

@export_group("Logs")
@export var log_texture: Texture2D = preload("res://assets/textures/log.png"):
	set(value):
		log_texture = value
		_rebuild()
@export_range(3, 8) var log_count := 5:
	set(value):
		log_count = value
		_rebuild()
@export_range(0.3, 2.0, 0.05) var log_length := 0.85:
	set(value):
		log_length = value
		_rebuild()
@export_range(0.03, 0.2, 0.005) var log_radius := 0.07:
	set(value):
		log_radius = value
		_rebuild()
## Tinte de los troncos apagados (carbonizados).
@export var charred_tint := Color(0.35, 0.32, 0.3)

@export_group("Fire")
@export_range(0.2, 3.0, 0.05) var fire_height := 0.9:
	set(value):
		fire_height = value
		_rebuild()
@export_range(0.2, 2.0, 0.05) var fire_width := 0.65:
	set(value):
		fire_width = value
		_rebuild()
@export_range(0.0, 1.5, 0.05) var fire_intensity := 1.0:
	set(value):
		fire_intensity = value
		_update_fx_params()
## Colores de la llama pixel-art (nucleo, medio y borde). Para fuego verde/azul/magico.
@export var fire_color_core := Color(1.0, 0.93, 0.55):
	set(value):
		fire_color_core = value
		_update_fx_params()
@export var fire_color_mid := Color(0.98, 0.55, 0.15):
	set(value):
		fire_color_mid = value
		_update_fx_params()
@export var fire_color_outer := Color(0.75, 0.2, 0.08):
	set(value):
		fire_color_outer = value
		_update_fx_params()

@export_group("Smoke")
@export var smoke_enabled := true:
	set(value):
		smoke_enabled = value
		_apply_state()
@export_range(0.5, 12.0, 0.1) var smoke_height := 5.0:
	set(value):
		smoke_height = value
		_rebuild()
@export_range(0.2, 6.0, 0.1) var smoke_width := 2.2:
	set(value):
		smoke_width = value
		_rebuild()
@export_range(0.0, 1.0, 0.05) var smoke_density := 0.55:
	set(value):
		smoke_density = value
		_update_fx_params()
## Color del humo recien salido (denso) y del humo ya disipado (alto).
@export var smoke_color_dark := Color(0.34, 0.34, 0.38):
	set(value):
		smoke_color_dark = value
		_update_fx_params()
@export var smoke_color_light := Color(0.55, 0.55, 0.58):
	set(value):
		smoke_color_light = value
		_update_fx_params()

@export_group("Sound")
@export var fire_sound: AudioStream = preload("res://assets/audio/fire.mp3")
## Volumen a pie de hoguera.
@export_range(-40.0, 6.0, 0.5) var sound_volume_db := -6.0
## Radio (m) dentro del cual suena a volumen completo (meseta).
@export_range(0.5, 50.0, 0.5) var sound_full_radius := 15.0
## Distancia (m) a la que el fade llega al silencio total.
@export_range(2.0, 150.0, 0.5) var sound_max_distance := 48.0

@export_group("Interaction")
## Acercarse muestra el prompt (E): "Encender" si esta apagada, "Apagar" si esta encendida.
@export var interaction_enabled := true
@export_range(0.5, 6.0, 0.1) var interaction_radius := 1.6
@export var prompt_key_text := "E"
@export var prompt_light_text := "Encender"
@export var prompt_extinguish_text := "Apagar"
## Accion del jugador durante el minijuego (pose de espera + golpe por pulsacion).
@export var light_action: PlayerAction = preload("res://scenes/player/actions/light_fire.tres")

@export_group("Pot")
## Escala de la llama con un pot encima: mas ancha y mas baja (lamiendo los lados).
@export var pot_fire_spread := Vector3(2.3, 0.38, 2.3)
## Altura a la que descansa el pot sobre los troncos.
@export_range(0.0, 1.0, 0.01) var pot_rest_height := 0.22

@export_group("Minigame")
## Encender requiere el minijuego de chispa (rueda). false = E enciende directamente.
@export var minigame_enabled := true
## Segundos que tarda la marca en dar una vuelta completa.
@export_range(0.5, 5.0, 0.1) var sweep_time := 1.6
## Tamano inicial de la seccion objetivo, en grados.
@export_range(10.0, 180.0, 1.0) var target_size_deg := 60.0
## Multiplicador del tamano de la seccion tras cada acierto.
@export_range(0.2, 0.95, 0.05) var target_shrink := 0.6
## Aciertos seguidos necesarios para encender el fuego.
@export_range(1, 8) var hits_to_light := 3
@export var flint_sound: AudioStream = preload("res://assets/audio/flint_fire.wav")
@export_range(-40.0, 6.0, 0.5) var flint_volume_db := -8.0
## Variacion aleatoria de tono por golpe (1.2 = +-20%) para que no suene repetitivo.
@export_range(1.0, 2.0, 0.01) var flint_random_pitch := 1.2
@export_range(0.0, 12.0, 0.5) var flint_random_volume_db := 3.0

@export_group("Light")
@export var light_color := Color(1.0, 0.6, 0.25):
	set(value):
		light_color = value
		if _light:
			_light.light_color = light_color
@export_range(0.0, 8.0, 0.1) var light_energy := 2.2
@export_range(1.0, 20.0, 0.5) var light_range := 6.0:
	set(value):
		light_range = value
		if _light:
			_light.omni_range = light_range
@export_range(0.0, 1.0, 0.05) var flicker_amount := 0.25
@export var light_casts_shadows := true:
	set(value):
		light_casts_shadows = value
		if _light:
			_light.shadow_enabled = light_casts_shadows

var _logs: Node3D
var _fire: Node3D
var _fire_mat: ShaderMaterial
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _zone: InteractionZone
var _wheel: FirestarterWheel
var _flint_player: AudioStreamPlayer
var _minigame_active := false
var _marker := 0.0
var _hits := 0
var _hits_needed := 3
var _target_frac := 0.16
var _lighting_player: Player
var _sparks: GPUParticles3D
var _pot_on_fire: Node3D
var _log_mat: StandardMaterial3D
var _smoke_ramp: Gradient
var _t := 0.0
var _burn := 0.0
var _burn_tween: Tween


func _ready() -> void:
	add_to_group("campfire")
	_rebuild()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _minigame_active:
		_update_minigame(delta)
	if not lit or _light == null:
		return
	_t += delta
	var flicker := sin(_t * 9.0) * 0.5 + sin(_t * 23.0 + 1.7) * 0.3 + sin(_t * 5.3 + 4.0) * 0.2
	_light.light_energy = light_energy * _burn * (1.0 + flicker * flicker_amount)
	_update_sound_fade()


## Volumen pleno hasta sound_full_radius; de ahi, smoothstep hasta silencio en sound_max_distance.
func _update_sound_fade() -> void:
	if _audio == null or not _audio.playing:
		return
	var listener := get_viewport().get_audio_listener_3d()
	if listener == null:
		return
	var d := _audio.global_position.distance_to(listener.global_position)
	var t := clampf((d - sound_full_radius) / maxf(sound_max_distance - sound_full_radius, 0.001), 0.0, 1.0)
	var lin := (1.0 - smoothstep(0.0, 1.0, t)) * _burn
	_audio.volume_db = sound_volume_db + (linear_to_db(lin) if lin > 0.001 else -80.0)


func toggle() -> void:
	lit = not lit


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in [_logs, _fire, _smoke, _light]:
		if child:
			child.queue_free()

	# --- Troncos en estrella: cajas alargadas, el extremo exterior en el suelo y el
	# interior apoyado sobre el montón (inclinados hacia el centro).
	_logs = Node3D.new()
	_logs.name = "Logs"
	_log_mat = StandardMaterial3D.new()
	_log_mat.albedo_texture = log_texture
	_log_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_log_mat.roughness = 1.0
	_log_mat.uv1_scale = Vector3(1.0, 3.0, 1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(log_radius * 2.0, log_radius * 2.0, log_length)
	mesh.material = _log_mat
	for i in log_count:
		var log := MeshInstance3D.new()
		log.name = "Log%d" % i
		log.mesh = mesh
		var yaw := TAU * float(i) / float(log_count) + float(i) * 0.37
		log.rotation.y = yaw
		log.rotation.x = -0.45  # inner end raised onto the pile
		log.position = Vector3(sin(yaw), 0.0, cos(yaw)) * log_length * -0.18
		log.position.y = log_radius + log_length * 0.16
		_logs.add_child(log)
	add_child(_logs)

	# --- Llama: shader pixel-art sobre dos quads cruzados.
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = FIRE_SHADER
	_fire = _make_crossed_quads("Fire", fire_width, fire_height, log_radius * 2.5, _fire_mat)
	add_child(_fire)

	# --- Humo: pompas grandes que se inflan, giran y se disipan.
	_smoke = _make_smoke_particles()
	add_child(_smoke)

	# --- Sonido posicional (atenuado por distancia al listener del rig).
	if fire_sound and not Engine.is_editor_hint():
		_audio = AudioStreamPlayer3D.new()
		_audio.name = "FireSound"
		_audio.stream = fire_sound
		_audio.volume_db = sound_volume_db
		# Atenuacion propia (meseta + fade suave a cero) calculada en _process:
		# el modelo nativo no tiene "pleno hasta X y despues fundido".
		_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		_audio.max_distance = 0.0
		_audio.position.y = 0.4
		add_child(_audio)

	# --- Luz.
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.position.y = 0.6
	_light.shadow_enabled = light_casts_shadows
	add_child(_light)

	if interaction_enabled and not Engine.is_editor_hint():
		_build_interaction()

	_update_fx_params()
	_apply_state()


func _build_interaction() -> void:
	_zone = InteractionZone.new()
	_zone.name = "InteractionZone"
	_zone.radius = interaction_radius
	_zone.height = 0.5
	_zone.interact_priority = 2
	_zone.key_text = prompt_key_text
	_zone.player_exited.connect(_on_player_exited)
	add_child(_zone)

	_wheel = FirestarterWheel.new()
	_wheel.name = "FirestarterWheel"
	var renderer := get_node_or_null("/root/RetroRenderer")
	if renderer and renderer.get("hud_layer") != null:
		renderer.hud_layer.add_child(_wheel)
	else:
		var layer := CanvasLayer.new()
		layer.add_child(_wheel)
		add_child(layer)

	var randomizer := AudioStreamRandomizer.new()
	randomizer.add_stream(0, flint_sound)
	randomizer.random_pitch = flint_random_pitch
	randomizer.random_volume_offset_db = flint_random_volume_db
	_flint_player = AudioStreamPlayer.new()
	_flint_player.name = "FlintSound"
	_flint_player.stream = randomizer
	_flint_player.volume_db = flint_volume_db
	_flint_player.max_polyphony = 3
	add_child(_flint_player)
	_sparks = _make_sparks()
	add_child(_sparks)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_wheel) and not is_ancestor_of(_wheel):
		_wheel.queue_free()


## El jugador esta dentro de la zona de interaccion (lo usa el pot para "poner al fuego").
func is_player_in_range(player: Player) -> bool:
	return _zone != null and _zone.player_in_range == player


func _on_player_exited(_player: Player) -> void:
	if _minigame_active:
		_cancel_minigame()


# ------------------------------------------------------------------ InteractionZone

func can_interact(_player: Player) -> bool:
	return not _minigame_active


func interaction_prompt(_player: Player) -> String:
	return prompt_extinguish_text if lit else prompt_light_text


## E: durante el minijuego (E capturada) es el golpe; si no, enciende (minijuego) o apaga.
func interact_with(player: Player) -> void:
	if _minigame_active:
		_minigame_press()
	elif not lit and minigame_enabled:
		_start_minigame(player)
	else:
		toggle()
		_zone.refresh_prompt()


# ------------------------------------------------------------------ minijuego

func _start_minigame(player: Player) -> void:
	_minigame_active = true
	_hits = 0
	_hits_needed = hits_to_light
	_target_frac = target_size_deg / 360.0
	_lighting_player = player
	_lighting_player.start_action(light_action)
	InteractionManager.capture(_zone, player)
	_new_round()
	_zone.hide_prompt()
	_wheel.show_wheel()
	_play_flint()


func _new_round() -> void:
	_marker = 0.0
	# Seccion en un punto aleatorio, lejos del arranque de la marca.
	_wheel.set_target(randf_range(0.2, 0.8), _target_frac)
	_wheel.marker_frac = 0.0


func _update_minigame(delta: float) -> void:
	_marker += delta / sweep_time
	if _marker >= 1.0:
		# Vuelta completa sin pulsar: cuenta como fallo.
		_miss()
		return
	_wheel.marker_frac = _marker
	# La rueda flota sobre la hoguera.
	var cam := get_viewport().get_camera_3d()
	if cam:
		_wheel.position = (cam.unproject_position(global_position + Vector3(0.0, 3.0, 0.0)) - _wheel.size * 0.5).round()


func _minigame_press() -> void:
	_play_flint()
	if is_instance_valid(_lighting_player):
		_lighting_player.strike()
	if _wheel.is_marker_in_target():
		_hits += 1
		_wheel.flash()
		_sparks.restart()
		if _hits >= _hits_needed:
			_finish_minigame()
			return
		_target_frac *= target_shrink
		_new_round()
	else:
		_miss()


func _miss() -> void:
	_hits = 0
	_target_frac = target_size_deg / 360.0
	_new_round()


func _finish_minigame() -> void:
	_minigame_active = false
	_wheel.pop_out()
	_release_lighting_player()
	lit = true
	_zone.refresh_prompt()


func _cancel_minigame() -> void:
	_minigame_active = false
	_wheel.pop_out()
	_release_lighting_player()
	_zone.refresh_prompt()


## Un pot (u otro cacharro) se apoya sobre el fuego: llama dispersa y sin humo.
func place_pot(pot: Node3D) -> void:
	_pot_on_fire = pot
	_fire.scale = pot_fire_spread
	_smoke.emitting = false
	pot_changed.emit(true)


func remove_pot() -> void:
	_pot_on_fire = null
	_fire.scale = Vector3.ONE
	_smoke.emitting = lit and smoke_enabled
	pot_changed.emit(false)


func has_pot() -> bool:
	return _pot_on_fire != null


func _release_lighting_player() -> void:
	InteractionManager.release(_zone)
	if is_instance_valid(_lighting_player):
		_lighting_player.stop_action()
	_lighting_player = null


## Chispas de acierto: rafaga corta de particulas aditivas saltando de la hoguera.
func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.55
	p.position.y = 0.3
	p.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 65.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.8
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.3, 0.05, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.09
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = preload("res://assets/textures/fx/flame_blob.png")
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _play_flint() -> void:
	if _flint_player:
		_flint_player.play()


func _particle_sprite_material(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	return mat


func _make_crossed_quads(quads_name: String, width: float, height: float, base_y: float, mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = quads_name
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	quad.material = mat
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.rotation.y = PI * 0.5 * float(i)
		mi.position.y = base_y + height * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _make_smoke_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	var smoke_lifetime := 5.5
	p.lifetime = smoke_lifetime
	p.amount = 30
	p.randomness = 0.35
	p.position.y = fire_height * 0.6
	p.custom_aabb = AABB(Vector3(-smoke_width - 3.0, -1, -smoke_width - 3.0),
			Vector3(smoke_width * 2.0 + 6.0, smoke_height + 5.0, smoke_width * 2.0 + 6.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = fire_width * 0.14
	pm.direction = Vector3.UP
	pm.spread = 4.0
	pm.initial_velocity_min = smoke_height / smoke_lifetime * 0.8
	pm.initial_velocity_max = smoke_height / smoke_lifetime * 1.2
	pm.gravity = Vector3(0.06, 0.12, 0.06)
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.scale_min = 0.9
	pm.scale_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.1))
	sc.add_point(Vector2(0.5, 0.45))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	_smoke_ramp = Gradient.new()
	_smoke_ramp.offsets = PackedFloat32Array([0.0, 0.07, 0.72, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = _smoke_ramp
	pm.color_ramp = gt
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.1
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * smoke_width * 0.6
	quad.material = _particle_sprite_material(SMOKE_SPRITE, false)
	p.draw_pass_1 = quad
	return p


func _update_fx_params() -> void:
	if _fire_mat:
		_fire_mat.set_shader_parameter("intensity", fire_intensity * _burn)
		_fire_mat.set_shader_parameter("color_core", fire_color_core)
		_fire_mat.set_shader_parameter("color_mid", fire_color_mid)
		_fire_mat.set_shader_parameter("color_outer", fire_color_outer)
	if _smoke:
		_smoke.amount_ratio = clampf(smoke_density * 1.4, 0.1, 1.0)
	if _smoke_ramp:
		var mid := smoke_color_dark.lerp(smoke_color_light, 0.5)
		_smoke_ramp.colors = PackedColorArray([
			Color(smoke_color_dark, 0.0), Color(smoke_color_dark, smoke_density * 0.95),
			Color(mid, smoke_density * 0.6), Color(smoke_color_light, 0.0)])


func _apply_state() -> void:
	if _fire == null:
		return
	if _burn_tween and _burn_tween.is_valid():
		_burn_tween.kill()
	if lit:
		_fire.visible = true
		_light.visible = true
		_smoke.visible = true
		_smoke.emitting = smoke_enabled and _pot_on_fire == null
		if _audio and not _audio.playing:
			_audio.play(randf() * maxf(fire_sound.get_length() - 1.0, 0.0))
		if ignite_time <= 0.0 or Engine.is_editor_hint():
			_set_burn(1.0)
		else:
			_burn_tween = create_tween()
			_burn_tween.tween_method(_set_burn, _burn, 1.0, ignite_time * (1.0 - _burn))
	else:
		_smoke.emitting = false  # las bocanadas existentes se disipan solas
		if extinguish_time <= 0.0 or Engine.is_editor_hint() or _burn <= 0.0:
			_set_burn(0.0)
			_on_extinguished()
		else:
			_burn_tween = create_tween()
			_burn_tween.tween_method(_set_burn, _burn, 0.0, extinguish_time * _burn)
			_burn_tween.finished.connect(_on_extinguished, CONNECT_ONE_SHOT)


## 0 = apagada, 1 = ardiendo a tope. Escala llama, luz, brasas y volumen del crepitar.
func _set_burn(value: float) -> void:
	_burn = value
	if _fire_mat:
		_fire_mat.set_shader_parameter("intensity", fire_intensity * _burn)
	if _log_mat:
		_log_mat.albedo_color = charred_tint.lerp(Color.WHITE, _burn)


func _on_extinguished() -> void:
	_fire.visible = false
	_light.visible = false
	if _audio:
		_audio.stop()
