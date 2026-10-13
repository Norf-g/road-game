class_name Palette
extends RefCounted
## Цвета прототипа. Финальная палитра появится на этапе 3 вместе с описанием стиля.

const BUILDINGS: Array[Color] = [
	Color("e0605a"), Color("4f86c6"), Color("f2b84b"), Color("5bb37a"), Color("9b6bc6"), Color("e98bb5"),
]
const LAND := Color("efe6d8")
const WATER := Color("8ec5e8")
const GRID := Color("e2d8c6")
const ROAD := Color("6d6d72")
const BRIDGE := Color("8f8173")
const OVERFLOW := Color("d93a2f")
const TEXT := Color("3a3a3a")


static func building(index: int) -> Color:
	return BUILDINGS[index % BUILDINGS.size()]
