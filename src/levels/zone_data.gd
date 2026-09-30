class_name ZoneData
extends RefCounted
## A themed world: palette, music, level roster, unlock rule and boss.
##
## Zones are pure data too. Adding a sixth zone to the campaign means adding
## one JSON file and one line to the zone list -- the map screen, progression
## and audio all read from here.

var id: String = ""
var index: int = 0
var name: String = ""
var tagline: String = ""
var story: String = ""
var music_id: String = ""
var boss_music_id: String = ""
var difficulty: int = GameTypes.Difficulty.MODERATE

## Ordered level ids in this zone.
var level_ids: PackedStringArray = PackedStringArray()
var boss_level_id: String = ""
var boss_name: String = ""
var boss_display_name: String = ""

## Progression rule: which zone must be cleared to open this one.
var requires_zone: String = ""
var requires_levels: int = 0

## Visual identity. Consumed by the renderer, the map and the UI.
var palette: Dictionary = {}     ## { sky_top, sky_bottom, fog, terrain, accent, glow }
var background_layers: PackedStringArray = PackedStringArray()
var weather: String = "none"     ## none | rain | snow | ash | bubbles | embers
var ambient_tint: Color = Color.WHITE
var unlock_message: String = ""

var errors: PackedStringArray = PackedStringArray()


static func from_dict(data: Dictionary) -> ZoneData:
	var zone := ZoneData.new()
	zone.id = String(data.get("id", ""))
	zone.index = int(data.get("index", 0))
	zone.name = String(data.get("name", "UNTITLED ZONE"))
	zone.tagline = String(data.get("tagline", ""))
	zone.story = String(data.get("story", ""))
	zone.music_id = String(data.get("music", ""))
	zone.boss_music_id = String(data.get("boss_music", ""))
	zone.boss_level_id = String(data.get("boss_level", ""))
	zone.boss_name = String(data.get("boss_name", ""))
	zone.boss_display_name = String(data.get("boss_display_name", zone.boss_name.to_upper()))
	zone.requires_zone = String(data.get("requires_zone", ""))
	zone.requires_levels = int(data.get("requires_levels", 0))
	zone.weather = String(data.get("weather", "none"))
	zone.unlock_message = String(data.get("unlock_message", ""))

	var levels: Variant = data.get("levels", [])
	if typeof(levels) == TYPE_ARRAY:
		for level_id in levels:
			zone.level_ids.append(String(level_id))

	var palette: Variant = data.get("palette", {})
	if typeof(palette) == TYPE_DICTIONARY:
		for key in palette.keys():
			zone.palette[String(key)] = String(palette[key])

	var layers: Variant = data.get("background_layers", [])
	if typeof(layers) == TYPE_ARRAY:
		for layer in layers:
			zone.background_layers.append(String(layer))

	if data.has("ambient_tint"):
		zone.ambient_tint = Color(String(data["ambient_tint"]))

	if zone.id.is_empty():
		zone.errors.append("zone is missing an 'id'")
	return zone


func is_valid() -> bool:
	return errors.is_empty()


func total_levels() -> int:
	return level_ids.size() + (1 if not boss_level_id.is_empty() else 0)


## The zone's accent colour, used by HUD accents and the map node.
func accent_color() -> Color:
	if palette.has("accent"):
		return Color(String(palette["accent"]))
	return Color(0.35, 0.85, 1.0)


func terrain_color() -> Color:
	if palette.has("terrain"):
		return Color(String(palette["terrain"]))
	return Color(0.18, 0.22, 0.26)


func fog_color() -> Color:
	if palette.has("fog"):
		return Color(String(palette["fog"]))
	return Color(0.10, 0.13, 0.18)


func sky_top_color() -> Color:
	if palette.has("sky_top"):
		return Color(String(palette["sky_top"]))
	return Color(0.04, 0.06, 0.10)


func sky_bottom_color() -> Color:
	if palette.has("sky_bottom"):
		return Color(String(palette["sky_bottom"]))
	return Color(0.10, 0.14, 0.20)


func glow_color() -> Color:
	if palette.has("glow"):
		return Color(String(palette["glow"]))
	return accent_color()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"index": index,
		"name": name,
		"tagline": tagline,
		"levels": Array(level_ids),
		"boss_level": boss_level_id,
		"requires_zone": requires_zone,
		"requires_levels": requires_levels,
		"palette": palette.duplicate(),
		"weather": weather,
	}
