class_name StrokeInput
extends Node
## Ведение одним пальцем: в зависимости от выбранного инструмента строит дорогу или сносит.
## Траектория сглаживается: соседняя клетка принимается, только когда палец дошёл до её середины.
## Поэтому при движении по диагонали через угол клетки дорога идёт по диагонали, без «ступенек».
## На ПК левая кнопка мыши работает как палец (emulate_touch_from_mouse).

enum Tool { ROAD, ERASER }

## Постройка не удалась по причине, которую стоит показать игроку.
signal build_failed(result: RoadNetwork.Result)

const INNER_RADIUS := 0.4
const REPORTED_FAILURES: Array[RoadNetwork.Result] = [
	RoadNetwork.Result.NO_TILES, RoadNetwork.Result.NO_BRIDGES, RoadNetwork.Result.CROSSING,
]

var tool: Tool = Tool.ROAD
var sim: Simulation
var camera: CameraController
## (Vector2) -> bool: точка экрана над кнопками интерфейса.
var is_over_ui: Callable

var _touches := {}
var _active := false
var _last_cell := Vector2i.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
		else:
			_touches.erase(event.index)
		if _touches.size() != 1 or not event.pressed:
			_active = false
		else:
			_begin(event.position)
	elif event is InputEventScreenDrag and _active and _touches.size() == 1:
		_continue(event.position)


func _begin(screen_pos: Vector2) -> void:
	if sim.game_over or is_over_ui.call(screen_pos):
		return
	_active = true
	_last_cell = _cell_at(screen_pos)
	if tool == Tool.ERASER:
		sim.erase_cell(_last_cell)


func _continue(screen_pos: Vector2) -> void:
	var point := camera.ground_point(screen_pos)
	var cell := _cell_at(screen_pos)
	if cell == _last_cell:
		return
	if tool == Tool.ERASER:
		for next in Grid.line(_last_cell, cell):
			sim.erase_cell(next)
		_last_cell = cell
		return
	var adjacent := maxi(absi(cell.x - _last_cell.x), absi(cell.y - _last_cell.y)) == 1
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	if adjacent and Vector2(point.x, point.z).distance_to(center) > INNER_RADIUS:
		return
	for next in Grid.line(_last_cell, cell):
		var result := sim.build_link(_last_cell, next)
		if result in REPORTED_FAILURES:
			build_failed.emit(result)
		_last_cell = next


func _cell_at(screen_pos: Vector2) -> Vector2i:
	var point := camera.ground_point(screen_pos)
	return Vector2i(floori(point.x), floori(point.z))
