extends Control
## 宏观战略层：世界地图、军队移动、动态边境与微观战斗入口。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var ui_font: SystemFont
var map_canvas: Control
var title_label: Label
var instruction_label: Label
var status_label: Label
var result_label: Label
var menu_button: Button
var restart_button: Button

var selected_dot_id: String = ""
var _frontline_timer: float = 0.0
var _frontline_points: Array[Vector2] = []
var _toast_timer: float = 0.0
var _transitioning: bool = false
var _game_over: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	WorldState.ensure_initialized()
	_build_ui()
	_refresh_frontline()
	_update_hud()
	if WorldState.last_result == "player":
		_show_toast(GameSettings.t("macro.last_win"), Color(0.55, 0.95, 0.6))
	elif WorldState.last_result == "enemy":
		_show_toast(GameSettings.t("macro.last_loss"), Color(1.0, 0.5, 0.45))
	WorldState.last_result = ""


func _build_ui() -> void:
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Helvetica"])
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 16
	theme = ui_theme

	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.06)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var map_texture := TextureRect.new()
	map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture.stretch_mode = TextureRect.STRETCH_SCALE
	map_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture_path := str(WorldState.config.get("map_texture", ""))
	if not texture_path.is_empty():
		var texture := load(texture_path) as Texture2D
		if texture != null:
			map_texture.texture = texture
	add_child(map_texture)

	map_canvas = Control.new()
	map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	map_canvas.draw.connect(_draw_map)
	map_canvas.gui_input.connect(_on_map_gui_input)
	add_child(map_canvas)

	var hud_bar := ColorRect.new()
	hud_bar.color = Color(0.02, 0.03, 0.04, 0.72)
	hud_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_bar.offset_bottom = 96.0
	hud_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_bar)

	title_label = _make_label(Vector2(16.0, 8.0), 24, Color(0.95, 0.82, 0.5))
	title_label.text = GameSettings.t("macro.title")
	instruction_label = _make_label(Vector2(16.0, 40.0), 15, Color(0.85, 0.88, 0.9))
	instruction_label.text = GameSettings.t("macro.instructions")
	status_label = _make_label(Vector2(16.0, 66.0), 15, Color(0.65, 0.85, 0.7))

	result_label = Label.new()
	result_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	result_label.offset_top = -96.0
	result_label.offset_bottom = -44.0
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_override("font", ui_font)
	result_label.add_theme_font_size_override("font_size", 26)
	result_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	result_label.add_theme_constant_override("outline_size", 5)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.visible = false
	add_child(result_label)

	menu_button = _make_button(GameSettings.t("macro.menu"))
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.offset_left = -180.0
	menu_button.offset_right = -16.0
	menu_button.offset_top = 12.0
	menu_button.offset_bottom = 48.0
	menu_button.pressed.connect(_on_menu_pressed)
	add_child(menu_button)

	restart_button = _make_button(GameSettings.t("macro.restart"))
	restart_button.anchor_left = 1.0
	restart_button.anchor_right = 1.0
	restart_button.offset_left = -180.0
	restart_button.offset_right = -16.0
	restart_button.offset_top = 54.0
	restart_button.offset_bottom = 90.0
	restart_button.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	add_child(restart_button)


func _make_label(position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	return button


func _process(delta: float) -> void:
	if _transitioning or _game_over:
		return
	_frontline_timer -= delta
	if _frontline_timer <= 0.0:
		_frontline_timer = float(WorldState.config.get("frontline_refresh", 0.12))
		_refresh_frontline()
		_update_hud()
	_move_dots(delta)
	_update_supply(delta)
	_check_collisions()
	if _transitioning:
		return
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and not _game_over:
			result_label.visible = false
	_check_game_over()
	map_canvas.queue_redraw()


func _refresh_frontline() -> void:
	_frontline_points.clear()
	var players: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	for dot in WorldState.dots:
		var faction := str(dot.get("faction", ""))
		if faction == "player":
			players.append(dot)
		elif faction == "enemy":
			enemies.append(dot)
	if players.is_empty() or enemies.is_empty():
		return
	var candidates: Array[Dictionary] = []
	for player in players:
		var enemy := _nearest_opponent(player, enemies)
		if not enemy.is_empty():
			candidates.append({
				"player": player,
				"enemy": enemy,
				"mid": _dot_pos(player).lerp(_dot_pos(enemy), 0.5),
			})
	if candidates.is_empty():
		return
	var all_midpoints: Array[Vector2] = []
	var x_values: Array[float] = []
	for candidate in candidates:
		var midpoint: Vector2 = candidate["mid"]
		all_midpoints.append(midpoint)
		x_values.append(midpoint.x)
	x_values.sort()
	var median_x := 0.0
	if x_values.size() % 2 == 0:
		median_x = (x_values[x_values.size() / 2 - 1] + x_values[x_values.size() / 2]) * 0.5
	else:
		median_x = x_values[x_values.size() / 2]
	var margin := float(WorldState.config.get("encirclement_margin", 0.02))
	var midpoints: Array[Vector2] = []
	for candidate in candidates:
		var player: Dictionary = candidate["player"]
		var enemy: Dictionary = candidate["enemy"]
		var player_position := _dot_pos(player)
		var enemy_position := _dot_pos(enemy)
		if player_position.x > median_x + margin:
			continue
		if enemy_position.x < median_x - margin:
			continue
		midpoints.append(candidate["mid"])
	if midpoints.is_empty():
		midpoints = all_midpoints
	midpoints.sort_custom(_sort_frontline_points)
	var unique: Array[Vector2] = []
	for point in midpoints:
		var duplicate := false
		for existing in unique:
			if point.distance_to(existing) < 0.012:
				duplicate = true
				break
		if not duplicate:
			unique.append(point)
	if unique.is_empty():
		return
	if unique.size() == 1:
		_frontline_points.append(Vector2(unique[0].x, 0.0))
		_frontline_points.append(Vector2(unique[0].x, 1.0))
	else:
		_frontline_points.append(Vector2(unique[0].x, 0.0))
		for point in unique:
			_frontline_points.append(point)
		_frontline_points.append(Vector2(unique[unique.size() - 1].x, 1.0))


func _nearest_opponent(dot: Dictionary, opponents: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for other in opponents:
		var distance := _dot_pos(dot).distance_to(_dot_pos(other))
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _sort_frontline_points(a: Vector2, b: Vector2) -> bool:
	return a.y < b.y


func _front_x_at(y: float) -> float:
	if _frontline_points.size() < 2:
		return 0.5
	for i in range(_frontline_points.size() - 1):
		var first := _frontline_points[i]
		var second := _frontline_points[i + 1]
		if y <= second.y:
			var span := second.y - first.y
			if span <= 0.0001:
				return second.x
			return lerpf(first.x, second.x, clampf((y - first.y) / span, 0.0, 1.0))
	return _frontline_points.back().x


func _dot_pos(dot: Dictionary) -> Vector2:
	var value: Variant = dot.get("pos", Vector2(0.5, 0.5))
	if value is Vector2:
		return value
	return Vector2(0.5, 0.5)


func _move_dots(delta: float) -> void:
	var player_speed := float(WorldState.config.get("player_speed", 0.05))
	var enemy_speed := float(WorldState.config.get("enemy_speed", 0.03))

	for dot in WorldState.dots:
		if str(dot.get("faction", "")) != "player":
			continue
		var target_value: Variant = dot.get("target")
		if not (target_value is Vector2):
			continue
		var position := _dot_pos(dot)
		var target: Vector2 = target_value
		var speed := player_speed
		var next_position := _move_toward(position, target, speed * delta)
		dot["pos"] = next_position
		if next_position.distance_to(target) <= 0.004:
			dot["pos"] = target
			dot["target"] = null

	var players: Array[Dictionary] = []
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) == "player":
			players.append(dot)
	if players.is_empty():
		return
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) != "enemy":
			continue
		var position := _dot_pos(dot)
		var nearest := players[0]
		var nearest_distance := position.distance_to(_dot_pos(nearest))
		for candidate in players:
			var candidate_distance := position.distance_to(_dot_pos(candidate))
			if candidate_distance < nearest_distance:
				nearest = candidate
				nearest_distance = candidate_distance
		var speed := enemy_speed
		dot["pos"] = _move_toward(position, _dot_pos(nearest), speed * delta)


func _move_toward(from: Vector2, to: Vector2, max_step: float) -> Vector2:
	var offset := to - from
	var distance := offset.length()
	if distance <= max_step or distance <= 0.0001:
		return to
	return from + offset / distance * max_step


func _supply_config() -> Dictionary:
	var value: Variant = WorldState.config.get("supply", {})
	if value is Dictionary:
		return value
	return {}


func _supply_max() -> float:
	return float(_supply_config().get("max", 100.0))


func _supply_low() -> float:
	return float(_supply_config().get("low_threshold", 30.0))


func _update_supply(delta: float) -> void:
	var config := _supply_config()
	var max_supply := float(config.get("max", 100.0))
	var drain := float(config.get("drain_per_second", 12.0))
	var recover := float(config.get("recover_per_second", 8.0))
	var low_threshold := float(config.get("low_threshold", 30.0))
	for dot in WorldState.dots:
		var encircled := _is_encircled(dot)
		dot["encircled"] = encircled
		if str(dot.get("faction", "")) != "player":
			continue
		var supply := float(dot.get("supply", max_supply))
		if encircled:
			supply = maxf(supply - drain * delta, 0.0)
		else:
			supply = minf(supply + recover * delta, max_supply)
		dot["supply"] = supply
		if supply <= low_threshold:
			dot["supply_status"] = "shortage"
		elif encircled:
			dot["supply_status"] = "cut"
		else:
			dot["supply_status"] = "normal"


func _is_encircled(dot: Dictionary) -> bool:
	if _frontline_points.size() < 2:
		return false
	var margin := float(WorldState.config.get("encirclement_margin", 0.02))
	var position := _dot_pos(dot)
	var front_x := _front_x_at(position.y)
	if str(dot.get("faction", "")) == "player":
		return position.x > front_x + margin
	return position.x < front_x - margin


func _check_collisions() -> void:
	var radius := float(WorldState.config.get("collision_radius", 0.022))
	for player_dot in WorldState.dots:
		if str(player_dot.get("faction", "")) != "player":
			continue
		for enemy_dot in WorldState.dots:
			if str(enemy_dot.get("faction", "")) != "enemy":
				continue
			if _dot_pos(player_dot).distance_to(_dot_pos(enemy_dot)) <= radius:
				_transitioning = true
				var contact_position := _dot_pos(player_dot).lerp(_dot_pos(enemy_dot), 0.5)
				var biome := WorldState.biome_at(contact_position)
				WorldState.begin_engagement(str(player_dot.get("id", "")), str(enemy_dot.get("id", "")), biome)
				GameSettings.play_start()
				get_tree().change_scene_to_file(BATTLE_SCENE)
				return


func _check_game_over() -> void:
	var player_count := 0
	var enemy_count := 0
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) == "player":
			player_count += 1
		else:
			enemy_count += 1
	if player_count > 0 and enemy_count > 0:
		return
	_game_over = true
	restart_button.visible = true
	result_label.visible = true
	if player_count == 0:
		result_label.text = GameSettings.t("macro.defeat")
		result_label.modulate = Color(1.0, 0.45, 0.4)
	else:
		result_label.text = GameSettings.t("macro.victory")
		result_label.modulate = Color(1.0, 0.9, 0.35)


func _update_hud() -> void:
	var player_count := 0
	var enemy_count := 0
	var cut := 0
	var shortage := 0
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) == "player":
			player_count += 1
			var status := str(dot.get("supply_status", "normal"))
			if bool(dot.get("encircled", false)):
				cut += 1
			if status == "shortage":
				shortage += 1
		else:
			enemy_count += 1
	status_label.text = GameSettings.t("macro.status") % [player_count, enemy_count, cut, shortage]


func _draw_map() -> void:
	if map_canvas == null:
		return
	var size := map_canvas.size

	for circle_value in WorldState.biome_circles():
		if not (circle_value is Dictionary):
			continue
		var circle: Dictionary = circle_value
		var center_data: Array = circle.get("center", [0.5, 0.5])
		var radius_data: Array = circle.get("radius", [0.1, 0.1])
		var center := Vector2(float(center_data[0]) * size.x, float(center_data[1]) * size.y)
		var radius_x := float(radius_data[0]) * size.x
		var radius_y := float(radius_data[1]) * size.y
		var points := PackedVector2Array()
		for i in range(40):
			var angle := TAU * float(i) / 40.0
			points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
		map_canvas.draw_colored_polygon(points, _biome_color(str(circle.get("map", ""))))

	for label_value in WorldState.biome_labels():
		if not (label_value is Dictionary):
			continue
		var label_data: Dictionary = label_value
		var position_data: Array = label_data.get("pos", [0.5, 0.5])
		var label_position := Vector2(float(position_data[0]) * size.x, float(position_data[1]) * size.y)
		var label_text := GameSettings.t("map." + str(label_data.get("map", "grassland")))
		map_canvas.draw_string(
			ui_font, label_position - Vector2(22.0, 0.0), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.0, 0.0, 0.0, 0.75)
		)
		map_canvas.draw_string(
			ui_font, label_position - Vector2(21.0, -1.0), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 1.0, 1.0, 0.9)
		)

	if _frontline_points.size() >= 2:
		var border_screen := PackedVector2Array()
		for point in _frontline_points:
			border_screen.append(_to_canvas(point, size))
		var left_polygon := PackedVector2Array()
		left_polygon.append(Vector2.ZERO)
		left_polygon.append_array(border_screen)
		left_polygon.append(Vector2(0.0, size.y))
		var right_polygon := PackedVector2Array()
		right_polygon.append(Vector2(size.x, 0.0))
		right_polygon.append_array(border_screen)
		right_polygon.append(Vector2(size.x, size.y))
		map_canvas.draw_colored_polygon(left_polygon, Color(0.12, 0.3, 0.75, 0.08))
		map_canvas.draw_colored_polygon(right_polygon, Color(0.75, 0.2, 0.15, 0.08))
		map_canvas.draw_polyline(border_screen, Color(0.0, 0.0, 0.0, 0.5), 8.0)
		map_canvas.draw_polyline(border_screen, Color(0.02, 0.02, 0.02, 0.95), 3.5)

	for faction in WorldState.bases:
		var base_value: Variant = WorldState.bases[faction]
		if not (base_value is Vector2):
			continue
		var center := _to_canvas(base_value, size)
		var color := Color(0.3, 0.65, 1.0) if str(faction) == "player" else Color(1.0, 0.4, 0.35)
		map_canvas.draw_circle(center, 26.0, Color(color.r, color.g, color.b, 0.14))
		var rect := Rect2(center - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
		map_canvas.draw_rect(rect, color)
		map_canvas.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.6), false, 2.0)

	for dot in WorldState.dots:
		var center := _to_canvas(_dot_pos(dot), size)
		var faction := str(dot.get("faction", ""))
		var color := Color(0.25, 0.68, 1.0) if faction == "player" else Color(1.0, 0.3, 0.28)
		var radius := 9.0 + float(dot.get("strength", 1)) * 1.5
		map_canvas.draw_circle(center, radius, color)
		map_canvas.draw_arc(center, radius + 2.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.6), 2.0)
		map_canvas.draw_circle(center, radius * 0.28, Color(0.98, 0.98, 0.95, 0.9))
		if bool(dot.get("encircled", false)):
			map_canvas.draw_arc(center, radius + 10.0, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.95), 3.0)
		if faction == "player":
			var max_supply := maxf(_supply_max(), 1.0)
			var supply := clampf(float(dot.get("supply", max_supply)), 0.0, max_supply)
			var supply_ratio := supply / max_supply
			var low_ratio := _supply_low() / max_supply
			var bar_width := 24.0
			var bar_position := center + Vector2(-bar_width * 0.5, -radius - 9.0)
			map_canvas.draw_rect(Rect2(bar_position, Vector2(bar_width, 3.0)), Color(0.0, 0.0, 0.0, 0.55))
			var bar_color := Color(0.35, 0.9, 0.4) if supply_ratio > low_ratio else Color(1.0, 0.55, 0.2)
			map_canvas.draw_rect(Rect2(bar_position, Vector2(bar_width * supply_ratio, 3.0)), bar_color)
			var status := str(dot.get("supply_status", "normal"))
			var encircled := bool(dot.get("encircled", false))
			if status != "normal" or encircled:
				var warning_color := Color(1.0, 0.35, 0.2) if status == "shortage" else Color(1.0, 0.65, 0.25)
				map_canvas.draw_arc(center, radius + 5.0, 0.0, TAU, 32, warning_color, 2.0)
				var warning_text := GameSettings.t("macro.supply_cut")
				if status == "shortage":
					warning_text = GameSettings.t("macro.supply_shortage")
					if encircled:
						warning_text = GameSettings.t("macro.supply_cut") + " · " + warning_text
				var text_position := center + Vector2(-24.0, -radius - 14.0)
				map_canvas.draw_string(
					ui_font, text_position + Vector2(1.0, 1.0), warning_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.0, 0.0, 0.8)
				)
				map_canvas.draw_string(
					ui_font, text_position, warning_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, warning_color
				)
		if str(dot.get("id", "")) == selected_dot_id:
			map_canvas.draw_arc(center, radius + 7.0, 0.0, TAU, 40, Color(1.0, 0.9, 0.4), 2.5)
			var target_value: Variant = dot.get("target")
			if target_value is Vector2:
				var target := _to_canvas(target_value, size)
				map_canvas.draw_arc(target, 8.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.4, 0.8), 2.0)


func _to_canvas(normalized: Vector2, size: Vector2) -> Vector2:
	return Vector2(normalized.x * size.x, normalized.y * size.y)


func _biome_color(map_id: String) -> Color:
	match map_id:
		"desert":
			return Color(0.95, 0.72, 0.35, 0.14)
		"mountain":
			return Color(0.65, 0.72, 0.85, 0.16)
		_:
			return Color(0.35, 0.85, 0.5, 0.1)


func _handle_click(screen_position: Vector2) -> void:
	var rect := map_canvas.get_global_rect()
	if not rect.has_point(screen_position):
		return
	var normalized := Vector2(
		(screen_position.x - rect.position.x) / maxf(rect.size.x, 1.0),
		(screen_position.y - rect.position.y) / maxf(rect.size.y, 1.0)
	)
	var best_id := ""
	var best_distance := 22.0
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) != "player":
			continue
		var center := rect.position + _to_canvas(_dot_pos(dot), rect.size)
		var distance := screen_position.distance_to(center)
		if distance < best_distance:
			best_id = str(dot.get("id", ""))
			best_distance = distance
	if not best_id.is_empty():
		selected_dot_id = best_id
		GameSettings.play_click()
	elif not selected_dot_id.is_empty():
		var dot := WorldState.get_dot(selected_dot_id)
		if not dot.is_empty():
			dot["target"] = Vector2(clampf(normalized.x, 0.03, 0.97), clampf(normalized.y, 0.06, 0.94))
			GameSettings.play_click()
	map_canvas.queue_redraw()
	_update_hud()


func _on_map_gui_input(event: InputEvent) -> void:
	if _transitioning or _game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event: InputEventMouseButton = event
		var screen_position := map_canvas.get_global_rect().position + mouse_event.position
		_handle_click(screen_position)
		map_canvas.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file(MENU_SCENE)


func _show_toast(text: String, color: Color) -> void:
	result_label.text = text
	result_label.modulate = color
	result_label.visible = true
	_toast_timer = 4.0


func _on_menu_pressed() -> void:
	GameSettings.play_click()
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_restart_pressed() -> void:
	GameSettings.play_start()
	WorldState.start_new_game()
	get_tree().reload_current_scene()
