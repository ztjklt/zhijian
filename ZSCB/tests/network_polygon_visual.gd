extends SceneTree
class Presentation extends RefCounted:
	var PIXELS_PER_UNIT := 60.0
	var origin := Vector2(832.0922,642.4497)
	func world_to_screen(point:Vector2)->Vector2:return origin+Vector2(point.x,-point.y)*PIXELS_PER_UNIT
class Surface extends Node2D:
	var subject:MedievalEntity
	var presentation:Presentation
	func _draw()->void:subject.draw_entity(self,presentation)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var entity:=MedievalEntity.new();entity.setup("crate",Vector2.ZERO,"precision-crate",0)
	entity.cuts=[{"radius":.8,"side":3.0,"x":.20102405548095703,"y":.800000011920929}]
	entity.rebuild_geometry();entity.freeze=true;root.add_child(entity)
	var presentation:=Presentation.new()
	var found:=false
	for attempt in 400:
		entity.rotation=-.134656+attempt*.000004
		var points:=PackedVector2Array()
		for point in entity.render_polygons[0]:points.append(presentation.world_to_screen(entity.to_global(point)))
		if Geometry2D.triangulate_polygon(points).is_empty():found=true;break
	if not found:print("FAIL: precision fixture did not reach the recorded tangent-cut transform");quit(1);return
	print("REPRO: locally valid cut fails after screen transform at angle=",entity.rotation)
	var surface:=Surface.new();surface.subject=entity;surface.presentation=presentation;root.add_child(surface)
	for i in 5:
		surface.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	surface.queue_free();entity.queue_free();await process_frame
	print("NETWORK POLYGON VISUAL: five real render frames; engine diagnostics checked by runner");quit()
