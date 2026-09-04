@tool
class_name Player
extends CharacterBody3D
## Character controller with camera-relative movement and Idle / Walk / Run animations.
## Movement input is projected onto the camera's yaw so "forward" always means
## "away from the camera", even while the isometric camera rotates.

@export_group("Movement")
@export var walk_speed := 2.5
@export var run_speed := 5.5
## If true you run by default and hold `sprint` to walk; if false, hold `sprint` (Shift) to run.
@export var run_by_default := false
## m/s² while there is input. Low values = heavy, slow-to-start character.
@export var acceleration := 6.0
## m/s² when input is released. The character always brakes along its facing, never sideways.
@export var deceleration := 12.0
## How fast the model turns to face the input direction (higher = tighter turns).
@export var turn_speed := 5.0

@export_group("Jump & Gravity")
@export var jump_enabled := true
@export var jump_velocity := 5.0
@export var gravity_scale := 2.0

@export_group("Animation")
@export var idle_animation := "Idle"
@export var walk_animation := "Walk"
@export var run_animation := "Run"
## One-shot clip played by play_pickup(); movement is locked while it runs.
@export var pickup_animation := "bp_pickup"
## Fraction of the pickup clip at which the hand "reaches" the item (backpack appears,
## pickup_reached is emitted). The drop plays the same clip backwards and uses it too.
@export_range(0.0, 1.0, 0.05) var pickup_reach_fraction := 0.5
## Channelled "lighting a fire" clips: start (one-shot) -> loop (while striking) -> end.
@export var light_fire_start_animation := "light_fire_start"
## Pose de espera durante el minijuego (en bucle); el golpe solo suena al pulsar.
@export var light_fire_idle_animation := "light_fire_idle"
## Clip del golpe: se reproduce UNA vez por pulsacion y vuelve a la pose de espera.
@export var light_fire_strike_animation := "light_fire"
@export var light_fire_end_animation := "light_fire_end"
## Agacharse (Ctrl): start -> idle en bucle -> end al moverse o pulsar Ctrl de nuevo.
@export var crouch_start_animation := "crouch_start"
@export var crouch_idle_animation := "crouch_idle"
@export var crouch_end_animation := "crouch_end"
@export var crouch_action: StringName = &"crouch"
## Sentarse en el suelo (tecla 0): transicion al clip en bucle; moverse o repetir levanta.
@export var sit_animation := "Sit_floor"
@export var sit_action: StringName = &"sit"

@export_group("Carry")
## Huesos de las manos: el objeto llevado se ancla al punto medio entre ambos y se
## mueve con las animaciones. Si faltan, se usa el anclaje fijo de abajo.
@export var carry_bones: PackedStringArray = ["hand.l", "hand.r"]
## Ajuste local extra sobre el punto medio de las manos (-Z = hacia delante del personaje).
@export var carry_offset := Vector3(0.0, -0.2, -0.3)
## Anclaje fijo de reserva (sin huesos): delante y altura.
@export var carry_forward := 0.55
@export var carry_height := 0.75
## Playback speed of the pickup/drop clip (2 = twice as fast).
@export_range(0.25, 4.0, 0.05) var pickup_animation_speed := 2.0
## Input action that drops the backpack (plays the pickup clip in reverse).
@export var drop_action: StringName = &"drop"
## Scene spawned on the ground when dropping.
@export var backpack_pickup_scene: PackedScene = preload("res://scenes/props/backpack/backpack.tscn")
## Where the dropped bag appears, relative to the character (forward distance).
@export var drop_distance := 0.5
## Sound played when the bag leaves the hand (same clip as the pickup, pitched down a bit).
@export var drop_sound: AudioStream = preload("res://assets/audio/pickupbackpack.wav")
@export_range(-40.0, 6.0, 0.5) var drop_volume_db := -8.0
@export_range(0.5, 1.5, 0.01) var drop_pitch := 0.85
## Cross-fade time between animations, in seconds.
@export_range(0.0, 1.0, 0.01) var blend_time := 0.3
## Cross-fade for ACTIONS (pickup, crouch, channels): short so they respond instantly.
@export_range(0.0, 0.5, 0.01) var action_blend_time := 0.08
## Below this horizontal speed the character is considered idle.
@export var idle_threshold := 0.15
## Speed (m/s) at which the Walk clip plays at 1x; the clip is time-scaled to match velocity.
@export var walk_anim_reference_speed := 2.5
## Speed (m/s) at which the Run clip plays at 1x.
@export var run_anim_reference_speed := 5.5
## Scale animation playback to the actual velocity so feet don't slide.
@export var sync_animation_to_speed := true

@export_group("Footsteps")
@export var footsteps_enabled := true
@export var footstep_stream: AudioStream = preload("res://assets/audio/step.wav")
## Base volume. Keep it low: footsteps should be felt, not heard.
@export_range(-40.0, 6.0, 0.5) var footstep_volume_db := -16.0
## Random pitch multiplier range (1.12 = ±12%) so repeated steps don't sound identical.
@export_range(1.0, 2.0, 0.01) var footstep_random_pitch := 1.12
## Random volume offset range in dB.
@export_range(0.0, 12.0, 0.5) var footstep_random_volume_db := 3.0
## Extra volume and pitch multiplier when running (heavier, louder steps).
@export_range(-12.0, 12.0, 0.5) var run_volume_boost_db := 3.0
@export_range(0.5, 1.5, 0.01) var run_pitch := 0.95
## The two foot bones. A step fires when one foot becomes lower than the other
## (= the swinging foot lands). Comparing feet cancels out body bobbing.
@export var foot_bones: PackedStringArray = ["foot.l", "foot.r"]
## Small delay so the sound lands on the very bottom of the stride, not the crossing.
@export_range(0.0, 0.2, 0.01) var footstep_delay := 0.04
## Minimum time between two steps (filters jitter during animation blends).
@export_range(0.05, 0.5, 0.01) var footstep_min_interval := 0.15

@export_group("Holding")
## Static pose layered on the arms while holding something (on top of walk/run/idle).
@export var hold_animation := "hold_pose"
## Bones the hold pose overrides; the rest keep the locomotion animation.
@export var hold_bones: PackedStringArray = ["shoulder.l", "arm.l", "hand.l", "shoulder.r", "arm.r", "hand.r"]
## Seconds to blend the hold pose in/out.
@export_range(0.0, 1.0, 0.05) var hold_blend_time := 0.2
## Input action that toggles holding (temporary, for testing: key 1).
@export var hold_toggle_action: StringName = &"hold_toggle"
## Whether the character is currently holding something.
@export var holding := false:
	set(value):
		holding = value
		_apply_holding()

@export_group("Model")
## Uniform scale applied to the imported character model (the raw GLB is ~5.6 units tall).
@export var model_scale := 0.3:
	set(value):
		model_scale = value
		_apply_model_scale()
## Extra yaw (degrees) if the model's "front" doesn't line up with -Z (this model faces +Z).
@export var model_yaw_offset_deg := 180.0
## Small lift so the soles aren't coplanar with the floor (avoids z-fighting and the
## x-ray silhouette flickering on the feet).
@export_range(0.0, 0.2, 0.005) var model_ground_offset := 0.03:
	set(value):
		model_ground_offset = value
		_apply_model_scale()
## Force nearest-neighbour texture filtering on the imported model materials (crisp pixels).
@export var nearest_texture_filter := true
## Render the model unshaded (flat texture colours, no lighting). It still casts shadows.
@export var unshaded_model := false
## 1-px dark outline (inverted hull in screen space, constant width at any zoom) so the
## character reads against busy backgrounds and in dark interiors.
@export var outline_enabled := true
@export var outline_color := Color(0.03, 0.02, 0.02)
@export_range(0.5, 4.0, 0.5) var outline_width_px := 1.0
## Show or hide the backpack mesh.
@export var show_backpack := true:
	set(value):
		show_backpack = value
		_apply_backpack_visibility()
## Name of the backpack MeshInstance3D inside the imported model.
@export var backpack_mesh_name := "Backpack"

@export_group("X-ray")
## Draw a flat silhouette wherever the character is hidden behind geometry.
@export var xray_enabled := true
## Material applied as material_overlay to every mesh of the model. Edit colour/alpha/pattern there.
@export var xray_material: ShaderMaterial = preload("res://scenes/player/shaders/xray_silhouette.tres")
## Only show the silhouette when the character is completely hidden (all probe points
## occluded from the camera). Off = show it on any occluded pixel.
@export var xray_only_when_fully_hidden := true
## Physics layers that count as visual occluders for the probes
## (1 = world, 4 = props, 8 = foliage occluder areas from BillboardTree).
@export_flags_3d_physics var xray_occluder_mask := 1 | 4 | 8
## Body points (local, metres) that must ALL be hidden. Head, chest, feet, shoulders.
@export var xray_probe_points: PackedVector3Array = PackedVector3Array([
	Vector3(0.0, 1.6, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.3, 0.0),
	Vector3(0.3, 1.1, 0.0), Vector3(-0.3, 1.1, 0.0), Vector3(0.0, 1.1, 0.3), Vector3(0.0, 1.1, -0.3)])
## Seconds to fade the silhouette in/out.
@export_range(0.0, 1.0, 0.05) var xray_fade_time := 0.15

## Emitted at pickup_reach_fraction of the pickup clip (hand touches the item).
signal pickup_reached
## Emitted when the pickup clip ends and control returns to the player.
signal pickup_finished
## Canal sin fase idle (agacharse a coger/soltar): emitido al acabar el clip de inicio,
## justo antes del clip de cierre. Es el momento de coger o dejar el objeto.
signal channel_apex(kind: String)
## Emitted (reverse clip at the reach fraction) when the bag leaves the hand.
signal backpack_dropped(pickup: Node3D)

@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model.find_child("AnimationPlayer", true, false)

var _camera_rig: Node3D
var _current_anim := ""
var _speed := 0.0
var _action_playing := false
var _sitting := false
## Bloqueo externo del movimiento (p. ej. una escena corta): el personaje se queda quieto.
var movement_locked := false
var _action_reached := false
var _action_reverse := false
var _channel_phase := ""  # "" | "start" | "idle" | "strike" | "end"
var _channel := {}        # nombres de clips del canal activo + "kind"
var _hold_modifier: HoldPoseModifier
## Ancla para objetos en brazos; sigue las manos del esqueleto.
var carry_slot: Node3D
var _carry_bone_a := -1
var _carry_bone_b := -1
var _hold_tween: Tween
var _xray_mat: ShaderMaterial
var _xray_full_alpha := 0.75
var _xray_hidden := false
var _xray_tween: Tween

var _skeleton: Skeleton3D
var _step_player: AudioStreamPlayer
var _foot_indices: PackedInt32Array
var _foot_diff_sign := 0
var _since_last_step := INF


func _ready() -> void:
	_apply_model_scale()
	_apply_backpack_visibility()
	if Engine.is_editor_hint():
		return  # editor preview only: scale + backpack flag, no gameplay setup
	_prepare_model_materials(_model)
	if xray_enabled and xray_material:
		# Per-player copy so the alpha can be driven without touching the shared resource.
		_xray_mat = xray_material.duplicate() as ShaderMaterial
		_xray_full_alpha = float(_xray_mat.get_shader_parameter("alpha"))
		if xray_only_when_fully_hidden:
			_xray_mat.set_shader_parameter("alpha", 0.0)
		_apply_overlay(_model, _xray_mat)
	_camera_rig = get_tree().get_first_node_in_group("camera_rig")
	carry_slot = Node3D.new()
	carry_slot.name = "CarrySlot"
	add_child(carry_slot)
	var sk := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		_skeleton = sk
	if sk and carry_bones.size() == 2:
		_carry_bone_a = sk.find_bone(carry_bones[0])
		_carry_bone_b = sk.find_bone(carry_bones[1])
	if _anim == null:
		push_warning("Player: no AnimationPlayer found under Model; animations disabled.")
	else:
		# Tolerate case/whitespace differences in clip names ("run" vs "Run").
		idle_animation = _resolve_animation_name(idle_animation)
		walk_animation = _resolve_animation_name(walk_animation)
		run_animation = _resolve_animation_name(run_animation)
		pickup_animation = _resolve_animation_name(pickup_animation)
		light_fire_start_animation = _resolve_animation_name(light_fire_start_animation)
		light_fire_idle_animation = _resolve_animation_name(light_fire_idle_animation)
		light_fire_strike_animation = _resolve_animation_name(light_fire_strike_animation)
		light_fire_end_animation = _resolve_animation_name(light_fire_end_animation)
		crouch_start_animation = _resolve_animation_name(crouch_start_animation)
		crouch_idle_animation = _resolve_animation_name(crouch_idle_animation)
		crouch_end_animation = _resolve_animation_name(crouch_end_animation)
		# Safety net in case the import settings didn't mark the clips as looping.
		for anim_name in [idle_animation, walk_animation, run_animation]:
			if not _anim.has_animation(anim_name):
				push_warning("Player: animation '%s' not found in the model (available: %s)." % [anim_name, _anim.get_animation_list()])
				continue
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_warn_if_idle_is_rest_pose()
		_setup_footsteps()
		_setup_hold_pose()
		_anim.animation_finished.connect(_on_animation_finished)
		_play(idle_animation)


## Returns the actual clip name matching `wanted` ignoring case, or `wanted` if none.
func _resolve_animation_name(wanted: String) -> String:
	if _anim.has_animation(wanted):
		return wanted
	for name in _anim.get_animation_list():
		if String(name).strip_edges().to_lower() == wanted.strip_edges().to_lower():
			return String(name)
	return wanted


## Diagnostic: an exported Idle that only contains the rest/T pose looks like a bug in
## the controller when it's really an export problem. Flag it loudly.
func _warn_if_idle_is_rest_pose() -> void:
	if not _anim.has_animation(idle_animation) or not _anim.has_animation("T"):
		return
	var idle := _anim.get_animation(idle_animation)
	var t_pose := _anim.get_animation("T")
	for i in idle.get_track_count():
		var path := idle.track_get_path(i)
		var t_track := t_pose.find_track(path, idle.track_get_type(i))
		if t_track < 0 or idle.track_get_key_count(i) == 0:
			continue
		var idle_key = idle.track_get_key_value(i, 0)
		var t_key = t_pose.track_get_key_value(t_track, 0)
		if idle_key is Quaternion and not idle_key.is_equal_approx(t_key):
			return
		if idle_key is Vector3 and not idle_key.is_equal_approx(t_key):
			return
	push_warning("Player: the '%s' clip is identical to the 'T' pose (%.3fs). Re-export it with a real idle pose."
			% [idle_animation, idle.length])


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_relative_direction(input)
	var running := _is_running()
	if is_crouching() and input != Vector2.ZERO:
		stop_channeling()  # crouch_end; el movimiento se libera al terminar el clip
	if _sitting and input != Vector2.ZERO:
		stand_up()
	if _action_playing or _sitting or movement_locked:
		direction = Vector3.ZERO
		running = false
	var target_speed := run_speed if running else walk_speed

	# Weight without drift: speed is a scalar that ramps slowly, and the character always
	# moves along its facing. Direction changes become turns (arcs), never sideways sliding.
	if direction != Vector3.ZERO:
		_face_direction(direction, delta)
		_speed = move_toward(_speed, target_speed, acceleration * delta)
	else:
		_speed = move_toward(_speed, 0.0, deceleration * delta)

	var facing := _facing_direction()
	velocity.x = facing.x * _speed
	velocity.z = facing.z * _speed
	move_and_slide()

	if _action_playing:
		_update_action()
	else:
		_update_animation(Vector2(velocity.x, velocity.z).length(), running)
	_update_footsteps(delta)
	_update_xray_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed(sit_action):
		get_viewport().set_input_as_handled()
		if _sitting:
			stand_up()
		elif not _action_playing and not movement_locked:
			sit_down()
	elif event.is_action_pressed(crouch_action):
		get_viewport().set_input_as_handled()
		if is_crouching():
			stop_channeling()
		elif not _action_playing and not _sitting:
			start_crouch()
	elif event.is_action_pressed(drop_action) and show_backpack and not _action_playing and not is_carrying():
		get_viewport().set_input_as_handled()
		play_drop()
	elif event.is_action_pressed(hold_toggle_action):
		get_viewport().set_input_as_handled()
		holding = not holding


# ------------------------------------------------------------------ actions

## Plays the pickup clip once, locks movement, shows the backpack at pickup_reach_fraction.
## Returns false if the clip is missing (caller should fall back to an instant pickup).
func play_pickup() -> bool:
	return _start_action(false)


## Plays the pickup clip backwards: the bag leaves the hand at pickup_reach_fraction and a
## BackpackPickup is spawned on the ground in front of the character.
func play_drop() -> bool:
	if not show_backpack:
		return false
	return _start_action(true)


func _start_action(reverse: bool) -> bool:
	if _anim == null or not _anim.has_animation(pickup_animation) or _action_playing:
		return false
	_action_playing = true
	_action_reached = false
	_action_reverse = reverse
	_anim.get_animation(pickup_animation).loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	if reverse:
		_anim.play(pickup_animation, action_blend_time, -pickup_animation_speed, true)
	else:
		_anim.play(pickup_animation, action_blend_time, pickup_animation_speed)
	_current_anim = pickup_animation
	return true


func is_action_playing() -> bool:
	return _action_playing


func _update_action() -> void:
	if _channel_phase != "":
		return  # las transiciones del canal las lleva _on_animation_finished
	var anim := _anim.get_animation(pickup_animation)
	var t := _anim.current_animation_position / maxf(anim.length, 0.001) \
			if _anim.current_animation == pickup_animation else 1.0
	var reached := (t <= pickup_reach_fraction) if _action_reverse else (t >= pickup_reach_fraction)
	if not _action_reached and reached:
		_on_action_reached()
	if not _anim.is_playing() or _anim.current_animation != pickup_animation:
		_finish_action()


func _on_action_reached() -> void:
	_action_reached = true
	if _action_reverse:
		show_backpack = false
		_spawn_dropped_backpack()
	else:
		show_backpack = true
		pickup_reached.emit()


func _spawn_dropped_backpack() -> void:
	if backpack_pickup_scene == null:
		return
	var pickup := backpack_pickup_scene.instantiate() as Node3D
	get_parent().add_child(pickup)
	pickup.global_position = global_position + _facing_direction() * drop_distance
	if drop_sound:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = drop_sound
		sfx.volume_db = drop_volume_db
		sfx.pitch_scale = drop_pitch * randf_range(0.95, 1.05)
		sfx.finished.connect(sfx.queue_free)
		add_child(sfx)
		sfx.play()
	backpack_dropped.emit(pickup)


func _on_animation_finished(anim_name: StringName) -> void:
	if not _action_playing:
		return
	var n := String(anim_name)
	if _channel_phase == "start" and n == _channel.get("start", "?"):
		if _channel.has("idle"):
			_channel_to_idle()
		else:
			channel_apex.emit(_channel.get("kind", ""))
			_play_channel_end()
	elif _channel_phase == "strike" and n == _channel.get("strike", "?"):
		_channel_to_idle()
	elif _channel_phase == "end" and n == _channel.get("end", "?"):
		_channel_phase = ""
		_channel = {}
		_finish_action()
	elif _channel_phase == "" and n == pickup_animation:
		_finish_action()


## Canal generico: start (una vez) -> idle (bucle) [-> strike por pulsacion] -> end.
## Bloquea el movimiento mientras dura.
func _start_channel(anims: Dictionary) -> bool:
	if _anim == null or _action_playing or not _anim.has_animation(anims.get("start", "")):
		return false
	_channel = anims
	_action_playing = true
	_action_reached = true  # no hay "reach" en canales
	_channel_phase = "start"
	_anim.get_animation(_channel.start).loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(_channel.start, action_blend_time)
	_current_anim = _channel.start
	return true


## Bucle "encendiendo fuego" del minijuego de la hoguera.
func start_fire_lighting() -> bool:
	return _start_channel({
		"kind": "fire",
		"start": light_fire_start_animation,
		"idle": light_fire_idle_animation,
		"strike": light_fire_strike_animation,
		"end": light_fire_end_animation,
	})


## Agacharse: Ctrl (o llamada directa). Moverse o repetir Ctrl lo termina.
func start_crouch() -> bool:
	return _start_channel({
		"kind": "crouch",
		"start": crouch_start_animation,
		"idle": crouch_idle_animation,
		"end": crouch_end_animation,
	})


func is_crouching() -> bool:
	return _action_playing and _channel.get("kind", "") == "crouch" and _channel_phase != "end"


func is_sitting() -> bool:
	return _sitting


## Sentarse en el suelo: funde al clip de sentado y bloquea el movimiento hasta levantarse.
func sit_down() -> bool:
	if _anim == null or _sitting or _action_playing:
		return false
	var name := _resolve_animation_name(sit_animation)
	if not _anim.has_animation(name):
		push_warning("Player: no existe la animacion de sentarse '%s'." % sit_animation)
		return false
	_sitting = true
	_speed = 0.0
	_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	_anim.speed_scale = 1.0
	_anim.play(name, action_blend_time * 3.0)
	_current_anim = name
	return true


func stand_up() -> void:
	if not _sitting:
		return
	_sitting = false
	_play(idle_animation)


func is_carrying() -> bool:
	return carry_slot != null and carry_slot.get_child_count() > 0


## Secuencia corta agacharse-y-volver (coger/soltar objetos): crouch_start ->
## channel_apex -> crouch_end. Bloquea el movimiento mientras dura.
func play_crouch_action() -> bool:
	return _start_channel({
		"kind": "crouch_grab",
		"start": crouch_start_animation,
		"end": crouch_end_animation,
	})


## Pose de espera del canal (en bucle) hasta la siguiente pulsacion o el cierre.
func _channel_to_idle() -> void:
	_channel_phase = "idle"
	_anim.get_animation(_channel.idle).loop_mode = Animation.LOOP_LINEAR
	_anim.play(_channel.idle, 0.1)
	_current_anim = _channel.idle


## Golpe (canal con "strike"): una pasada del clip y de vuelta a la espera.
func play_fire_strike() -> void:
	if (_channel_phase != "idle" and _channel_phase != "strike") or not _channel.has("strike"):
		return
	_channel_phase = "strike"
	var anim := _anim.get_animation(_channel.strike)
	anim.loop_mode = Animation.LOOP_NONE
	_anim.play(_channel.strike, 0.05)
	_anim.seek(0.0)
	_current_anim = _channel.strike


## Sale del canal con el clip de cierre y devuelve el control.
func stop_channeling() -> void:
	if _channel_phase == "" or _channel_phase == "end":
		return
	_play_channel_end()


func _play_channel_end() -> void:
	if not _channel.has("end") or not _anim.has_animation(_channel.end):
		_channel_phase = ""
		_channel = {}
		_finish_action()
		return
	_channel_phase = "end"
	_anim.get_animation(_channel.end).loop_mode = Animation.LOOP_NONE
	_anim.play(_channel.end, 0.1)
	_current_anim = _channel.end


## Alias historico usado por la hoguera.
func stop_fire_lighting() -> void:
	stop_channeling()


func _finish_action() -> void:
	if not _action_playing:
		return
	_action_playing = false
	if not _action_reached:
		_on_action_reached()
	_current_anim = ""
	_play(idle_animation)
	pickup_finished.emit()


# ------------------------------------------------------------------ x-ray

## Casts one ray per probe point from the camera side; the silhouette is enabled only
## when every probe is blocked (character completely hidden).
func _update_xray_visibility() -> void:
	if _xray_mat == null or not xray_only_when_fully_hidden:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var space := get_world_3d().direct_space_state
	var back := -cam.global_transform.basis.z  # camera forward
	var all_hidden := true
	for offset in xray_probe_points:
		var target := global_position + offset
		var origin := target - back * 60.0
		var query := PhysicsRayQueryParameters3D.create(origin, target, xray_occluder_mask, [get_rid()])
		query.collide_with_areas = true
		query.collide_with_bodies = true
		if space.intersect_ray(query).is_empty():
			all_hidden = false
			break
	if all_hidden != _xray_hidden:
		_xray_hidden = all_hidden
		if _xray_tween and _xray_tween.is_valid():
			_xray_tween.kill()
		var target_alpha := _xray_full_alpha if all_hidden else 0.0
		if xray_fade_time <= 0.0:
			_xray_mat.set_shader_parameter("alpha", target_alpha)
		else:
			_xray_tween = create_tween()
			_xray_tween.tween_method(func(a: float) -> void: _xray_mat.set_shader_parameter("alpha", a),
					float(_xray_mat.get_shader_parameter("alpha")), target_alpha, xray_fade_time)


# ------------------------------------------------------------------ holding

func _setup_hold_pose() -> void:
	hold_animation = _resolve_animation_name(hold_animation)
	if not _anim.has_animation(hold_animation):
		push_warning("Player: hold animation '%s' not found; holding pose disabled." % hold_animation)
		return
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	_hold_modifier = HoldPoseModifier.new()
	_hold_modifier.name = "HoldPose"
	_hold_modifier.pose_animation = _anim.get_animation(hold_animation)
	_hold_modifier.bones = hold_bones
	_hold_modifier.influence = 1.0 if holding else 0.0
	skeleton.add_child(_hold_modifier)


func _apply_holding() -> void:
	if _hold_modifier == null:
		return
	if _hold_tween and _hold_tween.is_valid():
		_hold_tween.kill()
	var target := 1.0 if holding else 0.0
	if hold_blend_time <= 0.0:
		_hold_modifier.influence = target
		return
	_hold_tween = create_tween()
	_hold_tween.tween_property(_hold_modifier, "influence", target, hold_blend_time)


# ------------------------------------------------------------------ footsteps

func _setup_footsteps() -> void:
	if not footsteps_enabled or footstep_stream == null:
		return
	_skeleton = _model.find_child("Skeleton3D", true, false)
	if _skeleton == null or foot_bones.size() != 2:
		push_warning("Player: footsteps need a Skeleton3D and exactly two foot bones; disabled.")
		return
	for bone_name in foot_bones:
		var idx := _skeleton.find_bone(bone_name)
		if idx < 0:
			push_warning("Player: foot bone '%s' not found; footsteps disabled." % bone_name)
			return
		_foot_indices.append(idx)

	var randomizer := AudioStreamRandomizer.new()
	randomizer.add_stream(0, footstep_stream)
	randomizer.random_pitch = footstep_random_pitch
	randomizer.random_volume_offset_db = footstep_random_volume_db
	_step_player = AudioStreamPlayer.new()
	_step_player.name = "Footsteps"
	_step_player.stream = randomizer
	_step_player.max_polyphony = 3
	add_child(_step_player)


## A step fires when the sign of (foot A height - foot B height) flips: the foot that
## just became the lowest is the one landing. Only while a locomotion clip is active.
func _update_footsteps(delta: float) -> void:
	if _step_player == null:
		return
	_since_last_step += delta
	var locomotion := _current_anim == walk_animation or _current_anim == run_animation
	if not locomotion:
		_foot_diff_sign = 0
		return
	var diff := _skeleton.get_bone_global_pose(_foot_indices[0]).origin.y 			- _skeleton.get_bone_global_pose(_foot_indices[1]).origin.y
	var sign := signi(int(sign(diff)))
	if sign != 0 and _foot_diff_sign != 0 and sign != _foot_diff_sign 			and _since_last_step >= footstep_min_interval:
		_since_last_step = 0.0
		var running := _current_anim == run_animation
		if footstep_delay > 0.0:
			get_tree().create_timer(footstep_delay).timeout.connect(_play_footstep.bind(running))
		else:
			_play_footstep(running)
	if sign != 0:
		_foot_diff_sign = sign


func _play_footstep(running: bool) -> void:
	_step_player.volume_db = footstep_volume_db + (run_volume_boost_db if running else 0.0)
	_step_player.pitch_scale = run_pitch if running else 1.0
	_step_player.play()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or carry_slot == null or carry_slot.get_child_count() == 0:
		return
	carry_slot.rotation.y = _model.rotation.y - deg_to_rad(model_yaw_offset_deg)
	if _carry_bone_a >= 0 and _carry_bone_b >= 0 and _skeleton:
		# Punto medio de las dos manos, en coordenadas de mundo: el objeto acompana la animacion.
		var a := _skeleton.global_transform * _skeleton.get_bone_global_pose(_carry_bone_a).origin
		var b := _skeleton.global_transform * _skeleton.get_bone_global_pose(_carry_bone_b).origin
		carry_slot.global_position = (a + b) * 0.5 + carry_slot.global_transform.basis * carry_offset
	else:
		carry_slot.position = _facing_direction() * carry_forward + Vector3(0.0, carry_height, 0.0)


func _is_running() -> bool:
	var sprint_held := Input.is_action_pressed("sprint")
	return (not sprint_held) if run_by_default else sprint_held


## Picks Idle / Walk / Run from the actual horizontal speed and syncs playback rate to it.
func _update_animation(speed: float, running: bool) -> void:
	if _anim == null or _sitting:
		return
	var anim_name := idle_animation
	var reference_speed := 1.0
	if speed > idle_threshold:
		# Choose the clip by intent (running) but fall back to Walk while still slow,
		# so accelerating from a stop doesn't flash the Run cycle at a crawl.
		var use_run := running and speed > walk_speed
		anim_name = run_animation if use_run else walk_animation
		reference_speed = run_anim_reference_speed if use_run else walk_anim_reference_speed
	_play(anim_name)
	if sync_animation_to_speed and anim_name != idle_animation and reference_speed > 0.0:
		_anim.speed_scale = clampf(speed / reference_speed, 0.5, 2.0)
	else:
		_anim.speed_scale = 1.0


func _play(anim_name: String) -> void:
	if not _anim.has_animation(anim_name):
		return
	# Guard: if a clip somehow stopped (non-looping import), restart it instead of freezing.
	if anim_name == _current_anim and _anim.is_playing():
		return
	_anim.play(anim_name, blend_time)
	_current_anim = anim_name


## Rotates a 2D input vector by the camera's yaw so movement is relative to the view.
## Input y is negative for "forward" (Input.get_vector convention).
func _camera_relative_direction(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var yaw := _camera_rig.global_rotation.y if _camera_rig else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return (right * input.x + forward * -input.y).normalized()


## World-space direction the model is currently facing (undoes model_yaw_offset_deg).
func _facing_direction() -> Vector3:
	var yaw := _model.rotation.y - deg_to_rad(model_yaw_offset_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


## Duplicates the imported GLB materials once and configures them:
##  - nearest filtering (glTF defaults to linear + mipmaps, which blurs texels)
##  - stencil write (reference 1) so the x-ray overlay can skip self-occlusion
func _prepare_model_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat is BaseMaterial3D:
				var copy := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				if nearest_texture_filter:
					copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				if unshaded_model:
					copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				if xray_enabled:
					copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
					copy.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
					copy.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
					copy.stencil_reference = 1
				if outline_enabled:
					copy.next_pass = _make_outline_material()
				mi.set_surface_override_material(i, copy)
	for child in node.get_children():
		_prepare_model_materials(child)


func _make_outline_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scenes/player/shaders/outline.gdshader")
	m.set_shader_parameter("color", outline_color)
	m.set_shader_parameter("width_px", outline_width_px)
	return m


func _apply_overlay(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material
	for child in node.get_children():
		_apply_overlay(child, material)


func _apply_backpack_visibility() -> void:
	if not is_node_ready():
		return
	var backpack := _model.find_child(backpack_mesh_name, true, false) as MeshInstance3D
	if backpack:
		backpack.visible = show_backpack
	else:
		push_warning("Player: backpack mesh '%s' not found in the model." % backpack_mesh_name)


func _apply_model_scale() -> void:
	if not is_node_ready():
		return
	_model.scale = Vector3.ONE * model_scale
	_model.position.y = model_ground_offset
