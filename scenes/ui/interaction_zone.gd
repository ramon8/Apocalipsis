class_name InteractionZone
extends Area3D
## Zona de interaccion reutilizable: esfera que detecta al jugador, prompt "E · accion" en
## el HUD y registro en InteractionManager con una prioridad. La E la procesa el manager
## una sola vez y llega al `target` (por defecto el padre) a traves de estos metodos,
## todos opcionales:
##
##   interact_with(player)                 -> la accion
##   can_interact(player) -> bool          -> ademas de las reglas de la zona
##   interaction_prompt(player) -> String  -> texto del prompt (si cambia con el estado)
##
## Uso tipico, en _ready del prop:
##   _zone = InteractionZone.new(); _zone.radius = 1.2; _zone.priority = 1; add_child(_zone)

signal player_entered(player: Player)
signal player_exited(player: Player)
## La E ha llegado a esta zona (antes de llamar a interact_with).
signal interacted(player: Player)

## Nodo que recibe interact_with / can_interact / interaction_prompt. Vacio = el padre.
var target: Node

@export var enabled := true:
	set(v):
		enabled = v
		if not v and is_inside_tree():
			_unregister()
## Radio de la esfera (m).
@export_range(0.3, 8.0, 0.1) var radius := 1.5:
	set(v):
		radius = v
		if _shape and _shape.shape is SphereShape3D:
			(_shape.shape as SphereShape3D).radius = v
## Altura del centro de la esfera sobre el origen.
@export var height := 0.5:
	set(v):
		height = v
		if _shape:
			_shape.position.y = v
## Prioridad en InteractionManager: menor gana cuando hay varias zonas en rango.
@export var interact_priority := 2:
	set(v):
		interact_priority = v
		if player_in_range and is_inside_tree():
			InteractionManager.enter(self, v)
@export var key_text := "E"
## Texto por defecto del prompt (el target puede sobreescribirlo con interaction_prompt).
@export var action_text := ""
## Con algo en brazos no se puede interactuar (el objeto llevado lleva su propia zona).
@export var blocked_while_carrying := true
@export var prompt_enabled := true

var player_in_range: Player

var _shape: CollisionShape3D
var _prompt: InteractPrompt


func _ready() -> void:
	if target == null:
		target = get_parent()
	collision_layer = 0
	collision_mask = 2  # capa del jugador
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	_shape.position.y = height
	add_child(_shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if Engine.is_editor_hint():
		return
	_prompt = InteractPrompt.new()
	_prompt.name = "Prompt"
	_prompt.key_text = key_text
	_prompt.action_text = action_text
	# HUD por encima del post-proceso retro; si no hay RetroRenderer, capa propia.
	var renderer := get_node_or_null("/root/RetroRenderer")
	if renderer and renderer.get("hud_layer") != null:
		renderer.hud_layer.add_child(_prompt)
	else:
		var layer := CanvasLayer.new()
		layer.name = "PromptLayer"
		layer.add_child(_prompt)
		add_child(layer)
	InteractionManager.changed.connect(refresh_prompt)


func _notification(what: int) -> void:
	# El prompt vive en el HUD, fuera de este subarbol: se libera con la zona (no en
	# _exit_tree, que tambien salta cuando RetroRenderer reparenta la escena).
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_prompt) and not is_ancestor_of(_prompt):
		_prompt.queue_free()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		InteractionManager.leave(self)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or not (body is Player):
		return
	player_in_range = body as Player
	InteractionManager.enter(self, interact_priority)
	player_entered.emit(player_in_range)


func _on_body_exited(body: Node3D) -> void:
	if body != player_in_range:
		return
	_unregister()
	player_exited.emit(body as Player)


func _unregister() -> void:
	player_in_range = null
	InteractionManager.leave(self)
	hide_prompt()


## Fuerza "en rango" sin area, p. ej. el objeto que el jugador lleva en brazos
## (prioridad -1: siempre gana). release() lo deshace.
func hold(player: Player, hold_priority := -1) -> void:
	player_in_range = player
	interact_priority = hold_priority
	InteractionManager.enter(self, hold_priority)


func release() -> void:
	_unregister()


func is_current() -> bool:
	return InteractionManager.is_current(self)


## Reglas de la zona + can_interact del target.
func can_interact(player: Player) -> bool:
	if not enabled or player == null:
		return false
	if blocked_while_carrying and player.is_carrying():
		return false
	if target and target.has_method("can_interact"):
		return target.can_interact(player)
	return true


## Ejecuta la accion sobre `player` (por defecto el que esta en rango). `force` salta
## can_interact: lo usa el manager cuando la zona tiene capturada la E (dialogo, minijuego).
func try_interact(player: Player = null, force := false) -> bool:
	if player == null:
		player = player_in_range
	if player == null or (not force and not can_interact(player)):
		return false
	interacted.emit(player)
	if target and target.has_method("interact_with"):
		target.interact_with(player)
	return true


## Muestra u oculta el prompt segun el estado actual. Se llama solo cuando cambia el
## manager; el target lo llama si su propio estado cambia (p. ej. la hoguera se enciende).
func refresh_prompt() -> void:
	if _prompt == null:
		return
	if prompt_enabled and player_in_range and is_current() and can_interact(player_in_range):
		var text := action_text
		if target and target.has_method("interaction_prompt"):
			text = target.interaction_prompt(player_in_range)
		_prompt.action_text = text
		_prompt.key_text = key_text
		_prompt.show_at()
	elif _prompt.visible:
		_prompt.pop_out()


func hide_prompt() -> void:
	if _prompt and _prompt.visible:
		_prompt.pop_out()
