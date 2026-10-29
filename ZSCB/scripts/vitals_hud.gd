extends Control
## Upper-left passive meters, laid out inside the toolbar's brand slot.
var toolbar = null
var previous_health := 100.0
var trailing_health := 100.0
var hurt_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(170, 48)

func _process(delta: float) -> void:
	if toolbar == null or toolbar.game == null or toolbar.game.combat == null: return
	var health: float = toolbar.game.combat.health
	if health < previous_health: hurt_time = 0.5
	if health > previous_health: trailing_health = health
	previous_health = health
	hurt_time = maxf(0, hurt_time - delta)
	if hurt_time <= 0: trailing_health = move_toward(trailing_health, health, delta * 90)
	queue_redraw()

func _draw() -> void:
	if toolbar == null or toolbar.game == null or toolbar.game.combat == null: return
	var game = toolbar.game
	var reserve = game.ink
	var width := minf(204, maxf(160, size.x))
	var font := get_theme_font("font")
	var red := Color("a92337")
	var black := Color("272932")
	var background := Color("ddd7c9")
	draw_string(font, Vector2(0, 14), "生命  %d / 100" % ceili(game.combat.health), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, red)
	draw_rect(Rect2(0, 20, width, 4), background)
	draw_rect(Rect2(0, 20, width * clampf(trailing_health / 100.0, 0, 1), 4), Color("db9b94"))
	draw_rect(Rect2(0, 20, width * clampf(game.combat.health / 100.0, 0, 1), 4), red)
	draw_string(font, Vector2(0, 39), "墨水  %d / 300" % floori(reserve.amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, black)
	draw_rect(Rect2(0, 45, width, 4), background)
	draw_rect(Rect2(0, 45, width * clampf(reserve.amount / 300.0, 0, 1), 4), black)
	var hint := "−%d" % roundi(reserve.last_cost) if reserve.recent > 0 else "%.1fs" % reserve.wait if reserve.wait > 0 else "恢复中" if reserve.amount < 300 else ""
	var hint_width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(width - hint_width, 39), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, red if reserve.recent > 0 else Color("6c7979"))
