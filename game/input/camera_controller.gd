class_name CameraController
extends Camera3D
## Ортографическая камера: сдвиг и масштаб двумя пальцами, на ПК — правой/средней кнопкой и колесом.
## Касание одним пальцем не обрабатывается: оно отдано инструментам (дорога, ластик).

@export var min_size := 6.0
@export var max_size := 30.0
## Область карты по XZ: центр экрана не уходит за её пределы.
@export var bounds := Rect2(0, 0, 24, 14)

var _touches: Dictionary = {}  # индекс касания -> позиция на экране


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var before := _touches.duplicate()
		_touches[event.index] = event.position
		if _touches.size() == 2:
			_apply_two_finger(before, _touches)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.1)
	elif event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_pan(event.position - event.relative, event.position)


func _apply_two_finger(before: Dictionary, after: Dictionary) -> void:
	var keys := after.keys()
	var a0: Vector2 = before[keys[0]]
	var a1: Vector2 = before[keys[1]]
	var b0: Vector2 = after[keys[0]]
	var b1: Vector2 = after[keys[1]]
	var mid_after := (b0 + b1) / 2
	_pan((a0 + a1) / 2, mid_after)
	var dist_before := a0.distance_to(a1)
	var dist_after := b0.distance_to(b1)
	if dist_before > 1.0 and dist_after > 1.0:
		_zoom_at(mid_after, dist_before / dist_after)


func _pan(from_screen: Vector2, to_screen: Vector2) -> void:
	position += ground_point(from_screen) - ground_point(to_screen)
	_clamp_to_bounds()


## Масштаб вокруг точки экрана: точка земли под ней остаётся на месте.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := ground_point(screen_pos)
	size = clampf(size * factor, min_size, max_size)
	position += anchor - ground_point(screen_pos)
	_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	var center := ground_point(get_viewport().get_visible_rect().size / 2)
	var clamped := Vector3(
		clampf(center.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(center.z, bounds.position.y, bounds.end.y))
	position += clamped - center


## Точка плоскости земли (y = 0) под точкой экрана.
func ground_point(screen_pos: Vector2) -> Vector3:
	var origin := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	return origin + dir * (-origin.y / dir.y)
