class_name UnitData
extends Resource
## 单位类型的基础数据（静态模板）。
##
## 数据与逻辑分离：所有兵种属性都定义在 data/units/*.json 中，
## 本类只负责承载与读取这些数据，不包含任何战斗逻辑。

## 单位类型的唯一标识，例如 &"spearman"。
@export var id: StringName = &""

## 显示名称，例如 "长矛兵"。
@export var name: String = ""

## 标签集合，用于兵种分组与克制判断，例如 &"infantry"、&"anti_cavalry"。
@export var tags: Array[StringName] = []

## 数值属性表，例如 { "hp": 100, "attack": 12, "speed": 4.5 }。
@export var stats: Dictionary = {}

## 单位立绘贴图路径，例如 "res://assets/units/spearman.png"。
@export var texture_path: String = ""

## 单位在地图上的几何形状：circle（圆+内三角）或 triangle。
@export var shape: String = "circle"


## 从 JSON 字典构建数据对象，缺失字段使用默认值。
static func from_dict(data: Dictionary) -> UnitData:
	var unit := UnitData.new()
	unit.id = StringName(data.get("id", ""))
	unit.name = str(data.get("name", ""))
	unit.texture_path = str(data.get("texture", ""))
	unit.shape = str(data.get("shape", "circle"))

	var raw_tags: Variant = data.get("tags", [])
	if raw_tags is Array:
		var tag_array: Array = raw_tags
		for tag in tag_array:
			unit.tags.append(StringName(tag))

	var raw_stats: Variant = data.get("stats", {})
	if raw_stats is Dictionary:
		unit.stats = raw_stats

	return unit


## 从 data/units/ 下的 JSON 文件加载单位数据。
static func load_from_file(path: String) -> UnitData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("UnitData: 无法打开文件 %s" % path)
		return null

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("UnitData: 文件 %s 不是有效的 JSON 对象" % path)
		return null

	return from_dict(parsed)


## 判断该单位类型是否带有指定标签。
func has_tag(tag: StringName) -> bool:
	return tag in tags


## 读取某个数值属性；属性不存在时返回 [param default_value]。
func get_stat(key: StringName, default_value: Variant = null) -> Variant:
	return stats.get(key, default_value)
