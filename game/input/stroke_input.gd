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
## Правка шоссе (инструменты «Дорога» и «Шоссе»): короткое касание конца шоссе выбирает его; затем
## ведение пальцем от выбранного конца переносит его, когда палец отпущен. Касание в другом месте
## только снимает выбор.
## На ПК левая кнопка мыши работает как палец (emulate_touch_from_mouse).

enum Tool { ROAD, ERASER, MOTORWAY, LIGHT, ROUNDABOUT }

## Действие не удалось по причине, которую стоит показать игроку.
signal action_failed(result: RoadNetwork.Result)
## Действие удалось: «build» — построено, «erase» — снесено. Для звука.
signal action_succeeded(event: String)
## Предпросмотр шоссе: valid — получится ли его построить.
signal motorway_preview_changed(from: Vector2i, to: Vector2i, valid: bool)
signal motorway_preview_hidden
## Выбран конец шоссе для правки (Vector2i) или выбор снят (null).
signal motorway_end_selected(cell: Variant)

const INNER_RADIUS := 0.4
## При ведении дороги игроку важны только эти причины отказа, остальные (здание на пути,
## дорога уже есть) — обычное дело при рисовании.
const ROAD_FAILURES: Array[RoadNetwork.Result] = [
	RoadNetwork.Result.NO_TILES, RoadNetwork.Result.NO_BRIDGES, RoadNetwork.Result.CROSSING,
	RoadNetwork.Result.BRIDGE_SHAPE, RoadNetwork.Result.BRIDGE_TOO_LONG,
]
## Попытка провести дорогу через подключённый дом молча ничего не делает — это не ошибка игрока.
const SILENT_RESULTS: Array[RoadNetwork.Result] = [RoadNetwork.Result.ALREADY_LINKED, RoadNetwork.Result.TERMINAL_FULL]
## Инструменты, в которых касание конца шоссе выбирает его для правки.
const EDIT_TOOLS: Array[Tool] = [Tool.ROAD, Tool.MOTORWAY]

## Смена инструмента снимает выбор конца шоссе.
var tool: Tool = Tool.ROAD:
	set(value):
		tool = value
		_select_end(null)
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
## Клетка, где палец коснулся экрана, и уходил ли он с неё — чтобы отличить касание от ведения.
var _press_cell := Vector2i.ZERO
var _moved := false
## Выбранный для правки конец шоссе (Vector2i) или null.
var _selected_end: Variant = null
## Палец ведёт выбранный конец шоссе на новое место.
var _editing := false


## Начало новой партии: никаких незавершённых действий и выбора.
func reset() -> void:
	_cancel()
	_select_end(null)


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
	if sim == null or is_over_ui.call(screen_pos) or sim.game_over:
		return
	var cell := _cell_at(screen_pos)
	if _selected_end != null:
		# Шоссе могли снести, пока его конец был выбран.
		var partner: Variant = sim.network.motorway_partner(_selected_end)
		if cell == _selected_end and tool in EDIT_TOOLS and partner != null:
			_editing = true
			_active = true
			_last_cell = cell
			motorway_preview_changed.emit(partner, cell, false)
		else:
			_select_end(null)  # касание в другом месте только снимает выбор
		return
	_press_cell = cell
	_moved = false
	match tool:
		Tool.LIGHT, Tool.ROUNDABOUT:
			var junction := RoadNetwork.Junction.LIGHT if tool == Tool.LIGHT else RoadNetwork.Junction.ROUNDABOUT
			_report(sim.place_control(cell, junction))
			return
		Tool.ERASER:
			_erase(cell)
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
	_moved = true
	if _editing:
		_last_cell = cell
		var fixed: Variant = sim.network.motorway_partner(_selected_end)
		if fixed == null:
			_cancel()
			_select_end(null)
			return
		var move := sim.network.plan_motorway_move(fixed, _selected_end, cell)
		motorway_preview_changed.emit(fixed, move.get("end", cell), move["result"] == RoadNetwork.Result.OK)
		return
	match tool:
		Tool.ERASER:
			for next in Grid.line(_last_cell, cell):
				_erase(next)
			_last_cell = cell
		Tool.MOTORWAY:
			_last_cell = cell
			# Предпросмотр там, где концы встанут на самом деле (на дороге — сбоку от неё).
			var plan := sim.network.plan_motorway(_motorway_start, cell)
			var ends: Array = plan.get("ends", [_motorway_start, cell])
			motorway_preview_changed.emit(ends[0], ends[1], plan["result"] == RoadNetwork.Result.OK)
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
		if result == RoadNetwork.Result.OK:
			action_succeeded.emit("build")
		elif result in ROAD_FAILURES:
			action_failed.emit(result)
		_last_cell = next


func _finish(screen_pos: Vector2) -> void:
	var end := _cell_at(screen_pos)
	if _editing:
		if end != _selected_end:
			_report(sim.move_motorway_end(_selected_end, end))
		_cancel()
		_select_end(null)
		return
	# Короткое касание конца шоссе выбирает его для правки.
	if not _moved and tool in EDIT_TOOLS and sim.network.motorway_partner(_press_cell) != null:
		_cancel()
		_select_end(_press_cell)
		return
	if tool == Tool.ROAD and not _anchored:
		action_failed.emit(RoadNetwork.Result.NOT_CONNECTED)
	if tool == Tool.MOTORWAY and end != _motorway_start:
		_report(sim.build_motorway(_motorway_start, end))
	_cancel()


func _cancel() -> void:
	if _active and (tool == Tool.MOTORWAY or _editing):
		motorway_preview_hidden.emit()
	_active = false
	_editing = false


func _select_end(cell: Variant) -> void:
	if typeof(cell) == typeof(_selected_end) and cell == _selected_end:
		return
	_selected_end = cell
	motorway_end_selected.emit(cell)


## Привязывает начало дороги: к дороге, дому или въезду здания (с любой его клетки).
func _try_anchor(cell: Vector2i) -> void:
	var dest := sim.destination_at(cell)
	if dest != null:
		_last_cell = dest.entrance
		_anchored = true
	elif sim.network.is_road(cell) or sim.network.is_terminal(cell):
		_anchored = true
		_relink_house = sim.network.is_single_exit(cell) and not sim.network.links_of(cell).is_empty()


func _erase(cell: Vector2i) -> void:
	if sim.erase_cell(cell):
		action_succeeded.emit("erase")


func _report(result: RoadNetwork.Result) -> void:
	if result == RoadNetwork.Result.OK:
		action_succeeded.emit("build")
	elif result not in SILENT_RESULTS:
		action_failed.emit(result)


func _cell_at(screen_pos: Vector2) -> Vector2i:
	var point := camera.ground_point(screen_pos)
	return Vector2i(floori(point.x), floori(point.z))
