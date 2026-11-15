extends Control
## 宏观战略层：世界地图、据点移动、补给线与微观战斗入口。

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
var _supply_timer: float = 0.0
var _toast_timer: float = 0.0
var _transitioning: bool = false
var _game_over: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	WorldState.ensure_initialized()
	_build_ui()
	_refresh_supply()
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
	_supply_timer -= delta
	if _supply_timer <= 0.0:
		_supply_timer = 0.25
		_refresh_supply()
		_update_hud()
	_move_dots(delta)
	_check_collisions()
	if _transitioning:
		return
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and not _game_over:
			result_label.visible = false
	_check_game_over()
	map_canvas.queue_redraw()


func _refresh_supply() -> void:
	var link_range := float(WorldState.config.get("link_range", 0.2))
	var interdiction := float(WorldState.config.get("interdiction_radius", 0.03))
	for dot in WorldState.dots:
		dot["supplied"] = false
		dot["supply_source"] = ""
	for faction in ["player", "enemy"]:
		var base_value: Variant = WorldState.bases.get(faction)
		if not (base_value is Vector2):
			continue
		var base_position: Vector2 = base_value
		var frontier: Array[Dictionary] = []
		for dot in WorldState.dots:
			if str(dot.get("faction", "")) != faction:
				continue
			var dot_position := _dot_pos(dot)
			if base_position.distance_to(dot_position) > link_range:
				continue
			if _link_blocked(base_position, dot_position, faction, interdiction):
				continue
			dot["supplied"] = true
			dot["supply_source"] = "base"
			frontier.append(dot)
		var index := 0
		while index < frontier.size():
			var supplier: Dictionary = frontier[index]
			index += 1
			var supplier_position := _dot_pos(supplier)
			for dot in WorldState.dots:
				if str(dot.get("faction", "")) != faction or bool(dot.get("supplied", false)):
					continue
				var dot_position := _dot_pos(dot)
				if supplier_position.distance_to(dot_position) > link_range:
					continue
				if _link_blocked(supplier_position, dot_position, faction, interdiction):
					continue
				dot["supplied"] = true
				dot["supply_source"] = str(supplier.get("id", ""))
				frontier.append(dot)


func _link_blocked(a: Vector2, b: Vector2, faction: String, radius: float) -> bool:
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) == faction:
			continue
		if _segment_distance(_dot_pos(dot), a, b) <= radius:
			return true
	return false


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _dot_pos(dot: Dictionary) -> Vector2:
	var value: Variant = dot.get("pos", Vector2(0.5, 0.5))
	if value is Vector2:
		return value
	return Vector2(0.5, 0.5)


func _move_dots(delta: float) -> void:
	var player_speed := float(WorldState.config.get("player_speed", 0.05))
	var enemy_speed := float(WorldState.config.get("enemy_speed", 0.03))
	var out_mult := float(WorldState.config.get("out_of_supply_speed", 0.45))

	for dot in WorldState.dots:
		if str(dot.get("faction", "")) != "player":
			continue
		var target_value: Variant = dot.get("target")
		if not (target_value is Vector2):
			continue
		var position := _dot_pos(dot)
		var target: Vector2 = target_value
		var speed := player_speed * (1.0 if bool(dot.get("supplied", true)) else out_mult)
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
		var speed := enemy_speed * (1.0 if bool(dot.get("supplied", true)) else out_mult)
		dot["pos"] = _move_toward(position, _dot_pos(nearest), speed * delta)


func _move_toward(from: Vector2, to: Vector2, max_step: float) -> Vector2:
	var offset := to - from
	var distance := offset.length()
	if distance <= max_step or distance <= 0.0001:
		return to
	return from + offset / distance * max_step


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
	var supplied := 0
	var cut := 0
	for dot in WorldState.dots:
		if str(dot.get("faction", "")) == "player":
			player_count += 1
			if bool(dot.get("supplied", false)):
				supplied += 1
			else:
				cut += 1
		else:
			enemy_count += 1
	status_label.text = GameSettings.t("macro.status") % [player_count, enemy_count, supplied, cut]


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

	for dot in WorldState.dots:
		if not bool(dot.get("supplied", false)):
			continue
		var faction := str(dot.get("faction", ""))
		var color := Color(0.35, 0.78, 1.0, 0.5) if faction == "player" else Color(1.0, 0.45, 0.3, 0.45)
		var to := _to_canvas(_dot_pos(dot), size)
		var from := Vector2.ZERO
		var source_id := str(dot.get("supply_source", ""))
		if source_id == "base" or source_id.is_empty():
			var base_value: Variant = WorldState.bases.get(faction)
			if not (base_value is Vector2):
				continue
			from = _to_canvas(base_value, size)
		else:
			var source := WorldState.get_dot(source_id)
			if source.is_empty():
				continue
			from = _to_canvas(_dot_pos(source), size)
		map_canvas.draw_line(from, to, color, 3.0)

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
		var supply_color := Color(0.45, 1.0, 0.5, 0.95) if bool(dot.get("supplied", false)) else Color(1.0, 0.2, 0.15, 0.95)
		map_canvas.draw_circle(center, radius * 0.3, supply_color)
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
