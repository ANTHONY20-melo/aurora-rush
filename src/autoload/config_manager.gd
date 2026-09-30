extends Node
## Settings authority.
##
## Owns the *default* for every setting, the current value, and persistence.
## Nothing else writes to the settings file, and nothing else invents a default
## -- if a setting exists, it is declared here once. Systems read typed getters
## from here and never touch `ConfigFile` themselves.

const SETTINGS_PATH := "user://settings.cfg"
const BINDINGS_PATH := "user://bindings.cfg"

## Default values, grouped by the settings section they belong to.
## Adding a setting = adding one line here. Nothing else changes.
const DEFAULTS := {
	"audio": {
		"master_volume": 0.9,
		"music_volume": 0.7,
		"sfx_volume": 0.9,
		"ui_volume": 0.8,
		"muted": false,
	},
	"video": {
		"fullscreen": false,
		"resolution_scale": 1.0,
		"quality": "high",          ## low | medium | high
		"particles": true,
		"screen_shake": true,
		"background_detail": "high", ## low | medium | high
		"vsync": true,
	},
	"accessibility": {
		"ui_scale": 1.0,
		"reduce_flashes": false,
		"screen_effects": true,
		"assist_mode": false,       ## easier timings, extra coyote time
		"high_contrast_hud": false,
		"camera_shake_scale": 1.0,
		"hold_to_dash": false,
	},
	"gameplay": {
		"difficulty": "normal",     ## easy | normal | hard | very_hard
		"show_timer": true,
		"lives_enabled": true,
		"auto_collect_radius": 0.0,
	},
}

## Quality presets -> concrete multipliers consumed by FX/particle systems.
const QUALITY_PRESETS := {
	"low":    {"particles": 0.25, "trails": false, "background_layers": 1, "shadows": false},
	"medium": {"particles": 0.6,  "trails": true,  "background_layers": 2, "shadows": false},
	"high":   {"particles": 1.0,  "trails": true,  "background_layers": 3, "shadows": true},
}

var _config := ConfigFile.new()
var _bindings := ConfigFile.new()
var _values: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	_rebuild_defaults()
	load_settings()
	apply_video_settings()


## Any consumer that needs a typed value before _ready has run.
func ensure_loaded() -> void:
	if not _loaded:
		_rebuild_defaults()
		load_settings()


func _rebuild_defaults() -> void:
	_values = {}
	for section: String in DEFAULTS.keys():
		var subsection: Dictionary = {}
		for key: String in DEFAULTS[section].keys():
			subsection[key] = DEFAULTS[section][key]
		_values[section] = subsection
	_loaded = true


# --- typed access -----------------------------------------------------------

func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	ensure_loaded()
	if _values.has(section) and (_values[section] as Dictionary).has(key):
		return _values[section][key]
	if fallback != null:
		return fallback
	if DEFAULTS.has(section) and (DEFAULTS[section] as Dictionary).has(key):
		return DEFAULTS[section][key]
	push_warning("ConfigManager: unknown setting %s.%s" % [section, key])
	return null


func set_value(section: String, key: String, value: Variant) -> void:
	ensure_loaded()
	if not _values.has(section):
		_values[section] = {}
	var before: Variant = _values[section].get(key)
	if before == value:
		return
	_values[section][key] = value
	EventBus.notify_setting_changed(section, key, value)
	_on_setting_applied(section, key, value)


func get_float(section: String, key: String) -> float:
	return float(get_value(section, key))


func get_int(section: String, key: String) -> int:
	return int(get_value(section, key))


func get_bool(section: String, key: String) -> bool:
	return bool(get_value(section, key))


func get_string(section: String, key: String) -> String:
	return String(get_value(section, key))


# --- convenience readers used all over the codebase -----------------------

func master_volume() -> float:
	return get_float("audio", "master_volume")


func music_volume() -> float:
	return get_float("audio", "music_volume")


func sfx_volume() -> float:
	return get_float("audio", "sfx_volume")


func ui_volume() -> float:
	return get_float("audio", "ui_volume")


func quality() -> String:
	return get_string("video", "quality")


func quality_preset() -> Dictionary:
	return QUALITY_PRESETS.get(quality(), QUALITY_PRESETS["high"])


func particles_enabled() -> bool:
	return get_bool("video", "particles")


func particle_scale() -> float:
	return float(quality_preset()["particles"])


func screen_shake_enabled() -> bool:
	return get_bool("video", "screen_shake")


func screen_shake_scale() -> float:
	if not screen_shake_enabled():
		return 0.0
	return get_float("accessibility", "camera_shake_scale")


func ui_scale() -> float:
	return get_float("accessibility", "ui_scale")


func reduce_flashes() -> bool:
	return get_bool("accessibility", "reduce_flashes")


func screen_effects_enabled() -> bool:
	return get_bool("video", "screen_shake") and get_bool("accessibility", "screen_effects")


func assist_mode() -> bool:
	return get_bool("accessibility", "assist_mode")


func difficulty() -> String:
	return get_string("gameplay", "difficulty")


## Difficulty multipliers used by gameplay tuning. Design still does the hard
## work -- these only trim the sharpest edges.
func difficulty_modifiers() -> Dictionary:
	match difficulty():
		"easy":
			return {"enemy_damage": 0.6, "enemy_health": 0.8, "time_bonus": 1.25, "lives": 5}
		"hard":
			return {"enemy_damage": 1.35, "enemy_health": 1.15, "time_bonus": 0.9, "lives": 3}
		"very_hard":
			return {"enemy_damage": 1.75, "enemy_health": 1.3, "time_bonus": 0.8, "lives": 2}
		_:
			return {"enemy_damage": 1.0, "enemy_health": 1.0, "time_bonus": 1.0, "lives": 3}


func _on_setting_applied(section: String, key: String, value: Variant) -> void:
	if section == "video":
		apply_video_settings()
	elif section == "accessibility" and key == "ui_scale":
		apply_ui_scale()
	elif section == "audio":
		EventBus.emit_signal("settings_changed", section, key, value)


# --- applying settings to the engine ---------------------------------------

func apply_video_settings() -> void:
	ensure_loaded()
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if get_bool("video", "fullscreen") \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_bool("video", "vsync") else DisplayServer.VSYNC_DISABLED)
	var scale: float = get_float("video", "resolution_scale")
	DisplayServer.window_set_size(Vector2i(
		int(1280 * scale), int(720 * scale)), DisplayServer.WINDOW_MODE_WINDOWED)


func apply_ui_scale() -> void:
	# Consumers (HUD, menus) read ui_scale() directly to size their fonts and
	# offsets. Theme.default_font_size gives a global baseline for strays.
	var base: int = 16
	ThemeDB.get_default_theme().default_font_size = int(round(base * ui_scale()))


# --- persistence ------------------------------------------------------------

func load_settings() -> void:
	_rebuild_defaults()
	var err := _config.load(SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("ConfigManager: could not read settings (%d)" % err)
	for section: String in DEFAULTS.keys():
		for key: String in DEFAULTS[section].keys():
			if not _config.has_section(section):
				continue
			if not _config.has_section_key(section, key):
				continue
			_values[section][key] = _config.get_value(section, key, _values[section][key])
	_loaded = true


func save_settings() -> void:
	ensure_loaded()
	for section: String in _values.keys():
		for key: String in (_values[section] as Dictionary).keys():
			_config.set_value(section, key, _values[section][key])
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("ConfigManager: could not save settings (%d)" % err)


func reset_to_defaults() -> void:
	_rebuild_defaults()
	for section: String in DEFAULTS.keys():
		for key: String in DEFAULTS[section].keys():
			EventBus.notify_setting_changed(section, key, _values[section][key])
	apply_video_settings()
	save_settings()


# --- input bindings ---------------------------------------------------------

## Actions that the player is allowed to rebind. UI-only navigation actions
## stay fixed so the player can never soft-lock the controls.
const REBINDABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"jump", "dash", "attack", "special", "interact", "quick_restart",
]


func load_bindings() -> Dictionary:
	var result: Dictionary = {}
	for action in REBINDABLE_ACTIONS:
		result[action] = binding_text(action)
	return result


## Human readable list of keys currently bound to an action.
func binding_text(action: String) -> PackedStringArray:
	var parts := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			parts.append(OS.get_keycode_string(event.physical_keycode))
		elif event is InputEventJoypadButton:
			parts.append("Pad%d" % event.button_index)
		elif event is InputEventJoypadMotion:
			var axis_name := "AxisY" if event.axis == JOY_AXIS_LEFT_Y else "AxisX"
			parts.append("%s%s" % [axis_name, "-" if event.axis_value < 0.0 else "+"])
	if parts.is_empty():
		parts.append("--")
	return parts


func set_key_binding(action: String, keycode: int) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	# Remove only keyboard events so gamepad support survives a rebind.
	var kept: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if not (event is InputEventKey):
			kept.append(event)
	InputMap.action_erase_events(action)
	for event in kept:
		InputMap.action_add_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)
	_persist_bindings()
	return true


func reset_bindings() -> void:
	# Re-read pristine defaults straight from the project manifest.
	InputMap.load_from_project_settings()
	_persist_bindings()
	EventBus.notify_setting_changed("controls", "bindings", "reset")


func _persist_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		_bindings.set_value("bindings", action, Array(binding_text(action)))
	_bindings.save(BINDINGS_PATH)
	EventBus.notify_setting_changed("controls", "bindings", "updated")
