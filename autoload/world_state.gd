extends Node
## 宏观世界状态：跨场景保存世界地图上的据点、边境与战斗结果。

signal changed

const WORLD_PATH := "res://data/world_map.json"

var initialized: bool = false
var config: Dictionary = {}
var bases: Dictionary = {}
var dots: Array[Dictionary] = []
var pending_engagement: Dictionary = {}
var last_result: String = ""


func start_new_game() -> void:
	initialized = false
	config.clear()
	bases.clear()
	dots.clear()
	pending_engagement.clear()
	last_result = ""
	ensure_initialized()
	changed.emit()


func ensure_initialized() -> void:
	if initialized:
		return
	_load_world()


func _load_world() -> void:
	initialized = true
	var file := FileAccess.open(WORLD_PATH, FileAccess.READ)
	if file == null:
		push_error("WorldState: 无法读取 %s" % WORLD_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("WorldState: 世界地图配置不是有效的 JSON 对象")
		return
	config = parsed
	var raw_bases: Variant = parsed.get("bases", {})
	if raw_bases is Dictionary:
		var base_dict: Dictionary = raw_bases
		for faction in base_dict:
			bases[str(faction)] = _to_vec2(base_dict[faction])
	var raw_dots: Variant = parsed.get("dots", [])
	if raw_dots is Array:
		for raw_dot in raw_dots:
			if raw_dot is Dictionary:
				dots.append(_make_dot(raw_dot))


func _make_dot(raw: Dictionary) -> Dictionary:
	return {
		"id": str(raw.get("id", "")),
		"faction": str(raw.get("faction", "player")),
		"pos": _to_vec2(raw.get("pos", [0.5, 0.5])),
		"target": null,
		"strength": int(raw.get("strength", 1)),
	}


func _to_vec2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(0.5, 0.5)


func get_dot(dot_id: String) -> Dictionary:
	for dot in dots:
		if str(dot.get("id", "")) == dot_id:
			return dot
	return {}


## 返回世界地图某个归一化坐标所在地形。
func biome_at(position: Vector2) -> String:
	var biomes: Variant = config.get("biomes", {})
	if not (biomes is Dictionary):
		return "grassland"
	var biome_dict: Dictionary = biomes
	var default_map := str(biome_dict.get("default", "grassland"))
	var circles: Variant = biome_dict.get("circles", [])
	if circles is Array:
		for circle_value in circles:
			if not (circle_value is Dictionary):
				continue
			var circle: Dictionary = circle_value
			var center := _to_vec2(circle.get("center", [0.5, 0.5]))
			var radius := _to_vec2(circle.get("radius", [0.1, 0.1]))
			var dx := (position.x - center.x) / maxf(radius.x, 0.0001)
			var dy := (position.y - center.y) / maxf(radius.y, 0.0001)
			if dx * dx + dy * dy <= 1.0:
				return str(circle.get("map", default_map))
	return default_map


func biome_circles() -> Array:
	var biomes: Variant = config.get("biomes", {})
	if biomes is Dictionary:
		var biome_dict: Dictionary = biomes
		var circles: Variant = biome_dict.get("circles", [])
		if circles is Array:
			return circles
	return []


func biome_labels() -> Array:
	var biomes: Variant = config.get("biomes", {})
	if biomes is Dictionary:
		var biome_dict: Dictionary = biomes
		var labels: Variant = biome_dict.get("labels", [])
		if labels is Array:
			return labels
	return []


## 玩家与敌方据点接触时记录交战，供微观战斗结束后结算。
func begin_engagement(player_id: String, enemy_id: String, map_id: String = "") -> void:
	pending_engagement = {"player": player_id, "enemy": enemy_id, "map": map_id}


## 微观战斗结束：败方据点从世界地图上移除。
func resolve_battle(winner: String) -> void:
	last_result = winner
	if pending_engagement.is_empty():
		changed.emit()
		return
	var loser_id := str(pending_engagement.get("enemy", "")) if winner == "player" else str(pending_engagement.get("player", ""))
	pending_engagement.clear()
	for index in range(dots.size() - 1, -1, -1):
		if str(dots[index].get("id", "")) == loser_id:
			dots.remove_at(index)
			break
	changed.emit()
