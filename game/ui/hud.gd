class_name Hud
extends CanvasLayer
## Интерфейс партии: запасы и очки, инструменты, пауза и скорость, сообщения, экран проигрыша.

signal tool_selected(tool: StrokeInput.Tool)
## 0 — пауза, 1 — обычная скорость, 2 — двойная.
signal speed_selected(speed: int)
signal restart_requested

const FONT_SIZE := 30
const BUTTON_SIZE := Vector2(170, 96)
const TOAST_SECONDS := 1.5

var _tiles := Label.new()
var _bridges := Label.new()
var _score := Label.new()
var _fps := Label.new()
var _toast := Label.new()
var _toast_left := 0.0
var _buttons: Array[Button] = []
var _speed_buttons: Array[Button] = []
var _tool_buttons: Array[Button] = []
var _game_over := CenterContainer.new()
var _game_over_score := Label.new()


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", Palette.TEXT)

	var root := MarginContainer.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 40)
	add_child(root)
	var column := _box(VBoxContainer.new())
	root.add_child(column)

	var top := _box(HBoxContainer.new())
	column.add_child(top)
	var stats := _box(VBoxContainer.new())
	for label in [_tiles, _bridges, _score, _fps]:
		stats.add_child(label)
	top.add_child(stats)
	var spacer := _box(Control.new())
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var speed_group := ButtonGroup.new()
	for speed in 3:
		var button := _button(tr(["SPEED_PAUSE", "SPEED_X1", "SPEED_X2"][speed]), speed_group)
		button.pressed.connect(speed_selected.emit.bind(speed))
		top.add_child(button)
		_speed_buttons.append(button)

	var middle := _box(CenterContainer.new())
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toast.add_theme_font_size_override("font_size", 36)
	_toast.add_theme_color_override("font_color", Palette.OVERFLOW)
	middle.add_child(_toast)
	column.add_child(middle)

	var bottom := HBoxContainer.new()
	_box(bottom)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	var tool_group := ButtonGroup.new()
	for tool: StrokeInput.Tool in [StrokeInput.Tool.ROAD, StrokeInput.Tool.ERASER]:
		var button := _button(tr(["TOOL_ROAD", "TOOL_ERASER"][tool]), tool_group)
		button.pressed.connect(tool_selected.emit.bind(tool))
		bottom.add_child(button)
		_tool_buttons.append(button)
	column.add_child(bottom)

	_build_game_over(theme)
	reset()


## Возвращает интерфейс к началу партии: инструмент «Дорога», скорость ×1, без экрана проигрыша.
func reset() -> void:
	_tool_buttons[0].button_pressed = true
	_speed_buttons[1].button_pressed = true
	_game_over.visible = false
	_toast_left = 0.0
	_toast.text = ""


func update_stats(sim: Simulation) -> void:
	_tiles.text = tr("HUD_TILES") % sim.network.tiles_left
	_bridges.text = tr("HUD_BRIDGES") % (sim.network.bridge_stock - sim.network.bridges_used)
	_score.text = tr("HUD_SCORE") % sim.score
	_fps.text = tr("HUD_FPS") % Engine.get_frames_per_second()


func show_message(key: String) -> void:
	_toast.text = tr(key)
	_toast_left = TOAST_SECONDS


func show_game_over(score: int) -> void:
	_game_over_score.text = tr("GAME_OVER_SCORE") % score
	_game_over.visible = true


func is_point_over_ui(screen_pos: Vector2) -> bool:
	if _game_over.visible:
		return true
	for button in _buttons:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(screen_pos):
			return true
	return false


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)


func _build_game_over(theme: Theme) -> void:
	_game_over.theme = theme
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game_over)
	var panel := PanelContainer.new()
	_game_over.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)
	var title := Label.new()
	title.text = tr("GAME_OVER_TITLE")
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	_game_over_score.add_theme_color_override("font_color", Color.WHITE)
	for label in [title, _game_over_score]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	var restart := _button(tr("GAME_OVER_RESTART"), null)
	restart.pressed.connect(restart_requested.emit)
	box.add_child(restart)


func _box(control: Control) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func _button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	if group != null:
		button.toggle_mode = true
		button.button_group = group
	_buttons.append(button)
	return button
