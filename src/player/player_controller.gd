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
##   3. copy the simulated position onto the visual, and fire sound effects,
##   4. select the pose that matches the simulated state.
##
## That split is why the movement code has 37 headless tests and this file needs
## none: anything interesting here is either one line or untestable by design.
## (4) is the one grey area: it is a pure function of the movement state, but the
## suite exercises PlayerMovement directly and never instantiates this node, so
## there is nothing headless to assert against.

## Assigned by Level.gd. The movement solver collides against the tile grid, and
## the level is the only thing that owns it.
var grid: LevelData = null
var body: KinematicBody = null
var movement: PlayerMovement = null

var _config: PlayerMovementConfig
## The rig root. A plain Node2D, not a Polygon2D: it is now the parent of the
## articulated body parts and carries no polygon of its own.
var _visual: Node2D
var _dash_trail: CPUParticles2D
var _camera: Camera2D
var _anim: AnimationPlayer
var _hitbox: Area2D
var _current_anim: String = ""
## Keys queued for the animation currently being built, keyed by property path.
## See _build_animations().
var _pending: Dictionary = {}
var _hurt_timer: float = 0.0
var _step_timer: float = 0.0
var _was_jump_down: bool = false
var _was_dash_down: bool = false
var _was_attack_down: bool = false

# External input (e.g., from TouchControls). If set, _read_input uses it
# instead of reading Godot's Input singleton.
var _external_input: PlayerInput = null


# Camera shake
var _shake_timer: float = 0.0
var _shake_magnitude: float = 0.0
var _shake_decay: float = 15.0


func _ready() -> void:
	_config = PlayerMovementConfig.new()
	_apply_character_modifiers(_config)
	var validation := _config.validate()
	if not validation.is_empty():
		push_error("PlayerController: invalid movement config: %s" % ", ".join(validation))

	body = KinematicBody.new()
	movement = PlayerMovement.new(_config, body)
	_visual = $Visual
	_dash_trail = $DashTrail
	_camera = $Camera
	_anim = $AnimationPlayer
	_setup_hitbox()
	_build_animations()


## The Area2D every pickup in the game detects the player through.
##
## Collectibles, checkpoints, boost pads, secret areas, the boss and enemy
## contact damage ALL gate on `area.is_in_group("player_hitbox")` and then reach
## the player through `area.get_parent()`. That contract is invisible in the .tscn
## and easy to delete by accident, so it is asserted here and in the content test
## suite rather than left to rot as a silent no-op.
##
## It is deliberately parented to the controller (not to the rig): the simulated
## body is a plain RefCounted with no transform of its own, and its position has
## to be copied onto this node every frame or the Area2D stays at the origin.
func _setup_hitbox() -> void:
	_hitbox = $Hitbox
	if _hitbox == null:
		push_error("PlayerController: no Hitbox node; collectibles and checkpoints cannot detect the player")
		return
	_hitbox.add_to_group("player_hitbox")


## Called by Level.gd with the grid it already holds, before the first frame.
func setup(level_grid: LevelData, spawn: Vector2) -> void:
	grid = level_grid
	body.teleport(spawn)
	if grid == null:
		push_error("PlayerController.setup called without a grid; player will not move")
		return
	# Seed the contact state so the very first physics tick already sees ground.
	movement.step(1.0 / 60.0, grid)
	
	# Apply character-specific health multiplier
	var char_data := ContentDB.get_character(SaveManager.data.get_selected_character())
	var health_mult := float(char_data.gameplay_modifiers.get("health_multiplier", 1.0))
	GameManager.max_health = 100.0 * health_mult
	GameManager.health = GameManager.max_health
	
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
	_update_animation(delta)


func _on_touch_input(input: PlayerInput) -> void:
	_external_input = input


## One frame of intent. If external input (touch) is provided, use it.
## Otherwise read from Godot's Input singleton.
func _read_input() -> PlayerInput:
	if _external_input != null:
		# If external input has any activity, use it. If it's all idle,
		# treat as no touch and fall back to keyboard/gamepad.
		if _external_input.move_x != 0.0 \
			or _external_input.jump_held \
			or _external_input.dash_pressed \
			or _external_input.attack_pressed \
			or _external_input.jump_pressed \
			or _external_input.jump_released:
			return _external_input
		# Touch ended (all idle) -> clear and fall back.
		_external_input = null

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
	_apply_tint()


## The single owner of Visual.modulate outside the hurt animation. Being the
## only writer is the point: the hurt animation drives modulate too, and two
## systems assigning the same property every frame turns a damage flash into a
## flicker. Whoever is not currently animating modulate yields.
func _apply_tint() -> void:
	if _visual == null or movement == null:
		return
	if _hurt_timer > 0.0:
		return
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
	# The rig is a Node2D, which also has no built-in flip; mirroring x is the
	# cheapest correct way.
	_visual.scale.x = -1.0 if movement.facing < 0 else 1.0

	# The hitbox is a sibling of the rig, not a child, so it needs its own copy
	# of the simulated position. Without this it sits at the spawn forever and
	# every collectible, checkpoint and boost pad in the level goes untouchable.
	if _hitbox:
		_hitbox.position = body.position
	
	# Camera zoom based on speed ratio
	if _camera:
		var speed_ratio := movement.speed_ratio()
		var target_zoom := lerpf(1.0, 1.15, speed_ratio)
		_camera.zoom = _camera.zoom.move_toward(Vector2(target_zoom, target_zoom), 2.0 * (1.0 / 60.0))


# --- animation ---------------------------------------------------------------
#
# The rig is a FLAT list of siblings under Visual: Body, Head, the eyes, the
# pupils, the arms and the legs are all children of Visual, not of each other.
# There is no joint chain to lean. Rotating or scaling `Body` alone -- the
# obvious reading of "tilt the body" -- would leave the head, arms and legs
# behind and shear the character into pieces. So:
#
#   * whole-body lean and recoil animate `Visual:rotation`;
#   * squash and stretch animate `Visual/Body:scale`;
#   * limb poses animate each sibling's `position` directly.
#
# `Visual:position` and `Visual:scale` are deliberately never animated:
# _sync_visual owns both of them every frame for world tracking and facing, so
# an animation writing either would fight the simulation and flicker.
#
# Every animation carries a key for all nine animated properties, seeded at the
# rest pose. AnimationPlayer does not blend between animations, so a property an
# animation forgets is left frozen at whatever the previous animation last wrote
# -- the legs would hang mid-stride forever. Seeding from rest also means each
# state change lands on a defined pose instead of a smear between two.

const ANIM_IDLE := "idle"
const ANIM_RUN := "run"
const ANIM_JUMP := "jump"
const ANIM_FALL := "fall"
const ANIM_DASH := "dash"
const ANIM_ATTACK := "attack"
const ANIM_HURT := "hurt"

## Matches the length of the "hurt" animation; also how long the tint stays
## ceded to it.
const HURT_DURATION := 0.25


## Builds the pose set in code rather than shipping an AnimationPlayer library in
## the .tscn, so the poses live next to the state machine that selects them and
## cannot silently drift away from the movement rules they illustrate.
func _build_animations() -> void:
	if _anim == null:
		return

	var lib: AnimationLibrary
	if _anim.has_animation_library(""):
		lib = _anim.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		_anim.add_animation_library("", lib)

	_build_idle(lib)
	_build_run(lib)
	_build_jump(lib)
	_build_fall(lib)
	_build_dash(lib)
	_build_attack(lib)
	_build_hurt(lib)


## Standing still: a slow breath. Torso and head rise by the same amount on the
## same curve, otherwise the 1px neck seam opens and closes twice a second.
func _build_idle(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual/Body:position", 0.0, Vector2.ZERO)
	_k("Visual/Body:position", 0.6, Vector2(0.0, -1.5))
	_k("Visual/Body:position", 1.2, Vector2.ZERO)
	_k("Visual/Head:position", 0.0, Vector2.ZERO)
	_k("Visual/Head:position", 0.6, Vector2(0.0, -1.5))
	_k("Visual/Head:position", 1.2, Vector2.ZERO)
	# Arms drift a third of the torso's travel: enough to read as alive.
	_k("Visual/ArmLeft:position", 0.6, Vector2(0.0, -0.5))
	_k("Visual/ArmRight:position", 0.6, Vector2(0.0, -0.5))
	_finish(lib, ANIM_IDLE, 1.2, true)


## Full sprint: one stride per 0.4s, legs and arms counter-swinging. The lean
## eases in and back out inside the cycle so the loop seam is the upright rest
## pose -- that is what keeps run -> idle from snapping.
func _build_run(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:rotation", 0.08, 0.08)
	_k("Visual:rotation", 0.32, 0.08)
	_k("Visual:rotation", 0.4, 0.0)
	# The torso bobs once per stride, peaking on each footfall.
	_k("Visual/Body:position", 0.1, Vector2(0.0, -1.5))
	_k("Visual/Body:position", 0.2, Vector2.ZERO)
	_k("Visual/Body:position", 0.3, Vector2(0.0, -1.5))
	_k("Visual/Body:position", 0.4, Vector2.ZERO)
	_k("Visual/Head:position", 0.1, Vector2(0.0, -1.5))
	_k("Visual/Head:position", 0.2, Vector2.ZERO)
	_k("Visual/Head:position", 0.3, Vector2(0.0, -1.5))
	_k("Visual/Head:position", 0.4, Vector2.ZERO)
	_k("Visual/LegLeft:position", 0.1, Vector2(3.0, -6.0))
	_k("Visual/LegLeft:position", 0.2, Vector2.ZERO)
	_k("Visual/LegLeft:position", 0.3, Vector2(-3.0, 4.0))
	_k("Visual/LegLeft:position", 0.4, Vector2.ZERO)
	_k("Visual/LegRight:position", 0.1, Vector2(-3.0, 4.0))
	_k("Visual/LegRight:position", 0.2, Vector2.ZERO)
	_k("Visual/LegRight:position", 0.3, Vector2(3.0, -6.0))
	_k("Visual/LegRight:position", 0.4, Vector2.ZERO)
	_k("Visual/ArmLeft:position", 0.1, Vector2(-3.0, 3.0))
	_k("Visual/ArmLeft:position", 0.2, Vector2.ZERO)
	_k("Visual/ArmLeft:position", 0.3, Vector2(3.0, -3.0))
	_k("Visual/ArmLeft:position", 0.4, Vector2.ZERO)
	_k("Visual/ArmRight:position", 0.1, Vector2(3.0, -3.0))
	_k("Visual/ArmRight:position", 0.2, Vector2.ZERO)
	_k("Visual/ArmRight:position", 0.3, Vector2(-3.0, 3.0))
	_k("Visual/ArmRight:position", 0.4, Vector2.ZERO)
	# Stretch on the power phase, tall on the recovery.
	_k("Visual/Body:scale", 0.1, Vector2(1.06, 0.97))
	_k("Visual/Body:scale", 0.2, Vector2.ONE)
	_k("Visual/Body:scale", 0.3, Vector2(1.06, 0.97))
	_k("Visual/Body:scale", 0.4, Vector2.ONE)
	_finish(lib, ANIM_RUN, 0.4, true)


## Take-off: legs tucked together and forward, arms thrown up. Held for the
## whole rise -- the pose, not the motion, is what sells the jump.
func _build_jump(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:rotation", 0.15, 0.05)
	_k("Visual:rotation", 0.3, 0.0)
	_k("Visual/Body:position", 0.3, Vector2(0.0, -1.0))
	_k("Visual/Head:position", 0.3, Vector2(0.0, -1.5))
	_k("Visual/LegLeft:position", 0.0, Vector2(3.0, -3.0))
	_k("Visual/LegLeft:position", 0.3, Vector2(3.0, -3.0))
	_k("Visual/LegRight:position", 0.0, Vector2(3.0, -3.0))
	_k("Visual/LegRight:position", 0.3, Vector2(3.0, -3.0))
	_k("Visual/ArmLeft:position", 0.0, Vector2(-1.0, -6.0))
	_k("Visual/ArmLeft:position", 0.3, Vector2(-1.0, -6.0))
	_k("Visual/ArmRight:position", 0.0, Vector2(1.0, -6.0))
	_k("Visual/ArmRight:position", 0.3, Vector2(1.0, -6.0))
	_k("Visual/Body:scale", 0.0, Vector2(0.94, 1.08))
	_k("Visual/Body:scale", 0.3, Vector2(0.94, 1.08))
	_finish(lib, ANIM_JUMP, 0.3, false)


## Descent: arms flung out sideways for balance, legs trailing apart.
func _build_fall(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:rotation", 0.3, -0.04)
	_k("Visual/ArmLeft:position", 0.0, Vector2(-5.0, -2.0))
	_k("Visual/ArmLeft:position", 0.3, Vector2(-5.0, -2.0))
	_k("Visual/ArmRight:position", 0.0, Vector2(5.0, -2.0))
	_k("Visual/ArmRight:position", 0.3, Vector2(5.0, -2.0))
	_k("Visual/LegLeft:position", 0.0, Vector2(-1.0, 3.0))
	_k("Visual/LegLeft:position", 0.3, Vector2(-1.0, 3.0))
	_k("Visual/LegRight:position", 0.0, Vector2(1.0, -2.0))
	_k("Visual/LegRight:position", 0.3, Vector2(1.0, -2.0))
	_k("Visual/Body:scale", 0.0, Vector2(0.96, 1.05))
	_k("Visual/Body:scale", 0.3, Vector2(0.96, 1.05))
	_finish(lib, ANIM_FALL, 0.3, false)


## Dash: the character throws itself forward, limbs trailing behind and the
## torso stretched along the direction of travel.
func _build_dash(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:rotation", 0.08, 0.3)
	_k("Visual:rotation", 0.25, 0.3)
	_k("Visual/Body:scale", 0.0, Vector2.ONE)
	_k("Visual/Body:scale", 0.08, Vector2(1.14, 0.94))
	_k("Visual/Body:scale", 0.25, Vector2(1.14, 0.94))
	_k("Visual/Body:position", 0.0, Vector2.ZERO)
	_k("Visual/Body:position", 0.25, Vector2(1.0, 0.0))
	_k("Visual/Head:position", 0.0, Vector2.ZERO)
	_k("Visual/Head:position", 0.25, Vector2(1.5, 0.0))
	_k("Visual/ArmLeft:position", 0.08, Vector2(-7.0, 2.0))
	_k("Visual/ArmLeft:position", 0.25, Vector2(-7.0, 2.0))
	_k("Visual/ArmRight:position", 0.08, Vector2(7.0, 2.0))
	_k("Visual/ArmRight:position", 0.25, Vector2(7.0, 2.0))
	_k("Visual/LegLeft:position", 0.0, Vector2(-6.0, 2.0))
	_k("Visual/LegLeft:position", 0.25, Vector2(-6.0, 2.0))
	_k("Visual/LegRight:position", 0.0, Vector2(-5.0, -3.0))
	_k("Visual/LegRight:position", 0.25, Vector2(-5.0, -3.0))
	_finish(lib, ANIM_DASH, 0.25, false)


## Attack: the right arm punches out and retracts. The rotation bump is the
## weight shift behind the punch; it returns to rest so the follow-up state
## starts from a known pose.
func _build_attack(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:rotation", 0.1, 0.06)
	_k("Visual:rotation", 0.3, 0.0)
	_k("Visual/ArmRight:position", 0.0, Vector2.ZERO)
	_k("Visual/ArmRight:position", 0.1, Vector2(9.0, -2.0))
	_k("Visual/ArmRight:position", 0.18, Vector2(8.0, -1.0))
	_k("Visual/ArmRight:position", 0.3, Vector2.ZERO)
	_k("Visual/Body:position", 0.1, Vector2(1.0, 0.0))
	_k("Visual/Body:position", 0.3, Vector2.ZERO)
	_finish(lib, ANIM_ATTACK, 0.3, false)


## Damage: recoil backwards plus a red flash. This is the one animation that
## drives modulate, which is why _apply_tint() stands down for its duration.
func _build_hurt(lib: AnimationLibrary) -> void:
	_rest_pose()
	_k("Visual:rotation", 0.0, -0.25)
	_k("Visual:rotation", 0.12, -0.12)
	_k("Visual:rotation", 0.25, 0.0)
	_k("Visual/Body:position", 0.0, Vector2(-2.0, 0.0))
	_k("Visual/Body:position", 0.25, Vector2.ZERO)
	_k("Visual/Head:position", 0.0, Vector2(-3.0, 1.0))
	_k("Visual/Head:position", 0.25, Vector2.ZERO)
	_k("Visual:modulate", 0.0, Color(1.0, 0.35, 0.35))
	_k("Visual:modulate", 0.15, Color(1.0, 0.35, 0.35))
	_k("Visual:modulate", 0.25, Color.WHITE)
	_finish(lib, ANIM_HURT, 0.25, false)


## Seeding every animated property at the rest pose on t=0. See the note above:
## omitting a property here is what leaves a limb frozen mid-stride.
func _rest_pose() -> void:
	_pending.clear()
	_k("Visual:rotation", 0.0, 0.0)
	_k("Visual:modulate", 0.0, Color.WHITE)
	_k("Visual/Body:position", 0.0, Vector2.ZERO)
	_k("Visual/Body:scale", 0.0, Vector2.ONE)
	_k("Visual/Head:position", 0.0, Vector2.ZERO)
	_k("Visual/ArmLeft:position", 0.0, Vector2.ZERO)
	_k("Visual/ArmRight:position", 0.0, Vector2.ZERO)
	_k("Visual/LegLeft:position", 0.0, Vector2.ZERO)
	_k("Visual/LegRight:position", 0.0, Vector2.ZERO)


## Queues one key. Re-queuing at a time that is already used replaces that key
## instead of inserting a duplicate, which is what lets every builder lay down
## the rest pose first and then overwrite only the parts it actually moves.
func _k(path: String, time: float, value: Variant) -> void:
	if not _pending.has(path):
		_pending[path] = []
	var keys: Array = _pending[path]
	for i in keys.size():
		if is_equal_approx(float(keys[i][0]), time):
			keys[i] = [time, value]
			return
	keys.append([time, value])
	keys.sort_custom(_key_comes_before)


func _key_comes_before(a: Array, b: Array) -> bool:
	return float(a[0]) < float(b[0])


## Turns the keys queued by _k() into a real animation and hands it to the
## library. Replaces any previous build, so this is safe to call again.
func _finish(lib: AnimationLibrary, anim_name: String, length: float, looping: bool) -> void:
	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)

	var anim := Animation.new()
	for path in _pending:
		var track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, NodePath(String(path)))
		for key in _pending[path]:
			anim.track_insert_key(track, float(key[0]), key[1])

	# Length last: assigning it truncates any key past the end.
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	lib.add_animation(anim_name, anim)
	_pending.clear()


## Picks the pose that matches the simulated state. Runs once per physics tick
## after _sync_visual, and deliberately only acts on a *change* of state:
## calling play() every frame would restart a one-shot animation on its own
## first frame, so the dash would never advance past frame one.
func _update_animation(delta: float) -> void:
	if _anim == null or movement == null or body == null:
		return
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	var next := _pick_animation()
	if next == _current_anim:
		return
	_play(next)


## Hurt outranks everything else: a hit has to be legible even mid-dash.
func _pick_animation() -> String:
	if _hurt_timer > 0.0:
		return ANIM_HURT
	if movement.is_dashing:
		return ANIM_DASH
	if movement.is_attacking:
		return ANIM_ATTACK
	if not body.is_grounded():
		return ANIM_JUMP if body.velocity.y < 0.0 else ANIM_FALL
	if absf(body.velocity.x) > 10.0:
		return ANIM_RUN
	return ANIM_IDLE


func _play(anim_name: String) -> void:
	if not _anim.has_animation(anim_name):
		return
	var was_hurt := _current_anim == ANIM_HURT
	_current_anim = anim_name
	_anim.play(anim_name)
	if was_hurt and anim_name != ANIM_HURT:
		# Hand modulate back on the frame the hurt pose ends rather than waiting
		# for _apply_tint to notice, which would leave the red up one extra frame.
		# The timer has to be cleared here too: _apply_tint stands down while it
		# runs, so calling it with the timer still ticking would re-stand-down
		# and leave the character stuck red.
		_hurt_timer = 0.0
		_apply_tint()


## Entry point for damage feedback. Nothing calls this yet -- wiring it to
## GameManager.damage is a one-liner once that path is wanted.
func play_hurt() -> void:
	_hurt_timer = HURT_DURATION


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


## Apply selected character's gameplay modifiers to the movement config.
func _apply_character_modifiers(config: PlayerMovementConfig) -> void:
	var char_id := SaveManager.data.get_selected_character()
	var char_data := ContentDB.get_character(char_id)
	var mods: Dictionary = char_data.gameplay_modifiers as Dictionary
	
	# Speed modifiers
	if mods.has("max_speed_multiplier"):
		config.max_speed *= float(mods["max_speed_multiplier"])
		config.max_air_speed *= float(mods["max_speed_multiplier"])
	if mods.has("acceleration_multiplier"):
		config.ground_acceleration *= float(mods["acceleration_multiplier"])
		config.air_acceleration *= float(mods["acceleration_multiplier"])
	if mods.has("air_control_multiplier"):
		config.air_acceleration *= float(mods["air_control_multiplier"])
	
	# Jump modifiers
	if mods.has("jump_buffer_multiplier"):
		config.jump_buffer_time *= float(mods["jump_buffer_multiplier"])
	if mods.has("coyote_time_multiplier"):
		config.coyote_time *= float(mods["coyote_time_multiplier"])
	if mods.has("double_jump_force_multiplier"):
		config.double_jump_force *= float(mods["double_jump_force_multiplier"])
	
	# Dash modifiers
	if mods.has("dash_cooldown_multiplier"):
		config.dash_cooldown *= float(mods["dash_cooldown_multiplier"])
	if mods.has("dash_duration_multiplier"):
		config.dash_duration *= float(mods["dash_duration_multiplier"])
	
	# Defense modifiers (handled in GameManager)
	# damage_taken_multiplier, knockback_resistance
	
	# Special abilities
	if mods.has("wall_jump_enabled") and bool(mods["wall_jump_enabled"]):
		# Wall jump would need additional implementation
		pass
	if mods.has("air_dash_charges"):
		config.air_dashes = int(mods["air_dash_charges"])
	if mods.has("ground_slam_attack") and bool(mods["ground_slam_attack"]):
		# Ground slam attack on landing from high velocity
		pass
	if mods.has("charge_attack_enabled") and bool(mods["charge_attack_enabled"]):
		# Charge attack
		pass
	if mods.has("crush_enemies_on_land") and bool(mods["crush_enemies_on_land"]):
		# Crush enemies on hard landing
		pass
	if mods.has("dash_damage_immunity") and bool(mods["dash_damage_immunity"]):
		# Immunity during dash
		pass
	if mods.has("lightning_trail") and bool(mods["lightning_trail"]):
		# Visual effect during dash
		pass
	if mods.has("secret_detection_radius"):
		# Expanded secret detection
		pass
	if mods.has("collectible_magnet_radius"):
		# Magnet for collectibles
		pass
	if mods.has("fragment_finder") and bool(mods["fragment_finder"]):
		# Show fragment locations
		pass


## Called by Checkpoint area when player touches it.
## Updates the respawn point in GameManager and provides visual feedback.
func activate_checkpoint(index: int, position: Vector2, total: int) -> void:
	GameManager.register_checkpoint(index, position, total)
	# Visual feedback handled by Checkpoint node itself via _activated state
	# Could add screen flash, sound, or HUD notification here later