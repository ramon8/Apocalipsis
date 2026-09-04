class_name PlayerAction
extends Resource
## Accion del jugador descrita por datos: una secuencia de clips que bloquea el movimiento.
##
##   start (una vez) -> [idle (bucle) [-> strike por pulsacion -> idle]] -> [end] -> fin
##
## Cualquier fase salvo `start` es opcional. El "apex" es el instante util de la accion
## (la mano toca el objeto, el jugador esta agachado del todo...): se emite en
## `apex_fraction` del clip de inicio o, si es 1.0, cuando ese clip termina.
## Para anadir una accion nueva basta con crear un .tres con este script y pasarlo a
## Player.start_action(); el controller no cambia.

## Identificador para las senales (action_started / action_apex / action_finished).
@export var kind: StringName = &""

@export_group("Clips")
@export var start_anim := ""
## Pose de espera en bucle tras `start`. Vacio = no hay espera: tras start viene end.
@export var idle_anim := ""
## Clip disparado por Player.strike() mientras se espera. Vacio = sin golpe.
@export var strike_anim := ""
## Clip de salida. Vacio = la accion termina al acabar start (o al pedir stop desde idle).
@export var end_anim := ""

@export_group("Timing")
## Fraccion del clip de inicio (en su linea de tiempo normal) donde ocurre el apex.
## 1.0 = al terminar el clip. Con `reverse`, el apex se alcanza cuando la posicion baja
## por debajo de esta fraccion.
@export_range(0.0, 1.0, 0.05) var apex_fraction := 1.0
## Reproduce `start` hacia atras (soltar = coger al reves).
@export var reverse := false
## Velocidad de reproduccion de `start`.
@export_range(0.25, 4.0, 0.05) var speed := 1.0

@export_group("Reglas")
## Mover el stick durante la espera (o el inicio) cancela la accion via `end`.
@export var cancel_on_move := false


func has_idle() -> bool:
	return not idle_anim.is_empty()


func has_strike() -> bool:
	return not strike_anim.is_empty()


func has_end() -> bool:
	return not end_anim.is_empty()
