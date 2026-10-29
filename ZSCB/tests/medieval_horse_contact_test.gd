extends SceneTree
var failures: Array[String] = []
var count := 0
class Fixture extends Node2D:
	var PIXELS_PER_UNIT := 78.0
	var origin := Vector2.ZERO
	var center := Vector2.ZERO
	func world_to_screen(p: Vector2) -> Vector2: return origin+Vector2((p.x-center.x)*PIXELS_PER_UNIT,-(p.y-center.y)*PIXELS_PER_UNIT)
class HorseCanvas extends Node2D:
	var horse
	var game
	func _draw() -> void:
		for row in 2:
			horse.facing = -1 if row==0 else 1
			for frame in 4:
				horse.age=(frame+0.1)/(8.0 if horse.kind=="dragon" else 6.0)
				game.origin=Vector2(155+frame*320,300+row*330)
				game.center=horse.position
				var a: Vector2=horse.to_global(Vector2(-1.5,.05))
				var b: Vector2=horse.to_global(Vector2(1.5,.05))
				if horse.kind=="horse": draw_line(game.world_to_screen(a),game.world_to_screen(b),Color(0.1,.4,.7),2,true)
				else: draw_line(game.origin+Vector2(0,-250),game.origin,Color(.3,.4,.5),1,true)
				horse.draw_entity(self,game)
				draw_circle(game.origin,3,Color(.8,.15,.1))
class Holder extends Node2D:
	var game
	var terrain
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	count += 1
	if not ok: failures.append(label); push_error("HORSE CONTACT: "+label)
func run() -> void:
	var fixture := Fixture.new()
	root.add_child(fixture)
	var world := Holder.new()
	world.game=fixture
	world.terrain=MedievalTerrain.new()
	fixture.add_child(world)
	var horse := MedievalEntity.new()
	horse.setup("horse",Vector2(60,0),"horse-contact",0)
	var pose: Dictionary=world.terrain.support_pose(60,horse.size.x*.335,.05)
	horse.position.y=pose.position_y
	horse.rotation=pose.rotation
	horse.freeze=true
	world.add_child(horse)
	check(horse.has_method("raster_actor_frame_draw"),"horse exposes pivot-local positive frame geometry")
	if horse.has_method("raster_actor_frame_draw"):
		var source_image: Image=horse.texture.get_image()
		var prior_size := Vector2.ZERO
		for face in [-1,1]:
			horse.facing=face
			for frame in 4:
				var draw: Dictionary=horse.raster_actor_frame_draw(frame)
				var rect: Rect2=draw.rect
				var source: Rect2=draw.source
				check(rect.size.x>0 and rect.size.y>0,"both facings use positive rectangles, never displaced negative width")
				check(absf(rect.get_center().x)<0.0001 and draw.mirror==-face,"horse mirrors around actual physical pivot")
				check(draw.grounded,"bridge horse render recognizes actual physical support")
				var bottom := -1
				for y in range(int(source.end.y)-1,int(source.position.y)-1,-1):
					for x in range(int(source.position.x),int(source.end.x)):
						if source_image.get_pixel(x,y).a>.05: bottom=y+1; break
					if bottom>=0: break
				var hoof_y := rect.position.y+float(bottom-source.position.y)/source.size.y*rect.size.y
				check(absf(hoof_y+.05)<.002,"actual lowest hoof alpha meets same rotated bridge baseline in every walking frame")
				if prior_size!=Vector2.ZERO: check(rect.size.is_equal_approx(prior_size),"frame art retains common scale without body pumping")
				prior_size=rect.size
		for excluded in ["hurt","airborne","unsupported","dead"]:
			horse.hurt_timer=0
			horse.alive=true
			horse.linear_velocity=Vector2.ZERO
			horse.position.y=pose.position_y
			if excluded=="hurt": horse.hurt_timer=.5
			if excluded=="airborne": horse.linear_velocity.y=2
			if excluded=="unsupported": horse.position.y+=1
			if excluded=="dead": horse.alive=false
			check(not horse.raster_actor_frame_draw(0).grounded,excluded+" horse keeps unsnapped art")
	var dragon := MedievalEntity.new()
	dragon.setup("dragon",Vector2(60,8),"dragon-contact",0)
	dragon.freeze=true
	world.add_child(dragon)
	check(dragon.has_method("raster_actor_frame_draw"),"dragon exposes positive pivot-local frame geometry")
	if dragon.has_method("raster_actor_frame_draw"):
		for face in [-1,1]:
			dragon.facing=face
			for frame in 8:
				var draw: Dictionary=dragon.raster_actor_frame_draw(frame)
				var rect: Rect2=draw.rect
				check(rect.size.x>0 and rect.size.y>0 and absf(rect.get_center().x)<.0001,"every flight frame stays centered with positive dimensions")
				check(draw.mirror==face and not draw.grounded,"dragon facing changes only pivot mirror and never ground-snaps")
	if DisplayServer.get_name() != "headless":
		horse.alive=true
		horse.hurt_timer=0
		horse.linear_velocity=Vector2.ZERO
		horse.position.y=pose.position_y
		fixture.PIXELS_PER_UNIT=110
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size=Vector2i.ZERO
		DisplayServer.window_set_size(Vector2i(1280,720))
		RenderingServer.set_default_clear_color(Color(.96,.945,.9))
		var canvas:=HorseCanvas.new()
		canvas.horse=horse
		canvas.game=fixture
		fixture.add_child(canvas)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/medieval-horse-contact.png")
		fixture.PIXELS_PER_UNIT=65
		canvas.horse=dragon
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/medieval-dragon-contact.png")
	fixture.queue_free()
	await process_frame
	print("HORSE CONTACT: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
