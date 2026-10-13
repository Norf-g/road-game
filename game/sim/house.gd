class_name House
extends RefCounted
## Дом на одну клетку. Его машины возят жителей к местам назначения того же цвета.

var id: int
var cell: Vector2i
var color: int


func _init(house_id: int, house_cell: Vector2i, house_color: int) -> void:
	id = house_id
	cell = house_cell
	color = house_color
