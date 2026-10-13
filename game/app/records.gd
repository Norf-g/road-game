class_name Records
extends RefCounted
## Лучший результат, сохраняется на устройстве.

const PATH := "user://records.cfg"


static func best_score() -> int:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return 0
	return int(config.get_value("classic", "best_score", 0))


## Записывает результат; true — если это новый рекорд.
static func submit(score: int) -> bool:
	if score <= best_score():
		return false
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("classic", "best_score", score)
	config.save(PATH)
	return true
