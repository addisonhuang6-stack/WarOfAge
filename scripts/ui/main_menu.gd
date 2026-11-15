extends Control
## 开始菜单：语言、声音、地图选择与开始/退出。

const SPEED_VALUES := [0.5, 1.0, 2.0, 3.0]

var map_generator := MapGenerator.new()
var maps: Array = []
var ui_font: SystemFont
var game_theme: Theme

var subtitle_label: Label
var language_label: Label
var sound_label: Label
var ai_label: Label
var speed_label: Label
var map_label: Label
var start_button: Button
var quit_button: Button
var language_option: OptionButton
var sound_toggle: CheckButton
var ai_toggle: CheckButton
var speed_option: OptionButton
var volume_slider: HSlider
var volume_value_label: Label
var map_option: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSettings.set_paused(false)
	maps = map_generator.load_maps()
	_build_ui()
	_sync_from_settings()
	GameSettings.changed.connect(_sync_from_settings)


func _build_ui() -> void:
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Helvetica"])
	game_theme = Theme.new()
	game_theme.default_font = ui_font
	game_theme.default_font_size = 18
	theme = game_theme

	var background := ColorRect.new()
	background.color = Color(0.055, 0.065, 0.075)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var accent_line := ColorRect.new()
	accent_line.color = Color(0.85, 0.68, 0.3)
	accent_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent_line.offset_bottom = 3.0
	add_child(accent_line)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660.0, 0.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.105, 0.12)
	panel_style.border_color = Color(0.2, 0.24, 0.27)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 38)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = "WAR OF AGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	column.add_child(title)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 17)
	subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.7))
	column.add_child(subtitle_label)

	column.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	column.add_child(grid)

	language_label = Label.new()
	language_label.custom_minimum_size = Vector2(120.0, 0.0)
	grid.add_child(language_label)
	language_option = OptionButton.new()
	language_option.add_item("中文")
	language_option.add_item("English")
	language_option.custom_minimum_size = Vector2(260.0, 38.0)
	language_option.item_selected.connect(_on_language_selected)
	grid.add_child(language_option)

	sound_label = Label.new()
	grid.add_child(sound_label)

	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 12)
	sound_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(sound_row)

	sound_toggle = CheckButton.new()
	sound_toggle.toggled.connect(_on_sound_toggled)
	sound_row.add_child(sound_toggle)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.custom_minimum_size = Vector2(160.0, 0.0)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)
	sound_row.add_child(volume_slider)

	volume_value_label = Label.new()
	volume_value_label.custom_minimum_size = Vector2(52.0, 0.0)
	volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sound_row.add_child(volume_value_label)

	ai_label = Label.new()
	grid.add_child(ai_label)
	ai_toggle = CheckButton.new()
	ai_toggle.toggled.connect(_on_ai_toggled)
	grid.add_child(ai_toggle)

	speed_label = Label.new()
	grid.add_child(speed_label)
	speed_option = OptionButton.new()
	speed_option.add_item("0.5×")
	speed_option.add_item("1×")
	speed_option.add_item("2×")
	speed_option.add_item("3×")
	speed_option.custom_minimum_size = Vector2(260.0, 38.0)
	speed_option.item_selected.connect(_on_speed_selected)
	grid.add_child(speed_option)

	map_label = Label.new()
	grid.add_child(map_label)
	map_option = OptionButton.new()
	map_option.custom_minimum_size = Vector2(260.0, 38.0)
	map_option.item_selected.connect(_on_map_selected)
	grid.add_child(map_option)

	column.add_child(HSeparator.new())

	start_button = Button.new()
	start_button.custom_minimum_size = Vector2(0.0, 56.0)
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.pressed.connect(_on_start_pressed)
	column.add_child(start_button)

	quit_button = Button.new()
	quit_button.custom_minimum_size = Vector2(0.0, 40.0)
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)

	_style_button(start_button, true)
	_style_button(quit_button, false)


func _style_button(button: Button, primary: bool) -> void:
	var base := Color(0.85, 0.66, 0.28) if primary else Color(0.18, 0.21, 0.24)
	var styles := {
		"normal": base,
		"hover": base.lightened(0.12),
		"pressed": base.darkened(0.12),
	}
	for state in styles:
		var box := StyleBoxFlat.new()
		box.bg_color = styles[state]
		box.set_corner_radius_all(7)
		if not primary:
			box.border_color = Color(0.3, 0.34, 0.38)
			box.set_border_width_all(1)
		button.add_theme_stylebox_override(state, box)
	var text_color := Color(0.08, 0.09, 0.1) if primary else Color(0.88, 0.9, 0.92)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)


func _sync_from_settings() -> void:
	subtitle_label.text = GameSettings.t("menu.subtitle")
	language_label.text = GameSettings.t("menu.language")
	sound_label.text = GameSettings.t("menu.sound")
	ai_label.text = GameSettings.t("menu.ai")
	speed_label.text = GameSettings.t("menu.speed")
	map_label.text = GameSettings.t("menu.map")
	sound_toggle.text = GameSettings.t("menu.sound_on")
	ai_toggle.text = GameSettings.t("menu.ai_on")
	start_button.text = GameSettings.t("menu.start")
	quit_button.text = GameSettings.t("menu.quit")
	volume_value_label.text = "%d%%" % int(round(GameSettings.volume * 100.0))
	sound_toggle.set_pressed_no_signal(GameSettings.sound_enabled)
	ai_toggle.set_pressed_no_signal(GameSettings.ai_enabled)
	speed_option.select(_speed_index())
	volume_slider.set_value_no_signal(GameSettings.volume * 100.0)
	language_option.select(0 if GameSettings.language == "zh" else 1)
	_rebuild_map_options()


func _rebuild_map_options() -> void:
	map_option.clear()
	map_option.add_item(GameSettings.t("map.random"))
	var selected_index := 0
	for i in range(maps.size()):
		var map_data: Dictionary = maps[i]
		map_option.add_item(_map_name(map_data))
		if str(map_data.get("id", "")) == GameSettings.selected_map:
			selected_index = i + 1
	map_option.select(selected_index)


func _map_name(map_data: Dictionary) -> String:
	var names: Variant = map_data.get("name", {})
	if names is Dictionary:
		var name_dict: Dictionary = names
		return str(name_dict.get(GameSettings.language, name_dict.get("en", map_data.get("id", ""))))
	return str(map_data.get("id", ""))


func _on_language_selected(index: int) -> void:
	GameSettings.set_language("zh" if index == 0 else "en")
	GameSettings.play_click()


func _on_sound_toggled(enabled: bool) -> void:
	GameSettings.set_sound_enabled(enabled)
	if enabled:
		GameSettings.play_click()


func _on_ai_toggled(enabled: bool) -> void:
	GameSettings.set_ai_enabled(enabled)
	if enabled:
		GameSettings.play_click()


func _on_speed_selected(index: int) -> void:
	GameSettings.set_game_speed(SPEED_VALUES[index])
	GameSettings.play_click()


func _speed_index() -> int:
	for i in range(SPEED_VALUES.size()):
		if is_equal_approx(float(SPEED_VALUES[i]), GameSettings.game_speed):
			return i
	return 1


func _on_volume_changed(value: float) -> void:
	GameSettings.set_volume(value / 100.0, false)
	volume_value_label.text = "%d%%" % int(round(value))


func _on_volume_drag_ended(changed: bool) -> void:
	if not changed:
		return
	GameSettings.set_volume(volume_slider.value / 100.0, true)
	GameSettings.play_click()


func _on_map_selected(index: int) -> void:
	if index <= 0:
		GameSettings.set_map("random")
	else:
		var map_data: Dictionary = maps[index - 1]
		GameSettings.set_map(str(map_data.get("id", "random")))
	GameSettings.play_click()


func _on_start_pressed() -> void:
	GameSettings.play_start()
	WorldState.start_new_game()
	get_tree().change_scene_to_file("res://scenes/macro_map.tscn")


func _on_quit_pressed() -> void:
	GameSettings.play_click()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_on_start_pressed()
