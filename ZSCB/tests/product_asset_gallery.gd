extends SceneTree
## Real renderer QA at 60 pixels/metre; never loads or saves a player world.
const CATALOG := preload("res://scripts/medieval_catalog.gd")
const ENTITY := preload("res://scripts/medieval_entity.gd")
const OUT := "/Users/jitian/Documents/ChatGPT/纸上城堡/ZSCB/assets/medieval/expansion/review/"

class Gallery extends Node2D:
	var entries: Array = []
	var edges := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,1800,1200),Color("faf7eb"))
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(30,35),"MEDIEVAL EXPANSION · 60 px / metre · transparent source PNGs",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("37342d"))
		for i in entries.size():
			var item: Dictionary = entries[i]
			var column := i % 3
			var row := i / 3
			var origin := Vector2(column*600+300,row*540+565)
			var size: Vector2 = item.size * 60.0
			draw_line(origin+Vector2(-270,0),origin+Vector2(270,0),Color("c8c1b0"),1)
			draw_string(font,origin+Vector2(-265,35),"%s · %.2f × %.2f m" % [item.id,item.size.x,item.size.y],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("37342d"))
			var rect := Rect2(origin+Vector2(-size.x/2,-size.y),size)
			draw_texture_rect_region(item.texture,rect,item.source)
			if edges:
				for edge in item.walk_edges:
					var a := origin+Vector2(float(edge[0])*size.x,-float(edge[1])*size.y)
					var b := origin+Vector2(float(edge[2])*size.x,-float(edge[3])*size.y)
					draw_line(a,b,Color(0.1,0.5,0.65,0.85),2,true)

func _init() -> void: call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1800,1200)
	var definitions := CATALOG.entries()
	assert(definitions.size()==22,"Expected all 22 independent generated assets")
	var provenance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/expansion/generation_manifest.json"))
	assert(provenance.records.size()==22,"Every sprite requires original path and full prompt")
	var items: Array = []
	for id in definitions:
		var definition: Dictionary = definitions[id]
		assert(ResourceLoader.exists(definition.path),"Missing PNG: "+id)
		assert(FileAccess.file_exists("res://assets/medieval/expansion/source/"+id+".png"),"Missing preserved original: "+id)
		var entity := ENTITY.new()
		entity.setup(id,Vector2.ZERO,"gallery-"+id,0)
		assert(entity.texture!=null and entity.source_rect.has_area(),"Missing actual rendered alpha source: "+id)
		var image := entity.texture.get_image()
		assert(image.get_pixel(0,0).a<0.05,"Opaque rectangular backdrop: "+id)
		for edge in definition.walk_edges:
			assert(edge.size()==4 and edge[0]>=-0.5 and edge[2]<=0.5 and edge[1]>=0 and edge[3]<=1,"Invalid normalized edge: "+id)
		items.append({"id":id,"size":entity.size,"texture":entity.texture,"source":entity.source_rect,"walk_edges":definition.walk_edges})
		entity.free()
	var gallery := Gallery.new()
	root.add_child(gallery)
	DirAccess.make_dir_recursive_absolute(OUT)
	for page in 4:
		gallery.entries = items.slice(page*6,mini(items.size(),page*6+6))
		for overlay in [false,true]:
			gallery.edges = overlay
			gallery.queue_redraw()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var filename := "godot-gallery-%d%s.png" % [page+1,"-walk-edges" if overlay else ""]
			assert(root.get_texture().get_image().save_png(OUT+filename)==OK,"Screenshot save failed")
	print("PASS: 22 independent PNGs, 22 preserved originals, provenance, normalized edges, 8 actual-renderer gameplay-scale gallery screenshots")
	quit()
