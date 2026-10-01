class_name BoostPad
extends Area2D
## Boost pad: gives the player a large speed burst when touched.

@export var boost_speed: float = 1200.0
@export var boost_duration: float = 0.3
@export var direction: Vector2 = Vector2.RIGHT
@export var cooldown: float = 1.0

var _ready_to_boost: bool = true
var _cooldown_timer: float = 0.0
var _pulse_time: float = 0.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	monitorable = false
	
	if has_node("Collision"):
		var shape := get_node("Collision").shape as RectangleShape2D
		if shape:
			shape.size = Vector2(64, 16)

func _process(delta: float) -> void:
	_pulse_time += delta
	modulate = Color(1.0, 1.0, 1.0, 0.7 + 0.3 * sin(_pulse_time * 8.0))
	
	if not _ready_to_boost:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_ready_to_boost = true

func _on_area_entered(area: Area2D) -> void:
	if not _ready_to_boost or not area.is_in_group("player_hitbox"):
		return
	
	var player := area.get_parent()
	if player and player.has_method("apply_boost"):
		player.apply_boost(direction.normalized() * boost_speed, boost_duration)
		_ready_to_boost = false
		_cooldown_timer = cooldown
		AudioDirector.play_sfx("item_powerup", -4.0)
		_create_boost_effect()

func _create_boost_effect() -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 20
	particles.lifetime = 0.5
	particles.speed = 200.0
	particles.spread = 120.0
	particles.gravity = Vector2(0, 0)
	particles.color = Color(0.36, 0.87, 1.0, 1.0)
	particles.color_ramp = Gradient.new()
	# set_offset(point, offset) moves a point along the ramp; it does not take a
	# colour. A fresh Gradient already has two points at 0.0 and 1.0, so the
	# intended fade is expressed with set_color.
	var cr: Gradient = particles.color_ramp
	cr.set_color(0, Color(0.62, 0.94, 1.0, 1.0))
	cr.set_color(1, Color(0.36, 0.87, 1.0, 0.0))
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	particles.emitting = true

func _draw() -> void:
	var color := Color(0.36, 0.87, 1.0)
	var rect := Rect2(-32, -8, 64, 16)
	draw_rect(rect, color)
	draw_rect(Rect2(-28, -6, 56, 4), Color(0.62, 0.94, 1.0))
	# Arrow
	var dir := direction.normalized()
	var center := Vector2.ZERO
	if dir.x > 0:
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color(0.1, 0.2, 0.3), 3.0)
		draw_line(center + Vector2(5, -5), center + Vector2(10, 0), Color(0.1, 0.2, 0.3), 3.0)
		draw_line(center + Vector2(5, 5), center + Vector2(10, 0), Color(0.1, 0.2, 0.3), 3.0)
	else:
		draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), Color(0.1, 0.2, 0.3), 3.0)
		draw_line(center + Vector2(-5, -5), center + Vector2(-10, 0), Color(0.1, 0.2, 0.3), 3.0)
		draw_line(center + Vector2(-5, 5), center + Vector2(-10, 0), Color(0.1, 0.2, 0.3), 3.0)