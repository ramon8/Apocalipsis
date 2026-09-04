class_name DialogueEntry
extends Resource
## Un bloque de dialogo de un NPC y cuando toca decirlo. El NPC tiene una lista de
## estos; cada uno se dispara por:
##
##   TALK       el jugador pulsa E. Entre las que cumplen condiciones gana la de mayor
##              `priority` (empate: la ultima de la lista).
##   FLAG       automatico en cuanto `trigger_flag` se pone a true (si cumple condiciones
##              y el jugador anda cerca y puede ver al NPC). Avanza solo.
##   ROOM_EXIT  despedida: el jugador sale de la habitacion del NPC. Manual (E).
##
## Condiciones: nombres de flag de WorldState, con "!" para negar: ["fire_lit", "!pot_taken"].
## Palabras clave entre asteriscos en las lineas: *asi* (ondulan y salen en color).

enum Trigger { TALK, FLAG, ROOM_EXIT }

## Identificador (para depurar y para `once`).
@export var id: StringName = &""
@export var trigger := Trigger.TALK
## FLAG: flag de WorldState que dispara este bloque al ponerse a true.
@export var trigger_flag: StringName = &""
@export_multiline var lines: Array[String] = []
## Flags que deben cumplirse ("flag" o "!flag"). Vacio = siempre.
@export var requires: PackedStringArray = []
## TALK: mayor gana entre las candidatas.
@export var priority := 0
## Solo se dice una vez en toda la partida.
@export var once := false
## Primera linea gritada (grande, roja, voz grave) + temblor de camara.
@export var shout := false
## Al dispararse (FLAG), vuelve a salir el marcador "!" hasta que el jugador hable.
@export var mark_new := false


func is_available() -> bool:
	return not lines.is_empty() and WorldState.check_all(requires)
