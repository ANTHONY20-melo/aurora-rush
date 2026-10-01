class_name MovingPlatform
extends CharacterBody2D
## Moving platform: moves between waypoints, carries the player.

@export var waypoints: Array[Vector2] = [Vector2.ZERO, Vector2(200, 0)]
@export var speed: float = 80.0
@export var wait_time: float = 0.5
@export var loop: bool = true

var _current_index: int = 0
var _target_index: int = 1
var _direction: int = 1
var _wait_timer: float = 0.0
var _waiting: bool = false
var _prev_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_prev_position = global_position
	
	if waypoints.size() < 2:
		waypoints = [global_position, global_position + Vector2(200, 0)]

func _physics_process(delta: float) -> void:
	if _waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_waiting = false
			_direction *= -1 if not loop else 1
			_advance_target()
		return
	
	var target := waypoints[_target_index]
	var to_target := target - global_position
	var dist := to_target.length()
	
	if dist < 4.0:
		global_position = target
		_waiting = true
		_wait_timer = wait_time
		return
	
	velocity = to_target.normalized() * speed
	move_and_slide()

func _advance_target() -> void:
	if loop:
		_target_index = (_target_index + _direction) % waypoints.size()
		if _target_index < 0:
			_target_index = waypoints.size() - 1
	else:
		_target_index += _direction
		if _target_index >= waypoints.size():
			_target_index = waypoints.size() - 2
			_direction = -1
		elif _target_index < 0:
			_target_index = 1
			_direction = 1

func _draw() -> void:
	var color := Color(0.85, 0.66, 0.38)
	var rect := Rect2(-48, -8, 96, 16)
	draw_rect(rect, color)
	draw_rect(Rect2(-44, -6, 88, 4), Color(0.7, 0.5, 0.25))
	
	if Engine.is_editor_hint() and waypoints.size() >= 2:
		draw_line(Vector2.ZERO, waypoints[0] - global_position, Color(0.5, 0.5, 0.9, 0.5), 2.0)
		for i in range(waypoints.size() - 1):
			draw_line(waypoints[i] - global_position, waypoints[i + 1] - global_position, Color(0.5, 0.5, 0.9, 0.5), 2.0)
		if not loop:
			draw_line(waypoints[-1] - global_position, waypoints[0] - global_position, Color(0.5, 0.5, 0.9, 0.2), 2.0)