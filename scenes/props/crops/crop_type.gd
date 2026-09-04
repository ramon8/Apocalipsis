@tool
class_name CropType
extends Resource
## Un cultivo: sus sprites por fase de crecimiento y como se planta. Las texturas son
## recortes con alpha (como bush.png), base en el borde inferior, y se dibujan como dos
## quads cruzados con el shader de viento. Crea un .tres por cultivo (trigo, calabaza...).

@export var crop_name := "Wheat"
## Sprites de brote a maduro, en orden. Con 3 texturas hay 3 fases.
@export var stage_textures: Array[Texture2D] = []
## Altura (m) del sprite maduro; las fases anteriores la escalan con stage_heights.
@export_range(0.1, 3.0, 0.05) var height := 0.9
## Fraccion de `height` por fase (misma longitud que stage_textures; si falta, lineal).
@export var stage_heights: PackedFloat32Array = [0.4, 0.7, 1.0]
## Ancho del sprite respecto a su alto (relacion de aspecto de la textura).
@export_range(0.2, 2.0, 0.05) var width_ratio := 0.67
## Separacion entre hileras y entre plantas de una hilera (m).
@export_range(0.2, 3.0, 0.05) var row_spacing := 0.8
@export_range(0.15, 3.0, 0.05) var plant_spacing := 0.45
## Respuesta al viento (shader wind_cutout).
@export_range(0.0, 3.0, 0.05) var wind_influence := 1.2
@export_range(0.0, 1.0, 0.01) var sway := 0.22
@export_range(0.0, 0.5, 0.01) var flutter := 0.08


func stage_count() -> int:
	return stage_textures.size()


## Fase (indice) para un crecimiento 0..1.
func stage_for(growth: float) -> int:
	var n := stage_count()
	if n <= 0:
		return -1
	return clampi(int(floor(clampf(growth, 0.0, 0.9999) * n)), 0, n - 1)


func stage_height(stage: int) -> float:
	if stage < 0:
		return height
	if stage < stage_heights.size():
		return height * stage_heights[stage]
	var n := maxi(stage_count(), 1)
	return height * float(stage + 1) / float(n)
