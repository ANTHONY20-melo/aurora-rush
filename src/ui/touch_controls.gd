extends Control
class_name TouchControls
## Virtual on-screen controls for touch devices.
## Built entirely in code — no external textures needed.

signal input_changed(input: PlayerInput)

@export var force_visible: bool = false
@export var joystick_deadzone: float = 0.15

var _joy_base: ColorRect
var _joy_stick: ColorRect
var _btn_jump: Button
var _btn_dash: Button
var _btn_attack: Button

var _joy_active: bool = false
var _joy_id: int = -1
var _joy_center: Vector2
var _axis_x: float = 0.0

var _jump_down: bool = false
var _dash_down: bool = false
var _attack_down: bool = false

var _prev_jump: bool = false
var _prev_dash: bool = false
var _prev_attack: bool = false


func _ready() -> void:
	if not force_visible:
		visible = false

	_build_ui()
	_joy_center = _joy_base.global_position


func _build_ui() -> void:
	# --- Joystick (left side) ---
	var joy_container := Control.new()
	joy_container.name = "Joystick"
	joy_container.layout_mode = 2
	joy_container.anchors_preset = 0
	joy_container.anchor_left = 0.0
	joy_container.anchor_top = 1.0
	joy_container.anchor_right = 0.0
	joy_container.anchor_bottom = 1.0
	joy_container.offset_left = 40.0
	joy_container.offset_top = -180.0
	joy_container.offset_right = 180.0
	joy_container.offset_bottom = -40.0
	add_child(joy_container)

	_joy_base = ColorRect.new()
	_joy_base.name = "Base"
	_joy_base.layout_mode = 3
	_joy_base.anchors_preset = 15
	_joy_base.anchor_right = 1.0
	_joy_base.anchor_bottom = 1.0
	_joy_base.grow_horizontal = 2
	_joy_base.grow_vertical = 2
	_joy_base.color = Color(0.2, 0.2, 0.3, 0.5)
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base.visible = false
	joy_container.add_child(_joy_base)

	_joy_stick = ColorRect.new()
	_joy_stick.name = "Stick"
	_joy_stick.layout_mode = 3
	_joy_stick.anchors_preset = 15
	_joy_stick.anchor_right = 1.0
	_joy_stick.anchor_bottom = 1.0
	_joy_stick.grow_horizontal = 2
	_joy_stick.grow_vertical = 2
	_joy_stick.color = Color(0.4, 0.8, 1.0, 0.8)
	_joy_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_stick.visible = false
	joy_container.add_child(_joy_stick)

	_joy_base.gui_input.connect(Callable(self, "_on_joystick_gui_input"))
	_joy_stick.gui_input.connect(Callable(self, "_on_joystick_gui_input"))

	# --- Buttons (right side) ---
	var btn_container := HBoxContainer.new()
	btn_container.name = "Buttons"
	btn_container.layout_mode = 2
	btn_container.anchors_preset = 6
	btn_container.anchor_left = 1.0
	btn_container.anchor_top = 1.0
	btn_container.anchor_right = 1.0
	btn_container.anchor_bottom = 1.0
	btn_container.offset_left = -260.0
	btn_container.offset_top = -180.0
	btn_container.offset_right = -20.0
	btn_container.offset_bottom = -40.0
	btn_container.add_theme_constant_override("separation", 20)
	add_child(btn_container)

	_btn_jump = _make_btn("Jump", Color(0.3, 0.7, 1.0))
	_btn_dash = _make_btn("Dash", Color(1.0, 0.6, 0.2))
	_btn_attack = _make_btn("Attack", Color(1.0, 0.3, 0.5))
	btn_container.add_child(_btn_jump)
	btn_container.add_child(_btn_dash)
	btn_container.add_child(_btn_attack)

	_btn_jump.gui_input.connect(Callable(self, "_on_jump_gui_input"))
	_btn_dash.gui_input.connect(Callable(self, "_on_dash_gui_input"))
	_btn_attack.gui_input.connect(Callable(self, "_on_attack_gui_input"))


func _make_btn(label: String, base_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 80)
	btn.text = label
	
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = base_color
	style_normal.corner_radius_top_left = 12
	style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12
	style_normal.corner_radius_bottom_right = 12
	style_normal.border_width_bottom = 3
	style_normal.border_color = base_color.darkened(0.3)
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = base_color.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return btn


func _process(_delta: float) -> void:
	if not visible:
		return

	var input := PlayerInput.new()
	input.move_x = clampf(_axis_x, -1.0, 1.0)
	input.jump_held = _jump_down
	input.jump_pressed = _jump_down and not _prev_jump
	input.jump_released = (not _jump_down) and _prev_jump
	input.dash_pressed = _dash_down and not _prev_dash
	input.attack_pressed = _attack_down and not _prev_attack

	_prev_jump = _jump_down
	_prev_dash = _dash_down
	_prev_attack = _attack_down

	emit_signal("input_changed", input)


func _on_joystick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _joy_active:
				_joy_active = true
				_joy_id = event.index
				_joy_center = event.position
				_joy_base.global_position = _joy_center
				_joy_stick.global_position = _joy_center
				_joy_base.show()
				_joy_stick.show()
		elif event.index == _joy_id:
			_joy_active = false
			_joy_id = -1
			_joy_base.hide()
			_joy_stick.hide()
			_axis_x = 0.0
	elif event is InputEventScreenDrag and event.index == _joy_id and _joy_active:
		var dir: Vector2 = (event.position - _joy_center).normalized()
		var dist := _joy_center.distance_to(event.position)
		var max_r := _joy_base.size.x * 0.5
		dist = min(dist, max_r)
		_joy_stick.global_position = _joy_center + dir * dist
		_axis_x = dir.x * (dist / max_r)
		if absf(_axis_x) < joystick_deadzone:
			_axis_x = 0.0


func _on_jump_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_jump_down = event.pressed


func _on_dash_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_dash_down = event.pressed


func _on_attack_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_attack_down = event.pressed