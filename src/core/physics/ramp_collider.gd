class_name RampCollider
extends RefCounted
## A triangular ramp: a sloped walkable surface built from a single collider.
##
## Slopes are entities rather than tiles. A tile grid of full squares cannot
## express "walk up and to the right", and faking it with stair-stepped tiles
## destroys the momentum feel this game is built on. A ramp is instead a
## right triangle with an analytic surface, so the surface height at any x is
## exact and the player accelerates along it smoothly.

enum Direction { UP_RIGHT, UP_LEFT }

var base: Vector2 = Vector2.ZERO      ## bottom-left of the bounding box
var width: float = 64.0
var height: float = 64.0
var direction: int = Direction.UP_RIGHT
var slick: bool = false
var enabled: bool = true

## The surface normal, pointing away from the ramp body.
var normal: Vector2 = Vector2.UP

## Where the ramp currently is. Moving platforms carry their delta here so the
## player standing on one is carried along instead of sliding off.
var offset: Vector2 = Vector2.ZERO


func _init() -> void:
	_recompute_normal()


func configure(new_base: Vector2, new_width: float, new_height: float,
		new_direction: int, is_slick: bool = false) -> void:
	base = new_base
	width = new_width
	height = new_height
	direction = new_direction
	slick = is_slick
	_recompute_normal()


func _recompute_normal() -> void:
	if direction == Direction.UP_LEFT:
		# Surface rises to the left: normal tilts left.
		normal = Vector2(-height, width).normalized()
	else:
		normal = Vector2(height, width).normalized()


## World-space bounding box of the ramp.
func bounds() -> Rect2:
	return Rect2(base + offset, Vector2(width, height))


## Height of the ramp surface at world x. Outside the span the surface is the
## low end, so a body walking off the top is not snapped down.
func surface_y_at(world_x: float) -> float:
	var left := base.x + offset.x
	var right := left + width
	var bottom := base.y + offset.y + height
	if world_x <= left:
		return bottom
	if world_x >= right:
		return bottom - height
	var t := (world_x - left) / maxf(1.0, width)
	if direction == Direction.UP_LEFT:
		t = 1.0 - t
	return bottom - t * height


## Angle of the surface in radians (0 = flat, positive = rising to the right).
func slope_angle() -> float:
	if direction == Direction.UP_LEFT:
		return -atan2(height, width)
	return atan2(height, width)


## Resolve a body resting on this ramp.
##
## `body_rect` is the body's AABB, `fall_speed` its downward velocity before
## the solve. Returns the corrected body centre, or the input unchanged when
## the body is not in contact.
func resolve(body_rect: Rect2, body_center: Vector2) -> Dictionary:
	if not enabled:
		return {"hit": false, "position": body_center}

	var feet_x_center := body_rect.get_center().x
	var left := base.x + offset.x
	var right := left + width
	# The body must be horizontally over the ramp.
	if feet_x_center < left or feet_x_center > right:
		return {"hit": false, "position": body_center}

	var surface := surface_y_at(feet_x_center)
	var feet := body_rect.end.y
	# Contact band: the feet must be at or just below the surface. Anything
	# deeper than this is a wall, not a landing, and must not be snapped.
	var contact_band := 6.0
	if feet < surface - contact_band or feet > surface + contact_band * 2.0:
		return {"hit": false, "position": body_center}

	# Never push a body *down* through the ramp.
	if feet < surface:
		return {"hit": false, "position": body_center}

	var corrected := body_center
	corrected.y = surface - (body_center.y - body_rect.position.y)
	return {"hit": true, "position": corrected, "surface": surface, "normal": normal}
