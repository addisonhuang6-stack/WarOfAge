class_name UnitBase
extends Node3D
## 所有单位的基类：移动、朝向、索敌、攻击、冲锋、血量与表现。
##
## 具体兵种的差异完全由 UnitData（data/units/*.json）驱动，
## 脚本中不出现任何兵种数值，以满足“数据与逻辑分离”。
## 单位只有在收到 Command 时才会移动；未接到命令时原地待命，
## 只攻击进入攻击范围的敌人，不会主动追击。

## 存活单位注册表，用于索敌与单位间推挤。
static var registry: Array[UnitBase] = []
static var _separation_grid: Dictionary = {}
static var _separation_frame: int = -1
const SEPARATION_CELL_SIZE := 0.25

var data: UnitData
var player_id: int = -1
var instance_id: int = -1

var hp: float = 0.0
var max_hp: float = 0.0
var radius: float = 0.5

## 当前朝向（XZ 平面单位向量），三角标记始终指向该方向。
var facing: Vector3 = Vector3.RIGHT

## 移动路径点（XZ 平面世界坐标）。
var move_points: Array[Vector3] = []

## 到达路径终点后恢复的阵型朝向（防御线命令）。
var hold_facing: Vector3 = Vector3.ZERO

## 当前攻击目标；为 null 时按索敌规则自动寻找。
var current_target: UnitBase = null

## 是否正在冲锋。
var is_charging: bool = false

var is_selected: bool = false:
	set(value):
		is_selected = value
		if _selection_marker != null:
			_selection_marker.visible = value

var _speed: float = 0.0
var _attack_cooldown: float = 0.0
var _acquire_timer: float = 0.0

var _charge_elapsed: float = 0.0
var _charge_speed: float = 0.0
var _charge_loss: float = 0.0
var _charge_hits: Dictionary = {}
var _dust_timer: float = 0.0

var _marker: Node3D
var _selection_marker: MeshInstance3D
var _hp_bar_bg: MeshInstance3D
var _hp_bar_fill: MeshInstance3D


func _ready() -> void:
	registry.append(self)
	EventBus.command_issued.connect(receive_command)
	_apply_data()
	facing = Vector3.LEFT if player_id == 1 else Vector3.RIGHT
	_build_visuals()
	_update_hp_bar()


func _exit_tree() -> void:
	registry.erase(self)


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_acquire_timer -= delta

	if is_charging:
		_process_charge(delta)
	else:
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

	_update_marker_rotation()


## 命令模式入口：所有行为都经由 Command 下发。
func receive_command(command: Command) -> void:
	if command == null or command.player_id != player_id:
		return
	if not (instance_id in command.unit_ids):
		return
	match command.type:
		&"move":
			_cancel_charge()
			current_target = null
			move_points.clear()
			hold_facing = Vector3.ZERO
			if command.facing.length() > 0.001:
				hold_facing = Vector3(command.facing.x, 0.0, command.facing.z).normalized()
			if command.waypoints.is_empty():
				move_points.append(command.target_position)
			else:
				move_points.assign(command.waypoints)
		&"charge":
			_start_charge()


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

	_marker = Node3D.new()
	add_child(_marker)
	var team_color := Color(0.25, 0.68, 1.0) if player_id == 0 else Color(1.0, 0.3, 0.28)
	var outline := Color(0.04, 0.06, 0.08)
	if data != null and data.shape == "triangle":
		_add_flat_triangle(_marker, radius * 2.9, radius * 2.2, outline, 0.025)
		_add_flat_triangle(_marker, radius * 2.5, radius * 1.9, team_color, 0.035)
	else:
		_add_flat_disc(_marker, radius * 1.15, outline, 0.02)
		_add_flat_disc(_marker, radius, team_color, 0.03)
		_add_flat_triangle(_marker, radius * 0.9, radius * 0.65, Color(0.96, 0.96, 0.96), 0.045)
	_update_marker_rotation()

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


func _add_flat_disc(parent: Node3D, disc_radius: float, color: Color, y: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = disc_radius
	mesh.bottom_radius = disc_radius
	mesh.height = 0.02
	instance.mesh = mesh
	instance.material_override = _flat_material(color)
	instance.position.y = y
	parent.add_child(instance)
	return instance


func _add_flat_triangle(parent: Node3D, length: float, width: float, color: Color, y: float) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, length * 0.5),
		Vector3(-width * 0.5, 0.0, -length * 0.5),
		Vector3(width * 0.5, 0.0, -length * 0.5),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _flat_material(color)
	instance.position.y = y
	parent.add_child(instance)
	return instance


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _update_marker_rotation() -> void:
	if _marker == null:
		return
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length() > 0.001:
		_marker.rotation.y = atan2(flat_facing.x, flat_facing.z)


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
			if move_points.is_empty() and hold_facing.length() > 0.001:
				facing = hold_facing
				hold_facing = Vector3.ZERO
			continue
		_move_position(delta, next_point)
		return


func _is_target_engageable(target: UnitBase) -> bool:
	if target == null or not is_instance_valid(target) or target.hp <= 0.0:
		return false
	if target.player_id == player_id:
		return false
	return horizontal_distance_to(target) <= float(data.get_stat(&"attack_range", 0.0))


func _attack(target: UnitBase) -> void:
	var flat_to_target := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	if flat_to_target.length() > 0.001:
		facing = flat_to_target.normalized()
	var is_counter: bool = CombatSystem.counter_multiplier(data, target.data) > 1.0
	var damage: float = CombatSystem.compute_damage(data, target.data, global_position, target.global_position, target.facing)
	target.take_damage(damage, self)
	EventBus.unit_attacked.emit(self, target, damage, is_counter)
	_attack_cooldown = float(data.get_stat(&"attack_interval", 1.0))


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
	var direction := offset.normalized()
	facing = direction
	var step := _speed * delta
	global_position = from + direction * minf(step, offset.length())


func _apply_separation(delta: float) -> void:
	_ensure_separation_grid()
	var center := _grid_cell(global_position)
	var push := Vector3.ZERO
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var bucket_value: Variant = _separation_grid.get(Vector2i(center.x + dx, center.y + dz))
			if not (bucket_value is Array):
				continue
			var bucket: Array = bucket_value
			for other_value in bucket:
				if not (other_value is UnitBase):
					continue
				var other: UnitBase = other_value
				if other == self or not is_instance_valid(other) or other.hp <= 0.0:
					continue
				var away := Vector3(
					global_position.x - other.global_position.x,
					0.0,
					global_position.z - other.global_position.z
				)
				var distance := away.length()
				var min_distance := radius + other.radius + 0.005
				if distance >= min_distance:
					continue
				if distance < 0.0001:
					var angle := float((instance_id * 37 + other.instance_id * 11) % 360) * PI / 180.0
					away = Vector3(cos(angle), 0.0, sin(angle))
					distance = 0.0001
				push += away.normalized() * (min_distance - distance)
	if push != Vector3.ZERO:
		var strength: float = float(data.get_stat(&"separation_strength", 2.0))
		global_position += push * minf(strength * delta, 1.0)


static func _ensure_separation_grid() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _separation_frame:
		return
	_separation_frame = frame
	_separation_grid.clear()
	for unit in registry:
		if not is_instance_valid(unit) or unit.hp <= 0.0:
			continue
		var cell := _grid_cell(unit.global_position)
		var bucket: Array = _separation_grid.get(cell, [])
		bucket.append(unit)
		_separation_grid[cell] = bucket


static func _grid_cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / SEPARATION_CELL_SIZE), floori(position.z / SEPARATION_CELL_SIZE))


static func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var p := Vector2(point.x, point.z)
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var ab := pb - pa
	var length_squared := ab.length_squared()
	if length_squared <= 0.000001:
		return Vector3(pa.x, 0.0, pa.y)
	var t := clampf((p - pa).dot(ab) / length_squared, 0.0, 1.0)
	return Vector3(pa.x + ab.x * t, 0.0, pa.y + ab.y * t)


func _start_charge() -> void:
	var max_speed := float(data.get_stat(&"charge_max_speed", 0.0))
	if max_speed <= 0.0:
		return
	current_target = null
	move_points.clear()
	hold_facing = Vector3.ZERO
	is_charging = true
	_charge_elapsed = 0.0
	_charge_speed = _speed
	_charge_loss = 0.0
	_charge_hits.clear()
	_dust_timer = 0.0


func _process_charge(delta: float) -> void:
	var duration := maxf(float(data.get_stat(&"charge_duration", 4.0)), 0.01)
	var max_duration := maxf(float(data.get_stat(&"charge_max_duration", 7.0)), duration)
	var max_speed := float(data.get_stat(&"charge_max_speed", _speed))
	_charge_elapsed += delta
	var ramp := clampf(_charge_elapsed / duration, 0.0, 1.0)
	_charge_speed = maxf(lerpf(_speed, max_speed, ramp) - _charge_loss, 0.0)
	if _charge_speed <= 0.05:
		_cancel_charge()
		return

	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length() < 0.001:
		flat_facing = Vector3.RIGHT
	flat_facing = flat_facing.normalized()
	var previous_position := global_position
	global_position += flat_facing * _charge_speed * delta
	_handle_charge_collisions(flat_facing, previous_position)

	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.07
		EventBus.charge_dust.emit(Vector3(global_position.x, 0.02, global_position.z))

	if _charge_elapsed >= max_duration:
		_cancel_charge()


func _handle_charge_collisions(flat_facing: Vector3, from: Vector3) -> void:
	var to := global_position
	for unit in registry:
		if unit == self or not is_instance_valid(unit) or unit.hp <= 0.0:
			continue
		var closest := _closest_point_on_segment(unit.global_position, from, to)
		var offset := Vector3(unit.global_position.x - closest.x, 0.0, unit.global_position.z - closest.z)
		var distance := offset.length()
		if distance > radius + unit.radius + 0.03:
			continue
		var from_to_unit := Vector3(unit.global_position.x - from.x, 0.0, unit.global_position.z - from.z)
		if from_to_unit.dot(flat_facing) < -0.05:
			continue
		if _charge_hits.has(unit.instance_id):
			continue
		if unit.is_charging:
			continue

		if unit.player_id == player_id:
			_charge_hits[unit.instance_id] = true
			var side := Vector3(-flat_facing.z, 0.0, flat_facing.x)
			var side_sign := 1.0 if offset.dot(side) >= 0.0 else -1.0
			if absf(offset.dot(side)) < 0.0001:
				side_sign = 1.0 if unit.instance_id % 2 == 0 else -1.0
			var dodge := float(data.get_stat(&"charge_friendly_dodge", 0.35))
			unit.move_points.clear()
			unit.move_points.append(Vector3(
				unit.global_position.x + side.x * side_sign * dodge,
				0.0,
				unit.global_position.z + side.z * side_sign * dodge
			))
			unit.current_target = null
			continue

		var target_toughness := float(unit.data.get_stat(&"toughness", 0.0))
		if _charge_speed <= target_toughness:
			continue
		_charge_hits[unit.instance_id] = true
		var push_scale := float(data.get_stat(&"charge_push_scale", 0.16))
		var push_distance := clampf((_charge_speed - target_toughness) * push_scale, 0.15, 0.8)
		var push_direction := offset.normalized() if offset.length() > 0.001 else flat_facing
		unit.global_position += push_direction * push_distance
		_charge_loss += target_toughness
		_charge_speed = maxf(_charge_speed - target_toughness, 0.0)
		EventBus.charge_dust.emit(Vector3(unit.global_position.x, 0.02, unit.global_position.z))


func _cancel_charge() -> void:
	is_charging = false
	_charge_speed = 0.0
	_charge_loss = 0.0
	_charge_hits.clear()


func _die() -> void:
	set_physics_process(false)
	registry.erase(self)
	EventBus.unit_died.emit(self)
	queue_free()
