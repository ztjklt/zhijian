extends SceneTree
func _init()->void:
	var paths:Array=[{"points":[Vector2(-4,-3),Vector2(4,-3),Vector2(4,3),Vector2(-4,3),Vector2(-4,-3)],"collision":true}]
	var cuts:Array=[]
	for side in 4:
		for i in 4:
			var p:=Vector2(-2.4+i*1.6,-3) if side==0 else Vector2(4,-1.8+i*1.2) if side==1 else Vector2(-2.4+i*1.6,3) if side==2 else Vector2(-4,-1.8+i*1.2)
			cuts.append({"x":p.x,"y":p.y,"r":.14})
	var obj:Dictionary={"x":0.0,"y":0.0,"dynamic":true,"paths":paths,"damage_cuts":cuts}
	var start:=Time.get_ticks_usec()
	var cooked:=PaperObjectDamage.prepare(obj)
	print("DAMAGE BUDGET: ",cooked.shapes.size()," fixtures, ",Time.get_ticks_usec()-start," us")
	var ok:bool=cooked.shapes.size()<=160
	for cut in cuts:
		if cooked.fills.any(func(p):return Geometry2D.is_point_in_polygon(Vector2(cut.x,cut.y),p)):ok=false
	if not cooked.fills.any(func(p):return Geometry2D.is_point_in_polygon(Vector2.ZERO,p)):ok=false
	if not ok:push_error("DAMAGE BUDGET: bounded fixtures preserve every actual cut and intact center")
	quit(0 if ok else 1)
