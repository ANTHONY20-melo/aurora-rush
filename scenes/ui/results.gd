extends Control
## Results screen: shows the rank, stats, and a full breakdown.
##
## Every number is explainable. The player sees exactly why they got their rank.

@onready var _title: Label = $Center/Column/Title
@onready var _rank_label: Label = $Center/Column/RankContainer/RankLabel
@onready var _rank_value: Label = $Center/Column/RankContainer/RankValue
@onready var _time_value: Label = $Center/Column/Stats/TimeRow/TimeValue
@onready var _score_value: Label = $Center/Column/Stats/ScoreRow/ScoreValue
@onready var _collectibles_value: Label = $Center/Column/Stats/CollectiblesRow/CollectiblesValue
@onready var _secrets_value: Label = $Center/Column/Stats/SecretsRow/SecretsValue
@onready var _deaths_value: Label = $Center/Column/Stats/DeathsRow/DeathsValue

@onready var _bd_time: Label = $Center/Column/Breakdown/BreakdownTime
@onready var _bd_deaths: Label = $Center/Column/Breakdown/BreakdownDeaths
@onready var _bd_collectibles: Label = $Center/Column/Breakdown/BreakdownCollectibles
@onready var _bd_secrets: Label = $Center/Column/Breakdown/BreakdownSecrets
@onready var _bd_score: Label = $Center/Column/Breakdown/BreakdownScore
@onready var _bd_effective: Label = $Center/Column/Breakdown/BreakdownEffective

@onready var _retry: Button = $Center/Column/Buttons/Retry
@onready var _map: Button = $Center/Column/Buttons/Map
@onready var _next: Button = $Center/Column/Buttons/Next

var _result: GameTypes.LevelResult = null
var _level: LevelData = null

func _ready() -> void:
	_setup_fonts()
	_retry.pressed.connect(_on_retry)
	_map.pressed.connect(_on_map)
	_next.pressed.connect(_on_next)
	
	for btn in [_retry, _map, _next]:
		btn.focus_entered.connect(func() -> void: AudioDirector.play_sfx("ui_move", -6.0))
		btn.pressed.connect(func() -> void: AudioDirector.play_sfx("ui_confirm", -4.0))

func _setup_fonts() -> void:
	var labels: Array[Label] = [
		_title, _rank_label, _rank_value,
		_time_value, _score_value, _collectibles_value, _secrets_value, _deaths_value,
		_bd_time, _bd_deaths, _bd_collectibles, _bd_secrets, _bd_score, _bd_effective
	]
	for label in labels:
		label.add_theme_font_size_override("font_size", 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color(0.62, 0.94, 1.0))
	_rank_value.add_theme_font_size_override("font_size", 48)
	
	_configure_rank_colors()

func _configure_rank_colors() -> void:
	var rank_colors: Dictionary = {
		GameTypes.Rank.S: Color(1.0, 0.85, 0.15),
		GameTypes.Rank.A: Color(0.3, 0.9, 0.4),
		GameTypes.Rank.B: Color(0.4, 0.7, 1.0),
		GameTypes.Rank.C: Color(0.8, 0.6, 0.9),
		GameTypes.Rank.D: Color(0.7, 0.5, 0.5),
	}
	_rank_value.add_theme_color_override("font_color", rank_colors.get(GameTypes.Rank.C, Color.WHITE))

func show_result(result: GameTypes.LevelResult) -> void:
	_result = result
	_level = ContentDB.get_level(result.level_id)
	visible = true
	AudioDirector.play_music("victory", 1.0)
	_populate()

func _populate() -> void:
	var targets: Dictionary = _level.par_ranks if _level else Ranking.DEFAULT_TARGETS
	var rank_int: int = Ranking.compute_rank(_result, targets)
	var rank_str: String = Ranking.rank_letter(rank_int)
	
	_rank_value.text = rank_str
	_rank_value.add_theme_color_override("font_color", _rank_color(rank_int))
	
	_time_value.text = Fmt.time(_result.attempt_time)
	_score_value.text = str(_result.score)
	_collectibles_value.text = "%d/%d" % [_result.collectibles_collected, _result.collectibles_total]
	_secrets_value.text = "%d/%d" % [_result.secrets_found, _result.secrets_total]
	_deaths_value.text = str(_result.deaths)
	
	var explain := Ranking.explain(_result, targets)
	_bd_time.text = "Tempo base: %s" % Fmt.time(explain["raw_time"])
	_bd_deaths.text = "Penalidade mortes: +%.2fs" % explain["death_penalty"]
	
	var ladder := Ranking.normalized_targets(targets)
	var collect_bonus := (_result.completion_ratio() * 10.0 * Ranking.COLLECTIBLE_BONUS_PER_DECILE * ladder["s"])
	var secret_bonus := (_result.secret_ratio() * 3.0 * Ranking.SECRET_BONUS * ladder["s"])
	var score_bonus := minf(Ranking.SCORE_BONUS_CAP, float(_result.score) / 100000.0 * 10.0 * Ranking.SCORE_BONUS_PER_10K) * ladder["s"]
	
	_bd_collectibles.text = "Bonus coletaveis: -%.2fs" % collect_bonus
	_bd_secrets.text = "Bonus segredos: -%.2fs" % secret_bonus
	_bd_score.text = "Bonus pontuacao: -%.2fs" % score_bonus
	_bd_effective.text = "Tempo efetivo: %s" % Fmt.time(explain["effective_time"])
	
	_next.disabled = _level == null or ContentDB.next_level_after(_result.level_id).is_empty()
	_next.text = "PROXIMA FASE" if not _next.disabled else "CAMPEAO!"

func _rank_color(rank: int) -> Color:
	match rank:
		GameTypes.Rank.S: return Color(1.0, 0.85, 0.15)
		GameTypes.Rank.A: return Color(0.3, 0.9, 0.4)
		GameTypes.Rank.B: return Color(0.4, 0.7, 1.0)
		GameTypes.Rank.C: return Color(0.8, 0.6, 0.9)
		_: return Color(0.7, 0.5, 0.5)

func _on_retry() -> void:
	AudioDirector.play_sfx("ui_confirm", -4.0)
	if _result != null:
		GameManager.begin_run(_result.level_id, GameManager.mode)
		SceneDirector.to_level(_result.level_id)

func _on_map() -> void:
	AudioDirector.play_sfx("ui_confirm", -4.0)
	SceneDirector.to_world_map()

func _on_next() -> void:
	AudioDirector.play_sfx("ui_confirm", -4.0)
	if _result != null:
		var next_id := ContentDB.next_level_after(_result.level_id)
		if not next_id.is_empty():
			GameManager.begin_run(next_id, GameManager.mode)
			SceneDirector.to_level(next_id)
		else:
			SceneDirector.to_world_map()