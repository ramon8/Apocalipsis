# retro/ — pipeline de render retro

Todo vive en `res://retro/`. Fuera de la carpeta sólo hay tres cosas en `project.godot`:
el autoload `RetroRenderer`, los ajustes de stretch (`viewport` / `keep`, 640x360) y
los `[shader_globals]` que usa `psx_base.gdshader`.

## Cómo funciona

```
Window (stretch=viewport, content_scale_size = resolución interna, upscale nearest)
└─ RetroRenderer (autoload)
   ├─ GameViewport : SubViewport (resolución interna)  ← aquí se reparenta la escena actual
   └─ Post : ColorRect a pantalla completa con retro_post.gdshader (UN pase)
```

- `RetroRenderer.retro_enabled` (bool): el flag global. En `false` devuelve la escena al
  root, oculta el post, apaga el SubViewport, restaura el escalado de ventana estándar y
  pone a 0 los globales del material PSX (snap, afín, niebla). Render estándar, sin artefactos.
- `RetroRenderer.profile` (`RetroProfile`): preset activo. `RetroRenderer.apply_profile(p)`
  aplica otro en caliente.
- `RetroRenderer.set_dither_offset(Vector2)`: desplaza el patrón de dither en píxeles
  internos (para clavarlo al mundo con cámaras 2D/orto).
- `RetroRenderer.integer_scaling`: escalado sólo por enteros (píxeles perfectos, bandas negras).

Cambios de escena (`get_tree().change_scene_to_*`) funcionan: el autoload captura la
nueva `current_scene` cuando entra en el root y libera la anterior. La UI del juego
también pasa por el post y se renderiza a resolución interna (inherente a `stretch=viewport`).

**Limitación conocida:** `SceneTree.current_scene` sólo admite hijos del root, así que
mientras retro está activo `get_tree().current_scene` es `null` y
`get_tree().reload_current_scene()` falla. Usa `RetroRenderer.current_scene` y
`RetroRenderer.reload_current_scene()`, que funcionan en ambos modos.

No añadas otra capa de pixelación (SubViewportContainer con `stretch_shrink`, etc.) en las
escenas: se pixelaría dos veces. La resolución se controla sólo desde el `RetroProfile`.

Consejo PSX: el mapeo afín deforma más cuanto más grandes son los triángulos. Subdivide
suelos y paredes grandes (`PlaneMesh.subdivide_*`), como hacían los juegos de la época.

**F1 en el juego real** abre el mismo panel de tuneo sobre la escena que esté corriendo
(`RetroRenderer.tuning_panel_action`): libera el ratón y pausa el input del juego mientras
está abierto. "Guardar" escribe `profiles/custom.tres` con lo que veas en pantalla.

`demo.tscn` es la herramienta de tuneo aislada: **TAB** panel, **ESPACIO** parar/orbitar cámara,
**R** retro on/off, **1/2** presets. El panel se genera de los `@export` de `RetroProfile`,
así que cualquier parámetro nuevo aparece solo. "Guardar" escribe `profiles/custom.tres`.

## Parámetros de `RetroProfile`

### Resolución interna
| Parámetro | Qué hace |
|---|---|
| `resolution` | Preset 320x180 / 480x270 / 640x360 / CUSTOM. Cambia `SubViewport.size` y `content_scale_size`. |
| `custom_resolution` | Sólo con CUSTOM. |

### Pixelación
| Parámetro | Qué hace |
|---|---|
| `pixel_size` | Bloques de N×N píxeles internos en la imagen final (paso 0 del post). 1 = la pixelación la da sólo `resolution`. 2–4 = píxeles más gordos sin bajar la resolución de render: geometría/sombras/UI del juego siguen a resolución interna, sólo la imagen se agrupa. El dither y el grano se alinean al bloque. El HUD (`RetroRenderer.hud_layer`) no se ve afectado. |

### Dither (Bayer 8x8, se aplica ANTES de cuantizar)
| Parámetro | Qué hace |
|---|---|
| `dither_enabled` | Bypass. |
| `dither_strength` | 0..1: cuánto del umbral Bayer se suma al color antes de redondear. 1 = dither completo. |
| `dither_space` | `SCREEN` (píxel del viewport de post) o `FRAMEBUFFER` (píxel de la resolución interna). Con `stretch=viewport` coinciden; ver comentario en el shader para el trade-off. |
| `dither_spread` | Amplitud en unidades de color. 0 = auto (un escalón de cuantización; 1/8 en modo paleta). Súbelo para un dither más visible que el propio banding. |

### Cuantización
| Parámetro | Qué hace |
|---|---|
| `quantize_enabled` | Bypass. |
| `quantize_mode` | `LEVELS`: N niveles por canal. `PALETTE`: color más cercano en la textura de paleta (Nx1). |
| `quantize_strength` | Mezcla entre color original y cuantizado. |
| `color_levels` | Niveles por canal (modo LEVELS). 32 ≈ 15 bits (PSX real), 16 notable, 8 muy crudo, 4 posterización extrema. |
| `palette` | Textura Nx1 (`palettes/`). El tamaño se lee de la textura. |

### Grano
| Parámetro | Qué hace |
|---|---|
| `grain_enabled` | Bypass. |
| `grain_strength` | Amplitud del ruido (±strength/2). 0.03 apenas se nota, 0.1 es "VHS". |
| `grain_speed` | Cambios de patrón por segundo. 8 = parpadeo lento, 24 = cine, 60 = ruido de TV. |

### Viñeta
| Parámetro | Qué hace |
|---|---|
| `vignette_enabled` | Bypass. |
| `vignette_strength` | Oscurecimiento máximo en las esquinas. |
| `vignette_radius` | Distancia (0 centro, 1 borde corto) donde empieza. |
| `vignette_softness` | Anchura del degradado. |

### Geometría PSX (globales usados por `psx_base.gdshader`)
| Parámetro | Qué hace |
|---|---|
| `vertex_snap_strength` | 0 = off, 1 = vértices clavados a la rejilla de la resolución interna (bailan al mover la cámara). |
| `affine_strength` | 0 = perspectiva correcta, 1 = mapeo afín puro (wobble de texturas). Se nota más en polígonos grandes vistos en escorzo (el suelo). |
| `fog_enabled` / `fog_color` / `fog_density` | Niebla exponencial `1 - e^(-density·d)`. 0.03 ≈ 50% a 23 m; 0.08 ≈ 50% a 9 m. |

Por material (`psx_base.gdshader`): `albedo_tex` (nearest, sin mipmaps), `albedo_color`,
`uv_scale`, y `snap_multiplier` / `affine_multiplier` / `fog_multiplier` para excluir o
exagerar objetos concretos (0 = ese objeto no lo sufre).

## De "sutil" a "crudo"
Orden de impacto visual, de mayor a menor:

1. **`resolution`** 640x360 → 480x270 → 320x180. Es lo que más cambia el carácter.
2. **`vertex_snap_strength`** 0.3 → 1.0 y **`affine_strength`** 0.4 → 1.0: el "temblor" PSX.
3. **`color_levels`** 32 → 8, o pasar a `PALETTE` con `pico8_16.png`.
4. **`dither_strength`** a 1.0 (y `dither_spread` 0.1–0.2 si quieres que se vea el patrón).
5. **`fog_density`** 0.03 → 0.08 con un color oscuro: recorta el fondo como en PSX.
6. `grain_strength` y `vignette_strength`: cosmético, subir con moderación.

Los presets `profiles/suave.tres` y `profiles/psx_crudo.tres` son exactamente esos dos
extremos. `profiles/crisp.tres` (el activo por defecto) es `suave` sin dither ni grano:
píxeles 100% nítidos; el dither y el grano añaden ruido por píxel que en los bordes se
percibe como antialiasing.

## Rendimiento
Un SubViewport + un ColorRect: un único pase de post a resolución interna (≤ 640x360 =
230k píxeles). El bucle de paleta cuesta `palette_size` lecturas por píxel; con paletas
≤ 64 colores es irrelevante. No se encadenan viewports.
