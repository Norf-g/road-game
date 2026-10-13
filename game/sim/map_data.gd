class_name MapData
extends RefCounted
## Карта, нарисованная вручную: размер, вода и здания на старте.
## В rows символ «.» — суша, «~» — вода.

var size := Vector2i.ZERO
var water: Dictionary = {}                # Vector2i -> true
var houses: Array[Dictionary] = []        # {cell: Vector2i, color: int}
var destinations: Array[Dictionary] = []  # {rect: Rect2i, entrance: Vector2i, color: int}


static func from_dict(data: Dictionary) -> MapData:
	var map := MapData.new()
	var rows: Array = data["rows"]
	map.size = Vector2i((rows[0] as String).length(), rows.size())
	for y in rows.size():
		var row: String = rows[y]
		assert(row.length() == map.size.x, "Map rows must have equal length")
		for x in row.length():
			if row[x] == "~":
				map.water[Vector2i(x, y)] = true
	for house: Dictionary in data.get("houses", []):
		map.houses.append({"cell": _vec(house["cell"]), "color": int(house["color"])})
	for dest: Dictionary in data.get("destinations", []):
		var r: Array = dest["rect"]
		map.destinations.append({
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"entrance": _vec(dest["entrance"]),
			"color": int(dest["color"]),
		})
	return map


static func _vec(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
