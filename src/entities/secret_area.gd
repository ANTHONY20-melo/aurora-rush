class_name SecretArea
extends Area2D
## Secret area: detects player entry and triggers discovery feedback.

@export var area_id: String = ""
@export var reward_energy: int = 10

var _discovered: bool = false
var _inside: bool = false
var _reveal_time: float = 0.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	monitorable = false

func _process(delta: float) -> void:
	if _discovered and _inside:
		_reveal_time += delta
		modulate = Color(1.0, 1.0, 1.0, 0.3 + 0.2 * sin(_reveal_time * 8.0))

func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("player_hitbox"):
		return
	_inside = true
	if not _discovered:
		_discovered = true
		AudioDirector.play_sfx("env_secret", -3.0)
		EventBus.secret_area_entered.emit(area_id)
		GameManager.register_secret(area_id, global_position)
		_show_discovery_popup()

func _on_area_exited(area: Area2D) -> void:
	if area.is_in_group("player_hitbox"):
		_inside = false

func _show_discovery_popup() -> void:
	var label := Label.new()
	label.text = "AREA SECRETA"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, -60)
	add_child(label)
	
	var tween := create_tween()
	tween.tween_property(label, "position:y", -100, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func() -> void: label.queue_free())

func _draw() -> void:
	if _discovered:
		return
	var color := Color(0.4, 0.6, 0.9, 0.15)
	var rect := Rect2(-100, -100, 200, 200)
	if has_node("Collision"):
		var shape := get_node("Collision").shape as RectangleShape2D
		if shape:
			rect = Rect2(-shape.size.x * 0.5, -shape.size.y * 0.5, shape.size.x, shape.size.y)
	draw_rect(rect, color)