class_name TechButton
extends Button
## Кнопка нижней панели инструментов в стиле «технического HUD»: тёмная плитка со срезанным верхним
## левым углом и тонкой светлой рамкой. У выбранной — оранжевая рамка, оранжевая планка вдоль среза
## и оранжевый треугольник в нижнем правом углу. Иконка и запас — в одну строку по центру плитки.
## Рисуется целиком в _draw(); стандартные стили кнопки отключены.

const SIZE := Vector2(150, 84)
const CHAMFER := 20.0
const LINE_WIDTH := 2.0
## Обводка выбранной кнопки толще обычной.
const ACTIVE_LINE_WIDTH := 3.0
const ICON_SIZE := 48.0
const COUNT_FONT_SIZE := 30
## Расстояние между иконкой и числом.
const GAP := 10.0
const CAPTION_FONT_SIZE := 20
const CORNER := 22.0
const LINE := Color("c9ced6")
const LINE_HOVER := Color("eef1f5")
const BACKGROUND := Color("1e2328", 0.9)

## Иконка; если её нет — по центру пишется caption.
var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
var caption := "":
	set(value):
		caption = value
		queue_redraw()
## Запас рядом с иконкой; -1 — счётчика нет.
var count := -1:
	set(value):
		if value != count:
			count = value
			queue_redraw()


func _init() -> void:
	custom_minimum_size = SIZE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _draw() -> void:
	var w := size.x
	var h := size.y
	var mode := get_draw_mode()
	var active := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	var accent := Palette.ACCENT
	var line := accent if active else (LINE_HOVER if mode == DRAW_HOVER else LINE)
	var fade := 0.35 if disabled else 1.0

	var outline := PackedVector2Array([
		Vector2(CHAMFER, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h), Vector2(0.0, CHAMFER),
	])
	draw_colored_polygon(outline, Color(BACKGROUND, BACKGROUND.a * (0.6 if disabled else 1.0)))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(line, fade), ACTIVE_LINE_WIDTH if active else LINE_WIDTH, true)
	if active:
		# Планка вдоль среза и треугольник в противоположном углу.
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, CHAMFER), Vector2(CHAMFER, 0.0), Vector2(CHAMFER + 9.0, 0.0), Vector2(0.0, CHAMFER + 9.0),
		]), accent)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w, h), Vector2(w - CORNER, h), Vector2(w, h - CORNER),
		]), accent)

	var font := UiTheme.font()
	if font == null:
		return
	# У выбранной кнопки иконка и подпись — основным жёлтым, как рамка.
	var tint := Color(accent, fade) if active else Color(1.0, 1.0, 1.0, fade)
	var label := str(count) if count >= 0 else ""
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE).x if label != "" else 0.0
	var gap := GAP if label != "" else 0.0
	if texture == null:
		# Без иконки: подпись и число одной строкой.
		var text := caption if label == "" else "%s %s" % [caption, label]
		draw_string(font, Vector2(0.0, h / 2 + CAPTION_FONT_SIZE / 3.0), text, HORIZONTAL_ALIGNMENT_CENTER, w,
			CAPTION_FONT_SIZE, tint)
		return
	# Иконка и число одной строкой, вместе по центру плитки.
	var left := (w - (ICON_SIZE + gap + label_width)) / 2
	draw_texture_rect(texture, Rect2(Vector2(left, (h - ICON_SIZE) / 2), Vector2.ONE * ICON_SIZE), false, tint)
	if label != "":
		var baseline := h / 2 + font.get_ascent(COUNT_FONT_SIZE) / 2 - font.get_descent(COUNT_FONT_SIZE) / 4
		draw_string(font, Vector2(left + ICON_SIZE + gap, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			COUNT_FONT_SIZE, Color(Palette.ACCENT, fade))
