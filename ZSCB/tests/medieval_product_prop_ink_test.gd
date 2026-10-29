extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func run()->void:
	var world:=MedievalWorld.new();root.add_child(world);await physics_frame
	for id in ["barrel-100","crate-100","haystack-100","fence-100","fence-101","fence-104","cart_goods-103","bench-100"]:
		var entity=world.entity_by_id(id)
		if entity.texture==null:
			failures.append(id);checks+=1;print("FAIL: missing source ink ",id);continue
		var image:Image=entity.texture.get_image()
		var source:Rect2=entity.source_rect
		var gap:=INF
		for x in range(int(source.position.x),int(source.end.x),7):
			for y in range(int(source.end.y)-1,int(source.position.y)-1,-1):
				if image.get_pixel(x,y).a<0.12:continue
				var local:Vector2=Vector2((float(x)-source.position.x)/source.size.x-0.5,1.0-(float(y)-source.position.y)/source.size.y)*entity.size
				var point:Vector2=entity.to_global(local)
				gap=minf(gap,point.y-world.travel_height(point.x))
				break
		checks+=1
		if gap<-.025 or gap>.025:
			failures.append(id);print("FAIL: actual ink foot ",id," gap ",gap)
	world.queue_free();await process_frame
	print("MEDIEVAL PRODUCT PROP INK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
