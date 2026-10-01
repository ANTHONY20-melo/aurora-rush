extends CanvasLayer
## Gameplay HUD: energy bar, timer, score, combo.

@onready var _energy_value: Label = $Root/TopLeft/EnergyBar/EnergyValue
@onready var _energy_bar: ColorRect = $Root/TopLeft/EnergyBar/EnergyFill/EnergyFillBar
@onready var _time_label: Label = $Root/TopLeft/TimeScore/TimeLabel
@onready var _score_label: Label = $Root/TopLeft/TimeScore/ScoreLabel
@onready var _combo_label: Label = $Root/TopLeft/Combo

func _ready() -> void:
	_setup_fonts()
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.combo_broken.connect(_on_combo_broken)
	EventBus.level_time_updated.connect(_on_time_updated)
	GameManager.connect("player_damaged", _on_health_changed)
	GameManager.connect("player_healed", _on_health_changed)
	_refresh_energy()

func _setup_fonts() -> void:
	for label in [_energy_value, _time_label, _score_label, _combo_label]:
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
		label.add_theme_constant_override("outline_size", 2)
	
	_time_label.add_theme_font_size_override("font_size", 22)
	_score_label.add_theme_font_size_override("font_size", 18)
	_combo_label.add_theme_font_size_override("font_size", 20)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))

func _on_score_changed(score: int, combo: int, multiplier: float) -> void:
	_score_label.text = Fmt.score(score)

func _on_combo_changed(combo: int, multiplier: float, time_left: float) -> void:
	if combo > 1:
		_combo_label.text = "x%s COMBO" % Fmt.multiplier(multiplier)
		_combo_label.visible = true
	else:
		_combo_label.visible = false

func _on_combo_broken(lost: int) -> void:
	_combo_label.visible = false

func _on_time_updated(elapsed: float) -> void:
	_time_label.text = Fmt.time(elapsed)

func _on_health_changed(current: float, max_h: float, amount: float = 0.0, source: String = "") -> void:
	_refresh_energy()

func _refresh_energy() -> void:
	var energy: int = GameManager.energy
	_energy_value.text = "%d" % energy
	var ratio := clampf(float(energy) / 100.0, 0.0, 1.0)
	var bar_width := 120.0 * ratio
	_energy_bar.size.x = bar_width
	
	if energy <= 20:
		_energy_bar.color = Color(0.9, 0.3, 0.2)
		_energy_value.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
	elif energy <= 50:
		_energy_bar.color = Color(1.0, 0.7, 0.2)
		_energy_value.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	else:
		_energy_bar.color = Color(0.36, 0.87, 1.0)
		_energy_value.add_theme_color_override("font_color", Color(0.36, 0.87, 1.0))