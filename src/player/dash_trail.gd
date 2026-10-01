extends GPUParticles2D
## Dash trail: emits only while dashing, oriented opposite to dash direction.

var _active: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

func set_active(active: bool, direction: float) -> void:
	_active = active
	emitting = active
	if active:
		initial_direction = Vector2(-direction, 0.0).rotated(randf_range(-0.3, 0.3))
		restart()
	else:
		emitting = false