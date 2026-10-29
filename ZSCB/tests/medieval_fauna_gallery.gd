extends SceneTree
const Entity := preload("res://scripts/medieval_entity.gd")
const OUT := "/Users/jitian/Documents/ChatGPT/纸上城堡/ZSCB/assets/medieval/fauna/review/"
class Fixture extends Node2D:
	var PIXELS_PER_UNIT := 90.0
	var origin := Vector2.ZERO
	func world_to_screen(point: Vector2) -> Vector2: return origin+Vector2(point.x,-point.y)*PIXELS_PER_UNIT
class Canvas extends Node2D:
	var game
	var animals: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,1000),Color("faf7eb"))
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(25,35),"Generated fauna · 90 px / m · walk or fly / hurt / fall / downed",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("34322c"))
		for row in animals.size():
			var animal=animals[row]
			for frame in 8:
				game.origin=Vector2(100+frame*200,270+row*300)
				animal.position=Vector2.ZERO
				animal.hurt_timer=.3 if frame==4 else 0
				animal.alive=frame<5
				animal.state="fall" if frame==5 else ("dead" if frame>5 else "walk")
				animal.rotation=0
				animal.facing=1
				draw_line(game.origin+Vector2(-90,0),game.origin+Vector2(90,0),Color("d0c8b5"),1)
				animal._draw_raster_actor(self,game,frame,Color.WHITE)
				draw_string(font,game.origin+Vector2(-87,30),"%s %d"%[animal.kind,frame],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("34322c"))
func _init() -> void: call_deferred("run")
func run() -> void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1600,1000)
	var game:=Fixture.new()
	root.add_child(game)
	var canvas:=Canvas.new()
	canvas.game=game
	game.add_child(canvas)
	for kind in ["rabbit","deer","bat"]:
		var animal:=Entity.new()
		animal.setup(kind,Vector2.ZERO,"gallery-"+kind,0)
		canvas.animals.append(animal)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png(OUT+"godot-fauna-frames.png")
	for animal in canvas.animals: animal.free()
	print("FAUNA GALLERY: 24 generated frames rendered by Godot Metal at 90px/m")
	quit()
