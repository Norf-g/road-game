extends GutTest

# Красный дом слева, красное место назначения справа (вход в клетке (4, 0)).
const LINE_MAP := {
	"rows": ["......", "......"],
	"houses": [{"cell": [0, 0], "color": 0}],
	"destinations": [{"rect": [4, 0, 2, 2], "entrance": [4, 0], "color": 0}],
}

# Крест: красный маршрут идёт слева направо, синий — сверху вниз, пересекаются в (3, 3).
const CROSS_MAP := {
	"rows": [".......", ".......", ".......", ".......", ".......", ".......", "......."],
	"houses": [{"cell": [0, 3], "color": 0}, {"cell": [3, 0], "color": 1}],
	"destinations": [
		{"rect": [5, 3, 2, 2], "entrance": [5, 3], "color": 0},
		{"rect": [3, 5, 2, 2], "entrance": [3, 5], "color": 1},
	],
}


func _sim(map: Dictionary, overrides := {}, seed_value := 1) -> Simulation:
	var balance := {
		"start_tiles": 50, "cars_per_house": 1, "car_speed": 2.0, "parking_time": 0.5,
		"pin_interval": 1.0, "overflow_pins": 100, "overflow_time": 1000.0,
	}
	balance.merge(overrides, true)
	return Simulation.new(MapData.from_dict(map), Balance.from_dict(balance), seed_value)


func _build_path(sim: Simulation, cells: Array) -> void:
	for i in range(1, cells.size()):
		assert_eq(sim.build_link(cells[i - 1], cells[i]), RoadNetwork.Result.OK)


func _build_line(sim: Simulation) -> void:
	_build_path(sim, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])


func _build_cross(sim: Simulation) -> void:
	_build_path(sim, [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)])
	_build_path(sim, [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)])
	_build_path(sim, [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)])


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * Simulation.TICK_RATE):
		sim.tick()


func test_car_delivers_and_returns_home() -> void:
	var sim := _sim(LINE_MAP)
	_build_line(sim)
	var car: Car = sim.cars[0]
	var saw_parked := false
	for i in 20 * Simulation.TICK_RATE:
		sim.tick()
		saw_parked = saw_parked or car.state == Car.State.PARKED
		if saw_parked and car.state == Car.State.IDLE:
			break
	assert_true(saw_parked, "машина должна доехать и встать на парковку")
	assert_eq(car.state, Car.State.IDLE, "машина должна вернуться домой")
	assert_gt(sim.score, 0)


func test_cars_keep_distance_on_lane() -> void:
	var sim := _sim(LINE_MAP, {"cars_per_house": 4, "pin_interval": 0.2})
	_build_line(sim)
	var gap := sim.balance.car_gap
	for i in 15 * Simulation.TICK_RATE:
		sim.tick()
		var lanes := {}
		for car in sim.cars:
			if car.on_road:
				var key := Traffic.lane_key(car.lane_from(), car.lane_to())
				if not lanes.has(key):
					lanes[key] = []
				(lanes[key] as Array).append(car.s)
		for key: Vector4i in lanes:
			var positions: Array = lanes[key]
			positions.sort()
			for j in range(1, positions.size()):
				assert_true(positions[j] - positions[j - 1] >= gap - 0.001,
					"машины на одной полосе ближе дистанции на тике %d" % sim.tick_count)
	assert_gt(sim.score, 4)


func test_intersection_lets_one_car_at_a_time() -> void:
	var sim := _sim(CROSS_MAP, {"cars_per_house": 3, "pin_interval": 0.3})
	_build_cross(sim)
	var center := Vector2i(3, 3)
	var radius := sim.balance.intersection_radius
	var max_inside := 0
	for i in 30 * Simulation.TICK_RATE:
		sim.tick()
		var inside := 0
		for car in sim.cars:
			if not car.on_road:
				continue
			var length := RoadNetwork.lane_length(car.lane_from(), car.lane_to())
			if (car.lane_to() == center and car.s > length - radius + 0.001) \
					or (car.lane_from() == center and car.s < radius - 0.001):
				inside += 1
		max_inside = maxi(max_inside, inside)
	assert_eq(max_inside, 1, "в зоне перекрёстка не больше одной машины")
	assert_gt(sim.score, 10, "перекрёсток не должен вставать намертво")


func test_game_over_when_destination_overflows() -> void:
	var sim := _sim(LINE_MAP, {"pin_interval": 0.5, "overflow_pins": 1, "overflow_time": 2.0})
	_run(sim, 5.0)
	assert_true(sim.game_over)


func test_no_game_over_while_served() -> void:
	var sim := _sim(LINE_MAP, {"pin_interval": 4.0, "overflow_pins": 2, "overflow_time": 3.0})
	_build_line(sim)
	_run(sim, 60.0)
	assert_false(sim.game_over)


func test_erasing_road_under_car_sends_it_home() -> void:
	var sim := _sim(LINE_MAP)
	_build_line(sim)
	var car: Car = sim.cars[0]
	for i in 10 * Simulation.TICK_RATE:
		sim.tick()
		if car.on_road and car.state == Car.State.TO_DEST and car.lane_to() == Vector2i(2, 0):
			break
	assert_true(car.on_road)
	assert_true(sim.erase_cell(Vector2i(2, 0)))
	assert_eq(car.state, Car.State.IDLE)
	assert_false(car.on_road)
	assert_eq(sim.destinations[0].claimed, 0)


func test_same_seed_and_commands_give_same_game() -> void:
	var hashes: Array[int] = []
	for attempt in 2:
		var sim := _sim(CROSS_MAP, {"cars_per_house": 2, "pin_interval": 0.7}, 42)
		_build_cross(sim)
		_run(sim, 10.0)
		sim.erase_cell(Vector2i(3, 4))
		_run(sim, 10.0)
		hashes.append(sim.state_hash())
	assert_eq(hashes[0], hashes[1])
