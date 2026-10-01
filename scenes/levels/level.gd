extends Node2D
## Gameplay level: binds the data-driven LevelData to a real scene.
##
## Spawns all entities (collectibles, enemies, checkpoints, secret areas)
## from LevelData. Terrain is drawn straight from the ASCII grid.

const PLAYER_SCENE := "res://scenes/Player.tscn"
const COLLECTIBLE_SCENE := "res://scenes/entities/Collectible.tscn"
const ENEMY_PATROL_SCENE := "res://scenes/entities/EnemyPatrol.tscn"
const ENEMY_FLYER_SCENE := "res://scenes/entities/EnemyFlyer.tscn"
const ENEMY_CHASER_SCENE := "res://scenes/entities/EnemyChaser.tscn"
## Asset 003, the Zone 1 villain: the man-dinosaur hybrid.
const ENEMY_HYBRID_TYRANT_SCENE := "res://scenes/entities/EnemyHybridTyrant.tscn"
const CHECKPOINT_SCENE := "res://scenes/entities/Checkpoint.tscn"
const SECRET_AREA_SCENE := "res://scenes/entities/SecretArea.tscn"
const MOVING_PLATFORM_SCENE := "res://scenes/entities/MovingPlatform.tscn"
const BOOST_PAD_SCENE := "res://scenes/entities/BoostPad.tscn"
const BOSS_GUARDIAN_ARBOR_SCENE := "res://scenes/entities/BossGuardianArbor.tscn"
const TUTORIAL_PROMPT_SCENE := "res://scenes/entities/TutorialPrompt.tscn"
const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const TOUCH_CONTROLS_SCENE := "res://src/ui/touch_controls.tscn"

const EXIT_RADIUS := 28.0
const HAZARD_KILL_Y := 900.0

# Terrain palette.
const COLOR_SOLID := Color(0.16, 0.24, 0.30)
const COLOR_SOLID_TOP := Color(0.35, 0.74, 0.52)
const COLOR_SLICK := Color(0.42, 0.62, 0.95)
const COLOR_PLATFORM := Color(0.85, 0.66, 0.38)
const COLOR_HAZARD := Color(0.92, 0.32, 0.30)
const COLOR_LIQUID := Color(0.25, 0.55, 0.85, 0.45)
const COLOR_EXIT := Color(0.40, 0.95, 0.70)
const COLOR_CHECKPOINT := Color(0.98, 0.72, 0.30)

var level: LevelData = null
var player: PlayerController = null
var _finished: bool = false

func _ready() -> void:
	var level_id := _resolve_level_id()
	if level_id.is_empty():
		push_error("Level: no level id available; refusing to start")
		return

	level = ContentDB.get_level(level_id)
	if level == null:
		push_error("Level: ContentDB has no level '%s'" % level_id)
		return
	if not level.is_valid():
		push_error("Level: '%s' is invalid:\n%s" % [level_id, "\n".join(level.errors)])
		return

	RenderingServer.set_default_clear_color(Color(0.055, 0.075, 0.115))
	queue_redraw()
	_spawn_entities()
	_spawn_player()
	_spawn_hud()
	_configure_camera()

func _resolve_level_id() -> String:
	if not SceneDirector.current_level_id.is_empty():
		return SceneDirector.current_level_id
	return GameManager.level_id

func _spawn_entities() -> void:
	# Collectibles
	for spawn in level.collectible_spawns:
		var c: Node = load(COLLECTIBLE_SCENE).instantiate()
		c.global_position = Vector2(spawn["pos"])
		c.kind = String(spawn["type"])
		c.value = _kind_value(c.kind)
		add_child(c)
	
	# Enemies
	for spawn in level.enemy_spawns:
		var enemy: Node = _spawn_enemy(spawn)
		if enemy:
			enemy.global_position = Vector2(spawn["pos"])
			add_child(enemy)
	
	# Checkpoints
	for i: int in level.checkpoints.size():
		var cp: Node = load(CHECKPOINT_SCENE).instantiate()
		cp.global_position = level.checkpoints[i]
		cp.index = i
		cp.total = level.checkpoints.size()
		add_child(cp)
	
	# Secret areas
	for spawn in level.area_spawns:
		if String(spawn["type"]) == "area_secret":
			var sa: Node = load(SECRET_AREA_SCENE).instantiate()
			sa.global_position = (spawn["rect"] as Rect2).position + (spawn["rect"] as Rect2).size * 0.5
			var rect := spawn["rect"] as Rect2
			if sa.has_node("Collision"):
				var shape := sa.get_node("Collision").shape as RectangleShape2D
				shape.size = rect.size
			sa.area_id = "%s_secret_%d" % [level.id, level.area_spawns.find(spawn)]
			add_child(sa)
	
	# Tutorial prompts
	for prompt_data in level.tutorial_prompts:
		var tp: Node = load(TUTORIAL_PROMPT_SCENE).instantiate()
		var at: Array = prompt_data["at"]
		tp.global_position = Vector2(float(at[0]), float(at[1]))
		tp.text = String(prompt_data["text"])
		tp.icon = String(prompt_data.get("icon", ""))
		add_child(tp)
	
	# Moving platforms
	for spawn in level.mover_spawns:
		var mp: Node = load(MOVING_PLATFORM_SCENE).instantiate()
		mp.global_position = Vector2(spawn["pos"])
		if spawn.has("waypoints"):
			mp.waypoints = spawn["waypoints"]
		if spawn.has("speed"):
			mp.speed = float(spawn["speed"])
		if spawn.has("wait_time"):
			mp.wait_time = float(spawn["wait_time"])
		if spawn.has("loop"):
			mp.loop = bool(spawn["loop"])
		add_child(mp)
	
	# Boost pads
	for spawn in level.powerup_spawns:
		if String(spawn["type"]) == "powerup_speed":
			var bp: Node = load(BOOST_PAD_SCENE).instantiate()
			bp.global_position = Vector2(spawn["pos"])
			if spawn.has("direction"):
				bp.direction = Vector2(spawn["direction"])
			if spawn.has("boost_speed"):
				bp.boost_speed = float(spawn["boost_speed"])
			add_child(bp)
	
	# Boss
	if level.has_boss:
		var boss: Node = load(BOSS_GUARDIAN_ARBOR_SCENE).instantiate()
		boss.global_position = level.boss_trigger
		add_child(boss)
		GameManager.set_boss_active(true)
		EventBus.boss_started.emit("guardian_arbor", "GUARDIÃO ARBOR")

func _spawn_enemy(spawn: Dictionary) -> Node:
	var enemy_type := String(spawn["type"])
	var scene_path: String
	match enemy_type:
		"enemy_patrol": scene_path = ENEMY_PATROL_SCENE
		"enemy_flyer": scene_path = ENEMY_FLYER_SCENE
		"enemy_chaser": scene_path = ENEMY_CHASER_SCENE
		"enemy_hybrid_tyrant": scene_path = ENEMY_HYBRID_TYRANT_SCENE
		_: return null
	var enemy: Node = load(scene_path).instantiate()
	return enemy

func _kind_value(kind: String) -> int:
	match kind:
		"collectible_energy": return 1
		"collectible_crystal": return 5
		"collectible_fragment": return 10
		"collectible_special": return 25
		_: return 1

func _spawn_hud() -> void:
	var hud: Node = load(HUD_SCENE).instantiate()
	add_child(hud)

	# Touch controls (only visible on touch devices, or forced for testing).
	var touch: Node = load(TOUCH_CONTROLS_SCENE).instantiate()
	add_child(touch)
	if player != null:
		touch.input_changed.connect(player._on_touch_input)

func _spawn_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		push_error("Level: cannot load %s" % PLAYER_SCENE)
		return
	player = packed.instantiate()
	add_child(player)
	player.setup(level, level.spawn_point)
	_configure_camera()

func _configure_camera() -> void:
	if player == null:
		return
	var camera: Camera2D = player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.world_width)
	camera.limit_bottom = int(level.world_height)

func _physics_process(_delta: float) -> void:
	if _finished or level == null or player == null:
		return

	if player.body.position.y > HAZARD_KILL_Y:
		_respawn()

	if player.body.position.distance_to(level.exit_point) < EXIT_RADIUS:
		_finish()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		$Overlay.visible = get_tree().paused
	elif event.is_action_pressed("quick_restart") and not get_tree().paused:
		_respawn()

func _respawn() -> void:
	if player == null:
		return
	var target := level.spawn_point
	if GameManager.respawn_point != Vector2.ZERO:
		target = GameManager.respawn_point
	player.body.teleport(target)
	player.movement.reset()
	player.body.velocity = Vector2.ZERO

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var result := GameManager.end_run(true)
	if result != null:
		print("[Level] '%s' completed -- score %d, rank %s" % [
			level.id, GameManager.final_score(), result.rank])
	SceneDirector.to_results()

func _draw() -> void:
	if level == null:
		return
	var ts := LevelData.TILE_SIZE
	for y in level.grid.size():
		var row: String = level.grid[y]
		for x in row.length():
			var glyph := row[x]
			if glyph == " ":
				continue
			var rect := Rect2(float(x) * ts, float(y) * ts, ts, ts)
			_draw_tile(glyph, rect)

func _draw_tile(glyph: String, rect: Rect2) -> void:
	match glyph:
		"#":
			draw_rect(rect, COLOR_SOLID)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), COLOR_SOLID_TOP)
		"~":
			draw_rect(rect, COLOR_SLICK)
		"=":
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 8.0)), COLOR_PLATFORM)
		"^":
			draw_rect(rect, COLOR_HAZARD)
		"w":
			draw_rect(rect, COLOR_LIQUID)
		"E":
			draw_rect(rect.grow(-8.0), COLOR_EXIT)
		"o":
			draw_rect(rect.grow(-10.0), COLOR_CHECKPOINT)
		"S":
			draw_rect(rect.grow(-12.0), Color(0.36, 0.87, 1.0, 0.5))