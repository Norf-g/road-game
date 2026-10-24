class_name MapData
extends RefCounted
## Карта, нарисованная вручную: размер, вода, здания на старте и сценарий расширения.
## В rows символ «.» — суша, «~» — вода. В expansions — с какой недели какая часть карты видна;
## без них карта видна целиком с начала.

var size := Vector2i.ZERO
var water: Dictionary = {}                # Vector2i -> true
var houses: Array[Dictionary] = []        # {cell: Vector2i, color: int}
var destinations: Array[Dictionary] = []  # {rect: Rect2i, entrance: Vector2i, color: int}
var expansions: Array[Dictionary] = []    # {week: int, rect: Rect2i}, по возрастанию недель


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
		map.destinations.append({
			"rect": _rect(dest["rect"]),
			"entrance": _vec(dest["entrance"]),
			"color": int(dest["color"]),
			"stub": _vec(dest["stub"]) if dest.has("stub") else null,
		})
	for expansion: Dictionary in data.get("expansions", []):
		map.expansions.append({"week": int(expansion["week"]), "rect": _rect(expansion["rect"])})
	if map.expansions.is_empty():
		map.expansions.append({"week": 0, "rect": Rect2i(Vector2i.ZERO, map.size)})
	map.expansions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["week"] < y["week"])
	return map


## Видимая часть карты на неделе week.
func area_at(week: int) -> Rect2i:
	var area: Rect2i = expansions[0]["rect"]
	for expansion in expansions:
		if expansion["week"] <= week:
			area = expansion["rect"]
	return area


static func _rect(value: Array) -> Rect2i:
	return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))


static func _vec(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
