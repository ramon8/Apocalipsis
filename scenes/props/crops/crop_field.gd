@tool
class_name CropField
extends Path3D
## Campo de cultivo: la curva cerrada es el borde de la parcela. Dentro se plantan sprites
## del CropType en hileras (direccion del primer tramo de la curva, o `row_angle_deg`),
## como MultiMesh de quads cruzados con el shader de viento. `growth` 0..1 elige la fase
## (textura y altura). Grupos: "scatter_exclusion" (sin arboles) y "ground_patch" (el suelo
## se pinta como tierra labrada bajo la parcela, via GroundPaths).

const WIND_SHADER := preload("res://scenes/props/tree/shaders/wind_cutout_lit.gdshader")

@export var crop: CropType:
	set(v):
		crop = v
		_rebuild()
## Crecimiento 0..1: elige la fase del cultivo.
@export_range(0.0, 1.0, 0.01) var growth := 1.0:
	set(v):
		growth = v
		_apply_stage()

@export_group("Tamano")
## Multiplica la altura de las plantas (sobre la del cultivo y su fase). No regenera.
@export_range(0.2, 3.0, 0.05) var plant_scale := 1.0:
	set(v):
		plant_scale = v
		_apply_stage()
## Multiplica solo el ancho (1 = el aspecto de la textura).
@export_range(0.2, 3.0, 0.05) var width_scale := 1.0:
	set(v):
		width_scale = v
		_apply_stage()

@export_group("Siembra")
## 0 = usar los del cultivo.
@export_range(0.0, 3.0, 0.05) var row_spacing := 0.0:
	set(v):
		row_spacing = v
		_rebuild()
@export_range(0.0, 3.0, 0.05) var plant_spacing := 0.0:
	set(v):
		plant_spacing = v
		_rebuild()
## Direccion de las hileras (grados). Vacio/0 = la del primer tramo de la curva.
@export var row_angle_deg := 0.0:
	set(v):
		row_angle_deg = v
		_rebuild()
@export var use_curve_direction := true:
	set(v):
		use_curve_direction = v
		_rebuild()
## Desorden de cada planta respecto a su sitio (fraccion del espaciado).
@export_range(0.0, 0.5, 0.01) var jitter := 0.15:
	set(v):
		jitter = v
		_rebuild()
## Variacion de tamano entre plantas.
@export_range(0.0, 0.5, 0.01) var size_variation := 0.12:
	set(v):
		size_variation = v
		_rebuild()
## Franja sin plantar junto al borde (m).
@export_range(0.0, 3.0, 0.05) var edge_margin := 0.4:
	set(v):
		edge_margin = v
		_rebuild()
@export var seed := 0:
	set(v):
		seed = v
		_rebuild()

@export_group("Suelo")
## Pinta tierra labrada bajo la parcela (grupo "ground_patch", lo lee GroundPaths).
@export var soil_enabled := true:
	set(v):
		soil_enabled = v
		_notify_ground()
@export var cast_shadows := true:
	set(v):
		cast_shadows = v
		if _mmi:
			_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if v else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _mmi: MultiMeshInstance3D
var _material: ShaderMaterial
var _plants: Array = []  # [pos local, yaw, size factor]
var _clearance: CurveClearance
var _stage := -1
var _building := false
static var _cross_mesh: ArrayMesh


func _ready() -> void:
	curve_changed.connect(_rebuild)
	_rebuild()


func _enter_tree() -> void:
	add_to_group("scatter_exclusion")
	add_to_group("ground_patch")


func _exit_tree() -> void:
	_notify_ground()


func clearance_at(world_xz: Vector2) -> float:
	if curve == null:
		return INF
	if _clearance == null:
		_clearance = CurveClearance.from_curve(curve, global_transform, true, 0.5, true)
	return _clearance.clearance_at(world_xz)


## Poligono de la parcela en metros de mundo (XZ), para pintar el suelo. Vacio = sin suelo.
func ground_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not soil_enabled or curve == null or curve.point_count < 3:
		return out
	for p in _local_polygon():
		var w := global_transform * Vector3(p.x, 0.0, p.y)
		out.append(Vector2(w.x, w.z))
	return out


## Numero de plantas (para tests / HUD).
func plant_count() -> int:
	return _plants.size()


func current_stage() -> int:
	return _stage


func _local_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var baked := curve.get_baked_points()
	var stride := maxi(1, int(0.5 / maxf(curve.bake_interval, 0.01)))
	var i := 0
	while i < baked.size():
		pts.append(Vector2(baked[i].x, baked[i].z))
		i += stride
	return pts


static func _get_cross_mesh() -> ArrayMesh:
	if _cross_mesh:
		return _cross_mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in 2:
		var right := Vector3(0.5, 0.0, 0.0) if i == 0 else Vector3(0.0, 0.0, 0.5)
		var base := verts.size()
		verts.append_array([-right, right, right + Vector3.UP, -right + Vector3.UP])
		# Normales hacia arriba: el follaje se ilumina como el suelo que lo rodea, sin
		# la cara oscura que darian las normales de cada quad (y sin normales no hay luz).
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_cross_mesh = ArrayMesh.new()
	_cross_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _cross_mesh


func _rebuild() -> void:
	if not is_inside_tree() or _building:
		return
	_building = true
	_clearance = null
	if _mmi:
		remove_child(_mmi)
		_mmi.queue_free()
		_mmi = null
	_plants.clear()
	_stage = -1
	if crop != null and crop.stage_count() > 0 and curve != null and curve.point_count >= 3:
		_plan_plants()
		_build_multimesh()
		_apply_stage()
	_building = false
	_notify_ground()


## Rejilla de hileras dentro de la parcela (menos el margen), con desorden.
func _plan_plants() -> void:
	var poly := _local_polygon()
	if poly.size() < 3:
		return
	var inner: Array[PackedVector2Array] = Geometry2D.offset_polygon(poly, -edge_margin, Geometry2D.JOIN_ROUND) if edge_margin > 0.0 else [poly]
	if inner.is_empty():
		return
	var rs := row_spacing if row_spacing > 0.0 else crop.row_spacing
	var ps := plant_spacing if plant_spacing > 0.0 else crop.plant_spacing
	var angle := deg_to_rad(row_angle_deg)
	if use_curve_direction and curve.point_count >= 2:
		var a := curve.get_point_position(0)
		var b := curve.get_point_position(1)
		angle = atan2(b.z - a.z, b.x - a.x)
	var along := Vector2(cos(angle), sin(angle))   # direccion de la hilera
	var across := Vector2(-along.y, along.x)      # de hilera a hilera
	# bbox en el marco de las hileras.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		var u := Vector2(p.dot(along), p.dot(across))
		lo = Vector2(minf(lo.x, u.x), minf(lo.y, u.y))
		hi = Vector2(maxf(hi.x, u.x), maxf(hi.y, u.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(global_position.snapped(Vector3.ONE * 0.01))
	var rows := int(floor((hi.y - lo.y) / rs))
	var cols := int(floor((hi.x - lo.x) / ps))
	if rows <= 0 or cols <= 0:
		return
	var y0 := lo.y + ((hi.y - lo.y) - float(rows - 1) * rs) * 0.5
	var x0 := lo.x + ((hi.x - lo.x) - float(cols - 1) * ps) * 0.5
	for r in rows:
		for c in cols:
			var u := Vector2(x0 + float(c) * ps + rng.randf_range(-jitter, jitter) * ps,
					y0 + float(r) * rs + rng.randf_range(-jitter, jitter) * rs)
			var p := along * u.x + across * u.y
			var inside := false
			for ring in inner:
				if Geometry2D.is_point_in_polygon(p, ring):
					inside = true
					break
			if not inside:
				continue
			_plants.append([p, rng.randf_range(0.0, TAU), 1.0 + rng.randf_range(-size_variation, size_variation)])


func _build_multimesh() -> void:
	_material = ShaderMaterial.new()
	_material.shader = WIND_SHADER
	_material.set_shader_parameter("alpha_cutoff", 0.5)
	_material.set_shader_parameter("wind_influence", crop.wind_influence)
	_material.set_shader_parameter("sway_amount", crop.sway)
	_material.set_shader_parameter("flutter_amount", crop.flutter)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _get_cross_mesh()
	mm.instance_count = _plants.size()
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Plants"
	_mmi.multimesh = mm
	_mmi.material_override = _material
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Aplica la fase actual: textura y altura de cada planta.
func _apply_stage() -> void:
	if _mmi == null or crop == null:
		return
	var stage := crop.stage_for(growth)
	if stage < 0:
		return
	if stage != _stage:
		_stage = stage
		_material.set_shader_parameter("albedo_tex", crop.stage_textures[stage])
	var h := crop.stage_height(stage) * plant_scale
	var mm := _mmi.multimesh
	var aabb := AABB()
	for i in _plants.size():
		var pl: Array = _plants[i]
		var s: float = h * pl[2]
		var w: float = s * crop.width_ratio * width_scale
		var basis := Basis.from_euler(Vector3(0.0, pl[1], 0.0)) * Basis.from_scale(Vector3(w, s, w))
		var pos := Vector3(pl[0].x, 0.0, pl[0].y)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		aabb = AABB(pos, Vector3.ZERO) if i == 0 else aabb.expand(pos)
	aabb = aabb.grow(h + 0.5)
	_mmi.custom_aabb = aabb


## El suelo (GroundPaths, grupo "ground_paths") repinta la tierra labrada.
func _notify_ground() -> void:
	if not is_inside_tree():
		return
	for gp in get_tree().get_nodes_in_group("ground_paths"):
		if gp.has_method("mark_dirty"):
			gp.mark_dirty()
