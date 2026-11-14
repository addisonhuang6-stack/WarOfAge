class_name UnitBase
extends Node3D
## 所有单位的基类：移动、索敌、攻击、血量与表现。
##
## 具体兵种的差异完全由 UnitData（data/units/*.json）驱动，
## 脚本中不出现任何兵种数值，以满足“数据与逻辑分离”。
## 单位只有在收到 Command 时才会移动；未接到命令时原地待命，
## 只攻击进入攻击范围的敌人，不会主动追击。

## 存活单位注册表，用于索敌与单位间推挤。
static var registry: Array[UnitBase] = []

var data: UnitData
var player_id: int = -1
var instance_id: int = -1

var hp: float = 0.0
var max_hp: float = 0.0
var radius: float = 0.5

## 移动路径点（XZ 平面世界坐标）。
var move_points: Array[Vector3] = []

## 当前攻击目标；为 null 时按索敌规则自动寻找。
var current_target: UnitBase = null

var is_selected: bool = false:
	set(value):
		is_selected = value
		if _selection_marker != null:
			_selection_marker.visible = value

var _speed: float = 0.0
var _attack_cooldown: float = 0.0
var _acquire_timer: float = 0.0

var _sprite: Sprite3D
var _selection_marker: MeshInstance3D
var _hp_bar_bg: MeshInstance3D
var _hp_bar_fill: MeshInstance3D


func _ready() -> void:
	registry.append(self)
	EventBus.command_issued.connect(receive_command)
	_apply_data()
	_build_visuals()
	_update_hp_bar()


func _exit_tree() -> void:
	registry.erase(self)


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_acquire_timer -= delta

	if not move_points.is_empty():
		current_target = null
		_follow_path(delta)
	else:
		# 待命状态：只攻击射程内的敌人，绝不自主移动。
		if _acquire_timer <= 0.0:
			_acquire_target()
			_acquire_timer = 0.25
		if current_target != null and not is_instance_valid(current_target):
			current_target = null
		if current_target != null:
			if _is_target_engageable(current_target):
				if _attack_cooldown <= 0.0:
					_attack(current_target)
			else:
				current_target = null

	_apply_separation(delta)


## 命令模式入口：所有行为都经由 Command 下发。
func receive_command(command: Command) -> void:
	if command == null or command.player_id != player_id:
		return
	if not (instance_id in command.unit_ids):
		return
	match command.type:
		&"move":
			# 红警式移动：新命令立即执行，丢弃之前未走完的路径。
			current_target = null
			move_points.clear()
			if command.waypoints.is_empty():
				move_points.append(command.target_position)
			else:
				move_points.assign(command.waypoints)


func take_damage(amount: float, _attacker: UnitBase) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_update_hp_bar()
	if hp <= 0.0:
		_die()


func horizontal_distance_to(other: Node3D) -> float:
	var a := global_position
	var b := other.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _apply_data() -> void:
	max_hp = float(data.get_stat(&"hp", 1.0))
	hp = max_hp
	_speed = float(data.get_stat(&"speed", 0.0))
	radius = float(data.get_stat(&"radius", 0.5))


func _build_visuals() -> void:
	# 地面阴影
	var shadow := Sprite3D.new()
	shadow.texture = load("res://assets/shadow.png")
	shadow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shadow.pixel_size = radius * 2.6 / 128.0
	shadow.position.y = 0.01
	add_child(shadow)

	# 立绘
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if data != null and not data.texture_path.is_empty():
		var texture := load(data.texture_path) as Texture2D
		if texture != null:
			_sprite.texture = texture
			_sprite.pixel_size = radius * 2.2 / float(texture.get_height())
	_sprite.position.y = radius * 1.05
	_sprite.modulate = Color(0.8, 0.9, 1.0) if player_id == 0 else Color(1.0, 0.7, 0.65)
	add_child(_sprite)

	# 选中标记（贴地圆盘）
	_selection_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 1.25
	disc.bottom_radius = radius * 1.25
	disc.height = 0.02
	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_marker.mesh = disc
	_selection_marker.material_override = disc_material
	_selection_marker.position.y = 0.015
	_selection_marker.visible = is_selected
	add_child(_selection_marker)

	# 血条（贴地）
	_hp_bar_bg = _make_bar(Color(0.1, 0.1, 0.1, 0.85), 1.0, 0.02)
	_hp_bar_fill = _make_bar(Color(0.3, 0.9, 0.35), 1.0, 0.026)


func _make_bar(color: Color, frac: float, y: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := radius * 2.0
	box.size = Vector3(length * frac, 0.02, radius * 0.45)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.mesh = box
	bar.material_override = material
	bar.position = Vector3(-length * (1.0 - frac) / 2.0, y, radius * 1.35)
	add_child(bar)
	return bar


func _update_hp_bar() -> void:
	if _hp_bar_fill == null:
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var length := radius * 2.0
	var box := _hp_bar_fill.mesh as BoxMesh
	if box != null:
		box.size.x = length * frac
	_hp_bar_fill.position.x = -(length * (1.0 - frac)) / 2.0
	var material := _hp_bar_fill.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(0.3, 0.9, 0.35).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)


func _follow_path(delta: float) -> void:
	while not move_points.is_empty():
		var next_point: Vector3 = move_points[0]
		if global_position.distance_to(next_point) <= 0.15:
			move_points.pop_front()
			continue
		_move_position(delta, next_point)
		break


func _is_target_engageable(target: UnitBase) -> bool:
	if target == null or not is_instance_valid(target) or target.hp <= 0.0:
		return false
	if target.player_id == player_id:
		return false
	return horizontal_distance_to(target) <= float(data.get_stat(&"attack_range", 0.0))


func _attack(target: UnitBase) -> void:
	var is_counter: bool = CombatSystem.counter_multiplier(data, target.data) > 1.0
	var damage: float = CombatSystem.compute_damage(data, target.data)
	target.take_damage(damage, self)
	EventBus.unit_attacked.emit(self, target, damage, is_counter)
	_attack_cooldown = float(data.get_stat(&"attack_interval", 1.0))
	_punch_scale()


func _acquire_target() -> void:
	var attack_range: float = float(data.get_stat(&"attack_range", 0.0))
	var best: UnitBase = null
	var best_distance := INF
	for unit in registry:
		if unit == self or unit.player_id == player_id or unit.hp <= 0.0:
			continue
		var distance := horizontal_distance_to(unit)
		if distance <= attack_range and distance < best_distance:
			best = unit
			best_distance = distance
	current_target = best


func _move_position(delta: float, target: Vector3) -> void:
	var from := Vector3(global_position.x, 0.0, global_position.z)
	var to := Vector3(target.x, 0.0, target.z)
	var offset := to - from
	if offset.length() <= 0.001:
		return
	var step := _speed * delta
	global_position = from + offset.normalized() * minf(step, offset.length())


func _apply_separation(delta: float) -> void:
	var push := Vector3.ZERO
	for unit in registry:
		if unit == self or unit.hp <= 0.0:
			continue
		var distance := horizontal_distance_to(unit)
		var min_distance := radius + unit.radius
		if distance > 0.001 and distance < min_distance:
			var away := Vector3(global_position.x - unit.global_position.x, 0.0, global_position.z - unit.global_position.z)
			push += away.normalized() * (min_distance - distance)
	if push != Vector3.ZERO:
		var strength: float = float(data.get_stat(&"separation_strength", 2.0))
		global_position += push * minf(strength * delta, 1.0)


func _die() -> void:
	set_physics_process(false)
	registry.erase(self)
	EventBus.unit_died.emit(self)
	queue_free()


func _punch_scale() -> void:
	var base := _sprite.pixel_size
	var tween := create_tween()
	tween.tween_property(_sprite, "pixel_size", base * 1.25, 0.06)
	tween.tween_property(_sprite, "pixel_size", base, 0.1)
