extends Node
## Scene transitions with a fade curtain.
##
## Keeps the "which scene am I in" question in one place and guarantees the
## player never sees an unloaded frame: every switch fades out, swaps, then
## fades back in. Also owns the top-level game state stack so BACK always means
## something sensible.

const BOOT := "res://scenes/Boot.tscn"
const MAIN_MENU := "res://scenes/ui/MainMenu.tscn"
const WORLD_MAP := "res://scenes/ui/WorldMap.tscn"
const LEVEL_SELECT := "res://scenes/ui/LevelSelect.tscn"
const CREDITS := "res://scenes/ui/Credits.tscn"
const SETTINGS := "res://scenes/ui/SettingsMenu.tscn"
const COLLECTION := "res://scenes/ui/Collection.tscn"
const CHARACTER := "res://scenes/ui/CharacterSelect.tscn"
const RESULTS := "res://scenes/ui/Results.tscn"
const LEVEL_TEMPLATE := "res://scenes/levels/Level.tscn"

const FADE_OUT := 0.22
const FADE_IN := 0.28

enum Screen { BOOT, MAIN_MENU, WORLD_MAP, LEVEL_SELECT, RESULTS, CREDITS, SETTINGS, COLLECTION, CHARACTER, GAMEPLAY }

var current_screen: int = Screen.BOOT
var current_level_id: String = ""
var _curtain: ColorRect
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_curtain()


func _build_curtain() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	layer.name = "TransitionCurtain"
	add_child(layer)

	_curtain = ColorRect.new()
	_curtain.color = Color(0.02, 0.03, 0.05, 0.0)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_curtain)


func _swap(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("SceneDirector: scene not found %s" % path)
		return
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("SceneDirector: change_scene_to_file(%s) failed (%d)" % [path, error])


## Fade to black, load, fade back. Returns when the new scene is in place.
func go_to(path: String, screen: int) -> void:
	if _busy:
		return
	_busy = true
	await _fade(1.0, FADE_OUT)
	_swap(path)
	current_screen = screen
	# One frame so the new scene has laid out before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade(0.0, FADE_IN)
	_busy = false


func _fade(target_alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", target_alpha, duration)
	await tween.finished


func instant_go_to(path: String, screen: int) -> void:
	_swap(path)
	current_screen = screen


# --- named destinations -----------------------------------------------------

func to_boot() -> void:
	go_to(BOOT, Screen.BOOT)


func to_main_menu() -> void:
	go_to(MAIN_MENU, Screen.MAIN_MENU)


func to_world_map() -> void:
	go_to(WORLD_MAP, Screen.WORLD_MAP)


func to_level_select() -> void:
	go_to(LEVEL_SELECT, Screen.LEVEL_SELECT)


func to_results() -> void:
	go_to(RESULTS, Screen.RESULTS)


func to_credits() -> void:
	go_to(CREDITS, Screen.CREDITS)


func to_settings() -> void:
	go_to(SETTINGS, Screen.SETTINGS)


func to_collection() -> void:
	go_to(COLLECTION, Screen.COLLECTION)


func to_character() -> void:
	go_to(CHARACTER, Screen.CHARACTER)


## Load a gameplay level. Kept separate so retry never reloads the menu stack.
func to_level(level_id: String) -> void:
	if not ContentDB.has_level(level_id):
		push_error("SceneDirector: cannot enter unknown level '%s'" % level_id)
		return
	current_level_id = level_id
	go_to(LEVEL_TEMPLATE, Screen.GAMEPLAY)


## Where BACK goes from the current screen. One table, no guesswork.
func back_destination() -> Dictionary:
	match current_screen:
		Screen.GAMEPLAY: return {"call": "to_world_map", "label": "MAPA"}
		Screen.RESULTS: return {"call": "to_world_map", "label": "MAPA"}
		Screen.WORLD_MAP: return {"call": "to_main_menu", "label": "MENU"}
		Screen.LEVEL_SELECT: return {"call": "to_world_map", "label": "MAPA"}
		Screen.CREDITS, Screen.SETTINGS, Screen.COLLECTION, Screen.CHARACTER:
			return {"call": "to_main_menu", "label": "MENU"}
		_: return {"call": "to_main_menu", "label": "MENU"}


func go_back() -> void:
	var destination := back_destination()
	if destination.has("call") and self.has_method(String(destination["call"])):
		call(String(destination["call"]))
