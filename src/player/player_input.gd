class_name PlayerInput
extends RefCounted
## One frame of player intent, decoupled from Godot's Input singleton.
##
## The movement system never calls Input.is_action_pressed. It receives this
## struct instead, which is why the whole controller can be driven by a test at
## 60 Hz with no window, no device and no event plumbing.

var move_x: float = 0.0        ## -1 .. 1, already deadzoned
var jump_pressed: bool = false ## rising edge this frame
var jump_held: bool = false
var jump_released: bool = false
var dash_pressed: bool = false
var attack_pressed: bool = false

## Environment modifiers, set by the level each frame.
var in_water: bool = false
var in_speed_zone: bool = false


static func neutral() -> PlayerInput:
	return PlayerInput.new()


## Build from raw axis/button state. Edge detection lives in PlayerController
## because only it can see the previous frame.
static func from_axes(axis: float, jump_down: bool, dash_down: bool, attack_down: bool,
		previous_jump: bool, previous_dash: bool, previous_attack: bool) -> PlayerInput:
	var input := PlayerInput.new()
	input.move_x = axis
	input.jump_held = jump_down
	input.jump_pressed = jump_down and not previous_jump
	input.jump_released = (not jump_down) and previous_jump
	input.dash_pressed = dash_down and not previous_dash
	input.attack_pressed = attack_down and not previous_attack
	return input
