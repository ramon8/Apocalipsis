@tool
class_name GroundPaths
extends Node3D
## Pinta los caminos de tierra del suelo. Cada GroundPath (Path3D) hijo se rasteriza a una
## mascara en un SubViewport (Line2D con puntas y uniones redondas, en anillos de brillo
## creciente hacia el centro para que el shader pueda desgastar el borde con ruido) y la
## mascara se pasa al material del suelo como `path_mask` + `path_region`.
##
## Uso: un GroundPaths bajo World con `ground` apuntando al MeshInstance3D del suelo, y
## dentro tantos GroundPath como caminos. Se refresca solo al mover puntos en el editor.
## La region cubierta esta centrada en este nodo: muevelo si el pueblo no esta en el origen.

## Malla del suelo cuyo material (ShaderMaterial con `path_mask`) recibe la mascara.
@export var ground: MeshInstance3D:
	set(v):
		ground = v
		mark_dirty()
## Metros cubiertos por la mascara (centrada en este nodo). Fuera no hay caminos.
@export var region_size := Vector2(256.0, 256.0):
	set(v):
		region_size = v
		mark_dirty()
## Pixeles de la mascara. 1024 px sobre 256 m = 4 px/m, lo mismo que texels_per_meter.
@export_enum("512", "1024", "2048", "4096") var mask_resolution := 1024:
	set(v):
		mask_resolution = v
		mark_dirty()
## Anillos de brillo alrededor de cada camino (mas = borde mas gradual para el ruido).
@export_range(1, 8) var edge_rings := 4:
	set(v):
		edge_rings = v
		mark_dirty()
## Cuanto se ensancha el ultimo anillo respecto al ancho del camino (1.5 = 50% mas).
@export_range(1.0, 3.0, 0.05) var edge_spread := 1.6:
	set(v):
		edge_spread = v
		mark_dirty()

var _viewport: SubViewport
var _lines_root: Node2D
var _dirty := true
var _last_hash := 0
var _editor_timer := 0.0
## Sube cada vez que se repinta: los sistemas que dependen de los caminos (ScatterWorld)
## lo usan como clave de cache barata.
var version := 0
# Rejilla de distancias para consultas por CPU (clearance_at): metros por celda y valores.
var _grid: PackedFloat32Array
var _grid_dirty := true
var _grid_res := 0
const GRID_M_PER_CELL := 0.5
## Mas alla de esta distancia del borde del camino la rejilla no distingue (devuelve INF).
const GRID_MAX_DIST := 8.0

func _ready() -> void:
	_build_viewport()
	mark_dirty()


func _enter_tree() -> void:
	child_entered_tree.connect(_on_child_changed)
	child_exiting_tree.connect(_on_child_changed)


func _exit_tree() -> void:
	child_entered_tree.disconnect(_on_child_changed)
	child_exiting_tree.disconnect(_on_child_changed)


func _on_child_changed(node: Node) -> void:
	if node is Path3D:
		var p := node as Path3D
		if node.is_inside_tree() and not p.curve_changed.is_connected(mark_dirty):
			p.curve_changed.connect(mark_dirty)
		mark_dirty()


## Pide un repintado (se hace en el siguiente _process).
func mark_dirty() -> void:
	_dirty = true
	_grid_dirty = true


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# En el editor, ademas de las senales, comprobamos cambios cada poco (mover el
		# nodo entero, cambiar la transform de un camino...).
		_editor_timer += delta
		if _editor_timer >= 0.3:
			_editor_timer = 0.0
			if _content_hash() != _last_hash:
				_dirty = true
	if _dirty:
		_dirty = false
		_repaint()


func _build_viewport() -> void:
	if _viewport:
		return
	_viewport = SubViewport.new()
	_viewport.name = "MaskViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport, false, Node.INTERNAL_MODE_BACK)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.anchors_preset = Control.PRESET_FULL_RECT
	_viewport.add_child(bg)
	_lines_root = Node2D.new()
	_lines_root.name = "Lines"
	_viewport.add_child(_lines_root)


func _paths() -> Array[GroundPath]:
	var out: Array[GroundPath] = []
	for c in get_children():
		if c is GroundPath:
			out.append(c)
	return out


func _content_hash() -> int:
	var parts := [global_transform, region_size, mask_resolution]
	for p in _paths():
		parts.append(p.global_transform)
		parts.append(p.width)
		parts.append(p.strength)
		if p.curve:
			parts.append(p.curve.get_baked_points())
	return hash(parts)


## Holgura (m) desde un punto del mundo (XZ) hasta el borde exterior del camino mas
## cercano: negativo = dentro del camino (o de su borde desgastado). INF si esta a mas de
## GRID_MAX_DIST o fuera de la region. Lectura O(1) sobre una rejilla precalculada:
## la usan los sistemas de dispersion para no plantar arboles en el camino.
func clearance_at(world_xz: Vector2) -> float:
	if _grid_dirty:
		_build_grid()
	var local := world_xz - Vector2(global_position.x, global_position.z) + region_size * 0.5
	var cx := int(local.x / GRID_M_PER_CELL)
	var cy := int(local.y / GRID_M_PER_CELL)
	if cx < 0 or cy < 0 or cx >= _grid_res or cy >= _grid_res:
		return INF
	return _grid[cy * _grid_res + cx]


## Rejilla de distancia al borde de los caminos: cada punto de la curva "estampa" un disco
## de radio (borde + GRID_MAX_DIST) guardando la distancia minima. Una sola pasada al
## cargar o al editar; las consultas despues son una lectura.
func _build_grid() -> void:
	_grid_dirty = false
	_grid_res = int(ceil(region_size.x / GRID_M_PER_CELL))
	_grid = PackedFloat32Array()
	_grid.resize(_grid_res * _grid_res)
	_grid.fill(INF)
	var origin := Vector2(global_position.x, global_position.z) - region_size * 0.5
	for path in _paths():
		if path.curve == null or path.curve.point_count < 2:
			continue
		var r := path.width * 0.5 * edge_spread
		var reach := r + GRID_MAX_DIST
		var reach_cells := int(ceil(reach / GRID_M_PER_CELL))
		# Puntos cada ~GRID_M_PER_CELL: suficiente para un disco por punto sin huecos.
		var baked := path.curve.get_baked_points()
		var stride := maxi(1, int(GRID_M_PER_CELL / maxf(path.curve.bake_interval, 0.01)))
		var i := 0
		while i < baked.size():
			var w := path.global_transform * baked[i]
			var c := (Vector2(w.x, w.z) - origin) / GRID_M_PER_CELL
			var ci := Vector2i(int(c.x), int(c.y))
			for gy in range(maxi(ci.y - reach_cells, 0), mini(ci.y + reach_cells + 1, _grid_res)):
				for gx in range(maxi(ci.x - reach_cells, 0), mini(ci.x + reach_cells + 1, _grid_res)):
					var d := (Vector2(gx + 0.5, gy + 0.5) - c).length() * GRID_M_PER_CELL - r
					var idx := gy * _grid_res + gx
					if d < _grid[idx]:
						_grid[idx] = d
			i += stride
		# Ultimo punto siempre (el stride puede saltarselo).
		if baked.size() > 0 and (baked.size() - 1) % stride != 0:
			var w := path.global_transform * baked[baked.size() - 1]
			var c := (Vector2(w.x, w.z) - origin) / GRID_M_PER_CELL
			var ci := Vector2i(int(c.x), int(c.y))
			for gy in range(maxi(ci.y - reach_cells, 0), mini(ci.y + reach_cells + 1, _grid_res)):
				for gx in range(maxi(ci.x - reach_cells, 0), mini(ci.x + reach_cells + 1, _grid_res)):
					var d := (Vector2(gx + 0.5, gy + 0.5) - c).length() * GRID_M_PER_CELL - r
					var idx := gy * _grid_res + gx
					if d < _grid[idx]:
						_grid[idx] = d


## Metros -> pixel de la mascara.
func _to_mask(world: Vector3) -> Vector2:
	var local := world - global_position
	var uv := (Vector2(local.x, local.z) + region_size * 0.5) / region_size
	return uv * float(mask_resolution)


func _repaint() -> void:
	if _viewport == null:
		return
	_last_hash = _content_hash()
	_viewport.size = Vector2i(mask_resolution, mask_resolution)
	(_viewport.get_node("Background") as ColorRect).size = Vector2(_viewport.size)
	for c in _lines_root.get_children():
		c.free()
	var px_per_m := float(mask_resolution) / region_size.x
	for path in _paths():
		if path.curve == null or path.curve.point_count < 2:
			continue
		var pts := PackedVector2Array()
		for p in path.curve.get_baked_points():
			pts.append(_to_mask(path.global_transform * p))
		if pts.size() < 2:
			continue
		# Anillos: del mas ancho y oscuro al nucleo blanco. El shader umbraliza la suma con
		# ruido, asi que el borde queda irregular dentro de la zona de los anillos.
		for k in edge_rings:
			var t := float(k) / float(edge_rings)  # 0 = exterior, ->1 = nucleo
			var w := path.width * lerpf(edge_spread, 1.0, t)
			var line := Line2D.new()
			line.points = pts
			line.width = w * px_per_m
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.antialiased = false
			var v := path.strength * float(k + 1) / float(edge_rings)
			line.default_color = Color(v, v, v, 1.0)
			_lines_root.add_child(line)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_grid_dirty = true
	version += 1
	_apply_to_ground()


func _apply_to_ground() -> void:
	if ground == null:
		return
	var mat := ground.material_override as ShaderMaterial
	if mat == null:
		mat = ground.get_active_material(0) as ShaderMaterial
	if mat == null:
		push_warning("GroundPaths: el suelo no tiene un ShaderMaterial con path_mask.")
		return
	mat.set_shader_parameter("path_mask", _viewport.get_texture())
	mat.set_shader_parameter("path_region", Vector4(
			global_position.x - region_size.x * 0.5, global_position.z - region_size.y * 0.5,
			region_size.x, region_size.y))
