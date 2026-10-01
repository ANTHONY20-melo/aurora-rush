class_name BossGuardianArbor
extends CharacterBody2D
## GUARDIÃO ARBOR - Boss da Zona 01
## Máquina/criatura gigante que protege o primeiro fragmento do Núcleo Aurora.
## 3 fases: Ground Slam → Energy Barrage + Arena Movement → Collapse Escape

@export var max_health: float = 500.0
@export var phase2_threshold: float = 0.66
@export var phase3_threshold: float = 0.33

@export var ground_slam_cooldown: float = 3.0
@export var ground_slam_windup: float = 1.2
@export var ground_slam_shockwave_speed: float = 400.0
@export var ground_slam_shockwave_range: float = 300.0

@export var energy_barrage_cooldown: float = 4.0
@export var energy_projectile_speed: float = 350.0
@export var energy_projectile_count: int = 5
@export var energy_spread: float = 0.6

@export var arena_move_speed: float = 60.0
@export var weakpoint_exposed_time: float = 3.0

var health: float = 0.0
var phase: int = 1
var _dead: bool = false

var _ground_slam_timer: float = 0.0
var _ground_slam_state: int = 0  # 0=idle, 1=windup, 2=slamming, 3=recover
var _ground_slam_windup_timer: float = 0.0
var _shockwaves: Array[Dictionary] = []

var _energy_barrage_timer: float = 0.0
var _arena_move_dir: int = 1
var _arena_move_timer: float = 0.0
var _arena_move_duration: float = 3.0

var _weakpoint_exposed: bool = false
var _weakpoint_timer: float = 0.0
var _weakpoint_hits: int = 0
var _weakpoint_required_hits: int = 3

var _player: Node2D = null
var _vulnerable: bool = false

func _ready() -> void:
	health = max_health
	phase = 1
	collision_layer = 10
	collision_mask = 1 | 2 | 16
	add_to_group("boss")
	add_to_group("boss_hitbox")
	
	_ground_slam_timer = ground_slam_cooldown
	_energy_barrage_timer = energy_barrage_cooldown
	_arena_move_timer = _arena_move_duration
	
	AudioDirector.play_music("zone01_boss", 1.0)
	EventBus.boss_intro_started.emit("guardian_arbor", "GUARDIÃO ARBOR")

func _physics_process(delta: float) -> void:
	if _dead:
		return
	
	_find_player()
	_update_timers(delta)
	_update_phase_transition()
	
	match phase:
		1: _update_phase1(delta)
		2: _update_phase2(delta)
		3: _update_phase3(delta)
	
	_update_shockwaves(delta)
	move_and_slide()

func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _update_timers(delta: float) -> void:
	_ground_slam_timer -= delta
	_energy_barrage_timer -= delta
	_arena_move_timer -= delta
	
	if _weakpoint_exposed:
		_weakpoint_timer -= delta
		if _weakpoint_timer <= 0.0:
			_weakpoint_exposed = false

func _update_phase_transition() -> void:
	var hp_ratio := health / max_health
	if phase == 1 and hp_ratio <= phase2_threshold:
		_enter_phase2()
	elif phase == 2 and hp_ratio <= phase3_threshold:
		_enter_phase3()

func _enter_phase2() -> void:
	phase = 2
	EventBus.boss_phase_changed.emit("guardian_arbor", 2, 3)
	AudioDirector.play_sfx("boss_phase_change", -3.0)
	_ground_slam_timer = ground_slam_cooldown * 0.5
	_energy_barrage_timer = 1.0
	_arena_move_timer = _arena_move_duration

func _enter_phase3() -> void:
	phase = 3
	EventBus.boss_phase_changed.emit("guardian_arbor", 3, 3)
	AudioDirector.play_sfx("boss_phase_change", -3.0)
	EventBus.boss_started.emit("guardian_arbor", "GUARDIÃO ARBOR - FASE FINAL")
	_ground_slam_timer = ground_slam_cooldown * 0.3
	_energy_barrage_timer = energy_barrage_cooldown * 0.5
	_arena_move_timer = 0.0

func _update_phase1(delta: float) -> void:
	# Fase 1: Apenas Ground Slam
	if _ground_slam_timer <= 0.0 and _ground_slam_state == 0:
		_start_ground_slam()
	
	_execute_ground_slam(delta)
	
	# Move slowly toward player
	if _player:
		var dir := signf(_player.global_position.x - global_position.x)
		velocity.x = move_toward(velocity.x, dir * 40.0, 200.0 * delta)

func _update_phase2(delta: float) -> void:
	# Fase 2: Ground Slam + Energy Barrage + Arena Movement
	if _ground_slam_timer <= 0.0 and _ground_slam_state == 0:
		_start_ground_slam()
	
	_execute_ground_slam(delta)
	
	# Energy barrage
	if _energy_barrage_timer <= 0.0:
		_fire_energy_barrage()
		_energy_barrage_timer = energy_barrage_cooldown
	
	# Arena movement
	if _arena_move_timer <= 0.0:
		_arena_move_dir *= -1
		_arena_move_timer = _arena_move_duration
	velocity.x = _arena_move_dir * arena_move_speed

func _update_phase3(delta: float) -> void:
	# Fase 3: Tudo mais rápido + arena desmoronando
	if _ground_slam_timer <= 0.0 and _ground_slam_state == 0:
		_start_ground_slam()
	
	_execute_ground_slam(delta)
	
	# Energy barrage mais frequente
	if _energy_barrage_timer <= 0.0:
		_fire_energy_barrage()
		_energy_barrage_timer = energy_barrage_cooldown * 0.6
	
	# Arena movement constante
	velocity.x = _arena_move_dir * arena_move_speed * 1.5
	if _arena_move_timer <= 0.0:
		_arena_move_dir *= -1
		_arena_move_timer = _arena_move_duration * 0.5

func _start_ground_slam() -> void:
	_ground_slam_state = 1
	_ground_slam_windup_timer = ground_slam_windup
	AudioDirector.play_sfx("boss_charge", -4.0)
	EventBus.boss_phase_changed.emit("guardian_arbor", phase, 3)  # Reuse for windup signal

func _execute_ground_slam(delta: float) -> void:
	match _ground_slam_state:
		1:  # Windup
			_ground_slam_windup_timer -= delta
			velocity.x = 0.0
			if _ground_slam_windup_timer <= 0.0:
				_ground_slam_state = 2
				AudioDirector.play_sfx("boss_slams", -2.0)
				_add_camera_shake(15.0, 0.4)
				_create_shockwaves()
				_ground_slam_timer = ground_slam_cooldown
		2:  # Slamming - brief pause
			_ground_slam_state = 3
		3:  # Recover
			_ground_slam_state = 0
			_expose_weakpoint()

func _expose_weakpoint() -> void:
	_weakpoint_exposed = true
	_weakpoint_timer = weakpoint_exposed_time
	_weakpoint_hits = 0
	_vulnerable = true
	AudioDirector.play_sfx("env_secret", -4.0)

func _create_shockwaves() -> void:
	# Left shockwave
	_shockwaves.append({
		"position": global_position + Vector2(-40, 20),
		"direction": -1.0,
		"distance": 0.0,
		"speed": ground_slam_shockwave_speed,
		"range": ground_slam_shockwave_range
	})
	# Right shockwave
	_shockwaves.append({
		"position": global_position + Vector2(40, 20),
		"direction": 1.0,
		"distance": 0.0,
		"speed": ground_slam_shockwave_speed,
		"range": ground_slam_shockwave_range
	})

func _update_shockwaves(delta: float) -> void:
	for i in range(_shockwaves.size() - 1, -1, -1):
		var sw := _shockwaves[i]
		sw.distance += sw.speed * delta
		sw.position.x += sw.direction * sw.speed * delta
		
		if sw.distance >= sw.range:
			_shockwaves.remove_at(i)
			continue
		
		# Check player collision
		if _player:
			var player_body := _player.get_node_or_null("Player") as Node2D
			if player_body:
				var player_pos := player_body.global_position
				if absf(player_pos.x - sw.position.x) < 30.0 and absf(player_pos.y - sw.position.y) < 40.0:
					if player_body.has_method("damage"):
						player_body.damage(25.0, "boss_shockwave")

func _fire_energy_barrage() -> void:
	if _player == null:
		return
	
	AudioDirector.play_sfx("enemy_shoot", -3.0)
	var to_player := (_player.global_position - global_position).normalized()
	var base_angle := atan2(to_player.y, to_player.x)
	
	for i in range(energy_projectile_count):
		var offset := (float(i) - float(energy_projectile_count - 1) * 0.5) * energy_spread
		var angle := base_angle + offset
		var dir := Vector2(cos(angle), sin(angle))
		
		var proj := _create_projectile(global_position + Vector2(0, -40), dir)
		get_tree().root.add_child(proj)

func _create_projectile(start_pos: Vector2, direction: Vector2) -> Node2D:
	var proj := Area2D.new()
	proj.collision_layer = 5
	proj.collision_mask = 2 | 4
	proj.global_position = start_pos
	
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	proj.add_child(col)
	
	var speed := energy_projectile_speed
	
	var script := """
extends Area2D
var velocity = Vector2(%f, %f)
var lifetime = 5.0

func _physics_process(delta):
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player_hitbox"):
		var player = area.get_parent()
		if player and player.has_method("damage"):
			player.damage(20.0, "boss_projectile")
		queue_free()
""" % [direction.x * speed, direction.y * speed]
	
	proj.set_script(script)
	proj.area_entered.connect(proj._on_area_entered.bind())
	
	return proj

func damage(amount: float, source: String = "") -> void:
	if _dead or not _vulnerable:
		return
	
	health -= amount
	_weakpoint_hits += 1
	AudioDirector.play_sfx("boss_weakpoint_hit", -3.0)
	EventBus.boss_health_changed.emit("guardian_arbor", health, max_health)
	
	if _weakpoint_hits >= _weakpoint_required_hits:
		_weakpoint_exposed = false
		_vulnerable = false
	
	if health <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	AudioDirector.play_sfx("boss_defeat", -2.0)
	EventBus.boss_defeated.emit("guardian_arbor", {"fragments": 1, "boss_id": "guardian_arbor"})
	GameManager.notify_boss_defeated({"fragments": 1, "boss_id": "guardian_arbor"})
	_create_death_effect()
	queue_free()

func _create_death_effect() -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 60
	particles.lifetime = 2.0
	particles.speed = 300.0
	particles.spread = 360.0
	particles.gravity = Vector2(0, 200.0)
	particles.color = Color(0.4, 0.8, 0.3, 1.0)
	# Gradient.new() já nasce com 2 pontos (offsets 0.0 e 1.0). No Godot 4 a cor
	# se define por índice com set_color(); set_offset() recebe só float.
	var cr := Gradient.new()
	cr.set_color(0, Color(0.6, 1.0, 0.4, 1.0))
	cr.set_color(1, Color(0.2, 0.5, 0.1, 0.0))
	particles.color_ramp = cr
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	particles.emitting = true

func _add_camera_shake(magnitude: float, duration: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("_add_camera_shake"):
		player._add_camera_shake(magnitude, duration)

func _draw() -> void:
	if _dead:
		return
	
	# Body
	var body_color := Color(0.3, 0.5, 0.25) if phase == 1 else (Color(0.4, 0.3, 0.6) if phase == 2 else Color(0.6, 0.2, 0.2))
	var body_rect := Rect2(-60, -100, 120, 100)
	draw_rect(body_rect, body_color)
	
	# Core/eye
	var core_color := Color(0.9, 0.7, 0.1) if phase == 1 else (Color(0.8, 0.3, 0.9) if phase == 2 else Color(1.0, 0.2, 0.2))
	draw_circle(Vector2(0, -60), 20, core_color)
	draw_circle(Vector2(0, -60), 12, Color(1.0, 1.0, 0.8, 0.8))
	
	# Weakpoint indicator
	if _weakpoint_exposed:
		var pulse := sin(_weakpoint_timer * 10.0) * 0.3 + 0.7
		draw_circle(Vector2(0, -60), 28 * pulse, Color(1.0, 0.9, 0.2, 0.5 * pulse))
		draw_circle(Vector2(0, -60), 34 * pulse, Color(1.0, 0.7, 0.1, 0.3 * pulse))
	
	# Health bar
	var bar_width := 120.0
	var hp_ratio := health / max_health
	draw_rect(Rect2(-bar_width * 0.5, -120, bar_width, 8), Color(0.1, 0.1, 0.1, 0.8))
	draw_rect(Rect2(-bar_width * 0.5, -120, bar_width * hp_ratio, 8), Color(0.9, 0.2, 0.2))
	
	# Phase indicator: três pips, o preenchido marca a fase atual.
	# Desenhado só com formas: draw_string() exige uma Font e o texto por cima
	# do boss duplicava a info que a intro da fase já mostra no HUD.
	for i in range(3):
		var pip_rect := Rect2(-18 + i * 14, -138, 10, 6)
		var pip_color := Color(1.0, 1.0, 1.0, 0.9) if i < phase else Color(1.0, 1.0, 1.0, 0.2)
		draw_rect(pip_rect, pip_color)