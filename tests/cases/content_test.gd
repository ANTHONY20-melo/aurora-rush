extends TestCase
## Content integrity: every shipped level must actually be playable, every
## animation must cover every rig node, and every scene the SceneDirector can
## navigate to must exist on disk.
##
## These are the three classes of bug that make a build look finished and play
## like nothing: a level with no spawn, an animation that freezes one limb, a
## menu button pointing at a scene that was never written.

const LEVEL_DIR := "res://src/data/levels/zone01/"
const EXPECTED_LEVELS := [
	"zone01_01", "zone01_02", "zone01_03", "zone01_04", "zone01_boss",
]

## Poses every animation must drive. If an animation omits one of these, the node
## keeps whatever pose the previous state left it in -- AnimationPlayer does not
## blend, so an uncovered limb freezes mid-stride.
const RIG_PROPS := [
	"Visual/Head:position",
	"Visual/Body:position",
	"Visual/Body:scale",
	"Visual/ArmLeft:position",
	"Visual/ArmRight:position",
	"Visual/LegLeft:position",
	"Visual/LegRight:position",
	"Visual:rotation",
]

## Tint is not a pose: only the damage flash needs it. Every other animation
## leaves the colour alone, so requiring it everywhere would be noise.
const TINT_PROP := "Visual:modulate"

const ANIMATIONS := ["idle", "run", "jump", "fall", "dash", "attack", "hurt"]


func suite_name() -> String:
	return "content"


# --- levels ----------------------------------------------------------------

func test_all_zone01_levels_load() -> void:
	# Existence alone proves nothing -- an empty or truncated JSON file still
	# exists. Parse every one, so a missing level fails here rather than at
	# runtime when a player picks it from the map.
	var files := DirAccess.get_files_at(LEVEL_DIR)
	var found := {}
	for file_name in files:
		if file_name.ends_with(".json"):
			found[file_name.trim_suffix(".json")] = true
	for expected in EXPECTED_LEVELS:
		assert_true(found.has(expected), "missing level file %s.json" % expected)
		if not found.has(expected):
			continue
		var text := FileAccess.get_file_as_string(LEVEL_DIR + expected + ".json")
		var parsed = JSON.parse_string(text)
		assert_true(parsed is Dictionary,
			"%s.json is not a JSON object" % expected)
		if not (parsed is Dictionary):
			continue
		assert_eq(String(parsed.get("id", "")), expected,
			"%s.json declares a mismatched id" % expected)


func test_every_level_parses_without_errors() -> void:
	for level_id in EXPECTED_LEVELS:
		var level := _load_level(level_id)
		assert_not_null(level, "%s: LevelData.from_dict returned null" % level_id)
		if level == null:
			continue
		assert_true(level.errors.is_empty(),
			"%s: parser reported %s" % [level_id, str(level.errors)])
		assert_true(level.is_valid(), "%s: is_valid() is false" % level_id)


func test_every_level_has_spawn_and_exit() -> void:
	for level_id in EXPECTED_LEVELS:
		var level := _load_level(level_id)
		if level == null:
			nope("%s: LevelData.from_dict returned null" % level_id)
			continue
		# Vector2.ZERO means the glyph was never found -- LevelData's own error
		# path for "no player spawn".
		assert_ne(level.spawn_point, Vector2.ZERO, "%s: no S (spawn) in grid" % level_id)
		assert_ne(level.exit_point, Vector2.ZERO, "%s: no E (exit) in grid" % level_id)


func test_every_level_has_standable_ground_under_spawn() -> void:
	for level_id in EXPECTED_LEVELS:
		var level := _load_level(level_id)
		if level == null:
			continue
		var spawn_x := int(level.spawn_point.x / LevelData.TILE_SIZE)
		var spawn_y := int(level.spawn_point.y / LevelData.TILE_SIZE)
		var supported := false
		for probe in range(spawn_y + 1, spawn_y + 4):
			if level.tile_is_solid(spawn_x, probe) or level.tile_is_one_way(spawn_x, probe):
				supported = true
				break
		assert_true(supported,
			"%s: nothing standable within 3 tiles below the spawn at %s"
			% [level_id, str(level.spawn_point)])


func test_boss_level_spawns_the_boss() -> void:
	# A boss arena with no B glyph silently becomes an empty room. This is the
	# exact shape of the bug that shipped: valid JSON, parses fine, no boss.
	var level := _load_level("zone01_boss")
	if level == null:
		nope("LevelData.from_dict returned null")
		return
	assert_true(level.has_boss, "zone01_boss: has_boss is false (no B glyph in grid)")
	assert_ne(level.boss_trigger, Vector2.ZERO, "zone01_boss: boss_trigger never set")


func test_boss_trigger_is_reachable_not_buried() -> void:
	# has_boss == true only proves the glyph exists. A B buried under four rows of
	# solid floor sets has_boss and instantiates the boss inside a wall where the
	# player can never touch it. The trigger has to sit on standable ground.
	var level := _load_level("zone01_boss")
	if level == null:
		nope("LevelData.from_dict returned null")
		return
	var col := int(level.boss_trigger.x / LevelData.TILE_SIZE)
	var row := int(level.boss_trigger.y / LevelData.TILE_SIZE)
	var standable_below := false
	for probe in range(row + 1, row + 4):
		if level.tile_is_solid(col, probe) or level.tile_is_one_way(col, probe):
			standable_below = true
			break
	assert_true(standable_below,
		"boss trigger at row %d col %d has nothing standable within 3 tiles below it"
		% [row, col])


func test_boss_arena_walkable_span_reaches_both_ends() -> void:
	# The player walks along one surface; the trigger and the exit have to share
	# it, otherwise the level cannot be finished. Both are checked for ground and
	# for a clear tile at the actor's own row between them.
	var level := _load_level("zone01_boss")
	if level == null:
		nope("LevelData.from_dict returned null")
		return
	var spawn_col := int(level.spawn_point.x / LevelData.TILE_SIZE)
	var boss_col := int(level.boss_trigger.x / LevelData.TILE_SIZE)
	var exit_col := int(level.exit_point.x / LevelData.TILE_SIZE)
	# spawn_point uses "base" (the row below the glyph); boss_trigger uses the
	# glyph's own "center". The actor stands ON the row holding the solid floor,
	# so walk the row above the spawn's base.
	var actor_row := int(level.spawn_point.y / LevelData.TILE_SIZE) - 1

	assert_lt(boss_col, exit_col,
		"the exit must sit past the boss, not behind it (boss col %d, exit col %d)"
		% [boss_col, exit_col])

	# Walk the actor row from spawn to boss: nothing solid may block the corridor,
	# or the fight can never be reached.
	var blocked_at := -1
	for col in range(spawn_col, boss_col + 1):
		if col == spawn_col or col == boss_col:
			continue
		if level.tile_is_solid(col, actor_row):
			blocked_at = col
			break
	assert_eq(blocked_at, -1,
		"solid tile at col %d on the actor row blocks the path to the boss" % blocked_at)


func test_no_actor_is_buried_in_solid_ground() -> void:
	# Spawn and checkpoints place their point on the tile BELOW the glyph ("base"),
	# while exit and boss use the glyph's own centre. Reading both with the wrong
	# convention points the test at the wrong row and proves nothing.
	for level_id in EXPECTED_LEVELS:
		var level := _load_level(level_id)
		if level == null:
			continue
		var actor_rows := 0
		for checkpoint in level.checkpoints:
			actor_rows += 1
			var col := int(checkpoint.x / LevelData.TILE_SIZE)
			var row := int(checkpoint.y / LevelData.TILE_SIZE)
			# "base" means the row below the glyph, so the glyph's own row is one up.
			assert_false(level.tile_is_solid(col, row - 1),
				"%s: checkpoint at row %d col %d is inside a solid tile"
				% [level_id, row, col])
			var supported := false
			for probe in range(row, row + 3):
				if level.tile_is_solid(col, probe) or level.tile_is_one_way(col, probe):
					supported = true
					break
			assert_true(supported,
				"%s: checkpoint at row %d col %d floats with no floor below"
				% [level_id, row, col])
		assert_gt(float(actor_rows), 0.0,
			"%s: no checkpoints parsed at all" % level_id)


func test_non_boss_levels_do_not_spawn_a_boss() -> void:
	for level_id in EXPECTED_LEVELS:
		if level_id == "zone01_boss":
			continue
		var level := _load_level(level_id)
		if level == null:
			continue
		assert_false(level.has_boss, "%s: has_boss true but is not the boss level" % level_id)


func test_levels_carry_gameplay_content() -> void:
	for level_id in EXPECTED_LEVELS:
		var level := _load_level(level_id)
		if level == null:
			continue
		assert_gt(float(level.collectible_spawns.size()), 0.0,
			"%s: no collectibles -- nothing to collect" % level_id)


# --- character rig ---------------------------------------------------------

func test_player_scene_loads_and_has_rig_nodes() -> void:
	var packed: PackedScene = load("res://scenes/Player.tscn")
	assert_not_null(packed, "Player.tscn failed to load")
	if packed == null:
		return
	var player := packed.instantiate()
	assert_not_null(player, "Player.tscn failed to instantiate")
	if player == null:
		return
	for node_path in ["Visual", "Visual/Body", "Visual/Head", "Visual/ArmLeft",
			"Visual/ArmRight", "Visual/LegLeft", "Visual/LegRight",
			"DashTrail", "Camera", "AnimationPlayer"]:
		assert_not_null(player.get_node_or_null(node_path),
			"Player.tscn missing node %s" % node_path)
	player.free()


func test_every_animation_exists() -> void:
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player to inspect animations")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	for animation_name in ANIMATIONS:
		assert_not_null(anim.get_animation(animation_name),
			"animation '%s' missing" % animation_name)
	player.free()


func test_every_animation_covers_every_rig_node() -> void:
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player to inspect animations")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	for animation_name in ANIMATIONS:
		var animation := anim.get_animation(animation_name)
		if animation == null:
			nope("%s: missing" % animation_name)
			continue
		var covered := {}
		for track_index in range(animation.get_track_count()):
			if animation.track_get_type(track_index) != Animation.TYPE_VALUE:
				continue
			covered[String(animation.track_get_path(track_index))] = true
		# Exact set equality, not "all present". A typo'd path ("Visual/rotation"
		# with a slash) creates a track that silently does nothing while every
		# expected property still looks present.
		for prop in RIG_PROPS:
			assert_true(covered.has(prop),
				"animation '%s' does not animate %s" % [animation_name, prop])
	player.free()


func test_hurt_animation_flashes_red() -> void:
	# The only animation that must drive colour. Without it, taking damage is
	# invisible on a procedural rig that has no sprite to flash.
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	var hurt := anim.get_animation("hurt")
	if hurt == null:
		nope("hurt animation missing")
		player.free()
		return
	var covered := {}
	var saw_red := false
	for track_index in range(hurt.get_track_count()):
		if hurt.track_get_type(track_index) != Animation.TYPE_VALUE:
			continue
		var path := String(hurt.track_get_path(track_index))
		covered[path] = true
		if path == TINT_PROP:
			for key_index in range(hurt.track_get_key_count(track_index)):
				var value: Color = hurt.track_get_key_value(track_index, key_index)
				if value.r > value.b:
					saw_red = true
	assert_true(covered.has(TINT_PROP), "hurt does not animate %s" % TINT_PROP)
	assert_true(saw_red, "hurt animates %s but never shifts it toward red" % TINT_PROP)
	player.free()


func test_animations_have_positive_length_and_no_stray_keys() -> void:
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player to inspect animations")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	for animation_name in ANIMATIONS:
		var animation := anim.get_animation(animation_name)
		if animation == null:
			continue
		assert_gt(animation.length, 0.0, "animation '%s' has zero length" % animation_name)
		for track_index in range(animation.get_track_count()):
			assert_lte(animation.track_get_key_time(track_index, 0), animation.length,
				"animation '%s' track %d starts past its length" % [animation_name, track_index])
	player.free()


func test_looping_animations_loop() -> void:
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player to inspect animations")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	# Only idle and run should cycle. jump/fall/dash/attack/hurt are one-shots;
	# looping them would make a recovery animation restart mid-reach.
	for animation_name in ["idle", "run"]:
		var animation := anim.get_animation(animation_name)
		if animation == null:
			nope("%s: missing" % animation_name)
			continue
		assert_eq(animation.loop_mode, Animation.LOOP_LINEAR,
			"animation '%s' should loop" % animation_name)
	for animation_name in ["jump", "fall", "dash", "attack", "hurt"]:
		var animation := anim.get_animation(animation_name)
		if animation == null:
			continue
		assert_ne(animation.loop_mode, Animation.LOOP_LINEAR,
			"animation '%s' should be a one-shot" % animation_name)
	player.free()


func test_playing_animation_actually_moves_a_limb() -> void:
	# Geometry-only assertions passed while attack had a no-op track. Assert the
	# effect, not the declaration.
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player to play animations")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	var leg: Node2D = player.get_node("Visual/LegLeft")
	var rest := leg.position
	anim.play("run")
	anim.advance(0.1)
	assert_ne(leg.position, rest, "playing 'run' did not move LegLeft")
	player.free()


func test_dash_animation_does_not_restart_every_frame() -> void:
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player")
		return
	var anim: AnimationPlayer = player.get_node("AnimationPlayer")
	anim.play("dash")
	anim.advance(0.1)
	var mid := anim.current_animation_position
	anim.advance(0.05)
	assert_gt(anim.current_animation_position, mid,
		"dash animation position went backwards or stalled")
	player.free()


func test_player_has_a_detectable_hitbox() -> void:
	# Seven systems gate on this group: collectible, checkpoint, boost pad,
	# secret area, boss, enemy contact damage. A Player without it is not a
	# cosmetic problem -- the entire pickup layer of the game becomes a silent
	# no-op that still parses, still exports and still reports green.
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player")
		return
	var hitbox: Area2D = player.get_node_or_null("Hitbox") as Area2D
	assert_not_null(hitbox, "Player.tscn has no Hitbox Area2D")
	if hitbox == null:
		player.free()
		return
	assert_true(hitbox.is_in_group("player_hitbox"),
		"Hitbox is not in group 'player_hitbox'; every pickup will ignore the player")
	# Every consumer reaches the player through get_parent(), so the hitbox must
	# be a direct child of the controller -- not of the rig.
	assert_eq(hitbox.get_parent(), player,
		"Hitbox must be a child of PlayerController; consumers use get_parent()")
	assert_true(hitbox.collision_layer & 2 != 0,
		"Hitbox must sit on collision layer 2 (Collectible/Checkpoint mask 2)")


func test_every_pickup_script_gates_on_the_hitbox_group() -> void:
	# If someone rewires a pickup to detect the player some other way, this test
	# says so explicitly instead of the group quietly becoming vestigial.
	var gated := [
		"res://src/entities/collectible.gd",
		"res://src/entities/checkpoint.gd",
		"res://src/entities/boost_pad.gd",
		"res://src/entities/secret_area.gd",
		"res://src/entities/enemy.gd",
		"res://src/entities/boss_guardian_arbor.gd",
	]
	for path in gated:
		assert_true(FileAccess.file_exists(path), "%s is missing" % path)
		if not FileAccess.file_exists(path):
			continue
		var script_text := FileAccess.get_file_as_string(path)
		assert_true(script_text.contains("player_hitbox"),
			"%s no longer detects the player via player_hitbox" % path)


func test_hitbox_follows_the_simulated_body() -> void:
	# The simulated body is a RefCounted with no transform. If nothing copies its
	# position onto the Area2D, the hitbox stays at the spawn point and a player
	# who runs the whole level collects nothing.
	var player := _spawn_player()
	if player == null:
		nope("could not spawn player")
		return
	var hitbox: Area2D = player.get_node_or_null("Hitbox") as Area2D
	if hitbox == null:
		nope("no Hitbox")
		player.free()
		return
	var before := hitbox.position
	player.body.teleport(Vector2(400.0, 300.0))
	player._sync_visual()
	assert_ne(hitbox.position, before, "Hitbox did not follow the body position")
	assert_eq(hitbox.position, player.body.position,
		"Hitbox position must equal the simulated body position")
	player.free()


# --- navigation ------------------------------------------------------------

func test_every_scene_the_director_can_open_exists() -> void:
	# A public to_* method pointing at a missing .tscn crashes on first click.
	# Naming the target explicitly keeps the check honest if the constant moves.
	var required := {
		"BOOT": "res://scenes/Boot.tscn",
		"MAIN_MENU": "res://scenes/ui/MainMenu.tscn",
		"CHARACTER": "res://scenes/ui/CharacterSelect.tscn",
		"RESULTS": "res://scenes/ui/Results.tscn",
		"LEVEL_TEMPLATE": "res://scenes/levels/Level.tscn",
	}
	for constant_name in required:
		var path: String = String(SceneDirector.get(constant_name))
		assert_eq(path, String(required[constant_name]),
			"SceneDirector.%s points somewhere unexpected" % constant_name)
		assert_true(ResourceLoader.exists(path),
			"SceneDirector.%s -> %s does not exist" % [constant_name, path])


func test_player_reachable_from_level_scene() -> void:
	var level: PackedScene = load("res://scenes/levels/Level.tscn")
	assert_not_null(level, "Level.tscn failed to load")
	if level == null:
		return
	assert_true(ResourceLoader.exists("res://scenes/Player.tscn"),
		"Level.gd instantiates Player.tscn; it must exist")


# --- helpers ---------------------------------------------------------------

func _load_level(level_id: String) -> LevelData:
	var text := FileAccess.get_file_as_string(LEVEL_DIR + level_id + ".json")
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return LevelData.from_dict(parsed)


## Instantiating the player requires a live scene tree (its _ready builds the
## animation library and reads the selected character), so the case has to
## parent it to the running tree.
func _spawn_player() -> PlayerController:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		nope("no scene tree available")
		return null
	var packed: PackedScene = load("res://scenes/Player.tscn")
	if packed == null:
		return null
	var player: PlayerController = packed.instantiate()
	if player == null:
		return null
	tree.root.add_child(player)
	return player
