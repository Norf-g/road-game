class_name RoadNetwork
extends RefCounted
## Дорожная сеть: клетки дорог и связи между ними, запасы дорог, мостов и улучшений, поиск пути.
## Обычные связи соединяют соседние клетки (8 направлений). Шоссе соединяет две далёкие клетки
## поверх всего, и по нему едут быстрее.
## Входы зданий — «терминалы»: в них можно въехать и из них выехать, но нельзя проехать насквозь.
## У дома ровно один выезд: подключённый дом новых связей не принимает, но выезд можно перенести
## на новую дорогу (relink_terminal).
## Клетки на воде — мосты: они не тратят клетки дорог, а каждый пролёт тратит один мост. Мост —
## прямой отрезок без поворотов и развилок, не длиннее bridge_max_length клеток.
## Новая дорога всегда продолжает сеть: одна из клеток связи уже должна быть дорогой или входом здания.
## На перекрёсток можно поставить светофор или развязку.

enum Result {
	OK, OUT_OF_BOUNDS, NOT_ADJACENT, BLOCKED, ALREADY_LINKED, CROSSING, NO_TILES, NO_BRIDGES,
	NOT_INTERSECTION, OCCUPIED, NO_STOCK, TOO_LONG, NOT_CONNECTED, BRIDGE_SHAPE, BRIDGE_TOO_LONG,
	TERMINAL_FULL,
}
enum Junction { NONE, LIGHT, ROUNDABOUT }

var grid: Grid
## Где сейчас можно строить: видимая часть карты.
var bounds: Rect2i
var tiles_left: int
var bridge_stock: int
var bridges_used := 0
var bridge_max_length := 4
var lights_left := 0
var roundabouts_left := 0
var motorways_left := 0
var motorway_max_length := 30.0
## Во сколько раз быстрее обычной дороги едут по шоссе.
var motorway_speed: float:
	get:
		return _astar.motorway_speed
	set(value):
		_astar.motorway_speed = value
## Растёт при каждом изменении сети: по нему отображение и кэши маршрутов понимают, что пора обновиться.
var version := 0

var _water: Dictionary = {}      # Vector2i -> true
var _blocked: Dictionary = {}    # клетки зданий, где нельзя строить
var _terminals: Dictionary = {}  # вход здания -> сколько связей он принимает (0 — сколько угодно)
var _roads: Dictionary = {}      # клетки дорог и мостов
var _links: Dictionary = {}      # Vector2i -> Array[Vector2i]
var _motorways: Dictionary = {}  # Vector4i (пара клеток по порядку) -> true
var _controls: Dictionary = {}   # клетка -> Junction
var _astar := RoadAStar.new()


## A* по дорогам: стоимость связи — время в пути, поэтому шоссе выгоднее обычной дороги той же длины.
class RoadAStar:
	extends AStar2D

	var motorway_speed := 2.0
	var motorway_ids: Dictionary = {}  # Vector2i(меньший id, больший id) -> true

	func _compute_cost(from_id: int, to_id: int) -> float:
		var length := get_point_position(from_id).distance_to(get_point_position(to_id))
		if motorway_ids.has(Vector2i(mini(from_id, to_id), maxi(from_id, to_id))):
			return length / motorway_speed
		return length

	func _estimate_cost(from_id: int, to_id: int) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id)) / motorway_speed


func _init(map_grid: Grid, water: Dictionary, tiles: int, bridges: int) -> void:
	grid = map_grid
	bounds = Rect2i(Vector2i.ZERO, grid.size)
	_water = water
	tiles_left = tiles
	bridge_stock = bridges


static func lane_length(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


static func _pair_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


## Во сколько раз быстрее обычного едут по связи a-b.
func speed_factor(a: Vector2i, b: Vector2i) -> float:
	return motorway_speed if is_motorway(a, b) else 1.0


## Время в пути по маршруту в «клетках обычной дороги».
func path_cost(path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += lane_length(path[i - 1], path[i]) / speed_factor(path[i - 1], path[i])
	return total


## Вход здания. max_links — сколько связей он принимает; 0 — без ограничений.
func add_terminal(cell: Vector2i, max_links := 0) -> void:
	_terminals[cell] = max_links
	_ensure_point(cell)
	_astar.set_point_disabled(grid.index_of(cell), true)


func add_blocked(cell: Vector2i) -> void:
	_blocked[cell] = true


func is_water(cell: Vector2i) -> bool:
	return _water.has(cell)


func is_road(cell: Vector2i) -> bool:
	return _roads.has(cell)


func is_bridge(cell: Vector2i) -> bool:
	return _roads.has(cell) and _water.has(cell)


func is_terminal(cell: Vector2i) -> bool:
	return _terminals.has(cell)


## Можно ли поставить здание: видимая суша без дорог и других зданий.
func is_free_land(cell: Vector2i) -> bool:
	return bounds.has_point(cell) and not _water.has(cell) and not _roads.has(cell) \
		and not _terminals.has(cell) and not _blocked.has(cell)


## Клетка занята зданием (вход или остальная часть здания).
func is_building(cell: Vector2i) -> bool:
	return _terminals.has(cell) or _blocked.has(cell)


func road_cells() -> Array:
	return _roads.keys()


## Все клетки, у которых есть хотя бы одна связь (дороги и подключённые входы зданий).
func linked_cells() -> Array:
	return _links.keys()


func links_of(cell: Vector2i) -> Array:
	return _links.get(cell, [])


func are_linked(a: Vector2i, b: Vector2i) -> bool:
	return links_of(a).has(b)


func is_motorway(a: Vector2i, b: Vector2i) -> bool:
	return _motorways.has(_pair_key(a, b))


## Пары концов всех шоссе.
func motorways() -> Array[Array]:
	var result: Array[Array] = []
	for key: Vector4i in _motorways:
		result.append([Vector2i(key.x, key.y), Vector2i(key.z, key.w)])
	return result


func is_intersection(cell: Vector2i) -> bool:
	return not _terminals.has(cell) and links_of(cell).size() >= 3


func control_at(cell: Vector2i) -> Junction:
	return _controls.get(cell, Junction.NONE)


func controls() -> Dictionary:
	return _controls


func can_build(a: Vector2i, b: Vector2i) -> Result:
	if not bounds.has_point(a) or not bounds.has_point(b):
		return Result.OUT_OF_BOUNDS
	var d := b - a
	if a == b or absi(d.x) > 1 or absi(d.y) > 1:
		return Result.NOT_ADJACENT
	if _blocked.has(a) or _blocked.has(b):
		return Result.BLOCKED
	if are_linked(a, b):
		return Result.ALREADY_LINKED
	var corner_a := Vector2i(b.x, a.y)
	var corner_b := Vector2i(a.x, b.y)
	if d.x != 0 and d.y != 0 and are_linked(corner_a, corner_b):
		return Result.CROSSING
	if not _is_anchor(a) and not _is_anchor(b):
		return Result.NOT_CONNECTED
	if _is_full(a) or _is_full(b):
		return Result.TERMINAL_FULL
	# Диагональ между клетками суши не может «срезать» угол реки.
	if d.x != 0 and d.y != 0 and _water.has(corner_a) and _water.has(corner_b) 			and not _water.has(a) and not _water.has(b):
		return Result.BLOCKED
	for cell: Vector2i in [a, b]:
		if _water.has(cell) and not _is_straight(cell, links_of(cell) + [b if cell == a else a]):
			return Result.BRIDGE_SHAPE
	if _new_land_cells([a, b]) > tiles_left:
		return Result.NO_TILES
	var new_water := 0
	var span := 0
	for cell: Vector2i in [a, b]:
		if is_bridge(cell):
			span += _span_cells(cell).size()
		elif _water.has(cell) and not _terminals.has(cell):
			new_water += 1
	if new_water > 0:
		# Новая водная клетка продолжает пролёт, только если её соединяют с уже построенным мостом.
		if span == 0 and bridges_used >= bridge_stock:
			return Result.NO_BRIDGES
		if span + new_water > bridge_max_length:
			return Result.BRIDGE_TOO_LONG
	return Result.OK


func build(a: Vector2i, b: Vector2i) -> Result:
	var check := can_build(a, b)
	if check != Result.OK:
		return check
	_add_roads([a, b])
	_link(a, b)
	_recount_bridges()
	version += 1
	return Result.OK


## Переносит выезд здания terminal на связь с клеткой b: старые связи здания снимаются (дороги
## остаются), новая строится по обычным правилам. Если новую связь построить нельзя, всё остаётся как было.
func relink_terminal(terminal: Vector2i, b: Vector2i) -> Result:
	if not _terminals.has(terminal):
		return Result.NOT_CONNECTED
	if are_linked(terminal, b):
		return Result.ALREADY_LINKED
	var old: Array = links_of(terminal).duplicate()
	# Проверка на время без старых связей; светофоры соседей при этом не трогаем.
	for neighbor: Vector2i in old:
		_unlink(terminal, neighbor, false)
	var check := can_build(terminal, b)
	for neighbor: Vector2i in old:
		_link(terminal, neighbor)
	if check != Result.OK:
		return check
	for neighbor: Vector2i in old:
		_unlink(terminal, neighbor)
	return build(terminal, b)


## Вход здания, который принимает только одну связь (дом).
func is_single_exit(cell: Vector2i) -> bool:
	return _terminals.get(cell, 0) == 1


func can_build_motorway(a: Vector2i, b: Vector2i) -> Result:
	if not bounds.has_point(a) or not bounds.has_point(b):
		return Result.OUT_OF_BOUNDS
	var length := lane_length(a, b)
	if length < 2.0:
		return Result.NOT_ADJACENT
	if length > motorway_max_length:
		return Result.TOO_LONG
	for cell in [a, b]:
		if _blocked.has(cell) or _terminals.has(cell) or _water.has(cell):
			return Result.BLOCKED
	if are_linked(a, b):
		return Result.ALREADY_LINKED
	if motorways_left <= 0:
		return Result.NO_STOCK
	if _new_land_cells([a, b]) > tiles_left:
		return Result.NO_TILES
	return Result.OK


func build_motorway(a: Vector2i, b: Vector2i) -> Result:
	var check := can_build_motorway(a, b)
	if check != Result.OK:
		return check
	_add_roads([a, b])
	_motorways[_pair_key(a, b)] = true
	_astar.motorway_ids[_id_pair(a, b)] = true
	_link(a, b)
	motorways_left -= 1
	version += 1
	return Result.OK


func place_control(cell: Vector2i, control: Junction) -> Result:
	if not is_intersection(cell):
		return Result.NOT_INTERSECTION
	if _controls.has(cell):
		return Result.OCCUPIED
	match control:
		Junction.LIGHT:
			if lights_left <= 0:
				return Result.NO_STOCK
			lights_left -= 1
		Junction.ROUNDABOUT:
			if roundabouts_left <= 0:
				return Result.NO_STOCK
			roundabouts_left -= 1
	_controls[cell] = control
	version += 1
	return Result.OK


## Сносит дорогу или мост в клетке вместе со связями, шоссе и светофором/развязкой —
## всё это возвращается в запас. Входы зданий снести нельзя.
func erase(cell: Vector2i) -> bool:
	if not _roads.has(cell):
		return false
	for neighbor: Vector2i in links_of(cell).duplicate():
		_unlink(cell, neighbor)
	_remove_control(cell)
	_roads.erase(cell)
	if not _water.has(cell):
		tiles_left += 1
	_astar.remove_point(grid.index_of(cell))
	_recount_bridges()
	version += 1
	return true


## Кратчайший по времени путь по дорогам от from до to включительно; пустой, если пути нет.
## Через входы зданий путь не проходит, кроме начала и конца.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var from_id := grid.index_of(from)
	var to_id := grid.index_of(to)
	if from == to or not _astar.has_point(from_id) or not _astar.has_point(to_id):
		return path
	_set_terminals_enabled([from, to], true)
	var ids := _astar.get_id_path(from_id, to_id)
	_set_terminals_enabled([from, to], false)
	for id in ids:
		path.append(Vector2i(_astar.get_point_position(id)))
	return path


## Вход здания, который уже принял все связи, какие мог.
func _is_full(cell: Vector2i) -> bool:
	var max_links: int = _terminals.get(cell, 0)
	return max_links > 0 and links_of(cell).size() >= max_links


func _is_anchor(cell: Vector2i) -> bool:
	return _roads.has(cell) or _terminals.has(cell)


## Связи водной клетки образуют прямую: не больше двух, и если две — в противоположные стороны.
static func _is_straight(cell: Vector2i, neighbors: Array) -> bool:
	if neighbors.size() > 2:
		return false
	return neighbors.size() < 2 or (neighbors[0] - cell) == -(neighbors[1] - cell)


## Клетки пролёта моста, в который входит клетка cell.
func _span_cells(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	var index := 0
	while index < cells.size():
		for neighbor: Vector2i in links_of(cells[index]):
			if is_bridge(neighbor) and not cells.has(neighbor):
				cells.append(neighbor)
		index += 1
	return cells


func _new_land_cells(cells: Array) -> int:
	var count := 0
	for cell: Vector2i in cells:
		if not _roads.has(cell) and not _terminals.has(cell) and not _water.has(cell):
			count += 1
	return count


func _add_roads(cells: Array) -> void:
	for cell: Vector2i in cells:
		if _roads.has(cell) or _terminals.has(cell):
			continue
		_roads[cell] = true
		if not _water.has(cell):
			tiles_left -= 1
		_ensure_point(cell)


func _remove_control(cell: Vector2i) -> void:
	match control_at(cell):
		Junction.LIGHT:
			lights_left += 1
		Junction.ROUNDABOUT:
			roundabouts_left += 1
	_controls.erase(cell)


func _set_terminals_enabled(cells: Array, enabled: bool) -> void:
	for cell in cells:
		if _terminals.has(cell):
			_astar.set_point_disabled(grid.index_of(cell), not enabled)


func _ensure_point(cell: Vector2i) -> void:
	var id := grid.index_of(cell)
	if not _astar.has_point(id):
		_astar.add_point(id, Vector2(cell))


func _id_pair(a: Vector2i, b: Vector2i) -> Vector2i:
	var ia := grid.index_of(a)
	var ib := grid.index_of(b)
	return Vector2i(mini(ia, ib), maxi(ia, ib))


func _link(a: Vector2i, b: Vector2i) -> void:
	for pair: Array in [[a, b], [b, a]]:
		if not _links.has(pair[0]):
			_links[pair[0]] = []
		(_links[pair[0]] as Array).append(pair[1])
	_astar.connect_points(grid.index_of(a), grid.index_of(b))


func _unlink(a: Vector2i, b: Vector2i, drop_controls := true) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var links: Array = _links.get(pair[0], [])
		links.erase(pair[1])
		if links.is_empty():
			_links.erase(pair[0])
	_astar.disconnect_points(grid.index_of(a), grid.index_of(b))
	if _motorways.erase(_pair_key(a, b)):
		_astar.motorway_ids.erase(_id_pair(a, b))
		motorways_left += 1
	# Перекрёсток, который перестал быть перекрёстком, возвращает светофор или развязку в запас.
	if not drop_controls:
		return
	for cell in [a, b]:
		if _controls.has(cell) and not is_intersection(cell):
			_remove_control(cell)


func _recount_bridges() -> void:
	var seen := {}
	var count := 0
	for cell: Vector2i in _roads:
		if not _water.has(cell) or seen.has(cell):
			continue
		count += 1
		seen[cell] = true
		var stack: Array[Vector2i] = [cell]
		while not stack.is_empty():
			var current: Vector2i = stack.pop_back()
			for neighbor: Vector2i in links_of(current):
				if is_bridge(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					stack.append(neighbor)
	bridges_used = count
