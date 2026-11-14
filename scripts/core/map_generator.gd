class_name MapGenerator
extends RefCounted
## 地图生成：按配置切换地面纹理、环境色并生成装饰物。
## 地图数据来自 data/maps.json，可在开始菜单选择或随机抽取。

const MAPS_PATH := "res://data/maps.json"

var maps: Array = []


func load_maps() -> Array:
	maps.clear()
	var file := FileAccess.open(MAPS_PATH, FileAccess.READ)
	if file == null:
		push_error("MapGenerator: 无法读取 %s" % MAPS_PATH)
		return maps
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("MapGenerator: 地图配置不是有效的 JSON 对象")
		return maps
	var raw_maps: Variant = parsed.get("maps", [])
	if raw_maps is Array:
		maps = raw_maps
	return maps


## 根据选择返回地图配置；preferred_id 为 "random" 时随机抽取。
func pick_map(preferred_id: String) -> Dictionary:
	if maps.is_empty():
		load_maps()
	if maps.is_empty():
		return {}
	if preferred_id.is_empty() or preferred_id == "random":
		return maps[randi_range(0, maps.size() - 1)].duplicate(true)
	for map_data in maps:
		if map_data is Dictionary and str(map_data.get("id", "")) == preferred_id:
			return map_data.duplicate(true)
	return maps[0].duplicate(true)


## 应用地图：替换地面材质并生成装饰物。
func apply(
	map_data: Dictionary,
	ground: MeshInstance3D,
	environment: Environment,
	decor_root: Node3D,
	rng_seed: int = 0,
	avoid_points: Array[Vector3] = []
) -> void:
	if map_data.is_empty() or ground == null:
		return
	var material := ground.material_override as StandardMaterial3D
	if material != null:
		var texture_path := str(map_data.get("ground_texture", ""))
		if not texture_path.is_empty():
			var texture := load(texture_path) as Texture2D
			if texture != null:
				material.albedo_texture = texture
		var tint: Variant = map_data.get("ground_tint", [1.0, 1.0, 1.0])
		if tint is Array and tint.size() >= 3:
			material.albedo_color = Color(float(tint[0]), float(tint[1]), float(tint[2]))

	if environment != null:
		var background: Variant = map_data.get("background_color", [])
		if background is Array and background.size() >= 3:
			environment.background_color = Color(float(background[0]), float(background[1]), float(background[2]))
		var ambient: Variant = map_data.get("ambient_color", [])
		if ambient is Array and ambient.size() >= 3:
			environment.ambient_light_color = Color(float(ambient[0]), float(ambient[1]), float(ambient[2]))

	if decor_root != null:
		_spawn_decor(map_data, decor_root, rng_seed, avoid_points)


func _spawn_decor(map_data: Dictionary, root: Node3D, rng_seed: int, avoid_points: Array[Vector3]) -> void:
	for child in root.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := int(map_data.get("decor_count", 0))
	var kind := str(map_data.get("decor_kind", ""))
	var scale_values: Variant = map_data.get("decor_scale", [1.0, 1.0])
	var min_scale := 1.0
	var max_scale := 1.0
	if scale_values is Array and scale_values.size() >= 2:
		min_scale = float(scale_values[0])
		max_scale = float(scale_values[1])
	for i in range(count):
		var decor := _make_decor(kind, rng)
		if decor == null:
			continue
		decor.position = _random_decor_position(rng, avoid_points)
		var scale_value := rng.randf_range(min_scale, max_scale)
		decor.scale = Vector3(scale_value, scale_value, scale_value)
		decor.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(decor)


func _random_decor_position(rng: RandomNumberGenerator, avoid_points: Array[Vector3]) -> Vector3:
	for attempt in range(8):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(9.0, 12.5)
		var x := clampf(cos(angle) * radius, -13.0, 13.0)
		var z := clampf(sin(angle) * radius * 0.72, -8.2, 8.2)
		var blocked := false
		for point in avoid_points:
			if Vector2(x - point.x, z - point.z).length() < 2.8:
				blocked = true
				break
		if not blocked:
			return Vector3(x, 0.0, z)
	return Vector3(0.0, 0.0, -8.0)


func _make_decor(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	match kind:
		"desert":
			if rng.randf() < 0.6:
				_add_cactus(root, rng)
			else:
				_add_rock(root, rng, Color(0.58, 0.5, 0.4))
		"grassland":
			if rng.randf() < 0.55:
				_add_tree(root, rng)
			else:
				_add_bush(root, rng)
		"mountain":
			if rng.randf() < 0.5:
				_add_rock(root, rng, Color(0.45, 0.46, 0.5))
			else:
				_add_spike(root, rng)
		_:
			return null
	return root


func _add_mesh(root: Node3D, mesh: Mesh, color: Color, position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	instance.material_override = material
	instance.position = position
	root.add_child(instance)
	return instance


func _add_cactus(root: Node3D, rng: RandomNumberGenerator) -> void:
	var green := Color(0.3, 0.5, 0.28)
	var height := rng.randf_range(1.6, 2.6)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.2
	trunk.height = height
	_add_mesh(root, trunk, green, Vector3(0.0, height * 0.5, 0.0))

	var arm := CylinderMesh.new()
	arm.top_radius = 0.1
	arm.bottom_radius = 0.12
	arm.height = height * 0.4
	var arm_instance := _add_mesh(root, arm, green, Vector3(0.28, height * 0.58, 0.0))
	arm_instance.rotation.z = deg_to_rad(-90.0)


func _add_rock(root: Node3D, rng: RandomNumberGenerator, color: Color) -> void:
	var rock := SphereMesh.new()
	rock.radius = rng.randf_range(0.5, 0.9)
	rock.height = rock.radius * 2.0
	var instance := _add_mesh(root, rock, color, Vector3(0.0, rock.radius * 0.45, 0.0))
	instance.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	instance.scale = Vector3(1.0, 0.7, 1.0)


func _add_tree(root: Node3D, rng: RandomNumberGenerator) -> void:
	var trunk_height := rng.randf_range(1.4, 2.2)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = trunk_height
	_add_mesh(root, trunk, Color(0.36, 0.26, 0.18), Vector3(0.0, trunk_height * 0.5, 0.0))

	var canopy := SphereMesh.new()
	canopy.radius = rng.randf_range(0.7, 1.1)
	canopy.height = canopy.radius * 2.0
	_add_mesh(root, canopy, Color(0.2, 0.42, 0.22), Vector3(0.0, trunk_height + canopy.radius * 0.5, 0.0))


func _add_bush(root: Node3D, rng: RandomNumberGenerator) -> void:
	var bush := SphereMesh.new()
	bush.radius = rng.randf_range(0.35, 0.6)
	bush.height = bush.radius * 2.0
	var instance := _add_mesh(root, bush, Color(0.22, 0.38, 0.2), Vector3(0.0, bush.radius * 0.6, 0.0))
	instance.scale = Vector3(1.2, 0.8, 1.2)


func _add_spike(root: Node3D, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(2.2, 4.0)
	var bottom_radius := rng.randf_range(0.7, 1.2)
	var spike := CylinderMesh.new()
	spike.top_radius = 0.02
	spike.bottom_radius = bottom_radius
	spike.height = height
	_add_mesh(root, spike, Color(0.4, 0.42, 0.46), Vector3(0.0, height * 0.5, 0.0))

	var cap := CylinderMesh.new()
	cap.top_radius = 0.02
	cap.bottom_radius = bottom_radius * 0.16
	cap.height = height * 0.18
	_add_mesh(root, cap, Color(0.9, 0.93, 0.97), Vector3(0.0, height * 0.86, 0.0))
