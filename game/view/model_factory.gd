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


## Дом на одну клетку: коробка, двускатная крыша и дверь. Дверь смотрит в сторону +Z —
## отображение поворачивает дом дверью к его выезду.
static func house(color: Color) -> Node3D:
	var root := Node3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.6, 0.35, 0.6)
	root.add_child(_part(body_mesh, color, body_mesh.size.y / 2))

	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.18, 0.22, 0.04)
	var door := _part(door_mesh, Palette.ROAD, door_mesh.size.y / 2)
	door.position.z = body_mesh.size.z / 2 + door_mesh.size.z / 2
	root.add_child(door)

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


## Въезд места назначения: тёмный проём, выступающий из угла здания.
static func gate() -> Node3D:
	var root := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.36, 0.3, 0.36)
	root.add_child(_part(mesh, Palette.ROAD, mesh.size.y / 2))
	return root


## Светофор: столбик в углу перекрёстка с жёлтым фонарём.
static func traffic_light() -> Node3D:
	var root := Node3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.04
	post_mesh.bottom_radius = 0.04
	post_mesh.height = 0.45
	var post := _part(post_mesh, Palette.LIGHT_POST, post_mesh.height / 2)
	post.position += Vector3(0.36, 0.0, 0.36)
	root.add_child(post)
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.12, 0.16, 0.12)
	var lamp := _part(lamp_mesh, Palette.LIGHT_LAMP, post_mesh.height + lamp_mesh.size.y / 2)
	lamp.position += Vector3(0.36, 0.0, 0.36)
	root.add_child(lamp)
	return root


## Развязка: кольцо дороги вокруг зелёного островка.
static func roundabout() -> Node3D:
	var root := Node3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.42
	ring_mesh.bottom_radius = 0.42
	ring_mesh.height = 0.03
	root.add_child(_part(ring_mesh, Palette.ROUNDABOUT_RING, 0.03))
	var island_mesh := CylinderMesh.new()
	island_mesh.top_radius = 0.18
	island_mesh.bottom_radius = 0.18
	island_mesh.height = 0.08
	root.add_child(_part(island_mesh, Palette.ROUNDABOUT_ISLAND, 0.06))
	return root


static func _part(mesh: Mesh, color: Color, height: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = flat_material(color)
	part.position.y = height
	return part
