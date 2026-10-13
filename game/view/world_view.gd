class_name WorldView
extends Node3D
## Показывает партию: землю и реку, дороги и мосты, здания, машины, заказы и таймеры переполнения.
## Только читает состояние симуляции и ничего в нём не меняет.

const ROAD_WIDTH := 0.5
const ROAD_HEIGHT := 0.02
const CAR_SIZE := Vector3(0.2, 0.12, 0.3)
## Смещение машины вправо от оси дороги — правостороннее движение.
const CAR_SIDE_OFFSET := 0.12
const MAX_PIN_MARKERS := 8
const PIN_SIZE := 0.18
const ROOF_HEIGHT := 0.6

var _sim: Simulation
var _roads := MeshInstance3D.new()
var _road_version := -1
var _cars := MultiMeshInstance3D.new()
var _pin_markers: Array = []  # для каждого места назначения — Array[MeshInstance3D]
var _overflow_bars: Array[MeshInstance3D] = []


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func setup(sim: Simulation) -> void:
	_sim = sim
	_build_terrain()
	_roads.material_override = _vertex_color_material()
	(_roads.material_override as StandardMaterial3D).disable_receive_shadows = true
	# Плоская геометрия у земли: её тени дают только полосатые артефакты.
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roads)
	_build_buildings()
	_build_cars()


func _process(_delta: float) -> void:
	if _sim.network.version != _road_version:
		_road_version = _sim.network.version
		_roads.mesh = _road_mesh()
	_update_cars()
	_update_destinations()


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


## Дороги: квадрат в центре каждой клетки дороги и полоса от центра клетки до середины каждой связи.
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
			var middle := (from + cell_center(neighbor) + Vector3.UP * ROAD_HEIGHT) / 2
			_add_strip(st, from, middle, ROAD_WIDTH, _road_color(cell))
	return st.commit()


func _road_color(cell: Vector2i) -> Color:
	return Palette.BRIDGE if _sim.network.is_bridge(cell) else Palette.ROAD


func _build_buildings() -> void:
	for house in _sim.houses:
		var model := ModelFactory.house(Palette.building(house.color))
		model.position = cell_center(house.cell)
		add_child(model)
	for dest in _sim.destinations:
		var model := ModelFactory.destination(Palette.building(dest.color))
		model.position = Vector3(dest.rect.get_center().x, 0.0, dest.rect.get_center().y)
		add_child(model)
		_build_pin_markers(dest)


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
	for dest in _sim.destinations:
		var markers: Array[MeshInstance3D] = _pin_markers[dest.id]
		for i in markers.size():
			markers[i].visible = i < dest.pins
		var bar := _overflow_bars[dest.id]
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
		var a := cell_center(car.lane_from())
		var b := cell_center(car.lane_to())
		var dir := (b - a).normalized()
		var t := car.s / RoadNetwork.lane_length(car.lane_from(), car.lane_to())
		var right := Vector3(-dir.z, 0.0, dir.x)
		var pos := a.lerp(b, t) + right * CAR_SIDE_OFFSET + Vector3.UP * (ROAD_HEIGHT + CAR_SIZE.y / 2)
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


## Полоса шириной width от точки from до точки to.
func _add_strip(st: SurfaceTool, from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var dir := (to - from).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * width / 2
	_add_quad(st, [from + side, to + side, to - side, from - side], color)


func _add_quad(st: SurfaceTool, corners: Array, color: Color) -> void:
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(corners[index])
