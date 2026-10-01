extends Control
## Character selection screen.

@onready var _fragments_value: Label = $TopBar/Currency/FragmentsValue
@onready var _crystals_value: Label = $TopBar/Currency/CrystalsValue
@onready var _back_btn: Button = $TopBar/BackBtn
@onready var _char_list: HBoxContainer = $CharacterList
@onready var _char_name: Label = $DetailsPanel/CharName
@onready var _char_title: Label = $DetailsPanel/CharTitle
@onready var _char_desc: Label = $DetailsPanel/CharDesc
@onready var _stat_speed: Label = $DetailsPanel/StatsContainer/StatSpeed/StatSpeedValue
@onready var _stat_defense: Label = $DetailsPanel/StatsContainer/StatDefense/StatDefenseValue
@onready var _stat_control: Label = $DetailsPanel/StatsContainer/StatControl/StatControlValue
@onready var _unlock_info: Label = $DetailsPanel/UnlockInfo
@onready var _select_btn: Button = $DetailsPanel/SelectBtn
@onready var _unlock_btn: Button = $DetailsPanel/UnlockBtn

var _characters: Array = []
var _char_buttons: Array[Button] = []
var _selected_index: int = 0
var _selected_char_id: String = "aero"

func _ready() -> void:
	_setup_fonts()
	_back_btn.pressed.connect(_on_back_pressed)
	_select_btn.pressed.connect(_on_select_pressed)
	_unlock_btn.pressed.connect(_on_unlock_pressed)
	
	_back_btn.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
	_select_btn.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
	_unlock_btn.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
	
	_back_btn.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))
	_select_btn.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))
	_unlock_btn.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_unlock", -4.0))
	
	_load_characters()
	_refresh_currency()
	_select_char_at(0)

func _setup_fonts() -> void:
	# Typed array: an untyped Array makes `label` a Variant, and assigning to an
	# attribute of a Variant is rejected by the parser.
	var labels: Array[Label] = [
		_char_name, _char_title, _char_desc,
		_stat_speed, _stat_defense, _stat_control, _unlock_info,
	]
	for label in labels:
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	_char_name.add_theme_font_size_override("font_size", 32)
	_char_name.add_theme_color_override("font_color", Color(0.62, 0.94, 1.0))
	_char_title.add_theme_font_size_override("font_size", 20)
	_char_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	_char_desc.add_theme_font_size_override("font_size", 16)
	_char_desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_unlock_info.add_theme_font_size_override("font_size", 16)

func _load_characters() -> void:
	ContentDB.ensure_loaded()
	_characters = ContentDB.get_all_characters()
	
	# Clear existing buttons
	for btn in _char_buttons:
		btn.queue_free()
	_char_buttons.clear()
	
	for i: int in _characters.size():
		var char: Dictionary = _characters[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 140)
		btn.size_flags_horizontal = 4
		btn.size_flags_vertical = 4
		
		# Create character preview
		var vbox := VBoxContainer.new()
		# theme_override_constants/separation is not an identifier and not a Godot 4
		# API; the supported form is add_theme_constant_override.
		vbox.add_theme_constant_override("separation", 8)
		vbox.alignment = 1
		
		var name_label := Label.new()
		name_label.text = String(char.name)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)
		
		var title_label := Label.new()
		title_label.text = String(char.title)
		title_label.add_theme_font_size_override("font_size", 12)
		title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title_label)
		
		# Stats preview
		var stats_hbox := HBoxContainer.new()
		stats_hbox.add_theme_constant_override("separation", 10)
		stats_hbox.alignment = 1

		var stats: Dictionary = char.get("stats", {})
		for stat_key in ["speed", "defense", "control"]:
			var stat_vbox := VBoxContainer.new()
			stat_vbox.add_theme_constant_override("separation", 2)
			stat_vbox.alignment = 1
			
			var icon := Label.new()
			icon.text = {"speed": "⚡", "defense": "🛡", "control": "🎯"}[stat_key]
			icon.add_theme_font_size_override("font_size", 16)
			icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stat_vbox.add_child(icon)
			
			var value := int(stats.get(stat_key, 1))
			var stars := "★".repeat(value) + "☆".repeat(5 - value)
			var star_label := Label.new()
			star_label.text = stars
			star_label.add_theme_font_size_override("font_size", 12)
			star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stat_vbox.add_child(star_label)
			
			stats_hbox.add_child(stat_vbox)
		
		vbox.add_child(stats_hbox)
		btn.add_child(vbox)
		
		# Lock overlay
		var lock_overlay := ColorRect.new()
		lock_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
		lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_overlay.visible = false
		lock_overlay.name = "LockOverlay"
		btn.add_child(lock_overlay)
		
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.add_theme_font_size_override("font_size", 28)
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_label.name = "LockLabel"
		lock_label.visible = false
		btn.add_child(lock_label)
		
		var char_id := String(char.id)
		btn.pressed.connect(_on_char_pressed.bind(i, char_id))
		btn.focus_entered.connect(_on_char_focused.bind(i, char_id))
		_char_buttons.append(btn)
		_char_list.add_child(btn)
	
	# Update lock states
	_update_lock_states()

func _update_lock_states() -> void:
	for i: int in _char_buttons.size():
		var btn: Button = _char_buttons[i]
		var char: Dictionary = _characters[i]
		var char_id := String(char.id)
		var unlocked := SaveManager.data.is_character_unlocked(char_id)
		
		var lock_overlay := btn.get_node_or_null("LockOverlay")
		var lock_label := btn.get_node_or_null("LockLabel")
		
		if lock_overlay:
			lock_overlay.visible = not unlocked
		if lock_label:
			lock_label.visible = not unlocked
			if not unlocked:
				var cost := int(char.get("unlock_cost", 0))
				lock_label.text = "🔒 %d ◆" % cost

func _on_char_pressed(index: int, char_id: String) -> void:
	AudioDirector.play_sfx("ui_confirm", -4.0)
	_select_char_at(index)

func _on_char_focused(index: int, char_id: String) -> void:
	AudioDirector.play_sfx("ui_move", -6.0)
	_select_char_at(index)

func _select_char_at(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return
	
	_selected_index = index
	_selected_char_id = String(_characters[index].id)
	
	# Update button visuals
	for i: int in _char_buttons.size():
		var btn := _char_buttons[i]
		var selected := (i == index)
		if selected:
			btn.add_theme_stylebox_override("normal", _create_border_style(Color(0.36, 0.87, 1.0)))
			btn.add_theme_stylebox_override("focus", _create_border_style(Color(0.36, 0.87, 1.0), true))
		else:
			btn.add_theme_stylebox_override("normal", _create_border_style(Color(0.2, 0.3, 0.4)))
			btn.add_theme_stylebox_override("focus", _create_border_style(Color(0.4, 0.5, 0.6), true))
	
	_update_details()
	_select_btn.grab_focus()

func _create_border_style(color: Color, is_focus: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.9)
	style.border_width_top = 3.0 if is_focus else 2.0
	style.border_width_bottom = 3.0 if is_focus else 2.0
	style.border_width_left = 3.0 if is_focus else 2.0
	style.border_width_right = 3.0 if is_focus else 2.0
	style.border_color = color
	style.corner_radius_top_left = 8.0
	style.corner_radius_top_right = 8.0
	style.corner_radius_bottom_left = 8.0
	style.corner_radius_bottom_right = 8.0
	return style

func _update_details() -> void:
	# _characters is an untyped Array, so every read out of it is a Variant and
	# cannot be inferred with :=. Each level is narrowed explicitly.
	var char: Dictionary = _characters[_selected_index]
	var char_id := String(char.id)
	var unlocked := SaveManager.data.is_character_unlocked(char_id)

	var color_arr: Array = char.get("color", [])
	var char_color := Color(1, 1, 1)
	if color_arr.size() >= 3:
		char_color = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]), 1.0)

	_char_name.text = String(char.name)
	_char_name.add_theme_color_override("font_color", char_color)
	_char_title.text = String(char.title)
	_char_desc.text = String(char.description)

	var stats: Dictionary = char.get("stats", {})
	_stat_speed.text = "★".repeat(int(stats.get("speed", 1))) + "☆".repeat(5 - int(stats.get("speed", 1)))
	_stat_defense.text = "★".repeat(int(stats.get("defense", 1))) + "☆".repeat(5 - int(stats.get("defense", 1)))
	_stat_control.text = "★".repeat(int(stats.get("control", 1))) + "☆".repeat(5 - int(stats.get("control", 1)))
	
	if unlocked:
		_unlock_info.text = "DESBLOQUEADO"
		_unlock_info.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		_select_btn.visible = true
		_select_btn.disabled = (char_id == SaveManager.data.get_selected_character())
		_select_btn.text = "SELECIONAR" if char_id != SaveManager.data.get_selected_character() else "SELECIONADO"
		_unlock_btn.visible = false
	else:
		var cost := int(char.get("unlock_cost", 0))
		var req := String(char.get("unlock_requirement", ""))
		_unlock_info.text = "%s\nCusto: %d fragmentos" % [req, cost]
		_unlock_info.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		_select_btn.visible = false
		_unlock_btn.visible = true
		_unlock_btn.disabled = SaveManager.data.energy_fragments < cost
		_unlock_btn.text = "DESBLOQUEAR (%d ◆)" % cost

func _refresh_currency() -> void:
	_fragments_value.text = "%d" % SaveManager.data.energy_fragments
	_crystals_value.text = "%d" % SaveManager.data.aurora_crystals

func _on_select_pressed() -> void:
	AudioDirector.play_sfx("ui_confirm", -4.0)
	SaveManager.data.select_character(_selected_char_id)
	SaveManager.save_game()
	_update_details()

func _on_unlock_pressed() -> void:
	var char: Dictionary = _characters[_selected_index]
	var char_id := String(char.id)
	var cost := int(char.get("unlock_cost", 0))
	
	if SaveManager.data.spend_energy_fragments(cost):
		AudioDirector.play_sfx("ui_unlock", -3.0)
		SaveManager.data.unlock_character(char_id)
		SaveManager.save_game()
		_update_lock_states()
		_update_details()
		_refresh_currency()
		EventBus.achievement_unlocked.emit("char_%s" % char_id, String(char.name), "Personagem desbloqueado!")
	else:
		AudioDirector.play_sfx("ui_denied", -4.0)

func _on_back_pressed() -> void:
	AudioDirector.play_sfx("ui_back", -4.0)
	SceneDirector.to_main_menu()