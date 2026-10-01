extends Control
## Main menu: the hub the player returns to between runs.
##
## Only buttons that lead somewhere real are shown. Screens that do not exist
## yet are absent rather than present-and-broken, so nothing here can dead-end.

@onready var _title: Label = $Background/Center/Column/Title
@onready var _tagline: Label = $Background/Center/Column/Tagline
@onready var _play: Button = $Background/Center/Column/Buttons/Play
@onready var _characters: Button = $Background/Center/Column/Buttons/Characters
@onready var _quit: Button = $Background/Center/Column/Buttons/Quit
@onready var _status: Label = $Background/Center/Column/Status


func _ready() -> void:
	_configure(_title, 62, Color(0.62, 0.94, 1.0))
	_configure(_tagline, 17, Color(0.45, 0.58, 0.70))
	_configure(_status, 13, Color(0.95, 0.72, 0.45))

	_play.pressed.connect(_on_play_pressed)
	_characters.pressed.connect(_on_characters_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_play.grab_focus()

	AudioDirector.play_music("menu", 1.0)
	_refresh_status()
	# Keyboard/gamepad navigation is expected without touching the mouse.
	_play.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
	_play.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))
	_characters.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
	_characters.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))
	_quit.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))


func _configure(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Progress and content health are shown on the hub, not hidden. If the content
## failed to load the player sees why before pressing Play.
func _refresh_status() -> void:
	ContentDB.ensure_loaded()
	var errors := ContentDB.errors()
	var levels := ContentDB.level_count()
	_status.text = "%d fase(s) disponiveis" % levels
	if errors.size() > 0:
		_status.text += "  --  %d problema(s) de conteudo" % errors.size()
		push_warning("MainMenu content problems:\n" + "\n".join(errors))


func _on_play_pressed() -> void:
	var first := ContentDB.first_level()
	if first.is_empty():
		_status.text = "Nenhuma fase carregada -- veja o log de conteudo"
		push_error("MainMenu: no level available to play")
		return
	if not GameManager.begin_run(first, GameManager.RunMode.CAMPAIGN):
		_status.text = "Falha ao iniciar a fase '%s'" % first
		return
	SceneDirector.to_level(first)


func _on_characters_pressed() -> void:
	SceneDirector.to_character()


func _on_quit_pressed() -> void:
	SaveManager.save_game()
	get_tree().quit()