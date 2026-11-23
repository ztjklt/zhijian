extends RefCounted
## Draw through the animated wrist, with the bristles ending on the exact ink sample.
static func draw(canvas: Node2D, grip: Vector2, nib: Vector2, ppu: float) -> void:
	var axis := nib.direction_to(grip)
	if axis.is_zero_approx(): axis = Vector2(-0.65,-0.76)
	var side := axis.orthogonal() * ppu
	var heel := nib + axis * ppu * 0.29
	var back := grip + axis * ppu * 0.35
	var collar := heel + axis * ppu * 0.10
	var width := maxf(2.4, ppu * 0.065)
	canvas.draw_line(collar, back, Color("332d32"), width + 2.4, true)
	canvas.draw_line(collar, back, Color("ab784c"), width, true)
	canvas.draw_line(heel, collar, Color("d9b166"), width + 3.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([nib, nib+axis*ppu*0.16+side*0.067, heel+side*0.047, heel-side*0.047, nib+axis*ppu*0.14-side*0.054]), Color("343643"))
	canvas.draw_line(nib+axis*ppu*0.06, heel-side*0.021, Color("85776d"), 1.0, true)
	canvas.draw_circle(grip, maxf(2.3,ppu*0.052), Color("343239"), true,-1,true)
