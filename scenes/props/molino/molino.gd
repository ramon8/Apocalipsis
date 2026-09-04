@tool
class_name Molino
extends Building
## Molino de viento: un Building (envejecido + interior + puerta) cuyas aspas ("Elices" en
## el GLB) giran sobre su eje a `blade_speed_rpm` rpm. La planta se mide solo con la malla
## de la torre (`bounds_mesh_name`), no con las aspas.

## Velocidad de las aspas en vueltas por minuto. Negativo = sentido contrario.
@export_range(-30.0, 30.0, 0.1) var blade_speed_rpm := 6.0
## Girar tambien en el editor para previsualizar.
@export var spin_in_editor := true
## Nombre del nodo de las aspas dentro del modelo importado.
@export var blades_node_name := "Elices"

var _blades: Node3D


func _init() -> void:
	bounds_mesh_name = "Molino"
	interior_shape = Room.Shape.CIRCLE


func _setup_model(model: Node) -> void:
	_blades = model.find_child(blades_node_name, true, false)
	if _blades == null:
		push_warning("Molino: no encuentro el nodo de aspas '%s' en el modelo." % blades_node_name)


func _process(delta: float) -> void:
	super(delta)
	if _blades != null and (not Engine.is_editor_hint() or spin_in_editor):
		# El nodo de las aspas viene del GLB con su pivote en el buje; su eje local Y
		# (tras la rotacion X+90 del export) es el eje del buje.
		_blades.rotate_object_local(Vector3.UP, blade_speed_rpm * TAU / 60.0 * delta)
