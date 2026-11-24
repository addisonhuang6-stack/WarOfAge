extends Node
## 全局设置：语言、声音与地图选择；自动持久化到 user://settings.cfg。

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const CLICK_SOUND_PATH := "res://assets/audio/click.wav"
const START_SOUND_PATH := "res://assets/audio/start.wav"
const GAME_SPEEDS := [0.25, 0.5, 1.0, 2.0, 3.0]
const SFX_SAMPLE_RATE := 22050
const SFX_PLAYER_COUNT := 4

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

var _audio_players: Array[AudioStreamPlayer] = []
var _audio_cursor: int = 0
var _click_stream: AudioStream
var _start_stream: AudioStream
var _move_confirm_stream: AudioStreamWAV
var _melee_hit_stream: AudioStreamWAV
var _unit_death_stream: AudioStreamWAV
var _charge_impact_stream: AudioStreamWAV
var _audio_stopped: bool = false


func _ready() -> void:
	for _index in range(SFX_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_audio_players.append(player)
	_click_stream = load(CLICK_SOUND_PATH)
	_start_stream = load(START_SOUND_PATH)
	_build_placeholder_sounds()
	_load_settings()
	_apply_audio()
	_apply_game_speed()
	get_tree().root.tree_exiting.connect(_stop_all_audio)


func _exit_tree() -> void:
	_stop_all_audio()


func _stop_all_audio() -> void:
	if _audio_stopped:
		return
	_audio_stopped = true
	for player in _audio_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_audio_players.clear()
	_click_stream = null
	_start_stream = null
	_move_confirm_stream = null
	_melee_hit_stream = null
	_unit_death_stream = null
	_charge_impact_stream = null


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


func play_move_confirm(pitch_scale: float = 1.0) -> void:
	_play(_move_confirm_stream, pitch_scale * randf_range(0.98, 1.04), -3.0)


func play_melee_hit(is_counter: bool = false) -> void:
	var pitch := randf_range(0.9, 1.06)
	if is_counter:
		pitch *= 1.08
	_play(_melee_hit_stream, pitch, -1.5)


func play_unit_death() -> void:
	_play(_unit_death_stream, randf_range(0.92, 1.02), -3.0)


func play_charge_impact() -> void:
	_play(_charge_impact_stream, randf_range(0.94, 1.02), 0.5)


func _play(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sound_enabled or stream == null or _audio_players.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		return
	var player: AudioStreamPlayer = null
	for candidate in _audio_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _audio_players[_audio_cursor]
		_audio_cursor = (_audio_cursor + 1) % _audio_players.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func _build_placeholder_sounds() -> void:
	# 所有战斗占位音效均由简单波形实时合成，不依赖外部版权素材。
	_move_confirm_stream = _make_placeholder_tone(0.085, 320.0, 540.0, 0.2, 0.02, 3.0)
	_melee_hit_stream = _make_placeholder_tone(0.105, 165.0, 68.0, 0.5, 0.48, 6.0)
	_unit_death_stream = _make_placeholder_tone(0.28, 220.0, 72.0, 0.38, 0.18, 2.2)
	_charge_impact_stream = _make_placeholder_tone(0.22, 92.0, 38.0, 0.68, 0.62, 3.4)


func _make_placeholder_tone(
	duration: float,
	start_frequency: float,
	end_frequency: float,
	amplitude: float,
	noise_amount: float,
	decay_power: float
) -> AudioStreamWAV:
	var sample_count := maxi(int(duration * SFX_SAMPLE_RATE), 1)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(start_frequency * 1009.0 + end_frequency * 917.0 + duration * 100000.0)
	var phase := 0.0
	var attack_samples := maxi(int(0.004 * SFX_SAMPLE_RATE), 1)
	for i in range(sample_count):
		var progress := float(i) / float(sample_count)
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / float(SFX_SAMPLE_RATE)
		var envelope := pow(maxf(1.0 - progress, 0.0), decay_power)
		if i < attack_samples:
			envelope *= float(i) / float(attack_samples)
		var noise := rng.randf_range(-1.0, 1.0)
		var sample := (sin(phase) * (1.0 - noise_amount * 0.55) + noise * noise_amount) * amplitude * envelope
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SFX_SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


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
