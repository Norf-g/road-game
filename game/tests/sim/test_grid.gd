extends GutTest


func test_in_bounds() -> void:
	var grid := Grid.new(Vector2i(4, 3))
	assert_true(grid.in_bounds(Vector2i(0, 0)))
	assert_true(grid.in_bounds(Vector2i(3, 2)))
	assert_false(grid.in_bounds(Vector2i(4, 0)))
	assert_false(grid.in_bounds(Vector2i(0, -1)))


func test_index_of_is_row_major() -> void:
	assert_eq(Grid.new(Vector2i(4, 3)).index_of(Vector2i(1, 2)), 9)


func test_neighbors8_in_middle_has_eight() -> void:
	assert_eq(Grid.new(Vector2i(5, 5)).neighbors8(Vector2i(2, 2)).size(), 8)


func test_line_steps_through_adjacent_cells() -> void:
	var cells := Grid.line(Vector2i(0, 0), Vector2i(3, 1))
	assert_eq(cells.size(), 3)
	assert_eq(cells.back(), Vector2i(3, 1))
	var previous := Vector2i(0, 0)
	for cell in cells:
		assert_eq(maxi(absi(cell.x - previous.x), absi(cell.y - previous.y)), 1)
		previous = cell


func test_neighbors8_in_corner_has_three() -> void:
	var neighbors := Grid.new(Vector2i(5, 5)).neighbors8(Vector2i(0, 0))
	assert_eq(neighbors.size(), 3)
	assert_has(neighbors, Vector2i(1, 1))
