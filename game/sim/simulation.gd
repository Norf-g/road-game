class_name Simulation
extends RefCounted
## Партия целиком: дорожная сеть, здания, машины, заказы, очки и проигрыш.
## Время идёт фиксированными шагами tick(). Состояние меняется только командами
## (build_link, erase_cell) между шагами, поэтому одинаковые seed и команды дают одинаковую партию.

const TICK_RATE := 30
const DT := 1.0 / TICK_RATE

var balance: Balance
var network: RoadNetwork
var houses: Array[House] = []
var destinations: Array[Destination] = []
var cars: Array[Car] = []
## Очки — число выполненных поездок.
var score := 0
var tick_count := 0
var game_over := false
var rng := RandomNumberGenerator.new()

var _traffic: Traffic


func _init(map: MapData, game_balance: Balance, seed_value: int) -> void:
	balance = game_balance
	rng.seed = seed_value
	network = RoadNetwork.new(Grid.new(map.size), map.water, balance.start_tiles, balance.start_bridges)
	_traffic = Traffic.new(network, balance)
	for house: Dictionary in map.houses:
		add_house(house["cell"], house["color"])
	for dest: Dictionary in map.destinations:
		add_destination(dest["rect"], dest["entrance"], dest["color"])


func add_house(cell: Vector2i, color: int) -> House:
	var house := House.new(houses.size(), cell, color)
	houses.append(house)
	network.add_terminal(cell)
	for i in balance.cars_per_house:
		cars.append(Car.new(cars.size(), house))
	return house


func add_destination(rect: Rect2i, entrance: Vector2i, color: int) -> Destination:
	var dest := Destination.new(destinations.size(), rect, entrance, color)
	# Первые заказы у разных мест назначения появляются не одновременно.
	dest.pin_timer = rng.randf() * balance.pin_interval
	destinations.append(dest)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if cell == entrance:
				network.add_terminal(cell)
			else:
				network.add_blocked(cell)
	return dest


# --- Команды -----------------------------------------------------------------

func build_link(a: Vector2i, b: Vector2i) -> RoadNetwork.Result:
	if game_over:
		return RoadNetwork.Result.BLOCKED
	var result := network.build(a, b)
	if result == RoadNetwork.Result.OK:
		_on_network_changed()
	return result


func erase_cell(cell: Vector2i) -> bool:
	if game_over or not network.erase(cell):
		return false
	_on_network_changed()
	return true


# --- Шаг времени -------------------------------------------------------------

func tick() -> void:
	if game_over:
		return
	tick_count += 1
	_spawn_pins()
	_dispatch()
	_update_parked()
	_depart()
	for car in _traffic.step(cars, tick_count, DT):
		_on_arrived(car)
	_update_overflow()


## Отпечаток состояния для проверки детерминизма.
func state_hash() -> int:
	var parts: Array = [score, tick_count, game_over]
	for car in cars:
		parts.append([car.state, car.route, car.seg, snappedf(car.s, 0.0001), car.on_road])
	for dest in destinations:
		parts.append([dest.pins, dest.claimed, snappedf(dest.overflow, 0.001)])
	return var_to_str(parts).hash()


func _spawn_pins() -> void:
	for dest in destinations:
		dest.pin_timer += DT
		if dest.pin_timer >= balance.pin_interval:
			dest.pin_timer -= balance.pin_interval
			dest.pins += 1


## Назначает на необслуженные заказы свободные машины того же цвета — ближайшие по дорогам.
func _dispatch() -> void:
	for dest in destinations:
		if dest.pins <= dest.claimed:
			continue
		var routes := {}  # id дома -> маршрут до места назначения
		while dest.pins > dest.claimed:
			var best: Car = null
			var best_length := INF
			for car in cars:
				if car.state != Car.State.IDLE or car.home.color != dest.color:
					continue
				if not routes.has(car.home.id):
					routes[car.home.id] = network.find_path(car.home.cell, dest.entrance)
				var route: Array[Vector2i] = routes[car.home.id]
				if route.size() < 2:
					continue
				var length := RoadNetwork.path_length(route)
				if length < best_length:
					best = car
					best_length = length
			if best == null:
				break
			best.state = Car.State.TO_DEST
			best.dest = dest
			var chosen: Array[Vector2i] = routes[best.home.id]
			best.route = chosen.duplicate()
			dest.claimed += 1


func _update_parked() -> void:
	for car in cars:
		if car.state != Car.State.PARKED:
			continue
		car.park_timer -= DT
		if car.park_timer <= 0.0:
			_send_home(car)


## Выпускает на дорогу машины, которые ждут выезда из дома или с парковки.
func _depart() -> void:
	for car in cars:
		if car.on_road or (car.state != Car.State.TO_DEST and car.state != Car.State.TO_HOME):
			continue
		if _traffic.can_enter(car):
			_traffic.enter(car)


func _on_arrived(car: Car) -> void:
	if car.state == Car.State.TO_DEST:
		car.dest.pins -= 1
		car.dest.claimed -= 1
		score += 1
		car.state = Car.State.PARKED
		car.park_timer = balance.parking_time
	else:
		car.state = Car.State.IDLE
		car.route.clear()


func _send_home(car: Car) -> void:
	var route := network.find_path(car.dest.entrance, car.home.cell)
	car.dest = null
	if route.size() < 2:
		# Дороги домой нет — машина возвращается сама, как в оригинале.
		car.state = Car.State.IDLE
		car.route.clear()
		return
	car.state = Car.State.TO_HOME
	car.route = route


func _update_overflow() -> void:
	for dest in destinations:
		if dest.pins > balance.overflow_pins:
			dest.overflow += DT
		else:
			dest.overflow = maxf(dest.overflow - DT * balance.overflow_recovery, 0.0)
		if dest.overflow >= balance.overflow_time:
			game_over = true


## После изменения дорог пересчитывает маршруты. Машина, у которой пропала полоса под колёсами
## или пропал путь к цели, возвращается домой, а её заказ снова становится свободным.
func _on_network_changed() -> void:
	for car in cars:
		if car.state != Car.State.TO_DEST and car.state != Car.State.TO_HOME:
			continue
		var target: Vector2i = car.route.back()
		if not car.on_road:
			var fresh := network.find_path(car.route[0], target)
			if fresh.size() < 2:
				_abort(car)
			else:
				car.route = fresh
			continue
		var a := car.lane_from()
		var b := car.lane_to()
		if not network.are_linked(a, b):
			_abort(car)
			continue
		if b == target:
			continue
		var tail := network.find_path(b, target)
		if tail.is_empty():
			_abort(car)
			continue
		var route: Array[Vector2i] = [a]
		route.append_array(tail)
		car.route = route
		car.seg = 0
	_traffic.rebuild(cars)


func _abort(car: Car) -> void:
	_traffic.remove(car)
	if car.state == Car.State.TO_DEST:
		car.dest.claimed -= 1
	car.state = Car.State.IDLE
	car.dest = null
	car.route.clear()
