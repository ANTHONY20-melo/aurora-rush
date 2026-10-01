extends TestCase
## Builds throwaway level grids so physics and movement can be tested against
## real collision data instead of mocks.
##
## A 32px tile grid is the actual game world, so a test that moves a body
## through one of these grids exercises the same solver the player will feel.

const TILE := LevelData.TILE_SIZE


## Build a LevelData from ASCII rows. Rows are padded to equal width.
static func make_grid(rows: Array, header: Dictionary = {}) -> LevelData:
	var data := {
		"id": String(header.get("id", "test_level")),
		"name": String(header.get("name", "Test Level")),
		"grid": rows,
	}
	for key in header.keys():
		if key != "id" and key != "name":
			data[key] = header[key]
	return LevelData.from_dict(data)


## A flat floor `floor_y` tiles tall spanning the whole grid, with a spawn.
static func flat_ground(columns: int = 40, floor_y: int = 12, ground_rows: int = 3) -> LevelData:
	var rows: Array = []
	for y in floor_y:
		rows.append(".".repeat(columns))
	var ground := "#".repeat(columns)
	for _i in ground_rows:
		rows.append(ground)
	# Spawn on top of the floor.
	rows[floor_y - 1] = _place(rows[floor_y - 1], 2, "S")
	return make_grid(rows)


static func _place(row: String, column: int, glyph: String) -> String:
	var chars := row.split("")
	while chars.size() <= column:
		chars.append(".")
	chars[column] = glyph
	return "".join(chars)


## An empty world with a single floor tile directly under the spawn.
static func single_tile_world() -> LevelData:
	return make_grid([
		"....",
		"....",
		"..S.",
		"..#.",
		"..#.",
	])


## A ramp sitting on a flat floor, rising to the right.
static func ramp_world(ramp_columns: int = 8, ramp_height: int = 5) -> LevelData:
	var columns := 40
	var rows: Array = []
	for y in 14:
		rows.append(".".repeat(columns))
	rows.append("#".repeat(columns))

	# Carve the ramp into the floor: a triangle rising to the right.
	for step in ramp_height:
		var y := 13 - step
		var width := ramp_columns - int(float(ramp_columns) * float(step) / float(ramp_height))
		var row: String = rows[y]
		rows[y] = _place_block(row, 6, width)
	return make_grid(rows, {"id": "ramp_world"})


## A world with a ceiling above the spawn, for jump/ceiling tests.
static func ceiling_world(gap_rows: int = 4) -> LevelData:
	var columns := 30
	var rows: Array = []
	for y in 10:
		rows.append(".".repeat(columns))
	# Ceiling
	rows.append("#".repeat(columns))
	for _i in gap_rows:
		rows.append(".".repeat(columns))
	rows[11] = _place(rows[11], 2, "S")
	rows.append("#".repeat(columns))
	rows.append("#".repeat(columns))
	return make_grid(rows)


static func _place_block(row: String, start: int, length: int) -> String:
	var chars := row.split("")
	while chars.size() < start + length:
		chars.append(".")
	for i in range(start, start + length):
		chars[i] = "#"
	return "".join(chars)


## A body of the player's real proportions, standing on the floor.
static func player_body() -> KinematicBody:
	var body := KinematicBody.new()
	body.size = Vector2(22.0, 30.0)
	return body


## A RampCollider configured as a right triangle rising to the right (UP_RIGHT)
## or left (UP_LEFT). `base` is the bottom-left of the ramp's bounding box.
static func make_ramp(base: Vector2, width: float = 128.0, height: float = 64.0,
		direction: int = RampCollider.Direction.UP_RIGHT, slick: bool = false) -> RampCollider:
	var ramp := RampCollider.new()
	ramp.configure(base, width, height, RampCollider.Direction.UP_RIGHT, slick)
	return ramp


## Attach a ramp to a KinematicBody for testing.
static func add_ramp(body: KinematicBody, ramp: RampCollider) -> void:
	body.ramps.append(ramp)


## Centre position that puts a body's feet exactly on top of tile row
## `floor_y`. Use this instead of hand-picking coordinates: guessing a resting
## Y is the single easiest way to write a collision test that silently
## measures nothing.
static func standing_on(body: KinematicBody, column: float, floor_y: int) -> Vector2:
	return Vector2(column * TILE, float(floor_y) * TILE - body.half_size().y)


## KinematicBody integrates and collides; it does NOT apply gravity -- gravity
## is owned by PlayerMovement. So any test that needs a body to fall must
## launch it explicitly. This helper is the only correct way to do that.
static func launch(body: KinematicBody, velocity: Vector2) -> void:
	body.velocity = velocity


## Step until the body reports ground contact, or until `max_frames` elapse.
## Returns true if it landed.
static func settle(body: KinematicBody, grid: LevelData, max_frames: int = 240) -> bool:
	for _i in max_frames:
		body.move(grid, 1.0 / 60.0)
		if body.on_floor:
			return true
	return false


## Step a fixed number of frames at the engine tick rate.
static func run(body: KinematicBody, grid: LevelData, frames: int) -> void:
	for _i in frames:
		body.move(grid, 1.0 / 60.0)
