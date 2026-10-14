class_name EdgeAlerts
extends Control
## Метки у края экрана: место назначения в тревоге за пределами кадра отмечается мягкой
## пульсирующей красной полосой на той стороне экрана, где оно находится. Полоса уходит
## в прозрачность к центру экрана и исчезает, как только здание попадает в кадр.

const BAND_DEPTH := 80.0
const BAND_LENGTH := 460.0
const SEGMENTS := 10
const MAX_ALPHA := 0.6
const PULSE_HZ := 0.8
## Здание считается в кадре, если его центр не ближе этого расстояния к краю экрана.
const VISIBLE_MARGIN := 24.0

var sim: Simulation
var camera: Camera3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or camera == null:
		return
	var rect := get_viewport_rect()
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU * PULSE_HZ)
	for dest in sim.destinations:
		if not sim.is_destination_warning(dest):
			continue
		var world := Vector3(dest.rect.get_center().x, 0.3, dest.rect.get_center().y)
		var point := camera.unproject_position(world)
		if rect.grow(-VISIBLE_MARGIN).has_point(point):
			continue
		_draw_band(rect, point, pulse)


## Полоса вдоль той стороны экрана, через которую проходит направление от центра экрана к зданию.
func _draw_band(rect: Rect2, point: Vector2, pulse: float) -> void:
	var center := rect.get_center()
	var dir := point - center
	var outward := Vector2(signf(dir.x), 0.0) if absf(dir.x) / rect.size.x > absf(dir.y) / rect.size.y \
		else Vector2(0.0, signf(dir.y))
	# Точка края, через которую проходит направление; полоса не вылезает за углы.
	var to_edge := INF
	if dir.x != 0.0:
		to_edge = minf(to_edge, rect.size.x / 2 / absf(dir.x))
	if dir.y != 0.0:
		to_edge = minf(to_edge, rect.size.y / 2 / absf(dir.y))
	var edge := center + dir * to_edge
	var half := BAND_LENGTH / 2
	if outward.x != 0.0:
		edge = Vector2(rect.position.x if outward.x < 0.0 else rect.end.x,
			clampf(edge.y, rect.position.y + half, rect.end.y - half))
	else:
		edge = Vector2(clampf(edge.x, rect.position.x + half, rect.end.x - half),
			rect.position.y if outward.y < 0.0 else rect.end.y)
	var along := Vector2(-outward.y, outward.x)
	var inward := -outward * BAND_DEPTH
	var clear := Color(Palette.OVERFLOW, 0.0)
	for i in SEGMENTS:
		var u0 := float(i) / SEGMENTS
		var u1 := float(i + 1) / SEGMENTS
		var p0 := edge + along * lerpf(-half, half, u0)
		var p1 := edge + along * lerpf(-half, half, u1)
		# Яркость вдоль полосы — плавный горб: к концам полоса тоже растворяется.
		var c0 := Color(Palette.OVERFLOW, MAX_ALPHA * pulse * sin(PI * u0))
		var c1 := Color(Palette.OVERFLOW, MAX_ALPHA * pulse * sin(PI * u1))
		draw_polygon(PackedVector2Array([p0, p1, p1 + inward, p0 + inward]), PackedColorArray([c0, c1, clear, clear]))
