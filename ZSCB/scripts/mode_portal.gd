class_name PaperModePortal
extends PaperSealButton
var artwork: Texture2D
var heading := ""
var detail := ""
var action_label := ""
var number := "01"

func _ready() -> void:
	silhouette = "portal"
	super._ready()

func _draw() -> void:
	super._draw()
	var narrow := size.x < 230
	var short := size.y < 260
	var font := get_theme_font("font")
	var motion := Vector2(0,-3*hover_mix+press_mix*2)
	if artwork != null:
		var box := Rect2(Vector2(size.x*.025,size.y*.075)+motion,Vector2(size.x*.95,size.y*.46))
		var dimensions := artwork.get_size()
		dimensions *= minf(box.size.x/dimensions.x,box.size.y/dimensions.y)
		draw_texture_rect(artwork,Rect2(box.get_center()-dimensions*.5,dimensions),false,Color(1,1,1,.95))
	if not short: _centered(number + "  /  " + ("SANDBOX" if number == "01" else "DUEL"),size.y*.58,10 if narrow else 12,Color(accent,.72))
	_centered(heading,size.y*(.65 if short else .69),22 if narrow or short else 32,Color("283d35"))
	_centered(detail,size.y*.78,12 if narrow or short else 15,Color("65746a"))
	_centered(action_label + "  ↗",size.y*.91,13 if narrow or short else 17,accent)

func _centered(value: String, baseline: float, font_size: int, ink: Color) -> void:
	var font := get_theme_font("font")
	var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,Vector2((size.x-width)*.5,baseline+press_mix*2-hover_mix*2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ink)
