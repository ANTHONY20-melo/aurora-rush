extends TestCase
## Player movement feel.
##
## PlayerMovement owns gravity, acceleration and the jump/dash state machine.
## It receives a PlayerInput struct rather than reading the Input singleton,
## which is precisely so this suite can drive it at a fixed 60 Hz with no
## window and no device.
##
## The bar here is not "does it move" but "does it move the way a speed
## platformer must": snappy starts, hard turns, momentum on landing, forgiving
## jump timing, and a dash that cannot be farmed for free speed.

const World := preload("res://tests/helpers/world_builder.gd")
const DT := 1.0 / 60.0
const TILE := LevelData.TILE_SIZE


func suite_name() -> String:
	return "Player/Movement"


# --- harness ----------------------------------------------------------------

## A movement system standing on a flat floor, with the body at rest.
## `floor_y` must match the grid's floor row: seeding the body over empty space
## silently produces a runner that can never jump.
func make_runner(grid: LevelData, config: PlayerMovementConfig = null,
		floor_y: int = 10) -> PlayerMovement:
	var cfg := config if config != null else PlayerMovementConfig.new()
	var body := World.player_body()
	body.teleport(World.standing_on(body, 3.0, floor_y))
	var movement := PlayerMovement.new(cfg, body)
	# Seed the contact state so the first frame already sees ground.
	movement.step(DT, grid)
	movement.input = PlayerInput.neutral()
	return movement


func step_for(movement: PlayerMovement, grid: LevelData, frames: int) -> void:
	for _i in frames:
		movement.step(DT, grid)


func hold(movement: PlayerMovement, axis: float, frames: int, grid: LevelData) -> void:
	for _i in frames:
		movement.input.move_x = axis
		movement.step(DT, grid)


# --- acceleration and friction ----------------------------------------------

func test_idle_player_stays_put() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var start := movement.body.position.x
	step_for(movement, grid, 60)
	assert_approx(movement.body.position.x, start, 0.5, "an idle player does not drift")
	assert_approx(movement.body.velocity.x, 0.0, 0.5, "and carries no horizontal speed")
	assert_eq(movement.state, GameTypes.PlayerState.IDLE, "state is IDLE")


func test_player_accelerates_towards_max_speed() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var config := movement.config
	hold(movement, 1.0, 1, grid)
	assert_gt(movement.body.velocity.x, 0.0, "holding right produces rightward speed")

	# After one second of held input, speed must be near -- but not past -- cap.
	hold(movement, 1.0, 59, grid)
	assert_gte(movement.body.velocity.x, config.max_speed * 0.8,
		"one second of input reaches most of max speed")
	assert_lte(movement.body.velocity.x, config.max_speed + 0.01,
		"speed never exceeds max speed while accelerating")

	# And it must actually converge, not creep up forever.
	hold(movement, 1.0, 120, grid)
	assert_approx(movement.body.velocity.x, config.max_speed, 1.0,
		"speed settles exactly on max speed")


func test_ground_acceleration_is_fast_enough_to_feel_snappy() -> void:
	# A speed platformer lives or dies on this number. At 60Hz, reaching 90% of
	# max speed should take a small fraction of a second, not a noticeable wait.
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var config := movement.config
	var target := config.max_speed * 0.9
	var frames := 0
	movement.input.move_x = 1.0
	while absf(movement.body.velocity.x) < target and frames < 600:
		movement.step(DT, grid)
		frames += 1
	var seconds := float(frames) * DT
	assert_lte(seconds, 0.30,
		"90%% of max speed is reached within 0.30s, took %.3fs" % seconds)


func test_player_decelerates_to_a_stop() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	hold(movement, 1.0, 60, grid)
	assert_gt(movement.body.velocity.x, 100.0, "player is moving before release")
	movement.input.move_x = 0.0
	step_for(movement, grid, 60)
	assert_approx(movement.body.velocity.x, 0.0, 1.0, "releasing input brings the player to rest")


func test_turning_around_is_faster_than_accelerating_from_rest() -> void:
	# This is the difference between a controller that feels responsive and one
	# that feels like it is arguing with you.
	var grid := World.flat_ground(60, 10, 3)
	var config := PlayerMovementConfig.new()

	var from_rest := make_runner(grid, config)
	var rest_frames := 0
	from_rest.input.move_x = -1.0
	while rest_frames < 120:
		from_rest.step(DT, grid)
		if absf(from_rest.body.velocity.x) >= config.max_speed * 0.5:
			break
		rest_frames += 1

	var reversing := make_runner(grid, config)
	hold(reversing, 1.0, 60, grid)
	assert_gt(reversing.body.velocity.x, 0.0, "moving right first")
	reversing.input.move_x = -1.0
	var turn_frames := 0
	while turn_frames < 120:
		reversing.step(DT, grid)
		if reversing.body.velocity.x >= -config.max_speed * 0.5:
			break
		turn_frames += 1

	assert_lt(turn_frames, rest_frames,
		"reversing reaches half speed in fewer frames (%d) than accelerating (%d)"
		% [turn_frames, rest_frames])


func test_facing_follows_input_direction() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	hold(movement, 1.0, 2, grid)
	assert_eq(movement.facing, 1, "facing right when moving right")
	hold(movement, -1.0, 2, grid)
	assert_eq(movement.facing, -1, "facing left when moving left")


func test_air_control_is_weaker_than_ground_control() -> void:
	var config := PlayerMovementConfig.new()
	assert_lt(config.air_acceleration, config.ground_acceleration,
		"air acceleration must be lower than ground acceleration")
	assert_lte(config.max_air_speed, config.max_speed,
		"air top speed must not exceed ground top speed")


# --- jumping ----------------------------------------------------------------

func test_jump_leaves_the_ground() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	assert_true(movement.jump_started_this_frame, "jump is reported on the frame it starts")
	assert_lt(movement.body.velocity.y, 0.0, "the player moves upward")
	assert_false(movement.body.is_grounded(), "and leaves the ground")

	var peak := movement.body.position.y
	for _i in 60:
		movement.input.jump_held = true
		movement.input.jump_pressed = false
		movement.step(DT, grid)
		peak = minf(peak, movement.body.position.y)
	assert_lt(peak, movement.body.position.y, "the player actually gains height")


func test_variable_jump_height_releases_early_for_a_short_hop() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var full := make_runner(grid)
	var full_peak := _measure_jump_peak(full, grid, 0.45)

	var tapped := make_runner(grid)
	var tapped_peak := _measure_jump_peak(tapped, grid, 0.0)

	assert_lt(tapped_peak, full_peak,
		"releasing jump immediately jumps lower (%.1f) than holding it (%.1f)"
		% [tapped_peak, full_peak])
	assert_gt(full_peak - tapped_peak, 10.0,
		"the difference is large enough to be a real design lever")


func test_jump_reaches_a_useful_height() -> void:
	# A tile is 32px. A jump that clears less than ~3 tiles cannot be designed
	# around, so this is a hard floor on the tuning rather than a taste call.
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var rise := absf(_measure_jump_peak(movement, grid, 0.45))
	assert_gte(rise, 2.5 * TILE, "a held jump clears at least 2.5 tiles, got %.1f" % rise)
	assert_lte(rise, 7.0 * TILE, "and does not fly so high that levels lose all shape")


## How far the player rises when the jump button is held for `hold_time`
## seconds. Returns a positive height in pixels.
func _measure_jump_peak(movement: PlayerMovement, grid: LevelData,
		hold_time: float) -> float:
	var start := movement.body.position.y
	var low := start
	var frames := int(ceil(0.45 / DT))
	var hold_frames := int(hold_time / DT)
	for i in frames:
		movement.input.jump_pressed = (i == 0)
		movement.input.jump_held = i < hold_frames
		movement.step(DT, grid)
		low = minf(low, movement.body.position.y)
	return start - low


func test_coyote_time_allows_a_jump_just_after_leaving_a_ledge() -> void:
	# Walk off a ledge, then jump a frame or two later. Forgiving this is the
	# difference between a game that feels good and one that feels cheap.
	#
	# The body has to actually WALK off, not be teleported into mid-air: coyote
	# time is seeded by grounded frames, so a teleport clears the very state the
	# test is trying to exercise.
	var grid := _ledge_world()
	var movement := make_runner(grid, null, 8)
	movement.body.teleport(World.standing_on(movement.body, 6.0, 8))
	movement.step(DT, grid)
	assert_true(movement.body.is_grounded(), "the player starts on the ledge")

	movement.input.move_x = 1.0
	for _i in 120:
		movement.step(DT, grid)
		if not movement.body.is_grounded():
			break
	assert_false(movement.body.is_grounded(), "the player walked off the ledge")

	# Straight into a jump, still inside the coyote window.
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	assert_true(movement.jump_started_this_frame,
		"a jump within coyote time still counts as a ground jump")
	assert_lt(movement.body.velocity.y, 0.0, "and the player gets upward velocity")


func test_coyote_time_expires() -> void:
	var grid := _ledge_world()
	var movement := make_runner(grid, null, 8)
	movement.body.teleport(World.standing_on(movement.body, 6.0, 8))
	movement.step(DT, grid)
	movement.input.move_x = 1.0
	for _i in 120:
		movement.step(DT, grid)
		if not movement.body.is_grounded():
			break
	assert_false(movement.body.is_grounded(), "airborne past the ledge")

	# Wait well past the coyote window.
	step_for(movement, grid, int(ceil(movement.config.coyote_time / DT)) + 6)
	assert_false(movement.body.is_grounded(), "still falling")
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	assert_false(movement.jump_started_this_frame,
		"a jump long after leaving the ledge is not a free ground jump")


func test_jump_buffer_catches_a_press_landed_just_before_touching_down() -> void:
	# The mirror of coyote time: the player pressed jump slightly too early, and
	# the game should honour it the instant they land.
	#
	# Two things make this test meaningful:
	#  - air jumps are disabled, so a press mid-air cannot be consumed as an
	#    air jump before touchdown;
	#  - the press happens close enough to the floor that the 0.13s buffer is
	#    still live when the body lands. Pressing much earlier is an expired
	#    jump, not a buffered one.
	var config := PlayerMovementConfig.new()
	config.air_jumps = 0
	var grid := World.flat_ground(60, 14, 3)
	var movement := make_runner(grid, config)
	movement.body.teleport(Vector2(3.0 * TILE, 11.0 * TILE))
	movement.body.velocity = Vector2(0.0, 120.0)

	var floor_y := 14.0 * TILE
	while movement.body.feet_y() < floor_y - 20.0:
		movement.step(DT, grid)

	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	movement.input.jump_pressed = false

	var jumped := false
	for _i in 30:
		movement.step(DT, grid)
		if movement.jump_started_this_frame:
			jumped = true
			break
	assert_true(jumped, "a buffered jump fires on landing")


func test_double_jump_is_available_once_in_the_air() -> void:
	var grid := World.flat_ground(60, 16, 3)
	var movement := make_runner(grid, null, 16)
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	assert_eq(movement.jumps_used, 1, "the ground jump consumes one charge")

	# Airborne, press again.
	movement.input.jump_pressed = false
	step_for(movement, grid, 6)
	movement.input.jump_pressed = true
	movement.step(DT, grid)
	assert_true(movement.double_jump_started_this_frame, "the air jump fires")
	assert_eq(movement.jumps_used, 2, "and consumes the second charge")

	# A third press must do nothing.
	movement.input.jump_pressed = false
	movement.input.jump_held = false
	step_for(movement, grid, 6)
	movement.input.jump_pressed = true
	var before := movement.body.velocity.y
	movement.step(DT, grid)
	assert_false(movement.double_jump_started_this_frame, "there is no third jump")
	assert_false(movement.jump_started_this_frame, "and no fourth ground jump")
	# Assert the absence of an impulse rather than an exact gravity value:
	# gravity is scaled by rise/fall/apex state, which is an implementation
	# detail this suite should not pin down.
	assert_gt(absf(movement.body.velocity.y - before), 0.0,
		"gravity is still being applied on the third press")
	assert_lt(absf(movement.body.velocity.y - before), absf(movement.config.double_jump_force),
		"but no jump-sized impulse was applied")


func test_jump_charges_reset_on_landing() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	movement.step(DT, grid)
	assert_eq(movement.jumps_used, 1, "used one charge")
	# Fall back down and land.
	movement.input.jump_pressed = false
	movement.input.jump_held = false
	for _i in 200:
		movement.step(DT, grid)
		if movement.body.is_grounded():
			break
	# Charges are refilled at the START of the frame the player is seen to be
	# grounded, so one more frame is needed before the refill is observable.
	movement.step(DT, grid)
	assert_true(movement.body.is_grounded(), "the player is still on the floor")
	assert_eq(movement.jumps_used, 0, "landing refills every jump charge")
	assert_eq(movement.jump_charges_left(), movement.config.air_jumps + 1,
		"and the UI-facing charge count matches")


func test_cannot_jump_while_dashing() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	assert_true(movement.is_dashing, "dash started")

	movement.input.dash_pressed = false
	movement.input.jump_pressed = true
	movement.input.jump_held = true
	var before := movement.body.velocity.y
	movement.step(DT, grid)
	assert_false(movement.jump_started_this_frame, "jump is suppressed during a dash")
	assert_approx(movement.body.velocity.y, before, 0.01, "and no jump velocity is applied")


# --- dashing ----------------------------------------------------------------

func test_dash_sets_speed_and_direction() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.move_x = 1.0
	movement.input.dash_pressed = true
	movement.step(DT, grid)
	assert_true(movement.dash_started_this_frame, "dash is reported on its first frame")
	assert_true(movement.is_dashing, "the player is dashing")
	assert_approx(movement.body.velocity.x, movement.config.dash_speed, 0.01,
		"dash reaches dash speed immediately")


func test_dash_directions_follow_input_or_facing() -> void:
	var grid := World.flat_ground(60, 10, 3)

	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = -1.0
	movement.step(DT, grid)
	assert_lt(movement.body.velocity.x, 0.0, "dashing left goes left")

	# With no input, the dash follows facing.
	var facing_grid := World.flat_ground(60, 10, 3)
	var other := make_runner(facing_grid)
	other.facing = 1
	other.input.dash_pressed = true
	other.step(DT, facing_grid)
	assert_gt(other.body.velocity.x, 0.0, "an inputless dash goes the way the player faces")


func test_dash_ends_and_keeps_only_a_fraction_of_its_speed() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	var config := movement.config

	var frames := int(ceil(config.dash_duration / DT)) + 2
	step_for(movement, grid, frames)
	assert_false(movement.is_dashing, "the dash ends after its duration")

	var exit_speed := config.dash_speed * config.dash_exit_speed_factor
	assert_lte(movement.body.velocity.x, exit_speed + 1.0,
		"dash exit speed does not exceed the configured fraction")
	assert_gte(movement.body.velocity.x, 0.0, "and keeps the dash direction")


func test_dash_cannot_be_spammed_for_free_speed() -> void:
	# Dash, let it end, then dash again immediately. The second must be refused
	# by the cooldown, otherwise the player farms speed with a mash.
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	step_for(movement, grid, int(ceil(movement.config.dash_duration / DT)) + 2)
	assert_false(movement.is_dashing, "first dash finished")

	movement.input.dash_pressed = true
	movement.step(DT, grid)
	assert_false(movement.dash_started_this_frame,
		"an immediate second dash is refused by the cooldown")
	assert_lt(movement.body.velocity.x, movement.config.dash_speed,
		"and the player does not regain dash speed instantly")


func test_dash_cooldown_expires_and_allows_another_dash() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var config := movement.config
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	assert_true(movement.dash_started_this_frame, "first dash starts")

	var wait := int(ceil((config.dash_duration + config.dash_cooldown) / DT)) + 2
	movement.input.dash_pressed = false
	step_for(movement, grid, wait)
	assert_true(movement.can_dash(), "cooldown has expired")
	movement.input.dash_pressed = true
	movement.step(DT, grid)
	assert_true(movement.dash_started_this_frame, "a second dash is allowed")


func test_air_dashes_are_limited_in_the_air() -> void:
	var grid := _open_air_world()
	var movement := make_runner(grid)
	var config := movement.config
	var started := 0
	for attempt in config.air_dashes + 2:
		movement.body.teleport(Vector2(3.0 * TILE, 3.0 * TILE))
		movement.body.velocity = Vector2(0.0, 0.0)
		movement.dashes_used = attempt
		movement._dash_cooldown = 0.0
		movement.input.dash_pressed = true
		movement.input.move_x = 1.0
		movement.step(DT, grid)
		movement.input.dash_pressed = false
		if movement.dash_started_this_frame:
			started += 1
	assert_eq(started, config.air_dashes,
		"exactly the configured number of air dashes is granted")


func test_dash_progress_is_monotonic_while_dashing() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)

	var last := -1.0
	for _i in 120:
		if not movement.is_dashing:
			break
		var progress := movement.dash_progress()
		assert_gte(progress, last, "dash progress never goes backwards")
		assert_in_range(progress, 0.0, 1.0, "dash progress stays normalised")
		last = progress
		movement.input.dash_pressed = false
		movement.step(DT, grid)
	assert_gte(last, 0.9, "progress reaches the end of the dash before it finishes")


# --- landing ----------------------------------------------------------------

func test_landing_keeps_horizontal_momentum() -> void:
	# Running fast and landing must not scrub the run. A platformer where every
	# landing stops you dead feels like running through mud.
	#
	# The measurement isolates the LANDING frame. Comparing speed before the
	# drop against speed after the landing would instead be measuring air
	# deceleration, which is a different system with a different answer.
	var grid := World.flat_ground(80, 14, 3)
	var movement := make_runner(grid)
	hold(movement, 1.0, 60, grid)
	var run_speed := movement.body.velocity.x
	assert_gt(run_speed, 200.0, "the player is running fast before the drop")

	# Put them in the air above the floor, still moving fast.
	movement.body.teleport(Vector2(12.0 * TILE, 10.0 * TILE))
	movement.body.velocity.x = run_speed
	movement.input.move_x = 0.0

	var was_grounded := false
	var before := run_speed
	for _i in 300:
		was_grounded = movement.body.is_grounded()
		before = movement.body.velocity.x
		movement.step(DT, grid)
		var grounded := movement.body.is_grounded()
		if grounded and not was_grounded:
			var after := movement.body.velocity.x
			assert_gte(after, before * 0.9,
				"landing scrubs at most 10%% of horizontal speed (%.1f -> %.1f)"
				% [before, after])
			return
	ok(false, "the player never landed within 300 frames")


func test_high_speed_landing_bounces() -> void:
	var config := PlayerMovementConfig.new()
	var grid := World.flat_ground(60, 14, 3)
	var movement := make_runner(grid, config)
	# Start just above the floor at a speed already over the bounce threshold,
	# so the short fall cannot push it back under.
	movement.body.teleport(Vector2(3.0 * TILE, 12.0 * TILE))
	movement.body.velocity = Vector2(0.0, config.bounce_speed_threshold + 200.0)

	var bounced := false
	for _i in 300:
		movement.step(DT, grid)
		if movement.just_bounced:
			bounced = true
			break
	assert_true(bounced, "a landing above the bounce threshold rebounds the player")


func test_gentle_landing_does_not_bounce() -> void:
	var config := PlayerMovementConfig.new()
	var grid := World.flat_ground(60, 14, 3)
	var movement := make_runner(grid, config)
	# Start a few pixels above the floor: gravity only has a few frames to work
	# with, so the landing speed stays well under the bounce threshold.
	movement.body.teleport(Vector2(3.0 * TILE, 13.0 * TILE))
	movement.body.velocity = Vector2(0.0, 150.0)

	var landed := false
	var bounced := false
	for _i in 300:
		movement.step(DT, grid)
		if movement.just_bounced:
			bounced = true
		elif movement.body.is_grounded():
			landed = true
			break
	assert_true(landed, "the player lands")
	assert_false(bounced, "a gentle landing is absorbed, not bounced")


# --- state reporting --------------------------------------------------------

func test_speed_ratio_is_normalised_and_tracks_speed() -> void:
	var grid := World.flat_ground(80, 10, 3)
	var movement := make_runner(grid)
	assert_approx(movement.speed_ratio(), 0.0, 0.001, "a standing player has no speed ratio")

	hold(movement, 1.0, 90, grid)
	var ratio := movement.speed_ratio()
	assert_gte(ratio, 0.2, "a running player reports meaningful speed")
	assert_lte(ratio, 1.5, "speed ratio is clamped")


func test_state_reports_run_and_sprint() -> void:
	var grid := World.flat_ground(80, 10, 3)
	var movement := make_runner(grid)
	hold(movement, 1.0, 90, grid)
	var state := movement.state
	var is_moving_state: bool = state == GameTypes.PlayerState.RUN \
		or state == GameTypes.PlayerState.SPRINT
	assert_true(is_moving_state,
		"a running player reports RUN or SPRINT, got %s" % state)


func test_dash_state_is_reported() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	assert_eq(movement.state, GameTypes.PlayerState.DASH, "state is DASH while dashing")


# --- attack gating ----------------------------------------------------------

func test_attack_is_refused_while_attacking_and_while_dashing() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	assert_true(movement.try_attack(), "a grounded attack starts")
	assert_false(movement.try_attack(), "a second attack is refused while one is active")

	# Wait out the attack, then check dashing blocks it.
	step_for(movement, grid, 30)
	movement.input.dash_pressed = true
	movement.input.move_x = 1.0
	movement.step(DT, grid)
	assert_true(movement.is_dashing, "dashing")
	assert_false(movement.try_attack(), "an attack is refused during a dash")


func test_air_attack_is_distinguished_from_ground_attack() -> void:
	var grid := _open_air_world()
	var movement := make_runner(grid)
	movement.body.teleport(Vector2(3.0 * TILE, 3.0 * TILE))
	movement.step(DT, grid)
	assert_true(movement.try_attack(), "an air attack starts")
	assert_true(movement.is_attacking_air, "it is flagged as an air attack")
	assert_eq(movement.state, GameTypes.PlayerState.ATTACK_AIR, "state is ATTACK_AIR")


# --- configuration ----------------------------------------------------------

func test_default_config_is_playable() -> void:
	var problems := PlayerMovementConfig.new().validate()
	assert_empty(problems,
		"the shipped movement config produces a playable character: %s"
		% ", ".join(problems))


func test_config_validation_catches_unplayable_values() -> void:
	var config := PlayerMovementConfig.new()
	assert_empty(config.validate(), "the default config is clean")

	config.max_speed = 0.0
	assert_not_empty(config.validate(), "zero max speed is rejected")
	config.max_speed = 520.0

	config.jump_force = 500.0
	assert_not_empty(config.validate(),
		"an upward-positive jump force is rejected (down is positive)")
	config.jump_force = -790.0

	config.max_air_speed = config.max_speed + 1.0
	assert_not_empty(config.validate(), "flying faster than running is rejected")
	config.max_air_speed = 470.0

	config.max_fall_speed = config.max_speed
	assert_not_empty(config.validate(), "a fall no faster than a run is rejected")
	config.max_fall_speed = 1150.0

	assert_empty(config.validate(), "the config validates again once fixed")


func test_duplicate_config_is_independent() -> void:
	var original := PlayerMovementConfig.new()
	var copy := original.duplicate_config()
	assert_approx(copy.max_speed, original.max_speed, 0.001, "the copy starts identical")

	copy.max_speed = 1.0
	assert_approx(original.max_speed, 520.0, 0.001,
		"mutating the copy does not touch the shared default")
	assert_approx(copy.jump_force, original.jump_force, 0.001,
		"and every other field was carried over")


func test_assist_mode_widens_input_windows() -> void:
	var normal := PlayerMovementConfig.new()
	var assist := PlayerMovementConfig.new().with_assist_mode()
	assert_gte(assist.coyote_time, normal.coyote_time, "assist does not shrink coyote time")
	assert_gte(assist.jump_buffer_time, normal.jump_buffer_time,
		"assist does not shrink the jump buffer")
	assert_gte(assist.turn_boost, normal.turn_boost, "assist does not weaken turning")
	assert_empty(assist.validate(), "assist mode is still a valid config")


# --- environments -----------------------------------------------------------

func test_water_slows_the_player_down() -> void:
	var grid := World.flat_ground(60, 10, 3)
	var movement := make_runner(grid)
	var dry := make_runner(grid)
	hold(dry, 1.0, 90, grid)

	movement.input.in_water = true
	hold(movement, 1.0, 90, grid)
	assert_lt(movement.body.velocity.x, dry.body.velocity.x,
		"the player is slower in water than out of it")


func test_speed_zone_raises_the_speed_cap() -> void:
	var grid := World.flat_ground(90, 10, 3)
	var movement := make_runner(grid)
	var base := movement.config.max_speed
	movement.input.in_speed_zone = true
	hold(movement, 1.0, 180, grid)
	assert_gt(movement.body.velocity.x, base,
		"a speed zone lets the player exceed the normal cap")


# --- world helpers ----------------------------------------------------------

## A short ledge with open air to the right: solid up to column 11, nothing
## beyond it. Rows above the ledge must be empty or the body never gets airborne.
func _ledge_world() -> LevelData:
	var rows: Array = []
	for _y in 20:
		rows.append(".".repeat(40))
	rows[8] = "#".repeat(12) + ".".repeat(28)
	return World.make_grid(rows)


## Tall open air with a floor far below, so the player stays airborne.
func _open_air_world() -> LevelData:
	var rows: Array = []
	for _y in 30:
		rows.append(".".repeat(40))
	rows.append("#".repeat(40))
	rows.append("#".repeat(40))
	return World.make_grid(rows)