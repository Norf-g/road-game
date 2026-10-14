class_name WorldView
extends Node3D
## Показывает партию: землю и реку, туман за пределами видимой части карты, дороги, мосты и шоссе,
## светофоры и развязки, здания, деревья, машины, заказы и таймеры переполнения, «Zzz» над домами
## без пути к месту назначения и красное мигание мест назначения в тревоге.
## Только читает состояние симуляции и ничего в нём не меняет.

const ROAD_WIDTH := 0.5
const ROAD_HEIGHT := 0.02
const FOG_HEIGHT := 0.04
const MOTORWAY_HEIGHT := 0.35
## Длина съезда шоссе с земли на эстакаду.
const MOTORWAY_RAMP := 1.0
const CAR_SIZE := Vector3(0.2, 0.12, 0.3)
const MAX_PIN_MARKERS := 8
const PIN_SIZE := 0.18
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
var _cars := MultiMeshInstance3D.new()
var _houses_shown := 0
var _house_models: Array[Node3D] = []
var _sleep_labels: Array[Label3D] = []
var _served_key := []
var _served: Array[bool] = []
## Полупрозрачный красный слой поверх модели каждого места назначения — для мигания.
var _warning_overlays: Array[StandardMaterial3D] = []
var _destinations_shown := 0
var _pin_markers: Array = []  # для каждого места назначения — Array[MeshInstance3D]
var _overflow_bars: Array[MeshInstance3D] = []
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


## Дороги: квадрат в центре каждой клетки дороги и полоса от центра клетки до середины каждой связи.
## Шоссе рисуются отдельно — эстакадой со съездами.
func _road_mesh() -> ArrayMesh:
	var network := _sim.network
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := ROAD_WIDTH / 2
	for cell: Vector2i in network.road_cells():
		var c := cell_center(cell)
		_add_rect(st, c + Vector3(-half, ROAD_HEIGHT, -half), c + Vector3(half, ROAD_HEIGHT, half), _road_color(cell))
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
		var center := Vector3(dest.rect.get_center().x, 0.0, dest.rect.get_center().y)
		var model := ModelFactory.destination(dest.color)
		# Въезд — тёмный проём в углу здания, где находится клетка въезда.
		var gate := ModelFactory.gate()
		var outward := Vector3(dest.entrance.x + 0.5, 0.0, dest.entrance.y + 0.5) - center
		gate.position = outward * 1.8
		gate.rotation.y = atan2(outward.x, outward.z)
		model.add_child(gate)
		var overlay := StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.albedo_color = Color(Palette.OVERFLOW, 0.0)
		_set_overlay(model, overlay)
		_warning_overlays.append(overlay)
		_pop_in(model, center)
		_build_pin_markers(dest, model.get_meta("roof_height"))
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
	if ResourceLoader.exists(Hud.FONT_PATH):
		label.font = load(Hud.FONT_PATH)
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


func _build_pin_markers(dest: Destination, roof_height: float) -> void:
	var markers: Array[MeshInstance3D] = []
	var center := Vector3(dest.rect.get_center().x, roof_height, dest.rect.get_center().y)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * PIN_SIZE
	for i in MAX_PIN_MARKERS:
		var marker := MeshInstance3D.new()
		marker.mesh = box
		marker.material_override = ModelFactory.flat_material(Palette.building(dest.color).darkened(0.35))
		var column := i % 4
		var row := i / 4
		marker.position = center + Vector3((column - 1.5) * 0.3, PIN_SIZE / 2, (row - 0.5) * 0.3)
		marker.visible = false
		add_child(marker)
		markers.append(marker)
	_pin_markers.append(markers)

	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.0, 0.08, 0.16)
	bar.mesh = bar_mesh
	bar.material_override = ModelFactory.flat_material(Palette.OVERFLOW)
	bar.position = center + Vector3(0.0, 0.5, -0.6)
	bar.visible = false
	add_child(bar)
	_overflow_bars.append(bar)


func _update_destinations() -> void:
	for i in _destinations_shown:
		var dest := _sim.destinations[i]
		var markers: Array[MeshInstance3D] = _pin_markers[i]
		for j in markers.size():
			markers[j].visible = j < dest.pins
		var alpha := 0.0
		if _sim.is_destination_warning(dest):
			alpha = 0.15 + 0.4 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * BLINK_HZ))
		_warning_overlays[i].albedo_color.a = alpha
		var bar := _overflow_bars[i]
		var ratio := dest.overflow / _sim.balance.overflow_time
		bar.visible = ratio > 0.0
		bar.scale.x = maxf(ratio * 1.6, 0.01)


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
func _add_quad(st: SurfaceTool, corners: Array, color: Color) -> void:
	var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
	if normal.y > 0.0:
		corners = [corners[3], corners[2], corners[1], corners[0]]
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(corners[index])
