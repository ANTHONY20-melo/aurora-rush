extends CPUParticles2D
## Dash trail: emits only while dashing, oriented opposite to the dash so the
## trail stays behind the player.
##
## This must extend CPUParticles2D, not GPUParticles2D: the node in Player.tscn is
## a CPUParticles2D, and `initial_direction` only exists on the CPU variant. The
## mismatch made this script fail to parse and left the player controller
## duplicating the same logic inline.

var _active: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS


func set_active(active: bool, dash_direction: float) -> void:
	_active = active
	emitting = active
	if active:
		# CPUParticles2D exposes `direction` (a Vector2 cone axis, widened by
		# `spread`); it has no `initial_direction`. Verified against the engine's
		# property list, not assumed. The trail points backwards so it stays behind
		# the player.
		direction = Vector2(-dash_direction, 0.0).rotated(randf_range(-0.3, 0.3))
		restart()
	else:
		emitting = false


func is_active() -> bool:
	return _active
