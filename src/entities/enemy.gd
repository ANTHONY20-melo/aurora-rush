class_name Enemy
extends CharacterBody2D
## Base enemy. Subclasses implement behaviour; this handles health, damage,
## defeat, and the physics body setup shared by all enemies.

@export var max_health: float = 30.0
@export var contact_damage: float = 15.0
@export var score_value: int = 100
@export var is_elite: bool = false

var health: float = 0.0
var dead: bool = false
var _stun_timer: float = 0.0
var _knockback: Vector2 = Vector2.ZERO

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("enemy_hitbox")
	collision_layer = 4
	collision_mask = 1 | 2 | 16

func _physics_process(delta: float) -> void:
	if dead:
		return
	_apply_knockback(delta)
	_behaviour(delta)
	move_and_slide()

func _apply_knockback(delta: float) -> void:
	if _knockback != Vector2.ZERO:
		velocity += _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1200.0 * delta)

func _behaviour(delta: float) -> void:
	pass

func damage(amount: float, source: Vector2 = Vector2.ZERO, knockback: float = 300.0) -> void:
	if dead or _stun_timer > 0.0:
		return
	health -= amount
	_stun_timer = 0.1
	AudioDirector.play_sfx("enemy_hit", -6.0)
	EventBus.enemy_damaged.emit(name, health, max_health)
	
	if source != Vector2.ZERO:
		var dir := (global_position - source).normalized()
		_knockback = dir * knockback
	
	if health <= 0.0:
		_die()

func _die() -> void:
	dead = true
	AudioDirector.play_sfx("enemy_defeat", -5.0)
	EventBus.enemy_defeated.emit(name, global_position, score_value)
	GameManager.register_enemy_defeated(global_position, is_elite)
	_create_defeat_effect()
	queue_free()

func _create_defeat_effect() -> void:
	var particles := GPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 12
	particles.lifetime = 0.6
	particles.speed = 120.0
	particles.spread = 45.0
	particles.gravity = Vector2(0, 400)
	particles.color = Color(0.9, 0.6, 0.2, 1.0)
	var cr := Gradient.new()
	cr.set_color(0, Color(1.0, 0.8, 0.2, 1.0))
	cr.set_color(1, Color(0.9, 0.3, 0.1, 0.0))
	particles.color_ramp = cr
	get_tree().root.add_child(particles)
	if particles.global_position == Vector2.ZERO:
		particles.global_position = global_position
	particles.emitting = true

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player_hitbox"):
		var player := body.get_parent()
		if player and player.has_method("damage"):
			player.damage(contact_damage, "enemy_" + name)