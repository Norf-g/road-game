class_name ModelFactory
extends RefCounted
## Процедурные low-poly модели. Стиль задаётся параметрами (цвет, размеры), а не файлами моделей.

## Отступ корпуса места назначения от края клеток по внешнему контуру.
const BODY_INSET := 0.06
const BODY_HEIGHT := 0.5
## Ширина светлого канта по краю крыши места назначения.
const ROOF_RIM := 0.13
const STRIP_LENGTH := 1.2
const STRIP_WIDTH := 0.2

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


## Место назначения по образцу «завода»: цельный корпус из клеток cells (центры клеток относительно
## начала модели, по X и Z) — крыша цвета здания со светлым кантом по краю. Если задан details:
## - chimneys: две трубы (центры по X и Z);
## - strip_center, strip_axis, windows: полоса из windows окон вдоль оси strip_axis (к дальнему концу);
## - door, door_out: ворота в стене над парковкой и направление к парковке.
## Окна — индикатор запаса терпения здания: их материалы — в meta «windows», окно 0 у дальнего
## конца гаснет последним.
static func destination(color_index: int, cells: Array[Vector2], details := {}) -> Node3D:
	var color := Palette.building(color_index)
	var root := Node3D.new()
	_cell_boxes(root, cells, BODY_INSET, 0.0, BODY_HEIGHT - 0.02, color.darkened(0.08))
	_cell_boxes(root, cells, BODY_INSET, BODY_HEIGHT - 0.02, 0.02, color.lightened(0.3))
	_cell_boxes(root, cells, ROOF_RIM, BODY_HEIGHT, 0.02, color)
	var windows: Array[StandardMaterial3D] = []
	if not details.is_empty():
		for chimney: Vector2 in details["chimneys"]:
			_add_chimney(root, chimney, color)
		windows = _add_window_strip(root, details["strip_center"], details["strip_axis"], details["windows"])
		_add_loading_door(root, details["door"], details["door_out"])
	root.set_meta("windows", windows)
	return root


## Труба на крыше: светлое основание, цилиндр и тёмное отверстие сверху.
static func _add_chimney(root: Node3D, at: Vector2, color: Color) -> void:
	var top := BODY_HEIGHT + 0.02
	for part in [
		_cylinder(0.26, 0.03, color.lightened(0.3), top),
		_cylinder(0.2, 0.3, color.lightened(0.12), top),
		_cylinder(0.13, 0.01, color.darkened(0.6), top + 0.3),
	]:
		part.position.x = at.x
		part.position.z = at.y
		root.add_child(part)


## Полоса окон в светлой раме вдоль оси axis; возвращает материалы окон (от дальнего конца к ближнему).
static func _add_window_strip(root: Node3D, center: Vector2, axis: Vector2, count: int) -> Array[StandardMaterial3D]:
	var top := BODY_HEIGHT + 0.02
	var along_x := absf(axis.x) > 0.5
	var frame_size := Vector2(STRIP_LENGTH + 0.08, STRIP_WIDTH + 0.08)
	var frame := _box(Vector3(frame_size.x if along_x else frame_size.y, 0.02, frame_size.y if along_x else frame_size.x),
		Palette.WINDOW_FRAME, top)
	frame.position = Vector3(center.x, frame.position.y, center.y)
	root.add_child(frame)
	var materials: Array[StandardMaterial3D] = []
	var step := STRIP_LENGTH / count
	for i in count:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Palette.WINDOW_LIT
		var length := step - 0.04
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length if along_x else STRIP_WIDTH, 0.02, STRIP_WIDTH if along_x else length)
		var window := MeshInstance3D.new()
		window.mesh = mesh
		window.material_override = material
		var offset := axis * (STRIP_LENGTH / 2 - step * (i + 0.5))
		window.position = Vector3(center.x + offset.x, top + 0.02, center.y + offset.y)
		root.add_child(window)
		materials.append(material)
	return materials


## Ворота в стене над парковкой: тёмный проём, светлый козырёк и жёлтые столбики по бокам.
static func _add_loading_door(root: Node3D, at: Vector2, out: Vector2) -> void:
	var across := Vector2(-out.y, out.x)
	var along_x := absf(out.x) > 0.5
	var door := _box(Vector3(0.06 if along_x else 0.5, 0.28, 0.5 if along_x else 0.06), Palette.DOOR, 0.0)
	var awning := _box(Vector3(0.14 if along_x else 0.62, 0.04, 0.62 if along_x else 0.14), Palette.WINDOW_FRAME, 0.3)
	for part: MeshInstance3D in [door, awning]:
		var shift := at + out * (0.03 if part == door else 0.07)
		part.position.x = shift.x
		part.position.z = shift.y
		root.add_child(part)
	for side: float in [-1.0, 1.0]:
		var post := _cylinder(0.035, 0.2, Palette.ACCENT, 0.0)
		var where := at + out * 0.12 + across * 0.31 * side
		post.position.x = where.x
		post.position.z = where.y
		root.add_child(post)


## Ступенька по клеткам: над каждой клеткой коробка от bottom высотой height. Со стороны соседней
## клетки фигуры коробка доходит до края клетки (тела смыкаются), с внешних сторон — отступ inset.
static func _cell_boxes(root: Node3D, cells: Array[Vector2], inset: float, bottom: float, height: float, color: Color) -> void:
	for cell in cells:
		var extent := _cell_extent(cell, cells, inset)
		var box := _box(Vector3(extent.size.x, height, extent.size.y), color, bottom)
		box.position.x = extent.get_center().x
		box.position.z = extent.get_center().y
		root.add_child(box)


## Прямоугольник клетки по X и Z с отступом inset только по внешнему контуру фигуры.
static func _cell_extent(cell: Vector2, cells: Array[Vector2], inset: float) -> Rect2:
	var left := cell.x - 0.5 + (0.0 if _has_cell(cells, cell + Vector2.LEFT) else inset)
	var right := cell.x + 0.5 - (0.0 if _has_cell(cells, cell + Vector2.RIGHT) else inset)
	var top := cell.y - 0.5 + (0.0 if _has_cell(cells, cell + Vector2.UP) else inset)
	var bottom := cell.y + 0.5 - (0.0 if _has_cell(cells, cell + Vector2.DOWN) else inset)
	return Rect2(left, top, right - left, bottom - top)


static func _has_cell(cells: Array[Vector2], cell: Vector2) -> bool:
	for other in cells:
		if other.is_equal_approx(cell):
			return true
	return false


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


## Парковка места назначения: площадка цвета дороги с разметкой мест. Разметка идёт вдоль оси Z —
## отображение поворачивает парковку разметкой к подъезду.
static func parking() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(1.0, 0.03, 1.0), Palette.ROAD, 0.02))
	for x in [-0.3, 0.0, 0.3]:
		var line := _box(Vector3(0.05, 0.01, 0.62), Palette.PARKING_LINE, 0.05)
		line.position.x = x
		line.position.z = -0.08
		root.add_child(line)
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
