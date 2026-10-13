class_name Destination
extends RefCounted
## Место назначения: здание на несколько клеток с одним въездом. Копит заказы, которые
## обслуживают машины из домов того же цвета.

var id: int
var rect: Rect2i
var entrance: Vector2i
var color: int
## Заказы, ещё не обслуженные (включая те, к которым машина уже едет).
var pins := 0
## Заказы, к которым уже назначена машина.
var claimed := 0
var pin_timer := 0.0
## Накопленное время переполнения, от 0 до Balance.overflow_time.
var overflow := 0.0


func _init(dest_id: int, dest_rect: Rect2i, dest_entrance: Vector2i, dest_color: int) -> void:
	assert(dest_rect.has_point(dest_entrance), "Entrance must be inside the destination")
	id = dest_id
	rect = dest_rect
	entrance = dest_entrance
	color = dest_color
