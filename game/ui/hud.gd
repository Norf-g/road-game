class_name Hud
extends CanvasLayer
## Интерфейс партии: запасы и очки, неделя, инструменты, пауза и скорость, сообщения,
## выбор улучшения в конце недели и экран проигрыша.

signal tool_selected(tool: StrokeInput.Tool)
## 0 — пауза, 1 — обычная скорость, 2 — двойная.
signal speed_selected(speed: int)
signal upgrade_chosen(index: int)
signal restart_requested

const FONT_SIZE := 30
const BUTTON_SIZE := Vector2(170, 96)
const TOAST_SECONDS := 1.5
const TOOL_KEYS := {
	StrokeInput.Tool.ROAD: "TOOL_ROAD",
	StrokeInput.Tool.ERASER: "TOOL_ERASER",
	StrokeInput.Tool.MOTORWAY: "TOOL_MOTORWAY",
	StrokeInput.Tool.LIGHT: "TOOL_LIGHT",
	StrokeInput.Tool.ROUNDABOUT: "TOOL_ROUNDABOUT",
}
const UPGRADE_KEYS := {
	Director.Upgrade.TILES: "UPGRADE_TILES",
	Director.Upgrade.BRIDGES: "UPGRADE_BRIDGES",
	Director.Upgrade.LIGHT: "UPGRADE_LIGHT",
	Director.Upgrade.ROUNDABOUT: "UPGRADE_ROUNDABOUT",
	Director.Upgrade.MOTORWAY: "UPGRADE_MOTORWAY",
}

var _theme := Theme.new()
var _tiles := Label.new()
var _bridges := Label.new()
var _score := Label.new()
var _week := Label.new()
var _week_progress := ProgressBar.new()
var _fps := Label.new()
var _toast := Label.new()
var _toast_left := 0.0
var _buttons: Array[Button] = []
var _speed_buttons: Array[Button] = []
var _tool_buttons := {}  # StrokeInput.Tool -> Button
var _offer := CenterContainer.new()
var _offer_title := Label.new()
var _offer_buttons: Array[Button] = []
var _game_over := CenterContainer.new()
var _game_over_score := Label.new()
var _game_over_record := Label.new()


func _ready() -> void:
	_theme.default_font_size = FONT_SIZE
	_theme.set_color("font_color", "Label", Palette.TEXT)

	var root := MarginContainer.new()
	root.theme = _theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 40)
	add_child(root)
	var column := _ignore(VBoxContainer.new())
	root.add_child(column)

	var top := _ignore(HBoxContainer.new())
	column.add_child(top)
	var stats := _ignore(VBoxContainer.new())
	_week_progress.custom_minimum_size = Vector2(220, 12)
	_week_progress.show_percentage = false
	_week_progress.max_value = 1.0
	_week_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in [_week, _week_progress, _tiles, _bridges, _score, _fps]:
		stats.add_child(control)
	top.add_child(stats)
	var spacer := _ignore(Control.new())
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var speed_group := ButtonGroup.new()
	for speed in 3:
		var button := _button(tr(["SPEED_PAUSE", "SPEED_X1", "SPEED_X2"][speed]), speed_group)
		button.pressed.connect(speed_selected.emit.bind(speed))
		top.add_child(button)
		_speed_buttons.append(button)

	var middle := _ignore(CenterContainer.new())
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toast.add_theme_font_size_override("font_size", 36)
	_toast.add_theme_color_override("font_color", Palette.OVERFLOW)
	middle.add_child(_toast)
	column.add_child(middle)

	var bottom := HBoxContainer.new()
	_ignore(bottom)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	var tool_group := ButtonGroup.new()
	for tool: StrokeInput.Tool in TOOL_KEYS:
		var button := _button(tr(TOOL_KEYS[tool]), tool_group)
		button.pressed.connect(tool_selected.emit.bind(tool))
		bottom.add_child(button)
		_tool_buttons[tool] = button
	column.add_child(bottom)

	_build_offer()
	_build_game_over()
	reset()


## Возвращает интерфейс к началу партии: инструмент «Дорога», скорость ×1, без окон.
func reset() -> void:
	select_tool(StrokeInput.Tool.ROAD)
	_speed_buttons[1].button_pressed = true
	_offer.visible = false
	_game_over.visible = false
	_toast_left = 0.0
	_toast.text = ""


func select_tool(tool: StrokeInput.Tool) -> void:
	(_tool_buttons[tool] as Button).button_pressed = true


func update_stats(sim: Simulation, director: Director) -> void:
	var network := sim.network
	_week.text = tr("HUD_WEEK") % (director.week + 1)
	_week_progress.value = director.week_progress()
	_tiles.text = tr("HUD_TILES") % network.tiles_left
	_bridges.text = tr("HUD_BRIDGES") % (network.bridge_stock - network.bridges_used)
	_score.text = tr("HUD_SCORE") % sim.score
	_fps.text = tr("HUD_FPS") % Engine.get_frames_per_second()
	var stocks := {
		StrokeInput.Tool.MOTORWAY: network.motorways_left,
		StrokeInput.Tool.LIGHT: network.lights_left,
		StrokeInput.Tool.ROUNDABOUT: network.roundabouts_left,
	}
	for tool: StrokeInput.Tool in stocks:
		var button: Button = _tool_buttons[tool]
		button.text = "%s · %d" % [tr(TOOL_KEYS[tool]), stocks[tool]]
		button.disabled = stocks[tool] == 0


func show_message(key: String) -> void:
	_toast.text = tr(key)
	_toast_left = TOAST_SECONDS


func show_offer(week: int, offer: Array[Director.Upgrade], balance: Balance) -> void:
	_offer_title.text = tr("OFFER_TITLE") % [week, balance.week_tiles]
	for i in offer.size():
		var amount := 1
		match offer[i]:
			Director.Upgrade.TILES:
				amount = balance.upgrade_tiles
			Director.Upgrade.BRIDGES:
				amount = balance.upgrade_bridges
		_offer_buttons[i].text = tr(UPGRADE_KEYS[offer[i]]) % amount
	_offer.visible = true


func show_game_over(score: int, record: int, is_new_record: bool) -> void:
	_game_over_score.text = tr("GAME_OVER_SCORE") % score
	_game_over_record.text = tr("GAME_OVER_NEW_RECORD") if is_new_record else tr("GAME_OVER_RECORD") % record
	_game_over.visible = true


func is_point_over_ui(screen_pos: Vector2) -> bool:
	if _game_over.visible or _offer.visible:
		return true
	for button in _buttons:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(screen_pos):
			return true
	return false


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)


func _build_offer() -> void:
	var box := _modal(_offer)
	_offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offer_title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_offer_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	for i in 2:
		var button := _button("", null)
		button.custom_minimum_size = Vector2(320, 140)
		button.pressed.connect(func() -> void:
			_offer.visible = false
			upgrade_chosen.emit(i))
		row.add_child(button)
		_offer_buttons.append(button)


func _build_game_over() -> void:
	var box := _modal(_game_over)
	var title := Label.new()
	title.text = tr("GAME_OVER_TITLE")
	title.add_theme_font_size_override("font_size", 48)
	for label: Label in [title, _game_over_score, _game_over_record]:
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	var restart := _button(tr("GAME_OVER_RESTART"), null)
	restart.pressed.connect(restart_requested.emit)
	box.add_child(restart)


## Окно по центру экрана; возвращает контейнер для его содержимого.
func _modal(holder: CenterContainer) -> VBoxContainer:
	holder.theme = _theme
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	add_child(holder)
	var panel := PanelContainer.new()
	holder.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	return box


func _ignore(control: Control) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func _button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	if group != null:
		button.toggle_mode = true
		button.button_group = group
	_buttons.append(button)
	return button
