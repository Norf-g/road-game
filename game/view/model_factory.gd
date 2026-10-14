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


## Место назначения на 2×2 клетки. У каждого цвета свой силуэт, чтобы здания различались
## не только цветом. Высота крыши (куда ставятся метки заказов) — в meta «roof_height».
static func destination(color_index: int) -> Node3D:
	var color := Palette.building(color_index)
	var root := Node3D.new()
	var roof := 0.5
	match color_index % 6:
		0:  # контора: плоская крыша с надстройкой
			root.add_child(_box(Vector3(1.7, 0.5, 1.7), color, 0.0))
			root.add_child(_box(Vector3(1.3, 0.08, 1.3), color.lightened(0.3), 0.5))
			roof = 0.58
		1:  # ступенчатое здание
			root.add_child(_box(Vector3(1.7, 0.35, 1.7), color, 0.0))
			root.add_child(_box(Vector3(1.15, 0.3, 1.15), color.lightened(0.15), 0.35))
			roof = 0.65
		2:  # завод с трубой
			root.add_child(_box(Vector3(1.7, 0.45, 1.7), color, 0.0))
			var chimney := _cylinder(0.14, 0.55, color.darkened(0.25), 0.45)
			chimney.position += Vector3(0.55, 0.0, -0.55)
			root.add_child(chimney)
			roof = 0.45
		3:  # мастерская с пилообразной крышей
			root.add_child(_box(Vector3(1.7, 0.35, 1.7), color, 0.0))
			for z in [-0.42, 0.42]:
				var tooth := PrismMesh.new()
				tooth.left_to_right = 0.0
				tooth.size = Vector3(1.7, 0.3, 0.84)
				var part := _part(tooth, color.lightened(0.2), 0.35 + tooth.size.y / 2)
				part.rotation.y = PI / 2
				part.position.z = z
				root.add_child(part)
			roof = 0.65
		4:  # круглое здание
			root.add_child(_cylinder(0.85, 0.5, color, 0.0))
			root.add_child(_cylinder(0.6, 0.06, color.lightened(0.3), 0.5))
			roof = 0.56
		5:  # здание с куполом
			root.add_child(_box(Vector3(1.7, 0.4, 1.7), color, 0.0))
			var dome := SphereMesh.new()
			dome.radius = 0.55
			dome.height = 0.55
			dome.is_hemisphere = true
			dome.radial_segments = 12
			dome.rings = 4
			root.add_child(_part(dome, color.lightened(0.25), 0.4))
			roof = 0.95
	root.set_meta("roof_height", roof)
	return root


## Дерево: ствол и крона из нескольких граней.
static func tree_trunk_mesh() -> Mesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.05
	trunk.bottom_radius = 0.06
	trunk.height = 0.24
	trunk.radial_segments = 6
	return trunk


static func tree_crown_mesh() -> Mesh:
	var crown := SphereMesh.new()
	crown.radius = 0.3
	crown.height = 0.5
	crown.radial_segments = 7
	crown.rings = 3
	return crown


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


## Коробка, стоящая на высоте bottom.
static func _box(size: Vector3, color: Color, bottom: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(mesh, color, bottom + size.y / 2)


## Цилиндр, стоящий на высоте bottom.
static func _cylinder(radius: float, height: float, color: Color, bottom: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return _part(mesh, color, bottom + height / 2)


static func _part(mesh: Mesh, color: Color, height: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = flat_material(color)
	part.position.y = height
	return part
