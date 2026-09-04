# Apocalipsis — guía de implementación

Prototipo isométrico retro en **Godot 4.7** (Forward+, renderer retro propio en `retro/`).
Este archivo describe los sistemas genéricos del juego y cómo extenderlos sin tocar el
core. Léelo antes de añadir acciones, objetos interactuables, NPCs o quests.

## Validar cambios

Godot 4.7 está en `C:/Develop/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe`.
Todo se puede validar sin abrir el editor:

```
godot --headless --path . --import                 # reimporta y registra class_name nuevos
godot --headless --path . --quit-after 90          # carga main.tscn: errores de parseo/carga
godot --headless --path . --quit-after 3000 tests/player_actions_test.tscn
godot --headless --path . --quit-after 3000 tests/interaction_zone_test.tscn
godot --headless --path . --quit-after 3000 tests/dialogue_test.tscn
```

- Los tests son escenas (`tests/*.tscn` con un script `extends Node`) para que carguen los
  autoloads. En modo `-s` no hay autoloads y todo lo que use `InteractionManager` o
  `WorldState` falla al compilar.
- En headless aparecen errores `Parameter "material" is null` del renderer dummy. Son ruido.
- Ejecuta el `--import` después de crear scripts con `class_name` o recursos `.tres`, si no
  la escena principal no los encuentra.
- Añade un test cuando toques la máquina de estados del jugador, la interacción o el
  diálogo. Patrón: `_check(cond, "descripción")`, `await get_tree().physics_frame`, y
  `get_tree().quit(1 if _failures > 0 else 0)` al final. Cuelga los nodos del propio nodo
  de test (`add_child`), no de `root`.

## Autoloads (project.godot)

| Autoload | Archivo | Para qué |
|---|---|---|
| `RetroRenderer` | `retro/retro_renderer.tscn` | Render a baja resolución + post. `hud_layer` es donde va la UI que no debe pasar por el post. |
| `InteractionManager` | `scenes/ui/interaction_manager.gd` | Decide qué zona tiene la E y procesa la tecla una sola vez. |
| `RoomManager` | `scenes/interiors/room_manager.gd` | Registro de habitaciones por `room_id` y señales de ocupación. |
| `WorldState` | `scenes/world/world_state.gd` | Flags globales del mundo (`fire_lit`, `pot_taken`...). |

## Jugador: máquina de estados + acciones por datos

`scenes/player/player.gd`. Cuatro estados:

| Estado | Qué hace |
|---|---|
| `LOCOMOTION` | Único estado que lee input de movimiento. Elige Idle/Walk/Run por velocidad. |
| `ACTION` | Ejecuta un `PlayerAction`. Fases `START → [IDLE [→ STRIKE → IDLE]] → [END]`. |
| `SITTING` | Sentado en el suelo. Moverse o repetir la tecla levanta. |
| `LOCKED` | Bloqueo externo. Se entra con `lock(reason)`, se sale cuando no queda ninguna razón. |

**API pública** (todo lo demás es privado, no lo uses desde fuera):

- `start_action(action) -> bool`, `strike()`, `stop_action()`, `can_start_action()`, `current_action()`
- `lock(reason: StringName)` / `unlock(reason)` / `is_locked()`. Cada sistema usa su propia razón
  (los NPC usan `npc_<instance_id>`), así dos bloqueos no se pisan el desbloqueo.
- `sit_down()` / `stand_up()`, `is_sitting()`, `is_crouching()`, `is_action_playing()`, `is_carrying()`
- `facing_direction()`, `facing_yaw()`, `carry_slot` (nodo `CarrySlot`)
- Señales: `action_started(kind)`, `action_apex(kind)`, `action_finished(kind)`,
  `state_changed(prev, cur)`, `backpack_dropped(pickup)`

**Reglas:**

- Un bloqueo que llega durante una acción no la interrumpe: la acción termina y luego el
  jugador queda en `LOCKED`.
- `action_finished` se emite para *todas* las acciones. Si te suscribes con
  `CONNECT_ONE_SHOT`, hazlo justo después de arrancar tu acción, y filtra por `kind` si
  hay riesgo de que otra acción termine antes.
- El pickup de la mochila no es un caso especial: es una acción con `apex_fraction = 0.5`.
  El jugador reacciona a los kinds `pickup_backpack` y `drop_backpack` en `_fire_apex`.

### Añadir una acción nueva (p. ej. talar, beber, tocar un instrumento)

1. Crea `scenes/player/actions/<nombre>.tres` con script `PlayerAction`. Campos:
   - `kind`: identificador que llega en las señales.
   - `start_anim`, opcionales `idle_anim` (espera en bucle), `strike_anim` (golpe por
     pulsación con `strike()`), `end_anim` (salida).
   - `apex_fraction`: momento útil dentro de `start` (0..1). `1.0` = al terminar `start`.
   - `reverse`: reproduce `start` al revés (soltar = coger al revés). Con `reverse`, el
     apex salta cuando la posición baja por debajo de la fracción.
   - `cancel_on_move`: el stick termina la acción por `end` (agacharse sí, coger no).
2. Los nombres de clip se resuelven sin distinguir mayúsculas. Si el clip no existe,
   `start_action` devuelve `false` y avisa. El llamante decide qué hacer.
3. Quien la necesite la exporta y la arranca:

```gdscript
@export var chop_action: PlayerAction = preload("res://scenes/player/actions/chop.tres")

func interact_with(player: Player) -> void:
	if player.start_action(chop_action):
		player.action_apex.connect(_on_apex.bind(player), CONNECT_ONE_SHOT)
```

No hace falta tocar `player.gd`. Si la acción necesita lógica propia del jugador (como
mostrar la mochila), añade el `kind` al `match` de `_fire_apex`.

### Componentes del jugador (`scenes/player/components/`, `scenes/shared/`)

Nodos hijos en `player.tscn`, opcionales (si faltan, la función queda apagada):

- `CarrySlot` (`components/carry_slot.gd`): ancla entre las manos para objetos llevados.
  Reparenta el objeto aquí para cogerlo. `is_carrying()`.
- `Xray` (`components/xray_visibility.gd`): silueta cuando el personaje queda tapado.
- `Footsteps` (`shared/footsteps.gd`, `FootstepAudio`): pasos por cruce de altura de huesos.
  Acepta pares de huesos (un bípedo un par, un cuadrúpedo dos) y audio 2D o 3D. Lo usan
  jugador y perro; el dueño llama a `setup(skeleton)` y `tick(delta, locomotion, running)`.

`ModelMaterials` (`shared/model_materials.gd`) prepara los materiales de un GLB importado:
copia por instancia, nearest, sin sombreado, stencil para x-ray y contorno como
`next_pass`. Úsalo en cualquier personaje nuevo en vez de duplicar la lógica:

```gdscript
var setup := ModelMaterials.new()
setup.nearest = true
setup.with_outline(outline_color, 1.0)
setup.apply(model)
```

## Interacción: `InteractionZone` + `InteractionManager`

`scenes/ui/interaction_zone.gd`. Es un componente (`Area3D` hijo), no una clase base,
porque los interactuables tienen bases distintas (`StaticBody3D`, `Node3D`, `RigidBody3D`).
La zona detecta al jugador, cuelga el prompt "E · acción" del HUD, se registra en el
manager con una prioridad y reenvía la E a su `target` (por defecto el padre).

**El manager procesa la tecla `interact` una sola vez.** Ningún prop debe tener
`_unhandled_input` para la E ni buscar `/root/RetroRenderer` para el prompt.

### Añadir un objeto interactuable

```gdscript
var _zone: InteractionZone

func _ready() -> void:
	_zone = InteractionZone.new()
	_zone.radius = 1.2
	_zone.height = 0.5
	_zone.interact_priority = 2   # menor gana: mochila 0, pot 1, resto 2, en mano -1
	_zone.action_text = "Abrir"   # texto fijo, o implementa interaction_prompt()
	add_child(_zone)

# Los tres métodos son opcionales.
func can_interact(player: Player) -> bool: ...
func interaction_prompt(player: Player) -> String: ...
func interact_with(player: Player) -> void: ...
```

- `blocked_while_carrying` (por defecto `true`): con algo en brazos la zona no responde.
  El pot lo pone a `false` y decide él.
- `zone.refresh_prompt()` cuando cambie tu estado y el texto del prompt deba cambiar
  (p. ej. la hoguera al encenderse). El manager ya lo llama cuando cambia la zona actual.
- `zone.enabled = false` desregistra y oculta el prompt (objeto consumido).
- `zone.hold(player)` fuerza "en rango" sin área con prioridad -1: es lo que hace el pot
  mientras se lleva. `zone.release()` lo deshace.
- Si la zona no cuelga del nodo con la lógica (la mochila la cuelga del cuerpo rígido para
  que la siga), asigna `zone.target = self` antes de `add_child`.
- Señales: `player_entered`, `player_exited`, `interacted`.

### Capturar la E (diálogos, minijuegos)

Mientras una zona tiene la E capturada, la tecla llega a esa zona aunque el jugador no
esté en rango, haya otra con más prioridad o `can_interact` diga que no:

```gdscript
InteractionManager.capture(_zone, player)   # al empezar el diálogo / minijuego
InteractionManager.release(_zone)           # al terminar, siempre (también al cancelar)
```

`interact_with` recibe la pulsación y distingue por su propio estado (`_minigame_active`,
`is_talking()`).

## Estado del mundo y diálogo por datos

### `WorldState`

Flags globales. Los **props publican** el flag cuyo nombre tienen en un export; los **NPC
leen**. Nadie busca a nadie por el árbol.

```gdscript
WorldState.set_flag(&"door_open")          # true, emite flag_changed si cambia
WorldState.set_flag(&"door_open", false)
WorldState.set_flag(&"x", true, false)      # sin notificar (estado inicial en _ready)
WorldState.is_set(&"door_open")
WorldState.check("!door_open")             # condición en texto
```

Flags actuales: `fire_lit`, `pot_on_fire` (los publica `Campfire`, exports `lit_flag` /
`pot_flag`) y `pot_taken` (lo publica `PotCarryable`, export `taken_flag`, pegajoso).

Para un evento nuevo: añade un export `StringName` al prop con el nombre del flag y llama
a `WorldState.set_flag` donde ocurra. En `_ready` publica el estado inicial con
`notify = false` para no disparar reacciones al cargar.

### `DialogueEntry` (`scenes/npc/dialogue_entry.gd`)

Un bloque de diálogo y cuándo toca. El NPC tiene `dialogue: Array[DialogueEntry]`.

| Campo | Significado |
|---|---|
| `trigger` | `TALK` (E), `FLAG` (automático al activarse `trigger_flag`), `ROOM_EXIT` (despedida al salir de la habitación). |
| `requires` | Condiciones `"flag"` / `"!flag"`. Todas deben cumplirse. |
| `priority` | Entre los `TALK` disponibles gana el mayor (empate: el último de la lista). |
| `once` | Solo una vez por partida. |
| `shout` | Primera línea gritada + temblor de cámara. |
| `mark_new` | Al dispararse (FLAG) vuelve a salir el "!" hasta que el jugador hable. |
| `lines` | Texto. `*palabra*` ondula y sale en color. BBCode normal también pasa. |

Reglas de comportamiento:

- Las reacciones `FLAG` solo se dicen en voz alta si el jugador está a menos de
  `reaction_distance` y puede ver al NPC (misma habitación, o ambos fuera). Si no, se
  pierden salvo `mark_new`.
- `FLAG` avanza sola (`auto_line_time` por línea). `TALK` y `ROOM_EXIT` esperan la E.
- Mientras habla, el NPC bloquea al jugador con `lock()` y captura la E.

### Añadir una quest o un NPC con diálogo

1. Decide los flags. Si hace falta uno nuevo, publícalo desde el prop (ver arriba).
2. Crea los `.tres` en `scenes/npc/dialogue/` con script `DialogueEntry`. Convención de
   nombres: `<npc>_<qué>.tres` (`villager_fire_lit.tres`, `barn_farewell.tres`).
   Lo típico por NPC: un `TALK` por defecto sin condiciones, `TALK` condicionados con más
   prioridad para cada fase, `FLAG` para reaccionar a cada evento, y `ROOM_EXIT` si vive
   en un interior.
3. Añádelos al array `dialogue` de la escena del NPC (`npc.tscn` es el aldeano;
   `npc_barn_keeper.tscn` hereda de él y sustituye el array). Para un NPC nuevo, crea una
   escena heredada de `npc.tscn`.
4. No toques `npc.gd`. Si necesitas un disparador que no existe, añádelo al enum
   `Trigger` y a `current_entry` / `_on_flag_changed` / `try_farewell`.

Los ejemplos vivos son las dos quests actuales: aldeano (encender la hoguera y traer el
pot) y granjero (grita al robarle el pot, se disculpa, se despide).

## Terreno: caminos desde `Path3D` y hierba a parches

El suelo es un `PlaneMesh` con `ground_material.tres` (`ground/shaders/ground.gdshader`).
El shader pinta, sobre la tierra base: hierba a parches (ruido umbralizado con borde
punteado, dos tonos) y caminos desde una máscara, con el borde desgastado por ruido.

**Caminos.** `GroundPaths` (`scenes/environment/paths/ground_paths.gd`) cuelga de `World`
con `ground` apuntando a la malla del suelo. Cada hijo `GroundPath` (un `Path3D` con
`width` y `strength`) se rasteriza a una máscara en un `SubViewport` (anillos de brillo
creciente hacia el centro) que llega al shader como `path_mask` + `path_region`. Se
repinta solo al mover puntos en el editor.

- Para un camino nuevo: añade un `GroundPath` bajo `GroundPaths` y dibuja la curva. La
  altura de los puntos se ignora. Solo cuenta lo que cae dentro de `region_size`
  (256 m centrados en el nodo por defecto; muévelo o amplíalo si el pueblo crece).
- `GroundPaths.clearance_at(xz)` da la distancia al borde del camino más cercano
  (negativa dentro, `INF` a más de 8 m). Es una lectura sobre una rejilla de 0.5 m que se
  precalcula una vez por edición: barata aunque la llames cien mil veces al cargar.
  `ScatterWorld` lo usa con `paths` y `path_clearance` para no plantar árboles ni arbustos
  encima. Cualquier dispersión nueva debería hacer lo mismo. `GroundPaths.version` sube en
  cada repintado y sirve como clave de caché.
- El ruido de la hierba y del borde del camino es de gradiente con dominio deformado
  (`organic()` en el shader). No uses `vnoise` (ruido de valor) para umbralizar parches:
  deja bordes rectos alineados a los ejes.
- `pixel_art` en el material alterna entre el look de texels (snap a 4/m, ruido cuantizado,
  bordes duros y punteados) y un modo continuo (coordenadas sin snap, bordes con
  `smooth_edge`). Ahora está en `false` para comparar; el look retro original es `true`.
- Hierba: `grass_coverage`, `grass_scale` (tamaño de parche), `grass_edge_dither` (borde
  en matas), `grass_path_margin` (cuánto se aparta del camino). La hierba de blades del
  `ScatterWorld` está desactivada (`grass_enabled = false`): metía ruido.

**Vallas.** `Fence` (`scenes/props/fence/fence.gd`, escena `fence.tscn`) es un `Path3D`:
dibuja la curva y se reconstruye sola con postes cada `post_spacing`, `rails` travesaños
entre poste y poste, y colisión por tramo. `curve.closed = true` para un corral. Postes y
travesaños son un `MultiMesh` cada uno con el shader de madera del banco, que ahora acepta
una semilla por instancia en `INSTANCE_CUSTOM.x`. Para escalar instancias de un
`MultiMesh` a lo largo de su eje usa `basis * Basis.from_scale(...)`: `Basis.scaled()`
escala en ejes globales y estira en la dirección equivocada.

**Capturas de pantalla.** Headless no compila shaders. Para validar un shader o ver el
resultado sin abrir el editor:

```
SCREENSHOT_PATH=out.png SCREENSHOT_POS="5,-13" SCREENSHOT_ZOOM=14 godot --path . --resolution 1280x720 --quit-after 500 tests/screenshot.tscn
```

`SCREENSHOT_POS` coloca al jugador (y la cámara) en ese XZ, `SCREENSHOT_ZOOM` acerca la
cámara (menor = más cerca, 55 es el valor de juego); `SCREENSHOT_MASK=mask.png`
vuelca además la máscara de caminos. Abre una ventana unos segundos.

## Interiores

`Room` (`scenes/interiors/room.gd`) es una escena heredada de `room.tscn` con `room_id`
único. Un edificio (`Molino`) la instancia, y su `InteractionZone` en la puerta llama a
`room.enter(player)` / `room.exit(player)`. "Estar dentro" es lógico y vale para NPCs; el
cambio de vista solo se aplica al jugador. Los NPC dentro de una `Room` solo se ven,
hablan y reaccionan si el jugador está en esa habitación. Al salir, el edificio pregunta
a los NPC `try_farewell(player)` y retiene la salida hasta que el diálogo termina.

## Perro (`scenes/companion/dog.gd`)

Máquina de estados con enum (`FOLLOW`, `HANG_AROUND`, `GO_SIT`, `SIT`, `GO_STAY`, `STAY`).
`stay_at(pos)` / `release()` lo dejan sentado en un sitio. Lee `is_crouching()` /
`is_sitting()` del jugador para venir a sentarse. Deuda conocida: `_sit_transition` y
`_fire_focus` son pseudo-estados fuera del enum; si añades comportamientos, conviértelos
en estados reales antes.

## Convenciones

- Paleta: 8 colores en `assets/textures/palette.png`. Props y shaders nuevos la usan.
- Props procedurales: se construyen en `_ready`/`_rebuild` con `@tool`, y los exports con
  setter reconstruyen en el editor. Cada prop en `scenes/props/<nombre>/` con sus shaders
  en `shaders/`.
- Capas de física: 1 mundo, 2 jugador, 4 props, 8 áreas oclusoras de follaje. Las zonas
  de interacción usan `collision_mask = 2`.
- Comentarios en español en el código nuevo; `##` para doc de exports y funciones.
- Commits: separa reorganizaciones de archivos de los cambios de lógica.
