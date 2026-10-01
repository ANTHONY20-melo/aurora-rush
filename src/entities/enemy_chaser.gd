class_name EnemyChaser
extends Enemy
## Runs at the player when in range. Simple but threatening.

@export var move_speed: float = 180.0
@export var chase_speed: float = 280.0
@export var detection_range: float = 240.0
@export var lose_interest_range: float = 320.0
@export var attack_cooldown: float = 1.2
@export var attack_range: float = 32.0

var _player: Node2D = null
var _chasing: bool = false
var _attack_timer: float = 0.0
var _facing: int = 1

func _ready() -> void:
	super._ready()
	_attack_timer = attack_cooldown
	collision_layer = 4
	collision_mask = 1 | 16

func _physics_process(delta: float) -> void:
	if dead:
		return
	_find_player()
	_update_ai(delta)
	move_and_slide()

func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _update_ai(delta: float) -> void:
	_attack_timer -= delta
	
	if _player == null:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		return
	
	var dist := global_position.distance_to(_player.global_position)
	var to_player := (_player.global_position - global_position).normalized()
	
	if not _chasing and dist < detection_range:
		_chasing = true
		AudioDirector.play_sfx("enemy_spawn", -8.0)
	elif _chasing and dist > lose_interest_range:
		_chasing = false
	
	if _chasing:
		var target_speed := chase_speed if dist > attack_range else 0.0
		velocity.x = move_toward(velocity.x, to_player.x * target_speed, 1200.0 * delta)
		_facing = 1 if to_player.x > 0 else -1
		
		if dist < attack_range and _attack_timer <= 0.0:
			_attack()
	else:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)

func _attack() -> void:
	_attack_timer = attack_cooldown
	if _player and _player.has_method("damage"):
		_player.damage(contact_damage, "enemy_chaser")

func _draw() -> void:
	if dead:
		return
	var color := Color(0.9, 0.6, 0.1) if is_elite else Color(0.95, 0.7, 0.2)
	var body_rect := Rect2(-14, -28, 28, 28)
	draw_rect(body_rect, color)
	draw_rect(Rect2(-10, -26, 8, 6), Color(0.9, 0.8, 0.1))
	draw_rect(Rect2(2, -26, 8, 6), Color(0.9, 0.8, 0.1))
	draw_rect(Rect2(-8, -8, 16, 8), Color(0.3, 0.2, 0.0))
	if is_elite:
		draw_rect(Rect2(-16, -32, 32, 4), Color(1.0, 0.9, 0.2))