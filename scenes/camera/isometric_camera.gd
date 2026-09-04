class_name IsometricCameraRig
extends Node3D
## Rotatable isometric camera rig.
## Hierarchy: CameraRig (yaw) -> Pivot (pitch) -> Camera3D (pushed back along +Z).
## The rig registers itself in the "camera_rig" group so the Player can read its yaw.

enum ProjectionMode { ORTHOGRAPHIC, PERSPECTIVE }
enum MouseRotateMode { OFF, DRAG, ALWAYS }
enum MouseDragButton { LEFT, RIGHT, MIDDLE }

@export_group("Target")
@export var target: Node3D
## How quickly the rig catches up with the target (higher = snappier). 0 = instant.
@export var follow_smoothing := 8.0
@export var target_offset := Vector3(0.0, 1.0, 0.0)

@export_group("View")
@export var projection_mode := ProjectionMode.ORTHOGRAPHIC:
	set(value):
		projection_mode = value
		_apply_camera_settings()
## Camera pitch in degrees. 35.264 is "true" isometric, 30 is the classic 2:1 pixel-art look.
@export_range(10.0, 89.0, 0.1) var pitch_deg := 35.264:
	set(value):
		pitch_deg = value
		_apply_camera_settings()
## How far the view is from the player. Orthographic: visible height in world units.
## Perspective: distance from the player to the camera. Scroll wheel changes this too.
@export_range(1.0, 100.0, 0.5) var zoom := 12.0:
	set(value):
		zoom = clampf(value, min_zoom, max_zoom) if is_node_ready() else value
		_apply_camera_settings()
## Orthographic only: MINIMUM distance the camera sits back. Doesn't change the view, only
## what gets clipped. The real offset grows automatically with zoom and the shallowest pitch
## so the ground at the bottom of the screen never ends up behind the camera.
@export_range(1.0, 200.0, 0.5) var ortho_camera_offset := 30.0:
	set(value):
		ortho_camera_offset = value
		_apply_camera_settings()
@export_range(10.0, 120.0, 0.5) var fov := 40.0:
	set(value):
		fov = value
		_apply_camera_settings()

@export_group("Rotation")
## Starting yaw in degrees. 45 gives the classic diagonal isometric angle.
@export var initial_yaw_deg := 45.0
## If true, Q/E rotate by `snap_angle_deg` steps; if false, they rotate continuously while held.
@export var snap_rotation := true
@export_range(15.0, 180.0, 5.0) var snap_angle_deg := 45.0
## Continuous rotation speed (degrees/sec) when snap_rotation is false.
@export var free_rotation_speed_deg := 120.0
## How quickly the yaw interpolates to its target. 0 = instant. Lower = heavier, floatier
## camera (3-4 feels weighty, 10+ feels 1:1 with the mouse).
@export var rotation_smoothing := 3.5

@export_group("Mouse")
## How the mouse rotates the view. Only the yaw changes; pitch is locked, so the view
## stays isometric. DRAG: hold `drag_rotate_button` and move. ALWAYS: the cursor is
## captured and any horizontal mouse movement orbits the camera.
@export var mouse_rotate_mode: MouseRotateMode = MouseRotateMode.ALWAYS:
	set(value):
		mouse_rotate_mode = value
		_apply_mouse_mode()
@export var drag_rotate_button: MouseDragButton = MouseDragButton.RIGHT
## Degrees of yaw per pixel of mouse movement.
@export_range(0.05, 2.0, 0.05) var mouse_sensitivity := 0.25
## Invert the horizontal mouse direction.
@export var mouse_invert_x := false
## Let vertical mouse movement tilt the view. The tilt is clamped to ±pitch_range_deg
## around pitch_deg, so it stays "almost isometric" instead of a free orbit camera.
@export var mouse_pitch_enabled := true
## Max tilt above/below pitch_deg, in degrees. 0 = locked to isometric.
@export_range(0.0, 45.0, 0.5) var pitch_range_deg := 16.0
## Degrees of pitch per pixel of vertical mouse movement.
@export_range(0.01, 1.0, 0.01) var mouse_pitch_sensitivity := 0.08
@export var mouse_invert_y := true
## Shift the camera towards the point on the ground the cursor is over (Hades/Diablo style).
@export var mouse_lean_enabled := false
## 0 = no lean, 1 = the camera centres on the cursor point (clamped by max distance).
@export_range(0.0, 1.0, 0.05) var mouse_lean_strength := 0.35
## Maximum world-space distance the camera can lean away from the target.
@export_range(0.0, 20.0, 0.25) var mouse_lean_max_distance := 3.0
## How quickly the lean follows the cursor (higher = snappier). 0 = instant.
@export var mouse_lean_smoothing := 5.0

@export_group("Zoom")
@export var allow_scroll_zoom := true
@export var zoom_step := 1.0
@export var min_zoom := 4.0
@export var max_zoom := 40.0

## Poner un AudioListener3D en el rig: los sonidos 3D se atenuan por distancia al
## JUGADOR (el rig lo sigue), no a la camara, que esta a 30 m. El paneo estereo sigue el yaw.
@export var use_audio_listener := true

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

var _target_yaw := 0.0
var _target_pitch := 0.0
var _pitch := 0.0
var _dragging := false
var _lean := Vector3.ZERO
var _shake_time := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0


## Sacude la camara: `strength` en metros de desplazamiento maximo, decae hasta 0 en
## `duration` segundos. Se aplica con h_offset/v_offset, sin tocar el seguimiento.
func shake(strength := 0.25, duration := 0.4) -> void:
	_shake_strength = maxf(strength, _shake_strength * (_shake_time / maxf(_shake_duration, 0.001)))
	_shake_duration = duration
	_shake_time = duration


func _ready() -> void:
	add_to_group("camera_rig")
	if use_audio_listener and not Engine.is_editor_hint():
		var listener := AudioListener3D.new()
		listener.name = "Listener"
		add_child(listener)
		listener.make_current()
	_target_yaw = deg_to_rad(initial_yaw_deg)
	rotation.y = _target_yaw
	_target_pitch = pitch_deg
	_pitch = pitch_deg
	_apply_camera_settings()
	_apply_mouse_mode()
	if target:
		global_position = target.global_position + target_offset


func _process(delta: float) -> void:
	_handle_rotation_input(delta)

	if rotation_smoothing <= 0.0:
		rotation.y = _target_yaw
		_pitch = _target_pitch
	else:
		var k := 1.0 - exp(-rotation_smoothing * delta)
		rotation.y = lerp_angle(rotation.y, _target_yaw, k)
		_pitch = lerpf(_pitch, _target_pitch, k)
	_pivot.rotation.x = -deg_to_rad(_pitch)

	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var k := _shake_time / maxf(_shake_duration, 0.001)
		var amp := _shake_strength * k * k
		_camera.h_offset = randf_range(-amp, amp)
		_camera.v_offset = randf_range(-amp, amp)
		if _shake_time == 0.0:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0

	_update_mouse_lean(delta)

	if target:
		var desired := target.global_position + target_offset + _lean
		if follow_smoothing <= 0.0:
			global_position = desired
		else:
			global_position = global_position.lerp(desired, 1.0 - exp(-follow_smoothing * delta))


func _unhandled_input(event: InputEvent) -> void:
	# Esc toggles the captured cursor in ALWAYS mode (handy while testing / for menus).
	if mouse_rotate_mode == MouseRotateMode.ALWAYS and event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if allow_scroll_zoom and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-zoom_step)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(zoom_step)
		if mouse_rotate_mode == MouseRotateMode.DRAG and mb.button_index == _drag_button_index():
			_dragging = mb.pressed
	elif event is InputEventMouseMotion:
		var rotating := mouse_rotate_mode == MouseRotateMode.ALWAYS \
				or (mouse_rotate_mode == MouseRotateMode.DRAG and _dragging)
		if rotating:
			var rel := (event as InputEventMouseMotion).relative
			var dx := rel.x * (-1.0 if mouse_invert_x else 1.0)
			_target_yaw -= deg_to_rad(dx * mouse_sensitivity)
			if mouse_pitch_enabled and pitch_range_deg > 0.0:
				var dy := rel.y * (-1.0 if mouse_invert_y else 1.0)
				# Mouse up (negative dy) looks more from above -> steeper pitch.
				_target_pitch = clampf(_target_pitch - dy * mouse_pitch_sensitivity,
						pitch_deg - pitch_range_deg, pitch_deg + pitch_range_deg)


func _drag_button_index() -> MouseButton:
	match drag_rotate_button:
		MouseDragButton.LEFT:
			return MOUSE_BUTTON_LEFT
		MouseDragButton.MIDDLE:
			return MOUSE_BUTTON_MIDDLE
	return MOUSE_BUTTON_RIGHT


func _apply_mouse_mode() -> void:
	if not is_inside_tree():
		return
	_dragging = false
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if mouse_rotate_mode == MouseRotateMode.ALWAYS
			else Input.MOUSE_MODE_VISIBLE)


## Projects the cursor onto the horizontal plane at the target's height and leans towards it.
## Only the XZ offset changes, so pitch/yaw (the isometric look) are untouched.
func _update_mouse_lean(delta: float) -> void:
	var desired := Vector3.ZERO
	if mouse_lean_enabled and target and mouse_lean_strength > 0.0:
		var viewport := get_viewport()
		var mouse := get_tree().root.get_mouse_position()
		var in_view := Rect2(Vector2.ZERO, viewport.get_visible_rect().size).has_point(mouse)
		if in_view:
			var origin := _camera.project_ray_origin(mouse)
			var dir := _camera.project_ray_normal(mouse)
			var plane := Plane(Vector3.UP, target.global_position.y + target_offset.y)
			var hit = plane.intersects_ray(origin, dir)
			if hit != null:
				var offset: Vector3 = (hit as Vector3) - (target.global_position + target_offset)
				offset.y = 0.0
				desired = offset.limit_length(mouse_lean_max_distance) * mouse_lean_strength
	if mouse_lean_smoothing <= 0.0:
		_lean = desired
	else:
		_lean = _lean.lerp(desired, 1.0 - exp(-mouse_lean_smoothing * delta))


func _handle_rotation_input(delta: float) -> void:
	if snap_rotation:
		if Input.is_action_just_pressed("camera_rotate_left"):
			_target_yaw += deg_to_rad(snap_angle_deg)
		if Input.is_action_just_pressed("camera_rotate_right"):
			_target_yaw -= deg_to_rad(snap_angle_deg)
	else:
		var axis := Input.get_axis("camera_rotate_right", "camera_rotate_left")
		_target_yaw += deg_to_rad(free_rotation_speed_deg) * axis * delta


func _zoom(amount: float) -> void:
	zoom = zoom + amount


func _apply_camera_settings() -> void:
	if not is_node_ready():
		return
	# Re-centre the tilt band on the new rest pitch.
	_target_pitch = clampf(_target_pitch, pitch_deg - pitch_range_deg, pitch_deg + pitch_range_deg)
	_pivot.rotation.x = -deg_to_rad(_pitch if _pitch > 0.0 else pitch_deg)
	if projection_mode == ProjectionMode.ORTHOGRAPHIC:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = zoom
		# Ground seen at the bottom edge of the screen sits zoom/2 * cot(pitch) closer than
		# the target; at the shallowest pitch of the tilt band that can exceed a fixed offset
		# and get clipped (it would be behind the camera). Push back as far as needed.
		var shallowest := pitch_deg - (pitch_range_deg if mouse_pitch_enabled else 0.0)
		var needed := zoom * 0.5 / tan(deg_to_rad(maxf(shallowest, 5.0))) + 10.0
		var offset := maxf(ortho_camera_offset, needed)
		_camera.position = Vector3(0.0, 0.0, offset)
		# Keep the far plane covering the ground at the TOP edge (offset + the same amount).
		_camera.far = maxf(_camera.far, offset + needed + 50.0)
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov
		_camera.position = Vector3(0.0, 0.0, zoom)
