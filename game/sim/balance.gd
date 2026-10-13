class_name Balance
extends RefCounted
## Числа баланса. Значения здесь — запасные, настоящие лежат в config/balance.json.

var start_tiles := 60
var start_bridges := 2
var cars_per_house := 1
## Скорость машины, клеток в секунду.
var car_speed := 2.0
## Минимальная дистанция между машинами на полосе, в клетках.
var car_gap := 0.4
## Половина зоны перекрёстка: машина ждёт на этом расстоянии от центра клетки.
var intersection_radius := 0.3
var parking_time := 1.0
## Секунд между новыми заказами у одного места назначения.
var pin_interval := 7.0
## Если заказов больше этого числа, у места назначения идёт таймер переполнения.
var overflow_pins := 5
## Сколько секунд переполнения выдерживает место назначения до проигрыша.
var overflow_time := 20.0
## Скорость остывания таймера переполнения относительно его роста.
var overflow_recovery := 0.5


static func from_dict(data: Dictionary) -> Balance:
	var balance := Balance.new()
	for key: String in data:
		var current: Variant = balance.get(key)
		if current == null:
			push_warning("Unknown balance key: %s" % key)
			continue
		var value: Variant = data[key]
		balance.set(key, int(value) if typeof(current) == TYPE_INT else float(value))
	return balance
