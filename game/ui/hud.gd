class_name Hud
extends CanvasLayer
## Интерфейс партии: неделя, запасы и очки, инструменты, звук, пауза и скорость, сообщения,
## выбор улучшения в конце недели и экран проигрыша.
## Иконки берутся из game/assets/ui (их делает конвейер art/): если картинки ещё нет, вместо неё
## показывается текст, поэтому интерфейс работает и без графики.

signal tool_selected(tool: StrokeInput.Tool)
## 0 — пауза, 1 — обычная скорость, 2 — двойная.
signal speed_selected(speed: int)
signal sound_toggled(muted: bool)
signal upgrade_chosen(index: int)
signal restart_requested
## Открыть главное меню (кнопка «Меню» в игре или «В меню» после проигрыша).
signal menu_requested
## Нажата любая кнопка — для звука щелчка.
signal button_clicked

const BUTTON_SIZE := Vector2(150, 96)
const STAT_ICON_SIZE := 40
const UPGRADE_ICON_SIZE := 120
const TOAST_SECONDS := 1.5
const TOAST_FADE := 0.4
## Откуда выезжает всплывающее сообщение и где останавливается (отступ сверху).
const TOAST_FROM := -100.0
const TOAST_TOP := 36.0
## Порядок кнопок на панели инструментов — порядок ключей: ластик крайний справа.
const TOOL_KEYS := {
	StrokeInput.Tool.ROAD: "TOOL_ROAD",
	StrokeInput.Tool.MOTORWAY: "TOOL_MOTORWAY",
	StrokeInput.Tool.LIGHT: "TOOL_LIGHT",
	StrokeInput.Tool.ROUNDABOUT: "TOOL_ROUNDABOUT",
	StrokeInput.Tool.ERASER: "TOOL_ERASER",
}
const TOOL_ICONS := {
	StrokeInput.Tool.ROAD: "tool_road",
	StrokeInput.Tool.ERASER: "tool_eraser",
	StrokeInput.Tool.MOTORWAY: "tool_motorway",
	StrokeInput.Tool.LIGHT: "tool_light",
	StrokeInput.Tool.ROUNDABOUT: "tool_roundabout",
}
const SPEED_KEYS: Array[String] = ["SPEED_PAUSE", "SPEED_X1", "SPEED_X2"]
const SPEED_ICONS: Array[String] = ["speed_pause", "speed_x1", "speed_x2"]
const UPGRADE_KEYS := {
	Director.Upgrade.TILES: "UPGRADE_TILES",
	Director.Upgrade.BRIDGES: "UPGRADE_BRIDGES",
	Director.Upgrade.LIGHT: "UPGRADE_LIGHT",
	Director.Upgrade.ROUNDABOUT: "UPGRADE_ROUNDABOUT",
	Director.Upgrade.MOTORWAY: "UPGRADE_MOTORWAY",
}
const UPGRADE_ICONS := {
	Director.Upgrade.TILES: "upgrade_tiles",
	Director.Upgrade.BRIDGES: "upgrade_bridges",
	Director.Upgrade.LIGHT: "upgrade_light",
	Director.Upgrade.ROUNDABOUT: "upgrade_roundabout",
	Director.Upgrade.MOTORWAY: "upgrade_motorway",
}

var _theme := UiTheme.get_theme()
var _week := Label.new()
var _week_progress := ProgressBar.new()
var _tiles := Label.new()
var _bridges := Label.new()
var _score := Label.new()
var _fps := Label.new()
## Подпись -> ключ перевода, если у строки нет иконки и число нужно подписать словами.
var _stat_keys := {}
var _toast_area := CenterContainer.new()
var _toast := Label.new()
var _toast_left := 0.0
var _toast_tween: Tween
var _buttons: Array[Button] = []
var _speed_buttons: Array[Button] = []
var _tool_buttons := {}  # StrokeInput.Tool -> Button
var _sound_button: Button
var _muted := false
var _offer := CenterContainer.new()
var _offer_title := Label.new()
var _offer_buttons: Array[Button] = []
var _game_over := CenterContainer.new()
var _game_over_score := Label.new()
var _game_over_record := Label.new()


static func icon(id: String) -> Texture2D:
	for folder in ["icons", "upgrades"]:
		var path := "res://assets/ui/%s/%s.png" % [folder, id]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _ready() -> void:
	var root := MarginContainer.new()
	root.theme = _theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 36)
	add_child(root)
	var column := _ignore(VBoxContainer.new())
	root.add_child(column)

	var top := _ignore(HBoxContainer.new())
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var stats := _ignore(VBoxContainer.new())
	_week_progress.custom_minimum_size = Vector2(220, 10)
	_week_progress.show_percentage = false
	_week_progress.max_value = 1.0
	_week_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_stat_row("stat_week", _week, "HUD_WEEK"))
	stats.add_child(_week_progress)
	stats.add_child(_stat_row("stat_tiles", _tiles, "HUD_TILES"))
	stats.add_child(_stat_row("stat_bridges", _bridges, "HUD_BRIDGES"))
	stats.add_child(_stat_row("stat_trips", _score, "HUD_SCORE"))
	stats.add_child(_fps)
	top.add_child(stats)
	var spacer := _ignore(Control.new())
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var menu := _button(tr("MENU_BUTTON"), null)
	menu.pressed.connect(menu_requested.emit)
	top.add_child(menu)
	_sound_button = _button("", null)
	_sound_button.pressed.connect(func() -> void:
		set_muted(not _muted)
		sound_toggled.emit(_muted))
	top.add_child(_sound_button)
	var speed_group := ButtonGroup.new()
	for speed in 3:
		var button := _icon_button(SPEED_ICONS[speed], tr(SPEED_KEYS[speed]), speed_group)
		button.pressed.connect(speed_selected.emit.bind(speed))
		top.add_child(button)
		_speed_buttons.append(button)

	var middle := _ignore(CenterContainer.new())
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)

	var bottom := HBoxContainer.new()
	_ignore(bottom)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	var tool_group := ButtonGroup.new()
	for tool: StrokeInput.Tool in TOOL_KEYS:
		var button := _icon_button(TOOL_ICONS[tool], tr(TOOL_KEYS[tool]), tool_group)
		button.pressed.connect(tool_selected.emit.bind(tool))
		bottom.add_child(button)
		_tool_buttons[tool] = button
	column.add_child(bottom)

	_build_toast()
	_build_offer()
	_build_game_over()
	set_muted(false)
	reset()


## Возвращает интерфейс к началу партии: инструмент «Дорога», скорость ×1, без окон.
func reset() -> void:
	select_tool(StrokeInput.Tool.ROAD)
	_speed_buttons[1].button_pressed = true
	_offer.visible = false
	_game_over.visible = false
	_toast_left = 0.0
	_toast_area.visible = false


func select_tool(tool: StrokeInput.Tool) -> void:
	(_tool_buttons[tool] as Button).button_pressed = true


## Показывает состояние звука на кнопке (не меняет сам звук).
func set_muted(muted: bool) -> void:
	_muted = muted
	var texture := icon("sound_off" if muted else "sound_on")
	_sound_button.icon = texture
	_sound_button.text = "" if texture != null else tr("SOUND_OFF" if muted else "SOUND_ON")


func update_stats(sim: Simulation, director: Director) -> void:
	var network := sim.network
	_set_stat(_week, director.week + 1)
	_week_progress.value = director.week_progress()
	_set_stat(_tiles, network.tiles_left)
	_set_stat(_bridges, network.bridge_stock - network.bridges_used)
	_set_stat(_score, sim.score)
	_fps.text = tr("HUD_FPS") % Engine.get_frames_per_second()
	var stocks := {
		StrokeInput.Tool.ROAD: network.tiles_left,
		StrokeInput.Tool.MOTORWAY: network.motorways_left,
		StrokeInput.Tool.LIGHT: network.lights_left,
		StrokeInput.Tool.ROUNDABOUT: network.roundabouts_left,
	}
	for tool: StrokeInput.Tool in stocks:
		var button: Button = _tool_buttons[tool]
		var count := str(stocks[tool])
		button.text = count if button.icon != null else "%s · %s" % [tr(TOOL_KEYS[tool]), count]
		# Иконка с числом запаса: иконка слева, число справа — иначе они накладываются.
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# «Дорогу» не блокируем и без запаса: можно вести дорогу по мостам и переносить выезд дома.
		button.disabled = stocks[tool] == 0 and tool != StrokeInput.Tool.ROAD


func show_message(key: String) -> void:
	_toast.text = tr(key)
	_toast_left = TOAST_SECONDS
	if _toast_area.visible and _toast_area.modulate.a > 0.0:
		_toast_area.modulate.a = 1.0  # сообщение уже на экране — только меняем текст
		return
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_area.visible = true
	_toast_area.modulate.a = 0.0
	_place_toast(TOAST_FROM)
	_toast_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_method(_place_toast, TOAST_FROM, TOAST_TOP, 0.25)
	_toast_tween.tween_property(_toast_area, "modulate:a", 1.0, 0.2)


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
		_offer_buttons[i].icon = icon(UPGRADE_ICONS[offer[i]])
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
		if _toast_left < TOAST_FADE:
			_toast_area.modulate.a = clampf(_toast_left / TOAST_FADE, 0.0, 1.0)
		if _toast_left <= 0.0:
			_toast_area.visible = false


## Строка статистики: иконка и число, а без иконки — подпись словами.
func _stat_row(icon_id: String, label: Label, key: String) -> Control:
	var row := _ignore(HBoxContainer.new())
	var texture := icon(icon_id)
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2.ONE * STAT_ICON_SIZE
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
	else:
		_stat_keys[label] = key
	row.add_child(label)
	return row


func _set_stat(label: Label, value: int) -> void:
	label.text = tr(_stat_keys[label]) % value if _stat_keys.has(label) else str(value)


## Всплывающее сообщение сверху по центру: белый текст на тёмной плашке цвета кнопок.
func _build_toast() -> void:
	_toast_area.theme = _theme
	_toast_area.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_area.visible = false
	add_child(_toast_area)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiTheme.style(Color(Palette.BUTTON, 0.95), 0, 28)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	_toast.add_theme_color_override("font_color", Palette.BUTTON_TEXT)
	_toast.add_theme_font_size_override("font_size", 32)
	panel.add_child(_toast)
	_toast_area.add_child(panel)


func _place_toast(top: float) -> void:
	_toast_area.offset_top = top
	_toast_area.offset_bottom = top + 90.0


func _build_offer() -> void:
	var box := _modal(_offer)
	_offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_offer_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in 2:
		var button := _button("", null)
		button.custom_minimum_size = Vector2(340, 220)
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", UPGRADE_ICON_SIZE)
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
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var restart := _button(tr("GAME_OVER_RESTART"), null)
	restart.custom_minimum_size = Vector2(260, 96)
	restart.pressed.connect(restart_requested.emit)
	row.add_child(restart)
	var to_menu := _button(tr("GAME_OVER_TO_MENU"), null)
	to_menu.custom_minimum_size = Vector2(260, 96)
	to_menu.pressed.connect(menu_requested.emit)
	row.add_child(to_menu)


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
		margin.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	return box


func _ignore(control: Control) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


## Кнопка с иконкой, а пока иконки нет — с текстом.
func _icon_button(icon_id: String, fallback: String, group: ButtonGroup) -> Button:
	var texture := icon(icon_id)
	var button := _button("" if texture != null else fallback, group)
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button


func _button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	if group != null:
		button.toggle_mode = true
		button.button_group = group
	button.pressed.connect(button_clicked.emit)
	_buttons.append(button)
	return button
