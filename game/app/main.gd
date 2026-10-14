extends Node3D
## Корневая сцена: загружает карту и баланс, создаёт партию с модулем генерации и связывает с ней
## отображение, ввод и интерфейс. Двигает симуляцию фиксированными шагами с учётом паузы и скорости.

const MAP_PATH := "res://maps/city01.json"
const BALANCE_PATH := "res://config/balance.json"
## Больше шагов за кадр не делаем: после подвисания игра не «проматывает» пропущенное время.
const MAX_TICKS_PER_FRAME := 8
const CAMERA_PITCH := -60.0
const CAMERA_DISTANCE := 30.0
const RESULT_MESSAGES := {
	RoadNetwork.Result.NO_TILES: "MSG_NO_TILES",
	RoadNetwork.Result.NO_BRIDGES: "MSG_NO_BRIDGES",
	RoadNetwork.Result.CROSSING: "MSG_CROSSING",
	RoadNetwork.Result.NOT_INTERSECTION: "MSG_NOT_INTERSECTION",
	RoadNetwork.Result.OCCUPIED: "MSG_OCCUPIED",
	RoadNetwork.Result.NO_STOCK: "MSG_NO_STOCK",
	RoadNetwork.Result.TOO_LONG: "MSG_TOO_LONG",
	RoadNetwork.Result.NOT_ADJACENT: "MSG_TOO_SHORT",
	RoadNetwork.Result.BLOCKED: "MSG_BLOCKED",
	RoadNetwork.Result.OUT_OF_BOUNDS: "MSG_OUT_OF_AREA",
	RoadNetwork.Result.NOT_CONNECTED: "MSG_NOT_CONNECTED",
	RoadNetwork.Result.BRIDGE_SHAPE: "MSG_BRIDGE_SHAPE",
	RoadNetwork.Result.BRIDGE_TOO_LONG: "MSG_BRIDGE_TOO_LONG",
	RoadNetwork.Result.TERMINAL_FULL: "MSG_HOUSE_CONNECTED",
}

var _sim: Simulation
var _director: Director
var _world: WorldView
var _camera: CameraController
var _input := StrokeInput.new()
var _hud := Hud.new()
var _audio := Audio.new()
var _edge_alerts := EdgeAlerts.new()
var _speed := 1
var _accumulator := 0.0
var _game_over_shown := false
var _offer_shown := false
var _area := Rect2i()


func _ready() -> void:
	_build_environment()
	add_child(_audio)
	var alerts_layer := CanvasLayer.new()  # под интерфейсом, над картой
	alerts_layer.add_child(_edge_alerts)
	add_child(alerts_layer)
	_hud.layer = 2
	add_child(_hud)
	add_child(_input)
	_hud.set_muted(_audio.muted)
	_hud.sound_toggled.connect(_audio.set_muted)
	_hud.button_clicked.connect(_audio.play.bind("click"))
	_input.action_succeeded.connect(_audio.play)
	_input.is_over_ui = _hud.is_point_over_ui
	_input.action_failed.connect(_on_action_failed)
	_input.motorway_preview_changed.connect(func(from: Vector2i, to: Vector2i, valid: bool) -> void:
		_world.show_motorway_preview(from, to, valid))
	_input.motorway_preview_hidden.connect(func() -> void: _world.hide_motorway_preview())
	_hud.tool_selected.connect(func(tool: StrokeInput.Tool) -> void: _input.tool = tool)
	_hud.speed_selected.connect(func(speed: int) -> void: _speed = speed)
	_hud.upgrade_chosen.connect(_on_upgrade_chosen)
	_hud.restart_requested.connect(_start_game)
	_start_game()


func _process(delta: float) -> void:
	if _director.has_offer():
		if not _offer_shown:
			_offer_shown = true
			_audio.play("week_end")
			_hud.show_offer(_director.week, _director.offer, _sim.balance)
		_accumulator = 0.0
	else:
		_accumulator += delta * _speed
	var ticks := 0
	while _accumulator >= Simulation.DT and ticks < MAX_TICKS_PER_FRAME and not _director.has_offer():
		_sim.tick()
		_accumulator -= Simulation.DT
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = 0.0
	if _sim.network.bounds != _area:
		_area = _sim.network.bounds
		_fit_camera(_area)
	_return_to_road_when_out_of_stock()
	_hud.update_stats(_sim, _director)
	if _sim.game_over and not _game_over_shown:
		_game_over_shown = true
		_audio.play("game_over")
		var is_new_record := Records.submit(_sim.score)
		_hud.show_game_over(_sim.score, Records.best_score(), is_new_record)


func _start_game() -> void:
	var map := MapData.from_dict(_load_json(MAP_PATH))
	var balance := Balance.from_dict(_load_json(BALANCE_PATH))
	_sim = Simulation.new(map, balance, randi())
	_director = Director.new(_sim, map)
	if _world != null:
		_world.queue_free()
	_world = WorldView.new()
	add_child(_world)
	_world.setup(_sim)
	if _camera == null:
		_camera = CameraController.new()
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.rotation_degrees = Vector3(CAMERA_PITCH, 0.0, 0.0)
		add_child(_camera)
	_area = Rect2i()
	_input.sim = _sim
	_input.camera = _camera
	_edge_alerts.sim = _sim
	_edge_alerts.camera = _camera
	_input.tool = StrokeInput.Tool.ROAD
	_speed = 1
	_accumulator = 0.0
	_game_over_shown = false
	_offer_shown = false
	_hud.reset()


## Показывает видимую часть карты целиком; при расширении карты камера отъезжает.
func _fit_camera(area: Rect2i) -> void:
	_camera.bounds = Rect2(area)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	# Орто-камера под углом видит по вертикали size / sin(угла) клеток земли.
	var by_height := area.size.y * sin(deg_to_rad(-CAMERA_PITCH)) + 3.0
	var by_width := area.size.x / aspect + 2.0
	_camera.size = clampf(maxf(by_height, by_width), _camera.min_size, _camera.max_size)
	var target := Vector3(area.get_center().x, 0.0, area.get_center().y)
	_camera.position = target + _camera.transform.basis.z * CAMERA_DISTANCE


func _return_to_road_when_out_of_stock() -> void:
	var network := _sim.network
	var empty := (_input.tool == StrokeInput.Tool.MOTORWAY and network.motorways_left == 0) \
		or (_input.tool == StrokeInput.Tool.LIGHT and network.lights_left == 0) \
		or (_input.tool == StrokeInput.Tool.ROUNDABOUT and network.roundabouts_left == 0)
	if empty:
		_input.tool = StrokeInput.Tool.ROAD
		_hud.select_tool(StrokeInput.Tool.ROAD)


func _on_upgrade_chosen(index: int) -> void:
	_audio.play("upgrade")
	_director.choose(index)
	_offer_shown = false


func _on_action_failed(result: RoadNetwork.Result) -> void:
	if RESULT_MESSAGES.has(result):
		_hud.show_message(RESULT_MESSAGES[result])


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.OUTSIDE
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
