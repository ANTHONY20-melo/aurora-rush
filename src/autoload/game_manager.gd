extends Node
## Run state authority + level session orchestration.
##
## Owns everything that belongs to "the attempt currently in progress":
## health, lives, score, combo, timers, checkpoints, power-ups. Systems read
## and mutate through the typed API here, and the UI observes via EventBus.
## Nothing else keeps gameplay state, so there is exactly one truth.

enum RunMode { CAMPAIGN, TIME_ATTACK, CHALLENGE, FREE_ROAM }

const COMBO_WINDOW := 2.4
const COMBO_MAX := 32
const COMBO_STEP := 0.25
const COMBO_MAX_MULTIPLIER := 4.0

# --- current run -----------------------------------------------------------
var mode: int = RunMode.CAMPAIGN
var level_id: String = ""
var level: LevelData = null
var is_playing: bool = false
var is_paused: bool = false

var score: int = 0
var lives: int = 3
var health: float = 100.0
var max_health: float = 100.0
var energy: int = 0
var combo: int = 0
var combo_multiplier: float = 1.0
var _combo_timer: float = 0.0
var elapsed_time: float = 0.0
var deaths: int = 0
var damage_taken: int = 0
var enemies_defeated: int = 0
var collectibles_collected: int = 0
var collectibles_total: int = 0
var secrets_found: int = 0
var secrets_total: int = 0
var checkpoint_index: int = -1
var respawn_point: Vector2 = Vector2.ZERO
var active_powerups: Dictionary = {}   ## id -> seconds remaining
var powers_used: PackedStringArray = PackedStringArray()
var invulnerable_time: float = 0.0
var boss_active: bool = false
var boss_cleared: bool = false
var level_finished: bool = false
var last_result: GameTypes.LevelResult = null

# --- score values (data, not literals scattered in gameplay) ---------------
const SCORE_ENEMY := 100
const SCORE_ENEMY_ELITE := 250
const SCORE_BOSS := 2500
const SCORE_COLLECTIBLE := 25
const SCORE_CRYSTAL := 150
const SCORE_FRAGMENT := 400
const SCORE_SPECIAL := 1000
const SCORE_SECRET := 750
const SCORE_CHECKPOINT := 50
const SCORE_TIME_PER_SECOND := 12
const SCORE_NO_DAMAGE_BONUS := 1500
const SCORE_DEATH_PENALTY := 300


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	max_health = 100.0


func _process(delta: float) -> void:
	if not is_playing or is_paused or level_finished:
		return
	elapsed_time += delta
	EventBus.level_time_updated.emit(elapsed_time)

	_tick_combo(delta)
	_tick_invulnerability(delta)
	_tick_powerups(delta)
	_check_time_limit()


# --- run lifecycle ----------------------------------------------------------

func begin_run(target_level_id: String, run_mode: int = RunMode.CAMPAIGN) -> bool:
	var data := ContentDB.get_level(target_level_id)
	if data == null:
		push_error("GameManager: unknown level '%s'" % target_level_id)
		return false
	level = data
	level_id = target_level_id
	mode = run_mode
	score = 0
	elapsed_time = 0.0
	deaths = 0
	damage_taken = 0
	enemies_defeated = 0
	collectibles_collected = 0
	secrets_found = 0
	checkpoint_index = -1
	active_powerups.clear()
	powers_used = PackedStringArray()
	reset_combo()
	respawn_point = level.spawn_point
	collectibles_total = level.collectible_total()
	secrets_total = level.secret_total()
	health = max_health
	boss_active = false
	boss_cleared = false
	level_finished = false
	last_result = null
	is_playing = true
	is_paused = false
	lives = SaveManager.data.lives

	SaveManager.set_target_ranks(level_id, level.par_ranks)
	SaveManager.set_current_level(level_id)
	EventBus.level_started.emit(level_id, SaveManager.data.get_record(level_id).attempts + 1)
	return true


func end_run(completed: bool) -> GameTypes.LevelResult:
	if level == null:
		return null
	is_playing = false
	var result := GameTypes.LevelResult.new()
	result.level_id = level_id
	result.zone_id = level.zone_id
	result.attempt_time = elapsed_time
	result.deaths = deaths
	result.collectibles_collected = collectibles_collected
	result.collectibles_total = collectibles_total
	result.enemies_defeated = enemies_defeated
	result.secrets_found = secrets_found
	result.secrets_total = secrets_total
	result.completed = completed
	result.damage_taken = damage_taken
	result.powers_used = powers_used.duplicate()
	result.score = final_score()
	level_finished = true
	last_result = result
	return result


## Score after time is converted to a bonus, and deaths are deducted.
func final_score() -> int:
	var time_bonus: float = float(elapsed_time) * SCORE_TIME_PER_SECOND \
		* float(ConfigManager.difficulty_modifiers()["time_bonus"])
	var death_cost: int = deaths * SCORE_DEATH_PENALTY
	var value: int = int(round(score + time_bonus)) - death_cost
	return maxi(0, value)


# --- scoring ----------------------------------------------------------------

func add_score(amount: int, at: Vector2 = Vector2.ZERO) -> void:
	if amount == 0:
		return
	score += int(round(float(amount) * combo_multiplier))
	EventBus.score_changed.emit(score, combo, combo_multiplier)


func register_enemy_defeated(position: Vector2, is_elite: bool = false) -> void:
	enemies_defeated += 1
	add_score(SCORE_ENEMY_ELITE if is_elite else SCORE_ENEMY, position)
	bump_combo()


func register_collectible(kind: String, position: Vector2) -> void:
	collectibles_collected += 1
	energy += 1
	match kind:
		"collectible_energy": add_score(SCORE_COLLECTIBLE, position)
		"collectible_crystal": add_score(SCORE_CRYSTAL, position)
		"collectible_fragment":
			add_score(SCORE_FRAGMENT, position)
			SaveManager.data.fragments += 1
		"collectible_special": add_score(SCORE_SPECIAL, position)
		_: add_score(SCORE_COLLECTIBLE, position)
	bump_combo()


func register_secret(area_id: String, position: Vector2) -> void:
	secrets_found += 1
	add_score(SCORE_SECRET, position)
	SaveManager.data.discover_secret(level_id, area_id)


func register_checkpoint(index: int, position: Vector2, total: int) -> void:
	checkpoint_index = index
	respawn_point = position
	add_score(SCORE_CHECKPOINT, position)
	EventBus.checkpoint_reached.emit(level_id, index, total)
	EventBus.checkpoint_activated.emit(position)


# --- combo ------------------------------------------------------------------

func bump_combo() -> void:
	combo = mini(combo + 1, COMBO_MAX)
	combo_multiplier = minf(1.0 + float(combo) * COMBO_STEP, COMBO_MAX_MULTIPLIER)
	_combo_timer = COMBO_WINDOW
	EventBus.combo_changed.emit(combo, combo_multiplier, _combo_timer)


func reset_combo() -> void:
	combo = 0
	combo_multiplier = 1.0
	_combo_timer = 0.0


func _tick_combo(delta: float) -> void:
	if combo <= 0:
		return
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		var lost := combo
		reset_combo()
		EventBus.combo_broken.emit(lost)


# --- health / lives ---------------------------------------------------------

func damage(amount: float, source: String = "unknown") -> void:
	if invulnerable_time > 0.0 or level_finished or not is_playing:
		return
	
	# Apply character damage taken multiplier
	var char_data := ContentDB.get_character(SaveManager.data.get_selected_character())
	var damage_mult := float(char_data.gameplay_modifiers.get("damage_taken_multiplier", 1.0))
	amount *= damage_mult
	
	health = maxf(0.0, health - amount)
	damage_taken += int(amount)
	invulnerable_time = 1.2
	reset_combo()
	EventBus.player_damaged.emit(health, max_health, amount, source)
	if health <= 0.0:
		_on_death(source)


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	EventBus.player_healed.emit(health, amount)


func _tick_invulnerability(delta: float) -> void:
	if invulnerable_time > 0.0:
		invulnerable_time = maxf(0.0, invulnerable_time - delta)


func is_invulnerable() -> bool:
	return invulnerable_time > 0.0


func _on_death(cause: String) -> void:
	deaths += 1
	score = maxi(0, score - SCORE_DEATH_PENALTY / 2)
	health = max_health
	reset_combo()
	active_powerups.clear()
	invulnerable_time = 1.5
	SaveManager.set_lives(maxi(0, lives - 1))
	SaveManager.touch()
	EventBus.player_died.emit(cause)
	EventBus.player_lives_changed.emit(SaveManager.data.lives)
	if SaveManager.data.lives <= 0:
		EventBus.level_failed.emit("out_of_lives")


func reset_for_respawn() -> void:
	health = max_health
	reset_combo()
	invulnerable_time = 1.5
	active_powerups.clear()
	SaveManager.data.lives = maxi(1, SaveManager.data.lives)
	EventBus.player_respawned.emit(health)


# --- power-ups --------------------------------------------------------------

func apply_powerup(powerup_id: String, duration: float) -> void:
	active_powerups[powerup_id] = duration
	if not powers_used.has(powerup_id):
		powers_used.append(powerup_id)
	EventBus.powerup_started.emit(powerup_id, duration)


func _tick_powerups(delta: float) -> void:
	if active_powerups.is_empty():
		return
	var expired: PackedStringArray = PackedStringArray()
	for powerup_id: String in active_powerups.keys():
		active_powerups[powerup_id] = float(active_powerups[powerup_id]) - delta
		if float(active_powerups[powerup_id]) <= 0.0:
			expired.append(powerup_id)
	for powerup_id in expired:
		active_powerups.erase(powerup_id)
		EventBus.powerup_expired.emit(powerup_id)
		EventBus.powerup_ended.emit(powerup_id)


func has_powerup(powerup_id: String) -> bool:
	return active_powerups.has(powerup_id)


func powerup_time_left(powerup_id: String) -> float:
	return float(active_powerups.get(powerup_id, 0.0))


# --- time limit -------------------------------------------------------------

func _check_time_limit() -> void:
	if level != null and level.time_limit > 0.0 and elapsed_time >= level.time_limit:
		level_finished = true
		EventBus.level_time_ran_out.emit()


# --- pause ------------------------------------------------------------------

func set_paused(value: bool) -> void:
	if is_paused == value:
		return
	is_paused = value
	EventBus.game_paused.emit() if value else EventBus.game_resumed.emit()


func toggle_pause() -> void:
	set_paused(not is_paused)


# --- boss -------------------------------------------------------------------

func set_boss_active(value: bool) -> void:
	boss_active = value


func notify_boss_defeated(rewards: Dictionary) -> void:
	boss_cleared = true
	set_boss_active(false)
	add_score(SCORE_BOSS)
	SaveManager.data.fragments += int(rewards.get("fragments", 1))
	EventBus.boss_defeated.emit(String(rewards.get("boss_id", "")), rewards)


# --- completion -------------------------------------------------------------

func request_level_completion() -> void:
	if level_finished:
		return
	var result := end_run(true)
	complete_progression(result)


func complete_progression(result: GameTypes.LevelResult) -> void:
	var records := SaveManager.record_completion(result)
	result.is_new_time_record = bool(records.get("new_time", false))
	result.is_new_score_record = bool(records.get("new_score", false))
	result.is_new_rank_record = bool(records.get("new_rank", false))

	var record := SaveManager.data.get_record(result.level_id)
	result.best_time = record.best_time
	result.best_score = record.best_score

	_unlock_following(result.level_id)
	SaveManager.set_lives(SaveManager.data.max_lives)
	SaveManager.touch()
	EventBus.level_completed.emit(result)
	SaveManager.save_game()


## Opening the next level is content-driven: a zone's level list, then the
## boss, then the next zone. Unlocking is idempotent and lives in the save.
func _unlock_following(completed_level_id: String) -> void:
	var zone := ContentDB.get_zone_of_level(completed_level_id)
	if zone == null:
		return
	if not zone.boss_level_id.is_empty() and completed_level_id != zone.boss_level_id:
		SaveManager.data.unlock_level(zone.boss_level_id)
		return
	# Boss cleared: open the next zone's first level.
	for candidate in ContentDB.zones:
		if candidate.requires_zone == zone.id:
			SaveManager.data.unlock_zone(candidate.id)
			if not candidate.level_ids.is_empty():
				SaveManager.data.unlock_level(candidate.level_ids[0])
			return
	SaveManager.data.campaign_completed = true


# --- helpers ----------------------------------------------------------------

func has_time_pressure() -> bool:
	if level == null:
		return false
	return level.time_limit > 0.0 or level.kind == GameTypes.LevelKind.TIME_ATTACK


func is_assist_mode() -> bool:
	return ConfigManager.assist_mode()
