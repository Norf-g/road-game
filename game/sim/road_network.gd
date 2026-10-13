class_name RoadNetwork
extends RefCounted
## Дорожная сеть: клетки дорог и связи между ними (8 направлений), запасы дорог и мостов, поиск пути.
## Входы зданий — «терминалы»: в них можно въехать и из них выехать, но нельзя проехать насквозь.
## Клетки на воде — мосты: они не тратят клетки дорог, а каждый непрерывный пролёт тратит один мост.

enum Result { OK, OUT_OF_BOUNDS, NOT_ADJACENT, BLOCKED, ALREADY_LINKED, CROSSING, NO_TILES, NO_BRIDGES }

const SQRT2 := 1.4142135623730951

var grid: Grid
var tiles_left: int
var bridge_stock: int
var bridges_used := 0
## Растёт при каждом изменении сети: по нему отображение понимает, что дороги надо перерисовать.
var version := 0

var _water: Dictionary = {}      # Vector2i -> true
var _blocked: Dictionary = {}    # клетки зданий, где нельзя строить
var _terminals: Dictionary = {}  # входы зданий
var _roads: Dictionary = {}      # клетки дорог и мостов
var _links: Dictionary = {}      # Vector2i -> Array[Vector2i]
var _astar := AStar2D.new()


func _init(map_grid: Grid, water: Dictionary, tiles: int, bridges: int) -> void:
	grid = map_grid
	_water = water
	tiles_left = tiles
	bridge_stock = bridges


static func lane_length(a: Vector2i, b: Vector2i) -> float:
	return SQRT2 if a.x != b.x and a.y != b.y else 1.0


static func path_length(path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += lane_length(path[i - 1], path[i])
	return total


func add_terminal(cell: Vector2i) -> void:
	_terminals[cell] = true
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


func road_cells() -> Array:
	return _roads.keys()


## Все клетки, у которых есть хотя бы одна связь (дороги и подключённые входы зданий).
func linked_cells() -> Array:
	return _links.keys()


func links_of(cell: Vector2i) -> Array:
	return _links.get(cell, [])


func are_linked(a: Vector2i, b: Vector2i) -> bool:
	return links_of(a).has(b)


func is_intersection(cell: Vector2i) -> bool:
	return not _terminals.has(cell) and links_of(cell).size() >= 3


func can_build(a: Vector2i, b: Vector2i) -> Result:
	if not grid.in_bounds(a) or not grid.in_bounds(b):
		return Result.OUT_OF_BOUNDS
	var d := b - a
	if a == b or absi(d.x) > 1 or absi(d.y) > 1:
		return Result.NOT_ADJACENT
	if _blocked.has(a) or _blocked.has(b) or (_terminals.has(a) and _terminals.has(b)):
		return Result.BLOCKED
	if are_linked(a, b):
		return Result.ALREADY_LINKED
	if d.x != 0 and d.y != 0 and are_linked(Vector2i(b.x, a.y), Vector2i(a.x, b.y)):
		return Result.CROSSING
	var new_land := 0
	var new_water: Array[Vector2i] = []
	for cell in [a, b]:
		if _roads.has(cell) or _terminals.has(cell):
			continue
		if _water.has(cell):
			new_water.append(cell)
		else:
			new_land += 1
	if new_land > tiles_left:
		return Result.NO_TILES
	if not new_water.is_empty():
		# Новая водная клетка продолжает пролёт, только если её соединяют с уже построенным мостом.
		var other := b if new_water[0] == a else a
		if not is_bridge(other) and bridges_used >= bridge_stock:
			return Result.NO_BRIDGES
	return Result.OK


func build(a: Vector2i, b: Vector2i) -> Result:
	var check := can_build(a, b)
	if check != Result.OK:
		return check
	for cell in [a, b]:
		if _roads.has(cell) or _terminals.has(cell):
			continue
		_roads[cell] = true
		if not _water.has(cell):
			tiles_left -= 1
		_ensure_point(cell)
	_link(a, b)
	_recount_bridges()
	version += 1
	return Result.OK


## Сносит дорогу или мост в клетке вместе со всеми связями. Входы зданий снести нельзя.
func erase(cell: Vector2i) -> bool:
	if not _roads.has(cell):
		return false
	for neighbor: Vector2i in links_of(cell).duplicate():
		_unlink(cell, neighbor)
	_roads.erase(cell)
	if not _water.has(cell):
		tiles_left += 1
	_astar.remove_point(grid.index_of(cell))
	_recount_bridges()
	version += 1
	return true


## Кратчайший путь по дорогам от from до to включительно; пустой, если пути нет.
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


func _set_terminals_enabled(cells: Array, enabled: bool) -> void:
	for cell in cells:
		if _terminals.has(cell):
			_astar.set_point_disabled(grid.index_of(cell), not enabled)


func _ensure_point(cell: Vector2i) -> void:
	var id := grid.index_of(cell)
	if not _astar.has_point(id):
		_astar.add_point(id, Vector2(cell))


func _link(a: Vector2i, b: Vector2i) -> void:
	for pair: Array in [[a, b], [b, a]]:
		if not _links.has(pair[0]):
			_links[pair[0]] = []
		(_links[pair[0]] as Array).append(pair[1])
	_astar.connect_points(grid.index_of(a), grid.index_of(b))


func _unlink(a: Vector2i, b: Vector2i) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var links: Array = _links.get(pair[0], [])
		links.erase(pair[1])
		if links.is_empty():
			_links.erase(pair[0])
	_astar.disconnect_points(grid.index_of(a), grid.index_of(b))


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
