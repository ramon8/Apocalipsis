@tool
class_name Player
extends CharacterBody3D
## Controlador del personaje. Movimiento relativo a la camara con Idle / Walk / Run y una
## maquina de estados pequena:
##
##   LOCOMOTION  se mueve, salta, elige el clip por velocidad. Unico estado con input.
##   ACTION      ejecuta un PlayerAction (start -> [idle [-> strike]] -> [end]).
##   SITTING     sentado en el suelo en bucle; moverse o repetir la tecla levanta.
##   LOCKED      bloqueo externo (dialogo, cinematica) via lock()/unlock().
##
## Las acciones concretas (coger la mochila, agacharse, encender fuego...) son recursos
## PlayerAction: quien las necesita llama a start_action(recurso) y escucha
## action_apex / action_finished. Pasos, x-ray y ancla de carga son nodos hijos.

enum State { LOCOMOTION, ACTION, SITTING, LOCKED }
enum Phase { START, IDLE, STRIKE, END }

signal state_changed(previous: State, current: State)
signal action_started(kind: StringName)
## Instante util de la accion (la mano toca el objeto, agachado del todo...).
signal action_apex(kind: StringName)
## La accion ha terminado y el control vuelve al jugador.
signal action_finished(kind: StringName)
## Se ha soltado la mochila: `pickup` es la BackpackPickup recien creada en el suelo.
signal backpack_dropped(pickup: Node3D)

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
## Sentado en el suelo (tecla `sit_input`): clip en bucle.
@export var sit_animation := "Sit_floor"
## Cross-fade time between locomotion animations, in seconds.
@export_range(0.0, 1.0, 0.01) var blend_time := 0.3
## Cross-fade into ACTIONS: short so they respond instantly.
@export_range(0.0, 0.5, 0.01) var action_blend_time := 0.08
## Below this horizontal speed the character is considered idle.
@export var idle_threshold := 0.15
## Speed (m/s) at which the Walk clip plays at 1x; the clip is time-scaled to match velocity.
@export var walk_anim_reference_speed := 2.5
## Speed (m/s) at which the Run clip plays at 1x.
@export var run_anim_reference_speed := 5.5
## Scale animation playback to the actual velocity so feet don't slide.
@export var sync_animation_to_speed := true

@export_group("Actions")
## Agacharse con `crouch_input` (Ctrl). Moverse o repetir la tecla lo termina.
@export var crouch_action: PlayerAction = preload("res://scenes/player/actions/crouch.tres")
## Soltar la mochila con `drop_input`: el clip de coger al reves.
@export var drop_backpack_action: PlayerAction = preload("res://scenes/player/actions/drop_backpack.tres")

@export_group("Input")
@export var crouch_input: StringName = &"crouch"
@export var sit_input: StringName = &"sit"
@export var drop_input: StringName = &"drop"
## Toggles holding (temporary, for testing: key 1).
@export var hold_toggle_input: StringName = &"hold_toggle"

@export_group("Backpack")
## Show or hide the backpack mesh.
@export var show_backpack := true:
	set(value):
		show_backpack = value
		_apply_backpack_visibility()
## Name of the backpack MeshInstance3D inside the imported model.
@export var backpack_mesh_name := "Backpack"
## Scene spawned on the ground when dropping.
@export var backpack_pickup_scene: PackedScene = preload("res://scenes/props/backpack/backpack.tscn")
## Where the dropped bag appears, relative to the character (forward distance).
@export var drop_distance := 0.5
## Sound played when the bag leaves the hand (same clip as the pickup, pitched down a bit).
@export var drop_sound: AudioStream = preload("res://assets/audio/pickupbackpack.wav")
@export_range(-40.0, 6.0, 0.5) var drop_volume_db := -8.0
@export_range(0.5, 1.5, 0.01) var drop_pitch := 0.85

@export_group("Holding")
## Static pose layered on the arms while holding something (on top of walk/run/idle).
@export var hold_animation := "hold_pose"
## Bones the hold pose overrides; the rest keep the locomotion animation.
@export var hold_bones: PackedStringArray = ["shoulder.l", "arm.l", "hand.l", "shoulder.r", "arm.r", "hand.r"]
## Seconds to blend the hold pose in/out.
@export_range(0.0, 1.0, 0.05) var hold_blend_time := 0.2
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

var state := State.LOCOMOTION
## Ancla para objetos en brazos (nodo hijo CarrySlot; se crea si falta).
var carry_slot: CarrySlot

@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model.find_child("AnimationPlayer", true, false)

var _camera_rig: Node3D
var _skeleton: Skeleton3D
var _footsteps: FootstepAudio
var _xray: XrayVisibility
var _hold_modifier: HoldPoseModifier
var _hold_tween: Tween

var _current_anim := ""
var _speed := 0.0
var _clip_cache := {}  # nombre pedido -> nombre real del clip (sin distinguir mayusculas)
var _lock_reasons := {}  # StringName -> true

# Accion en curso (solo en State.ACTION).
var _action: PlayerAction
var _phase := Phase.START
var _apex_done := false


func _ready() -> void:
	_apply_model_scale()
	_apply_backpack_visibility()
	if Engine.is_editor_hint():
		return  # editor preview only: scale + backpack flag, no gameplay setup
	_camera_rig = get_tree().get_first_node_in_group("camera_rig")
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_footsteps = get_node_or_null("Footsteps") as FootstepAudio
	_xray = get_node_or_null("Xray") as XrayVisibility
	carry_slot = get_node_or_null("CarrySlot") as CarrySlot
	if carry_slot == null:
		carry_slot = CarrySlot.new()
		carry_slot.name = "CarrySlot"
		add_child(carry_slot)
	carry_slot.setup(_skeleton, _model, model_yaw_offset_deg)
	_prepare_model_materials(_model)
	if _xray:
		_xray.setup(self, _model)
	if _footsteps:
		_footsteps.setup(_skeleton)
	if _anim == null:
		push_warning("Player: no AnimationPlayer found under Model; animations disabled.")
		return
	idle_animation = _clip(idle_animation)
	walk_animation = _clip(walk_animation)
	run_animation = _clip(run_animation)
	sit_animation = _clip(sit_animation)
	# Safety net in case the import settings didn't mark the clips as looping.
	for anim_name in [idle_animation, walk_animation, run_animation]:
		if not _anim.has_animation(anim_name):
			push_warning("Player: animation '%s' not found in the model (available: %s)." % [anim_name, _anim.get_animation_list()])
			continue
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_warn_if_idle_is_rest_pose()
	_setup_hold_pose()
	_anim.animation_finished.connect(_on_animation_finished)
	_play(idle_animation)


## Nombre real del clip para `wanted`, tolerando mayusculas/espacios ("run" vs "Run").
func _clip(wanted: String) -> String:
	if _clip_cache.has(wanted):
		return _clip_cache[wanted]
	var found := wanted
	if not _anim.has_animation(wanted):
		for name in _anim.get_animation_list():
			if String(name).strip_edges().to_lower() == wanted.strip_edges().to_lower():
				found = String(name)
				break
	_clip_cache[wanted] = found
	return found


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


# ------------------------------------------------------------------ bucle principal

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif jump_enabled and state == State.LOCOMOTION and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	var running := false
	match state:
		State.LOCOMOTION:
			direction = _camera_relative_direction(input)
			running = _is_running()
		State.ACTION:
			if input != Vector2.ZERO and _action.cancel_on_move:
				stop_action()  # el movimiento se libera al terminar el clip de salida
		State.SITTING:
			if input != Vector2.ZERO:
				stand_up()
		State.LOCKED:
			pass
	var target_speed := run_speed if running else walk_speed

	# Weight without drift: speed is a scalar that ramps slowly, and the character always
	# moves along its facing. Direction changes become turns (arcs), never sideways sliding.
	if direction != Vector3.ZERO:
		_face_direction(direction, delta)
		_speed = move_toward(_speed, target_speed, acceleration * delta)
	else:
		_speed = move_toward(_speed, 0.0, deceleration * delta)

	var facing := facing_direction()
	velocity.x = facing.x * _speed
	velocity.z = facing.z * _speed
	move_and_slide()

	if state == State.ACTION:
		_update_action()
	elif state == State.LOCOMOTION:
		_update_locomotion_anim(Vector2(velocity.x, velocity.z).length(), running)

	if _footsteps:
		var locomotion := state == State.LOCOMOTION \
				and (_current_anim == walk_animation or _current_anim == run_animation)
		_footsteps.tick(delta, locomotion, _current_anim == run_animation)
	if _xray:
		_xray.tick()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed(sit_input):
		get_viewport().set_input_as_handled()
		if state == State.SITTING:
			stand_up()
		else:
			sit_down()
	elif event.is_action_pressed(crouch_input):
		get_viewport().set_input_as_handled()
		if is_crouching():
			stop_action()
		else:
			start_action(crouch_action)
	elif event.is_action_pressed(drop_input) and show_backpack and not is_carrying():
		get_viewport().set_input_as_handled()
		play_drop()
	elif event.is_action_pressed(hold_toggle_input):
		get_viewport().set_input_as_handled()
		holding = not holding


# ------------------------------------------------------------------ estados

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	var previous := state
	state = new_state
	state_changed.emit(previous, new_state)


## Estado al que se vuelve cuando termina una accion o el jugador se levanta.
func _rest_state() -> State:
	return State.LOCKED if not _lock_reasons.is_empty() else State.LOCOMOTION


## Bloqueo externo del movimiento (dialogos, cinematicas). Cada razon se libera con
## unlock(); el jugador solo se mueve cuando no queda ninguna. Si llega durante una
## accion, la accion termina normalmente y despues se queda quieto.
func lock(reason: StringName) -> void:
	_lock_reasons[reason] = true
	if state == State.LOCOMOTION:
		_set_state(State.LOCKED)


func unlock(reason: StringName) -> void:
	_lock_reasons.erase(reason)
	if _lock_reasons.is_empty() and state == State.LOCKED:
		_set_state(State.LOCOMOTION)


func is_locked() -> bool:
	return not _lock_reasons.is_empty()


func is_carrying() -> bool:
	return carry_slot != null and carry_slot.is_carrying()


func is_sitting() -> bool:
	return state == State.SITTING


## Agachado (accion `crouch`) y todavia no saliendo de ella.
func is_crouching() -> bool:
	return state == State.ACTION and _action.kind == &"crouch" and _phase != Phase.END


func is_action_playing() -> bool:
	return state == State.ACTION


## Accion en curso, o null.
func current_action() -> PlayerAction:
	return _action if state == State.ACTION else null


# ------------------------------------------------------------------ sentarse

## Sentarse en el suelo: funde al clip de sentado y bloquea el movimiento hasta levantarse.
func sit_down() -> bool:
	if _anim == null or state != State.LOCOMOTION:
		return false
	if not _anim.has_animation(sit_animation):
		push_warning("Player: no existe la animacion de sentarse '%s'." % sit_animation)
		return false
	_set_state(State.SITTING)
	_speed = 0.0
	_anim.get_animation(sit_animation).loop_mode = Animation.LOOP_LINEAR
	_anim.speed_scale = 1.0
	_anim.play(sit_animation, action_blend_time * 3.0)
	_current_anim = sit_animation
	return true


func stand_up() -> void:
	if state != State.SITTING:
		return
	_set_state(_rest_state())
	_play(idle_animation)


# ------------------------------------------------------------------ acciones

func can_start_action() -> bool:
	return _anim != null and state == State.LOCOMOTION


## Arranca `action`. Devuelve false si no se puede ahora o falta el clip de inicio
## (el llamante decide si hace la accion al instante o la ignora).
func start_action(action: PlayerAction) -> bool:
	if action == null or not can_start_action():
		return false
	var start := _clip(action.start_anim)
	if not _anim.has_animation(start):
		push_warning("Player: accion '%s' sin clip de inicio '%s' (hay: %s)." % [action.kind, action.start_anim, _anim.get_animation_list()])
		return false
	_action = action
	_apex_done = false
	_phase = Phase.START
	_set_state(State.ACTION)
	_anim.get_animation(start).loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	if action.reverse:
		_anim.play(start, action_blend_time, -action.speed, true)
	else:
		_anim.play(start, action_blend_time, action.speed)
	_current_anim = start
	action_started.emit(action.kind)
	return true


## Golpe (acciones con `strike_anim`): una pasada del clip y vuelta a la espera.
func strike() -> void:
	if state != State.ACTION or not _action.has_strike():
		return
	if _phase != Phase.IDLE and _phase != Phase.STRIKE:
		return
	var clip := _clip(_action.strike_anim)
	if not _anim.has_animation(clip):
		return
	_phase = Phase.STRIKE
	_anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_anim.play(clip, 0.05)
	_anim.seek(0.0)
	_current_anim = clip


## Sale de la accion por el clip de salida (o termina en seco si no lo hay).
func stop_action() -> void:
	if state != State.ACTION or _phase == Phase.END:
		return
	if _phase == Phase.START and not _apex_done:
		_fire_apex()
	_to_end()


## Soltar la mochila: el clip de coger al reves; la bolsa aparece en el suelo en el apex.
func play_drop() -> bool:
	if not show_backpack:
		return false
	return start_action(drop_backpack_action)


func _to_idle() -> void:
	var clip := _clip(_action.idle_anim)
	if not _anim.has_animation(clip):
		_to_end()
		return
	_phase = Phase.IDLE
	_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play(clip, 0.1)
	_current_anim = clip


func _to_end() -> void:
	var clip := _clip(_action.end_anim) if _action.has_end() else ""
	if clip.is_empty() or not _anim.has_animation(clip):
		_finish_action()
		return
	_phase = Phase.END
	_anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_anim.play(clip, 0.1)
	_current_anim = clip


## Apex durante el clip de inicio: se sondea la posicion del clip cada frame de fisica.
func _update_action() -> void:
	if _phase != Phase.START or _apex_done:
		return
	var f := _action.apex_fraction
	if not _action.reverse and f >= 1.0:
		return  # se emite al terminar el clip (_on_animation_finished)
	var start := _clip(_action.start_anim)
	if _anim.current_animation != start:
		return
	var t := _anim.current_animation_position / maxf(_anim.get_animation(start).length, 0.001)
	if (t <= f) if _action.reverse else (t >= f):
		_fire_apex()


func _fire_apex() -> void:
	_apex_done = true
	var kind := _action.kind
	match kind:
		&"pickup_backpack":
			show_backpack = true
		&"drop_backpack":
			show_backpack = false
			_spawn_dropped_backpack()
	action_apex.emit(kind)


func _on_animation_finished(anim_name: StringName) -> void:
	if state != State.ACTION:
		return
	var n := String(anim_name)
	match _phase:
		Phase.START:
			if n != _clip(_action.start_anim):
				return
			if not _apex_done:
				_fire_apex()
			if _action.has_idle():
				_to_idle()
			else:
				_to_end()
		Phase.STRIKE:
			if n == _clip(_action.strike_anim):
				_to_idle()
		Phase.END:
			if n == _clip(_action.end_anim):
				_finish_action()


func _finish_action() -> void:
	if state != State.ACTION:
		return
	if not _apex_done:
		_fire_apex()
	var kind := _action.kind
	_action = null
	_phase = Phase.START
	_current_anim = ""
	_set_state(_rest_state())
	_play(idle_animation)
	action_finished.emit(kind)


func _spawn_dropped_backpack() -> void:
	if backpack_pickup_scene == null:
		return
	var pickup := backpack_pickup_scene.instantiate() as Node3D
	get_parent().add_child(pickup)
	pickup.global_position = global_position + facing_direction() * drop_distance
	if drop_sound:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = drop_sound
		sfx.volume_db = drop_volume_db
		sfx.pitch_scale = drop_pitch * randf_range(0.95, 1.05)
		sfx.finished.connect(sfx.queue_free)
		add_child(sfx)
		sfx.play()
	backpack_dropped.emit(pickup)


# ------------------------------------------------------------------ holding

func _setup_hold_pose() -> void:
	hold_animation = _clip(hold_animation)
	if not _anim.has_animation(hold_animation):
		push_warning("Player: hold animation '%s' not found; holding pose disabled." % hold_animation)
		return
	if _skeleton == null:
		return
	_hold_modifier = HoldPoseModifier.new()
	_hold_modifier.name = "HoldPose"
	_hold_modifier.pose_animation = _anim.get_animation(hold_animation)
	_hold_modifier.bones = hold_bones
	_hold_modifier.influence = 1.0 if holding else 0.0
	_skeleton.add_child(_hold_modifier)


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


# ------------------------------------------------------------------ locomocion

func _is_running() -> bool:
	var sprint_held := Input.is_action_pressed("sprint")
	return (not sprint_held) if run_by_default else sprint_held


## Picks Idle / Walk / Run from the actual horizontal speed and syncs playback rate to it.
func _update_locomotion_anim(speed: float, running: bool) -> void:
	if _anim == null:
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
	if _anim == null or not _anim.has_animation(anim_name):
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
func facing_direction() -> Vector3:
	var yaw := _model.rotation.y - deg_to_rad(model_yaw_offset_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Yaw (mundo) del modelo: para orientar objetos soltados como el personaje.
func facing_yaw() -> float:
	return _model.global_rotation.y


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


# ------------------------------------------------------------------ modelo

## Copia por instancia de los materiales del GLB: nearest, sin sombreado opcional,
## stencil para la silueta x-ray y contorno (ver ModelMaterials).
func _prepare_model_materials(node: Node) -> void:
	var setup := ModelMaterials.new()
	setup.nearest = nearest_texture_filter
	setup.unshaded = unshaded_model
	setup.stencil = _xray != null and _xray.is_active()
	if outline_enabled:
		setup.with_outline(outline_color, outline_width_px)
	setup.apply(node)


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
