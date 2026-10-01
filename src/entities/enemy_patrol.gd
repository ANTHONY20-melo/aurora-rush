class_name EnemyPatrol
extends Enemy
## Walks back and forth on a platform. Turns at edges or walls.

@export var move_speed: float = 120.0
@export var turn_distance: float = 48.0

var _direction: int = 1
var _start_x: float = 0.0
var _ray_left: RayCast2D
var _ray_right: RayCast2D
var _ray_down: RayCast2D

func _ready() -> void:
	super._ready()
	_start_x = global_position.x
	_setup_rays()
	_direction = 1 if randf() < 0.5 else -1

func _setup_rays() -> void:
	_ray_left = RayCast2D.new()
	_ray_left.target_position = Vector2(-24.0, 0.0)
	_ray_left.collision_mask = 1
	add_child(_ray_left)
	
	_ray_right = RayCast2D.new()
	_ray_right.target_position = Vector2(24.0, 0.0)
	_ray_right.collision_mask = 1
	add_child(_ray_right)
	
	_ray_down = RayCast2D.new()
	_ray_down.target_position = Vector2(0.0, 20.0)
	_ray_down.collision_mask = 1
	add_child(_ray_down)

func _behaviour(delta: float) -> void:
	if is_on_floor():
		velocity.x = _direction * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
	
	var hit_wall := (_direction > 0 and _ray_right.is_colliding()) or (_direction < 0 and _ray_left.is_colliding())
	var no_ground := not _ray_down.is_colliding()
	var at_limit := absf(global_position.x - _start_x) > turn_distance
	
	if hit_wall or no_ground or at_limit:
		_direction *= -1

func _draw() -> void:
	if dead:
		return
	var color := Color(0.85, 0.35, 0.25) if is_elite else Color(0.92, 0.45, 0.35)
	var body_rect := Rect2(-14, -28, 28, 28)
	draw_rect(body_rect, color)
	draw_rect(Rect2(-10, -26, 8, 6), Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(2, -26, 8, 6), Color(0.2, 0.05, 0.05))
	if is_elite:
		draw_rect(Rect2(-16, -32, 32, 4), Color(1.0, 0.8, 0.1))