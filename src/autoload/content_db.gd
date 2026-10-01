extends Node
## Content registry.
##
## Single source of truth for what content exists. Loads and validates every
## level and zone at boot, reports problems loudly, and serves typed lookups
## to everything else. If a level file is malformed the game still runs and
## says exactly what is wrong -- content never crashes the engine.

const ZONES_DIR := "res://src/data/zones"
const LEVELS_DIR := "res://src/data/levels"
const CHARACTERS_PATH := "res://src/data/characters/characters.json"

var zones: Array[ZoneData] = []
var levels: Dictionary = {}          ## level_id -> LevelData
var characters: Dictionary = {}      ## character_id -> character data
var _zone_index: Dictionary = {}     ## zone_id -> ZoneData
var _load_errors: PackedStringArray = PackedStringArray()
var _loaded: bool = false


func _ready() -> void:
	load_all()


func load_all() -> void:
	zones.clear()
	levels.clear()
	characters.clear()
	_zone_index.clear()
	_load_errors.clear()

	_load_zones()
	_load_levels()
	_load_characters()
	_validate_cross_references()
	_loaded = true

	if not _load_errors.is_empty():
		push_warning("ContentDB: %d content problem(s) detected" % _load_errors.size())


func ensure_loaded() -> void:
	if not _loaded:
		load_all()


func _load_zones() -> void:
	var paths := _json_files_in(ZONES_DIR)
	# Zones declare their own order; sort by it so campaign flow is data-driven.
	var parsed: Array[ZoneData] = []
	for path in paths:
		var data: Variant = _read_json(path)
		if typeof(data) != TYPE_DICTIONARY:
			_load_errors.append("%s: not a JSON object" % path)
			continue
		var zone := ZoneData.from_dict(data)
		for error in zone.errors:
			_load_errors.append("%s: %s" % [path.get_file(), error])
		parsed.append(zone)
	parsed.sort_custom(func(a: ZoneData, b: ZoneData) -> bool: return a.index < b.index)
	for zone in parsed:
		if _zone_index.has(zone.id):
			_load_errors.append("duplicate zone id '%s'" % zone.id)
			continue
		zones.append(zone)
		_zone_index[zone.id] = zone


func _load_levels() -> void:
	# Levels are nested per zone: data/levels/zone01/*.json
	for zone in zones:
		var dir := LEVELS_DIR.path_join(zone.id)
		if not DirAccess.dir_exists_absolute(dir):
			_load_errors.append("zone '%s' has no level directory %s" % [zone.id, dir])
			continue
		for path in _json_files_in(dir):
			var data: Variant = _read_json(path)
			if typeof(data) != TYPE_DICTIONARY:
				_load_errors.append("%s: not a JSON object" % path)
				continue
			var level := LevelData.from_dict(data)
			if level.id.is_empty():
				# Fall back to the filename so the error names something usable.
				level.id = path.get_file().get_basename()
				level.errors.append("missing 'id', using filename '%s'" % level.id)
			if level.zone_id.is_empty():
				level.zone_id = zone.id
			for error in level.errors:
				_load_errors.append("%s: %s" % [path.get_file(), error])
			for warning in level.warnings:
				_load_errors.append("%s (warning): %s" % [path.get_file(), warning])
			if levels.has(level.id):
				_load_errors.append("duplicate level id '%s'" % level.id)
				continue
			levels[level.id] = level


## Make sure every level referenced by a zone actually exists, and vice versa.
func _validate_cross_references() -> void:
	for zone in zones:
		for level_id in zone.level_ids:
			if not levels.has(level_id):
				_load_errors.append("zone '%s' references missing level '%s'" % [zone.id, level_id])
		if not zone.boss_level_id.is_empty() and not levels.has(zone.boss_level_id):
			_load_errors.append("zone '%s' references missing boss level '%s'"
				% [zone.id, zone.boss_level_id])
		if not zone.requires_zone.is_empty() and not _zone_index.has(zone.requires_zone):
			_load_errors.append("zone '%s' requires unknown zone '%s'"
				% [zone.id, zone.requires_zone])

	var referenced: Dictionary = {}
	for zone in zones:
		for level_id in zone.level_ids:
			referenced[level_id] = true
		if not zone.boss_level_id.is_empty():
			referenced[zone.boss_level_id] = true
	for level_id in levels.keys():
		if not referenced.has(level_id):
			_load_errors.append("level '%s' is not referenced by any zone" % level_id)


func _json_files_in(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return found
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".json") and not file_name.begins_with("_"):
			found.append(dir_path.path_join(file_name))
	var sorted := Array(found)
	sorted.sort()
	return PackedStringArray(sorted)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_load_errors.append("%s: file not found" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_load_errors.append("%s: invalid JSON (line %d)" % [path, _first_error_line(text)])
	return parsed


func _first_error_line(text: String) -> int:
	# Cheap sanity check so a broken file reports something actionable.
	for i in text.length():
		if text[i] == "\n" and i > 0 and text[i - 1] not in [" ", "\t", "\r", ","]:
			continue
	return maxi(1, text.split("\n").size())


func _load_characters() -> void:
	if not FileAccess.file_exists(CHARACTERS_PATH):
		_load_errors.append("characters file not found at %s" % CHARACTERS_PATH)
		return
	var text := FileAccess.get_file_as_string(CHARACTERS_PATH)
	if text.is_empty():
		_load_errors.append("characters file is empty")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_errors.append("characters: not a JSON object")
		return
	
	var char_list: Array = (parsed as Dictionary).characters as Array
	if typeof(char_list) != TYPE_ARRAY:
		_load_errors.append("characters: 'characters' must be an array")
		return
	
	for char_data in char_list:
		if typeof(char_data) != TYPE_DICTIONARY:
			continue
		var id := String(char_data.get("id", ""))
		if id.is_empty():
			_load_errors.append("character missing 'id'")
			continue
		if characters.has(id):
			_load_errors.append("duplicate character id '%s'" % id)
			continue
		characters[id] = char_data


# --- lookups ----------------------------------------------------------------

func get_level(level_id: String) -> LevelData:
	ensure_loaded()
	return levels.get(level_id)


func has_level(level_id: String) -> bool:
	ensure_loaded()
	return levels.has(level_id)


func get_zone(zone_id: String) -> ZoneData:
	ensure_loaded()
	return _zone_index.get(zone_id)


func get_zone_of_level(level_id: String) -> ZoneData:
	var level := get_level(level_id)
	if level == null:
		return null
	return get_zone(level.zone_id)


func zone_count() -> int:
	ensure_loaded()
	return zones.size()


func level_count() -> int:
	ensure_loaded()
	return levels.size()


## Every level in campaign order, boss levels last within their zone.
func campaign_order() -> PackedStringArray:
	ensure_loaded()
	var order := PackedStringArray()
	for zone in zones:
		for level_id in zone.level_ids:
			order.append(level_id)
		if not zone.boss_level_id.is_empty():
			order.append(zone.boss_level_id)
	return order


## The level the campaign should continue from.
func next_level_after(level_id: String) -> String:
	var order := campaign_order()
	var index := order.find(level_id)
	if index == -1:
		return order[0] if not order.is_empty() else ""
	if index + 1 < order.size():
		return order[index + 1]
	return ""


## The first level of the campaign, used to reset progression.
func first_level() -> String:
	var order := campaign_order()
	return order[0] if not order.is_empty() else ""


func is_boss_level(level_id: String) -> bool:
	var level := get_level(level_id)
	return level != null and level.has_boss


# --- character lookups --------------------------------------------------------

func get_character(character_id: String) -> Dictionary:
	ensure_loaded()
	return characters.get(character_id, characters.get("aero", {}))

func has_character(character_id: String) -> bool:
	ensure_loaded()
	return characters.has(character_id)

func get_all_characters() -> Array:
	ensure_loaded()
	var list := []
	for key in characters.keys():
		list.append(characters[key])
	return list

func character_count() -> int:
	ensure_loaded()
	return characters.size()


func errors() -> PackedStringArray:
	return _load_errors


func content_report() -> Dictionary:
	var total_collectibles := 0
	var total_enemies := 0
	var total_secrets := 0
	for level_id in levels.keys():
		var level: LevelData = levels[level_id]
		total_collectibles += level.collectible_total()
		total_enemies += level.enemy_total()
		total_secrets += level.secret_total()
	return {
		"zones": zones.size(),
		"levels": levels.size(),
		"collectibles": total_collectibles,
		"enemies": total_enemies,
		"secrets": total_secrets,
		"errors": _load_errors.size(),
	}
