class_name SaveData
extends RefCounted
## Pure save-file model: all progression rules live here, no disk access.
##
## Deliberately filesystem-free so the entire progression and unlock system
## is unit-testable under `--headless`. SaveManager owns the IO.

const SAVE_VERSION := 1

var version: int = SAVE_VERSION
var profile_name: String = "KIP"
var created_at: int = 0
var last_played: int = 0
var total_play_time: float = 0.0
var current_level_id: String = ""
var lives: int = 3
var max_lives: int = 3

## level_id -> LevelRecord
var levels: Dictionary = {}
## zone_id -> true
var unlocked_zones: Dictionary = {}
## ordered ids of levels the player may currently enter
var unlocked_levels: PackedStringArray = PackedStringArray()
## collectible definition ids acquired across the whole campaign
var collectibles: Dictionary = {}
## ability id -> unlocked
var abilities: Dictionary = {}
## cosmetic id -> unlocked
var skins: Dictionary = {}
var selected_skin: String = "default"
## character id -> true
var unlocked_characters: Dictionary = {}
## currency
var energy_fragments: int = 0
var aurora_crystals: int = 0
var selected_character: String = "aero"
## achievement id -> unix time unlocked
var achievements: Dictionary = {}
## star/fragment ids collected (campaign-wide counters)
var fragments: int = 0
var campaign_completed: bool = false
## ids of every level finished at least once, in completion order
var completion_order: PackedStringArray = PackedStringArray()
## challenge id -> true
var challenges_cleared: Dictionary = {}


static func create_new(profile: String = "KIP") -> SaveData:
	var data := SaveData.new()
	data.profile_name = profile
	data.created_at = Time.get_unix_time_from_system()
	data.last_played = data.created_at
	return data


# --- level records ----------------------------------------------------------

func get_record(level_id: String) -> GameTypes.LevelRecord:
	if levels.has(level_id):
		return levels[level_id]
	var record := GameTypes.LevelRecord.new()
	record.level_id = level_id
	levels[level_id] = record
	return record


func has_record(level_id: String) -> bool:
	return levels.has(level_id)


func is_level_completed(level_id: String) -> bool:
	return has_record(level_id) and (levels[level_id] as GameTypes.LevelRecord).completed


## Records a completed attempt and reports which records were beaten.
## Returns a dictionary of {new_time, new_score, new_rank} booleans so the
## results screen can celebrate without recomputing anything.
func record_completion(result: GameTypes.LevelResult) -> Dictionary:
	var record := get_record(result.level_id)
	record.attempts += 1
	record.deaths += result.deaths
	record.times.append(result.attempt_time)
	record.completed = true

	var out := {"new_time": false, "new_score": false, "new_rank": false}

	if record.best_time < 0.0 or result.attempt_time < record.best_time:
		record.best_time = result.attempt_time
		out["new_time"] = true
	if result.score > record.best_score:
		record.best_score = result.score
		out["new_score"] = true

	var rank := Ranking.compute_rank(result, get_target_ranks(result.level_id))
	if record.best_rank < 0 or rank > record.best_rank:
		record.best_rank = rank
		out["new_rank"] = true

	for star in result.powers_used:
		if not record.stars_collected.has(star):
			record.stars_collected.append(star)

	if not completion_order.has(result.level_id):
		completion_order.append(result.level_id)

	return out


## Rank thresholds per level. Content data owns the target times; the ranking
## system only reads them. This is what keeps ranks deterministic.
var _target_rank_cache: Dictionary = {}


func set_target_ranks(level_id: String, ranks: Dictionary) -> void:
	_target_rank_cache[level_id] = ranks


func get_target_ranks(level_id: String) -> Dictionary:
	if _target_rank_cache.has(level_id):
		return _target_rank_cache[level_id]
	return {"s": 45.0, "a": 60.0, "b": 80.0, "c": 105.0, "d": 140.0}


func collect_starlike(level_id: String, collectible_id: String) -> bool:
	var record := get_record(level_id)
	if record.stars_collected.has(collectible_id):
		return false
	record.stars_collected.append(collectible_id)
	collectibles[collectible_id] = true
	return true


func discover_secret(level_id: String, secret_id: String) -> bool:
	var record := get_record(level_id)
	if record.secrets_found.has(secret_id):
		return false
	record.secrets_found.append(secret_id)
	return true


# --- unlocks ----------------------------------------------------------------

func unlock_zone(zone_id: String) -> bool:
	if unlocked_zones.has(zone_id):
		return false
	unlocked_zones[zone_id] = true
	return true


func is_zone_unlocked(zone_id: String) -> bool:
	return unlocked_zones.has(zone_id)


func unlock_level(level_id: String) -> bool:
	if unlocked_levels.has(level_id):
		return false
	unlocked_levels.append(level_id)
	return true


func is_level_unlocked(level_id: String) -> bool:
	return unlocked_levels.has(level_id)


func unlock_ability(ability_id: String) -> bool:
	if abilities.has(ability_id):
		return false
	abilities[ability_id] = true
	return true


func has_ability(ability_id: String) -> bool:
	return abilities.has(ability_id)


func unlock_skin(skin_id: String) -> bool:
	if skins.has(skin_id):
		return false
	skins[skin_id] = true
	return true


func has_skin(skin_id: String) -> bool:
	return skins.has(skin_id)


func select_skin(skin_id: String) -> bool:
	if not has_skin(skin_id):
		return false
	selected_skin = skin_id
	return true


func mark_challenge_cleared(challenge_id: String) -> bool:
	if challenges_cleared.has(challenge_id):
		return false
	challenges_cleared[challenge_id] = true
	return true


# --- characters ---------------------------------------------------------------

func unlock_character(character_id: String) -> bool:
	if unlocked_characters.has(character_id):
		return false
	unlocked_characters[character_id] = true
	return true


func is_character_unlocked(character_id: String) -> bool:
	return unlocked_characters.has(character_id)


func select_character(character_id: String) -> bool:
	if not is_character_unlocked(character_id):
		return false
	selected_character = character_id
	return true


func get_selected_character() -> String:
	if not is_character_unlocked(selected_character):
		selected_character = "aero"
	return selected_character


# --- currency ----------------------------------------------------------------

func add_energy_fragments(amount: int) -> void:
	energy_fragments += maxi(0, amount)


func spend_energy_fragments(amount: int) -> bool:
	if energy_fragments < amount:
		return false
	energy_fragments -= amount
	return true


func add_aurora_crystals(amount: int) -> void:
	aurora_crystals += maxi(0, amount)


func spend_aurora_crystals(amount: int) -> bool:
	if aurora_crystals < amount:
		return false
	aurora_crystals -= amount
	return true


# --- aggregate progress -----------------------------------------------------

func levels_completed_count() -> int:
	var count := 0
	for level_id in levels.keys():
		if (levels[level_id] as GameTypes.LevelRecord).completed:
			count += 1
	return count


func total_collectibles() -> int:
	return collectibles.size()


func total_secrets() -> int:
	var count := 0
	for level_id in levels.keys():
		count += (levels[level_id] as GameTypes.LevelRecord).secrets_found.size()
	return count


func has_any_progress() -> bool:
	return not completion_order.is_empty() or not unlocked_levels.is_empty() \
		or levels_completed_count() > 0


# --- achievements -----------------------------------------------------------

func unlock_achievement(id: String) -> bool:
	if achievements.has(id):
		return false
	achievements[id] = Time.get_unix_time_from_system()
	return true


func has_achievement(id: String) -> bool:
	return achievements.has(id)


# --- serialisation ----------------------------------------------------------

func to_dict() -> Dictionary:
	var level_dict: Dictionary = {}
	for level_id in levels.keys():
		level_dict[level_id] = (levels[level_id] as GameTypes.LevelRecord).to_dict()
	return {
		"version": version,
		"profile_name": profile_name,
		"created_at": created_at,
		"last_played": last_played,
		"total_play_time": total_play_time,
		"current_level_id": current_level_id,
		"lives": lives,
		"max_lives": max_lives,
		"levels": level_dict,
		"unlocked_zones": unlocked_zones.duplicate(),
		"unlocked_levels": Array(unlocked_levels),
		"collectibles": collectibles.duplicate(),
		"abilities": abilities.duplicate(),
		"skins": skins.duplicate(),
		"selected_skin": selected_skin,
		"unlocked_characters": unlocked_characters.duplicate(),
		"energy_fragments": energy_fragments,
		"aurora_crystals": aurora_crystals,
		"selected_character": selected_character,
		"achievements": achievements.duplicate(),
		"challenges_cleared": challenges_cleared.duplicate(),
		"fragments": fragments,
		"campaign_completed": campaign_completed,
		"completion_order": Array(completion_order),
	}


## Tolerant loader: a corrupt or older save must degrade, never crash.
## Unknown fields are ignored, missing fields fall back to defaults.
static func from_dict(data: Dictionary) -> SaveData:
	var out := SaveData.new()
	out.version = int(data.get("version", 1))
	out.profile_name = String(data.get("profile_name", "KIP"))
	out.created_at = int(data.get("created_at", 0))
	out.last_played = int(data.get("last_played", 0))
	out.total_play_time = float(data.get("total_play_time", 0.0))
	out.current_level_id = String(data.get("current_level_id", ""))
	out.lives = int(data.get("lives", 3))
	out.max_lives = int(data.get("max_lives", 3))
	for level_id in (data.get("levels", {}) as Dictionary).keys():
		out.levels[String(level_id)] = GameTypes.LevelRecord.from_dict(
			(data["levels"] as Dictionary)[level_id])
	out.unlocked_zones = (data.get("unlocked_zones", {}) as Dictionary).duplicate()
	for id in data.get("unlocked_levels", []):
		out.unlocked_levels.append(String(id))
	out.collectibles = (data.get("collectibles", {}) as Dictionary).duplicate()
	out.abilities = (data.get("abilities", {}) as Dictionary).duplicate()
	out.skins = (data.get("skins", {}) as Dictionary).duplicate()
	out.selected_skin = String(data.get("selected_skin", "default"))
	out.unlocked_characters = (data.get("unlocked_characters", {}) as Dictionary).duplicate()
	out.energy_fragments = int(data.get("energy_fragments", 0))
	out.aurora_crystals = int(data.get("aurora_crystals", 0))
	out.selected_character = String(data.get("selected_character", "aero"))
	out.achievements = (data.get("achievements", {}) as Dictionary).duplicate()
	out.challenges_cleared = (data.get("challenges_cleared", {}) as Dictionary).duplicate()
	out.fragments = int(data.get("fragments", 0))
	out.campaign_completed = bool(data.get("campaign_completed", false))
	for id in data.get("completion_order", []):
		out.completion_order.append(String(id))
	return out


## Forward-migration hook. Called by SaveManager after parsing.
func migrate() -> bool:
	var changed := false
	if version < SAVE_VERSION:
		# No older formats shipped yet; new fields default safely via from_dict.
		version = SAVE_VERSION
		changed = true
	if max_lives < lives:
		lives = max_lives
		changed = true
	return changed
