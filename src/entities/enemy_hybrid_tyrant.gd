class_name EnemyHybridTyrant
extends Enemy
## Zone 1 villain (Asset 003): a grinning man in a worn baseball cap grafted onto
## a chubby bipedal dinosaur. Olive-green hide, red-and-black plaid flannel,
## short sleeved arms and big rounded three-toed feet.

@export var move_speed: float = 200.0
@export var chase_speed: float = 340.0
@export var detection_range: float = 320.0
@export var lose_interest_range: float = 420.0
@export var attack_cooldown: float = 0.9
@export var attack_range: float = 44.0

var _player: Node2D = null
var _chasing: bool = false
var _attack_timer: float = 0.0
var _step_timer: float = 0.0

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
	_animate_walk(delta)
	move_and_slide()

func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _update_ai(delta: float) -> void:
	_attack_timer -= delta
	if _player == null:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		return
	var dist := global_position.distance_to(_player.global_position)
	var to_player := (_player.global_position - global_position).normalized()
	if not _chasing and dist < detection_range:
		_chasing = true
		AudioDirector.play_sfx("enemy_spawn", -6.0)
	elif _chasing and dist > lose_interest_range:
		_chasing = false
	if _chasing:
		var target_speed := chase_speed if dist > attack_range else 0.0
		velocity.x = move_toward(velocity.x, to_player.x * target_speed, 900.0 * delta)
		if dist < attack_range and _attack_timer <= 0.0:
			_attack()
	else:
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)

func _attack() -> void:
	_attack_timer = attack_cooldown
	if _player and _player.has_method("damage"):
		_player.damage(contact_damage, "hybrid_tyrant")

func _animate_walk(delta: float) -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	if absf(velocity.x) < 5.0:
		_step_timer = 0.0
		visual.rotation = lerp_angle(visual.rotation, 0.0, delta * 8.0)
		return
	_step_timer += delta
	visual.rotation = sin(_step_timer * 9.0) * 0.06

const FLANNEL := Color(0.62, 0.13, 0.13)
const FLANNEL_DARK := Color(0.11, 0.09, 0.1)
const HIDE := Color(0.42, 0.48, 0.2)
const HIDE_LIGHT := Color(0.5, 0.57, 0.25)
const SKIN := Color(0.85, 0.65, 0.47)
const CAP := Color(0.42, 0.36, 0.24)

func _draw() -> void:
	if dead:
		return
	_poly(PackedVector2Array([-14.0, -18.0, -34.0, -8.0, -30.0, 4.0, -12.0, -6.0]), HIDE)
	_poly(PackedVector2Array([-18.0, -6.0, 18.0, -6.0, 22.0, 12.0, 16.0, 34.0, -16.0, 34.0, -22.0, 12.0]), HIDE)
	_poly(PackedVector2Array([-10.0, 0.0, 10.0, 0.0, 12.0, 22.0, -12.0, 22.0]), HIDE_LIGHT)
	_poly(PackedVector2Array([-17.0, -2.0, 17.0, -2.0, 19.0, 18.0, -19.0, 18.0]), FLANNEL)
	for i in range(-2, 3):
		var x := float(i) * 7.0
		draw_line(Vector2(x, -2.0), Vector2(x + 2.0, 18.0), FLANNEL_DARK, 2.0)
	for j in range(3):
		var y := 2.0 + float(j) * 6.0
		draw_line(Vector2(-18.0, y), Vector2(18.0, y), FLANNEL_DARK, 2.0)
	_poly(PackedVector2Array([-19.0, -2.0, -13.0, -2.0, -13.0, 8.0, -19.0, 8.0]), FLANNEL_DARK)
	_poly(PackedVector2Array([13.0, -2.0, 19.0, -2.0, 19.0, 8.0, 13.0, 8.0]), FLANNEL_DARK)
	for side in [-1.0, 1.0]:
		var base := Vector2(side * 11.0, 34.0)
		_poly(PackedVector2Array([base.x - 8.0, base.y - 4.0, base.x + 8.0, base.y - 4.0,
			base.x + 10.0, base.y + 4.0, base.x - 10.0, base.y + 4.0]), HIDE)
		for toe in range(3):
			var tx := base.x - 6.0 + float(toe) * 6.0
			_poly(PackedVector2Array([tx - 2.0, base.y + 2.0, tx + 2.0, base.y + 2.0,
				tx + 1.5, base.y + 6.0, tx - 1.5, base.y + 6.0]), HIDE_LIGHT)
			draw_rect(Rect2(tx - 1.5, base.y + 5.0, 3.0, 1.5), FLANNEL_DARK)
	_poly(PackedVector2Array([-22.0, -2.0, -30.0, 8.0, -26.0, 14.0, -19.0, 4.0]), HIDE)
	_poly(PackedVector2Array([22.0, -2.0, 30.0, 8.0, 26.0, 14.0, 19.0, 4.0]), HIDE)
	_poly(PackedVector2Array([-13.0, -22.0, 13.0, -22.0, 15.0, -4.0, -15.0, -4.0]), SKIN)
	draw_rect(Rect2(-13.0, -4.0, 28.0, 4.0), FLANNEL_DARK)
	_poly(PackedVector2Array([-10.0, -9.0, 10.0, -9.0, 7.0, -4.0, -7.0, -4.0]), Color(0.35, 0.1, 0.1))
	draw_rect(Rect2(-10.0, -9.0, 20.0, 2.0), Color(0.95, 0.95, 0.9))
	draw_rect(Rect2(-8.0, -18.0, 6.0, 4.0), Color(0.1, 0.1, 0.12))
	draw_rect(Rect2(2.0, -18.0, 6.0, 4.0), Color(0.1, 0.1, 0.12))
	_poly(PackedVector2Array([-14.0, -22.0, 14.0, -22.0, 11.0, -32.0, -11.0, -32.0]), CAP)
	_poly(PackedVector2Array([10.0, -26.0, 30.0, -22.0, 30.0, -18.0, 10.0, -21.0]), CAP)
	draw_rect(Rect2(-6.0, -30.0, 12.0, 3.0), Color(0.55, 0.48, 0.33))

## PackedVector2Array() has no varargs constructor in Godot 4, so every literal
## above is built from an Array and converted here.
func _poly(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
