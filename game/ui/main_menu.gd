class_name MainMenu
extends CanvasLayer
## Главное меню: заставка игры (с названием на ней) слева во всю высоту экрана, кнопки справа.
## Свободное место по бокам занимает та же заставка, растянутая на весь экран и затемнённая.
## При запуске игры (play_intro) заставка сначала, как загрузочный экран, покрывает весь экран, а затем
## плавно уменьшается и уезжает влево, пока проявляются фон и кнопки, — без скачка после загрузки.
## Без начатой партии — «Начать» и «Выход»; во время партии — «Продолжить», «Новая игра» и «Выход».

signal start_requested
signal continue_requested
signal exit_requested
## Нажата любая кнопка — для звука щелчка.
signal button_clicked

const SPLASH_PATH := "res://assets/ui/splash.png"
## Насколько затемнена растянутая заставка на фоне.
const BACKDROP_DIM := Color(0.42, 0.45, 0.5)
const BUTTON_SIZE := Vector2(460, 110)
## Доля ширины экрана под заставку слева (остальное — кнопки).
const PICTURE_SHARE := 0.55
const INTRO_DELAY := 0.25
const INTRO_SECONDS := 0.8

var _continue := Button.new()
var _start := Button.new()
## Заставка в меню; положение задаём сами, чтобы его можно было анимировать.
var _picture := TextureRect.new()
var _backdrop: TextureRect
var _column := VBoxContainer.new()
var _intro_running := false


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var background := ColorRect.new()
	background.color = Palette.BUTTON_ACTIVE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var splash: Texture2D = load(SPLASH_PATH) if ResourceLoader.exists(SPLASH_PATH) else null
	if splash != null:
		_backdrop = _splash_rect(splash, TextureRect.STRETCH_KEEP_ASPECT_COVERED, BACKDROP_DIM)
		root.add_child(_backdrop)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(row)
	var spacer := Control.new()  # место под заставку слева
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = PICTURE_SHARE / (1.0 - PICTURE_SHARE)
	row.add_child(spacer)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 24)
	center.add_child(_column)

	_add_button(_column, _continue, tr("MENU_CONTINUE"), continue_requested)
	_add_button(_column, _start, tr("MENU_START"), start_requested)
	_add_button(_column, Button.new(), tr("MENU_EXIT"), exit_requested)

	if splash != null:
		_picture.texture = splash
		_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_picture.stretch_mode = TextureRect.STRETCH_SCALE
		_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_picture)
		get_viewport().size_changed.connect(_place_picture)
		_place_picture()
	show_menu(false)


## Анимация при запуске игры: заставка от «на весь экран» к своему месту слева, фон и кнопки проявляются.
func play_intro() -> void:
	if _picture.texture == null:
		return
	_intro_running = true
	_set_picture_rect(_cover_rect())
	_column.modulate.a = 0.0
	_backdrop.modulate.a = 0.0
	var start := _cover_rect()
	var tween := create_tween()
	tween.tween_interval(INTRO_DELAY)
	tween.tween_method(_animate_picture.bind(start), 0.0, 1.0, INTRO_SECONDS) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_column, "modulate:a", 1.0, INTRO_SECONDS)
	tween.parallel().tween_property(_backdrop, "modulate:a", 1.0, INTRO_SECONDS)
	tween.finished.connect(func() -> void: _intro_running = false)


## Промежуточное положение заставки: t = 0 — на весь экран (start), t = 1 — на своём месте.
func _animate_picture(t: float, start: Rect2) -> void:
	var target := _target_rect()
	_set_picture_rect(Rect2(start.position.lerp(target.position, t), start.size.lerp(target.size, t)))


## Квадратная заставка на своём месте: по центру левой части экрана, во всю её высоту или ширину.
func _target_rect() -> Rect2:
	var view := get_viewport().get_visible_rect().size
	var width := view.x * PICTURE_SHARE
	var side := minf(view.y, width)
	return Rect2(Vector2((width - side) / 2, (view.y - side) / 2), Vector2(side, side))


## Заставка, как на загрузочном экране: покрывает весь экран, по центру по горизонтали и прижата
## к верху, чтобы было видно название. Загрузочный экран показывает верхнюю часть картинки
## в пропорциях экрана (assets/ui/splash_boot.png) — так переход к меню идёт без скачка.
func _cover_rect() -> Rect2:
	var view := get_viewport().get_visible_rect().size
	var side := maxf(view.x, view.y)
	return Rect2(Vector2((view.x - side) / 2, 0.0), Vector2(side, side))


func _place_picture() -> void:
	if not _intro_running:
		_set_picture_rect(_target_rect())


func _set_picture_rect(rect: Rect2) -> void:
	_picture.position = rect.position
	_picture.size = rect.size


func _splash_rect(texture: Texture2D, stretch: TextureRect.StretchMode, tint: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = stretch
	rect.modulate = tint
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect


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
