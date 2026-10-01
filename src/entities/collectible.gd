class_name Collectible
extends Area2D
## Base collectible: energy, crystal, fragment, special.
## Each kind has a value and a visual signature.

@export var kind: String = "collectible_energy"
@export var value: int = 1
@export var float_amplitude: float = 4.0
@export var float_speed: float = 2.5

var _base_y: float = 0.0
var _time: float = 0.0
var _collected: bool = false

func _ready() -> void:
	_base_y = position.y
	_time = randf() * TAU
	area_entered.connect(_on_area_entered)
	queue_redraw()

func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	position.y = _base_y + sin(_time * float_speed) * float_amplitude
	rotation = sin(_time * 0.5) * 0.12

func _on_area_entered(area: Area2D) -> void:
	if _collected or not area.is_in_group("player_hitbox"):
		return
	_collected = true
	AudioDirector.play_sfx(_collect_sfx(), -6.0)
	EventBus.item_collected.emit(kind, kind, value, global_position)
	queue_free()

func _collect_sfx() -> String:
	match kind:
		"collectible_crystal": return "item_crystal"
		"collectible_fragment": return "item_fragment"
		"collectible_special": return "item_special"
		_: return "item_collect"

func _draw() -> void:
	if _collected:
		return
	var color := _kind_color()
	var r := 10.0
	draw_circle(Vector2.ZERO, r, color)
	draw_circle(Vector2.ZERO, r * 0.5, Color(1.0, 1.0, 1.0, 0.6))
	if kind == "collectible_fragment":
		draw_line(Vector2(-6, 0), Vector2(6, 0), Color(1.0, 1.0, 1.0, 0.9), 2.0)
		draw_line(Vector2(0, -6), Vector2(0, 6), Color(1.0, 1.0, 1.0, 0.9), 2.0)

func _kind_color() -> Color:
	match kind:
		"collectible_crystal": return Color(0.4, 0.9, 1.0, 1.0)
		"collectible_fragment": return Color(1.0, 0.7, 0.2, 1.0)
		"collectible_special": return Color(1.0, 0.4, 0.8, 1.0)
		_: return Color(0.36, 0.87, 1.0, 1.0)