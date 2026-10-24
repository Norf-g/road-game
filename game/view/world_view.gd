class_name WorldView
extends Node3D
## Показывает партию: землю и реку, туман за пределами видимой части карты, дороги, мосты и шоссе,
## светофоры и развязки, здания, деревья, машины, заказы и таймеры переполнения, «Zzz» над домами
## без пути к месту назначения и красное мигание мест назначения в тревоге.
## Только читает состояние симуляции и ничего в нём не меняет.

const ROAD_WIDTH := 0.5
const ROAD_HEIGHT := 0.02
## Сколько отрезков в круге на стыке дорог.
const DISC_SEGMENTS := 24
const FOG_HEIGHT := 0.04
## Эстакада выше любой крыши: дома ~0.6, купол места назначения ~0.95.
const MOTORWAY_HEIGHT := 1.2
## Длина съезда шоссе с земли на эстакаду.
const MOTORWAY_RAMP := 1.6
const CAR_SIZE := Vector3(0.2, 0.12, 0.3)
const SLEEP_HEIGHT := 1.15
const BLINK_HZ := 1.5
## Доля свободных клеток с деревом. Деревья — только украшение: исчезают под дорогами и зданиями.
const TREE_DENSITY := 0.07
const POP_IN_SECONDS := 0.35

var _sim: Simulation
var _roads := MeshInstance3D.new()
var _road_version := -1
var _junctions := Node3D.new()
var _fog := MeshInstance3D.new()
var _fog_area := Rect2i()
var _preview := MeshInstance3D.new()
## Пульсирующее кольцо вокруг выбранного для правки конца шоссе.
var _end_marker := MeshInstance3D.new()
var _cars := MultiMeshInstance3D.new()
var _houses_shown := 0
var _house_models: Array[Node3D] = []
var _sleep_labels: Array[Label3D] = []
var _served_key := []
var _served: Array[bool] = []
## Полупрозрачный красный слой поверх модели каждого места назначения — для мигания.
var _warning_overlays: Array[StandardMaterial3D] = []
var _destinations_shown := 0
## Материалы окон каждого места назначения — индикатор запаса терпения.
var _windows: Array = []  # для каждого места назначения — Array[StandardMaterial3D]
var _tree_trunks := MultiMeshInstance3D.new()
var _tree_crowns := MultiMeshInstance3D.new()
var _trees_key := []


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func setup(sim: Simulation) -> void:
	_sim = sim
	_build_terrain()
	for flat: MeshInstance3D in [_roads, _fog, _preview]:
		flat.material_override = _vertex_color_material()
		flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flat)
	add_child(_junctions)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.3
	ring.outer_radius = 0.42
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Palette.ACCENT
	ring.material = ring_material
	_end_marker.mesh = ring
	_end_marker.visible = false
	add_child(_end_marker)
	_tree_trunks.multimesh = _tree_multimesh(ModelFactory.tree_trunk_mesh(), Palette.TREE_TRUNK)
	_tree_crowns.multimesh = _tree_multimesh(ModelFactory.tree_crown_mesh(), Palette.TREE_CROWN)
	add_child(_tree_trunks)
	add_child(_tree_crowns)
	_build_cars()


func _process(_delta: float) -> void:
	var network := _sim.network
	if network.version != _road_version:
		_road_version = network.version
		_roads.mesh = _road_mesh()
		_rebuild_junctions()
		_turn_houses_to_exits()
	if network.bounds != _fog_area:
		_fog_area = network.bounds
		_fog.mesh = _fog_mesh()
	_show_new_buildings()
	if _end_marker.visible:
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)
		_end_marker.scale = Vector3(pulse, 1.0, pulse)
	_update_trees()
	_update_cars()
	_update_destinations()
	_update_sleep_labels()


## Предпросмотр шоссе от from до to; valid — можно ли его построить.
func show_motorway_preview(from: Vector2i, to: Vector2i, valid: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var color := Palette.PREVIEW_OK if valid else Palette.PREVIEW_BAD
	_add_motorway(st, from, to, color, 0.02)
	_preview.mesh = st.commit()
	_preview.visible = true


func hide_motorway_preview() -> void:
	_preview.visible = false


## Подсвечивает выбранный для правки конец шоссе (Vector2i) или снимает подсветку (null).
func show_end_selection(cell: Variant) -> void:
	_end_marker.visible = cell != null
	if cell != null:
		_end_marker.position = cell_center(cell) + Vector3.UP * 0.06


func _build_terrain() -> void:
	var grid := _sim.network.grid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_rect(st, Vector3.ZERO, Vector3(grid.size.x, 0.0, grid.size.y), Palette.LAND)
	for y in grid.size.y:
		for x in grid.size.x:
			if _sim.network.is_water(Vector2i(x, y)):
				_add_rect(st, Vector3(x, 0.005, y), Vector3(x + 1, 0.005, y + 1), Palette.WATER)
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.material_override = _vertex_color_material()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)

	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(grid.size.x + 1):
		lines.surface_add_vertex(Vector3(x, 0.01, 0.0))
		lines.surface_add_vertex(Vector3(x, 0.01, grid.size.y))
	for y in range(grid.size.y + 1):
		lines.surface_add_vertex(Vector3(0.0, 0.01, y))
		lines.surface_add_vertex(Vector3(grid.size.x, 0.01, y))
	lines.surface_end()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Palette.GRID
	var grid_lines := MeshInstance3D.new()
	grid_lines.mesh = lines
	grid_lines.material_override = grid_material
	grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_lines)


## Туман: всё, что вне видимой части карты, закрыто цветом фона.
func _fog_mesh() -> ArrayMesh:
	var size := Vector2(_sim.network.grid.size)
	var area := Rect2(_fog_area)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := FOG_HEIGHT
	for band: Rect2 in [
		Rect2(0, 0, size.x, area.position.y),
		Rect2(0, area.end.y, size.x, size.y - area.end.y),
		Rect2(0, area.position.y, area.position.x, area.size.y),
		Rect2(area.end.x, area.position.y, size.x - area.end.x, area.size.y),
	]:
		if band.size.x > 0.0 and band.size.y > 0.0:
			_add_rect(st, Vector3(band.position.x, y, band.position.y), Vector3(band.end.x, y, band.end.y), Palette.OUTSIDE)
	return st.commit()


## Дороги: круг в центре каждой клетки дороги и полоса от центра клетки до середины каждой связи.
## Шоссе рисуются отдельно — эстакадой со съездами.
func _road_mesh() -> ArrayMesh:
	var network := _sim.network
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Круг в центре каждой клетки дороги — скруглённый стык: полосы под любым углом (в том числе
	# диагональ с прямой) сходятся гладко, без торчащих углов, а тупик получает круглое окончание.
	for cell: Vector2i in network.road_cells():
		_add_disc(st, cell_center(cell) + Vector3.UP * ROAD_HEIGHT, ROAD_WIDTH / 2, _road_color(cell))
	for cell: Vector2i in network.linked_cells():
		var from := cell_center(cell) + Vector3.UP * ROAD_HEIGHT
		for neighbor: Vector2i in network.links_of(cell):
			if network.is_motorway(cell, neighbor):
				continue
			var middle := (from + cell_center(neighbor) + Vector3.UP * ROAD_HEIGHT) / 2
			_add_strip(st, from, middle, ROAD_WIDTH, _road_color(cell))
	for ends: Array in network.motorways():
		_add_motorway(st, ends[0], ends[1], Palette.MOTORWAY, 0.0)
	return st.commit()


## Эстакада шоссе: съезд, пролёт, съезд.
func _add_motorway(st: SurfaceTool, from: Vector2i, to: Vector2i, color: Color, lift: float) -> void:
	var a := cell_center(from)
	var b := cell_center(to)
	var dir := (b - a).normalized()
	var low := Vector3.UP * (ROAD_HEIGHT + lift)
	var high := Vector3.UP * (MOTORWAY_HEIGHT + lift)
	var points := [a + low, a + dir * MOTORWAY_RAMP + high, b - dir * MOTORWAY_RAMP + high, b + low]
	for i in 3:
		_add_strip(st, points[i], points[i + 1], ROAD_WIDTH, color)


func _road_color(cell: Vector2i) -> Color:
	return Palette.BRIDGE if _sim.network.is_bridge(cell) else Palette.ROAD


func _rebuild_junctions() -> void:
	for child in _junctions.get_children():
		child.queue_free()
	var controls := _sim.network.controls()
	for cell: Vector2i in controls:
		var model := ModelFactory.traffic_light() if controls[cell] == RoadNetwork.Junction.LIGHT \
			else ModelFactory.roundabout()
		model.position = cell_center(cell)
		_junctions.add_child(model)


## Новые здания, появившиеся в симуляции, «вырастают» из земли.
func _show_new_buildings() -> void:
	while _houses_shown < _sim.houses.size():
		var house := _sim.houses[_houses_shown]
		var model := ModelFactory.house(Palette.building(house.color))
		_house_models.append(model)
		_pop_in(model, cell_center(house.cell))
		var label := _sleep_label()
		label.position = cell_center(house.cell) + Vector3.UP * SLEEP_HEIGHT
		add_child(label)
		_sleep_labels.append(label)
		_houses_shown += 1
		_turn_houses_to_exits()
	while _destinations_shown < _sim.destinations.size():
		var dest := _sim.destinations[_destinations_shown]
		var main := _main_rect(dest)
		var center := Vector3(main.position.x + main.size.x / 2.0, 0.0, main.position.y + main.size.y / 2.0)
		# Корпус — все клетки здания, кроме парковки: основная часть и пристройка одним телом.
		var cells: Array[Vector2] = []
		for y in range(dest.rect.position.y, dest.rect.end.y):
			for x in range(dest.rect.position.x, dest.rect.end.x):
				if Vector2i(x, y) != dest.entrance or dest.stub == null:
					var offset := cell_center(Vector2i(x, y)) - center
					cells.append(Vector2(offset.x, offset.z))
		var model := ModelFactory.destination(dest.color, cells, _destination_details(dest, center))
		var overlay := StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.albedo_color = Color(Palette.OVERFLOW, 0.0)
		_set_overlay(model, overlay)
		_warning_overlays.append(overlay)
		if dest.stub != null:
			# Парковка не мигает вместе со зданием — её добавляем после слоя тревоги.
			var parking := ModelFactory.parking()
			var toward: Vector2i = dest.stub - dest.entrance
			parking.position = cell_center(dest.entrance) - center
			parking.rotation.y = atan2(toward.x, toward.y)
			model.add_child(parking)
		_pop_in(model, center)
		_windows.append(model.get_meta("windows"))
		_destinations_shown += 1


## Каждый подключённый дом смотрит дверью на свой единственный выезд.
func _turn_houses_to_exits() -> void:
	for i in _house_models.size():
		var cell := _sim.houses[i].cell
		var links := _sim.network.links_of(cell)
		if not links.is_empty():
			var dir: Vector2i = links[0] - cell
			_house_models[i].rotation.y = atan2(dir.x, dir.y)


func _set_overlay(node: Node, overlay: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = overlay
	for child in node.get_children():
		_set_overlay(child, overlay)


func _sleep_label() -> Label3D:
	var label := Label3D.new()
	label.text = "Zzz"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 14
	label.pixel_size = 0.01
	label.modulate = Palette.TEXT
	label.outline_modulate = Palette.LAND
	label.font = UiTheme.font()
	label.visible = false
	return label


## «Zzz» над домами, у которых нет пути ни к одному месту назначения своего цвета. Связность
## пересчитываем только при изменении дорог или зданий; покачивание — каждый кадр.
func _update_sleep_labels() -> void:
	var key := [_sim.network.version, _sim.houses.size(), _sim.destinations.size()]
	if key != _served_key:
		_served_key = key
		_served.clear()
		for house in _sim.houses:
			_served.append(_sim.is_house_served(house))
	var time := Time.get_ticks_msec() / 1000.0
	for i in _sleep_labels.size():
		var label := _sleep_labels[i]
		label.visible = i < _served.size() and not _served[i]
		if label.visible:
			var base := cell_center(_sim.houses[i].cell) + Vector3.UP * SLEEP_HEIGHT
			label.position = base + Vector3.UP * 0.06 * sin(time * 2.0 + i)


func _pop_in(model: Node3D, at: Vector3) -> void:
	model.position = at
	model.scale = Vector3(1.0, 0.01, 1.0)
	add_child(model)
	model.create_tween().tween_property(model, "scale", Vector3.ONE, POP_IN_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Детали по образцу для места назначения 2×3 с подъездом (у прочих — пусто): трубы в дальнем от
## парковки ряду, полоса окон над клеткой рядом с пристройкой, ворота над парковкой. Всё — в координатах
## модели (относительно center).
func _destination_details(dest: Destination, center: Vector3) -> Dictionary:
	if dest.stub == null or dest.rect.size.x * dest.rect.size.y != 6:
		return {}
	var out: Vector2i = dest.stub - dest.entrance
	var far := -out
	var across: Vector2i = Vector2i(out.y, -out.x)
	if not dest.rect.has_point(dest.entrance + across):
		across = -across
	var local := func(cell: Vector2i) -> Vector2:
		var offset := cell_center(cell) - center
		return Vector2(offset.x, offset.z)
	var door_cell := dest.entrance + far
	return {
		"chimneys": [local.call(dest.entrance + far * 2), local.call(dest.entrance + far * 2 + across)],
		"strip_center": local.call(door_cell + across),
		"strip_axis": Vector2(far),
		"windows": _sim.supply_slots(),
		"door": (local.call(dest.entrance) + local.call(door_cell)) / 2,
		"door_out": Vector2(out),
	}


## Основная часть места назначения (2×2) — без торцевого ряда с парковкой.
static func _main_rect(dest: Destination) -> Rect2i:
	var rect := dest.rect
	if rect.size.y == 3:
		return Rect2i(rect.position.x, rect.position.y + (1 if dest.entrance.y == rect.position.y else 0), 2, 2)
	if rect.size.x == 3:
		return Rect2i(rect.position.x + (1 if dest.entrance.x == rect.position.x else 0), rect.position.y, 2, 2)
	return rect


func _update_destinations() -> void:
	for i in _destinations_shown:
		var dest := _sim.destinations[i]
		# Окна гаснут по одному на каждый невыполненный заказ, последнее — плавно, пока идёт таймер.
		var windows: Array[StandardMaterial3D] = _windows[i]
		var level := _sim.supply_level(dest)
		for j in windows.size():
			windows[j].albedo_color = Palette.WINDOW_OFF.lerp(Palette.WINDOW_LIT, clampf(level - j, 0.0, 1.0))
		var alpha := 0.0
		if _sim.is_destination_warning(dest):
			alpha = 0.15 + 0.4 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * BLINK_HZ))
		_warning_overlays[i].albedo_color.a = alpha


func _tree_multimesh(mesh: Mesh, color: Color) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	mesh.surface_set_material(0, ModelFactory.flat_material(color))
	return multimesh


## Деревья на свободной суше видимой части карты. Где стоит дерево, решает хэш клетки,
## поэтому деревья не «прыгают» при перестройке; перестраиваем, только когда что-то изменилось.
func _update_trees() -> void:
	var network := _sim.network
	var key := [network.version, network.bounds, _sim.houses.size(), _sim.destinations.size()]
	if key == _trees_key:
		return
	_trees_key = key
	var transforms: Array[Transform3D] = []
	var area := network.bounds
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var h := _cell_hash(cell)
			if (h % 1000) / 1000.0 >= TREE_DENSITY or not network.is_free_land(cell):
				continue
			var offset := Vector3(((h >> 10) % 100) / 100.0 - 0.5, 0.0, ((h >> 17) % 100) / 100.0 - 0.5) * 0.4
			var scale := 0.8 + ((h >> 24) % 40) / 100.0
			transforms.append(Transform3D(Basis.from_scale(Vector3.ONE * scale), cell_center(cell) + offset))
	for pair: Array in [[_tree_trunks, 0.12], [_tree_crowns, 0.42]]:
		var multimesh: MultiMesh = (pair[0] as MultiMeshInstance3D).multimesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			var t := transforms[i]
			multimesh.set_instance_transform(i, t.translated(Vector3.UP * pair[1] * t.basis.get_scale().y))


static func _cell_hash(cell: Vector2i) -> int:
	return absi(hash(cell))


func _build_cars() -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var box := BoxMesh.new()
	box.size = CAR_SIZE
	multimesh.mesh = box
	_cars.multimesh = multimesh
	# Машины объёмные — им нужно освещение, в отличие от плоской геометрии у земли.
	var car_material := StandardMaterial3D.new()
	car_material.vertex_color_use_as_albedo = true
	car_material.vertex_color_is_srgb = true
	car_material.roughness = 1.0
	_cars.material_override = car_material
	add_child(_cars)


func _update_cars() -> void:
	var multimesh := _cars.multimesh
	if multimesh.instance_count != _sim.cars.size():
		multimesh.instance_count = _sim.cars.size()
	var shown := 0
	for car in _sim.cars:
		if not car.on_road:
			continue
		var from := car.lane_from()
		var to := car.lane_to()
		var a := cell_center(from)
		var b := cell_center(to)
		var dir := (b - a).normalized()
		var length := RoadNetwork.lane_length(from, to)
		var right := Vector3(-dir.z, 0.0, dir.x)
		var height := ROAD_HEIGHT + CAR_SIZE.y / 2
		if _sim.network.is_motorway(from, to):
			height += (MOTORWAY_HEIGHT - ROAD_HEIGHT) * clampf(minf(car.s, length - car.s) / MOTORWAY_RAMP, 0.0, 1.0)
		var pos := a.lerp(b, car.s / length) + right * Traffic.LANE_OFFSET + Vector3.UP * height
		multimesh.set_instance_transform(shown, Transform3D(Basis.looking_at(dir), pos))
		multimesh.set_instance_color(shown, Palette.building(car.home.color))
		shown += 1
	multimesh.visible_instance_count = shown


## Материал плоской геометрии у земли (земля, вода, дороги, туман) — без освещения: так цвета на
## экране в точности совпадают с палитрой, а тени не дают полосатых артефактов.
func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Прямоугольник на плоскости XZ между углами from и to.
func _add_rect(st: SurfaceTool, from: Vector3, to: Vector3, color: Color) -> void:
	_add_quad(st, [Vector3(from.x, from.y, from.z), Vector3(to.x, from.y, from.z),
		Vector3(to.x, to.y, to.z), Vector3(from.x, to.y, to.z)], color)


## Полоса шириной width от точки from до точки to (концы могут быть на разной высоте).
func _add_strip(st: SurfaceTool, from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var side := Vector3(-flat.z, 0.0, flat.x) * width / 2
	_add_quad(st, [from + side, to + side, to - side, from - side], color)


## Четырёхугольник, всегда обращённый лицом вверх. С отключённым отсечением граней Godot освещает
## перевёрнутую грань как нижнюю сторону — она темнее и на стыках дорог даёт полосы.
## Круг радиуса radius на плоскости XZ, лицом вверх.
func _add_disc(st: SurfaceTool, center: Vector3, radius: float, color: Color) -> void:
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for i in DISC_SEGMENTS:
		var a := TAU * i / DISC_SEGMENTS
		var b := TAU * (i + 1) / DISC_SEGMENTS
		# Порядок вершин — как у _add_quad после разворота (нормаль по векторному произведению вниз),
		# иначе грань освещалась бы как обратная сторона и выглядела темнее.
		st.add_vertex(center)
		st.add_vertex(center + Vector3(cos(a), 0.0, sin(a)) * radius)
		st.add_vertex(center + Vector3(cos(b), 0.0, sin(b)) * radius)


func _add_quad(st: SurfaceTool, corners: Array, color: Color) -> void:
	var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
	if normal.y > 0.0:
		corners = [corners[3], corners[2], corners[1], corners[0]]
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(corners[index])
