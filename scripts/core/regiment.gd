class_name Regiment
extends RefCounted
## 一个军团（Total War 式单位）对应一组具体士兵。

var id: String = ""
var player_id: int = -1
var unit_type_id: StringName = &""
var display_name: String = ""
var unit_ids: Array[int] = []
var icon_shape: String = "circle"
var max_unit_hp: float = 1.0


func alive_units(units_by_id: Dictionary) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit_id in unit_ids:
		if not units_by_id.has(unit_id):
			continue
		var unit: UnitBase = units_by_id[unit_id]
		if is_instance_valid(unit) and unit.hp > 0.0:
			result.append(unit)
	return result


func alive_count(units_by_id: Dictionary) -> int:
	return alive_units(units_by_id).size()


func centroid(units_by_id: Dictionary) -> Vector3:
	var units := alive_units(units_by_id)
	if units.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	for unit in units:
		center += unit.global_position
	return center / float(units.size())


func hp_fraction(units_by_id: Dictionary) -> float:
	var units := alive_units(units_by_id)
	if units.is_empty():
		return 0.0
	var current := 0.0
	for unit in units:
		current += unit.hp
	var total := max_unit_hp * float(unit_ids.size())
	return 0.0 if total <= 0.0 else clampf(current / total, 0.0, 1.0)
