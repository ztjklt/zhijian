extends RefCounted
## Compact paper labels anchored to a character's head in the world view.

static func vitals_area(toolbar: Control) -> Rect2:
	var header: Control = toolbar.header
	return header.get_global_rect().grow(5) if header.is_visible_in_tree() else Rect2()

static func bounds(anchor: Vector2, size: Vector2, view: Rect2, avoid: Rect2) -> Rect2:
	var point := anchor-Vector2(size.x*.5,size.y+7)
	point.x = clampf(point.x,view.position.x+6,view.end.x-size.x-6)
	if avoid.has_area() and avoid.intersects(Rect2(point,size)):
		if avoid.end.x+size.x+6 <= view.end.x:
			point.x = avoid.end.x
		else:
			point.y = avoid.end.y
	return Rect2(point,size)

static func draw(canvas: Node2D, font: Font, anchor: Vector2, view: Rect2, words: String, ink: Color, px: int, avoid: Rect2) -> Rect2:
	if not view.grow(12).has_point(anchor): return Rect2()
	var size := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, px) + Vector2(12,5)
	var label := bounds(anchor,size,view,avoid)
	if not (label.position.x+2 <= anchor.x and anchor.x <= label.end.x-2):
		var foot := Vector2(clampf(anchor.x,label.position.x+3,label.end.x-3),label.end.y-1)
		canvas.draw_line(foot,anchor,Color(ink,.68),1,true)
	canvas.draw_rect(label,Color("fbf6e9f5"))
	canvas.draw_line(label.position,Vector2(label.position.x,label.end.y),ink,2,true)
	canvas.draw_string(font,label.position+Vector2(6,2+font.get_ascent(px)),words,HORIZONTAL_ALIGNMENT_LEFT,-1,px,ink)
	return label
