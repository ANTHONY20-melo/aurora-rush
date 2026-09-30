class_name LevelData
extends RefCounted
## One level, parsed from a JSON recipe into validated runtime data.
##
## Content is data. A level is authored as an ASCII grid plus a small header;
## nothing about a specific level is hardcoded in engine code, and adding a
## level means dropping in a JSON file. Validation happens here, at load time,
## with messages precise enough to fix the offending line.

const TILE_SIZE := 32.0

# --- header -----------------------------------------------------------------
var id: String = ""
var name: String = ""
var zone_id: String = ""
var subtitle: String = ""
var kind: int = GameTypes.LevelKind.STANDARD
var difficulty: int = GameTypes.Difficulty.MODERATE
var music_id: String = ""
var background_id: String = "zone01_far"
var par_time: float = 0.0            ## reference time used for tutorial hints
var time_limit: float = 0.0          ## 0 = no limit
var par_ranks: Dictionary = {}       ## {"s": 45, "a": 60, ...}
var is_secret: bool = false
var requires_ability: String = ""
var intro_text: String = ""
var outro_text: String = ""
var tutorial_prompts: Array = []     ## [{ "at": Vector2i, "text": String, "icon": String }]
var modifiers: Array = []            ## challenge modifiers enabled for this level

# --- grid -------------------------------------------------------------------
var grid: PackedStringArray = PackedStringArray()
var width: int = 0                   ## in tiles
var height: int = 0
var world_width: float = 0.0
var world_height: float = 0.0

# --- derived spawns (filled by parse) --------------------------------------
var spawn_point: Vector2 = Vector2.ZERO
var exit_point: Vector2 = Vector2.ZERO
var boss_trigger: Vector2 = Vector2.ZERO
var path_point: Vector2 = Vector2.ZERO
var has_boss: bool = false
var checkpoints: PackedVector2Array = PackedVector2Array()
var enemy_spawns: Array = []        ## [{ "type": String, "pos": Vector2 }]
var collectible_spawns: Array = []   ## [{ "type": String, "pos": Vector2 }]
var powerup_spawns: Array = []       ## [{ "type": String, "pos": Vector2 }]
var hazard_spawns: Array = []        ## [{ "type": String, "pos": Vector2 }]
var mover_spawns: Array = []         ## [{ "type": String, "pos": Vector2, ...params }]
var area_spawns: Array = []          ## [{ "type": String, "rect": Rect2 }]
var decor_spawns: Array = []         ## [{ "type": String, "pos": Vector2 }]

## Parse/validation diagnostics. Empty means the level is valid.
var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()


## Build from a parsed JSON dictionary.
static func from_dict(data: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.id = String(data.get("id", ""))
	level.name = String(data.get("name", "UNTITLED"))
	level.zone_id = String(data.get("zone", ""))
	level.subtitle = String(data.get("subtitle", ""))
	level.music_id = String(data.get("music", ""))
	level.background_id = String(data.get("background", "zone01_far"))
	level.par_time = float(data.get("par_time", 0.0))
	level.time_limit = float(data.get("time_limit", 0.0))
	level.is_secret = bool(data.get("secret", false))
	level.requires_ability = String(data.get("requires_ability", ""))
	level.intro_text = String(data.get("intro", ""))
	level.outro_text = String(data.get("outro", ""))
	level.tutorial_prompts = data.get("tutorials", [])

	var ranks: Dictionary = data.get("par_ranks", {})
	level.par_ranks = Ranking.normalized_targets(ranks)

	match String(data.get("kind", "standard")):
		"standard": level.kind = GameTypes.LevelKind.STANDARD
		"time_attack": level.kind = GameTypes.LevelKind.TIME_ATTACK
		"challenge": level.kind = GameTypes.LevelKind.CHALLENGE
		"hunt": level.kind = GameTypes.LevelKind.HUNT
		"survival": level.kind = GameTypes.LevelKind.SURVIVAL
		"score": level.kind = GameTypes.LevelKind.SCORE
		"precision": level.kind = GameTypes.LevelKind.PRECISION

	match String(data.get("difficulty", "moderate")):
		"easy": level.difficulty = GameTypes.Difficulty.EASY
		"hard": level.difficulty = GameTypes.Difficulty.HARD
		"very_hard": level.difficulty = GameTypes.Difficulty.VERY_HARD
		"challenge": level.difficulty = GameTypes.Difficulty.CHALLENGE
		_: level.difficulty = GameTypes.Difficulty.MODERATE

	level.modifiers = data.get("modifiers", [])
	level._parse_grid(data.get("grid", []))
	level._validate()
	return level


## Parse the ASCII grid. Rows are top-to-bottom, columns left-to-right.
func _parse_grid(rows: Variant) -> void:
	if typeof(rows) != TYPE_ARRAY:
		errors.append("'grid' must be an array of strings")
		return
	var lines := PackedStringArray()
	for row in rows:
		lines.append(String(row))
	grid = lines
	height = grid.size()
	width = 0
	for row in grid:
		width = maxi(width, row.length())
	world_width = float(width) * TILE_SIZE
	world_height = float(height) * TILE_SIZE

	if grid.is_empty():
		errors.append("grid is empty")
		return

	var legal := TileType.all_glyphs()
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			var glyph := row[x]
			if glyph == " ":
				continue
			if not legal.has(glyph):
				errors.append("row %d col %d: unknown glyph '%s'" % [y, x, glyph])
				continue
			_absorb_glyph(glyph, x, y)

	if spawn_point == Vector2.ZERO:
		errors.append("no player spawn ('S') found in grid")


## Where each object glyph's spawn data goes. Data-driven instead of a long
## match statement so adding an object is a one-line change here.
const OBJECT_SINK := {
	"collectible_energy": "collectible_spawns",
	"collectible_crystal": "collectible_spawns",
	"collectible_fragment": "collectible_spawns",
	"collectible_special": "collectible_spawns",
	"powerup_shield": "powerup_spawns",
	"powerup_speed": "powerup_spawns",
	"powerup_magnet": "powerup_spawns",
	"powerup_invincible": "powerup_spawns",
	"powerup_energy": "powerup_spawns",
	"enemy_patrol": "enemy_spawns",
	"enemy_flyer": "enemy_spawns",
	"enemy_shield": "enemy_spawns",
	"enemy_chaser": "enemy_spawns",
	"enemy_bomber": "enemy_spawns",
	"enemy_tank": "enemy_spawns",
	"enemy_sentinel": "enemy_spawns",
	"hazard_laser": "hazard_spawns",
	"hazard_crush": "hazard_spawns",
	"hazard_crumble": "hazard_spawns",
	"hazard_jumppad": "hazard_spawns",
	"hazard_vortex": "hazard_spawns",
	"platform_mover": "mover_spawns",
	"decor_tree": "decor_spawns",
	"decor_bush": "decor_spawns",
	"decor_crystal_vein": "decor_spawns",
	"decor_cave": "decor_spawns",
}

## Named points the level script and camera read at runtime.
const POINTS := {
	"spawn": "spawn_point",
	"exit": "exit_point",
	"boss_trigger": "boss_trigger",
	"path_marker": "path_point",
}


## Convert a glyph into runtime spawn data. A glyph may place an entity and
## still be a solid tile underneath (e.g. a collectible sitting on the floor).
func _absorb_glyph(glyph: String, x: int, y: int) -> void:
	# Centre of the tile, in world pixels. Feet go to the bottom edge for
	# ground-standing actors so they do not float.
	var center := Vector2(
		float(x) * TILE_SIZE + TILE_SIZE * 0.5,
		float(y) * TILE_SIZE + TILE_SIZE * 0.5)
	var base := Vector2(center.x, float(y + 1) * TILE_SIZE)
	var kind := TileType.object_kind(glyph)
	if kind.is_empty():
		return

	if POINTS.has(kind):
		set(POINTS[kind], center if kind == "exit" or kind == "boss_trigger" else base)
		if kind == "boss_trigger":
			has_boss = true
		elif kind == "checkpoint":
			checkpoints.append(base)
		return

	if kind == "area_underwater" or kind == "area_highspeed" or kind == "area_secret":
		# Area volumes are 4x4 tiles, centred on the marker.
		area_spawns.append({
			"type": kind,
			"rect": Rect2(center - Vector2(TILE_SIZE, TILE_SIZE) * 2.0,
				Vector2(TILE_SIZE, TILE_SIZE) * 4.0),
		})
		return

	if OBJECT_SINK.has(kind):
		(get(OBJECT_SINK[kind]) as Array).append({"type": kind, "pos": center})


func _validate() -> void:
	if id.is_empty():
		errors.append("level is missing an 'id'")
	if grid.is_empty():
		return

	# Ragged rows make the level look fine but break reachability, so warn.
	for y in grid.size():
		if grid[y].length() < width:
			warnings.append("row %d is shorter than the widest row (%d < %d) -- padded with empty"
				% [y, grid[y].length(), width])

	# Checkpoints should be reachable, and there should be enough of them.
	if grid.size() > 20 and checkpoints.size() < 2:
		warnings.append("long level with fewer than 2 checkpoints")

	# A player standing on solid ground is mandatory or the level is unplayable.
	if not _has_spawn_support():
		errors.append("player spawn is not above any solid tile")

	# Every checkpoint should also have ground beneath it.
	for i in checkpoints.size():
		if not _has_support_below(checkpoints[i]):
			warnings.append("checkpoint %d floats with no floor beneath it" % i)


func _has_spawn_support() -> bool:
	if spawn_point == Vector2.ZERO:
		return false
	return _has_support_below(spawn_point)


func _has_support_below(point: Vector2) -> bool:
	var x := int(point.x / TILE_SIZE)
	var start_y := int(point.y / TILE_SIZE)
	for y in range(start_y, height):
		if y >= grid.size():
			return false
		for dx: int in [0, 1]:
			var cx: int = x + dx
			if cx < 0 or cx >= width:
				continue
			if cx < grid[y].length() and TileType.is_standable(grid[y][cx]):
				return true
	return false


# --- tile access used by the physics grid -----------------------------------

func tile_glyph(x: int, y: int) -> String:
	if y < 0 or y >= grid.size() or x < 0 or x >= width:
		return "."
	var row: String = grid[y]
	if x >= row.length():
		return "."
	return row[x]


func tile_is_solid(x: int, y: int) -> bool:
	return TileType.is_solid(tile_glyph(x, y))


func tile_is_one_way(x: int, y: int) -> bool:
	return TileType.is_one_way(tile_glyph(x, y))


func tile_is_hazard(x: int, y: int) -> bool:
	return TileType.is_hazard(tile_glyph(x, y))


func tile_is_slick(x: int, y: int) -> bool:
	return TileType.is_slick(tile_glyph(x, y))


func is_valid() -> bool:
	return errors.is_empty()


func display_title() -> String:
	return name.to_upper()


## Counts for the results screen and for the map.
func collectible_total() -> int:
	return collectible_spawns.size()


func enemy_total() -> int:
	return enemy_spawns.size()


func secret_total() -> int:
	var count := 0
	for area in area_spawns:
		if String(area["type"]) == "area_secret":
			count += 1
	count += collectible_spawns.filter(
		func(item: Dictionary) -> bool: return String(item["type"]) == "collectible_fragment").size()
	return count
