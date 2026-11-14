class_name Command
extends Resource
## 玩家或系统发出的一条指令（命令模式）。
##
## 所有玩家操作都必须封装为 Command，按 tick 顺序在确定性模拟中执行；
## 在 Lockstep 同步中，Command 会被序列化后通过 ENet 传输。

## 指令类型，例如 &"move"、&"attack"、&"formation"。
@export var type: StringName = &""

## 发起指令的玩家编号。
@export var player_id: int = -1

## 参与指令的单位实例 ID 列表。
@export var unit_ids: Array[int] = []

## 目标位置（本工程为 3D，因此使用 Vector3）。
@export var target_position: Vector3 = Vector3.ZERO

## 本次移动令的完整路径（划线的所有路点，最后一个点即目标位置）。
## 一次移动令只产生一条 Command；新的移动令会整体覆盖旧路径。
@export var waypoints: Array[Vector3] = []

## 指令生效的模拟 tick 序号。
@export var tick: int = 0


## 序列化为字典，供 JSON 编码与网络传输使用。
func to_dict() -> Dictionary:
	var waypoint_data: Array = []
	for point in waypoints:
		waypoint_data.append([point.x, point.y, point.z])
	return {
		"type": String(type),
		"player_id": player_id,
		"unit_ids": unit_ids,
		"target_position": [
			target_position.x,
			target_position.y,
			target_position.z,
		],
		"waypoints": waypoint_data,
		"tick": tick
	}


## 从字典（例如网络接收的 JSON）恢复指令对象。
static func from_dict(data: Dictionary) -> Command:
	var command := Command.new()
	command.type = StringName(data.get("type", ""))
	command.player_id = int(data.get("player_id", -1))

	var raw_unit_ids: Variant = data.get("unit_ids", [])
	if raw_unit_ids is Array:
		var id_array: Array = raw_unit_ids
		command.unit_ids.assign(id_array)

	var raw_position: Variant = data.get("target_position", [])
	if raw_position is Array:
		var pos_array: Array = raw_position
		if pos_array.size() >= 3:
			command.target_position = Vector3(
				float(pos_array[0]),
				float(pos_array[1]),
				float(pos_array[2])
			)

	var raw_waypoints: Variant = data.get("waypoints", [])
	if raw_waypoints is Array:
		var waypoint_array: Array = raw_waypoints
		for raw_point in waypoint_array:
			if raw_point is Array and raw_point.size() >= 3:
				command.waypoints.append(Vector3(
					float(raw_point[0]),
					float(raw_point[1]),
					float(raw_point[2])
				))

	command.tick = int(data.get("tick", 0))
	return command
