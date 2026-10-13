class_name Grid
extends RefCounted
## Квадратная сетка карты. Чистая логика без нод: её используют симуляция и генерация.

const DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

var size: Vector2i


func _init(grid_size: Vector2i) -> void:
	assert(grid_size.x > 0 and grid_size.y > 0, "Grid size must be positive")
	size = grid_size


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func index_of(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


## Клетки отрезка from -> to без начальной, каждая соседняя с предыдущей (по 8 направлениям).
static func line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		cells.append(Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t))))
	return cells


func neighbors8(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in DIRS_8:
		var neighbor := cell + dir
		if in_bounds(neighbor):
			result.append(neighbor)
	return result
