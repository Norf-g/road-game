class_name Director
extends RefCounted
## Модуль генерации («директор»): решает, что, где и когда появляется в городе, и ведёт игровые недели.
## - Цвета появляются по неделям из color_weeks: место назначения и несколько домов сразу.
## - Здания ставятся с отступом spawn_edge_margin от края видимой части карты.
## - Дома появляются всё чаще: рядом с домами того же цвета или на растущем расстоянии
##   от места назначения своего цвета.
## - Раз в несколько недель — ещё одно место назначения знакомого цвета.
## - Заказы с каждой неделей приходят чаще, видимая часть карты расширяется по сценарию карты.
## - В конце недели игрок получает дороги и выбирает одно из двух улучшений; пока он выбирает,
##   симуляция стоит.
## Вся случайность — из RNG партии, поэтому директор детерминирован вместе с симуляцией.

enum Upgrade { TILES, BRIDGES, LIGHT, ROUNDABOUT, MOTORWAY }

## Номер текущей недели, с нуля.
var week := 0
## Два улучшения на выбор в конце недели; пусто, если выбора сейчас нет.
var offer: Array[Upgrade] = []

## Слабая ссылка: симуляция владеет директором, а не наоборот, иначе оба никогда не освободятся.
var _sim_ref: WeakRef
var _sim: Simulation:
	get:
		return _sim_ref.get_ref()
var _map: MapData
var _balance: Balance
var _week_time := 0.0
var _house_timer := 0.0
var _colors := 0


func _init(sim: Simulation, map: MapData) -> void:
	_sim_ref = weakref(sim)
	_map = map
	_balance = sim.balance
	sim.director = self
	_start_week()


func has_offer() -> bool:
	return not offer.is_empty()


## Доля прошедшей недели, от 0 до 1.
func week_progress() -> float:
	return _week_time / _balance.week_seconds


func area() -> Rect2i:
	return _sim.network.bounds


## Где можно ставить здания: видимая часть карты без полосы у края.
func spawn_area() -> Rect2i:
	return area().grow(-_balance.spawn_edge_margin)


func choose(index: int) -> void:
	var network := _sim.network
	match offer[index]:
		Upgrade.TILES:
			network.tiles_left += _balance.upgrade_tiles
		Upgrade.BRIDGES:
			network.bridge_stock += _balance.upgrade_bridges
		Upgrade.LIGHT:
			network.lights_left += 1
		Upgrade.ROUNDABOUT:
			network.roundabouts_left += 1
		Upgrade.MOTORWAY:
			network.motorways_left += 1
	offer.clear()


func step() -> void:
	_week_time += Simulation.DT
	if _week_time >= _balance.week_seconds:
		_week_time -= _balance.week_seconds
		_end_week()
		return
	_house_timer += Simulation.DT
	if _house_timer >= _house_interval():
		_house_timer = 0.0
		_spawn_house(_neediest_color())


func _end_week() -> void:
	week += 1
	_sim.network.tiles_left += _balance.week_tiles
	var kinds: Array = Upgrade.values()
	var first: int = kinds.pop_at(_sim.rng.randi_range(0, kinds.size() - 1))
	var second: int = kinds[_sim.rng.randi_range(0, kinds.size() - 1)]
	offer = [first, second]
	_start_week()


func _start_week() -> void:
	_sim.network.bounds = _map.area_at(week)
	_sim.pin_interval = maxf(_balance.pin_interval * pow(_balance.pin_interval_decay, week),
		_balance.pin_interval_min)
	while _colors < _balance.color_weeks.size() and _balance.color_weeks[_colors] <= week:
		_introduce_color(_colors)
		_colors += 1
	if week > 0 and week % _balance.destination_every_weeks == 0 and _colors > 0:
		_spawn_destination(_sim.rng.randi_range(0, _colors - 1))


func _house_interval() -> float:
	return maxf(_balance.house_interval * pow(_balance.house_interval_decay, week), _balance.house_interval_min)


func _spawn_distance() -> float:
	return minf(_balance.spawn_distance_start + _balance.spawn_distance_growth * week, _balance.spawn_distance_max)


func _introduce_color(color: int) -> void:
	if _spawn_destination(color) == null:
		return
	for i in _balance.houses_per_new_color:
		_spawn_house(color)


## Цвет, у которого меньше всего домов на одно место назначения.
func _neediest_color() -> int:
	var best := 0
	var best_ratio := INF
	for color in _colors:
		var dests := _destinations_of(color).size()
		if dests == 0:
			continue
		var ratio := float(_houses_of(color).size()) / dests
		if ratio < best_ratio:
			best = color
			best_ratio = ratio
	return best


## Место назначения 2×2 на свободной суше с полосой свободных от зданий клеток вокруг.
## Вход — одна из клеток здания, рядом с которой снаружи есть свободная суша.
func _spawn_destination(color: int) -> Destination:
	var network := _sim.network
	var area := spawn_area()
	var candidates: Array[Rect2i] = []
	for y in range(area.position.y, area.end.y - 1):
		for x in range(area.position.x, area.end.x - 1):
			var rect := Rect2i(x, y, 2, 2)
			if _rect_is_free(rect) and _far_from_destinations(rect, 4.0):
				candidates.append(rect)
	if candidates.is_empty():
		return null
	var rect := candidates[_sim.rng.randi_range(0, candidates.size() - 1)]
	var entrances: Array[Vector2i] = []
	for cell in _cells_of(rect):
		for neighbor in network.grid.neighbors8(cell):
			if not rect.has_point(neighbor) and network.is_free_land(neighbor) and not entrances.has(cell):
				entrances.append(cell)
	if entrances.is_empty():
		return null
	return _sim.add_destination(rect, entrances[_sim.rng.randi_range(0, entrances.size() - 1)], color)


## Дом цвета color: с вероятностью cluster_chance — рядом с домом того же цвета, иначе — на
## расстоянии около spawn_distance от места назначения своего цвета.
func _spawn_house(color: int) -> House:
	var dests := _destinations_of(color)
	if dests.is_empty():
		return null
	var houses := _houses_of(color)
	var free := _free_cells()
	var candidates: Array[Vector2i] = []
	if not houses.is_empty() and _sim.rng.randf() < _balance.cluster_chance:
		var anchor := houses[_sim.rng.randi_range(0, houses.size() - 1)].cell
		for cell in free:
			var d := maxi(absi(cell.x - anchor.x), absi(cell.y - anchor.y))
			if d >= 1 and d <= 2:
				candidates.append(cell)
	if candidates.is_empty():
		var target := _spawn_distance()
		for cell in free:
			var d := _distance_to_nearest(cell, dests)
			if absf(d - target) <= 2.0:
				candidates.append(cell)
	if candidates.is_empty():
		for cell in free:
			if _distance_to_nearest(cell, dests) >= 3.0:
				candidates.append(cell)
	if candidates.is_empty():
		return null
	return _sim.add_house(candidates[_sim.rng.randi_range(0, candidates.size() - 1)], color)


## Свободные клетки суши, не вплотную к местам назначения (чтобы не закрыть им въезд).
func _free_cells() -> Array[Vector2i]:
	var network := _sim.network
	var area := spawn_area()
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if network.is_free_land(cell) and not _touches_destination(cell):
				cells.append(cell)
	return cells


func _rect_is_free(rect: Rect2i) -> bool:
	var network := _sim.network
	for cell in _cells_of(rect):
		if not network.is_free_land(cell):
			return false
	for cell in _cells_of(rect.grow(1)):
		if network.is_building(cell):
			return false
	return true


func _far_from_destinations(rect: Rect2i, min_distance: float) -> bool:
	for dest in _sim.destinations:
		if Vector2(rect.get_center()).distance_to(Vector2(dest.rect.get_center())) < min_distance:
			return false
	return true


func _touches_destination(cell: Vector2i) -> bool:
	for dest in _sim.destinations:
		if dest.rect.grow(1).has_point(cell):
			return true
	return false


func _distance_to_nearest(cell: Vector2i, dests: Array[Destination]) -> float:
	var best := INF
	for dest in dests:
		best = minf(best, (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(Vector2(dest.rect.get_center())))
	return best


func _destinations_of(color: int) -> Array[Destination]:
	var result: Array[Destination] = []
	for dest in _sim.destinations:
		if dest.color == color:
			result.append(dest)
	return result


func _houses_of(color: int) -> Array[House]:
	var result: Array[House] = []
	for house in _sim.houses:
		if house.color == color:
			result.append(house)
	return result


static func _cells_of(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	return cells
