extends Node
## Global event bus.
##
## Decoupling contract for the whole game: systems publish what happened here
## and subscribe to what they care about. No system holds a reference to
## another system for the purpose of reacting to a change -- that coupling
## goes through these signals. This is what makes menus, HUD, audio,
## achievements and analytics reusable without editing gameplay code.
##
## Rule of thumb: if a gameplay system needs to tell the UI something, emit.
## If the UI needs to tell gameplay something, use a typed method on
## GameManager / the level API -- not a signal.

# --- lifecycle --------------------------------------------------------------

signal game_boot_requested()
signal game_new_run_requested()
signal game_continue_requested()

# --- level lifecycle --------------------------------------------------------

signal level_loading(level_id: String, display_name: String)
signal level_started(level_id: String, attempt: int)
signal level_completed(result: GameTypes.LevelResult)
signal level_failed(reason: String)
signal level_restarted()
signal level_exited(to: String)
signal level_time_updated(elapsed: float)
signal level_time_ran_out()

# --- checkpoints ------------------------------------------------------------

signal checkpoint_reached(checkpoint_id: String, index: int, total: int)
signal checkpoint_activated(position: Vector2)

# --- player -----------------------------------------------------------------

signal player_spawned()
signal player_damaged(current_health: float, max_health: float, amount: float, source: String)
signal player_healed(current_health: float, amount: float)
signal player_died(cause: String)
signal player_respawned(health: float)
signal player_jumped()
signal player_landed(fall_speed: float, hard_landing: bool)
signal player_dashed(direction: Vector2, distance: float)
signal player_attack_started(airborne: bool)
signal player_attack_hit(actor_id: String, damage: int)
signal player_state_changed(state_name: String)
signal player_lives_changed(lives: int)
signal player_checkpoint_state_changed(has_checkpoint: bool)

# --- combat / actors --------------------------------------------------------

signal enemy_spawned(enemy_id: String, position: Vector2)
signal enemy_damaged(enemy_id: String, current_health: float, max_health: float)
signal enemy_defeated(enemy_id: String, position: Vector2, points: int)
signal boss_started(boss_id: String, display_name: String)
signal boss_intro_started(boss_id: String, display_name: String)
signal boss_phase_changed(boss_id: String, phase: int, phase_count: int)
signal boss_health_changed(boss_id: String, current: float, max: float)
signal boss_defeated(boss_id: String, rewards: Dictionary)

# --- items ------------------------------------------------------------------

signal item_collected(item_id: String, item_type: String, value: int, position: Vector2)
signal powerup_started(powerup_id: String, duration: float)
signal powerup_ended(powerup_id: String)
signal powerup_expired(powerup_id: String)
signal secret_area_entered(area_id: String)
signal secret_area_exited(area_id: String)

# --- score / flow -----------------------------------------------------------

signal score_changed(score: int, combo: int, combo_multiplier: float)
signal combo_changed(combo: int, multiplier: float, time_left: float)
signal combo_broken(lost_combo: int)
signal achievement_unlocked(achievement_id: String, title: String, description: String)

# --- flow control -----------------------------------------------------------

signal game_paused()
signal game_resumed()
signal game_quit_requested()

# --- settings ---------------------------------------------------------------

signal settings_changed(section: String, key: String, value: Variant)


## Convenience: fire a settings signal with a single call site.
func notify_setting_changed(section: String, key: String, value: Variant) -> void:
	settings_changed.emit(section, key, value)
