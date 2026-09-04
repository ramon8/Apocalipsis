class_name WakeCanvas
extends Node2D
## Lienzo de estela de un lago (vive en un SubViewport que se limpia cada frame). Guarda las
## estampas de los ultimos `life` segundos y las redibuja cada frame con intensidad
## decreciente y radio creciente, con blend ADD para que se sumen donde se solapan.
## (No se acumula en la GPU: un SubViewport sin limpiar no conserva el contenido de forma
## fiable en Forward+.) El shader del agua lee el canal R como intensidad de estela.

## Segundos que tarda una estampa en desaparecer.
var life := 1.4
## Cuanto crece el radio al disiparse (1.6 = 60% mas grande al final).
var spread := 1.6
var px_per_m := 8.0
var origin := Vector2.ZERO  # metros de mundo (XZ) del pixel (0,0)

var _stamps: Array = []  # [Vector2 px, radius px, strength, t0]
var _time := 0.0


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add


func resize(_size: Vector2i) -> void:
	pass


## Estampa un disco en metros de mundo (XZ).
func stamp(world_xz: Vector2, radius_m: float, strength: float) -> void:
	_stamps.append([(world_xz - origin) * px_per_m, radius_m * px_per_m, strength, _time])


func _process(delta: float) -> void:
	_time += delta
	# Purga las caducadas (estan ordenadas por tiempo: basta con recortar por delante).
	var first_alive := 0
	while first_alive < _stamps.size() and _time - _stamps[first_alive][3] >= life:
		first_alive += 1
	if first_alive > 0:
		_stamps = _stamps.slice(first_alive)
	queue_redraw()


func _draw() -> void:
	for s in _stamps:
		var age: float = clampf((_time - s[3]) / maxf(life, 0.001), 0.0, 1.0)
		var k := 1.0 - age
		var r: float = s[1] * lerpf(1.0, spread, age)
		var v: float = s[2] * k
		# Disco con borde suave: dos circulos, el exterior mas tenue.
		draw_circle(s[0], r, Color(v * 0.35, 0.0, 0.0, 1.0))
		draw_circle(s[0], r * 0.6, Color(v * 0.45, 0.0, 0.0, 1.0))
