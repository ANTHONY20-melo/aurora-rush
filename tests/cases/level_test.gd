extends TestCase
## Integration tests for real content: the level JSON, the level scene, and the
## player running against actual terrain.
##
## The physics and movement suites prove the rules are correct against grids
## built by hand inside the test. This suite proves the shipped content parses,
## the scene wires itself together, and the player can traverse the level a
## player would download. A green movement suite over a broken level file is
## still an unplayable game.

const LEVEL_SCENE := "res://scenes/levels/Level.tscn"
const LEVEL_ID := "zone01_01"
const DT := 1.0 / 60.0
const GAP_END_COL := 36.0


func suite_name() -> String:
	return "Content/Level"


## Build the level scene for real: this runs _ready, which loads the level data,
## draws the terrain and spawns the player.
func _open_level() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "no scene tree available for the level test")
	if tree == null:
		return null

	ContentDB.ensure_loaded()
	SceneDirector.current_level_id = LEVEL_ID

	var packed: PackedScene = load(LEVEL_SCENE)
	assert_not_null(packed, "Level.tscn failed to load")
	if packed == null:
		return null

	var level: Node = packed.instantiate()
	tree.root.add_child(level)
	return level


func _close_level(level: Node) -> void:
	if level == null:
		return
	# Remove from the tree before freeing: the level's _physics_process must not
	# get another frame against a half-destroyed state.
	if level.get_parent() != null:
		level.get_parent().remove_child(level)
	level.free()


func _player_of(level: Node) -> PlayerController:
	if level == null:
		return null
	return level.get("player") as PlayerController


func _data_of(level: Node) -> LevelData:
	if level == null:
		return null
	return level.get("level") as LevelData


## Drive the player with scripted intent, exactly as PlayerController does, but
## without waiting on real frames.
func _drive(player: PlayerController, data: LevelData, frames: int, axis: float,
		jump_on_first: bool = false) -> void:
	for i in frames:
		player.movement.input = PlayerInput.from_axes(
			axis, jump_on_first and i == 0, false, false, false, false, false)
		player.movement.step(DT, data)


func test_shipped_level_loads_and_is_valid() -> void:
	ContentDB.ensure_loaded()
	assert_true(ContentDB.has_level(LEVEL_ID), "the shipped level is registered")
	var data: LevelData = ContentDB.get_level(LEVEL_ID)
	assert_not_null(data, "level data is returned")
	if data == null:
		return
	assert_true(data.is_valid(), "level has no validation errors: %s"
		% ", ".join(data.errors))
	assert_eq(data.grid.size(), 18, "grid has 18 rows")
	assert_eq(int(data.grid[0].length()), 100, "every row is 100 columns wide")
	assert_gt(data.world_width, 0.0, "world width was computed")
	assert_point_parsed(data.spawn_point, "the spawn point was parsed")
	assert_point_parsed(data.exit_point, "the exit point was parsed")


func test_level_has_standable_ground_under_the_spawn() -> void:
	ContentDB.ensure_loaded()
	var data: LevelData = ContentDB.get_level(LEVEL_ID)
	if data == null:
		nope("level data missing")
		return
	var col := int(data.spawn_point.x / LevelData.TILE_SIZE)
	assert_true(data.tile_is_solid(col, 13) or data.tile_is_solid(col, 14),
		"there is solid ground beneath the spawn column %d" % col)


func test_level_scene_spawns_a_player_standing_on_ground() -> void:
	var level := _open_level()
	if level == null:
		return
	var data: LevelData = _data_of(level)
	var player: PlayerController = _player_of(level)
	assert_not_null(data, "the level resolved its data")
	assert_not_null(player, "the level spawned a player")
	if player != null and data != null:
		assert_true(player.body.is_grounded(),
			"the player is grounded on the first frame at the spawn")
		assert_approx(player.body.position.x, data.spawn_point.x, 2.0,
			"the player starts at the spawn x")
	_close_level(level)


func test_player_runs_right_and_travels_grounded() -> void:
	var level := _open_level()
	var player: PlayerController = _player_of(level)
	var data: LevelData = _data_of(level)
	if player == null or data == null:
		nope("level setup failed: player or level data is missing")
		_close_level(level)
		return
	var start_x: float = player.body.position.x
	_drive(player, data, 60, 1.0)
	var end_x: float = player.body.position.x
	assert_gt(end_x - start_x, 100.0, "holding right moves the player a real distance")
	assert_true(player.body.is_grounded(), "and the player stays on the ground")
	_close_level(level)


func test_player_jumps_over_the_first_gap() -> void:
	# The level opens with a 4-tile pit at columns 32..35. Running right and
	# jumping has to clear it: the single most important traversal claim the
	# shipped content makes.
	#
	# Driven by position, not by a fixed frame count. Counting frames couples the
	# test to acceleration tuning, so a retune of max_speed would break a test
	# that was never about speed.
	var level := _open_level()
	var player: PlayerController = _player_of(level)
	var data: LevelData = _data_of(level)
	if player == null or data == null:
		nope("level setup failed: player or level data is missing")
		_close_level(level)
		return

	var pit_left: float = 32.0 * LevelData.TILE_SIZE
	var pit_right: float = 36.0 * LevelData.TILE_SIZE
	var jump_from: float = pit_left - 5.0 * LevelData.TILE_SIZE

	# 1. Run up to a launch point short of the edge.
	for _i in 600:
		player.movement.input = PlayerInput.from_axes(1.0, false, false, false,
			false, false, false)
		player.movement.step(DT, data)
		if player.body.position.x >= jump_from:
			break
	assert_gte(player.body.position.x, jump_from,
		"the player reached the launch point before the pit")

	# 2. Jump and keep holding right until they land beyond the far edge.
	var landed_beyond := false
	for i in 180:
		player.movement.input = PlayerInput.from_axes(1.0, i == 0, false, false,
			false, false, false)
		player.movement.step(DT, data)
		if i > 4 and player.body.is_grounded() and player.body.position.x > pit_right:
			landed_beyond = true
			break

	assert_true(landed_beyond,
		"the player cleared the pit and landed beyond x=%.0f (ended at x=%.0f)"
			% [pit_right, player.body.position.x])
	_close_level(level)


func test_idle_player_does_not_sink_through_the_floor() -> void:
	# Standing still for two seconds must not accumulate downward drift: the
	# resting-contact regression, verified at level scale.
	var level := _open_level()
	var player: PlayerController = _player_of(level)
	var data: LevelData = _data_of(level)
	if player == null or data == null:
		nope("level setup failed: player or level data is missing")
		_close_level(level)
		return
	var start_y: float = player.body.position.y
	_drive(player, data, 120, 0.0)
	assert_approx(player.body.position.y, start_y, 1.0, "an idle player holds their height")
	assert_true(player.body.is_grounded(), "and stays grounded")
	_close_level(level)


func test_player_does_not_pass_through_solid_ground_when_standing() -> void:
	# Drop the player from high above the floor and confirm the floor stops it,
	# rather than the tile grid being ignored by the scene wiring.
	var level := _open_level()
	var player: PlayerController = _player_of(level)
	var data: LevelData = _data_of(level)
	if player == null or data == null:
		nope("level setup failed: player or level data is missing")
		_close_level(level)
		return
	player.body.teleport(data.spawn_point - Vector2(0.0, 200.0))
	for _i in 180:
		player.movement.input = PlayerInput.neutral()
		player.movement.step(DT, data)
	assert_true(player.body.is_grounded(), "the fall ended on solid ground")
	assert_lte(player.body.position.y, data.spawn_point.y + 40.0,
		"and the body never sank far below the floor surface")
	_close_level(level)


## Assert a spawn/exit marker was actually parsed rather than left at the default.
func assert_point_parsed(point: Vector2, message: String) -> void:
	ok(point != Vector2.ZERO, "expected a parsed point, got the zero default -- " + message)