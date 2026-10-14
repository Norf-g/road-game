class_name WorldView
extends Node3D
## Показывает партию: землю и реку, туман за пределами видимой части карты, дороги, мосты и шоссе,
## светофоры и развязки, здания, машины, заказы и таймеры переполнения.
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
const ROOF_HEIGHT := 0.6
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
var _destinations_shown := 0
var _pin_markers: Array = []  # для каждого места назначения — Array[MeshInstance3D]
var _overflow_bars: Array[MeshInstance3D] = []


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func setup(sim: Simulation) -> void:
	_sim = sim
	_build_terrain()
	for flat: MeshInstance3D in [_roads, _fog, _preview]:
		var material := _vertex_color_material()
		# Плоская геометрия у земли: тени на ней дают только полосатые артефакты.
		material.disable_receive_shadows = true
		flat.material_override = material
		flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flat)
	add_child(_junctions)
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
	_update_cars()
	_update_destinations()


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
		_houses_shown += 1
		_turn_houses_to_exits()
	while _destinations_shown < _sim.destinations.size():
		var dest := _sim.destinations[_destinations_shown]
		var center := Vector3(dest.rect.get_center().x, 0.0, dest.rect.get_center().y)
		var model := ModelFactory.destination(Palette.building(dest.color))
		# Въезд — тёмный проём в углу здания, где находится клетка въезда.
		var gate := ModelFactory.gate()
		var outward := Vector3(dest.entrance.x + 0.5, 0.0, dest.entrance.y + 0.5) - center
		gate.position = outward * 1.8
		gate.rotation.y = atan2(outward.x, outward.z)
		model.add_child(gate)
		_pop_in(model, center)
		_build_pin_markers(dest)
		_destinations_shown += 1


## Каждый подключённый дом смотрит дверью на свой единственный выезд.
func _turn_houses_to_exits() -> void:
	for i in _house_models.size():
		var cell := _sim.houses[i].cell
		var links := _sim.network.links_of(cell)
		if not links.is_empty():
			var dir: Vector2i = links[0] - cell
			_house_models[i].rotation.y = atan2(dir.x, dir.y)


func _pop_in(model: Node3D, at: Vector3) -> void:
	model.position = at
	model.scale = Vector3(1.0, 0.01, 1.0)
	add_child(model)
	model.create_tween().tween_property(model, "scale", Vector3.ONE, POP_IN_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_pin_markers(dest: Destination) -> void:
	var markers: Array[MeshInstance3D] = []
	var center := Vector3(dest.rect.get_center().x, ROOF_HEIGHT, dest.rect.get_center().y)
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
		var bar := _overflow_bars[i]
		var ratio := dest.overflow / _sim.balance.overflow_time
		bar.visible = ratio > 0.0
		bar.scale.x = maxf(ratio * 1.6, 0.01)


func _build_cars() -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var box := BoxMesh.new()
	box.size = CAR_SIZE
	multimesh.mesh = box
	_cars.multimesh = multimesh
	_cars.material_override = _vertex_color_material()
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


func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
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
