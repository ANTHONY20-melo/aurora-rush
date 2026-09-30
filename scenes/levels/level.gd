extends Node2D
## Gameplay level: binds the data-driven LevelData to a real scene.
##
## Terrain is drawn straight from the ASCII grid rather than through a TileMap
## asset. That is a deliberate trade: the renderer and the collision solver then
## read the exact same source, so what the player sees and what they collide with
## can never drift apart. Swapping in a TileMap later is a contained change
## because everything above this line only talks to LevelData.

const PLAYER_SCENE := "res://scenes/Player.tscn"
const EXIT_RADIUS := 28.0
const HAZARD_KILL_Y := 900.0

# Terrain palette. Kept in one place so the level reads as a single surface.
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
	_spawn_player()
	_configure_camera()


## Prefer the director's id: it is what the player actually asked to load.
## GameManager is the fallback for a direct scene launch during development.
func _resolve_level_id() -> String:
	if not SceneDirector.current_level_id.is_empty():
		return SceneDirector.current_level_id
	return GameManager.level_id


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
	# Clamp the view to the level so the void is never on screen.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.world_width)
	camera.limit_bottom = int(level.world_height)


func _physics_process(_delta: float) -> void:
	if _finished or level == null or player == null:
		return

	# Falling out of the world is a fail state, not a crash.
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
	# Checkpoints move the respawn point; until one is reached, use the start.
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
	# The results screen does not exist yet; returning to the menu keeps the
	# loop closed instead of swapping to a scene that is not there.
	SceneDirector.to_main_menu()


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
			# A lighter cap so the walkable surface is readable at a glance.
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), COLOR_SOLID_TOP)
		"~":
			draw_rect(rect, COLOR_SLICK)
		"=":
			# One-way platforms are drawn as a thin slab on the top edge, which
			# is exactly the surface the physics treats as landable.
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