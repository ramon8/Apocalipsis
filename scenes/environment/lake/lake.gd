@tool
class_name Lake
extends Path3D
## Lago: dibuja la orilla con la curva (cerrada) y se genera solo. Un plano cubre el bbox de
## la curva; la forma y la distancia a la orilla van en una mascara pintada en un
## SubViewport (relleno + anillos de distancia) que el shader del agua usa para recortar,
## colorear por profundidad y poner espuma. La orilla lleva cajas de colision retranqueadas
## `wade_distance` metros hacia dentro (se puede vadear el borde, no nadar).
## Se anade al grupo "scatter_exclusion": no crecen arboles dentro. Y al grupo "lake":
## el componente Wading del jugador pregunta depth_at() para hundirse y chapotear.

const WATER_SHADER := preload("res://scenes/environment/lake/shaders/water.gdshader")

@export_group("Forma")
## Altura del agua respecto a este nodo.
@export var water_level := 0.0:
	set(v):
		water_level = v
		_rebuild()
## Pixeles por metro de la mascara de forma.
@export_range(1.0, 16.0, 1.0) var mask_px_per_m := 4.0:
	set(v):
		mask_px_per_m = v
		_rebuild()
## Metros hacia dentro que cubre el gradiente de distancia (espuma, somero).
@export_range(1.0, 12.0, 0.5) var mask_range := 4.0:
	set(v):
		mask_range = v
		_rebuild()
## Escalones del gradiente de distancia (mas = espuma mas fina).
@export_range(4, 64) var distance_rings := 24:
	set(v):
		distance_rings = v
		_rebuild()

@export_group("Agua")
@export var pixel_art := false:
	set(v):
		pixel_art = v
		_set_param("pixel_art", v)
@export var deep_color := Color(0.10, 0.13, 0.13):
	set(v):
		deep_color = v
		_set_param("deep_color", v)
@export var shallow_color := Color(0.20, 0.24, 0.20):
	set(v):
		shallow_color = v
		_set_param("shallow_color", v)
@export var foam_color := Color(0.75, 0.76, 0.53):
	set(v):
		foam_color = v
		_set_param("foam_color", v)
@export_range(0.1, 10.0, 0.1) var shallow_width := 2.5:
	set(v):
		shallow_width = v
		_set_param("shallow_width", v)
@export_range(0.0, 5.0, 0.1) var foam_width := 1.6:
	set(v):
		foam_width = v
		_set_param("foam_width", v)
@export_range(0.0, 0.6, 0.01) var ripple_strength := 0.18:
	set(v):
		ripple_strength = v
		_set_param("ripple_strength", v)
@export_range(0.0, 1.0, 0.05) var water_alpha := 0.92:
	set(v):
		water_alpha = v
		_set_param("water_alpha", v)

@export_group("Colision")
@export var collision_enabled := true:
	set(v):
		collision_enabled = v
		_rebuild()
## Metros de orilla que se pueden vadear antes de chocar con el agua.
@export_range(0.0, 5.0, 0.1) var wade_distance := 0.8:
	set(v):
		wade_distance = v
		_rebuild()

@export_group("Vadeo")
## Cuanto se hunde el personaje (m) al llegar al limite vadeable; crece linealmente desde
## la orilla.
@export_range(0.0, 1.0, 0.01) var wade_depth := 0.3
## Velocidad del personaje con el agua a la profundidad maxima (1 = no frena).
@export_range(0.1, 1.0, 0.05) var wade_speed_factor := 0.55

@export_group("Dispersion")
@export var clear_scatter := true
@export_range(0.0, 5.0, 0.25) var scatter_margin := 1.5

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _viewport: SubViewport
var _body: StaticBody3D
var _clearance: CurveClearance
var _building := false


func _ready() -> void:
	curve_changed.connect(_rebuild)
	_rebuild()


func _enter_tree() -> void:
	add_to_group("scatter_exclusion")
	add_to_group("lake")


## Profundidad del agua (m) bajo un punto del mundo: 0 fuera del lago, y dentro crece con la
## distancia a la orilla hasta `wade_depth` en `wade_distance` (mas alla no se puede pasar).
func depth_at(world_xz: Vector2) -> float:
	if curve == null:
		return 0.0
	if _clearance == null:
		_clearance = CurveClearance.from_curve(curve, global_transform, true, scatter_margin, true)
	if not _clearance.is_inside(world_xz):
		return 0.0
	var d := _clearance.distance_to_line(world_xz)
	return wade_depth * clampf(d / maxf(wade_distance, 0.05), 0.0, 1.0)


func clearance_at(world_xz: Vector2) -> float:
	if not clear_scatter or curve == null:
		return INF
	if _clearance == null:
		_clearance = CurveClearance.from_curve(curve, global_transform, true, scatter_margin, true)
	return _clearance.clearance_at(world_xz)


func _set_param(pname: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(pname, value)


func _clear() -> void:
	for n in [_mesh, _viewport, _body]:
		if n:
			n.free()
	_mesh = null
	_viewport = null
	_body = null
	_clearance = null


## Puntos de la orilla en espacio local (XZ), a ~0.5 m.
func _shore_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	if curve == null or curve.point_count < 3:
		return pts
	var baked := curve.get_baked_points()
	var stride := maxi(1, int(0.5 / maxf(curve.bake_interval, 0.01)))
	var i := 0
	while i < baked.size():
		pts.append(Vector2(baked[i].x, baked[i].z))
		i += stride
	return pts


func _rebuild() -> void:
	if not is_inside_tree() or _building:
		return
	_building = true
	_clear()
	var pts := _shore_points()
	if pts.size() >= 3:
		var bbox := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bbox = bbox.expand(p)
		bbox = bbox.grow(1.0)
		_build_mask(pts, bbox)
		_build_mesh(bbox)
		if collision_enabled:
			_build_collision(pts)
	_building = false


func _build_mask(pts: PackedVector2Array, bbox: Rect2) -> void:
	var size := Vector2i(maxi(8, int(bbox.size.x * mask_px_per_m)), maxi(8, int(bbox.size.y * mask_px_per_m)))
	_viewport = SubViewport.new()
	_viewport.name = "MaskViewport"
	_viewport.size = size
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport, false, Node.INTERNAL_MODE_BACK)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(size)
	_viewport.add_child(bg)
	var px := PackedVector2Array()
	for p in pts:
		px.append((p - bbox.position) / bbox.size * Vector2(size))
	# 1) Relleno R = 1 (lejos de la orilla).
	var fill := Polygon2D.new()
	fill.polygon = px
	fill.color = Color(1.0, 0.0, 0.0)
	_viewport.add_child(fill)
	# 2) Anillos sobre la orilla, del mas ancho (R alto) al mas estrecho (R ~ 0): R = distancia.
	for k in distance_rings:
		var t := 1.0 - float(k) / float(distance_rings)  # 1 -> 1/rings
		var line := Line2D.new()
		line.points = px
		line.closed = true
		line.width = 2.0 * mask_range * t * mask_px_per_m
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.antialiased = false
		var v := t - 0.5 / float(distance_rings)
		line.default_color = Color(maxf(v, 0.0), 0.0, 0.0)
		_viewport.add_child(line)
	# 3) Relleno G = 1 (dentro) sumado encima: R queda como distancia, G marca el interior.
	var inside := Polygon2D.new()
	inside.polygon = px
	inside.color = Color(0.0, 1.0, 0.0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	inside.material = add
	_viewport.add_child(inside)


func _build_mesh(bbox: Rect2) -> void:
	_material = ShaderMaterial.new()
	_material.shader = WATER_SHADER
	for p in ["pixel_art", "deep_color", "shallow_color", "foam_color", "shallow_width",
			"foam_width", "ripple_strength", "water_alpha", "mask_range"]:
		_material.set_shader_parameter(p, get(p))
	_material.set_shader_parameter("mask", _viewport.get_texture())
	var plane := PlaneMesh.new()
	plane.size = bbox.size
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	plane.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.name = "Water"
	_mesh.mesh = plane
	_mesh.position = Vector3(bbox.get_center().x, water_level, bbox.get_center().y)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## Cajas a lo largo de la orilla, retranqueadas hacia dentro `wade_distance`.
func _build_collision(pts: PackedVector2Array) -> void:
	_body = StaticBody3D.new()
	_body.name = "ShoreCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var inner: Array[PackedVector2Array] = Geometry2D.offset_polygon(pts, -wade_distance, Geometry2D.JOIN_ROUND)
	for poly in inner:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var along := b - a
			var len := along.length()
			if len < 0.05:
				continue
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.3, 2.0, len)
			shape.shape = box
			var mid := (a + b) * 0.5
			shape.position = Vector3(mid.x, water_level + 0.5, mid.y)
			shape.rotation.y = atan2(along.x, along.y)
			_body.add_child(shape)
	add_child(_body)
