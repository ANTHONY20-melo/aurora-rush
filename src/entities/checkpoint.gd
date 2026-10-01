class_name Checkpoint
extends Area2D
## Checkpoint: saves progress and gives visual/audio feedback when activated.

@export var index: int = 0
@export var total: int = 1
@export var activation_radius: float = 40.0

var _activated: bool = false
var _pulse_time: float = 0.0
var _particles: GpuParticles2D

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_setup_particles()
	_pulse_time = randf() * TAU

func _setup_particles() -> void:
	_particles = GpuParticles2D.new()
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.amount = 8
	_particles.lifetime = 1.2
	_particles.speed = 30.0
	_particles.spread = 180.0
	_particles.gravity = Vector2(0, -50.0)
	_particles.color = Color(0.98, 0.72, 0.3, 0.8)
	_particles.color_ramp = Gradient.new()
	var cr := _particles.color_ramp
	cr.set_offset(0.0, Color(1.0, 0.85, 0.2, 0.9))
	cr.set_offset(1.0, Color(0.98, 0.5, 0.1, 0.0))
	add_child(_particles)
	_particles.emitting = false

func _process(delta: float) -> void:
	if _activated:
		_pulse_time += delta
		var pulse := sinf(_pulse_time * 4.0) * 0.15 + 0.85
		modulate = Color(1.0, 1.0, 1.0, pulse)
		_particles.emitting = true
	else:
		_particles.emitting = false

func _on_area_entered(area: Area2D) -> void:
	if _activated or not area.is_in_group("player_hitbox"):
		return
	_activated = true
	AudioDirector.play_sfx("item_powerup", -4.0)
	EventBus.checkpoint_activated.emit(global_position)
	GameManager.register_checkpoint(index, global_position, total)
	_create_activation_burst()

func _create_activation_burst() -> void:
	var burst := GpuParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 20
	burst.lifetime = 0.8
	burst.speed = 150.0
	burst.spread = 360.0
	burst.gravity = Vector2(0, 100.0)
	burst.color = Color(0.98, 0.72, 0.3, 1.0)
	burst.color_ramp = Gradient.new()
	var cr := burst.color_ramp
	cr.set_offset(0.0, Color(1.0, 0.9, 0.3, 1.0))
	cr.set_offset(1.0, Color(0.98, 0.4, 0.1, 0.0))
	get_tree().root.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true

func _draw() -> void:
	var color := Color(0.98, 0.72, 0.3) if _activated else Color(0.7, 0.5, 0.2)
	var r := 18.0
	draw_circle(Vector2.ZERO, r, color)
	draw_circle(Vector2.ZERO, r * 0.5, Color(0.2, 0.15, 0.05))
	if _activated:
		draw_circle(Vector2.ZERO, r + 6.0, Color(1.0, 0.8, 0.2, 0.3))
		draw_circle(Vector2.ZERO, r + 12.0, Color(1.0, 0.7, 0.1, 0.15))