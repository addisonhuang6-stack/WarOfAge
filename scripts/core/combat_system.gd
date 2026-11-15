class_name CombatSystem
extends Object
## 战斗数值计算（纯逻辑，不依赖任何场景）。
##
## 所有数值都来自 UnitData（data/units/*.json），本文件不硬编码任何兵种数值，
## 以保证“数据与逻辑分离”。全部为静态纯函数，便于测试与后续 Lockstep 确定性模拟。


## 计算攻击方对目标造成的最终伤害（克制加成、方向护甲后再减去护甲，且不低于最低伤害）。
static func compute_damage(
	attacker: UnitData,
	target: UnitData,
	attacker_position: Vector3 = Vector3.ZERO,
	target_position: Vector3 = Vector3.ZERO,
	target_facing: Vector3 = Vector3.ZERO,
	attacker_facing: Vector3 = Vector3.ZERO
) -> float:
	var attack: float = float(attacker.get_stat(&"attack", 0.0))
	attack *= attack_direction_multiplier(attacker, attacker_position, target_position, attacker_facing)
	var armor: float = float(target.get_stat(&"armor", 0.0))
	armor *= directional_armor_multiplier(target, attacker_position, target_position, target_facing)
	var min_damage: float = float(attacker.get_stat(&"min_damage", 0.0))
	var damage := attack * counter_multiplier(attacker, target) - armor
	return maxf(damage, min_damage)


## 从侧面或背后发起攻击时的伤害倍率（长矛兵为 0.3，即伤害减少 70%）。
static func attack_direction_multiplier(
	attacker: UnitData,
	attacker_position: Vector3,
	target_position: Vector3,
	attacker_facing: Vector3
) -> float:
	var penalty := float(attacker.get_stat(&"side_back_attack_multiplier", 0.0))
	if penalty <= 0.0 or attacker_facing.length() < 0.001:
		return 1.0
	var to_target := Vector3(target_position.x - attacker_position.x, 0.0, target_position.z - attacker_position.z)
	if to_target.length() < 0.001:
		return 1.0
	var flat_facing := Vector3(attacker_facing.x, 0.0, attacker_facing.z)
	if flat_facing.length() < 0.001:
		return 1.0
	var dot := flat_facing.normalized().dot(to_target.normalized())
	return penalty if dot < 0.5 else 1.0


## 冲锋伤害：基础值等于动量 M×V，再减去目标护甲。
static func compute_charge_damage(attacker: UnitData, target: UnitData, momentum: float) -> float:
	var armor := float(target.get_stat(&"armor", 0.0))
	var min_damage := float(attacker.get_stat(&"min_damage", 0.0))
	return maxf(momentum - armor, min_damage)


## 方向护甲：背后受击护甲 -70%，侧面受击护甲 -40%（只对配置了该规则的单位生效）。
static func directional_armor_multiplier(
	target: UnitData,
	attacker_position: Vector3,
	target_position: Vector3,
	target_facing: Vector3
) -> float:
	if not bool(target.get_stat(&"directional_armor", false)):
		return 1.0
	var to_attacker := Vector3(attacker_position.x - target_position.x, 0.0, attacker_position.z - target_position.z)
	var flat_facing := Vector3(target_facing.x, 0.0, target_facing.z)
	if to_attacker.length() < 0.001 or flat_facing.length() < 0.001:
		return 1.0
	var dot := flat_facing.normalized().dot(to_attacker.normalized())
	if dot < -0.5:
		return float(target.get_stat(&"rear_armor_multiplier", 0.3))
	if absf(dot) <= 0.5:
		return float(target.get_stat(&"flank_armor_multiplier", 0.6))
	return 1.0


## 攻击方对目标的克制倍率：目标带有关键标签时生效（例如长矛兵反骑）。
static func counter_multiplier(attacker: UnitData, target: UnitData) -> float:
	var counter_tags: Array = attacker.get_stat(&"counter_tags", [])
	for tag in counter_tags:
		if target.has_tag(StringName(tag)):
			return float(attacker.get_stat(&"counter_multiplier", 1.0))
	return 1.0


## 目标是否处于攻击方的近战范围（水平距离）。
static func is_in_attack_range(attacker: UnitData, distance: float) -> bool:
	return distance <= float(attacker.get_stat(&"attack_range", 0.0))
