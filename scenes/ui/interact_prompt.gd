class_name InteractPrompt
extends Control
## Interaction hint: a white circle with a key letter (+ optional action text).
## By default it sits in the bottom-right corner of the screen (HUD); set
## `follow_world = true` to anchor it above a 3D point instead.
## Create one under a CanvasLayer inside the game scene, call show_at()/pop_out().
## Draws itself in code (no texture needed) and pops with a bouncy scale tween.

@export var key_text := "E"
## Text drawn to the left of the bubble ("Pick up"). Empty = bubble only.
@export var action_text := ""
## Circle radius in screen pixels (internal resolution).
@export_range(4.0, 64.0, 1.0) var radius := 7.0
@export var background_color := Color.WHITE
@export var text_color := Color(0.1, 0.1, 0.12)
@export var outline_color := Color(0.1, 0.1, 0.12)
@export_range(0.0, 4.0, 1.0) var outline_width := 1.0
@export_range(6, 48, 1) var font_size := 9
@export var action_text_color := Color.WHITE
@export var action_text_shadow := Color(0.0, 0.0, 0.0, 0.8)
## Gap between the action text and the bubble, in pixels.
@export var text_gap := 6.0

@export_group("Placement")
## false = fixed in the screen corner; true = above target_position in the world.
@export var follow_world := false
## Distance from the bottom-right corner (screen pixels).
@export var corner_margin := Vector2(14.0, 12.0)
## World-space height above the anchor point (follow_world only).
@export var world_offset_y := 0.5
## Gentle vertical bob in pixels.
@export var bob_pixels := 1.0
@export var bob_speed := 3.0
@export_range(0.05, 1.0, 0.05) var pop_duration := 0.25

var target_position := Vector3.ZERO
var _tween: Tween
var _t := 0.0


func _ready() -> void:
	_update_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale = Vector2.ZERO
	visible = false


func _update_size() -> void:
	var d := radius * 2.0 + outline_width * 2.0
	var w := d
	if not action_text.is_empty():
		w += _action_text_width() + text_gap
	size = Vector2(w, d)
	# Scale from the bubble's centre (right side) so the pop grows out of the key.
	pivot_offset = Vector2(size.x - d * 0.5, d * 0.5)


func _action_text_width() -> float:
	return ThemeDB.fallback_font.get_string_size(action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _process(delta: float) -> void:
	_t += delta
	var bob := sin(_t * bob_speed) * bob_pixels
	if follow_world:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var world := target_position + Vector3(0.0, world_offset_y, 0.0)
		if cam.is_position_behind(world):
			visible = false
			return
		var screen := cam.unproject_position(world)
		screen.y += bob
		position = (screen - size * 0.5).round()
	else:
		var view := get_viewport().get_visible_rect().size
		position = (view - size - corner_margin + Vector2(0.0, bob)).round()


func _draw() -> void:
	var d := radius * 2.0 + outline_width * 2.0
	var c := Vector2(size.x - d * 0.5, d * 0.5)
	var font := ThemeDB.fallback_font
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline_y := c.y + (ascent - descent) * 0.5

	if not action_text.is_empty():
		var tx := 0.0
		draw_string(font, Vector2(tx + 1.0, baseline_y + 1.0).round(), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, action_text_shadow)
		draw_string(font, Vector2(tx, baseline_y).round(), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, action_text_color)

	if outline_width > 0.0:
		draw_circle(c, radius + outline_width, outline_color)
	draw_circle(c, radius, background_color)
	var key_size := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(c.x - key_size.x * 0.5, baseline_y).round(), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Pop in. `world_position` is only used when follow_world is true.
func show_at(world_position: Vector3 = Vector3.ZERO) -> void:
	target_position = world_position
	_update_size()
	queue_redraw()
	visible = true
	_animate_scale(Vector2.ONE, Tween.TRANS_BACK, Tween.EASE_OUT)


func pop_out() -> void:
	_animate_scale(Vector2.ZERO, Tween.TRANS_BACK, Tween.EASE_IN)
	if _tween:
		_tween.finished.connect(func() -> void: visible = false, CONNECT_ONE_SHOT)


func _animate_scale(to: Vector2, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", to, pop_duration).set_trans(trans).set_ease(ease_type)
