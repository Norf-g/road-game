class_name UiTheme
extends RefCounted
## Общая тема интерфейса: шрифт Nunito, кнопки «мокрый асфальт» с белым текстом, активная кнопка —
## темнее, с жёлтой рамкой и жёлтым текстом, белые панели окон. Ею пользуются и игра, и меню.

const FONT_PATH := "res://assets/fonts/Nunito.ttf"
const FONT_WEIGHT := 700
const FONT_SIZE := 30
const ICON_SIZE := 56
const CORNER_RADIUS := 20

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _create()
	return _theme


static func font() -> Font:
	return get_theme().default_font


static func _create() -> Theme:
	var theme := Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		var variation := FontVariation.new()
		variation.base_font = load(FONT_PATH)
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): FONT_WEIGHT}
		theme.default_font = variation
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", Palette.TEXT)
	# Иконки кнопок белые (их перекрашивает tools/art.py), поэтому цвет иконки задаётся так же, как текст.
	for state in ["font_color", "font_hover_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		theme.set_color(state, "Button", Palette.BUTTON_TEXT)
	for state in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(state, "Button", Palette.ACCENT)
	theme.set_color("font_disabled_color", "Button", Color(Palette.BUTTON_TEXT, 0.45))
	theme.set_color("icon_disabled_color", "Button", Color(Palette.BUTTON_TEXT, 0.4))
	theme.set_constant("icon_max_width", "Button", ICON_SIZE)
	theme.set_constant("h_separation", "Button", 8)
	theme.set_stylebox("normal", "Button", style(Palette.BUTTON, 0))
	theme.set_stylebox("hover", "Button", style(Palette.BUTTON_HOVER, 0))
	theme.set_stylebox("pressed", "Button", style(Palette.BUTTON_ACTIVE, 4, CORNER_RADIUS, Palette.ACCENT))
	theme.set_stylebox("hover_pressed", "Button", style(Palette.BUTTON_ACTIVE, 4, CORNER_RADIUS, Palette.ACCENT))
	theme.set_stylebox("disabled", "Button", style(Color(Palette.BUTTON, 0.45), 0))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", style(Palette.PANEL, 0, 28))
	theme.set_stylebox("background", "ProgressBar", style(Color(Palette.TEXT, 0.12), 0, 5))
	theme.set_stylebox("fill", "ProgressBar", style(Palette.TEXT, 0, 5))
	return theme


static func style(color: Color, border: int, radius := CORNER_RADIUS, border_color := Palette.TEXT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border)
	box.border_color = border_color
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
