extends GutTest

const OK := RoadNetwork.Result.OK


func _network(rows: Array, tiles := 10, bridges := 1) -> RoadNetwork:
	var map := MapData.from_dict({"rows": rows})
	return RoadNetwork.new(Grid.new(map.size), map.water, tiles, bridges)


func test_build_spends_tiles_and_erase_returns_them() -> void:
	var net := _network(["....."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.tiles_left, 7)
	assert_true(net.erase(Vector2i(1, 0)))
	assert_eq(net.tiles_left, 8)
	assert_false(net.are_linked(Vector2i(0, 0), Vector2i(1, 0)))
	assert_false(net.are_linked(Vector2i(1, 0), Vector2i(2, 0)))


func test_build_fails_without_tiles() -> void:
	var net := _network(["....."], 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), RoadNetwork.Result.NO_TILES)
	assert_eq(net.tiles_left, 1)


func test_build_rejects_far_cells_and_repeats() -> void:
	var net := _network(["....."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(2, 0)), RoadNetwork.Result.NOT_ADJACENT)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(0, 0)), RoadNetwork.Result.ALREADY_LINKED)


func test_diagonals_cannot_cross() -> void:
	var net := _network(["...", "..."])
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 1)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(0, 1)), RoadNetwork.Result.CROSSING)


func test_bridge_span_uses_one_bridge_and_no_tiles() -> void:
	var net := _network([".~~."], 10, 1)
	assert_eq(net.build(Vector2i(0, 0), Vector2i(1, 0)), OK)
	assert_eq(net.build(Vector2i(1, 0), Vector2i(2, 0)), OK)
	assert_eq(net.build(Vector2i(2, 0), Vector2i(3, 0)), OK)
	assert_eq(net.bridges_used, 1)
	assert_eq(net.tiles_left, 8)


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
