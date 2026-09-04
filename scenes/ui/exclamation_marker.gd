class_name ExclamationMarker
extends Control
## Marcador "!" flotando sobre la cabeza de un NPC con algo nuevo que decir. Se dibuja
## en codigo (colores de la paleta), bota suavemente y aparece/desaparece con un pop.
## Vive en RetroRenderer.hud_layer; `anchor` (mundo) + `camera` lo posicionan cada frame.

@export var text := "!"
@export_range(6, 48, 1) var font_size := 20
@export var fill_color := Color("c0c188")
@export var outline_color := Color("1c1009")
@export var bob_pixels := 2.0
@export var bob_speed := 3.0
## Separacion vertical sobre el ancla (pixeles).
@export var lift := 6.0

var anchor := Vector3.ZERO
var camera: Camera3D
var _t := 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := ThemeDB.fallback_font
	var s := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	size = s + Vector2(6, 6)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2.ZERO
	visible = false


var _shown := false  # estado objetivo: evita reiniciar el tween en cada llamada


func show_marker() -> void:
	if _shown:
		return
	_shown = true
	visible = true
	_pop(Vector2.ONE)


func hide_marker() -> void:
	if not _shown:
		return
	_shown = false
	_pop(Vector2.ZERO, true)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var cam := camera if is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.unproject_position(anchor)
	var bob := absf(sin(_t * bob_speed)) * bob_pixels
	global_position = (p - Vector2(size.x * 0.5, size.y + lift + bob)).round()
	queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	var pos := Vector2(3.0, size.y - 4.0)
	for ox in [-2, -1, 0, 1, 2]:
		for oy in [-2, -1, 0, 1, 2]:
			if ox != 0 or oy != 0:
				draw_string(f, pos + Vector2(ox, oy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_color)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


func _pop(target: Vector2, hide_after := false) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "scale", target, 0.25)
	if hide_after:
		_tween.tween_callback(func() -> void: visible = false)
