class_name TileType
extends RefCounted
## Tile vocabulary shared by the level format and the renderer.
##
## The ASCII map in a level file is the single source of truth. Everything the
## engine spawns (solids, hazards, items, enemies) is derived from these
## symbols, so adding a new tile type means adding a case here and a glyph in
## the legend -- never editing level loading code.

enum Kind {
	EMPTY,
	SOLID,          ## full collision
	PLATFORM,       ## one-way, land from above only
	SLICK,          ## SOLID with near-frictionless surface
	HAZARD,         ## damaging on contact
	LIQUID,         ## decorative + slow movement
}

## glyph -> tile definition
const TILES := {
	".": {"kind": Kind.EMPTY,   "solid": false, "one_way": false, "slick": false, "hazard": false},
	"#": {"kind": Kind.SOLID,   "solid": true,  "one_way": false, "slick": false, "hazard": false},
	"=": {"kind": Kind.PLATFORM,"solid": true,  "one_way": true,  "slick": false, "hazard": false},
	"~": {"kind": Kind.SLICK,   "solid": true,  "one_way": false, "slick": true,  "hazard": false},
	"^": {"kind": Kind.HAZARD,  "solid": false, "one_way": false, "slick": false, "hazard": true},
	"w": {"kind": Kind.LIQUID,  "solid": false, "one_way": false, "slick": false, "hazard": false},
}

## Object glyphs that place a gameplay entity and leave the tile EMPTY.
const OBJECTS := {
	"S": "spawn",
	"E": "exit",
	"o": "checkpoint",
	"*": "collectible_energy",
	"c": "collectible_crystal",
	"f": "collectible_fragment",
	"X": "collectible_special",
	"!": "enemy_patrol",
	"1": "enemy_flyer",
	"2": "enemy_shield",
	"3": "enemy_chaser",
	"4": "enemy_bomber",
	"5": "enemy_tank",
	"6": "enemy_sentinel",
	"@": "powerup_shield",
	"%": "powerup_speed",
	"&": "powerup_magnet",
	"$": "powerup_invincible",
	"+": "powerup_energy",
	"M": "platform_mover",
	"L": "hazard_laser",
	"G": "hazard_crush",
	"T": "hazard_crumble",
	"J": "hazard_jumppad",
	"V": "hazard_vortex",
	"B": "boss_trigger",
	"P": "path_marker",
	"A": "area_underwater",
	"N": "area_highspeed",
	"K": "area_secret",
	"Q": "decor_tree",
	"b": "decor_bush",
	"C": "decor_crystal_vein",
	"u": "decor_cave",
}

static func is_tile(glyph: String) -> bool:
	return TILES.has(glyph)


static func is_object(glyph: String) -> bool:
	return OBJECTS.has(glyph)


static func tile_info(glyph: String) -> Dictionary:
	return TILES.get(glyph, TILES["."])


static func is_solid(glyph: String) -> bool:
	return bool(tile_info(glyph)["solid"])


static func is_one_way(glyph: String) -> bool:
	return bool(tile_info(glyph)["one_way"])


static func is_slick(glyph: String) -> bool:
	return bool(tile_info(glyph)["slick"])


static func is_hazard(glyph: String) -> bool:
	return bool(tile_info(glyph)["hazard"])


static func object_kind(glyph: String) -> String:
	return String(OBJECTS.get(glyph, ""))


## All glyphs the parser accepts, for error messages and editor tooling.
static func all_glyphs() -> PackedStringArray:
	var glyphs := PackedStringArray()
	for key in TILES.keys():
		glyphs.append(String(key))
	for key in OBJECTS.keys():
		glyphs.append(String(key))
	return glyphs
