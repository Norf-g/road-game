extends GutTest

const OK := RoadNetwork.Result.OK


## Сеть по карте rows. Если anchored, в клетке (0, 0) стоит вход здания — от него начинаются дороги.
func _network(rows: Array, tiles := 10, bridges := 1, anchored := true) -> RoadNetwork:
	var map := MapData.from_dict({"rows": rows})
	var net := RoadNetwork.new(Grid.new(map.size), map.water, tiles, bridges)
	if anchored:
		net.add_terminal(Vector2i(0, 0))
	return net


func test_build_spends_tiles_and_erase_returns_them() -> void:
	var net := _network(["....."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.tiles_left, 8)
	assert_true(net.erase(Vector2i(1, 0)))
	assert_eq(net.tiles_left, 9)
	assert_false(net.are_linked(Vector2i(0, 0), Vector2i(1, 0)))
	assert_false(net.are_linked(Vector2i(1, 0), Vector2i(2, 0)))


func test_build_fails_without_tiles() -> void:
	var net := _network(["....."], 0)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), RoadNetwork.Result.NO_TILES)
	assert_eq(net.tiles_left, 0)


func test_build_rejects_far_cells_and_repeats() -> void:
	var net := _network(["....."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(2, 0)), RoadNetwork.Result.NOT_ADJACENT)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(0, 0)), RoadNetwork.Result.ALREADY_LINKED)


func test_diagonals_cannot_cross() -> void:
	var net := _network(["...", "..."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 1)), OK)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(0, 1)), RoadNetwork.Result.CROSSING)


func test_bridge_span_uses_one_bridge_and_no_tiles() -> void:
	var net := _network([".~~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), OK)
	assert_eq(net.bridges_used, 1)
	assert_eq(net.tiles_left, 9)


func test_second_span_needs_second_bridge() -> void:
	var net := _network([".~.~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.NO_BRIDGES)


func test_erasing_bridge_returns_it() -> void:
	var net := _network([".~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.bridges_used, 1)
	assert_true(net.erase(Vector2i(1, 0)))
	assert_eq(net.bridges_used, 0)


func test_cannot_build_inside_building() -> void:
	var net := _network(["...."])
	net.add_blocked(Vector2i(2, 0))
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), RoadNetwork.Result.BLOCKED)


func test_path_does_not_pass_through_buildings() -> void:
	var net := _network([".....", "....."], 20)
	net.add_terminal(Vector2i(2, 0))
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), OK)
	assert_true(net.find_path(Vector2i(1, 0), Vector2i(3, 0)).is_empty())
	assert_eq(net.find_path(Vector2i(2, 0), Vector2i(3, 0)).size(), 2)

	for pair: Array in [[Vector2i(1, 0), Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)],
			[Vector2i(2, 1), Vector2i(3, 1)], [Vector2i(3, 1), Vector2i(3, 0)]]:
		assert_eq(net.build(pair[0], pair[1]), OK)
	var detour := net.find_path(Vector2i(1, 0), Vector2i(3, 0))
	assert_eq(detour.size(), 5)
	assert_does_not_have(detour, Vector2i(2, 0))


func test_path_prefers_diagonal() -> void:
	var net := _network(["...", "..."], 20)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(1, 1)), OK)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 1)), OK)
	assert_eq(net.find_path(Vector2i(0, 0), Vector2i(1, 1)).size(), 2)


func test_cannot_build_outside_visible_area() -> void:
	var net := _network([".....", "....."])
	net.bounds = Rect2i(0, 0, 3, 2)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.OUT_OF_BOUNDS)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)


func test_motorway_spends_stock_and_erase_returns_it() -> void:
	var net := _network([".........."], 10, 1, false)
	net.motorways_left = 1
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(6, 0)), OK)
	assert_eq(net.motorways_left, 0)
	assert_eq(net.tiles_left, 8)
	assert_true(net.is_motorway(Vector2i(6, 0), Vector2i(0, 0)))
	assert_true(net.erase(Vector2i(6, 0)))
	assert_eq(net.motorways_left, 1)
	assert_false(net.is_motorway(Vector2i(0, 0), Vector2i(6, 0)))


func test_motorway_limits() -> void:
	var net := _network(["..............~"], 20, 1, false)
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(5, 0)), RoadNetwork.Result.NO_STOCK)
	net.motorways_left = 1
	net.motorway_max_length = 5.0
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(8, 0)), RoadNetwork.Result.TOO_LONG)
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(1, 0)), RoadNetwork.Result.NOT_ADJACENT)
	net.motorway_max_length = 20.0
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(14, 0)), RoadNetwork.Result.BLOCKED)


func test_path_prefers_motorway() -> void:
	var net := _network(["........", "........"], 30)
	for x in 7:
		assert_eq(net.build(Vector2i(x, 0), Vector2i(x + 1, 0)), OK)
	net.motorways_left = 1
	assert_eq(net.build(Vector2i(0, 0), Vector2i(0, 1)), OK)
	assert_eq(net.build(Vector2i(7, 0), Vector2i(7, 1)), OK)
	assert_eq(net.build_motorway(Vector2i(0, 1), Vector2i(7, 1)), OK)
	assert_eq(Array(net.find_path(Vector2i(0, 0), Vector2i(7, 0))), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(7, 1), Vector2i(7, 0)])


func test_control_needs_intersection_and_stock() -> void:
	var net := _network(["...", "..."], 10)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.place_control(Vector2i(1, 0), RoadNetwork.Junction.LIGHT), RoadNetwork.Result.NOT_INTERSECTION)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(1, 1)), OK)
	assert_eq(net.place_control(Vector2i(1, 0), RoadNetwork.Junction.LIGHT), RoadNetwork.Result.NO_STOCK)
	net.lights_left = 1
	assert_eq(net.place_control(Vector2i(1, 0), RoadNetwork.Junction.LIGHT), OK)
	assert_eq(net.lights_left, 0)
	assert_eq(net.control_at(Vector2i(1, 0)), RoadNetwork.Junction.LIGHT)


func test_control_returns_when_intersection_disappears() -> void:
	var net := _network(["...", "..."], 10)
	for pair: Array in [[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)], [Vector2i(1, 0), Vector2i(1, 1)]]:
		assert_eq(net.build(pair[0], pair[1]), OK)
	net.roundabouts_left = 1
	assert_eq(net.place_control(Vector2i(1, 0), RoadNetwork.Junction.ROUNDABOUT), OK)
	assert_true(net.erase(Vector2i(1, 1)))
	assert_eq(net.control_at(Vector2i(1, 0)), RoadNetwork.Junction.NONE)
	assert_eq(net.roundabouts_left, 1)


func test_road_must_continue_network() -> void:
	var net := _network(["....."])
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.NOT_CONNECTED)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)


func test_bridge_cannot_turn_along_river() -> void:
	var net := _network([".~.", ".~.", ".~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(1, 1)), RoadNetwork.Result.BRIDGE_SHAPE)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 1)), RoadNetwork.Result.BRIDGE_SHAPE, "мост без развилок")


func test_bridge_length_is_limited() -> void:
	var net := _network([".~~~~~."], 10, 1)
	net.bridge_max_length = 4
	for x in 4:
		assert_eq(net.build(Vector2i(x, 0), Vector2i(x + 1, 0)), OK)
	assert_eq(net.build(Vector2i(4, 0), Vector2i(5, 0)), RoadNetwork.Result.BRIDGE_TOO_LONG)


func test_diagonal_cannot_cut_river_corner() -> void:
	# Суша (0, 0) и (1, 1), вода в двух других углах.
	var net := _network([".~", "~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 1)), RoadNetwork.Result.BLOCKED)


func test_house_has_only_one_exit() -> void:
	var net := _network([".....", "....."], 10, 1, false)
	net.add_terminal(Vector2i(2, 0), 1)
	net.add_terminal(Vector2i(0, 0))
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK, "дом подключается к дороге")
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.TERMINAL_FULL, "второй выезд из дома")
	assert_eq(net.build(Vector2i(1, 1), Vector2i(2, 0)), RoadNetwork.Result.TERMINAL_FULL)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(1, 0)), RoadNetwork.Result.ALREADY_LINKED)
	assert_true(net.erase(Vector2i(1, 0)))
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), OK, "после сноса дорога ведёт в другую сторону")


func test_two_houses_can_be_linked() -> void:
	var net := _network(["...."], 10, 1, false)
	net.add_terminal(Vector2i(0, 0), 1)
	net.add_terminal(Vector2i(1, 0), 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)


func test_house_exit_can_be_moved_to_new_road() -> void:
	var net := _network([".....", "....."], 10, 1, false)
	net.add_terminal(Vector2i(2, 0), 1)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(1, 0)), OK)
	assert_eq(net.relink_terminal(Vector2i(2, 0), Vector2i(3, 0)), OK)
	assert_eq(net.links_of(Vector2i(2, 0)), [Vector2i(3, 0)])
	assert_true(net.is_road(Vector2i(1, 0)), "старая дорога остаётся")
	assert_eq(net.relink_terminal(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.ALREADY_LINKED)


func test_failed_relink_keeps_old_exit() -> void:
	var net := _network([".....", "....."], 1, 1, false)
	net.add_terminal(Vector2i(2, 0), 1)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(1, 0)), OK)
	assert_eq(net.relink_terminal(Vector2i(2, 0), Vector2i(3, 0)), RoadNetwork.Result.NO_TILES)
	assert_eq(net.links_of(Vector2i(2, 0)), [Vector2i(1, 0)])


func test_relink_does_not_lose_neighbor_light_on_failure() -> void:
	# Дом (1, 1) — четвёртая ветка перекрёстка (1, 0) со светофором.
	var net := _network(["...", "..."], 2, 1, true)
	net.add_terminal(Vector2i(1, 1), 1)
	for pair: Array in [[Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(2, 0)], [Vector2i(1, 0), Vector2i(1, 1)]]:
		assert_eq(net.build(pair[0], pair[1]), OK)
	net.lights_left = 1
	assert_eq(net.place_control(Vector2i(1, 0), RoadNetwork.Junction.LIGHT), OK)
	assert_eq(net.relink_terminal(Vector2i(1, 1), Vector2i(0, 1)), RoadNetwork.Result.NO_TILES)
	assert_eq(net.control_at(Vector2i(1, 0)), RoadNetwork.Junction.LIGHT)


func _motorway_net() -> RoadNetwork:
	var net := _network(["............", "............"], 10, 1, false)
	net.motorways_left = 1
	assert_eq(net.build_motorway(Vector2i(0, 0), Vector2i(6, 0)), OK)
	return net


func test_motorway_end_can_be_moved() -> void:
	var net := _motorway_net()
	assert_eq(net.motorway_partner(Vector2i(6, 0)), Vector2i(0, 0))
	assert_eq(net.move_motorway_end(Vector2i(0, 0), Vector2i(6, 0), Vector2i(9, 1)), OK)
	assert_true(net.is_motorway(Vector2i(0, 0), Vector2i(9, 1)))
	assert_false(net.is_road(Vector2i(6, 0)), "старый конец без других дорог убран")
	assert_eq(net.tiles_left, 8, "клетка старого конца вернулась, новая потрачена")
	assert_eq(net.motorways_left, 0, "перенос не тратит запас шоссе")


func test_moved_end_keeps_player_road() -> void:
	var net := _motorway_net()
	assert_eq(net.build(Vector2i(6, 0), Vector2i(7, 0)), OK)
	assert_eq(net.move_motorway_end(Vector2i(0, 0), Vector2i(6, 0), Vector2i(6, 1)), OK)
	assert_true(net.is_road(Vector2i(6, 0)), "от старого конца начинается дорога игрока — клетка остаётся")
	assert_false(net.is_motorway(Vector2i(0, 0), Vector2i(6, 0)))


func test_invalid_move_changes_nothing() -> void:
	var net := _motorway_net()
	net.motorway_max_length = 8.0
	assert_eq(net.plan_motorway_move(Vector2i(0, 0), Vector2i(6, 0), Vector2i(11, 0))["result"], RoadNetwork.Result.TOO_LONG)
	assert_eq(net.move_motorway_end(Vector2i(0, 0), Vector2i(6, 0), Vector2i(11, 0)), RoadNetwork.Result.TOO_LONG)
	assert_true(net.is_motorway(Vector2i(0, 0), Vector2i(6, 0)))
	assert_eq(net.tiles_left, 8)
	assert_eq(net.motorways_left, 0)


## Дорога по строке 2 от входа здания (0, 2) до (8, 2).
func _road_net() -> RoadNetwork:
	var net := _network(["..........", "..........", "..........", "..........", ".........."], 30, 1, false)
	net.add_terminal(Vector2i(0, 2))
	for x in 8:
		assert_eq(net.build(Vector2i(x, 2), Vector2i(x + 1, 2)), OK)
	net.motorways_left = 1
	return net


func test_motorway_attaches_beside_road() -> void:
	var net := _road_net()
	# Шоссе ведут из середины дороги (4, 2) к дальней точке (9, 4).
	var plan := net.plan_motorway(Vector2i(4, 2), Vector2i(9, 4))
	assert_eq(plan["result"], OK)
	var start: Vector2i = plan["ends"][0]
	assert_ne(start, Vector2i(4, 2), "конец шоссе не встаёт на саму дорогу")
	assert_eq(plan["attach"][0], Vector2i(4, 2))
	assert_eq(net.build_motorway_planned(Vector2i(4, 2), Vector2i(9, 4)), OK)
	assert_true(net.is_motorway(start, Vector2i(9, 4)))
	assert_true(net.are_linked(start, Vector2i(4, 2)), "конец подключён к дороге сбоку")
	assert_eq(net.links_of(Vector2i(4, 2)).size(), 3)


func test_motorway_takes_free_side_of_intersection() -> void:
	var net := _road_net()
	assert_eq(net.build(Vector2i(4, 2), Vector2i(4, 1)), OK)
	assert_eq(net.build(Vector2i(4, 2), Vector2i(4, 3)), OK)
	# Перекрёсток (4, 2): заняты запад, восток, север, юг — шоссе займёт свободную диагональ.
	assert_eq(net.build_motorway_planned(Vector2i(4, 2), Vector2i(9, 4)), OK)
	var start: Variant = null
	for cell: Vector2i in net.links_of(Vector2i(4, 2)):
		if net.motorway_partner(cell) != null:
			start = cell
	assert_not_null(start)
	assert_eq(maxi(absi(start.x - 4), absi(start.y - 2)), 1)
	assert_ne(start.x, 4, "не на занятой северной/южной стороне")


func test_motorway_without_room_is_refused() -> void:
	var net := _network(["~~~~~~~~", "~......~", "~~~~~~~~"], 30, 1, false)
	net.add_terminal(Vector2i(1, 1))
	for x in range(1, 6):
		assert_eq(net.build(Vector2i(x, 1), Vector2i(x + 1, 1)), OK)
	net.motorways_left = 1
	assert_eq(net.plan_motorway(Vector2i(3, 1), Vector2i(6, 1))["result"], RoadNetwork.Result.NO_ROOM)


func test_moving_attached_end_cleans_old_stub() -> void:
	var net := _road_net()
	assert_eq(net.build_motorway_planned(Vector2i(4, 2), Vector2i(9, 4)), OK)
	var start: Vector2i = Vector2i.ZERO
	for cell: Vector2i in net.links_of(Vector2i(4, 2)):
		if net.motorway_partner(cell) != null:
			start = cell
	var tiles := net.tiles_left
	assert_eq(net.move_motorway_end(Vector2i(9, 4), start, Vector2i(1, 4)), OK)
	assert_false(net.is_road(start), "заглушка старого конца у дороги убрана")
	assert_eq(net.links_of(Vector2i(4, 2)).size(), 2)
	assert_eq(net.tiles_left, tiles, "одна клетка вернулась, одна потрачена")
