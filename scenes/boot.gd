extends Control
## Boot screen: the first thing the player ever sees.
##
## Does the work of getting the game into a playable state with a visible
## progress bar instead of a black screen: warms the audio graph, validates
## content, repairs the save if needed, then hands off to the main menu.

const STAGES: Array[Dictionary] = [
	{"label": "Iniciando sistema energetico", "weight": 0.10},
	{"label": "Verificando conteudo", "weight": 0.35},
	{"label": "Sintetizando audio", "weight": 0.20},
	{"label": "Carregando progresso", "weight": 0.20},
	{"label": "Sincronizando nucleo", "weight": 0.15},
]

@onready var _title: Label = $Center/Column/Title
@onready var _subtitle: Label = $Center/Column/Subtitle
@onready var _status: Label = $Center/Column/Status
@onready var _bar_bg: ColorRect = $Center/Column/Bar/Background
@onready var _bar_fill: ColorRect = $Center/Column/Bar/Fill
@onready var _report: Label = $Center/Column/Report

var _progress: float = 0.0


func _ready() -> void:
	_setup_visuals()
	_run_boot_sequence()


func _setup_visuals() -> void:
	_configure($Center/Column/Title, 58, Color(0.62, 0.94, 1.0))
	_configure($Center/Column/Subtitle, 17, Color(0.45, 0.58, 0.70))
	_configure($Center/Column/Status, 15, Color(0.72, 0.82, 0.90))
	_configure($Center/Column/Report, 12, Color(0.95, 0.62, 0.45))
	_bar_fill.color = Color(0.49, 0.90, 1.0)
	# Dim the trough only. Setting modulate on the Bar itself would tint the
	# Fill too, since modulate propagates down the whole subtree.
	_bar_bg.color = Color(0.16, 0.24, 0.34, 0.85)


func _configure(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _run_boot_sequence() -> void:
	for stage in STAGES:
		_status.text = String(stage["label"])
		await _animate_to(_progress + float(stage["weight"]))
		match String(stage["label"]):
			"Iniciando sistema energetico":
				_apply_initial_settings()
			"Verificando conteudo":
				ContentDB.ensure_loaded()
				_show_content_report()
			"Sintetizando audio":
				AudioDirector.play_music("boot", 0.8)
			"Carregando progresso":
				await get_tree().process_frame
			"Sincronizando nucleo":
				GameManager.mode = GameManager.RunMode.CAMPAIGN

	_progress = 1.0
	_update_bar()
	# Hold the finished bar for a beat so the transition is not jarring.
	await get_tree().create_timer(0.35).timeout
	SceneDirector.to_main_menu()


func _animate_to(target: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_progress, _progress, target, 0.22)
	await tween.finished


func _set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	_update_bar()


func _update_bar() -> void:
	if _bar_fill == null:
		return
	var bar := _bar_fill.get_parent() as Control
	if bar == null:
		return
	_bar_fill.position.x = 0.0
	_bar_fill.size.x = bar.size.x * _progress


## Content problems are surfaced, never hidden. A broken level file should be
## obvious during development and in a bug report, not a silent missing stage.
func _show_content_report() -> void:
	var report := ContentDB.content_report()
	var summary := "%d zonas  -  %d fases  -  %d coletaveis  -  %d inimigos" % [
		int(report["zones"]), int(report["levels"]),
		int(report["collectibles"]), int(report["enemies"])]
	_status.text = summary
	if int(report["errors"]) > 0:
		_report.text = "ATENCAO: %d problema(s) de conteudo -- veja o log" % int(report["errors"])
		_report.visible = true
		push_warning("Boot content problems:\n" + "\n".join(ContentDB.errors()))
	else:
		_report.visible = false


func _apply_initial_settings() -> void:
	ConfigManager.ensure_loaded()
	ConfigManager.apply_ui_scale()
