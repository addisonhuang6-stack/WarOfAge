extends Node
## 全局设置：语言、声音与地图选择；自动持久化到 user://settings.cfg。

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const CLICK_SOUND_PATH := "res://assets/audio/click.wav"
const START_SOUND_PATH := "res://assets/audio/start.wav"
const GAME_SPEEDS := [0.25, 0.5, 1.0, 2.0, 3.0]

const TEXTS := {
	"zh": {
		"menu.subtitle": "宏观世界地图 · 微观战术战斗",
		"menu.language": "语言",
		"menu.sound": "声音",
		"menu.sound_on": "开启",
		"menu.ai": "人机",
		"menu.ai_on": "开启",
		"menu.speed": "游戏速度",
		"hud.pause": "暂停",
		"hud.speed": "速度 %s",
		"hud.speed_hint": "P 暂停 · [ ] 调速 · WASD 平移",
		"macro.selected": "已选",
		"macro.supply": "补给",
		"menu.map": "地图",
		"menu.start": "开始游戏",
		"menu.quit": "退出游戏",
		"map.random": "随机",
		"map.desert": "沙漠",
		"map.grassland": "草原",
		"map.mountain": "高山",
		"battle.instructions": "左键选兵/划线移动 · Ctrl+左键拖拽防御线 · 右键移动 · C 冲锋 · T 同类\nCtrl+1~9 编队 · 1~9 选队 · 滚轮缩放 · 中键平移 · R 重开",
		"battle.counter": "克制：长矛兵反骑，对轻骑兵伤害 ×2",
		"battle.status": "我方 %d  ·  敌方 %d  ·  已选 %d%s",
		"unit.spearman": "长矛兵",
		"unit.light_cavalry": "轻骑兵",
		"battle.map": "地图：%s",
		"battle.victory": "胜利！",
		"battle.defeat": "战败",
		"battle.return_hint": "按 Enter 返回世界地图",
		"macro.title": "世界地图",
		"macro.instructions": "左键选择军队下令；边境线由最前线军队接触点决定；越过战线会被包围断补；接敌地形由接战位置决定",
		"macro.status": "我方军队 %d  ·  敌方军队 %d  ·  补给中断 %d  ·  短缺 %d",
		"macro.supply_cut": "补给中断",
		"macro.supply_shortage": "短缺",
		"macro.menu": "返回主菜单",
		"macro.restart": "重新开始",
		"macro.victory": "你已消灭所有敌军",
		"macro.defeat": "我方军队已全部被消灭",
		"macro.last_win": "上一战：胜利",
		"macro.last_loss": "上一战：失败",
	},
	"en": {
		"menu.subtitle": "Macro world map · Tactical micro battles",
		"menu.language": "Language",
		"menu.sound": "Sound",
		"menu.sound_on": "On",
		"menu.ai": "AI",
		"menu.ai_on": "On",
		"menu.speed": "Game Speed",
		"hud.pause": "Paused",
		"hud.speed": "Speed %s",
		"hud.speed_hint": "P pause · [ ] speed · WASD pan",
		"macro.selected": "Selected",
		"macro.supply": "Supply",
		"menu.map": "Map",
		"menu.start": "Start Game",
		"menu.quit": "Quit",
		"map.random": "Random",
		"map.desert": "Desert",
		"map.grassland": "Grassland",
		"map.mountain": "Mountains",
		"battle.instructions": "LMB select / draw move · Ctrl+LMB drag: defense line · RMB move · C charge · T same type\nCtrl+1~9 group · 1~9 select group · Wheel zoom · MMB pan · R restart",
		"battle.counter": "Counter: Spearmen deal ×2 damage to Light Cavalry",
		"battle.status": "Units %d  ·  Enemy %d  ·  Selected %d%s",
		"unit.spearman": "Spearmen",
		"unit.light_cavalry": "Light Cavalry",
		"battle.map": "Map: %s",
		"battle.victory": "Victory!",
		"battle.defeat": "Defeat",
		"battle.return_hint": "Press Enter to return to the world map",
		"macro.title": "World Map",
		"macro.instructions": "Click a friendly army to move; the frontline follows the contact points of front armies; crossing it means encirclement; terrain comes from the contact location",
		"macro.status": "Friendly armies %d  ·  Enemy armies %d  ·  Cut off %d  ·  Shortage %d",
		"macro.supply_cut": "Supply cut",
		"macro.supply_shortage": "Shortage",
		"macro.menu": "Main Menu",
		"macro.restart": "Restart",
		"macro.victory": "All enemy forces destroyed",
		"macro.defeat": "All friendly armies destroyed",
		"macro.last_win": "Last battle: Victory",
		"macro.last_loss": "Last battle: Defeat",
	},
}

var language: String = "zh"
var sound_enabled: bool = true
var volume: float = 0.8
var ai_enabled: bool = true
var game_speed: float = 1.0
var paused: bool = false
var selected_map: String = "random"

var _audio_player: AudioStreamPlayer
var _click_stream: AudioStream
var _start_stream: AudioStream


func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_click_stream = load(CLICK_SOUND_PATH)
	_start_stream = load(START_SOUND_PATH)
	_load_settings()
	_apply_audio()
	_apply_game_speed()


func t(key: String) -> String:
	var table: Dictionary = TEXTS.get(language, TEXTS["zh"])
	return str(table.get(key, key))


func set_language(value: String) -> void:
	if value == language:
		return
	language = value
	_save_settings()
	changed.emit()


func set_sound_enabled(value: bool) -> void:
	if value == sound_enabled:
		return
	sound_enabled = value
	_apply_audio()
	_save_settings()
	changed.emit()


func set_volume(value: float, persist: bool = true) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, volume):
		if persist:
			_save_settings()
		return
	volume = clamped
	_apply_audio()
	if persist:
		_save_settings()
	changed.emit()


func set_map(value: String) -> void:
	if value == selected_map:
		return
	selected_map = value
	_save_settings()
	changed.emit()


func set_ai_enabled(value: bool) -> void:
	if value == ai_enabled:
		return
	ai_enabled = value
	_save_settings()
	changed.emit()


func set_game_speed(value: float) -> void:
	var clamped := clampf(value, 0.25, 3.0)
	if is_equal_approx(clamped, game_speed):
		_apply_game_speed()
		return
	game_speed = clamped
	_apply_game_speed()
	_save_settings()
	changed.emit()


func toggle_pause() -> void:
	set_paused(not paused)


func set_paused(value: bool) -> void:
	if value == paused:
		return
	paused = value
	_apply_game_speed()
	changed.emit()


func adjust_game_speed(direction: int) -> void:
	var index := 0
	for i in range(GAME_SPEEDS.size()):
		if is_equal_approx(float(GAME_SPEEDS[i]), game_speed):
			index = i
			break
	index = clampi(index + direction, 0, GAME_SPEEDS.size() - 1)
	set_game_speed(float(GAME_SPEEDS[index]))


func play_click() -> void:
	_play(_click_stream)


func play_start() -> void:
	_play(_start_stream)


func _play(stream: AudioStream) -> void:
	if not sound_enabled or stream == null or _audio_player == null:
		return
	_audio_player.stream = stream
	_audio_player.play()


func _apply_audio() -> void:
	AudioServer.set_bus_mute(0, not sound_enabled)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func _apply_game_speed() -> void:
	Engine.time_scale = 0.0 if paused else game_speed


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	language = str(config.get_value("ui", "language", language))
	if language != "zh" and language != "en":
		language = "zh"
	sound_enabled = bool(config.get_value("audio", "enabled", sound_enabled))
	volume = clampf(float(config.get_value("audio", "volume", volume)), 0.0, 1.0)
	ai_enabled = bool(config.get_value("game", "ai_enabled", ai_enabled))
	game_speed = clampf(float(config.get_value("game", "speed", game_speed)), 0.25, 3.0)
	selected_map = str(config.get_value("game", "map", selected_map))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "language", language)
	config.set_value("audio", "enabled", sound_enabled)
	config.set_value("audio", "volume", volume)
	config.set_value("game", "ai_enabled", ai_enabled)
	config.set_value("game", "speed", game_speed)
	config.set_value("game", "map", selected_map)
	config.save(SETTINGS_PATH)
