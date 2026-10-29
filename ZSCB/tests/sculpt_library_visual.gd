extends SceneTree

class Gallery extends Node2D:
	var items: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,1536,1080),Color("faf7eb"))
		draw_string(ThemeDB.fallback_font,Vector2(34,47),"纸上城堡 · 44 种自动塑形",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("303941"))
		draw_string(ThemeDB.fallback_font,Vector2(34,78),"5 开始 → 可画多笔 → 5 确认；图示为实际识别后生成的轮廓",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("777d77"))
		for i in items.size():
			var item: Dictionary = items[i]
			var cell := Vector2(24+(i%8)*188,102+floori(i/8.0)*158)
			draw_style_box(PaperTheme.panel(Color("fffaf0"),12),Rect2(cell,Vector2(178,146)))
			var b := ShapeMatcher.bounds(item.object.paths)
			var center := Vector2((b.min_x+b.max_x)*0.5,(b.min_y+b.max_y)*0.5)
			var scale := minf(120/maxf(b.width,0.1),82/maxf(b.height,0.1))
			var anchor := cell+Vector2(89,54)
			for fill in PaperShapePhysics.prepare(item.object.paths).fills:
				var polygon := PackedVector2Array()
				for p in fill: polygon.append(anchor+(p-center)*Vector2(scale,-scale))
				draw_colored_polygon(polygon,Color("e1e9dd"))
			for path in item.object.paths:
				var points := PackedVector2Array()
				for p in path.points: points.append(anchor+(p-center)*Vector2(scale,-scale))
				draw_polyline(points,Color("376f65"),2.4,true)
			draw_string(ThemeDB.fallback_font,cell+Vector2(10,126),"%02d  %s"%[i+1,item.label],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("303941"))

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1536,1080)
	root.title = "纸上城堡 · 44 种形状图鉴"
	var gallery := Gallery.new()
	var basic := [
		{"kind":"circle","points":AutoSculpt._oval(Vector2.ZERO,Vector2.ONE,0)},
		{"kind":"ellipse","points":AutoSculpt._oval(Vector2.ZERO,Vector2(1,0.6),0)},
		{"kind":"rectangle","points":[Vector2(-1,-0.5),Vector2(1,-0.5),Vector2(1,0.5),Vector2(-1,0.5),Vector2(-1,-0.5)]},
		{"kind":"triangle","points":[Vector2(-1,-1),Vector2(1,-1),Vector2(0,1),Vector2(-1,-1)]},
		{"kind":"line","points":[Vector2(-1,0),Vector2(1,0)]}]
	for entry in basic+SculptLibrary.entries():
		var result := AutoSculpt.fit([{"points":entry.points}])
		if result.object.is_empty():
			push_error("Unable to render "+entry.kind)
			continue
		gallery.items.append({"label":AutoSculpt.label(result.object.kind),"object":result.object})
	root.add_child(gallery)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/paper-sculpt-library-44.png")
	print("SCULPT GALLERY: %d shapes rendered"%gallery.items.size())
	quit()
