extends GutTest

const C := Vector2i(1, 1)
const WEST := Vector2i(0, 1)
const EAST := Vector2i(2, 1)
const NORTH := Vector2i(1, 0)
const SOUTH := Vector2i(1, 2)


func test_opposite_straights_do_not_conflict() -> void:
	assert_false(Traffic.movements_conflict(C, [WEST, EAST], [EAST, WEST]))


func test_crossing_straights_conflict() -> void:
	assert_true(Traffic.movements_conflict(C, [WEST, EAST], [NORTH, SOUTH]))


func test_left_turn_conflicts_with_oncoming_straight() -> void:
	# С запада налево — на север; навстречу едут с востока на запад.
	assert_true(Traffic.movements_conflict(C, [WEST, NORTH], [EAST, WEST]))


func test_right_turns_from_opposite_sides_do_not_conflict() -> void:
	# С запада направо — на юг; с востока направо — на север.
	assert_false(Traffic.movements_conflict(C, [WEST, SOUTH], [EAST, NORTH]))


func test_merging_into_same_lane_conflicts() -> void:
	assert_true(Traffic.movements_conflict(C, [WEST, SOUTH], [NORTH, SOUTH]))


func test_same_entry_lane_does_not_conflict() -> void:
	assert_false(Traffic.movements_conflict(C, [WEST, EAST], [WEST, SOUTH]))
