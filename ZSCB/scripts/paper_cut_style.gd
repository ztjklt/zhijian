class_name PaperCutStyle
extends StyleBox
## Shallow cut-paper edges for ordinary buttons, inputs and modal panels.
var bg_color := Color("faf5e7")
var border_color := Color("c9c9ae")
var depth := 2.5
func _draw(item: RID, rect: Rect2) -> void:
	var cut:=minf(7.0,rect.size.y*.14)
	var x:=rect.position.x;var y:=rect.position.y
	var w:=rect.size.x;var h:=rect.size.y
	var points:=PackedVector2Array([Vector2(x+cut,y+1),Vector2(x+w*.56,y),Vector2(x+w-cut,y+1),Vector2(x+w,y+cut),Vector2(x+w-1,y+h-cut),Vector2(x+w-cut,y+h),Vector2(x+w*.37,y+h-1),Vector2(x+cut,y+h),Vector2(x,y+h-cut),Vector2(x+1,y+cut)])
	var shadow:PackedVector2Array=points.duplicate()
	for i in shadow.size():shadow[i]+=Vector2(depth*.45,depth)
	RenderingServer.canvas_item_add_polygon(item,shadow,PackedColorArray([Color(.21,.25,.17,.13)]))
	RenderingServer.canvas_item_add_polygon(item,points,PackedColorArray([bg_color]))
	points.append(points[0])
	RenderingServer.canvas_item_add_polyline(item,points,PackedColorArray([border_color]),1.0,true)
	RenderingServer.canvas_item_add_line(item,Vector2(x+cut,y+1),Vector2(x+w-cut,y+1),bg_color.lightened(.35),1.0,true)
