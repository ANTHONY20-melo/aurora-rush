extends Node
## Audio authority: bus routing, adaptive music, and a procedurally
## synthesised SFX library.
##
## The project ships zero binary audio assets. Every sound is generated at
## runtime into an AudioStreamWAV, so the game has real, working audio with
## nothing licensed and nothing to download. Sounds are generated once,
## cached, and played through a pool of players.

const SFX_VOICES := 12
const MUSIC_VOICES := 4
const SAMPLE_RATE := 22050

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

var _sfx_cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music_index: int = 0
var _current_music_id: String = ""
var _current_music_volume_db: float = 0.0
var _ready_for_audio: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_pools()
	_generate_library()
	_ready_for_audio = true


func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, BUS_MASTER)
	_apply_volumes()


func _build_pools() -> void:
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_pool.append(player)
	for i in MUSIC_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_music_players.append(player)


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MASTER),
		linear_to_db(maxf(0.0001, ConfigManager.master_volume())))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MUSIC),
		linear_to_db(maxf(0.0001, ConfigManager.music_volume())))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_SFX),
		linear_to_db(maxf(0.0001, ConfigManager.sfx_volume())))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_UI),
		linear_to_db(maxf(0.0001, ConfigManager.ui_volume())))
	var muted: bool = ConfigManager.get_bool("audio", "muted")
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), muted)


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY and _ready_for_audio:
		pass


# --- SFX --------------------------------------------------------------------

## Play a named sound effect. Categories map to bus volumes:
## ui, player, enemy, boss, environment.
func play_sfx(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _ready_for_audio or sound_id.is_empty():
		return
	var stream: AudioStream = _sfx_cache.get(sound_id)
	if stream == null:
		return
	var player := _claim_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch, 0.1, 4.0)
	player.bus = BUS_UI if sound_id.begins_with("ui_") else BUS_SFX
	player.play()


func _claim_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	# Steal the oldest voice rather than dropping the sound entirely.
	var oldest: AudioStreamPlayer = _sfx_pool[0]
	for player in _sfx_pool:
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest


# --- Music ------------------------------------------------------------------

## Crossfade to a music track. `fade_seconds` of 0 switches instantly.
func play_music(music_id: String, fade_seconds: float = 1.2) -> void:
	if not _ready_for_audio or music_id == _current_music_id:
		return
	var stream: AudioStream = _music_cache.get(music_id)
	if stream == null:
		return
	_current_music_id = music_id
	_current_music_volume_db = -60.0

	# Fade out whatever is playing.
	for player in _music_players:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -60.0, fade_seconds)

	var target: AudioStreamPlayer = _music_players[_music_index]
	_music_index = (_music_index + 1) % _music_players.size()
	target.stream = stream
	target.volume_db = -60.0
	target.play()
	var fade_in := create_tween()
	fade_in.tween_property(target, "volume_db", 0.0, fade_seconds)


func stop_music(fade_seconds: float = 0.8) -> void:
	_current_music_id = ""
	for player in _music_players:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -60.0, fade_seconds)
			tween.tween_callback(player.stop)


func current_music() -> String:
	return _current_music_id


## Duck the music (used when a boss intro or a cutscene takes over).
func duck(amount_db: float = -8.0, duration: float = 0.5) -> void:
	var bus := AudioServer.get_bus_index(BUS_MUSIC)
	if bus == -1:
		return
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void: AudioServer.set_bus_volume_db(bus, value),
		AudioServer.get_bus_volume_db(bus),
		AudioServer.get_bus_volume_db(bus) + amount_db,
		duration)


# --- library generation -----------------------------------------------------

func _generate_library() -> void:
	var sfx_dir := "res://src/data/audio"
	# The synth definitions live in data so a designer can add a sound without
	# touching engine code. Anything listed there is baked on boot.
	if not DirAccess.dir_exists_absolute(sfx_dir):
		return
	for file_name in DirAccess.get_files_at(sfx_dir):
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sfx_dir.path_join(file_name)))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for sound_id: String in (parsed as Dictionary).keys():
			_sfx_cache[sound_id] = Synth.sfx_from_definition(parsed[sound_id], SAMPLE_RATE)
	for file_name in DirAccess.get_files_at(sfx_dir):
		if not file_name.ends_with(".music.json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sfx_dir.path_join(file_name)))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for music_id: String in (parsed as Dictionary).keys():
			_music_cache[music_id] = Synth.music_from_definition(parsed[music_id], SAMPLE_RATE)
