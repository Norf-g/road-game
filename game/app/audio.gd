class_name Audio
extends Node
## Звуки и фоновая музыка. Соответствие «событие → файлы» собрано здесь, чтобы любой звук было легко
## заменить. Если для события несколько файлов, играет случайный из них. Включён ли звук,
## хранится в user://settings.cfg.

const SOUNDS := {
	"build": ["res://assets/audio/sfx/build_0.ogg", "res://assets/audio/sfx/build_1.ogg", "res://assets/audio/sfx/build_2.ogg"],
	"erase": ["res://assets/audio/sfx/erase.ogg"],
	"week_end": ["res://assets/audio/sfx/week_end.ogg"],
	"upgrade": ["res://assets/audio/sfx/upgrade.ogg"],
	"click": ["res://assets/audio/sfx/click.ogg"],
	"game_over": ["res://assets/audio/sfx/game_over.ogg"],
}
## Музыка подхватывается, когда появится файл (см. art/prompts/music.md).
const MUSIC_PATHS := [
	"res://assets/audio/music/theme.ogg", "res://assets/audio/music/theme.mp3", "res://assets/audio/music/theme.wav",
]
const SETTINGS_PATH := "user://settings.cfg"
## Один и тот же звук не чаще, чем раз в столько секунд: дорога строится по клетке за раз.
const MIN_INTERVAL := 0.07
const VOICES := 6
const MUSIC_VOLUME_DB := -10.0

var muted := false

var _streams := {}  # событие -> Array[AudioStream]
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played := {}
var _music := AudioStreamPlayer.new()


func _ready() -> void:
	muted = _load_muted()
	for event: String in SOUNDS:
		_streams[event] = (SOUNDS[event] as Array).map(func(path: String) -> AudioStream: return load(path))
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_music.volume_db = MUSIC_VOLUME_DB
	_music.finished.connect(_music.play)  # петля для форматов без встроенного повтора
	add_child(_music)
	_music.stream = _load_music()
	if _music.stream != null and not muted:
		_music.play()


func play(event: String) -> void:
	if muted:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(event, -1.0)) < MIN_INTERVAL:
		return
	_last_played[event] = now
	var options: Array = _streams[event]
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % VOICES
	player.stream = options[randi() % options.size()]
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()


func set_muted(value: bool) -> void:
	muted = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
	if muted:
		_music.stop()
		for player in _players:
			player.stop()
	elif _music.stream != null:
		_music.play()


func _load_muted() -> bool:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return false
	return bool(config.get_value("audio", "muted", false))


func _load_music() -> AudioStream:
	for path: String in MUSIC_PATHS:
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
				stream.set("loop", true)
			return stream
	return null
