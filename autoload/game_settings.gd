extends Node
## 全局设置：语言、声音与地图选择；自动持久化到 user://settings.cfg。

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const CLICK_SOUND_PATH := "res://assets/audio/click.wav"
const START_SOUND_PATH := "res://assets/audio/start.wav"

const TEXTS := {
	"zh": {
		"menu.subtitle": "宏观世界地图 · 微观战术战斗",
		"menu.language": "语言",
		"menu.sound": "声音",
		"menu.sound_on": "开启",
		"menu.map": "地图",
		"menu.start": "开始游戏",
		"menu.quit": "退出游戏",
		"map.random": "随机",
		"battle.instructions": "左键选兵/划线移动 · Ctrl+左键拖拽防御线 · 右键移动 · C 冲锋 · T 同类\nCtrl+1~9 编队 · 1~9 选队 · 滚轮缩放 · 中键平移 · R 重开",
		"battle.counter": "克制：长矛兵反骑，对轻骑兵伤害 ×2",
		"battle.status": "我方 %d  ·  敌方 %d  ·  已选 %d",
		"battle.map": "地图：%s",
		"battle.victory": "胜利！",
		"battle.defeat": "战败",
		"battle.return_hint": "按 Enter 返回世界地图",
		"macro.title": "世界地图",
		"macro.instructions": "左键选择己方圆点，再点击地图下令移动；与敌方圆点接触即进入微观战斗",
		"macro.status": "我方据点 %d  ·  敌方据点 %d  ·  补给 %d / 断线 %d",
		"macro.menu": "返回主菜单",
		"macro.restart": "重新开始",
		"macro.victory": "你已消灭所有敌军",
		"macro.defeat": "我方部队已全部被消灭",
		"macro.last_win": "上一战：胜利",
		"macro.last_loss": "上一战：失败",
	},
	"en": {
		"menu.subtitle": "Macro world map · Tactical micro battles",
		"menu.language": "Language",
		"menu.sound": "Sound",
		"menu.sound_on": "On",
		"menu.map": "Map",
		"menu.start": "Start Game",
		"menu.quit": "Quit",
		"map.random": "Random",
		"battle.instructions": "LMB select / draw move · Ctrl+LMB drag: defense line · RMB move · C charge · T same type\nCtrl+1~9 group · 1~9 select group · Wheel zoom · MMB pan · R restart",
		"battle.counter": "Counter: Spearmen deal ×2 damage to Light Cavalry",
		"battle.status": "Units %d  ·  Enemy %d  ·  Selected %d",
		"battle.map": "Map: %s",
		"battle.victory": "Victory!",
		"battle.defeat": "Defeat",
		"battle.return_hint": "Press Enter to return to the world map",
		"macro.title": "World Map",
		"macro.instructions": "Click a friendly dot, then click the map to move. Contact with an enemy dot starts a tactical battle",
		"macro.status": "Friendly %d  ·  Enemy %d  ·  Supply %d / Cut %d",
		"macro.menu": "Main Menu",
		"macro.restart": "Restart",
		"macro.victory": "All enemy forces destroyed",
		"macro.defeat": "All friendly forces destroyed",
		"macro.last_win": "Last battle: Victory",
		"macro.last_loss": "Last battle: Defeat",
	},
}

var language: String = "zh"
var sound_enabled: bool = true
var volume: float = 0.8
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


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	language = str(config.get_value("ui", "language", language))
	if language != "zh" and language != "en":
		language = "zh"
	sound_enabled = bool(config.get_value("audio", "enabled", sound_enabled))
	volume = clampf(float(config.get_value("audio", "volume", volume)), 0.0, 1.0)
	selected_map = str(config.get_value("game", "map", selected_map))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "language", language)
	config.set_value("audio", "enabled", sound_enabled)
	config.set_value("audio", "volume", volume)
	config.set_value("game", "map", selected_map)
	config.save(SETTINGS_PATH)
