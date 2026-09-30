extends Node
## Save file IO. All progression *rules* live in SaveData (pure, testable);
## this autoload only reads and writes bytes.
##
## Writes are atomic: serialise to a temp file, verify it parses, then swap
## it in. A crash mid-save must never destroy a player's campaign.

const SAVE_PATH := "user://savegame.json"
const BACKUP_PATH := "user://savegame.bak.json"
const TEMP_PATH := "user://savegame.tmp.json"
const AUTOSAVE_INTERVAL := 25.0

var data: SaveData = null
var _dirty: bool = false
var _autosave_timer: float = 0.0
var _last_error: String = ""


func _ready() -> void:
	load_game()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _dirty:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		save_game()


func has_save() -> bool:
	return data != null and data.has_any_progress()


func load_game() -> SaveData:
	data = _read_from(SAVE_PATH)
	if data == null:
		# Primary is missing or corrupt: fall back to the backup.
		data = _read_from(BACKUP_PATH)
		if data != null:
			push_warning("SaveManager: primary save unreadable, recovered from backup")
	if data == null:
		data = SaveData.create_new()
		_new_run_defaults(data)
		_last_error = "no save found"
	return data


func _read_from(path: String) -> SaveData:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: %s is not valid JSON" % path)
		return null
	var loaded := SaveData.from_dict(parsed)
	if loaded.migrate():
		push_warning("SaveManager: migrated save at %s" % path)
	return loaded


## Wipe everything and start a fresh campaign. The first level is unlocked so
## CONTINUAR always has somewhere to go.
func start_new_game(profile: String = "KIP") -> void:
	data = SaveData.create_new(profile)
	_new_run_defaults(data)
	_dirty = true
	save_game()
	EventBus.game_new_run_requested.emit()


func _new_run_defaults(data: SaveData) -> void:
	data.unlock_zone("zone01")
	data.unlock_level("z1_l1")
	data.unlock_skin("default")
	data.max_lives = 3
	data.lives = 3


## Commit to disk now. Safe to call at any time.
func save_game() -> bool:
	if data == null:
		return false
	_dirty = false
	_autosave_timer = 0.0
	data.last_played = Time.get_unix_time_from_system()

	var payload := JSON.stringify(data.to_dict(), "\t")
	# 1. write temp
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		_last_error = "could not open temp file"
		push_error("SaveManager: %s" % _last_error)
		return false
	temp.store_string(payload)
	temp.close()

	# 2. verify the temp file round-trips before trusting it
	if typeof(JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))) != TYPE_DICTIONARY:
		_last_error = "serialised save failed validation"
		push_error("SaveManager: %s" % _last_error)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
		return false

	# 3. keep the previous good save as a backup, then swap
	if FileAccess.file_exists(SAVE_PATH):
		var previous := FileAccess.get_file_as_string(SAVE_PATH)
		var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		if backup != null:
			backup.store_string(previous)
			backup.close()

	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		_last_error = "atomic swap failed (%d)" % err
		push_error("SaveManager: %s" % _last_error)
		return false
	_last_error = ""
	return true


## Mark state as needing a flush without writing immediately.
func touch() -> void:
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func record_completion(result: GameTypes.LevelResult) -> Dictionary:
	var out: Dictionary = data.record_completion(result)
	_dirty = true
	return out


func set_current_level(level_id: String) -> void:
	data.current_level_id = level_id
	_dirty = true


func set_lives(lives: int) -> void:
	data.lives = clampi(lives, 0, data.max_lives)
	_dirty = true


func add_play_time(seconds: float) -> void:
	data.total_play_time += seconds
	_dirty = true


func last_error() -> String:
	return _last_error


func _notification(what: int) -> void:
	# Flush on quit so progress is never lost to a hard exit.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			save_game()
		elif data != null:
			data.last_played = Time.get_unix_time_from_system()
			save_game()
