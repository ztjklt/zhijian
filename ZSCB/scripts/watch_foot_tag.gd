extends Node2D
## A short paper tag tied to the selected person's real foot when changing cameras.
const HOLD_SECONDS := 3.5
const FADE_SECONDS := 0.45
const WATCH_INK := Color("315d66")
const PLAYER_INK := Color("854f37")

const SHORT_NAMES := {"companion":"阿靛", "priest":"牧师", "war_god":"战神", "adventurer-lizhou":"砾舟"}

var panel
var other_role := ""
var other_foot := Vector2.INF
var subject := ""
var caption := ""
var portrait: Texture2D
var remaining := 0.0

func _ready() -> void:
	z_index = 4000
	process_priority = 100
	hide()
	set_process(false)

func point_to(id: String, returning_from := "") -> void:
	subject = id
	other_role = returning_from if id == "player" else "player"
	caption = "我在这里" if id == "player" else "在看 · " + str(SHORT_NAMES.get(id,id))
	portrait = null
	if id != "player" and panel.field_book != null:
		portrait = panel.field_book.character_art(id, true)
	remaining = HOLD_SECONDS + FADE_SECONDS
	set_process(true)
	_process(0)

func stop() -> void:
	hide()
	set_process(false)

func _feet(role: String) -> Vector2:
	if role == "player": return panel.game.player.position - Vector2(0, StickmanPlayer.BODY_RADIUS)
	var at:Vector2 = panel.person_point(role)
	return at if role == "priest" else at - Vector2(0, StickmanPlayer.BODY_RADIUS)

func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0 or not is_instance_valid(panel):
		stop()
		return
	var self_view := subject == "player"
	var following:bool = panel.visible and panel.strip.is_visible_in_tree() and panel.watching == subject
	if (self_view and panel.visible) or (not self_view and not following):
		stop()
		return
	var game=panel.game
	var point := _feet(subject)
	if not point.is_finite():
		hide()
		return
	position = game.world_to_screen(point)
	scale = Vector2.ONE * PaperGuiScale.factor(get_viewport_rect().size)
	other_foot = Vector2.INF
	if not other_role.is_empty():
		var other := _feet(other_role)
		var gap := (other-point).abs()
		if gap.x < .42 and gap.y < .55:
			other_foot = (game.world_to_screen(other)-position)/scale
	modulate.a = clampf(remaining / FADE_SECONDS,0.0,1.0)
	show()
	queue_redraw()

func _draw() -> void:
	var ink := PLAYER_INK if subject == "player" else WATCH_INK
	var font:Font = panel.get_theme_default_font()
	var area := get_viewport_rect().size / scale
	var at := position / scale
	var width := ceilf(font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x) + (34 if portrait else 14)
	var y := -34.0 if at.y + 37 > area.y else 10.0
	var side := -1 if subject == "player" else 1
	if not other_foot.is_finite():
		if at.x-15-width < 6: side = 1
		elif at.x+15+width > area.x-6: side = -1
		_draw_tag(Vector2.ZERO, side, y, width, caption, ink, portrait, true, 0.0)
		draw_circle(Vector2.ZERO,4.6,PaperTheme.PAPER,true,-1,true)
		draw_circle(Vector2.ZERO,2.8,ink,true,-1,true)
		return

	var player := Vector2.ZERO if subject=="player" else other_foot
	var role := other_foot if subject=="player" else Vector2.ZERO
	# Use each person's actual side. On a shared footpoint the ring and dot remain distinct.
	var player_side := -1 if player.x < role.x-1 else 1
	side = player_side if subject=="player" else -player_side
	var short_name:String = SHORT_NAMES.get(other_role,"我")
	var short_width := ceilf(font.get_string_size(short_name,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x) + 14
	y = maxf(0,other_foot.y)+10
	if at.y+y+27 > area.y: y = minf(0,other_foot.y)-34
	var left := -15-width if side < 0 else other_foot.x-15-short_width
	var right := 15+width if side > 0 else other_foot.x+15+short_width
	var shift := maxf(0,6-at.x-left) + minf(0,area.x-6-at.x-right)
	_draw_tag(Vector2.ZERO,side,y,width,caption,ink,portrait,true,shift)
	var other_ink := PLAYER_INK if other_role=="player" else WATCH_INK
	_draw_tag(other_foot,-side,y,short_width,short_name,other_ink,null,false,shift)
	draw_circle(player,4.4,PaperTheme.PAPER,true,-1,true)
	draw_arc(player,3.7,0,TAU,24,PLAYER_INK,1.8,true)
	draw_circle(role,3.1,PaperTheme.PAPER,true,-1,true)
	draw_circle(role,2.1,WATCH_INK,true,-1,true)

func _draw_tag(foot:Vector2,side:int,y:float,width:float,words:String,ink:Color,art:Texture2D,selected:bool,shift:float) -> void:
	var near_edge := foot.x+side*15+shift
	var left := near_edge if side==1 else near_edge-width
	var rect := Rect2(left,y,width,25)
	var joint := Vector2(near_edge-side*5,y+12)
	draw_line(foot,joint,PaperTheme.PAPER,4,true)
	draw_line(foot,joint,ink,2,true)
	draw_line(joint,Vector2(near_edge,y+12),ink,2,true)
	draw_rect(rect,PaperTheme.PAPER)
	if selected: draw_rect(rect,ink,false,1.4)
	else: draw_line(Vector2(left+3,y+24),Vector2(left+width-3,y+24),ink,1,true)
	if art: draw_texture_rect(art,Rect2(left+5,y+2,22,21),false)
	draw_string(panel.get_theme_default_font(),Vector2(left+(28 if art else 7),y+18),words,HORIZONTAL_ALIGNMENT_LEFT,-1,15,ink)
