class_name EnemyFlyer
extends Enemy
## Floats in a sine pattern. Periodically swoops toward the player.

@export var float_speed: float = 1.8
@export var float_amplitude: float = 30.0
@export var horizontal_speed: float = 60.0
@export var swoop_cooldown: float = 3.0
@export var swoop_speed: float = 350.0
@export var detection_range: float = 200.0

var _base_y: float = 0.0
var _time: float = 0.0
var _swoop_timer: float = 0.0
var _swooping: bool = false
var _swoop_target: Vector2 = Vector2.ZERO
var _player: Node2D = null

func _ready() -> void:
	super._ready()
	_base_y = global_position.y
	_time = randf() * TAU
	_swoop_timer = randf_range(0.0, swoop_cooldown)
	collision_layer = 4
	collision_mask = 1 | 16

func _physics_process(delta: float) -> void:
	if dead:
		return
	_find_player()
	_update_ai(delta)
	velocity.y = 0.0
	move_and_slide()

func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _update_ai(delta: float) -> void:
	_time += delta
	_swoop_timer -= delta
	
	if _swooping:
		var to_target := _swoop_target - global_position
		if to_target.length() < 20.0 or _swoop_timer < -1.0:
			_swooping = false
			_swoop_timer = swoop_cooldown
		else:
			velocity = to_target.normalized() * swoop_speed
		return
	
	velocity.x = -horizontal_speed
	velocity.y = cos(_time * float_speed) * float_amplitude * float_speed
	
	if _player and _swoop_timer <= 0.0:
		var dist := global_position.distance_to(_player.global_position)
		if dist < detection_range:
			_swooping = true
			_swoop_target = _player.global_position + Vector2(0.0, -20.0)
			_swoop_timer = 1.5

func _draw() -> void:
	if dead:
		return
	var color := Color(0.6, 0.3, 0.8) if is_elite else Color(0.7, 0.4, 0.9)
	var body_rect := Rect2(-16, -16, 32, 20)
	draw_rect(body_rect, color)
	draw_rect(Rect2(-12, -12, 6, 6), Color(0.1, 0.0, 0.2))
	draw_rect(Rect2(6, -12, 6, 6), Color(0.1, 0.0, 0.2))
	if is_elite:
		draw_rect(Rect2(-18, -20, 36, 4), Color(0.8, 0.3, 1.0))