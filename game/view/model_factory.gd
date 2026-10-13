class_name ModelFactory
extends RefCounted
## Процедурные low-poly модели. Стиль задаётся параметрами (цвет, размеры), а не файлами моделей.

static var _materials: Dictionary = {}


static func flat_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[color] = material
	return _materials[color]


## Дом на одну клетку: коробка и двускатная крыша.
static func house(color: Color) -> Node3D:
	var root := Node3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.6, 0.35, 0.6)
	root.add_child(_part(body_mesh, color, body_mesh.size.y / 2))

	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(0.7, 0.25, 0.6)
	root.add_child(_part(roof_mesh, color.darkened(0.25), body_mesh.size.y + roof_mesh.size.y / 2))
	return root


## Место назначения на 2×2 клетки: широкое здание с плоской крышей.
static func destination(color: Color) -> Node3D:
	var root := Node3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.7, 0.5, 1.7)
	root.add_child(_part(body_mesh, color, body_mesh.size.y / 2))

	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(1.3, 0.08, 1.3)
	root.add_child(_part(top_mesh, color.lightened(0.3), body_mesh.size.y + top_mesh.size.y / 2))
	return root


static func _part(mesh: Mesh, color: Color, height: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = flat_material(color)
	part.position.y = height
	return part
