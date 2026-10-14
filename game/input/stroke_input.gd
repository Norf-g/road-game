class_name StrokeInput
extends Node
## Касание одним пальцем. Что оно делает, зависит от выбранного инструмента:
## - Дорога: ведение пальцем строит дорогу от дома, здания или уже построенной дороги. Если палец
##   начал на пустом месте, стройка начнётся, когда он дойдёт до дома или дороги. С любой клетки
##   здания дорога начинается от его въезда. Если начать с уже подключённого дома, его единственный
##   выезд переносится на новую дорогу. Траектория сглаживается: соседняя клетка принимается,
##   только когда палец дошёл до её середины, поэтому по диагонали дорога идёт без «ступенек».
## - Ластик: ведение пальцем сносит всё на пути.
## - Шоссе: ведём от начала до конца, шоссе строится, когда палец отпущен.
## - Светофор, развязка: касание по перекрёстку.
## На ПК левая кнопка мыши работает как палец (emulate_touch_from_mouse).

enum Tool { ROAD, ERASER, MOTORWAY, LIGHT, ROUNDABOUT }

## Действие не удалось по причине, которую стоит показать игроку.
signal action_failed(result: RoadNetwork.Result)
## Предпросмотр шоссе: valid — получится ли его построить.
signal motorway_preview_changed(from: Vector2i, to: Vector2i, valid: bool)
signal motorway_preview_hidden

const INNER_RADIUS := 0.4
## При ведении дороги игроку важны только эти причины отказа, остальные (здание на пути,
## дорога уже есть) — обычное дело при рисовании.
const ROAD_FAILURES: Array[RoadNetwork.Result] = [
	RoadNetwork.Result.NO_TILES, RoadNetwork.Result.NO_BRIDGES, RoadNetwork.Result.CROSSING,
	RoadNetwork.Result.BRIDGE_SHAPE, RoadNetwork.Result.BRIDGE_TOO_LONG, RoadNetwork.Result.TERMINAL_FULL,
]

var tool: Tool = Tool.ROAD
var sim: Simulation
var camera: CameraController
## (Vector2) -> bool: точка экрана над кнопками интерфейса.
var is_over_ui: Callable

var _touches := {}
var _active := false
var _last_cell := Vector2i.ZERO
## Дорога уже привязана к сети: найдена клетка, от которой можно строить.
var _anchored := false
## Дорога начата с подключённого дома: первая связь переносит его выезд.
var _relink_house := false
var _motorway_start := Vector2i.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
		else:
			_touches.erase(event.index)
		if event.pressed and _touches.size() == 1:
			_begin(event.position)
		elif not event.pressed and _touches.is_empty() and _active:
			_finish(event.position)
		else:
			_cancel()
	elif event is InputEventScreenDrag and _active and _touches.size() == 1:
		_continue(event.position)


func _begin(screen_pos: Vector2) -> void:
	if sim.game_over or is_over_ui.call(screen_pos):
		return
	var cell := _cell_at(screen_pos)
	match tool:
		Tool.LIGHT, Tool.ROUNDABOUT:
			var junction := RoadNetwork.Junction.LIGHT if tool == Tool.LIGHT else RoadNetwork.Junction.ROUNDABOUT
			_report(sim.place_control(cell, junction))
			return
		Tool.ERASER:
			sim.erase_cell(cell)
		Tool.MOTORWAY:
			_motorway_start = cell
			motorway_preview_changed.emit(cell, cell, false)
	_active = true
	_last_cell = cell
	_anchored = false
	_relink_house = false
	if tool == Tool.ROAD:
		_try_anchor(cell)


func _continue(screen_pos: Vector2) -> void:
	var cell := _cell_at(screen_pos)
	if cell == _last_cell:
		return
	match tool:
		Tool.ERASER:
			for next in Grid.line(_last_cell, cell):
				sim.erase_cell(next)
			_last_cell = cell
		Tool.MOTORWAY:
			_last_cell = cell
			var valid := sim.network.can_build_motorway(_motorway_start, cell) == RoadNetwork.Result.OK
			motorway_preview_changed.emit(_motorway_start, cell, valid)
		Tool.ROAD:
			_continue_road(screen_pos, cell)


func _continue_road(screen_pos: Vector2, cell: Vector2i) -> void:
	if not _anchored:
		_last_cell = cell
		_try_anchor(cell)
		return
	var point := camera.ground_point(screen_pos)
	var adjacent := maxi(absi(cell.x - _last_cell.x), absi(cell.y - _last_cell.y)) == 1
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	if adjacent and Vector2(point.x, point.z).distance_to(center) > INNER_RADIUS:
		return
	for next in Grid.line(_last_cell, cell):
		# Клетки здания (кроме въезда) палец проходит насквозь: дорога идёт от въезда.
		if sim.network.is_building(next) and not sim.network.is_terminal(next):
			continue
		var result: RoadNetwork.Result
		if _relink_house:
			_relink_house = false
			result = sim.relink_house(_last_cell, next)
		else:
			result = sim.build_link(_last_cell, next)
		if result in ROAD_FAILURES:
			action_failed.emit(result)
		_last_cell = next


func _finish(screen_pos: Vector2) -> void:
	if tool == Tool.ROAD and not _anchored:
		action_failed.emit(RoadNetwork.Result.NOT_CONNECTED)
	if tool == Tool.MOTORWAY:
		var end := _cell_at(screen_pos)
		if end != _motorway_start:
			_report(sim.build_motorway(_motorway_start, end))
	_cancel()


func _cancel() -> void:
	if _active and tool == Tool.MOTORWAY:
		motorway_preview_hidden.emit()
	_active = false


## Привязывает начало дороги: к дороге, дому или въезду здания (с любой его клетки).
func _try_anchor(cell: Vector2i) -> void:
	var dest := sim.destination_at(cell)
	if dest != null:
		_last_cell = dest.entrance
		_anchored = true
	elif sim.network.is_road(cell) or sim.network.is_terminal(cell):
		_anchored = true
		_relink_house = sim.network.is_single_exit(cell) and not sim.network.links_of(cell).is_empty()


func _report(result: RoadNetwork.Result) -> void:
	if result != RoadNetwork.Result.OK and result != RoadNetwork.Result.ALREADY_LINKED:
		action_failed.emit(result)


func _cell_at(screen_pos: Vector2) -> Vector2i:
	var point := camera.ground_point(screen_pos)
	return Vector2i(floori(point.x), floori(point.z))
