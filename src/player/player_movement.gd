class_name PlayerMovement
extends RefCounted
## The movement state machine: intent + config + body in, new velocity out.
##
## This is the single most important file in the game. It owns horizontal
## acceleration, gravity shaping, the variable-height jump, coyote time, jump
## buffering, dashing, and slope influence -- and it does so without touching
## rendering, audio, or the scene tree, so all of it is verifiable headless.
##
## The loop is always the same order, and the order matters:
##   1. tick timers        (so this frame sees the state from last frame)
##   2. horizontal control (accel/decel/turn boost/friction)
##   3. slope influence    (modifies speed and gravity before integration)
##   4. jump resolution    (buffered/coyote/variable height)
##   5. dash resolution    (overrides velocity for its duration)
##   6. gravity            (unless dashing)
##   7. integrate + collide
## Doing gravity before the jump means a jump always leaves the ground with
## exactly jump_force, no matter what the previous frame's velocity was.

var config: PlayerMovementConfig
var body: KinematicBody
var input: PlayerInput = PlayerInput.new()

# --- state exposed to the rest of the game ---------------------------------
var state: int = GameTypes.PlayerState.IDLE
var facing: int = 1
var jumps_used: int = 0
var dashes_used: int = 0
var is_dashing: bool = false
var is_attacking: bool = false
var is_attacking_air: bool = false
var attack_timer: float = 0.0
var was_grounded: bool = false
var just_bounced: bool = false

# --- timers -----------------------------------------------------------------
var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: float = 1.0
var _coyote_timer: float = 0.0
var _jump_buffer: float = 0.0
var _slope_speed_bonus: float = 0.0

## Set for one frame when a new dash starts, so FX can read the true distance.
var dash_started_this_frame: bool = false
var jump_started_this_frame: bool = false
var double_jump_started_this_frame: bool = false


func _init(movement_config: PlayerMovementConfig, kinematic_body: KinematicBody) -> void:
	config = movement_config
	body = kinematic_body


func reset() -> void:
	state = GameTypes.PlayerState.IDLE
	jumps_used = 0
	dashes_used = 0
	is_dashing = false
	is_attacking = false
	is_attacking_air = false
	attack_timer = 0.0
	_dash_timer = 0.0
	_dash_cooldown = 0.0
	_coyote_timer = 0.0
	_jump_buffer = 0.0
	_slope_speed_bonus = 0.0
	dash_started_this_frame = false
	jump_started_this_frame = false
	double_jump_started_this_frame = false


## Advance one frame. `grid` is the collision world; `previous` is the last
## frame's input, used only for edge detection already done by the caller.
func step(delta: float, grid: LevelData) -> void:
	if delta <= 0.0:
		return
	dash_started_this_frame = false
	jump_started_this_frame = false
	double_jump_started_this_frame = false

	was_grounded = body.is_grounded()
	_tick_timers(delta)
	_resolve_attack(delta)
	_horizontal(delta)
	_slope_effects(delta)
	_resolve_jump()
	_resolve_dash()
	_apply_gravity(delta)
	_integrate(delta, grid)
	_update_state()


# --- timers -----------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	_dash_timer = maxf(0.0, _dash_timer - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	if is_attacking and attack_timer <= 0.0:
		is_attacking = false
		is_attacking_air = false

	if body.is_grounded():
		_coyote_timer = config.coyote_time
		jumps_used = 0
		dashes_used = 0
		_slope_speed_bonus = 0.0
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	if input.jump_pressed:
		_jump_buffer = config.jump_buffer_time
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)


# --- horizontal control -----------------------------------------------------

func _horizontal(delta: float) -> void:
	if is_dashing:
		# A dash owns the horizontal axis completely.
		body.velocity.x = _dash_direction * config.dash_speed
		return

	var grounded := body.is_grounded()
	var speed_scale := config.water_speed_scale if input.in_water else 1.0
	var max_speed := (config.max_air_speed if not grounded else config.max_speed) * speed_scale
	if input.in_speed_zone:
		max_speed += config.speed_zone_max_speed_boost

	var axis := input.move_x
	if absf(axis) > 1.0:
		axis = signf(axis)

	if absf(axis) > 0.01:
		# Turning around accelerates harder than starting from rest. This is
		# what makes a direction change feel instant instead of mushy.
		var reversing: bool = signf(axis) != signf(body.velocity.x) and absf(body.velocity.x) > 1.0
		var accel: float = config.ground_acceleration if grounded else config.air_acceleration
		if input.in_speed_zone:
			accel *= config.speed_zone_acceleration_boost
		if reversing:
			accel *= config.turn_boost
		elif absf(body.velocity.x) > max_speed * config.sprint_speed_threshold:
			accel *= config.sprint_acceleration_boost

		body.velocity.x = move_toward(body.velocity.x, axis * max_speed, accel * delta)
		facing = 1 if axis > 0.0 else -1
	else:
		var decel: float = config.ground_deceleration if grounded else config.air_deceleration
		if grounded and body.on_slick:
			decel *= config.slick_friction_scale
		# Slope momentum is not scrubbed away when standing still on a ramp.
		if not grounded or _slope_speed_bonus <= 0.0:
			body.velocity.x = move_toward(body.velocity.x, 0.0, decel * delta)

	# Slope assistance can legitimately push past max_speed; clamp to the cap so
	# a long downhill cannot compound into an unplayable blur.
	if absf(body.velocity.x) > max_speed + config.slope_speed_bonus_cap:
		body.velocity.x = signf(body.velocity.x) * (max_speed + config.slope_speed_bonus_cap)


# --- slope ------------------------------------------------------------------

## Slopes are the game's main source of extra speed. Running down converts
## height into velocity; running up costs speed but never below the base cap,
## so a steep climb is slow rather than impossible.
func _slope_effects(delta: float) -> void:
	if not body.on_ramp:
		# Airborne: bleed the bonus away so a dash off a ramp does not bank
		# permanently free speed.
		if _slope_speed_bonus != 0.0:
			_slope_speed_bonus = move_toward(_slope_speed_bonus, 0.0, 600.0 * delta)
		return

	var angle := body.floor_angle
	# Flat enough to ignore: below this the ramp is just ground.
	if absf(angle) < deg_to_rad(2.0):
		return

	# Sign of travel along the surface. A positive angle rises to the right, so
	# a body moving right is climbing and a body moving left is descending.
	var travelling := signf(body.velocity.x) if absf(body.velocity.x) > 1.0 else signf(angle)
	var climbing := travelling * signf(angle) < 0.0

	if climbing:
		_slope_speed_bonus = maxf(_slope_speed_bonus - config.slope_climb_penalty * delta,
			-config.slope_speed_bonus_cap * 0.5)
	else:
		_slope_speed_bonus = minf(_slope_speed_bonus + config.slope_acceleration * delta,
			config.slope_speed_bonus_cap)

	# Only assist in the direction the body is actually moving, otherwise
	# standing still at the top of a ramp launches the player downhill.
	if absf(body.velocity.x) > 1.0 or _slope_speed_bonus != 0.0:
		var assist_direction := signf(body.velocity.x) if absf(body.velocity.x) > 1.0 else travelling
		body.velocity.x += assist_direction * absf(_slope_speed_bonus) * delta \
			* (-1.0 if climbing else 1.0) * signf(travelling)


# --- jumping ----------------------------------------------------------------

func _resolve_jump() -> void:
	# Variable height: releasing early cuts the remaining rise. Applied every
	# frame while rising unheld, which also handles a cut on the very next frame.
	if input.jump_released and body.velocity.y < 0.0 and not is_dashing:
		body.velocity.y *= config.jump_cut_multiplier
		_jump_buffer = 0.0
		return

	if _jump_buffer <= 0.0 or is_dashing:
		return

	var can_ground_jump: bool = _coyote_timer > 0.0 and jumps_used == 0
	if can_ground_jump:
		var force := config.jump_force
		if input.in_water:
			force *= config.water_jump_scale
		body.velocity.y = force
		jumps_used = 1
		_jump_buffer = 0.0
		_coyote_timer = 0.0
		jump_started_this_frame = true
		return

	# An air jump requires BOTH that air jumps are configured and that the ground
	# jump has already been spent (jumps_used >= 1). Without the second check,
	# `jumps_used <= config.air_jumps` reads 0 <= 0 as true, so walking off any
	# ledge granted a free air jump even on a config with none.
	var can_air_jump: bool = config.air_jumps > 0 \
		and jumps_used >= 1 and jumps_used <= config.air_jumps
	if can_air_jump:
		body.velocity.y = config.double_jump_force
		jumps_used += 1
		_jump_buffer = 0.0
		double_jump_started_this_frame = true


# --- dashing ----------------------------------------------------------------

func _resolve_dash() -> void:
	if is_dashing:
		if _dash_timer <= 0.0:
			_end_dash()
		return
	if not input.dash_pressed or _dash_cooldown > 0.0:
		return
	var available: int = config.air_dashes if not body.is_grounded() else 99
	if dashes_used >= available:
		return
	# Dashing with no direction input dashes the way the player is facing.
	_dash_direction = signf(input.move_x) if absf(input.move_x) > 0.01 else float(facing)
	is_dashing = true
	_dash_timer = config.dash_duration
	_dash_cooldown = config.dash_duration + config.dash_cooldown
	dashes_used += 1
	if absf(input.move_x) > 0.01:
		facing = int(signf(input.move_x))
	if body.is_grounded():
		body.velocity.y = config.dash_ground_lift
	body.velocity.x = _dash_direction * config.dash_speed
	dash_started_this_frame = true


func _end_dash() -> void:
	is_dashing = false
	# Exit speed is a fraction of the dash speed, so dashing never banks a
	# permanent free speed boost.
	body.velocity.x = _dash_direction * config.dash_speed * config.dash_exit_speed_factor


# --- gravity ----------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if is_dashing and config.dash_ignores_gravity:
		return

	# Acceleration, not a multiplier. jump_hold_gravity is an absolute rate
	# (px/s^2) tuned to be *weaker* than full gravity, so holding the button
	# buys height. Treating it as a scale made gravity 2450 * 1750 px/s^2 and
	# killed every jump inside a single frame.
	var acceleration := config.gravity
	if input.in_water:
		acceleration = config.gravity * config.water_gravity_scale
	elif body.velocity.y < 0.0:
		# Rising: lighter while the button is held, so the player controls height.
		if input.jump_held:
			acceleration = config.jump_hold_gravity
		# Near the apex, gravity tapers so a jump does not snap to a stop.
		if absf(body.velocity.y) < config.apex_speed_threshold:
			acceleration *= config.apex_gravity_scale
	else:
		acceleration = config.gravity * config.fall_gravity_scale
		if absf(body.velocity.y) < config.apex_speed_threshold:
			acceleration *= config.apex_gravity_scale

	if body.on_ramp and body.floor_angle < 0.0 and body.velocity.x < 0.0:
		# Climbing: slightly heavier so ramps have weight.
		acceleration *= config.slope_gravity_scale

	body.velocity.y = minf(body.velocity.y + acceleration * delta, config.max_fall_speed)


# --- integration ------------------------------------------------------------

func _integrate(delta: float, grid: LevelData) -> void:
	just_bounced = false
	var was_airborne := not body.is_grounded()
	body.move(grid, delta)

	if was_airborne and body.is_grounded():
		_on_land(body.land_speed)
	elif body.just_left_floor:
		_coyote_timer = config.coyote_time


func _on_land(impact: float) -> void:
	# Keep a little horizontal momentum through a landing so a fast approach
	# does not turn into a dead stop.
	var horizontal := body.velocity.x
	if impact >= config.bounce_speed_threshold:
		# A survivable but punishing bounce: you keep your run, you lose height.
		body.velocity.y = config.bounce_force
		just_bounced = true
	else:
		body.velocity.y = 0.0

	if absf(horizontal) > 0.0:
		# Speed is preserved as-is unless it was so low that the landing should
		# still feel like it carried momentum.
		var retain := clampf(impact * 0.18, 0.0, config.landing_retain_speed)
		if absf(horizontal) < retain:
			horizontal = signf(horizontal) * retain
	body.velocity.x = horizontal


# --- attack -----------------------------------------------------------------

func try_attack() -> bool:
	if is_attacking or is_dashing:
		return false
	var airborne := not body.is_grounded()
	is_attacking = true
	is_attacking_air = airborne
	attack_timer = 0.18 if not airborne else 0.2
	state = GameTypes.PlayerState.ATTACK_AIR if airborne else GameTypes.PlayerState.ATTACK
	return true


func _resolve_attack(delta: float) -> void:
	if not is_attacking:
		return
	if input.attack_pressed and attack_timer <= 0.0:
		try_attack()


# --- state ------------------------------------------------------------------

func _update_state() -> void:
	if is_dashing:
		state = GameTypes.PlayerState.DASH
	elif is_attacking:
		state = GameTypes.PlayerState.ATTACK_AIR if is_attacking_air else GameTypes.PlayerState.ATTACK
	elif not body.is_grounded():
		state = GameTypes.PlayerState.JUMP if body.velocity.y < 0.0 else GameTypes.PlayerState.FALL
	elif absf(body.velocity.x) > config.max_speed * 0.72:
		state = GameTypes.PlayerState.SPRINT
	elif absf(body.velocity.x) > 12.0:
		state = GameTypes.PlayerState.RUN
	else:
		state = GameTypes.PlayerState.IDLE


# --- queries used by FX, audio and the camera ------------------------------

## 0..1 how "fast" the player currently feels, used to drive camera FOV kick,
## motion trails and the music intensity layer.
func speed_ratio() -> float:
	var reference: float = config.max_speed + config.slope_speed_bonus_cap
	return clampf(absf(body.velocity.x) / maxf(1.0, reference), 0.0, 1.5)


func dash_progress() -> float:
	if not is_dashing or config.dash_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _dash_timer / config.dash_duration, 0.0, 1.0)


func can_dash() -> bool:
	return _dash_cooldown <= 0.0


func dash_cooldown_ratio() -> float:
	if config.dash_cooldown <= 0.0:
		return 0.0
	return clampf(_dash_cooldown / (config.dash_duration + config.dash_cooldown), 0.0, 1.0)


func can_jump() -> bool:
	var can_ground: bool = _coyote_timer > 0.0 and jumps_used == 0
	var can_air: bool = config.air_jumps > 0 \
		and jumps_used >= 1 and jumps_used <= config.air_jumps
	return can_ground or can_air


func jump_charges_left() -> int:
	return maxi(0, config.air_jumps + 1 - jumps_used)
