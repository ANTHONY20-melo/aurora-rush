class_name PlayerMovementConfig
extends RefCounted
## Every number that defines how the player feels, in one place.
##
## The design brief for a high-speed platformer is that the movement must be
## learnable in thirty seconds and still reward mastery after fifty hours. That
## balance lives entirely in this file. Gameplay code reads these fields and
## never contains a literal, so feel can be retuned without touching logic and
## without risking a regression in behaviour.
##
## Units: pixels and seconds. The engine runs at a fixed 60 Hz physics tick.

# --- horizontal -------------------------------------------------------------

## Top speed on foot, px/s. Fast enough to cross a screen in ~2.5s.
var max_speed: float = 520.0

## Speed cap while airborne. Slightly below max_speed so a jump cannot grant
## free top speed from a standstill.
var max_air_speed: float = 470.0

## Acceleration toward the input direction, px/s^2.
var ground_acceleration: float = 2900.0
var air_acceleration: float = 1750.0

## Deceleration when no input is held, px/s^2. Higher than ground acceleration
## so stopping feels crisp rather than floaty.
var ground_deceleration: float = 3400.0
var air_deceleration: float = 780.0

## When the input reverses direction, acceleration is multiplied by this.
## The single biggest contributor to a platformer feeling responsive.
var turn_boost: float = 2.0

## Multiplier applied to acceleration while above this fraction of max speed.
## Keeps top speed approachable instead of an exponential grind.
var sprint_acceleration_boost: float = 1.35
var sprint_speed_threshold: float = 0.72

# --- gravity ----------------------------------------------------------------

## Downward acceleration, px/s^2.
var gravity: float = 2450.0

## Gravity while rising and the jump button is still held.
var jump_hold_gravity: float = 1750.0

## Gravity within this speed of the apex. Reduced gravity gives the player a
## readable hang time to aim a landing instead of a single frame of control.
var apex_gravity_scale: float = 0.55
var apex_speed_threshold: float = 140.0

## Extra gravity once falling, to make the descent feel decisive.
var fall_gravity_scale: float = 1.35

## Terminal velocity, px/s.
var max_fall_speed: float = 1150.0

# --- jumping ----------------------------------------------------------------

## Upward impulse, px/s (negative is up).
var jump_force: float = -790.0

## Upward impulse for a mid-air jump.
var double_jump_force: float = -700.0

## Mid-air jumps allowed before touching the ground again.
var air_jumps: int = 1

## Releasing jump while still rising scales the remaining upward speed by this.
## The variable-height jump: tap for a hop, hold for height.
var jump_cut_multiplier: float = 0.42

## Grace period after walking off a ledge during which a jump still works.
## Without it, players read a jump as unresponsive at the exact moment they
## commit to it.
var coyote_time: float = 0.11

## How long a jump press is remembered before landing. Lets a player press jump
## slightly early and still get the jump.
var jump_buffer_time: float = 0.13

## Downward velocity retained when hitting the ground after a fall, px/s.
## Non-zero so a long fall flows into a run instead of stopping dead.
var landing_retain_speed: float = 180.0

## Vertical speed above which a landing counts as hard (camera shake, dust).
var hard_landing_speed: float = 760.0

## Downward speed above which the landing kills fall momentum and gives a
## small upward pop. Punishes blind platforming without being lethal.
var bounce_speed_threshold: float = 980.0
var bounce_force: float = -430.0

# --- dash -------------------------------------------------------------------

## Horizontal speed during a dash, px/s.
var dash_speed: float = 980.0

## How long a dash lasts, seconds.
var dash_duration: float = 0.15

## Minimum time between dashes, seconds.
var dash_cooldown: float = 0.38

## Dashes available while airborne. One air dash is the difference between a
## movement system and a fighting game.
var air_dashes: int = 1

## Dash end speed as a fraction of dash speed. Below 1.0 so the dash always
## bleeds momentum instead of granting a free speed boost forever.
var dash_exit_speed_factor: float = 0.72

## Upward velocity set at the start of a dash when the player is grounded.
var dash_ground_lift: float = -60.0

## Dashes ignore gravity entirely.
var dash_ignores_gravity: bool = true

# --- surfaces ---------------------------------------------------------------

## Multiplier on ground deceleration while standing on a low-friction surface.
## Slopes are how a fast platformer lets you *gain* speed.
var slick_friction_scale: float = 0.12

## Speed gained per second while descending a slope, px/s^2. Positive because
## running downhill should reward the player.
var slope_acceleration: float = 900.0

## Ceiling on slope-assisted speed, px/s, above max_speed.
var slope_speed_bonus_cap: float = 460.0

## Speed lost per second while climbing a slope, px/s^2.
var slope_climb_penalty: float = 1100.0

## Multiplier on gravity while running up a slope.
var slope_gravity_scale: float = 1.25

## Maximum slope (radians) the player can walk up without sliding.
var max_walkable_slope: float = deg_to_rad(55.0)

# --- water / liquid ---------------------------------------------------------

## Horizontal and vertical speed multipliers while submerged.
var water_speed_scale: float = 0.62
var water_gravity_scale: float = 0.45
## A single jump while submerged, as a fraction of jump_force.
var water_jump_scale: float = 0.7

# --- high speed zones -------------------------------------------------------

## Extra acceleration inside a "high speed" area, so the level design can hand
## the player a boost rather than the code hard-coding one.
var speed_zone_acceleration_boost: float = 1.9
var speed_zone_max_speed_boost: float = 320.0


## Apply accessibility assist: more forgiving timings, not different physics.
## Assist mode must never make the game easier by changing the rules silently;
## it widens the input windows.
func with_assist_mode() -> PlayerMovementConfig:
	coyote_time = 0.18
	jump_buffer_time = 0.22
	turn_boost = 2.4
	dash_cooldown = 0.28
	return self


## Copy so a per-run instance can be tweaked without mutating the shared default.
func duplicate_config() -> PlayerMovementConfig:
	var copy := PlayerMovementConfig.new()
	for property in get_property_list():
		if not (property["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var name := String(property["name"])
		if name == "script":
			continue
		copy.set(name, get(name))
	return copy


## Sanity check used by tests: a config that cannot produce a playable
## character is a content bug, not a player-facing one.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if max_speed <= 0.0:
		problems.append("max_speed must be positive")
	if ground_acceleration <= 0.0:
		problems.append("ground_acceleration must be positive")
	if max_air_speed > max_speed:
		problems.append("max_air_speed must not exceed max_speed")
	if jump_force >= 0.0:
		problems.append("jump_force must be negative (upward)")
	if not _is_unit_range(jump_cut_multiplier):
		problems.append("jump_cut_multiplier must be in (0, 1]")
	if max_fall_speed <= max_speed:
		problems.append("max_fall_speed must exceed max_speed")
	if not _is_unit_range(dash_exit_speed_factor):
		problems.append("dash_exit_speed_factor must be in (0, 1]")
	if coyote_time < 0.0 or jump_buffer_time < 0.0:
		problems.append("coyote_time and jump_buffer_time cannot be negative")
	if not _is_unit_range(apex_gravity_scale):
		problems.append("apex_gravity_scale must be in (0, 1]")
	if not _is_unit_range(water_speed_scale):
		problems.append("water_speed_scale must be in (0, 1]")
	if max_walkable_slope <= 0.0 or max_walkable_slope >= PI * 0.5:
		problems.append("max_walkable_slope must be in (0, 90 degrees)")
	return problems


## True for values in the half-open range (0, 1].
##
## GDScript has no chained comparison operators: writing `0.0 < value <= 1.0`
## parses as `(0.0 < value) <= 1.0`, comparing a bool against a float and
## failing to compile. Every range check goes through this helper instead.
func _is_unit_range(value: float) -> bool:
	return value > 0.0 and value <= 1.0
