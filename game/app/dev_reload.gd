class_name DevReload
extends Node
## Горячая перезагрузка интерфейса при запуске на ПК в отладке (на телефоне не работает).
## Раз в полсекунды проверяет, не изменились ли файлы интерфейса и палитры; если изменились —
## перечитывает эти скрипты и сообщает об этом, а главная сцена пересоздаёт интерфейс на лету.
## Партия при этом продолжается. Логику игры так не перезагрузить — для неё нужен перезапуск.

signal ui_changed

const CHECK_SECONDS := 0.5
## Порядок важен: сначала то, от чего зависят остальные.
const WATCHED: Array[String] = [
	"res://view/palette.gd",
	"res://ui/ui_theme.gd",
	"res://ui/tech_button.gd",
	"res://ui/hud.gd",
	"res://ui/main_menu.gd",
	"res://ui/edge_alerts.gd",
]

var _times := {}
var _elapsed := 0.0


static func is_available() -> bool:
	return OS.is_debug_build() and OS.has_feature("pc")


func _ready() -> void:
	for path in WATCHED:
		_times[path] = _modified(path)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < CHECK_SECONDS:
		return
	_elapsed = 0.0
	var changed := false
	for path in WATCHED:
		var time := _modified(path)
		if time != _times[path]:
			_times[path] = time
			changed = true
	if changed:
		ui_changed.emit()


## Перечитывает с диска все отслеживаемые скрипты. Вызывать, когда их экземпляров уже нет.
func reload_scripts() -> void:
	for path in WATCHED:
		var script: GDScript = load(path)
		script.source_code = FileAccess.get_file_as_string(path)
		var error := script.reload(true)
		if error != OK:
			push_warning("Не удалось перезагрузить %s: %s" % [path, error_string(error)])
		else:
			print("DevReload: ", path)


func _modified(path: String) -> int:
	return FileAccess.get_modified_time(ProjectSettings.globalize_path(path))
