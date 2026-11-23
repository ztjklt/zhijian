class_name PaperUIArt
extends RefCounted
## Menu illustration only. Never apply this art to the game world or actors.
const PAPER:=Color("f7f0df")
const Hills:=preload("res://assets/ui/paper-art/hills.png")
static func background(canvas:CanvasItem,size:Vector2,quiet:bool=false)->void:
	canvas.draw_rect(Rect2(Vector2.ZERO,size),PAPER)
	var height:=maxf(size.y,size.x/3.0)
	canvas.draw_texture_rect(Hills,Rect2(0,size.y-height,size.x,height),false,Color(1,1,1,.35 if quiet else .72))
