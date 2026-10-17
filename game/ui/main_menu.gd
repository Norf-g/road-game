class_name MainMenu
extends CanvasLayer
## Главное меню: название игры, эмблема (если картинка уже есть) и кнопки.
## Без начатой партии — «Начать» и «Выход»; во время партии — «Продолжить», «Новая игра» и «Выход».

signal start_requested
signal continue_requested
signal exit_requested
## Нажата любая кнопка — для звука щелчка.
signal button_clicked

const EMBLEM_PATH := "res://assets/ui/emblem.png"
const BUTTON_SIZE := Vector2(460, 110)

var _continue := Button.new()
var _start := Button.new()


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var background := ColorRect.new()
	background.color = Palette.OUTSIDE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	if ResourceLoader.exists(EMBLEM_PATH):
		var emblem := TextureRect.new()
		emblem.texture = load(EMBLEM_PATH)
		emblem.custom_minimum_size = Vector2(240, 240)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(emblem)
	var title := Label.new()
	title.text = tr("TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	column.add_child(gap)

	_add_button(column, _continue, tr("MENU_CONTINUE"), continue_requested)
	_add_button(column, _start, tr("MENU_START"), start_requested)
	_add_button(column, Button.new(), tr("MENU_EXIT"), exit_requested)
	show_menu(false)


## Показывает меню. has_game — есть ли партия, к которой можно вернуться.
func show_menu(has_game: bool) -> void:
	_continue.visible = has_game
	_start.text = tr("MENU_NEW_GAME") if has_game else tr("MENU_START")
	visible = true


func _add_button(column: VBoxContainer, button: Button, text: String, action: Signal) -> void:
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 40)
	button.pressed.connect(button_clicked.emit)
	button.pressed.connect(action.emit)
	column.add_child(button)
