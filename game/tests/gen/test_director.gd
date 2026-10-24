extends GutTest

# 20×12, река посередине, видимая часть растёт на второй неделе.
const MAP := {
	"rows": [
		".........~~.........", ".........~~.........", ".........~~.........",
		".........~~.........", ".........~~.........", ".........~~.........",
		".........~~.........", ".........~~.........", ".........~~.........",
		".........~~.........", ".........~~.........", ".........~~.........",
	],
	"expansions": [
		{"week": 0, "rect": [4, 2, 12, 8]},
		{"week": 2, "rect": [0, 0, 20, 12]},
	],
}


func _game(seed_value := 7, overrides := {}) -> Array:
	var balance := {"week_seconds": 10.0, "house_interval": 2.0, "color_weeks": [0, 1, 2]}
	balance.merge(overrides, true)
	var map := MapData.from_dict(MAP)
	var sim := Simulation.new(map, Balance.from_dict(balance), seed_value)
	var director := Director.new(sim, map)
	return [sim, director]


## Крутит партию seconds секунд, выбирая первое улучшение в конце каждой недели.
func _run(sim: Simulation, director: Director, seconds: float) -> void:
	for i in int(seconds * Simulation.TICK_RATE):
		if director.has_offer():
			director.choose(0)
		sim.tick()


func test_first_color_appears_at_start() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	assert_eq(sim.destinations.size(), 1)
	assert_eq(sim.houses.size(), sim.balance.houses_per_new_color)


func test_buildings_appear_on_free_land_inside_area() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	var director: Director = game[1]
	_run(sim, director, 25.0)
	var area := director.spawn_area()
	assert_eq(area, director.area().grow(-1), "отступ от края — одна клетка")
	var taken := {}
	for house in sim.houses:
		assert_true(area.has_point(house.cell), "дом вне видимой части карты или у самого края")
		assert_false(sim.network.is_water(house.cell), "дом на воде")
		assert_false(taken.has(house.cell), "два дома в одной клетке")
		taken[house.cell] = true
	for dest in sim.destinations:
		for y in range(dest.rect.position.y, dest.rect.end.y):
			for x in range(dest.rect.position.x, dest.rect.end.x):
				var cell := Vector2i(x, y)
				assert_true(area.has_point(cell))
				assert_false(sim.network.is_water(cell))
				assert_false(taken.has(cell), "здания пересекаются")
				taken[cell] = true


func test_week_end_offers_upgrade_and_stops_time() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	var director: Director = game[1]
	var tiles := sim.network.tiles_left
	for i in int(sim.balance.week_seconds * Simulation.TICK_RATE) + 1:
		sim.tick()
	assert_true(director.has_offer())
	assert_eq(director.week, 1)
	assert_eq(director.offer.size(), 2)
	assert_ne(director.offer[0], director.offer[1])
	assert_eq(sim.network.tiles_left, tiles + sim.balance.week_tiles)
	var frozen := sim.tick_count
	sim.tick()
	assert_eq(sim.tick_count, frozen, "пока игрок выбирает улучшение, время стоит")
	director.offer = [Director.Upgrade.MOTORWAY, Director.Upgrade.LIGHT]
	director.choose(0)
	assert_eq(sim.network.motorways_left, 1)
	assert_false(director.has_offer())
	sim.tick()
	assert_eq(sim.tick_count, frozen + 1)


func test_new_colors_and_area_by_weeks() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	var director: Director = game[1]
	assert_eq(director.area(), Rect2i(4, 2, 12, 8))
	_run(sim, director, 21.0)
	assert_eq(director.week, 2)
	assert_eq(director.area(), Rect2i(0, 0, 20, 12))
	var colors := {}
	for dest in sim.destinations:
		colors[dest.color] = true
	assert_eq(colors.size(), 3)


func test_pins_come_faster_each_week() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	var director: Director = game[1]
	var first := sim.pin_interval
	_run(sim, director, 11.0)
	assert_lt(sim.pin_interval, first)


func test_same_seed_same_city() -> void:
	var hashes: Array[int] = []
	for attempt in 2:
		var game := _game(99)
		_run(game[0], game[1], 35.0)
		hashes.append((game[0] as Simulation).state_hash())
	assert_eq(hashes[0], hashes[1])
	var other := _game(100)
	_run(other[0], other[1], 35.0)
	assert_ne((other[0] as Simulation).state_hash(), hashes[0], "другой seed — другой город")


func test_color_waits_for_room_instead_of_being_skipped() -> void:
	# Крошечная стартовая область: месту назначения второго цвета сначала негде встать.
	var map := MapData.from_dict({
		"rows": ["............", "............", "............", "............", "............", "............"],
		"expansions": [{"week": 0, "rect": [0, 0, 5, 5]}, {"week": 2, "rect": [0, 0, 12, 6]}],
	})
	var balance := Balance.from_dict({"week_seconds": 10.0, "house_interval": 1.0, "color_weeks": [0, 1]})
	var sim := Simulation.new(map, balance, 3)
	var director := Director.new(sim, map)
	_run(sim, director, 25.0)
	var colors := {}
	for dest in sim.destinations:
		colors[dest.color] = true
	assert_true(colors.has(1), "второй цвет появляется, когда для него находится место")


func test_destinations_are_two_by_three_with_stub() -> void:
	var game := _game()
	var sim: Simulation = game[0]
	_run(sim, game[1], 25.0)
	for dest in sim.destinations:
		assert_true(dest.rect.size == Vector2i(2, 3) or dest.rect.size == Vector2i(3, 2))
		assert_not_null(dest.stub)
		assert_false(dest.rect.has_point(dest.stub), "подъезд снаружи здания")
		assert_eq((dest.stub - dest.entrance).length_squared(), 1, "подъезд — прямо рядом с парковкой")
		assert_true(sim.network.is_permanent(dest.stub))


func test_no_bridge_offers_without_water() -> void:
	var map := MapData.from_dict({"rows": ["..........", "..........", "..........", "..........", ".........."]})
	var balance := Balance.from_dict({"week_seconds": 2.0, "house_interval": 100.0, "color_weeks": [0]})
	var sim := Simulation.new(map, balance, 5)
	var director := Director.new(sim, map)
	for i in int(30.0 * Simulation.TICK_RATE):
		if director.has_offer():
			assert_false(director.offer.has(Director.Upgrade.BRIDGES), "без воды мосты не предлагаются")
			director.choose(0)
		sim.tick()
	assert_gt(director.week, 5)

