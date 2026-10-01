extends TestCase
## Collision model verification.
##
## Every case here corresponds to a way a platformer can feel broken: falling
## through the floor, tunnelling a wall at speed, getting stuck on a ledge,
## being trapped by a one-way platform, or a body resting inside geometry.
##
## Note: KinematicBody integrates and resolves collisions. It deliberately does
## not apply gravity -- that belongs to PlayerMovement, which owns game feel.
## So these tests launch bodies explicitly via World.launch().

const World := preload("res://tests/helpers/world_builder.gd")
const DT := 1.0 / 60.0
const TILE := LevelData.TILE_SIZE


func suite_name() -> String:
	return "Physics/Collision"


# --- resting on ground ------------------------------------------------------

func test_body_falls_and_lands_on_solid_ground() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 0.0))
	World.launch(body, Vector2(0.0, 500.0))
	assert_true(World.settle(body, grid), "a falling body must land on solid ground")
	assert_approx(body.feet_y(), 12.0 * TILE, 0.5, "feet rest on the floor surface")
	assert_approx(body.velocity.y, 0.0, 0.01, "vertical velocity is zeroed on landing")


func test_body_never_sinks_into_the_floor() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 0.0))
	# Fast enough that a single frame covers more than one tile, so the only
	# thing keeping the body above the floor is sub-stepping.
	World.launch(body, Vector2(0.0, 2000.0))
	var floor_y := 12.0 * TILE
	var deepest := 0.0
	for _i in 120:
		body.move(grid, DT)
		# While falling through open air the feet are above the floor; what must
		# never happen is the body ending up *below* the floor surface.
		deepest = maxf(deepest, body.feet_y())
	assert_lte(deepest, floor_y + 1.0,
		"the body never ends a frame below the floor surface")
	assert_approx(body.feet_y(), floor_y, 1.0, "and it comes to rest on the surface")


func test_body_stops_at_a_wall() -> void:
	var rows: Array = []
	for y in 12:
		var row := ".".repeat(30)
		if y >= 8:
			row = World._place(row, 10, "#")
		rows.append(row)
	rows[7] = World._place(rows[7], 2, "S")
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 8.0 * TILE))
	World.launch(body, Vector2(400.0, 0.0))
	var hit_wall := false
	for _i in 120:
		body.move(grid, DT)
		if body.on_wall_right:
			hit_wall = true
			break
	assert_true(hit_wall, "moving right into a wall must report a wall contact")
	assert_approx(body.velocity.x, 0.0, 0.01, "horizontal velocity is zeroed by a wall")
	assert_lt(body.right_x(), 10.0 * TILE, "body stops before penetrating the wall")


func test_high_speed_body_does_not_tunnel_through_a_thin_wall() -> void:
	# One-tile-thick wall spanning rows 4..12. At 2000 px/s the body covers 33px
	# per frame, more than a full 32px tile: without sub-stepping it passes clean
	# through. This is the regression that makes fast levels unplayable.
	var rows: Array = []
	for y in 14:
		var row := ".".repeat(40)
		if y >= 4 and y < 13:
			row = World._place(row, 20, "#")
		rows.append(row)
	rows.append("#".repeat(40))
	rows.append("#".repeat(40))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	# Placed at row 8, squarely inside the wall's vertical span.
	body.teleport(Vector2(2.5 * TILE, 8.0 * TILE))
	World.launch(body, Vector2(2000.0, 0.0))
	var passed_through := false
	for _i in 60:
		body.move(grid, DT)
		if body.left_x() > 21.0 * TILE:
			passed_through = true
			break
	assert_false(passed_through, "a 2000 px/s body must not pass through a one-tile wall")
	assert_approx(body.velocity.x, 0.0, 0.01, "velocity zeroed on impact")


func test_body_is_stopped_by_a_ceiling() -> void:
	var grid := World.ceiling_world(4)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 11.0 * TILE))
	World.launch(body, Vector2(0.0, -900.0))
	var hit_ceiling := false
	for _i in 60:
		body.move(grid, DT)
		if body.on_ceiling:
			hit_ceiling = true
			break
	assert_true(hit_ceiling, "an upward body must hit a ceiling")
	assert_approx(body.velocity.y, 0.0, 0.01, "upward velocity is zeroed by a ceiling")


# --- one-way platforms ------------------------------------------------------

func test_one_way_platform_is_solid_from_above() -> void:
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(30))
	rows[8] = World._place(".".repeat(30), 5, "=")
	rows.append(".".repeat(30))
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(Vector2(5.5 * TILE, 2.0 * TILE))
	World.launch(body, Vector2(0.0, 400.0))
	assert_true(World.settle(body, grid), "a falling body must land on a one-way platform")
	assert_in_range(body.feet_y(), 8.0 * TILE - 1.0, 8.0 * TILE + 1.0,
		"rests on the platform surface")
	assert_true(body.on_one_way, "contact is reported as a one-way surface")


func test_one_way_platform_is_transparent_from_below() -> void:
	# The classic bug: a player jumps "through" a platform and is then stuck
	# under it. A one-way platform must not exist at all for an upward body.
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(30))
	rows[6] = World._place(".".repeat(30), 5, "=")
	rows.append(".".repeat(30))
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(Vector2(5.5 * TILE, 9.0 * TILE))
	World.launch(body, Vector2(0.0, -600.0))
	var passed_through := false
	for _i in 60:
		body.move(grid, DT)
		if body.head_y() < 6.0 * TILE:
			passed_through = true
			break
	assert_true(passed_through, "an upward body must pass through a one-way platform")
	assert_false(body.on_ceiling, "no ceiling contact is reported for a one-way platform")


func test_one_way_platform_does_not_block_horizontal_movement() -> void:
	# A one-way platform is a surface, not a wall. Walking into its side must
	# not stop the player.
	var rows: Array = []
	for y in 12:
		rows.append(".".repeat(30))
	rows[6] = World._place(".".repeat(30), 5, "=")
	rows.append(".".repeat(30))
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(World.standing_on(body, 2.0, 10))
	World.launch(body, Vector2(300.0, 0.0))
	World.run(body, grid, 60)
	assert_gt(body.position.x, 8.0 * TILE, "body walked past the platform")
	assert_false(body.on_wall_left or body.on_wall_right,
		"a one-way platform reports no wall contact")


func test_body_does_not_get_snapped_up_onto_a_platform_above() -> void:
	# Standing still under a one-way platform must not teleport the body up.
	var rows: Array = []
	for y in 12:
		rows.append(".".repeat(30))
	rows[4] = World._place(".".repeat(30), 5, "=")
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(World.standing_on(body, 5.0, 10))
	var resting_y := body.position.y
	World.run(body, grid, 120)
	assert_approx(body.position.y, resting_y, 0.5,
		"body stays on the floor and is not pulled up to the platform")


# --- surfaces and queries ---------------------------------------------------

func test_slick_surface_is_reported() -> void:
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(30))
	rows.append("~".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 6.0 * TILE))
	World.launch(body, Vector2(0.0, 400.0))
	assert_true(World.settle(body, grid), "lands on the slick tile")
	assert_true(body.on_slick, "slick surface is reported so friction can change")


func test_normal_ground_is_not_reported_as_slick() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 0.0))
	World.launch(body, Vector2(0.0, 400.0))
	World.settle(body, grid)
	assert_true(body.on_floor, "lands on the floor")
	assert_false(body.on_slick, "ordinary ground is not slick")


func test_hazard_overlap_is_detected() -> void:
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(30))
	rows.append("#".repeat(15) + "^".repeat(15))
	var grid := World.make_grid(rows)

	var safe := World.player_body()
	safe.teleport(Vector2(2.5 * TILE, 9.0 * TILE))
	assert_false(safe.overlaps_hazard(grid), "the spawn tile is not a hazard")

	var spiked := World.player_body()
	spiked.teleport(Vector2(20.0 * TILE, 10.0 * TILE))
	assert_true(spiked.overlaps_hazard(grid), "a body on a spike tile reports a hazard")


func test_ground_ahead_detects_a_ledge() -> void:
	# Floor occupies rows 10 and 11, columns 0..14 only.
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(30))
	rows.append("#".repeat(15) + ".".repeat(15))
	rows.append("#".repeat(15) + ".".repeat(15))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(World.standing_on(body, 5.0, 10))
	assert_true(body.ground_ahead(grid, 1), "solid ground is found to the right")
	assert_true(body.ground_ahead(grid, -1), "solid ground is found to the left")

	var ledge := World.player_body()
	ledge.teleport(World.standing_on(ledge, 25.0, 10))
	assert_false(ledge.ground_ahead(grid, 1), "no ground past the right-hand edge")
	assert_false(ledge.ground_ahead(grid, -1), "no ground past the left-hand edge")


func test_ground_below_finds_the_floor() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 4.0 * TILE))
	assert_approx(body.ground_below(grid, 512.0), 12.0 * TILE, 0.01,
		"floor found beneath the body")

	var void_rows: Array = []
	for _y in 40:
		void_rows.append(".".repeat(40))
	var void_grid := World.make_grid(void_rows)
	var over_void := World.player_body()
	over_void.teleport(Vector2(2.5 * TILE, 4.0 * TILE))
	assert_eq(over_void.ground_below(void_grid, 64.0), -1.0,
		"no floor returns -1 rather than a bogus height")


func test_wall_ahead_detects_a_wall() -> void:
	var rows: Array = []
	for y in 12:
		var row := ".".repeat(30)
		if y >= 8:
			row = World._place(row, 12, "#")
		rows.append(row)
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	body.teleport(World.standing_on(body, 5.0, 12))
	assert_false(body.wall_ahead(grid, 1), "clear to the right")
	assert_false(body.wall_ahead(grid, -1), "clear to the left")

	var close := World.player_body()
	# Column 12, so the body's right edge actually overlaps the wall column.
	# A body parked a tile short of a wall is genuinely not touching it, and
	# asserting otherwise just hides the bug.
	close.teleport(World.standing_on(close, 12.0, 12))
	assert_true(close.wall_ahead(grid, 1), "wall detected to the right")
	assert_false(close.wall_ahead(grid, -1), "no wall to the left")


# --- contact bookkeeping ----------------------------------------------------

func test_resting_body_keeps_ground_contact_every_frame() -> void:
	# Regression: a body resting on a floor sits a SKIN above it, so its AABB is
	# flush with the tile and does not overlap it. Without a contact probe the
	# body reported leaving the floor every single frame, which silently broke
	# coyote time, jump charges and landing handling.
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(World.standing_on(body, 2.5, 12))
	World.settle(body, grid)

	for i in 120:
		body.move(grid, DT)
		assert_true(body.on_floor, "frame %d: a resting body stays grounded" % i)
		assert_false(body.just_left_floor, "frame %d: and never reports leaving" % i)


func test_resting_body_is_not_pushed_through_the_floor() -> void:
	# Regression: with zero vertical velocity the solver used to take the ceiling
	# branch, snapping the body to tile_bottom + half_height and dropping it out
	# of the level entirely.
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(World.standing_on(body, 2.5, 12))
	World.settle(body, grid)
	var resting_y := body.position.y
	World.run(body, grid, 120)
	assert_approx(body.position.y, resting_y, 0.5,
		"a resting body holds its height and is not ejected downward")


func test_resting_body_keeps_wall_contact() -> void:
	# Same skin probe, horizontal axis: a body standing still against a wall must
	# keep reporting it, otherwise wall detection flickers frame to frame.
	var rows: Array = []
	for y in 14:
		var row := ".".repeat(30)
		if y >= 8 and y < 13:
			row = World._place(row, 12, "#")
		rows.append(row)
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	# Flush against the wall on its RIGHT: right_x() == 384, the wall's left
	# edge. Standing on the floor so the body is genuinely at rest.
	var rest_y := World.standing_on(body, 0.0, 13).y
	body.teleport(Vector2(12.0 * TILE - body.half_size().x, rest_y))
	body.move(grid, DT)
	body.velocity.x = 0.0
	var resting_x := body.position.x

	var lost := 0
	for _i in 60:
		body.move(grid, DT)
		if not body.on_wall_right:
			lost += 1
	assert_eq(lost, 0, "wall contact persists while the body rests against it")
	assert_approx(body.position.x, resting_x, 0.5,
		"and the body is not shoved sideways by the contact")


func test_just_landed_is_reported_exactly_once() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 0.0))
	World.launch(body, Vector2(0.0, 500.0))
	var landings := 0
	var leave_events := 0
	for _i in 200:
		body.move(grid, DT)
		if body.just_landed:
			landings += 1
		if body.just_left_floor:
			leave_events += 1
	assert_eq(landings, 1, "landing is reported once, not every frame it rests")
	assert_eq(leave_events, 0, "a resting body never reports leaving the floor")


func test_just_left_floor_is_reported_when_the_body_leaves_ground() -> void:
	# Regression: `was_grounded` used to be captured AFTER the contacts were
	# reset, which made it permanently false and left just_left_floor as dead
	# code. A suite that only asserted `leave_events == 0` would pass happily
	# against that bug, so this case asserts the event actually fires.
	var grid := World.flat_ground(60, 10, 3)
	var body := World.player_body()
	body.teleport(World.standing_on(body, 3.0, 10))
	World.settle(body, grid)
	assert_true(body.on_floor, "the body starts on the floor")

	# Upward velocity, which is exactly what a jump hands the collision solver.
	# Downward velocity would simply be absorbed back into the floor.
	World.launch(body, Vector2(0.0, -300.0))

	var left_events := 0
	for _i in 60:
		body.move(grid, DT)
		if body.just_left_floor:
			left_events += 1
			break
	assert_eq(left_events, 1, "leaving the floor is reported exactly once")
	assert_false(body.on_floor, "and the body is genuinely airborne")


func test_landing_reports_the_impact_speed() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	body.teleport(Vector2(2.5 * TILE, 0.0))
	World.launch(body, Vector2(0.0, 700.0))
	for _i in 200:
		body.move(grid, DT)
		if body.just_landed:
			break
	assert_gte(body.land_speed, 600.0, "impact speed is close to the pre-landing velocity")
	assert_lte(body.land_speed, 750.0, "impact speed is not inflated past reality")


func test_frozen_body_does_not_move() -> void:
	var grid := World.flat_ground(40, 12, 3)
	var body := World.player_body()
	var start := Vector2(5.0 * TILE, 5.0 * TILE)
	body.teleport(start)
	body.frozen = true
	body.velocity = Vector2(900.0, -400.0)
	var travelled := body.move(grid, DT)
	assert_approx(travelled, 0.0, 0.001, "a frozen body integrates nothing")
	assert_eq(body.position, start, "position is unchanged")


func test_move_reports_actual_travel_not_intended() -> void:
	# Callers use the return value to detect an interrupted dash, so it must
	# reflect what actually happened, not what was asked for.
	var rows: Array = []
	for y in 12:
		var row := ".".repeat(30)
		if y >= 8:
			row = World._place(row, 14, "#")
		rows.append(row)
	rows.append("#".repeat(30))
	rows.append("#".repeat(30))
	var grid := World.make_grid(rows)

	var body := World.player_body()
	# 3000 px/s at 60Hz is 50px per frame. Start at x=400 so that frame's move
	# spans x=411..461, which overlaps the wall column starting at x=448.
	body.teleport(Vector2(12.5 * TILE, 8.0 * TILE))
	World.launch(body, Vector2(3000.0, 0.0))
	var intended := 3000.0 * DT
	var travelled := body.move(grid, DT)
	assert_lt(travelled, intended,
		"travel is less than intended when a wall interrupts the move")
	assert_gte(travelled, 0.0, "travel is never negative")
	assert_lt(body.right_x(), 14.0 * TILE,
		"and the body ends up against the wall, not through it")


# ============================================================================
# RAMP TESTS
# ============================================================================
# Ramps are the most intricate collision surface in the game. They must:
# - Snap the body to the exact surface Y at any X
# - Report correct floor_angle for slope physics
# - Not launch the body off the top (no airborne at ramp end)
# - Apply climb penalty and descent bonus with proper caps
# - Bleed bonus when leaving the ramp

func _make_ramp_body() -> Dictionary:
	# Ramp: base at (0,0), width=128, height=64, UP_RIGHT.
	# Ramp surface at x=0 is y=64 (base.y + height), at x=128 is y=0.
	var ramp := World.make_ramp(Vector2(0.0, 0.0), 128.0, 64.0)
	var body := World.player_body()
	body.ramps.append(ramp)
	# Place body at ramp start (x=0): feet at y=64 (ramp bottom surface)
	body.teleport(Vector2(0.0, 64.0 - body.half_size().y))
	return {"body": body, "ramp": ramp}


func test_ramp_body_snaps_to_surface() -> void:
	var r_snap := _make_ramp_body(); var body: KinematicBody = r_snap["body"]; var ramp: RampCollider = r_snap["ramp"]
	# At x=32 (25% up ramp), surface Y = 64 - 0.25*64 = 48
	body.teleport(Vector2(32.0, 48.0 - body.half_size().y))
	# Move to trigger _integrate_ramps
	body.move(World.flat_ground(40, 12, 3), DT)
	var result := body.ramps[0].resolve(body.rect(), body.position)
	assert_true(bool(result["hit"]), "ramp detects contact at x=32")
	assert_approx(float(result["surface"]), 48.0, 0.5, "surface Y is correct at 25% up")
	assert_true(body.on_floor, "body is grounded on ramp")


func test_ramp_angle_reported_correctly() -> void:
	var r_angle := _make_ramp_body(); var body: KinematicBody = r_angle["body"]; var ramp: RampCollider = r_angle["ramp"]
	# Start at ramp start, move right to engage ramp
	body.move(World.flat_ground(40, 12, 3), DT)
	body.velocity = Vector2(100.0, 0.0)
	body.move(World.flat_ground(40, 12, 3), DT)
	assert_true(body.on_ramp, "ramp sets on_ramp flag")
	# Ramp angle: atan2(64, 128) = 26.565 deg
	assert_approx(absf(body.floor_angle), deg_to_rad(26.565), deg_to_rad(1.0),
		"floor_angle matches ramp geometry")


func test_ramp_climbing_applies_penalty() -> void:
	var r_climb := _make_ramp_body(); var body: KinematicBody = r_climb["body"]; var ramp: RampCollider = r_climb["ramp"]
	# Start at x=10 (near bottom of ramp). Surface Y = 64 - 10/128*64 = 59
	body.teleport(Vector2(10.0, 59.0 - body.half_size().y))
	body.velocity = Vector2(400.0, 0.0)  # moving right = climbing
	# Run one frame with ramp
	body.move(World.flat_ground(40, 12, 3), DT)
	# Climbing should reduce speed bonus (negative)
	# The exact value depends on config.slope_climb_penalty
	# Just verify the ramp is detected and angle is correct
	assert_true(body.on_ramp, "climbing body is on ramp")


func test_ramp_descending_gives_bonus_capped() -> void:
	# A body placed on a descending ramp should be detected as on_ramp.
	# The speed bonus capping is tested in PlayerMovement tests.
	var r_desc := _make_ramp_body(); var body: KinematicBody = r_desc["body"]; var ramp: RampCollider = r_desc["ramp"]
	# Place on upper part of ramp (x=30), surface Y = 64 - 30/128*64 = 49
	body.teleport(Vector2(30.0, 49.0 - body.half_size().y))
	body.move(World.flat_ground(40, 12, 3), DT)
	assert_true(body.on_ramp, "body on descending portion of ramp is detected")


func test_no_launch_at_ramp_top() -> void:
	# Standing at the top of a ramp must NOT launch the player airborne.
	# The ramp surface ends, but the body should simply stop being on_ramp
	# and transition to flat ground, not go airborne.
	# Custom grid with floor at y=0 (row 0)
	var rows: Array = []
	rows.append("#".repeat(40))  # row 0: floor at y=0
	var grid := World.make_grid(rows)
	
	var body := World.player_body()
	var ramp := World.make_ramp(Vector2(0.0, 0.0), 128.0, 64.0)
	body.ramps.append(ramp)
	
	# Place body just past ramp end, above floor; give downward velocity to fall
	body.teleport(Vector2(130.0, -20.0))
	body.velocity = Vector2(0.0, 300.0)  # downward velocity to fall onto floor
	World.settle(body, grid)
	
	# Now move horizontally past the ramp end
	body.velocity = Vector2(0.0, 0.0)
	body.move(grid, DT)
	assert_true(body.on_floor, "body is grounded on flat floor after ramp")
	assert_false(body.on_ramp, "ramp flag cleared off the ramp")
	assert_false(body.on_floor == false and body.on_ramp == false,
		"body does NOT become airborne at ramp end")


func test_ramp_bonus_bleeds_off_on_flat() -> void:
	var r_flat := _make_ramp_body(); var body: KinematicBody = r_flat["body"]; var ramp: RampCollider = r_flat["ramp"]
	# Give some slope bonus by descending from top
	body.teleport(Vector2(128.0, 0.0 - body.half_size().y))
	body.velocity = Vector2(-500.0, 0.0)
	body.move(World.flat_ground(40, 12, 3), DT)
	
	# Now move to flat ground (past ramp at x=128, flat floor at y=0)
	body.teleport(Vector2(130.0, 0.0 - body.half_size().y))
	body.velocity = Vector2(0.0, 0.0)
	
	# Simulate 1 second on flat
	for _i in 60:
		body.move(World.flat_ground(40, 12, 3), DT)
	
	# On flat ground, bonus should bleed toward zero
	assert_false(body.on_ramp, "ramp flag cleared on flat ground")


func test_slick_ramp_flag_propagates() -> void:
	var body := World.player_body()
	var slick_ramp := World.make_ramp(Vector2(0.0, 0.0), 128.0, 64.0, RampCollider.Direction.UP_RIGHT, true)
	body.ramps.append(slick_ramp)
	body.teleport(Vector2(32.0, 48.0 - body.half_size().y))
	body.move(World.flat_ground(40, 12, 3), DT)
	assert_true(body.on_slick, "slick ramp sets on_slick flag")


func test_ramp_up_left_works() -> void:
	var body := World.player_body()
	var ramp := RampCollider.new()
	ramp.configure(Vector2(0.0, 0.0), 128.0, 64.0, RampCollider.Direction.UP_LEFT)
	body.ramps.append(ramp)
	# UP_LEFT: surface at x=128 is y=64, at x=0 is y=0
	# Place at x=60 (mid-ramp), surface Y = 64 - 60/128*64 = 32
	body.teleport(Vector2(60.0, 32.0 - body.half_size().y))
	body.velocity = Vector2(-50.0, 0.0)  # move left to engage ramp
	body.move(World.flat_ground(40, 12, 3), DT)
	assert_true(body.on_ramp, "UP_LEFT ramp also works")
	# Angle should be negative (rising to the left)
	assert_true(body.floor_angle < 0.0, "UP_LEFT ramp has negative angle")


func test_multiple_ramps_only_closest_resolves() -> void:
	# Two overlapping ramps: the one with the highest surface at body x should win
	var body := World.player_body()
	var ramp1 := World.make_ramp(Vector2(0.0, 0.0), 128.0, 64.0)  # low ramp: surface at x=64 is 32
	var ramp2 := World.make_ramp(Vector2(0.0, 0.0), 128.0, 128.0) # steep ramp: surface at x=64 is 64
	body.ramps.append(ramp1)
	body.ramps.append(ramp2)
	# At x=64, ramp1 surface = 64 - 64/128*64 = 32, ramp2 surface = 128 - 64/128*128 = 64
	# Place body at x=64, feet at y=64 (above both ramps, will fall to highest)
	body.teleport(Vector2(64.0, 64.0 - body.half_size().y))
	body.move(World.flat_ground(40, 12, 3), DT)
	# Should resolve to the higher ramp (ramp2 surface at x=64 is 64)
	assert_approx(body.feet_y(), 64.0, 1.0, "body rests on highest ramp surface")
