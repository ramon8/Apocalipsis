class_name FirestarterWheel
extends Control
## Rueda estilo "estamina de Zelda" para el minijuego de encender la hoguera.
## Un anillo oscuro, una seccion coloreada (objetivo) y una marca que lo recorre.
## Es puramente visual: la logica (avance de la marca, aciertos) vive en Campfire.
## Fracciones en 0..1 empezando arriba y girando en sentido horario.

@export_range(8.0, 64.0, 1.0) var radius := 22.0
@export_range(2.0, 16.0, 1.0) var ring_width := 6.0
@export var ring_color := Color(0.12, 0.12, 0.15, 0.85)
@export var target_color := Color(1.0, 0.62, 0.15)
@export var marker_color := Color.WHITE
@export var hit_flash_color := Color(0.5, 1.0, 0.5)
@export_range(0.05, 1.0, 0.05) var pop_duration := 0.2

var marker_frac := 0.0:
	set(value):
		marker_frac = value
		queue_redraw()
var target_from_frac := 0.1
var target_size_frac := 0.16

var _tween: Tween
var _flash := 0.0


func _ready() -> void:
	var d := (radius + ring_width) * 2.0 + 6.0
	size = Vector2(d, d)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale = Vector2.ZERO
	visible = false


func set_target(from_frac: float, size_frac: float) -> void:
	target_from_frac = fposmod(from_frac, 1.0)
	target_size_frac = size_frac
	queue_redraw()


func is_marker_in_target() -> bool:
	return fposmod(marker_frac - target_from_frac, 1.0) <= target_size_frac


## Destello breve (acierto).
func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		queue_redraw()


func _angle(frac: float) -> float:
	return -PI * 0.5 + fposmod(frac, 1.0) * TAU


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, radius, 0.0, TAU, 64, ring_color, ring_width)
	var col := target_color.lerp(hit_flash_color, _flash)
	draw_arc(c, radius, _angle(target_from_frac), _angle(target_from_frac) + target_size_frac * TAU,
			maxi(int(target_size_frac * 48.0), 4), col, ring_width)
	# Marca radial que cruza el anillo.
	var dir := Vector2(cos(_angle(marker_frac)), sin(_angle(marker_frac)))
	draw_line(c + dir * (radius - ring_width), c + dir * (radius + ring_width), marker_color, 2.0)


func show_wheel() -> void:
	visible = true
	_animate(Vector2.ONE, Tween.EASE_OUT)


func pop_out() -> void:
	_animate(Vector2.ZERO, Tween.EASE_IN)
	if _tween:
		_tween.finished.connect(func() -> void: visible = false, CONNECT_ONE_SHOT)


func _animate(to: Vector2, ease_type: Tween.EaseType) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", to, pop_duration).set_trans(Tween.TRANS_BACK).set_ease(ease_type)
