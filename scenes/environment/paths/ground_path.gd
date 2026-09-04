@tool
class_name GroundPath
extends Path3D
## Un camino de tierra. Dibuja la curva en el editor (hijo de un GroundPaths); el ancho y
## la fuerza se pintan en la mascara que mezcla el shader del suelo. Solo importa la
## proyeccion XZ: la altura de los puntos se ignora.

## Ancho del camino en metros (la parte de tierra pura; el borde irregular sale por fuera).
@export_range(0.5, 20.0, 0.1) var width := 2.5:
	set(v):
		width = v
		_notify()
## 1 = tierra pisada del todo; menos = sendero apenas marcado.
@export_range(0.1, 1.0, 0.05) var strength := 1.0:
	set(v):
		strength = v
		_notify()


func _notify() -> void:
	var p := get_parent()
	if p and p.has_method("mark_dirty"):
		p.mark_dirty()
