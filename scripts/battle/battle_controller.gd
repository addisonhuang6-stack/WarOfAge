class_name BattleController
extends Node3D
## 单机战斗场景控制器：搭建世界与 UI、生成双方单位、处理玩家输入、驱动敌方 AI。
## 所有玩家操作（移动）都封装为 Command，经 EventBus 下发（命令模式）。

const SETUP_PATH := "res://data/battle_setup.json"
const UNIT_DATA_DIR := "res://data/units/"
const CAMERA_ZOOM_MIN := 3.0
const CAMERA_ZOOM_MAX := 14.0
const CAMERA_BOUNDS_MIN := Vector2(-9.0, -6.0)
const CAMERA_BOUNDS_MAX := Vector2(9.0, 6.0)

var camera: Camera3D
var canvas_layer: CanvasLayer
var selection_box: Control
var instruction_label: Label
var status_label: Label
var map_label: Label
var result_label: Label
var return_hint_label: Label
var ui_font: SystemFont
var environment: Environment
var ground_mesh: MeshInstance3D
var current_map: Dictionary = {}
var _decor_root: Node3D

var unit_types: Dictionary = {}
var units_by_id: Dictionary = {}
var selected_units: Array[UnitBase] = []
var next_unit_id: int = 0

var _drawing_path: bool = false
var _path_preview: PackedVector2Array = PackedVector2Array()
var _drag_path_world: Array[Vector3] = []
var _box_selecting: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_current: Vector2 = Vector2.ZERO
var _box_shift: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _panning: bool = false
var _enemy_ai_enabled: bool = false
var _ai_timer: float = 0.5
var _battle_over: bool = false
var _battle_result: int = -1
var control_groups: Dictionary = {}
var _drawing_defense_line: bool = false
var _defense_line_start := Vector3.ZERO
var _defense_line_current := Vector3.ZERO
var _pressed_unit: UnitBase = null
var _press_shift: bool = false
var _selected_on_press: bool = false
var _path_mesh: ImmediateMesh
var _path_lines: MeshInstance3D
var _path_timer: float = 0.0


func _ready() -> void:
	_setup_world()
	_setup_ui()
	_load_unit_data()
	_spawn_armies()
	_apply_map()

	EventBus.unit_died.connect(_on_unit_died)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.charge_dust.connect(_on_charge_dust)

	_update_hud()


func _physics_process(delta: float) -> void:
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = 0.1
		_update_path_lines()
		if selected_units.size() > 1:
			selection_box.queue_redraw()

	if _battle_over or not _enemy_ai_enabled:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = 1.2
		_enemy_ai_step()


func _setup_world() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.position = Vector3(0.0, 10.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65.0, -35.0, 0.0)
	add_child(light)

	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.11, 0.12, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.85, 0.85)
	environment.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	ground_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28.0, 18.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/ground.png")
	material.texture_repeat = true
	material.uv1_scale = Vector3(14.0, 9.0, 1.0)
	ground_mesh.mesh = plane
	ground_mesh.material_override = material
	add_child(ground_mesh)

	_decor_root = Node3D.new()
	add_child(_decor_root)

	_path_lines = MeshInstance3D.new()
	_path_mesh = ImmediateMesh.new()
	_path_lines.mesh = _path_mesh
	var path_material := StandardMaterial3D.new()
	path_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_material.vertex_color_use_as_albedo = true
	path_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	path_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_path_lines.material_override = path_material
	add_child(_path_lines)


func _setup_ui() -> void:
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)

	selection_box = Control.new()
	selection_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.draw.connect(_draw_selection_box)
	canvas_layer.add_child(selection_box)

	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Helvetica"])

	instruction_label = _make_label(Vector2(12.0, 8.0), 15)
	instruction_label.text = GameSettings.t("battle.instructions")

	var counter_label := _make_label(Vector2(12.0, 50.0), 16)
	counter_label.text = GameSettings.t("battle.counter")
	counter_label.modulate = Color(1.0, 0.85, 0.4)

	status_label = _make_label(Vector2(12.0, 74.0), 16)
	map_label = _make_label(Vector2(12.0, 98.0), 16)
	map_label.modulate = Color(0.72, 0.84, 1.0)
	result_label = _make_label(Vector2(12.0, 128.0), 30)
	result_label.visible = false
	return_hint_label = _make_label(Vector2(12.0, 168.0), 17)
	return_hint_label.text = GameSettings.t("battle.return_hint")
	return_hint_label.modulate = Color(0.8, 0.86, 0.9)
	return_hint_label.visible = false


func _make_label(position: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	canvas_layer.add_child(label)
	return label


func _load_unit_data() -> void:
	var dir := DirAccess.open(UNIT_DATA_DIR)
	if dir == null:
		push_error("无法读取单位数据目录 %s" % UNIT_DATA_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var unit_data := UnitData.load_from_file(UNIT_DATA_DIR + file_name)
		if unit_data != null:
			unit_types[String(unit_data.id)] = unit_data


func _spawn_armies() -> void:
	var file := FileAccess.open(SETUP_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取战斗配置 %s" % SETUP_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("战斗配置不是有效的 JSON 对象")
		return
	_enemy_ai_enabled = GameSettings.ai_enabled
	_spawn_groups(parsed.get("player", []), 0)
	_spawn_groups(parsed.get("enemy", []), 1)


func _spawn_groups(groups: Variant, team_id: int) -> void:
	if not (groups is Array):
		return
	for group in groups:
		if not (group is Dictionary):
			continue
		var type_name := str(group.get("type", ""))
		var count := int(group.get("count", 0))
		if count <= 0 or not unit_types.has(type_name):
			continue
		var origin_data: Array = group.get("origin", [0.0, 0.0, 0.0])
		var direction_data: Array = group.get("direction", [0.0, 0.0, 1.0])
		var step := float(group.get("step", 1.0))
		var columns := maxi(int(group.get("columns", 1)), 1)
		var column_step := float(group.get("column_step", 0.0))
		var column_dir_data: Array = group.get("column_direction", [0.0, 0.0, 0.0])
		var origin := Vector3(float(origin_data[0]), 0.0, float(origin_data[2]))
		var direction := Vector3(float(direction_data[0]), 0.0, float(direction_data[2])).normalized()
		var column_direction := Vector3(float(column_dir_data[0]), 0.0, float(column_dir_data[2]))
		for i in range(count):
			var row := int(i / columns)
			var column := i % columns
			var offset := direction * (step * float(row)) + column_direction * (column_step * float(column))
			_spawn_unit(type_name, team_id, origin + offset)


func _spawn_unit(type_name: String, team_id: int, position: Vector3) -> void:
	var unit := UnitBase.new()
	unit.data = unit_types[type_name]
	unit.player_id = team_id
	unit.instance_id = next_unit_id
	next_unit_id += 1
	unit.position = position
	add_child(unit)
	units_by_id[unit.instance_id] = unit


func _apply_map() -> void:
	var generator := MapGenerator.new()
	generator.load_maps()
	var preferred_map := GameSettings.selected_map
	if not WorldState.pending_engagement.is_empty():
		var encounter_map := str(WorldState.pending_engagement.get("map", ""))
		if not encounter_map.is_empty():
			preferred_map = encounter_map
	current_map = generator.pick_map(preferred_map)
	if current_map.is_empty():
		return
	generator.apply(current_map, ground_mesh, environment, _decor_root, randi())
	if map_label != null:
		map_label.text = _localized_map_text()


func _localized_map_text() -> String:
	if current_map.is_empty():
		return ""
	var names: Variant = current_map.get("name", {})
	var map_name := str(current_map.get("id", ""))
	if names is Dictionary:
		var name_dict: Dictionary = names
		map_name = str(name_dict.get(GameSettings.language, name_dict.get("en", map_name)))
	return GameSettings.t("battle.map") % map_name


func _select_single(unit: UnitBase) -> void:
	selected_units = [unit]
	_refresh_selection()


func _toggle_select(unit: UnitBase) -> void:
	if unit in selected_units:
		selected_units.erase(unit)
	else:
		selected_units.append(unit)
	_refresh_selection()


func _clear_selection() -> void:
	selected_units.clear()
	_refresh_selection()


func _refresh_selection() -> void:
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if is_instance_valid(unit):
			unit.is_selected = unit in selected_units
	EventBus.selection_changed.emit(selected_units.size())
	_update_hud()
	if selection_box != null:
		selection_box.queue_redraw()


func _box_select(from: Vector2, to: Vector2, additive: bool) -> void:
	var rect := Rect2(from, to - from).abs()
	var found: Array[UnitBase] = []
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0 or unit.player_id != 0:
			continue
		var center := camera.unproject_position(unit.global_position)
		if rect.has_point(center):
			found.append(unit)
	if additive:
		for unit in found:
			if not (unit in selected_units):
				selected_units.append(unit)
	else:
		selected_units = found
	_refresh_selection()


func _pick_unit(screen_position: Vector2) -> UnitBase:
	var best: UnitBase = null
	var best_distance := 12.0
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0 or unit.player_id != 0:
			continue
		var center := camera.unproject_position(unit.global_position)
		var distance := screen_position.distance_to(center)
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _mouse_to_ground(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return Vector3.ZERO
	var t := -origin.y / direction.y
	return origin + direction * t


func _zoom_camera(factor: float) -> void:
	camera.size = clampf(camera.size * factor, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)


func _pan_camera(screen_delta: Vector2) -> void:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var units_per_pixel := camera.size * 2.0 / viewport_height
	camera.position += Vector3(-screen_delta.x, 0.0, -screen_delta.y) * units_per_pixel
	camera.position.x = clampf(camera.position.x, CAMERA_BOUNDS_MIN.x, CAMERA_BOUNDS_MAX.x)
	camera.position.z = clampf(camera.position.z, CAMERA_BOUNDS_MIN.y, CAMERA_BOUNDS_MAX.y)


func _issue_move(points: Array[Vector3]) -> void:
	if points.is_empty() or selected_units.is_empty():
		return
	_issue_move_for_units(selected_units, points, 0)


## 为每个单位生成带自身阵型偏移的移动命令，转弯时保持相对队列。
func _issue_move_for_units(units: Array[UnitBase], points: Array[Vector3], command_player_id: int) -> void:
	if points.is_empty() or units.is_empty():
		return
	var valid_units: Array[UnitBase] = []
	var centroid := Vector3.ZERO
	for unit in units:
		if is_instance_valid(unit) and unit.hp > 0.0:
			valid_units.append(unit)
			centroid += unit.global_position
	if valid_units.is_empty():
		return
	centroid /= float(valid_units.size())
	var center: Vector3 = Vector3(points.back().x, 0.0, points.back().z)
	var forward := center - centroid
	if points.size() >= 2:
		var tail_direction: Vector3 = points.back() - points[points.size() - 2]
		if tail_direction.length() > 0.01:
			forward = tail_direction
	var slots := _formation_slots(valid_units.size(), center, forward, _average_radius(valid_units))
	var tick := Engine.get_process_frames()
	for i in range(valid_units.size()):
		var unit := valid_units[i]
		var offset := slots[i] - center
		var waypoints: Array[Vector3] = []
		for point in points:
			waypoints.append(Vector3(point.x + offset.x, 0.0, point.z + offset.z))
		var command := Command.new()
		command.type = &"move"
		command.player_id = command_player_id
		command.unit_ids.assign([unit.instance_id])
		command.waypoints.assign(waypoints)
		command.target_position = waypoints.back()
		command.tick = tick
		tick += 1
		EventBus.command_issued.emit(command)


func _average_radius(units: Array[UnitBase]) -> float:
	var total := 0.0
	var count := 0
	for unit in units:
		if is_instance_valid(unit):
			total += unit.radius
			count += 1
	return total / float(maxi(count, 1))


func _formation_slots(count: int, center: Vector3, forward: Vector3, average_radius: float) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	if count <= 0:
		return slots
	var columns := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(columns)))
	var spacing := maxf(average_radius * 3.0, 0.16)
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length() < 0.001:
		flat_forward = Vector3.RIGHT
	flat_forward = flat_forward.normalized()
	var right := Vector3(-flat_forward.z, 0.0, flat_forward.x)
	for i in range(count):
		var row := int(i / columns)
		var column := i % columns
		var lateral := (float(column) - (float(columns) - 1.0) * 0.5) * spacing
		var depth := (float(row) - (float(rows) - 1.0) * 0.5) * spacing
		slots.append(center + right * lateral - flat_forward * depth)
	return slots


func _issue_charge() -> void:
	var unit_ids: Array[int] = []
	for unit in selected_units:
		if is_instance_valid(unit) and float(unit.data.get_stat(&"charge_max_speed", 0.0)) > 0.0:
			unit_ids.append(unit.instance_id)
	if unit_ids.is_empty():
		return
	var command := Command.new()
	command.type = &"charge"
	command.player_id = 0
	command.unit_ids = unit_ids
	command.tick = Engine.get_process_frames()
	EventBus.command_issued.emit(command)
	GameSettings.play_click()


func _select_same_type() -> void:
	if selected_units.is_empty():
		return
	var type_id: StringName = selected_units[0].data.id
	var same_type: Array[UnitBase] = []
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if is_instance_valid(unit) and unit.hp > 0.0 and unit.player_id == 0 and unit.data.id == type_id:
			same_type.append(unit)
	if same_type.is_empty():
		return
	selected_units = same_type
	_refresh_selection()


func _assign_control_group(index: int) -> void:
	if selected_units.is_empty():
		return
	var unit_ids: Array[int] = []
	for unit in selected_units:
		if is_instance_valid(unit):
			unit_ids.append(unit.instance_id)
	control_groups[index] = unit_ids
	GameSettings.play_click()


func _select_control_group(index: int) -> void:
	var stored: Variant = control_groups.get(index, [])
	if not (stored is Array):
		return
	var chosen: Array[UnitBase] = []
	for raw_id in stored:
		var unit_id := int(raw_id)
		if not units_by_id.has(unit_id):
			continue
		var unit: UnitBase = units_by_id[unit_id]
		if is_instance_valid(unit) and unit.hp > 0.0:
			chosen.append(unit)
	selected_units = chosen
	_refresh_selection()


func _digit_group(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode) - int(KEY_1) + 1
	return 0


func _issue_defense_line(start: Vector3, finish: Vector3) -> void:
	if selected_units.is_empty():
		return
	var flat_start := Vector3(start.x, 0.0, start.z)
	var flat_finish := Vector3(finish.x, 0.0, finish.z)
	var segment := flat_finish - flat_start
	if segment.length() < 0.3:
		return
	var direction := segment.normalized()
	var perpendicular := Vector3(-direction.z, 0.0, direction.x)
	var midpoint := flat_start.lerp(flat_finish, 0.5)
	var line_facing := _line_facing(midpoint, perpendicular)
	var count := selected_units.size()
	var average_radius := 0.0
	for unit in selected_units:
		if is_instance_valid(unit):
			average_radius += unit.radius
	average_radius /= maxf(float(count), 1.0)
	var slot_width := maxf(average_radius * 3.0, 0.16)
	var max_columns := maxi(1, int(floor(segment.length() / slot_width)))
	var row_spacing := maxf(average_radius * 3.0, 0.18)
	var tick := Engine.get_process_frames()
	for i in range(count):
		var unit: UnitBase = selected_units[i]
		if not is_instance_valid(unit):
			continue
		var row := int(i / max_columns)
		var column := i % max_columns
		var units_in_row := mini(max_columns, count - row * max_columns)
		var t := 0.5 if units_in_row == 1 else float(column) / float(units_in_row - 1)
		var target := flat_start.lerp(flat_finish, t) - line_facing * row_spacing * float(row)
		var command := Command.new()
		command.type = &"move"
		command.player_id = 0
		command.unit_ids.assign([unit.instance_id])
		command.waypoints.assign([target])
		command.target_position = target
		command.facing = line_facing
		command.tick = tick
		tick += 1
		EventBus.command_issued.emit(command)
	GameSettings.play_click()


func _line_facing(midpoint: Vector3, perpendicular: Vector3) -> Vector3:
	var best: UnitBase = null
	var best_distance := INF
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0 or unit.player_id == 0:
			continue
		var distance := Vector2(unit.global_position.x - midpoint.x, unit.global_position.z - midpoint.z).length()
		if distance < best_distance:
			best = unit
			best_distance = distance
	if best == null:
		return perpendicular
	var to_enemy := Vector3(best.global_position.x - midpoint.x, 0.0, best.global_position.z - midpoint.z)
	return perpendicular if to_enemy.dot(perpendicular) >= 0.0 else -perpendicular


func _on_charge_dust(position: Vector3) -> void:
	var dust := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = randf_range(0.22, 0.4)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.88, 0.87, 0.83, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust.mesh = mesh
	dust.material_override = material
	dust.position = position + Vector3(randf_range(-0.12, 0.12), 0.005, randf_range(-0.12, 0.12))
	add_child(dust)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(dust, "scale", Vector3(2.2, 1.0, 2.2), 1.0)
	tween.tween_property(material, "albedo_color:a", 0.0, 1.0)
	tween.chain().tween_callback(dust.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_return_to_world()
		elif event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			_clear_selection()
		elif not _battle_over:
			var group_index := _digit_group(event.keycode)
			if group_index > 0:
				if event.ctrl_pressed or event.meta_pressed or Input.is_key_pressed(KEY_T):
					_assign_control_group(group_index)
				else:
					_select_control_group(group_index)
			elif event.keycode == KEY_T:
				_select_same_type()
			elif event.keycode == KEY_C:
				_issue_charge()
		return

	# 视角缩放与平移：战斗结束后依然可用
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(0.9)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.1)
			return
	if event is InputEventMagnifyGesture:
		if event.factor > 0.0:
			_zoom_camera(1.0 / event.factor)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		return
	if event is InputEventMouseMotion and _panning:
		_pan_camera(event.relative)
		return

	if _battle_over:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not selected_units.is_empty():
				_issue_move([_mouse_to_ground(event.position)])
	elif event is InputEventMouseMotion:
		_handle_motion(event)


func _handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		_press_position = event.position
		_pressed_unit = _pick_unit(event.position)
		_press_shift = event.shift_pressed
		_selected_on_press = false

		if (event.ctrl_pressed or event.meta_pressed) and not selected_units.is_empty() and _pressed_unit == null:
			_drawing_defense_line = true
			_defense_line_start = _mouse_to_ground(event.position)
			_defense_line_current = _defense_line_start
		else:
			# 无选择时点击单位立即选中；已有选择时，点击留到松手再判定，
			# 这样按住左键直接从单位身上拖线也能下达移动命令。
			if _pressed_unit != null and selected_units.is_empty():
				if _press_shift:
					_toggle_select(_pressed_unit)
				else:
					_select_single(_pressed_unit)
				_selected_on_press = true

			if not selected_units.is_empty():
				_drawing_path = true
				_drag_path_world.clear()
				_path_preview.clear()
				var world := _mouse_to_ground(event.position)
				_drag_path_world.append(world)
				_path_preview.append(event.position)
			else:
				_box_selecting = true
				_box_select_start = event.position
				_box_select_current = event.position
				_box_shift = event.shift_pressed
		selection_box.queue_redraw()
	else:
		if _drawing_defense_line:
			_drawing_defense_line = false
			_issue_defense_line(_defense_line_start, _defense_line_current)
			_pressed_unit = null
		elif _drawing_path:
			_drawing_path = false
			if _press_position.distance_to(event.position) <= 5.0:
				if not _selected_on_press:
					if _pressed_unit != null:
						if _press_shift:
							_toggle_select(_pressed_unit)
						else:
							_select_single(_pressed_unit)
					else:
						_clear_selection()
			else:
				_issue_move(_drag_path_world)
			_drag_path_world.clear()
			_path_preview.clear()
			_pressed_unit = null
			_selected_on_press = false
		elif _box_selecting:
			_box_selecting = false
			if _press_position.distance_to(event.position) > 5.0:
				_box_select(_box_select_start, _box_select_current, _box_shift)
			else:
				_clear_selection()
		selection_box.queue_redraw()


func _handle_motion(event: InputEventMouseMotion) -> void:
	if _drawing_defense_line:
		_defense_line_current = _mouse_to_ground(event.position)
		selection_box.queue_redraw()
	elif _drawing_path:
		var world := _mouse_to_ground(event.position)
		if _drag_path_world.is_empty() or _drag_path_world.back().distance_to(world) >= 0.7:
			_drag_path_world.append(world)
			_path_preview.append(event.position)
		selection_box.queue_redraw()
	elif _box_selecting:
		_box_select_current = event.position
		selection_box.queue_redraw()


func _draw_selection_box() -> void:
	if _box_selecting:
		var rect := Rect2(_box_select_start, _box_select_current - _box_select_start).abs()
		selection_box.draw_rect(rect, Color(0.35, 0.7, 1.0, 0.16), true)
		selection_box.draw_rect(rect, Color(0.4, 0.75, 1.0, 0.9), false, 2.0)
	if _drawing_path:
		_draw_dashed(_path_preview, Color(1.0, 0.9, 0.4, 0.95), 3.0)
	if _drawing_defense_line:
		var from := camera.unproject_position(_defense_line_start)
		var to := camera.unproject_position(_defense_line_current)
		selection_box.draw_line(from, to, Color(0.35, 0.9, 1.0, 0.95), 3.0)
		var screen_dir := to - from
		if screen_dir.length() > 0.001:
			var normal := Vector2(-screen_dir.y, screen_dir.x).normalized()
			selection_box.draw_line(from - normal * 10.0, from + normal * 10.0, Color(0.35, 0.9, 1.0, 0.95), 2.0)
			selection_box.draw_line(to - normal * 10.0, to + normal * 10.0, Color(0.35, 0.9, 1.0, 0.95), 2.0)
	_draw_formation_preview()


func _draw_formation_preview() -> void:
	if selected_units.size() < 2 or _drawing_defense_line:
		return
	var center := Vector3.ZERO
	var forward := Vector3.ZERO
	for unit in selected_units:
		if is_instance_valid(unit):
			center += unit.global_position
			forward += unit.facing
	center /= float(selected_units.size())
	if _drawing_path and not _drag_path_world.is_empty():
		center = _drag_path_world.back()
		if _drag_path_world.size() >= 2:
			forward = _drag_path_world.back() - _drag_path_world[_drag_path_world.size() - 2]
	if forward.length() < 0.01:
		forward = Vector3.RIGHT
	var slots := _formation_slots(
		selected_units.size(),
		Vector3(center.x, 0.0, center.z),
		forward,
		_average_radius(selected_units)
	)
	for i in range(mini(slots.size(), selected_units.size())):
		var screen := camera.unproject_position(slots[i])
		var color := Color(0.3, 0.75, 1.0, 0.5)
		if selected_units[i].data.shape == "triangle":
			selection_box.draw_colored_polygon(PackedVector2Array([
				screen + Vector2(0.0, -4.0),
				screen + Vector2(-3.5, 3.0),
				screen + Vector2(3.5, 3.0),
			]), color)
		else:
			selection_box.draw_circle(screen, 3.0, color)


func _draw_dashed(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.is_empty():
		return
	if points.size() == 1:
		selection_box.draw_circle(points[0], width * 2.0, color)
		return
	var dash := 10.0
	var gap := 8.0
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var segment := to - from
		var length := segment.length()
		if length <= 0.001:
			continue
		var direction := segment / length
		var travelled := 0.0
		while travelled < length:
			var end := minf(travelled + dash, length)
			selection_box.draw_line(from + direction * travelled, from + direction * end, color, width)
			travelled += dash + gap


func _update_path_lines() -> void:
	if _path_mesh == null:
		return
	_path_mesh.clear_surfaces()
	var has_paths := false
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if is_instance_valid(unit) and unit.hp > 0.0 and unit.player_id == 0 and not unit.move_points.is_empty():
			has_paths = true
			break
	if not has_paths:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0 or unit.player_id != 0 or unit.move_points.is_empty():
			continue
		var points: Array[Vector3] = []
		points.append(Vector3(unit.global_position.x, 0.06, unit.global_position.z))
		for point in unit.move_points:
			points.append(Vector3(point.x, 0.06, point.z))
		var color := Color(0.45, 0.45, 0.45, 0.65)
		if unit.is_selected:
			color = Color(1.0, 0.85, 0.3, 0.9)
		for i in range(points.size() - 1):
			_path_mesh.surface_set_color(color)
			_path_mesh.surface_add_vertex(points[i])
			_path_mesh.surface_set_color(color)
			_path_mesh.surface_add_vertex(points[i + 1])
	_path_mesh.surface_end()


func _update_hud() -> void:
	var player_count := 0
	var enemy_count := 0
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0:
			continue
		if unit.player_id == 0:
			player_count += 1
		else:
			enemy_count += 1
	status_label.text = GameSettings.t("battle.status") % [player_count, enemy_count, selected_units.size()]


func _on_unit_died(unit: UnitBase) -> void:
	selected_units.erase(unit)
	units_by_id.erase(unit.instance_id)
	EventBus.selection_changed.emit(selected_units.size())
	_check_battle_end()
	_update_hud()


func _check_battle_end() -> void:
	if _battle_over:
		return
	var player_alive := 0
	var enemy_alive := 0
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0:
			continue
		if unit.player_id == 0:
			player_alive += 1
		else:
			enemy_alive += 1
	if player_alive == 0 or enemy_alive == 0:
		_battle_over = true
		EventBus.battle_ended.emit(0 if enemy_alive == 0 else 1)


func _on_battle_ended(winner: int) -> void:
	_battle_result = winner
	if winner == 0:
		result_label.text = GameSettings.t("battle.victory")
		result_label.modulate = Color(1.0, 0.9, 0.35)
	else:
		result_label.text = GameSettings.t("battle.defeat")
		result_label.modulate = Color(1.0, 0.45, 0.4)
	result_label.visible = true
	return_hint_label.visible = true


func _return_to_world() -> void:
	if not _battle_over:
		return
	WorldState.resolve_battle("player" if _battle_result == 0 else "enemy")
	get_tree().change_scene_to_file("res://scenes/macro_map.tscn")


func _enemy_ai_step() -> void:
	var enemies: Array[UnitBase] = []
	var players: Array[UnitBase] = []
	for id in units_by_id:
		var unit: UnitBase = units_by_id[id]
		if not is_instance_valid(unit) or unit.hp <= 0.0:
			continue
		if unit.player_id == 0:
			players.append(unit)
		elif unit.melee_target == null and not unit.is_charging:
			enemies.append(unit)
	if enemies.is_empty() or players.is_empty():
		return
	var centroid := Vector3.ZERO
	for unit in enemies:
		centroid += unit.global_position
	centroid /= float(enemies.size())
	var target := players[0]
	var nearest_distance := Vector2(target.global_position.x - centroid.x, target.global_position.z - centroid.z).length()
	for candidate in players:
		var distance := Vector2(candidate.global_position.x - centroid.x, candidate.global_position.z - centroid.z).length()
		if distance < nearest_distance:
			target = candidate
			nearest_distance = distance
	if nearest_distance <= 0.6:
		return
	_issue_move_for_units(enemies, [Vector3(target.global_position.x, 0.0, target.global_position.z)], 1)
