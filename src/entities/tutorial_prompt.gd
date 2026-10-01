class_name TutorialPrompt
extends Node2D
## Tutorial prompt: shows contextual hint when player is nearby.

@export var text: String = ""
@export var icon: String = ""
@export var trigger_radius: float = 64.0
@export var once: bool = true

var _shown: bool = false
var _label: Label
var _player: Node2D = null
var _fade_timer: float = 0.0
var _visible: bool = false

func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	_label.add_theme_constant_override("outline_size", 2)
	_label.position = Vector2(0, -40)
	_label.visible = false
	add_child(_label)

func _process(delta: float) -> void:
	if _shown and once:
		return
	
	_find_player()
	if _player == null:
		return
	
	var dist := global_position.distance_to(_player.global_position)
	var should_show := dist < trigger_radius and not _shown
	
	if should_show:
		_show()
	elif _visible and dist >= trigger_radius * 1.2:
		_hide()
	
	if _visible:
		_fade_timer += delta
		var alpha := clampf(sin(_fade_timer * 3.0) * 0.3 + 0.7, 0.5, 1.0)
		_label.modulate = Color(1.0, 1.0, 1.0, alpha)

func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _show() -> void:
	_visible = true
	_label.text = text
	_label.visible = true
	if once:
		_shown = true

func _hide() -> void:
	_visible = false
	_label.visible = false