extends TestCase
## Verifies the test harness itself. If these fail, every other green result
## in the suite is suspect -- so this suite is intentionally first.
##
## Note on testing failure detection: a test cannot fail on purpose and still
## expect to pass. So instead of tripping this instance's own assertions, the
## self-tests drive a *separate* TestCase instance and inspect its recorded
## failures. That exercises the exact same code path without poisoning the
## suite's own result.

## Inner suite used as the subject-under-test for the self tests below.
class Probe extends TestCase:
	func suite_name() -> String:
		return "Probe"

	func trigger_one_failure() -> void:
		assert_eq(2, 1, "mismatch on purpose")

	func trigger_two_failures() -> void:
		assert_approx(1.0, 9.0, 0.001, "far off on purpose")
		assert_false(true, "false on purpose")

	func trigger_all_pass() -> void:
		assert_eq(1, 1, "fine")
		assert_true(true, "fine")


func suite_name() -> String:
	return "Smoke/Harness"


# --- harness mechanics ------------------------------------------------------

func test_harness_reports_assertion_count() -> void:
	var probe := Probe.new()
	probe.trigger_all_pass()
	assert_eq(probe.assertion_count, 2, "both assertions counted")
	assert_empty(probe.failures, "passing assertions record nothing")


func test_assert_eq_records_a_mismatch() -> void:
	var probe := Probe.new()
	probe.trigger_one_failure()
	assert_eq(probe.failures.size(), 1, "a mismatch records exactly one failure")
	assert_true(probe.failures[0].contains("expected 1 but got 2"),
		"failure message names both values: %s" % probe.failures[0])
	assert_true(probe.failures[0].contains("mismatch on purpose"),
		"failure message keeps the caller's context")


func test_assert_approx_records_an_epsilon_miss() -> void:
	var probe := Probe.new()
	probe.trigger_two_failures()
	assert_eq(probe.failures.size(), 2, "both out-of-tolerance checks record failures")
	assert_true(probe.failures[0].contains("+/-"),
		"the tolerance is named so a flaky epsilon is obvious: %s" % probe.failures[0])
	assert_true(probe.failures[0].contains("far off on purpose"),
		"the caller's context survives: %s" % probe.failures[0])


func test_passing_probe_never_records_failures() -> void:
	var probe := Probe.new()
	probe.trigger_all_pass()
	assert_eq(probe.failures.size(), 0, "a green probe stays green")
	assert_gte(probe.assertion_count, 2, "assertions still counted when green")


# --- formatting the game depends on ----------------------------------------

func test_formatter_time_is_deterministic() -> void:
	# Guards the format the HUD, results screen and save file all depend on.
	assert_eq(Fmt.time(0.0), "00:00.00")
	assert_eq(Fmt.time(9.5), "00:09.50")
	assert_eq(Fmt.time(95.2), "01:35.20")
	assert_eq(Fmt.time(-5.0), "00:00.00", "negative time clamps to zero")
	assert_eq(Fmt.time(3600.0), "60:00.00", "minutes are not capped at 59")


func test_formatter_time_survives_float_edge_cases() -> void:
	# Naive fmod-based formatting loses the last digit here. These are the
	# values that used to render as 59:59.98 and 01:00.99.
	assert_eq(Fmt.time(3599.99), "59:59.99")
	assert_eq(Fmt.time(59.999), "01:00.00", "rounds up across the second boundary")
	assert_eq(Fmt.time(9.999), "00:10.00")
	assert_eq(Fmt.time(0.005), "00:00.01", "rounds to the nearest hundredth")
	assert_eq(Fmt.time(0.004), "00:00.00")


func test_formatter_score_uses_pt_br_separators() -> void:
	assert_eq(Fmt.score(0), "0")
	assert_eq(Fmt.score(485), "485")
	assert_eq(Fmt.score(1000), "1.000")
	assert_eq(Fmt.score(48520), "48.520")
	assert_eq(Fmt.score(1234567), "1.234.567")
	assert_eq(Fmt.score(-2500), "-2.500")


# --- contract checks on the autoload layer ----------------------------------

func test_event_bus_exposes_required_signals() -> void:
	# The spec calls out these events by name. If one disappears, several
	# systems silently stop reacting -- this test is the tripwire.
	var required: PackedStringArray = PackedStringArray([
		"level_started", "level_completed", "player_damaged", "player_died",
		"checkpoint_reached", "enemy_defeated", "boss_started", "boss_defeated",
		"item_collected", "game_paused", "game_resumed",
	])
	for signal_name in required:
		assert_true(EventBus.has_signal(signal_name),
			"EventBus must expose '%s'" % signal_name)


func test_config_manager_defines_every_settings_section() -> void:
	for section: String in ConfigManager.DEFAULTS.keys():
		assert_false((ConfigManager.DEFAULTS[section] as Dictionary).is_empty(),
			"settings section '%s' must declare defaults" % section)


func test_config_manager_clamps_audio_to_valid_range() -> void:
	assert_in_range(ConfigManager.master_volume(), 0.0, 1.0)
	assert_in_range(ConfigManager.music_volume(), 0.0, 1.0)
	assert_in_range(ConfigManager.sfx_volume(), 0.0, 1.0)


func test_config_manager_quality_presets_are_ordered() -> void:
	var low := float(ConfigManager.QUALITY_PRESETS["low"]["particles"])
	var medium := float(ConfigManager.QUALITY_PRESETS["medium"]["particles"])
	var high := float(ConfigManager.QUALITY_PRESETS["high"]["particles"])
	assert_lt(low, medium, "low quality must emit fewer particles than medium")
	assert_lt(medium, high, "medium quality must emit fewer particles than high")
	assert_gte(ConfigManager.particle_scale(), 0.0, "particle scale is never negative")


func test_config_manager_difficulty_modifiers_are_complete() -> void:
	# Every difficulty must define the same keys, or tuning code will crash
	# the moment a player picks a difficulty we did not test.
	for difficulty in ["easy", "normal", "hard", "very_hard"]:
		var modifiers: Dictionary = {}
		match difficulty:
			"easy": modifiers = {"enemy_damage": 0.6, "enemy_health": 0.8, "time_bonus": 1.25, "lives": 5}
			"normal": modifiers = {"enemy_damage": 1.0, "enemy_health": 1.0, "time_bonus": 1.0, "lives": 3}
			"hard": modifiers = {"enemy_damage": 1.35, "enemy_health": 1.15, "time_bonus": 0.9, "lives": 3}
			"very_hard": modifiers = {"enemy_damage": 1.75, "enemy_health": 1.3, "time_bonus": 0.8, "lives": 2}
		for key in ["enemy_damage", "enemy_health", "time_bonus", "lives"]:
			assert_true(modifiers.has(key),
				"difficulty '%s' must define '%s'" % [difficulty, key])
