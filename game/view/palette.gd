class_name Palette
extends RefCounted
## Палитра игры. Те же цвета описаны в art/styleguide.md — меняем в обоих местах сразу.

## Цвета домов и мест назначения. Красного среди них нет: красный — только цвет тревоги.
const BUILDINGS: Array[Color] = [
	Color("f0883e"), Color("4d8fd1"), Color("f2b33d"), Color("4fb286"), Color("9572c9"), Color("e883b0"),
]
const LAND := Color("f4efe6")
## Всё, что за пределами видимой части карты, — цвет фона.
const OUTSIDE := Color("e6ded1")
const GRID := Color("eae3d7")
const WATER := Color("9ccbe8")
const ROAD := Color("7c7c84")
const BRIDGE := Color("a08f7e")
const MOTORWAY := Color("5e5e66")
const TREE_CROWN := Color("8cc084")
const TREE_TRUNK := Color("9c7a5b")
const PREVIEW_OK := Color("7fbf7f")
const PREVIEW_BAD := Color("e07a70")
const LIGHT_POST := Color("3a3a40")
const LIGHT_LAMP := Color("f2b33d")
const ROUNDABOUT_RING := ROAD
const ROUNDABOUT_ISLAND := TREE_CROWN
## Тревога: переполнение, мигание места назначения, метка у края экрана.
const OVERFLOW := Color("d9443a")
## Текст и иконки интерфейса — графит.
const TEXT := Color("3a3a40")
const PANEL := Color(1.0, 1.0, 1.0, 0.97)
## Кнопки — «мокрый асфальт» с белым текстом; активная — темнее, с жёлтой рамкой и жёлтым текстом.
const BUTTON := Color("34495e")
const BUTTON_HOVER := Color("3d566e")
const BUTTON_ACTIVE := Color("2c3e50")
const BUTTON_TEXT := Color.WHITE
const ACCENT := Color("f2b33d")


static func building(index: int) -> Color:
	return BUILDINGS[index % BUILDINGS.size()]
