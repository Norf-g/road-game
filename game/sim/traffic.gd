class_name Traffic
extends RefCounted
## Движение машин по полосам: дистанция, очереди и перекрёстки по правилу «кто первый подъехал».
## Полоса — направленный отрезок между центрами соседних клеток. Движение правостороннее,
## поэтому встречные полосы друг другу не мешают.
## Через перекрёсток (клетку с тремя и более связями) одновременно проезжает одна машина: она
## держит «замок» клетки и получает его, только если за перекрёстком есть место — так машины
## не застревают посреди перекрёстка.

var _network: RoadNetwork
var _balance: Balance
var _lanes: Dictionary = {}  # Vector4i -> Array[Car]
var _locks: Dictionary = {}  # клетка перекрёстка -> Car


func _init(network: RoadNetwork, balance: Balance) -> void:
	_network = network
	_balance = balance


static func lane_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y)


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
		_locks.erase(car.lock_cell)
		car.has_lock = false
	car.wait_since = -1


## Пересобирает полосы после того, как у машин поменялись маршруты.
func rebuild(cars: Array[Car]) -> void:
	_lanes.clear()
	for car in cars:
		if car.on_road:
			_lane_add(car)


## Один шаг движения. Возвращает машины, доехавшие до конца маршрута; они уже сняты с дороги.
func step(cars: Array[Car], tick: int, dt: float) -> Array[Car]:
	_update_locks(cars, tick)
	var arrived: Array[Car] = []
	var max_step := _balance.car_speed * dt
	for car in cars:
		if not car.on_road:
			continue
		var advance := minf(max_step, _free_distance(car))
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


func _update_locks(cars: Array[Car], tick: int) -> void:
	for cell: Vector2i in _locks.keys():
		var holder: Car = _locks[cell]
		if not _still_needs_lock(holder, cell):
			_locks.erase(cell)
			holder.has_lock = false

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
		if _locks.has(cell):
			continue
		var queue: Array = requests[cell]
		queue.sort_custom(func(x: Car, y: Car) -> bool:
			return x.wait_since < y.wait_since or (x.wait_since == y.wait_since and x.id < y.id))
		for car: Car in queue:
			var exit_lane := lane_key(cell, car.route[car.seg + 2])
			if _min_s(exit_lane) >= radius + _balance.car_gap:
				_locks[cell] = car
				car.has_lock = true
				car.lock_cell = cell
				car.wait_since = -1
				break


func _still_needs_lock(car: Car, cell: Vector2i) -> bool:
	if not car.on_road:
		return false
	if car.lane_to() == cell:
		return true
	return car.lane_from() == cell and car.s < _balance.intersection_radius


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
