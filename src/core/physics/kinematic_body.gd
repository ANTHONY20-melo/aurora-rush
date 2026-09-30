class_name KinematicBody
extends RefCounted
## Custom kinematic character controller.
##
## Written by hand rather than using CharacterBody2D because the whole feel of
## this game lives in the details `move_and_slide` hides: how a body is
## sub-stepped at 2000 px/s, whether a one-way platform is solid on the way up,
## what surface friction a body inherits, and how a slope adds speed instead
## of subtracting it.
##
## Resolution is axis-separated (X then Y), which is stable, cheap, and cannot
## wedge a body into a corner. The cost is that a body moving diagonally into
## a corner stops on the first axis it hits -- acceptable here, and invisible
## in play.
##
## Pure logic: it knows about LevelData, not about nodes, so the entire
## collision model is unit-testable under `--headless`.

const TILE := LevelData.TILE_SIZE

## Never integrate more than this fraction of a tile in one sub-step. Keeps a
## fast body from tunnelling through a one-tile-thick wall.
const MAX_STEP_RATIO := 0.4

## Skin width kept between a resolved body and the surface it touched.
const SKIN := 0.01

## How far above a platform's top a body may be and still land on it. Prevents
## snapping up onto a platform the player is already standing above.
const ONE_WAY_SNAP := 8.0

## Contact band for ramp landing.
const RAMP_BAND := 10.0

# --- state ------------------------------------------------------------------
var position: Vector2 = Vector2.ZERO      ## centre of the body, world pixels
var velocity: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2(22.0, 30.0)   ## full extents
var enabled: bool = true

# --- contact flags, valid after each move() --------------------------------
var on_floor: bool = false
var on_ceiling: bool = false
var on_wall_left: bool = false
var on_wall_right: bool = false
var on_slick: bool = false
var on_one_way: bool = false
var on_ramp: bool = false
var floor_normal: Vector2 = Vector2.UP
var floor_angle: float = 0.0

## Set when the body left the ground this frame, for coyote time.
var just_left_floor: bool = false
## Set when the body touched ground this frame, with the impact speed.
var just_landed: bool = false
var land_speed: float = 0.0

## Colliders the body can stand on. Ramps are separate from the tile grid.
var ramps: Array[RampCollider] = []

## Set by the level to freeze the body (cutscene, boss intro, death).
var frozen: bool = false


func half_size() -> Vector2:
	return size * 0.5


func rect() -> Rect2:
	return AABB2.from_center(position, size)


func feet_y() -> float:
	return position.y + half_size().y


func head_y() -> float:
	return position.y - half_size().y


func left_x() -> float:
	return position.x - half_size().x


func right_x() -> float:
	return position.x + half_size().x


func facing() -> int:
	return 1 if velocity.x > 1.0 else (-1 if velocity.x < -1.0 else 0)


func is_grounded() -> bool:
	return on_floor or on_ramp


func teleport(to: Vector2, keep_velocity: bool = false) -> void:
	position = to
	if not keep_velocity:
		velocity = Vector2.ZERO
	_reset_contacts()


func _reset_contacts() -> void:
	on_floor = false
	on_ceiling = false
	on_wall_left = false
	on_wall_right = false
	on_slick = false
	on_one_way = false
	on_ramp = false
	floor_normal = Vector2.UP
	floor_angle = 0.0


## Integrate one frame.
##
## Returns the actual distance travelled, which is less than `delta * velocity`
## whenever a wall was hit -- movement code needs that to know a dash was
## interrupted rather than assuming it completed.
func move(grid: LevelData, delta: float) -> float:
	_reset_contacts()
	just_landed = false
	just_left_floor = false
	land_speed = 0.0

	if frozen or not enabled or grid == null or delta <= 0.0:
		return 0.0

	var was_grounded := is_grounded()
	var fall_before := velocity.y

	# Sub-step so a fast body cannot cross a whole tile in one integration.
	var travel := Vector2(velocity.x * delta, velocity.y * delta)
	var longest := maxf(absf(travel.x), absf(travel.y))
	var steps: int = clampi(int(ceil(longest / (TILE * MAX_STEP_RATIO))), 1, 32)
	var step_delta := delta / float(steps)
	var start := position

	for _i in steps:
		_integrate_x(grid, travel.x / float(steps))
		_integrate_y(grid, travel.y / float(steps))
		_integrate_ramps()

	if not was_grounded and is_grounded():
		just_landed = true
		land_speed = maxf(0.0, fall_before)
	elif was_grounded and not is_grounded():
		just_left_floor = true

	return position.distance_to(start)


# --- X axis -----------------------------------------------------------------

func _integrate_x(grid: LevelData, dx: float) -> void:
	if is_zero_approx(dx):
		return
	position.x += dx

	var body := rect()
	var b := AABB2.tile_bounds(body, TILE)
	for ty in range(b.y, b.w + 1):
		for tx in range(b.x, b.z + 1):
			if not grid.tile_is_solid(tx, ty):
				continue
			var tile_rect := AABB2.tile_rect(tx, ty, TILE)
			if not AABB2.overlaps(body, tile_rect):
				continue
			if dx > 0.0:
				position.x = tile_rect.position.x - half_size().x - SKIN
				on_wall_right = true
			else:
				position.x = tile_rect.end.x + half_size().x + SKIN
				on_wall_left = true
			velocity.x = 0.0
			return


# --- Y axis -----------------------------------------------------------------

func _integrate_y(grid: LevelData, dy: float) -> void:
	if is_zero_approx(dy):
		return
	var previous_feet := feet_y()
	position.y += dy

	var body := rect()
	var b := AABB2.tile_bounds(body, TILE)
	for ty in range(b.y, b.w + 1):
		for tx in range(b.x, b.z + 1):
			# One-way platforms are resolved first and exclusively. They are not
			# solid, so this branch must come before the solid branch and must
			# `continue` rather than fall through: a platform has to be
			# transparent to anything that is not falling onto its top edge.
			if grid.tile_is_one_way(tx, ty):
				if dy <= 0.0:
					continue
				var platform_top := float(ty) * TILE
				# Only land if the body was above the surface last frame.
				if previous_feet > platform_top + ONE_WAY_SNAP:
					continue
				position.y = platform_top - half_size().y - SKIN
				velocity.y = 0.0
				on_floor = true
				on_one_way = true
				return

			if not grid.tile_is_solid(tx, ty):
				continue
			if not AABB2.overlaps(body, AABB2.tile_rect(tx, ty, TILE)):
				continue

			var tile_rect := AABB2.tile_rect(tx, ty, TILE)
			if dy > 0.0:
				position.y = tile_rect.position.y - half_size().y - SKIN
				on_floor = true
				if grid.tile_is_slick(tx, ty):
					on_slick = true
			else:
				position.y = tile_rect.end.y + half_size().y + SKIN
				on_ceiling = true
			velocity.y = 0.0
			return


# --- ramps ------------------------------------------------------------------

func _integrate_ramps() -> void:
	for ramp in ramps:
		var result := ramp.resolve(rect(), position)
		if not bool(result["hit"]):
			continue
		position = result["position"]
		# A ramp only counts as ground if the body is not being thrown upward
		# by its own jump; otherwise jumping off a slope would be impossible.
		if velocity.y >= -1.0:
			on_floor = true
			on_ramp = true
			floor_normal = result["normal"]
			floor_angle = ramp.slope_angle()
			if ramp.slick:
				on_slick = true
			velocity.y = maxf(velocity.y, 0.0)


# --- queries used by gameplay ----------------------------------------------

## True if the body's AABB overlaps any hazard tile.
func overlaps_hazard(grid: LevelData) -> bool:
	var body := rect()
	var b := AABB2.tile_bounds(body, TILE)
	for ty in range(b.y, b.w + 1):
		for tx in range(b.x, b.z + 1):
			if grid.tile_is_hazard(tx, ty):
				return true
	return false


## True if the body's lower half is inside any hazard tile. Used for hazards
## that should not punish a body merely brushing past at the very top.
func overlaps_hazard_feet(grid: LevelData, band: float = 10.0) -> bool:
	var probe := Rect2(rect().position.x, feet_y() - band, size.x, band + size.y * 0.1)
	var b := AABB2.tile_bounds(probe, TILE)
	for ty in range(b.y, b.w + 1):
		for tx in range(b.x, b.z + 1):
			if grid.tile_is_hazard(tx, ty):
				return true
	return false


## Is there solid ground directly beneath the body within `reach` pixels?
## Used by enemies that patrol and need to turn at ledges.
func ground_ahead(grid: LevelData, direction: int, reach: float = 6.0) -> bool:
	var probe_x := position.x + float(direction) * (half_size().x + 1.0)
	var probe_y := feet_y() + reach
	var tx := int(floor(probe_x / TILE))
	var ty := int(floor(probe_y / TILE))
	if grid.tile_is_solid(tx, ty) or grid.tile_is_one_way(tx, ty):
		return true
	for ramp in ramps:
		var bounds := ramp.bounds()
		if probe_x >= bounds.position.x and probe_x <= bounds.end.x \
				and probe_y >= ramp.surface_y_at(probe_x) - 2.0:
			return true
	return false


## Is there a wall directly ahead? Enemies use this to avoid walking off a
## cliff into a pit or into a closed door.
func wall_ahead(grid: LevelData, direction: int) -> bool:
	var probe_x := position.x + float(direction) * (half_size().x + 1.0)
	var ty := int(floor((position.y + half_size().y - 4.0) / TILE))
	var tx := int(floor(probe_x / TILE))
	return grid.tile_is_solid(tx, ty)


## Height of the nearest ground below the body, or -1 if there is none within
## `max_depth`. Drives the fall-detection used for hard landings and for
## enemies that spawn-drop into a level.
func ground_below(grid: LevelData, max_depth: float = 512.0) -> float:
	var tx := int(floor(position.x / TILE))
	var start_ty := int(floor(feet_y() / TILE))
	var end_ty := int(floor((feet_y() + max_depth) / TILE))
	for ty in range(start_ty, end_ty + 1):
		if grid.tile_is_solid(tx, ty) or grid.tile_is_one_way(tx, ty):
			return float(ty) * TILE
	for ramp in ramps:
		var bounds := ramp.bounds()
		if position.x < bounds.position.x or position.x > bounds.end.x:
			continue
		var surface := ramp.surface_y_at(position.x)
		if surface >= feet_y() - 2.0 and surface <= feet_y() + max_depth:
			return surface
	return -1.0
