class_name CharacterData
extends RefCounted
## Character definitions loaded from JSON.
## Pure data, no logic. Gameplay systems read modifiers from here.

const DATA_PATH := "res://src/data/characters/characters.json"

var characters: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	load_all()

func load_all() -> void:
	if _loaded:
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_error("CharacterData: file not found at %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CharacterData: invalid JSON")
		return
	
	for char_data in (parsed as Dictionary).characters:
		var id := String(char_data.id)
		characters[id] = char_data
	
	_loaded = true

func get_character(id: String) -> Dictionary:
	if not _loaded:
		load_all()
	return characters.get(id, characters["aero"])

func get_all_characters() -> Array:
	if not _loaded:
		load_all()
	var list := []
	for key in characters.keys():
		list.append(characters[key])
	return list

func get_unlocked_characters(save_data: SaveData) -> Array:
	var list := []
	for key in characters.keys():
		var char := characters[key]
		if save_data.is_character_unlocked(key):
			list.append(char)
	return list

func is_unlocked(id: String, save_data: SaveData) -> bool:
	return save_data.is_character_unlocked(id)

func get_currency_data(currency_id: String) -> Dictionary:
	if not _loaded:
		load_all()
	var currency_data := (JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) as Dictionary).currency
	return currency_data.get(currency_id, {})