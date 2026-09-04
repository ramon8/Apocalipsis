class_name ModelMaterials
extends RefCounted
## Preparacion comun de los materiales de un modelo importado (glTF):
##  - copia por instancia (no se toca el recurso compartido del import)
##  - filtro nearest (glTF viene con lineal + mipmaps, que emborrona los texels)
##  - opcional: sin sombreado, escritura de stencil (para la silueta x-ray)
##  - contorno de 1 px como next_pass (outline.gdshader)
## Uso: ModelMaterials.new().with_outline(color).apply(model)

const OUTLINE_SHADER := preload("res://scenes/player/shaders/outline.gdshader")

var nearest := true
var unshaded := false
## Escribe stencil (referencia 1) para que el overlay x-ray salte la auto-oclusion.
var stencil := false
var outline := false
var outline_color := Color(0.03, 0.02, 0.02)
var outline_width_px := 1.0
## Mallas (por nombre) que se ocultan en vez de prepararse.
var hidden_mesh_names: PackedStringArray = []


func with_outline(color: Color, width_px := 1.0) -> ModelMaterials:
	outline = true
	outline_color = color
	outline_width_px = width_px
	return self


## Material de contorno listo para usar como next_pass.
static func make_outline(color: Color, width_px := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("width_px", width_px)
	return m


## Copia configurada de un material base segun las opciones de esta instancia.
func prepare(mat: BaseMaterial3D) -> BaseMaterial3D:
	var copy := mat.duplicate() as BaseMaterial3D
	if nearest:
		copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if unshaded:
		copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if stencil:
		copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		copy.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		copy.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		copy.stencil_reference = 1
	if outline:
		copy.next_pass = make_outline(outline_color, outline_width_px)
	return copy


## Recorre todas las MeshInstance3D bajo `root` (incluida) y sustituye sus BaseMaterial3D.
func apply(root: Node) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if hidden_mesh_names.has(mi.name):
			mi.visible = false
			continue
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat is BaseMaterial3D:
				mi.set_surface_override_material(i, prepare(mat))
