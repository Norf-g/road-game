class_name Traffic
extends RefCounted
## Движение машин по полосам: дистанция, очереди и проезд перекрёстков.
## Полоса — направленный отрезок между центрами связанных клеток. Движение правостороннее,
## поэтому встречные полосы друг другу не мешают.
## Перекрёсток — клетка с тремя и более связями. Машина въезжает в него, только получив разрешение,
## и только если за перекрёстком есть место — так она не застрянет посередине. Одновременно едут
## машины, чьи траектории не пересекаются (например, встречные прямо).
## - Обычный перекрёсток: «уступи дорогу» — машина стоит yield_time и едет в порядке очереди.
## - Светофор: направления по очереди получают зелёный; на зелёный едут без остановки.
## - Развязка: без остановки и без проверки траекторий, но не больше roundabout_capacity машин.

## Смещение полосы вправо от оси дороги.
const LANE_OFFSET := 0.12

var _network: RoadNetwork
var _balance: Balance
var _lanes: Dictionary = {}   # Vector4i -> Array[Car]
var _inside: Dictionary = {}  # клетка перекрёстка -> Array[Car], которым разрешён проезд


func _init(network: RoadNetwork, balance: Balance) -> void:
	_network = network
	_balance = balance


static func lane_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y)


## Траектория проезда перекрёстка at из клетки from в клетку to: [точка въезда, точка выезда]
## относительно центра перекрёстка, по правым полосам.
static func movement(from: Vector2i, at: Vector2i, to: Vector2i) -> PackedVector2Array:
	var dir_in := (Vector2(at) - Vector2(from)).normalized()
	var dir_out := (Vector2(to) - Vector2(at)).normalized()
	return PackedVector2Array([
		-dir_in * 0.5 + _right(dir_in) * LANE_OFFSET,
		dir_out * 0.5 + _right(dir_out) * LANE_OFFSET,
	])


## Мешают ли друг другу два проезда одного перекрёстка: [from, to] каждой машины.
static func movements_conflict(at: Vector2i, first: Array, second: Array) -> bool:
	if first[0] == second[0]:
		return false  # с одной полосы едут друг за другом, дистанцию держит очередь
	if first[1] == second[1]:
		return true  # сливаются в одну полосу
	var a := movement(first[0], at, first[1])
	var b := movement(second[0], at, second[1])
	return Geometry2D.segment_intersects_segment(a[0], a[1], b[0], b[1]) != null


static func _right(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)


## Можно ли выехать из здания: у начала первой полосы маршрута есть место.
func can_enter(car: Car) -> bool:
	return _min_s(lane_key(car.route[0], car.route[1])) >= _balance.car_gap


func enter(car: Car) -> void:
	car.seg = 0
	car.s = 0.0
	car.on_road = true
	_lane_add(car)


func remove(car: Car) -> void:
	if car.on_road:
		_lane_remove(car)
		car.on_road = false
	if car.has_lock:
		_release(car)
	car.wait_since = -1


## Пересобирает полосы после того, как у машин поменялись маршруты.
func rebuild(cars: Array[Car]) -> void:
	_lanes.clear()
	for car in cars:
		if car.on_road:
			_lane_add(car)


## Один шаг движения. Возвращает машины, доехавшие до конца маршрута; они уже сняты с дороги.
func step(cars: Array[Car], tick: int, dt: float) -> Array[Car]:
	_update_intersections(cars, tick, dt)
	var arrived: Array[Car] = []
	for car in cars:
		if not car.on_road:
			continue
		var speed := _balance.car_speed * _network.speed_factor(car.lane_from(), car.lane_to())
		var advance := minf(speed * dt, _free_distance(car))
		if advance <= 0.0:
			continue
		car.s += advance
		var length := RoadNetwork.lane_length(car.lane_from(), car.lane_to())
		while car.s >= length:
			if car.is_on_last_lane():
				arrived.append(car)
				break
			_lane_remove(car)
			car.s -= length
			car.seg += 1
			_lane_add(car)
			length = RoadNetwork.lane_length(car.lane_from(), car.lane_to())
	for car in arrived:
		remove(car)
	return arrived


## Сколько машина может проехать до препятствия: машины впереди или стоп-линии перекрёстка.
func _free_distance(car: Car) -> float:
	var a := car.lane_from()
	var b := car.lane_to()
	var gap := _balance.car_gap
	var leader := INF
	for other: Car in _lanes.get(lane_key(a, b), []):
		if other != car and (other.s > car.s or (other.s == car.s and other.id < car.id)):
			leader = minf(leader, other.s)
	if leader < INF:
		return maxf(leader - car.s - gap, 0.0)
	var to_end := RoadNetwork.lane_length(a, b) - car.s
	if car.is_on_last_lane():
		return to_end + 1.0  # дальше только въезд в здание
	if _network.is_intersection(b) and not (car.has_lock and car.lock_cell == b):
		return maxf(to_end - _balance.intersection_radius, 0.0)
	var c := car.route[car.seg + 2]
	var next_min := _min_s(lane_key(b, c))
	if next_min < INF:
		return maxf(to_end + next_min - gap, 0.0)
	return to_end + RoadNetwork.lane_length(b, c)


func _update_intersections(cars: Array[Car], tick: int, dt: float) -> void:
	for cell: Vector2i in _inside.keys():
		for car: Car in (_inside[cell] as Array).duplicate():
			if not _still_inside(car, cell):
				_release(car)

	var radius := _balance.intersection_radius
	var requests := {}  # клетка перекрёстка -> Array[Car]
	for car in cars:
		if not car.on_road or car.has_lock:
			continue
		var b := car.lane_to()
		var length := RoadNetwork.lane_length(car.lane_from(), b)
		if not _network.is_intersection(b) or car.s < length - radius - 0.001:
			car.wait_since = -1
			continue
		if car.wait_since < 0:
			car.wait_since = tick
		if not requests.has(b):
			requests[b] = []
		(requests[b] as Array).append(car)

	for cell: Vector2i in requests:
		var queue: Array = requests[cell]
		queue.sort_custom(func(x: Car, y: Car) -> bool:
			return x.wait_since < y.wait_since or (x.wait_since == y.wait_since and x.id < y.id))
		_grant(cell, queue, tick, dt)


## Разрешает проезд машинам из очереди в порядке подъезда. Машина, которая уже могла бы ехать,
## но ей мешают, не даёт проехать тем, кто подъехал позже и мешал бы ей, — без обгонов очереди.
func _grant(cell: Vector2i, queue: Array, tick: int, dt: float) -> void:
	var control := _network.control_at(cell)
	var inside: Array = _inside.get(cell, [])
	var held_back: Array[Array] = []  # проезды машин, которые ждут своей очереди
	for car: Car in queue:
		var move := [car.lane_from(), car.route[car.seg + 2]]
		var eligible := false
		match control:
			RoadNetwork.Junction.ROUNDABOUT:
				eligible = inside.size() < _balance.roundabout_capacity
			RoadNetwork.Junction.LIGHT:
				eligible = _is_green(cell, car.lane_from(), tick * dt)
			_:
				eligible = (tick - car.wait_since) * dt >= _balance.yield_time
		if not eligible:
			continue
		var clear := _min_s(lane_key(cell, move[1])) >= _balance.intersection_radius + _balance.car_gap
		if clear and control != RoadNetwork.Junction.ROUNDABOUT:
			for other: Car in inside:
				if movements_conflict(cell, move, [other.lock_from, other.lock_to]):
					clear = false
					break
			for waiting in held_back:
				if clear and movements_conflict(cell, move, waiting):
					clear = false
		if not clear:
			held_back.append(move)
			continue
		inside.append(car)
		car.has_lock = true
		car.lock_cell = cell
		car.lock_from = move[0]
		car.lock_to = move[1]
		car.wait_since = -1
	if not inside.is_empty():
		_inside[cell] = inside


## Зелёный ли свет для машины, въезжающей на перекрёсток cell из клетки from.
## Фазы — группы встречных направлений; каждая горит light_phase_time секунд.
func _is_green(cell: Vector2i, from: Vector2i, time: float) -> bool:
	var groups := _light_groups(cell)
	var phase := int(time / _balance.light_phase_time) % groups.size()
	var arm := (Vector2(from) - Vector2(cell)).normalized()
	for dir: Vector2 in groups[phase]:
		if dir.dot(arm) > 0.99:
			return true
	return false


func _light_groups(cell: Vector2i) -> Array[Array]:
	var arms: Array[Vector2] = []
	for neighbor: Vector2i in _network.links_of(cell):
		arms.append((Vector2(neighbor) - Vector2(cell)).normalized())
	arms.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.angle() < y.angle())
	var groups: Array[Array] = []
	var used := {}
	for i in arms.size():
		if used.has(i):
			continue
		var group := [arms[i]]
		used[i] = true
		for j in range(i + 1, arms.size()):
			if not used.has(j) and arms[i].dot(arms[j]) < -0.99:
				group.append(arms[j])
				used[j] = true
		groups.append(group)
	return groups


func _still_inside(car: Car, cell: Vector2i) -> bool:
	if not car.on_road:
		return false
	if car.lane_to() == cell:
		return true
	return car.lane_from() == cell and car.s < _balance.intersection_radius


func _release(car: Car) -> void:
	var inside: Array = _inside.get(car.lock_cell, [])
	inside.erase(car)
	if inside.is_empty():
		_inside.erase(car.lock_cell)
	car.has_lock = false


func _min_s(key: Vector4i) -> float:
	var result := INF
	for other: Car in _lanes.get(key, []):
		result = minf(result, other.s)
	return result


func _lane_add(car: Car) -> void:
	var key := lane_key(car.lane_from(), car.lane_to())
	if not _lanes.has(key):
		_lanes[key] = []
	(_lanes[key] as Array).append(car)


func _lane_remove(car: Car) -> void:
	var key := lane_key(car.lane_from(), car.lane_to())
	var lane: Array = _lanes.get(key, [])
	lane.erase(car)
	if lane.is_empty():
		_lanes.erase(key)
