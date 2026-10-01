extends Node2D
class_name PlayerController
## The node that turns player intent into simulation, and simulation into pixels.
##
## Deliberately thin. All the movement rules live in PlayerMovement, which is a
## plain RefCounted with no Node, no Input singleton and no scene tree. This
## script only does the three things that genuinely need a scene:
##
##   1. read Godot's Input singleton into a PlayerInput struct,
##   2. step the movement system once per physics tick,
##   3. copy the simulated position onto the visual, and fire sound effects.
##
## That split is why the movement code has 37 headless tests and this file needs
## none: anything interesting here is either one line or untestable by design.

## Assigned by Level.gd. The movement solver collides against the tile grid, and
## the level is the only thing that owns it.
var grid: LevelData = null
var body: KinematicBody = null
var movement: PlayerMovement = null

var _config: PlayerMovementConfig
var _visual: Polygon2D
var _dash_trail: CPUParticles2D
var _camera: Camera2D
var _step_timer: float = 0.0
var _was_jump_down: bool = false
var _was_dash_down: bool = false
var _was_attack_down: bool = false

# Camera shake
var _shake_timer: float = 0.0
var _shake_magnitude: float = 0.0
var _shake_decay: float = 15.0


func _ready() -> void:
	_config = PlayerMovementConfig.new()
	var validation := _config.validate()
	if not validation.is_empty():
		push_error("PlayerController: invalid movement config: %s" % ", ".join(validation))

	body = KinematicBody.new()
	movement = PlayerMovement.new(_config, body)
	_visual = $Visual
	_dash_trail = $DashTrail
	_camera = $Camera


## Called by Level.gd with the grid it already holds, before the first frame.
func setup(level_grid: LevelData, spawn: Vector2) -> void:
	grid = level_grid
	body.teleport(spawn)
	if grid == null:
		push_error("PlayerController.setup called without a grid; player will not move")
		return
	# Seed the contact state so the very first physics tick already sees ground.
	movement.step(1.0 / 60.0, grid)
	_sync_visual()


func _physics_process(delta: float) -> void:
	if movement == null or grid == null:
		return

	movement.input = _read_input()
	if movement.input.attack_pressed:
		movement.try_attack()

	movement.step(delta, grid)

	_fire_feedback()
	_update_footsteps(delta)
	_update_dash_trail()
	_update_camera_shake(delta)
	_sync_visual()


## One frame of intent. Edge detection lives here because only a node that
## survives between frames can know what the previous frame looked like.
func _read_input() -> PlayerInput:
	var axis := Input.get_axis("move_left", "move_right")
	var jump_down := Input.is_action_pressed("jump")
	var dash_down := Input.is_action_pressed("dash")
	var attack_down := Input.is_action_pressed("attack")

	var input := PlayerInput.from_axes(axis, jump_down, dash_down, attack_down,
		_was_jump_down, _was_dash_down, _was_attack_down)

	_was_jump_down = jump_down
	_was_dash_down = dash_down
	_was_attack_down = attack_down

	input.in_water = _is_inside_area("area_underwater")
	input.in_speed_zone = _is_inside_area("area_highspeed")
	return input


## Sound is driven by the same flags the movement system exposes, so the audio
## can never disagree with what the simulation actually did.
func _fire_feedback() -> void:
	if movement.jump_started_this_frame:
		AudioDirector.play_sfx("player_jump", -5.0)
	elif movement.double_jump_started_this_frame:
		AudioDirector.play_sfx("player_double_jump", -5.0)
	if movement.dash_started_this_frame:
		AudioDirector.play_sfx("player_dash", -5.0)
		_add_camera_shake(4.0, 0.15)
	if body.just_landed:
		var hard := body.land_speed > _config.hard_landing_speed
		AudioDirector.play_sfx("player_land_hard" if hard else "player_land", -6.0)
		if hard:
			_add_camera_shake(8.0, 0.25)
	if movement.is_dashing:
		_visual.modulate = Color(0.62, 0.94, 1.0)
	elif movement.is_attacking:
		_visual.modulate = Color(1.0, 0.85, 0.55)
	else:
		_visual.modulate = Color.WHITE


func _update_dash_trail() -> void:
	if _dash_trail == null:
		return
	var dashing := movement.is_dashing
	if dashing and not _dash_trail.emitting:
		_dash_trail.emitting = true
		_dash_trail.initial_direction = Vector2(-float(movement.facing), 0.0).rotated(randf_range(-0.3, 0.3))
		_dash_trail.restart()
	elif not dashing and _dash_trail.emitting:
		_dash_trail.emitting = false


func _add_camera_shake(magnitude: float, duration: float) -> void:
	_shake_magnitude = maxf(_shake_magnitude, magnitude)
	_shake_timer = maxf(_shake_timer, duration)


func _update_camera_shake(delta: float) -> void:
	if _shake_timer <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = _camera.offset.move_toward(Vector2.ZERO, 30.0 * delta)
		return
	
	_shake_timer -= delta
	var offset := Vector2(
		randf_range(-1.0, 1.0) * _shake_magnitude,
		randf_range(-1.0, 1.0) * _shake_magnitude * 0.5
	)
	_camera.offset = offset
	_shake_magnitude = maxf(0.0, _shake_magnitude - _shake_decay * delta)


## Footsteps on a cadence, not once per physics tick, so they do not machine-gun
## at 60 Hz.
func _update_footsteps(delta: float) -> void:
	if not body.is_grounded() or absf(body.velocity.x) < _config.max_speed * 0.5:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = 0.34
		AudioDirector.play_sfx("player_footstep", -14.0)


func _sync_visual() -> void:
	_visual.position = body.position
	# Polygon2D has no built-in flip; mirroring x is the cheapest correct way.
	_visual.scale.x = -1.0 if movement.facing < 0 else 1.0
	
	# Camera zoom based on speed ratio
	if _camera:
		var speed_ratio := movement.speed_ratio()
		var target_zoom := lerpf(1.0, 1.15, speed_ratio)
		_camera.zoom = _camera.zoom.move_toward(Vector2(target_zoom, target_zoom), 2.0 * (1.0 / 60.0))


func _is_inside_area(kind: String) -> bool:
	if grid == null:
		return false
	var body_rect := Rect2(body.position - body.half_size(), body.size)
	for area in grid.area_spawns:
		if String(area["type"]) == kind and (area["rect"] as Rect2).intersects(body_rect):
			return true
	return false

## Called by boost pads to give the player a speed burst.
func apply_boost(boost_velocity: Vector2, duration: float) -> void:
	movement.apply_boost(boost_velocity, duration)