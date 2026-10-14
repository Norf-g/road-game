class_name Balance
extends RefCounted
## Числа баланса. Значения здесь — запасные, настоящие лежат в config/balance.json.

# --- Стартовые запасы ---
var start_tiles := 30
var start_bridges := 1
## Самый длинный мост, в клетках воды.
var bridge_max_length := 4

# --- Машины и перекрёстки ---
var cars_per_house := 1
## Скорость машины, клеток в секунду.
var car_speed := 2.0
## Минимальная дистанция между машинами на полосе, в клетках.
var car_gap := 0.4
## Половина зоны перекрёстка: машина ждёт на этом расстоянии от центра клетки.
var intersection_radius := 0.3
## Сколько стоит машина перед обычным перекрёстком («уступи дорогу»).
var yield_time := 0.4
## Сколько секунд горит зелёный для одной группы направлений.
var light_phase_time := 4.0
## Сколько машин одновременно может быть на развязке.
var roundabout_capacity := 3
var parking_time := 1.0

# --- Шоссе ---
var motorway_max_length := 30.0
var motorway_speed := 2.0

# --- Заказы и проигрыш ---
## Секунд между новыми заказами у одного места назначения в первую неделю.
var pin_interval := 7.0
## Каждую неделю интервал умножается на это число, но не опускается ниже pin_interval_min.
var pin_interval_decay := 0.93
var pin_interval_min := 2.5
## Если заказов больше этого числа, у места назначения идёт таймер переполнения.
var overflow_pins := 5
## Сколько секунд переполнения выдерживает место назначения до проигрыша.
var overflow_time := 20.0
## Скорость остывания таймера переполнения относительно его роста.
var overflow_recovery := 0.5

# --- Недели и улучшения ---
var week_seconds := 60.0
## Клетки дорог, которые игрок получает в конце каждой недели.
var week_tiles := 15
## Сколько даёт улучшение «Дороги» и «Мосты».
var upgrade_tiles := 20
var upgrade_bridges := 2

# --- Модуль генерации ---
## Неделя появления каждого цвета; длина списка — сколько всего цветов.
var color_weeks: Array = [0, 1, 3, 5, 7, 10]
## Сколько домов появляется вместе с новым цветом.
var houses_per_new_color := 2
## Секунд между появлением домов в первую неделю; каждую неделю умножается на house_interval_decay.
var house_interval := 10.0
var house_interval_decay := 0.92
var house_interval_min := 4.0
## Раз в столько недель появляется ещё одно место назначения уже знакомого цвета.
var destination_every_weeks := 3
## Расстояние от нового дома (не в группе) до места назначения его цвета: растёт каждую неделю.
var spawn_distance_start := 5.0
var spawn_distance_growth := 0.7
var spawn_distance_max := 14.0
## Отступ зданий от края видимой части карты, в клетках.
var spawn_edge_margin := 1
## Вероятность, что новый дом встанет рядом с домом того же цвета, а не в новом месте.
var cluster_chance := 0.6


static func from_dict(data: Dictionary) -> Balance:
	var balance := Balance.new()
	for key: String in data:
		var current: Variant = balance.get(key)
		if current == null:
			push_warning("Unknown balance key: %s" % key)
			continue
		var value: Variant = data[key]
		match typeof(current):
			TYPE_INT:
				balance.set(key, int(value))
			TYPE_FLOAT:
				balance.set(key, float(value))
			TYPE_ARRAY:
				balance.set(key, (value as Array).map(func(item: Variant) -> int: return int(item)))
	return balance
