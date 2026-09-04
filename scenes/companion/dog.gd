class_name Dog
extends CharacterBody3D
## AI companion that behaves like a dog:
##  - FOLLOW: keeps up with the player (walks, runs if the player runs or is far away)
##    and stops at a respectful distance.
##  - HANG_AROUND: player nearby -> idles, wanders to random points around the player and
##    sometimes sniffs the ground (head overlay on top of idle/walk).
##  - GO_SIT / SIT: player crouches -> comes close, plays Sit_start and loops Sit;
##    when the player stands up, Sit_start plays backwards (sit_end) and it gets up.
## Tail overlays (OverlayAnimModifier): happy when close to the player or sitting with
## them, sad when left behind for a while.

enum State { FOLLOW, HANG_AROUND, GO_SIT, SIT, GO_STAY, STAY }

@export_group("Target")
@export var target: Player

@export_group("Movement")
@export var walk_speed := 2.0
@export var run_speed := 4.2
@export var acceleration := 10.0
@export var deceleration := 12.0
## How quickly the dog turns towards where it wants to go (higher = snappier).
@export var turn_speed := 7.0
@export var gravity_scale := 1.0
## Degrees the model is rotated relative to "forward is -Z".
@export var model_yaw_offset_deg := 0.0

@export_group("Follow")
## Beyond this distance from the player the dog starts following.
@export var follow_distance := 9.0
## The dog stops approaching once this close (hysteresis with follow_distance).
@export var stop_distance := 3.2
## Runs instead of walks when farther than this.
@export var catchup_distance := 14.0
## Player speed above which the dog also runs.
@export var player_run_speed_threshold := 3.0
## Seconds the dog takes to notice the player's speed changing: it keeps running for a
## moment after the player stops instead of mirroring them instantly.
@export_range(0.0, 3.0, 0.1) var speed_reaction_time := 0.8
## Random pause (x..y s) before the dog reacts to the player walking away.
@export var reaction_time_range := Vector2(0.3, 1.0)

@export_group("Fire")
## The dog never goes closer than this to a campfire (destinations are pushed out of
## this radius and the steering is repelled by it).
@export var fire_avoid_radius := 2.2
@export var fire_avoid_strength := 1.6

@export_group("Hang around")
## Radius around the player for wander points.
@export var wander_radius := 6.0
## Seconds of idling between mini-behaviours (random in [x, y]).
@export var idle_time_range := Vector2(2.0, 5.0)
## Chance that the next mini-behaviour is sniffing instead of wandering.
@export_range(0.0, 1.0, 0.05) var sniff_chance := 0.35
## Seconds a sniff lasts (random in [x, y]).
@export var sniff_time_range := Vector2(2.0, 4.0)

@export_group("Sit")
## The dog sits once this close to the crouching player.
@export var sit_distance := 1.6
## After the player crouches, the dog keeps hanging around this long (random x..y s)
## before deciding to come and sit next to them.
@export var sit_delay_range := Vector2(1.5, 6.0)

@export_group("Mood (tail)")
## Within this distance of the player the tail wags happily.
@export var happy_distance := 4.0
## Farther than this counts as "left behind"...
@export var sad_distance := 20.0
## ...after this many seconds of it, the tail droops.
@export var sad_delay := 3.0

@export_group("Animations")
@export var idle_animation := "Idle"
@export var walk_animation := "Walk"
@export var run_animation := "Run"
@export var sit_animation := "Sit"
@export var sit_start_animation := "Sit_start"
@export var sniff_animation := "Sniffing"
@export var tail_happy_animation := "Tail_happy"
@export var tail_sad_animation := "Tail_sad"
@export var blend_time := 0.25
@export var sync_animation_to_speed := true
## Ground speed (m/s) the Walk / Run clips were authored for.
@export var walk_anim_reference_speed := 2.0
@export var run_anim_reference_speed := 3.2
@export var idle_threshold := 0.15
## Bones the tail overlay drives.
@export var tail_bones: PackedStringArray = ["tail1", "tail2", "tail3"]
## Bones the sniff overlay drives.
@export var head_bones: PackedStringArray = ["Neck", "face", "nose", "ear1.l", "ear2.l", "ear1.r", "ear2.r"]

@export_group("Bark")
@export var bark_enabled := true
@export var bark_stream: AudioStream = preload("res://assets/audio/dog_bark.mp3")
@export_range(-40.0, 6.0, 0.5) var bark_volume_db := -12.0
@export_range(1.0, 2.0, 0.01) var bark_random_pitch := 1.15
@export_range(0.0, 12.0, 0.5) var bark_random_volume_db := 3.0
## Minimum seconds between barks, whatever the trigger (keeps a single clip from tiring).
@export var bark_cooldown := 5.0
## Chance of a single bark when it finishes sniffing something.
@export_range(0.0, 1.0, 0.05) var sniff_bark_chance := 0.15
## Barks at a campfire lighting up if within this distance of it.
@export var bark_fire_distance := 12.0
## Seconds the dog stares at the fire (sniff pose) before barking at it.
@export var fire_react_time := 1.0

@export_group("Rendering")
@export var nearest_texture_filter := true
## 1-px dark outline like the player's (same shader), for readability.
@export var outline_enabled := true
@export var outline_color := Color(0.03, 0.02, 0.02)
@export_range(0.5, 4.0, 0.5) var outline_width_px := 1.0

var state := State.FOLLOW

var _model: Node3D
var _anim: AnimationPlayer
var _tail_overlay: OverlayAnimModifier
var _head_overlay: OverlayAnimModifier
var _rng := RandomNumberGenerator.new()

var _speed := 0.0
var _destination := Vector3.ZERO
var _has_destination := false
var _current_anim := ""
var _sit_transition := false  # Sit_start (fwd or reverse) in progress: movement locked
var _behaviour_timer := 0.0  # HANG_AROUND: time left idling / sniffing
var _sniffing := false
var _sad_timer := 0.0
var _stuck_timer := 0.0
var _avoid_offset := Vector3.ZERO  # sideways push while stuck against an obstacle
var _perceived_player_speed := 0.0  # player speed as the dog "notices" it (lagged)
var _react_timer := -1.0  # pause before chasing a leaving player (-1 = unset)
var _sit_wait := -1.0  # time left hanging around before coming to sit (-1 = unset)
var _footsteps: FootstepAudio  # nodo hijo "Footsteps" (opcional)
var _bark_player: AudioStreamPlayer3D
var _bark_ready_at := 0.0  # Time (s) the cooldown ends
var _long_chase := false  # this FOLLOW involved a real catch-up run (greet bark on arrival)
var _fire_focus: Node3D  # campfire being stared at (fire reaction in progress)
var _fire_react_timer := 0.0
var _stay_pos := Vector3.ZERO  # STAY: spot where the dog sits and stays for good
var _gosit_moved := false  # GO_SIT: ya ha ido hacia el jugador al menos una vez


## Send the dog to `pos` and make it sit there indefinitely (it stops following the
## player until release() is called). Used e.g. to leave the dog with an NPC.
func stay_at(pos: Vector3) -> void:
	_stay_pos = _away_from_fires(pos)  # nunca sentarse dentro del radio del fuego
	if state == State.SIT or _sit_transition:
		_begin_stand_up()  # gets up first; _on_stood_up re-routes to GO_STAY
	_change_state(State.GO_STAY)
	_set_destination(_stay_pos)


func release() -> void:
	if state == State.STAY and not _sit_transition:
		_stay_pos = Vector3.ZERO
		_begin_stand_up()
	elif state == State.GO_STAY:
		_stay_pos = Vector3.ZERO
		_change_state(State.FOLLOW)


func is_staying() -> bool:
	return state == State.STAY or state == State.GO_STAY


func _ready() -> void:
	_model = get_node_or_null("Model")
	if _model == null:
		push_warning("Dog: needs a child named 'Model' (the dog.glb instance).")
		return
	_anim = _model.find_child("AnimationPlayer", true, false)
	_rng.randomize()
	if _anim:
		for prop in ["idle_animation", "walk_animation", "run_animation", "sit_animation",
				"sit_start_animation", "sniff_animation", "tail_happy_animation", "tail_sad_animation"]:
			set(prop, _resolve_animation_name(get(prop)))
		for anim_name in [idle_animation, walk_animation, run_animation, sit_animation]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_play(idle_animation)
	_setup_overlays()
	_prepare_materials(_model)
	_footsteps = get_node_or_null("Footsteps") as FootstepAudio
	if _footsteps:
		_footsteps.setup(_model.find_child("Skeleton3D", true, false) as Skeleton3D)
	_setup_bark()


## Returns the actual clip name matching `wanted` ignoring case, or `wanted` if none.
func _resolve_animation_name(wanted: String) -> String:
	if _anim.has_animation(wanted):
		return wanted
	for name in _anim.get_animation_list():
		if String(name).strip_edges().to_lower() == wanted.strip_edges().to_lower():
			return String(name)
	push_warning("Dog: animation '%s' not found (available: %s)." % [wanted, _anim.get_animation_list()])
	return wanted


func _setup_overlays() -> void:
	var skeleton: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_warning("Dog: no Skeleton3D found; tail/sniff overlays disabled.")
		return
	_tail_overlay = OverlayAnimModifier.new()
	_tail_overlay.name = "TailOverlay"
	_tail_overlay.bones = tail_bones
	skeleton.add_child(_tail_overlay)
	_head_overlay = OverlayAnimModifier.new()
	_head_overlay.name = "SniffOverlay"
	_head_overlay.bones = head_bones
	skeleton.add_child(_head_overlay)


## Nearest filtering + contorno en los materiales importados (ver ModelMaterials).
func _prepare_materials(node: Node) -> void:
	var setup := ModelMaterials.new()
	setup.nearest = nearest_texture_filter
	if outline_enabled:
		setup.with_outline(outline_color, outline_width_px)
	setup.apply(node)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale * delta
	if target == null or _anim == null:
		move_and_slide()
		return

	var to_player := target.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# The dog notices speed changes late: fast to spot a sprint starting, slow to accept
	# that the player stopped, so it keeps running a beat longer.
	var actual_speed := Vector2(target.velocity.x, target.velocity.z).length()
	var tau := speed_reaction_time * (0.3 if actual_speed > _perceived_player_speed else 1.0)
	_perceived_player_speed = lerpf(_perceived_player_speed, actual_speed,
			1.0 - exp(-delta / maxf(tau, 0.01)))

	if is_instance_valid(_fire_focus):
		_update_fire_reaction(delta)
	elif not _sit_transition:
		_update_state(dist, delta)
	_steer(delta)
	move_and_slide()
	_clamp_out_of_fires()

	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not _sit_transition and state != State.SIT and state != State.STAY:
		_update_locomotion_anim(ground_speed)
	_update_mood(dist, delta)
	_update_stuck(ground_speed, delta)
	if _footsteps:
		var locomotion := _current_anim == walk_animation or _current_anim == run_animation
		_footsteps.tick(delta, locomotion, _current_anim == run_animation)


# ------------------------------------------------------------------ state machine

## El jugador esta "en reposo bajo": agachado o sentado en el suelo -> el perro viene a sentarse.
func _player_resting() -> bool:
	return target.is_crouching() or (target.has_method("is_sitting") and target.is_sitting())


func _update_state(dist: float, delta: float) -> void:
	match state:
		State.FOLLOW:
			_set_destination(target.global_position)
			if dist > catchup_distance:
				_long_chase = true
			if dist <= stop_distance:
				_change_state(State.HANG_AROUND)
		State.HANG_AROUND:
			# Crouching player: keep living for a random while, THEN come to sit.
			if _player_resting():
				if _sit_wait < 0.0:
					_sit_wait = _rng.randf_range(sit_delay_range.x, sit_delay_range.y)
				_sit_wait -= delta
				if _sit_wait <= 0.0:
					_change_state(State.GO_SIT)
					return
			else:
				_sit_wait = -1.0
			# Player leaving: a short random pause before reacting, not an instant mirror.
			if dist > follow_distance:
				if _react_timer < 0.0:
					_react_timer = _rng.randf_range(reaction_time_range.x, reaction_time_range.y)
				_react_timer -= delta
				if _react_timer <= 0.0:
					_change_state(State.FOLLOW)
					return
			else:
				_react_timer = -1.0
			_update_hang_around(delta)
		State.GO_SIT:
			if not _player_resting():
				_change_state(State.HANG_AROUND)
			elif dist <= sit_distance or (_gosit_moved and not _has_destination \
					and dist <= sit_distance + fire_avoid_radius):
				_begin_sit()  # (o lo mas cerca que el fuego le deja llegar)
			else:
				_set_destination(target.global_position)
				_gosit_moved = true
		State.SIT:
			if not _player_resting():
				_begin_stand_up()
		State.GO_STAY:
			_set_destination(_stay_pos)
			var to_spot := _stay_pos - global_position
			to_spot.y = 0.0
			if to_spot.length() <= 0.45:
				_begin_sit(State.STAY)
		State.STAY:
			pass  # sits there for good until release()


func _change_state(new_state: State) -> void:
	if state == new_state:
		return
	# Greeting: it just caught up after a real run -> a bark as it arrives.
	if state == State.FOLLOW and new_state == State.HANG_AROUND and _long_chase:
		_bark(2 if _rng.randf() < 0.4 else 1)
	_long_chase = false
	state = new_state
	_has_destination = false
	_behaviour_timer = 0.0
	_gosit_moved = false
	_react_timer = -1.0
	_sit_wait = -1.0
	_stop_sniffing()


## Idle a while, then either sniff around or wander to a point near the player.
func _update_hang_around(delta: float) -> void:
	if _has_destination:
		return  # walking to a wander point; _steer clears it on arrival
	_behaviour_timer -= delta
	if _behaviour_timer > 0.0:
		return
	if _sniffing:
		_stop_sniffing()
		if _rng.randf() < sniff_bark_chance:
			_bark()  # found something!
		_behaviour_timer = _rng.randf_range(idle_time_range.x, idle_time_range.y)
	elif _rng.randf() < sniff_chance:
		_sniffing = true
		if _head_overlay and _anim.has_animation(sniff_animation):
			_head_overlay.play(_anim.get_animation(sniff_animation))
		_behaviour_timer = _rng.randf_range(sniff_time_range.x, sniff_time_range.y)
	else:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(wander_radius * 0.3, wander_radius)
		_set_destination(target.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius)
		_behaviour_timer = _rng.randf_range(idle_time_range.x, idle_time_range.y)


func _stop_sniffing() -> void:
	_sniffing = false
	if _head_overlay:
		_head_overlay.stop()


# ------------------------------------------------------------------ sitting

func _begin_sit(final_state := State.SIT) -> void:
	state = final_state
	_has_destination = false
	_speed = 0.0
	_stop_sniffing()
	if not _anim.has_animation(sit_start_animation):
		_play(sit_animation)
		return
	_sit_transition = true
	_anim.get_animation(sit_start_animation).loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(sit_start_animation, blend_time)
	_current_anim = sit_start_animation
	_anim.animation_finished.connect(_on_sat_down, CONNECT_ONE_SHOT)


func _on_sat_down(_name: StringName) -> void:
	_sit_transition = false
	_play(sit_animation)


func _begin_stand_up() -> void:
	if not _anim.has_animation(sit_start_animation):
		_change_state(State.HANG_AROUND)
		_play(idle_animation)
		return
	_sit_transition = true
	_anim.get_animation(sit_start_animation).loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = 1.0
	_anim.play(sit_start_animation, blend_time, -1.0, true)  # sit_end = Sit_start al reves
	_current_anim = sit_start_animation
	_anim.animation_finished.connect(_on_stood_up, CONNECT_ONE_SHOT)


func _on_stood_up(_name: StringName) -> void:
	_sit_transition = false
	if _stay_pos != Vector3.ZERO:
		_change_state(State.GO_STAY)  # se levanto para ir a su sitio
		_set_destination(_stay_pos)
	elif state == State.STAY or state == State.GO_STAY:
		_change_state(State.FOLLOW)  # liberado
	else:
		_change_state(State.HANG_AROUND)
	_play(idle_animation)


# ------------------------------------------------------------------ movement

func _set_destination(pos: Vector3) -> void:
	_destination = _away_from_fires(Vector3(pos.x, global_position.y, pos.z))
	_has_destination = true


## Campfires in the scene (cached, refreshed now and then).
var _fires: Array = []
var _fires_timer := 0.0

func _campfires() -> Array:
	_fires_timer -= get_physics_process_delta_time()
	if _fires_timer <= 0.0:
		_fires_timer = 2.0
		_fires = get_tree().get_nodes_in_group("campfire")
	return _fires


## Moves `pos` radially out of any campfire's keep-out radius.
func _away_from_fires(pos: Vector3) -> Vector3:
	for fire in _campfires():
		var fp: Vector3 = fire.global_position
		var d := Vector2(pos.x - fp.x, pos.z - fp.z)
		if d.length() < fire_avoid_radius:
			var dir := d.normalized() if d.length() > 0.01 else Vector2(1.0, 0.0)
			pos.x = fp.x + dir.x * fire_avoid_radius * 1.05
			pos.z = fp.z + dir.y * fire_avoid_radius * 1.05
	return pos


## Hard limit: whatever the steering did, never end a frame inside a fire's radius.
func _clamp_out_of_fires() -> void:
	for fire in _campfires():
		var fp: Vector3 = fire.global_position
		var d := Vector2(global_position.x - fp.x, global_position.z - fp.z)
		if d.length() < fire_avoid_radius:
			var dir := d.normalized() if d.length() > 0.01 else Vector2(1.0, 0.0)
			global_position.x = fp.x + dir.x * fire_avoid_radius
			global_position.z = fp.z + dir.y * fire_avoid_radius


## Repulsion vector (XZ) from nearby campfires, strongest at the keep-out radius.
func _fire_repulsion() -> Vector3:
	var push := Vector3.ZERO
	for fire in _campfires():
		var fp: Vector3 = fire.global_position
		var d := Vector3(global_position.x - fp.x, 0.0, global_position.z - fp.z)
		var reach := fire_avoid_radius + 1.0
		if d.length() < reach and d.length() > 0.01:
			push += d.normalized() * (1.0 - d.length() / reach) * fire_avoid_strength
	return push


## Same weighty movement as the player: speed is a scalar and the dog always moves along
## its facing, so direction changes become arcs.
func _steer(delta: float) -> void:
	var target_speed := 0.0
	if _has_destination and not _sit_transition and state != State.SIT and state != State.STAY:
		var to_dest := _destination + _avoid_offset - global_position
		to_dest.y = 0.0
		var arrive := 0.3 if state == State.GO_STAY else stop_distance if state == State.FOLLOW \
				else (sit_distance if state == State.GO_SIT else 0.4)
		if to_dest.length() <= arrive:
			_has_destination = false
		else:
			var dir := (to_dest.normalized() + _fire_repulsion()).normalized()
			_face_direction(dir, delta)
			target_speed = run_speed if _should_run() else walk_speed
			# Slow into the stop so the dog doesn't overshoot and spin.
			target_speed = minf(target_speed, (to_dest.length() - arrive) * 2.0 + 0.5)
	if not _has_destination and (state == State.FOLLOW or state == State.HANG_AROUND):
		var push := _fire_repulsion()
		if push.length() > 0.55:  # parado casi encima del fuego: apartarse
			_set_destination(global_position + push.normalized() * 1.5)
	if target_speed > _speed:
		_speed = move_toward(_speed, target_speed, acceleration * delta)
	else:
		_speed = move_toward(_speed, target_speed, deceleration * delta)
	var facing := _facing_direction()
	velocity.x = facing.x * _speed
	velocity.z = facing.z * _speed


func _should_run() -> bool:
	if state != State.FOLLOW:
		return false
	var dist := (target.global_position - global_position).length()
	return dist > catchup_distance or _perceived_player_speed > player_run_speed_threshold


func _facing_direction() -> Vector3:
	var yaw := _model.rotation.y - deg_to_rad(model_yaw_offset_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z) + deg_to_rad(model_yaw_offset_deg)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


## If blocked against something (tree trunk, the campfire) while trying to move, push the
## goal sideways so the dog slides around. The offset lives outside _destination because
## FOLLOW rewrites the destination every frame; it decays once the dog moves freely again.
func _update_stuck(ground_speed: float, delta: float) -> void:
	if _has_destination and _speed > 0.5 and ground_speed < 0.3:
		_stuck_timer += delta
		if _stuck_timer > 0.5:
			_stuck_timer = 0.0
			var side := _facing_direction().cross(Vector3.UP)
			_avoid_offset += side * (2.5 if _rng.randf() < 0.5 else -2.5)
			_avoid_offset = _avoid_offset.limit_length(5.0)
	else:
		_stuck_timer = 0.0
		_avoid_offset = _avoid_offset.move_toward(Vector3.ZERO, delta * 2.0)


# ------------------------------------------------------------------ animation

func _update_locomotion_anim(speed: float) -> void:
	var anim_name := idle_animation
	var reference_speed := 1.0
	if speed > idle_threshold:
		var use_run := _should_run() and speed > walk_speed
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
	if anim_name == _current_anim and _anim.is_playing():
		return
	_anim.play(anim_name, blend_time)
	_current_anim = anim_name


# ------------------------------------------------------------------ bark

func _setup_bark() -> void:
	if not bark_enabled or bark_stream == null:
		return
	var randomizer := AudioStreamRandomizer.new()
	randomizer.add_stream(0, bark_stream)
	randomizer.random_pitch = bark_random_pitch
	randomizer.random_volume_offset_db = bark_random_volume_db
	_bark_player = AudioStreamPlayer3D.new()
	_bark_player.name = "Bark"
	_bark_player.stream = randomizer
	_bark_player.volume_db = bark_volume_db
	_bark_player.max_polyphony = 2
	add_child(_bark_player)
	_connect_campfires.call_deferred()


func _connect_campfires() -> void:
	for fire in get_tree().get_nodes_in_group("campfire"):
		if fire.has_signal("lit_changed"):
			fire.lit_changed.connect(_on_campfire_lit.bind(fire))


func _on_campfire_lit(is_lit: bool, fire: Node3D) -> void:
	if not is_lit or global_position.distance_to(fire.global_position) >= bark_fire_distance:
		return
	if state == State.SIT or _sit_transition:
		_bark()  # sentado: ladra sin levantarse
		return
	# Reaccion: parar, mirar al fuego, olfatear un momento y entonces ladrar.
	_fire_focus = fire
	_fire_react_timer = fire_react_time
	_has_destination = false
	_stop_sniffing()
	if _head_overlay and _anim.has_animation(sniff_animation):
		_head_overlay.play(_anim.get_animation(sniff_animation))


## Stares at the lit campfire holding the sniff pose, then barks and lets go.
func _update_fire_reaction(delta: float) -> void:
	var to_fire := _fire_focus.global_position - global_position
	to_fire.y = 0.0
	if to_fire.length() > 0.01:
		_face_direction(to_fire.normalized(), delta)
	_fire_react_timer -= delta
	if _fire_react_timer <= 0.0:
		_bark()
		if _head_overlay:
			_head_overlay.stop()
		_fire_focus = null


## One bark (or a quick double bark), respecting a global cooldown so triggers never spam.
func _bark(count := 1) -> void:
	if _bark_player == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _bark_ready_at:
		return
	_bark_ready_at = now + bark_cooldown
	_bark_player.play()
	for i in count - 1:
		get_tree().create_timer(0.35 * (i + 1)).timeout.connect(_bark_player.play)


# ------------------------------------------------------------------ mood

## Tail: happy near the player (or sitting with them), sad when left behind for a while.
func _update_mood(dist: float, delta: float) -> void:
	if _tail_overlay == null:
		return
	var was_sad := _sad_timer > sad_delay
	_sad_timer = _sad_timer + delta if dist > sad_distance else 0.0
	if dist <= happy_distance or state == State.SIT or state == State.STAY:
		if _anim.has_animation(tail_happy_animation):
			_tail_overlay.play(_anim.get_animation(tail_happy_animation))
	elif _sad_timer > sad_delay:
		if not was_sad:
			_bark(2)  # left behind: call for attention before chasing
		if _anim.has_animation(tail_sad_animation):
			_tail_overlay.play(_anim.get_animation(tail_sad_animation))
	else:
		_tail_overlay.stop()
