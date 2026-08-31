class_name RetroProfile
extends Resource
## Preset completo del pipeline retro. Guarda uno por look (ver res://retro/profiles/).
## RetroRenderer.apply_profile() vuelca estos valores al shader de post y a los
## uniforms globales del material PSX. Todo es editable en el inspector y en runtime.

enum Resolution { RES_320x180, RES_480x270, RES_640x360, CUSTOM }
enum DitherSpace { SCREEN, FRAMEBUFFER }
enum QuantizeMode { LEVELS, PALETTE }

@export_group("Resolución interna")
@export var resolution: Resolution = Resolution.RES_640x360
## Sólo se usa si resolution == CUSTOM.
@export var custom_resolution := Vector2i(640, 360)

@export_group("Pixelación")
## Bloques de N x N píxeles internos en la imagen final. 1 = sólo la resolución interna
## decide. 2-4 = píxeles más gordos manteniendo el detalle de render (y la UI del juego).
@export_range(1, 8, 1) var pixel_size := 1

@export_group("Dither (Bayer 8x8)")
@export var dither_enabled := true
@export_range(0.0, 1.0, 0.01) var dither_strength := 0.35
## SCREEN: patrón anclado al píxel del viewport de post. FRAMEBUFFER: anclado al píxel interno.
@export var dither_space: DitherSpace = DitherSpace.FRAMEBUFFER
## Amplitud del dither en unidades de color. 0 = automático (un escalón de cuantización).
@export_range(0.0, 0.5, 0.005) var dither_spread := 0.0

@export_group("Cuantización")
@export var quantize_enabled := true
@export var quantize_mode: QuantizeMode = QuantizeMode.LEVELS
@export_range(0.0, 1.0, 0.01) var quantize_strength := 1.0
## Niveles por canal (modo LEVELS). 32 ~ 15 bits (PSX), 8 ~ muy crudo.
@export_range(2, 64, 1) var color_levels := 32
## Textura Nx1 con la paleta (modo PALETTE). Ver res://retro/palettes/.
@export var palette: Texture2D

@export_group("Grano")
@export var grain_enabled := true
@export_range(0.0, 1.0, 0.005) var grain_strength := 0.03
@export_range(0.0, 60.0, 0.5) var grain_speed := 8.0

@export_group("Viñeta")
@export var vignette_enabled := true
@export_range(0.0, 1.0, 0.01) var vignette_strength := 0.25
@export_range(0.0, 1.5, 0.01) var vignette_radius := 0.75
@export_range(0.01, 1.0, 0.01) var vignette_softness := 0.6

@export_group("Geometría PSX (material psx_base)")
## 0 = sin snapping, 1 = vértices clavados a la rejilla de la resolución interna.
@export_range(0.0, 1.0, 0.01) var vertex_snap_strength := 0.35
## 0 = texturas con corrección de perspectiva, 1 = mapeo afín puro (wobble PSX).
@export_range(0.0, 1.0, 0.01) var affine_strength := 0.4
@export var fog_enabled := true
@export var fog_color := Color(0.45, 0.48, 0.55)
## Densidad de la niebla exponencial: f = 1 - e^(-density * distancia).
@export_range(0.0, 0.5, 0.001) var fog_density := 0.03


func get_internal_resolution() -> Vector2i:
	match resolution:
		Resolution.RES_320x180:
			return Vector2i(320, 180)
		Resolution.RES_480x270:
			return Vector2i(480, 270)
		Resolution.RES_640x360:
			return Vector2i(640, 360)
	return Vector2i(maxi(custom_resolution.x, 16), maxi(custom_resolution.y, 16))


func get_palette_size() -> int:
	return palette.get_width() if palette else 1
