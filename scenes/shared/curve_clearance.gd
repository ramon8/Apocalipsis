class_name CurveClearance
extends RefCounted
## Consulta de "holgura" (distancia al borde) de una polilinea en el plano XZ, para que la
## dispersion (ScatterWorld) no plante nada encima de vallas, lagos, caminos...
## Se construye desde una Curve3D (en espacio de mundo) con un paso de ~1 m; las consultas
## rechazan por bbox primero, asi que salen baratas aunque haya cien mil.
##
##   var cc := CurveClearance.from_curve(curve, global_transform, closed, margin, exclude_inside)
##   cc.clearance_at(Vector2(x, z))  # negativo = dentro de la zona vetada

var points: PackedVector2Array
var closed := false
## Distancia (m) alrededor de la linea que tambien se veta.
var margin := 0.0
## Si es un bucle cerrado, veta tambien todo el interior (corral, lago).
var exclude_inside := false
var bbox := Rect2()


static func from_curve(curve: Curve3D, xform: Transform3D, is_closed: bool, margin_m: float,
		inside: bool, step := 1.0) -> CurveClearance:
	var cc := CurveClearance.new()
	cc.closed = is_closed
	cc.margin = margin_m
	cc.exclude_inside = inside and is_closed
	if curve == null or curve.point_count < 2:
		return cc
	var baked := curve.get_baked_points()
	var stride := maxi(1, int(step / maxf(curve.bake_interval, 0.01)))
	var i := 0
	while i < baked.size():
		var w := xform * baked[i]
		cc._add(Vector2(w.x, w.z))
		i += stride
	if (baked.size() - 1) % stride != 0:
		var w := xform * baked[baked.size() - 1]
		cc._add(Vector2(w.x, w.z))
	cc.bbox = cc.bbox.grow(margin_m)
	return cc


func _add(p: Vector2) -> void:
	if points.is_empty():
		bbox = Rect2(p, Vector2.ZERO)
	else:
		bbox = bbox.expand(p)
	points.append(p)


## Holgura en metros: negativa dentro de la zona vetada, INF lejos (fuera del bbox).
func clearance_at(p: Vector2) -> float:
	if points.size() < 2 or not bbox.has_point(p):
		return INF
	if exclude_inside and Geometry2D.is_point_in_polygon(p, points):
		return -1.0
	return distance_to_line(p) - margin


func is_inside(p: Vector2) -> bool:
	return closed and points.size() >= 3 and bbox.has_point(p) and Geometry2D.is_point_in_polygon(p, points)


## Distancia (m, siempre >= 0) del punto a la polilinea, sin margen ni test de interior.
func distance_to_line(p: Vector2) -> float:
	if points.size() < 2:
		return INF
	var best := INF
	var n := points.size() if closed else points.size() - 1
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 <= 0.000001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best
