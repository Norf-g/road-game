class_name Car
extends RefCounted
## Машина дома. Едет по маршруту из клеток; на дороге находится на полосе
## route[seg] -> route[seg + 1], пройдя по ней расстояние s.

enum State { IDLE, TO_DEST, PARKED, TO_HOME }

var id: int
var home: House
var state: State = State.IDLE
var dest: Destination = null
var route: Array[Vector2i] = []
var seg := 0
var s := 0.0
## false — машина дома или на парковке и ещё не выехала на полосу.
var on_road := false
var park_timer := 0.0
var has_lock := false
var lock_cell := Vector2i.ZERO
## Откуда и куда машина проезжает перекрёсток, на который получила разрешение.
var lock_from := Vector2i.ZERO
var lock_to := Vector2i.ZERO
## Тик, с которого машина ждёт у перекрёстка; -1 — не ждёт.
var wait_since := -1


func _init(car_id: int, car_home: House) -> void:
	id = car_id
	home = car_home


func lane_from() -> Vector2i:
	return route[seg]


func lane_to() -> Vector2i:
	return route[seg + 1]


func is_on_last_lane() -> bool:
	return seg + 2 >= route.size()
