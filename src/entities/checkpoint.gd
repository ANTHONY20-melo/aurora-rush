extends Area2D
class_name Checkpoint
## Checkpoint: saves respawn point when touched.
## Shows visual feedback and updates SaveManager.

@export var index: int = 0
@export var total: int = 1
@export var activation_radius: float = 16.0

var _activated: bool = false
var _pulse_time: float = 0.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	queue_redraw()

func _process(delta: float) -> void:
	if _activated:
		_pulse_time += delta
		queue_redraw()

func _on_area_entered(area: Area2D) -> void:
	if _activated or not area.is_in_group("player_hitbox"):
		return
	var player := area.get_parent()
	if player and player.has_method("activate_checkpoint"):
		player.activate_checkpoint(index, global_position, total)
	_activated = true
	AudioDirector.play_sfx("checkpoint", -4.0)
	queue_redraw()

func _draw() -> void:
	var r := activation_radius
	if _activated:
		# Activated: green pulsing ring
		var pulse := 1.0 + sin(_pulse_time * 6.0) * 0.15
		draw_arc(Vector2.ZERO, r * pulse, 0, TAU, 20, Color(0.3, 1.0, 0.5, 0.8), 3.0)
		# Checkmark
		draw_line(Vector2(-6, 0), Vector2(0, 6), Color(0.3, 1.0, 0.5), 3.0)
		draw_line(Vector2(0, 6), Vector2(8, -4), Color(0.3, 1.0, 0.5), 3.0)
	else:
		# Inactive: dim pulsing ring
		var pulse := 1.0 + sin(_pulse_time * 2.0) * 0.1
		draw_arc(Vector2.ZERO, r * pulse, 0, TAU, 16, Color(0.9, 0.7, 0.2, 0.6), 2.0)
		# Flag icon
		draw_line(Vector2(-4, -r), Vector2(-4, r - 4), Color(0.9, 0.7, 0.2, 0.8), 2.0)
		draw_polygon([
			Vector2(-4, -r),
			Vector2(4, -r + 4),
			Vector2(-4, -r + 8)
		], [Color(0.9, 0.7, 0.2, 0.9)])