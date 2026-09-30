class_name AABB2
extends RefCounted
## Axis-aligned bounding box helpers for the kinematic solver.
##
## The solver works in tile space, so these are deliberately thin: overlap
## tests, tile-index ranges and edge resolution. No allocation per call --
## this runs 60 times a second for every moving body in the level.


## Rect from a centre point and a full size.
static func from_center(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


## Inclusive tile bounds actually spanned by a rect.
static func tile_bounds(rect: Rect2, tile_size: float) -> Vector4i:
	var min_x := int(floor(rect.position.x / tile_size))
	var max_x := int(floor((rect.end.x - 0.0001) / tile_size))
	var min_y := int(floor(rect.position.y / tile_size))
	var max_y := int(floor((rect.end.y - 0.0001) / tile_size))
	return Vector4i(min_x, min_y, max_x, max_y)


static func overlaps(a: Rect2, b: Rect2) -> bool:
	# Strict comparison on the far edges: two rects that merely share a
	# boundary are touching, not intersecting, and must not count as a hit.
	return a.position.x < b.end.x and a.end.x > b.position.x \
		and a.position.y < b.end.y and a.end.y > b.position.y


## Horizontal overlap only, used to decide whether a ceiling/floor contact
## should be resolved at all.
static func overlaps_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x


static func overlaps_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and a.end.y > b.position.y


## The top surface of the tile at (tx, ty), in world pixels.
static func tile_top(tx: int, ty: int, tile_size: float) -> float:
	return float(ty) * tile_size


static func tile_rect(tx: int, ty: int, tile_size: float) -> Rect2:
	return Rect2(float(tx) * tile_size, float(ty) * tile_size, tile_size, tile_size)
