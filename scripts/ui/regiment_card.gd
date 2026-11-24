class_name RegimentCard
extends Control
## Total War 式单位卡；图标使用 We March As One 风格的极简色块与方向标记。

signal clicked(regiment_id: String, additive: bool)

var regiment: Regiment
var ui_font: Font
var team_color: Color = Color(0.25, 0.68, 1.0)
var display_name: String = ""
var alive_count: int = 0
var hp_fraction: float = 1.0
var is_card_selected: bool = false
var defeated: bool = false
var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(126.0, 82.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


func setup(unit_regiment: Regiment, font: Font, color: Color, name: String) -> void:
	regiment = unit_regiment
	ui_font = font
	team_color = color
	display_name = name
	queue_redraw()


func set_status(count: int, health: float, selected: bool) -> void:
	alive_count = count
	hp_fraction = clampf(health, 0.0, 1.0)
	is_card_selected = selected
	defeated = count <= 0
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if regiment != null:
			clicked.emit(regiment.id, event.shift_pressed)
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := Color(0.055, 0.07, 0.085, 0.96)
	if _hovered:
		background = Color(0.085, 0.105, 0.125, 0.98)
	draw_rect(rect, background, true)
	var border_color := Color(1.0, 0.85, 0.3) if is_card_selected else Color(team_color.r, team_color.g, team_color.b, 0.85)
	draw_rect(rect, border_color, false, 2.0)
	draw_rect(Rect2(0.0, 0.0, size.x, 3.0), team_color)

	var icon_center := Vector2(22.0, 26.0)
	if regiment != null and regiment.icon_shape == "triangle":
		draw_colored_polygon(PackedVector2Array([
			icon_center + Vector2(0.0, -12.0),
			icon_center + Vector2(-10.0, 8.0),
			icon_center + Vector2(10.0, 8.0),
		]), Color(0.02, 0.03, 0.04, 1.0))
		draw_colored_polygon(PackedVector2Array([
			icon_center + Vector2(0.0, -9.0),
			icon_center + Vector2(-7.5, 6.0),
			icon_center + Vector2(7.5, 6.0),
		]), team_color)
		draw_colored_polygon(PackedVector2Array([
			icon_center + Vector2(0.0, -4.0),
			icon_center + Vector2(-3.0, 3.0),
			icon_center + Vector2(3.0, 3.0),
		]), Color(0.97, 0.97, 0.95, 1.0))
	else:
		draw_circle(icon_center, 11.0, Color(0.02, 0.03, 0.04, 1.0))
		draw_circle(icon_center, 9.0, team_color)
		draw_colored_polygon(PackedVector2Array([
			icon_center + Vector2(0.0, -5.0),
			icon_center + Vector2(-4.5, 4.0),
			icon_center + Vector2(4.5, 4.0),
		]), Color(0.97, 0.97, 0.95, 1.0))

	if ui_font != null:
		draw_string(ui_font, Vector2(39.0, 24.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, 78.0, 13, Color(0.92, 0.94, 0.96))
		var count_text := "%d/%d" % [alive_count, regiment.unit_ids.size() if regiment != null else 0]
		draw_string(ui_font, Vector2(39.0, 43.0), count_text, HORIZONTAL_ALIGNMENT_LEFT, 78.0, 12, Color(0.65, 0.72, 0.78))

	var bar_rect := Rect2(Vector2(8.0, 64.0), Vector2(110.0, 6.0))
	draw_rect(bar_rect, Color(0.02, 0.03, 0.04, 1.0), true)
	var hp_color := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - hp_fraction)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * hp_fraction, bar_rect.size.y)), hp_color, true)

	if defeated:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.55), true)
		if ui_font != null:
			draw_string(ui_font, Vector2(46.0, 40.0), "X", HORIZONTAL_ALIGNMENT_CENTER, 34.0, 22, Color(0.9, 0.3, 0.25))
