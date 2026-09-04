@tool
class_name ScatterClearing
extends Path3D
## Claro: dentro de esta curva cerrada no crecen arboles ni arbustos (grupo
## "scatter_exclusion"). Dibujala alrededor del pueblo para reservar sitio a casas y
## caminos; `margin` deja ademas una franja libre por fuera del borde.

@export_range(0.0, 20.0, 0.5) var margin := 2.0:
	set(v):
		margin = v
		_clearance = null

var _clearance: CurveClearance


func _ready() -> void:
	curve_changed.connect(func() -> void: _clearance = null)


func _enter_tree() -> void:
	add_to_group("scatter_exclusion")


func clearance_at(world_xz: Vector2) -> float:
	if curve == null or curve.point_count < 3:
		return INF
	if _clearance == null:
		_clearance = CurveClearance.from_curve(curve, global_transform, true, margin, true)
	return _clearance.clearance_at(world_xz)
