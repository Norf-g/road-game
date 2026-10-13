extends Node3D
## Корневая сцена: загружает карту и баланс, создаёт партию и связывает с ней отображение,
## ввод и интерфейс. Двигает симуляцию фиксированными шагами с учётом паузы и скорости.

const MAP_PATH := "res://maps/city01.json"
const BALANCE_PATH := "res://config/balance.json"
## Больше шагов за кадр не делаем: после подвисания игра не «проматывает» пропущенное время.
const MAX_TICKS_PER_FRAME := 8

var _sim: Simulation
var _world: WorldView
var _camera: CameraController
var _input := StrokeInput.new()
var _hud := Hud.new()
var _speed := 1
var _accumulator := 0.0
var _game_over_shown := false


func _ready() -> void:
	_build_environment()
	add_child(_hud)
	add_child(_input)
	_input.is_over_ui = _hud.is_point_over_ui
	_input.build_failed.connect(_on_build_failed)
	_hud.tool_selected.connect(func(tool: StrokeInput.Tool) -> void: _input.tool = tool)
	_hud.speed_selected.connect(func(speed: int) -> void: _speed = speed)
	_hud.restart_requested.connect(_start_game)
	_start_game()


func _process(delta: float) -> void:
	_accumulator += delta * _speed
	var ticks := 0
	while _accumulator >= Simulation.DT and ticks < MAX_TICKS_PER_FRAME:
		_sim.tick()
		_accumulator -= Simulation.DT
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0
	_hud.update_stats(_sim)
	if _sim.game_over and not _game_over_shown:
		_game_over_shown = true
		_hud.show_game_over(_sim.score)


func _start_game() -> void:
	var map := MapData.from_dict(_load_json(MAP_PATH))
	var balance := Balance.from_dict(_load_json(BALANCE_PATH))
	_sim = Simulation.new(map, balance, randi())
	if _world != null:
		_world.queue_free()
	_world = WorldView.new()
	add_child(_world)
	_world.setup(_sim)
	if _camera == null:
		_camera = _create_camera(map.size)
		add_child(_camera)
	_input.sim = _sim
	_input.camera = _camera
	_input.tool = StrokeInput.Tool.ROAD
	_speed = 1
	_accumulator = 0.0
	_game_over_shown = false
	_hud.reset()


func _on_build_failed(result: RoadNetwork.Result) -> void:
	match result:
		RoadNetwork.Result.NO_TILES:
			_hud.show_message("MSG_NO_TILES")
		RoadNetwork.Result.NO_BRIDGES:
			_hud.show_message("MSG_NO_BRIDGES")
		RoadNetwork.Result.CROSSING:
			_hud.show_message("MSG_CROSSING")


func _create_camera(map_size: Vector2i) -> CameraController:
	var camera := CameraController.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.0
	camera.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	camera.bounds = Rect2(Vector2.ZERO, Vector2(map_size))
	var target := Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0)
	camera.position = target + camera.transform.basis.z * 30.0
	return camera


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.LAND.darkened(0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)


func _load_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary, "Invalid JSON: %s" % path)
	return data
