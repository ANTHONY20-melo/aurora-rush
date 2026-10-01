class_name MascotSextaFeira
extends Control
## Asset 002: the SEXTA-FEIRA mascot and UI identity.
##
## Matte black with neon green accents, a black cap reading SEXTA-FEIRA, a black
## gamer hoodie, and a dark visor with green digital eyes. Drawn procedurally so
## the whole identity ships without binary assets. Four expressions and the
## personality bar are part of the asset brief and are all reachable from here.

## Neon green on matte black, per the brief's "cores_principais".
const NEON := Color(0.24, 1.0, 0.42)
const NEON_DIM := Color(0.14, 0.6, 0.26)
const MATTE := Color(0.06, 0.06, 0.07)
const MATTE_LIGHT := Color(0.12, 0.12, 0.14)
const VISOR := Color(0.04, 0.05, 0.06)

const SLOGAN := "SEXTA-FEIRA NAO E SO UM NOME. E O SEU ASSISTENTE."
const PROMPT := "PS C:\\SEXTA-FEIRA>"

## The four expressions from the asset's "expressoes" grid. Named Mood, not
## Expression: GDScript has a native Expression class and an enum member cannot
## shadow it.
enum Mood { FELIZ, SURPRESO, CONFIDENTE, PENSATIVO }

## The five personality traits from the asset's "personalidade" grid.
const PERSONALITY := [
	"Tecnica", "Inteligente", "Agil", "Confiavel", "Sempre Online (Local)",
]

@export var mood: Mood = Mood.FELIZ:
	set(value):
		mood = value
		_face_timer = 0.0
		queue_redraw()

var _face_timer: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(96, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	# Cycles the expressions so all four from the grid are actually visible.
	_face_timer += delta
	if _face_timer >= 2.5:
		_face_timer = 0.0
		mood = ((mood + 1) % Mood.size()) as Mood
	queue_redraw()

func _draw() -> void:
	# Control.size is shadowed by the local below, so the property is read first.
	var box := size
	var canvas := Vector2(minf(box.x, box.y), minf(box.x, box.y))
	_draw_hoodie(canvas * 0.5, canvas)
	_draw_cap(canvas * 0.5, canvas)
	_draw_visor(canvas * 0.5, canvas)
	_draw_personality(canvas)

func _draw_hoodie(center: Vector2, size: Vector2) -> void:
	var w := size.x * 0.42
	var h := size.y * 0.3
	# Shoulders.
	draw_colored_polygon(PackedVector2Array([
		center.x - w, center.y + h,
		center.x + w, center.y + h,
		center.x + w * 0.72, center.y + h * 0.1,
		center.x - w * 0.72, center.y + h * 0.1,
	]), MATTE)
	# Hoodie collar, a lighter ring at the neck.
	draw_rect(Rect2(center.x - w * 0.5, center.y + h * 0.02, w, h * 0.12), MATTE_LIGHT)
	# Gamer hoodie drawstrings.
	draw_line(Vector2(center.x - w * 0.3, center.y + h * 0.14),
		Vector2(center.x - w * 0.3, center.y + h * 0.6), NEON, 2.0)
	draw_line(Vector2(center.x + w * 0.3, center.y + h * 0.14),
		Vector2(center.x + w * 0.3, center.y + h * 0.6), NEON, 2.0)

func _draw_cap(center: Vector2, size: Vector2) -> void:
	var w := size.x * 0.3
	var h := size.y * 0.16
	# Crown.
	draw_colored_polygon(PackedVector2Array([
		center.x - w, center.y - h * 0.2,
		center.x + w, center.y - h * 0.2,
		center.x + w * 0.8, center.y - h * 1.5,
		center.x - w * 0.8, center.y - h * 1.5,
	]), MATTE)
	# Brim.
	draw_colored_polygon(PackedVector2Array([
		center.x - w, center.y - h * 0.2,
		center.x + w * 1.7, center.y - h * 0.05,
		center.x + w * 1.7, center.y + h * 0.12,
		center.x - w, center.y - h * 0.02,
	]), MATTE_LIGHT)
	# The cap reads SEXTA-FEIRA, so the word has to fit the crown.
	draw_string(ThemeDB.fallback_font, Vector2(center.x - w * 0.78, center.y - h * 0.75),
		"SEXTA-FEIRA", HORIZONTAL_ALIGNMENT_LEFT, w * 1.56, size.y * 0.1, NEON)

func _draw_visor(center: Vector2, size: Vector2) -> void:
	var w := size.x * 0.27
	var h := size.y * 0.15
	var rect := Rect2(center.x - w, center.y - h * 0.05, w * 2.0, h)
	draw_rect(rect, VISOR)
	draw_rect(rect, NEON_DIM, false, 1.5)
	_draw_eyes(center + Vector2(-w * 0.45, h * 0.35), w, h)

func _draw_eyes(at: Vector2, w: float, h: float) -> void:
	var eye_w := w * 0.5
	var eye_h := h * 0.4
	var left := at - Vector2(eye_w * 1.25, 0.0)
	var right := at + Vector2(eye_w * 0.75, 0.0)
	match mood:
		Mood.FELIZ:
			# Upturned arcs.
			draw_arc(left, eye_h, PI, TAU, 6, NEON, 2.0)
			draw_arc(right, eye_h, PI, TAU, 6, NEON, 2.0)
		Mood.SURPRESO:
			draw_rect(Rect2(left - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 1.6)), NEON)
			draw_rect(Rect2(right - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 1.6)), NEON)
		Mood.CONFIDENTE:
			# Narrowed slits.
			draw_rect(Rect2(left - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 0.55)), NEON)
			draw_rect(Rect2(right - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 0.55)), NEON)
		Mood.PENSATIVO:
			# Looking up, with one eye larger.
			draw_rect(Rect2(left - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 0.8)), NEON)
			draw_rect(Rect2(right - Vector2(eye_w, 0), Vector2(eye_w * 2.0, eye_h * 1.3)), NEON)

func _draw_personality(size: Vector2) -> void:
	var y := size.y * 0.78
	var x := size.x * 0.04
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(size.y * 0.055, 7.0, 12.0))
	draw_string(font, Vector2(x, y), SLOGAN, HORIZONTAL_ALIGNMENT_LEFT,
		size.x * 0.92, font_size, NEON)
	for i in PERSONALITY.size():
		var row_y := y + float(i + 1) * (font_size + 3.0)
		draw_string(font, Vector2(x, row_y), PERSONALITY[i],
			HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.92, font_size, NEON_DIM)
