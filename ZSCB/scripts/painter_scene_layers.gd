extends RefCounted
## Worker-local geometry for a read-only lookup. The SDK receives the chosen
## contours only. Each work and water segment must exist in this team's project.
const Plans = preload("res://scripts/architecture/building_plans.gd")
const Brush = preload("res://scripts/architecture/scenery_brush.gd")
const Frame = preload("res://scripts/painter_scene_frame.gd")
const Space = preload("res://scripts/paper_space.gd")

static func _xy(v:Vector2) -> Array:
	return [v.x,v.y]

static func _mark(game, obj:Dictionary, i:int, master:Dictionary, cutters:Array) -> Dictionary:
	var path:Dictionary=obj.paths[i]
	var local:PackedVector2Array=path.points
	var points:Array=[]
	for p in local:
		points.append(_xy(game.object_point(obj,p)))
	var row:={"index":i,"layer":obj.built_plan.layout.layers[i],"brush":path.get("brush","bold"),
		"pigment":path.get("pigment","inherit"),"points":points}
	var layout:Dictionary=obj.built_plan.layout
	var sources:Array=layout.get("stroke_sources",[])
	if i<sources.size() and sources[i] is Dictionary:
		row.source=sources[i]
	if not master.is_empty() and i<master.paths.size() and i<master.layout.layers.size():
		var original:Array=[]
		for p:Vector2 in master.paths[i].points:
			original.append(_xy(p))
		row.original={"layer":master.layout.layers[i],"points":original}
	var visible:=Brush.after_damage([path],obj.get("damage_cuts",[]))
	if Brush.is_wash(row.brush):
		var faces:Array=[]
		for piece:Dictionary in visible:
			var face:Array=[]
			for p in Brush.wash_polygon(PackedVector2Array(piece.points)):
				face.append(_xy(game.object_point(obj,p)))
			if not face.is_empty():faces.append(face)
		row.faces=faces
	else:
		# Use only the constant-alpha inner strips of the game's actual feathered ribbon.
		# Two rail points per station reproduce the ink-core quadrilateral.
		var strips:Array=[]
		for piece:Dictionary in visible:
			var pts:=PackedVector2Array(piece.points)
			var length:=0.0
			for j in range(1,pts.size()):length+=pts[j-1].distance_to(pts[j])
			if length<.0002:continue
			var ribbon:Dictionary={}
			Brush.Ribbon.bake(ribbon,pts,0,length,row.brush,Brush.UNITS)
			var rails:Array=[]
			for j in range(0,ribbon.vertices.size(),4):
				var left:Vector2=pts[0]+ribbon.vertices[j+1]*Vector2(1,-1)/Brush.UNITS
				var right:Vector2=pts[0]+ribbon.vertices[j+2]*Vector2(1,-1)/Brush.UNITS
				rails.append([_xy(game.object_point(obj,left)),_xy(game.object_point(obj,right))])
			strips.append(rails)
		row.ink_core_strips=strips
	if not cutters.is_empty():
		var pieces:Array=[]
		for j in range(1,local.size()):
			for segment in PaperObjectDamage._remaining(local[j-1],local[j],cutters):
				pieces.append([j-1,_xy(game.object_point(obj,segment[0])),_xy(game.object_point(obj,segment[1]))])
		row.remaining=pieces
	return row

# Sprite bounds follow the posed limbs. Atlas parts are tightly cropped;
# transparent corners are included, so these are conservative ink clearances.
static func _figure(game, visual, body:Vector2) -> Dictionary:
	var faces:Array=[]
	if is_instance_valid(visual):
		for sprite:Sprite2D in visual.find_children("Ink","Sprite2D",true,false):
			if not sprite.is_visible_in_tree() or sprite.texture==null:continue
			var box:=sprite.get_rect()
			var face:Array=[]
			for local:Vector2 in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
				var delta:Vector2=sprite.to_global(local)-visual.global_position
				face.append(_xy(body+delta*Vector2(1,-1)/game.PIXELS_PER_UNIT))
			faces.append(face)
	return {"feet":_xy(body-Vector2(0,.29)),"faces":faces}

static func _display_view(game) -> Dictionary:
	var info:={"ppu":game.PIXELS_PER_UNIT,"viewport":_xy(game.get_viewport_rect().size),
		"player":_figure(game,game.character_visual,game.player.position)}
	var painter=game.medieval_world.get_node_or_null("SandboxCompanion")
	if painter!=null and is_instance_valid(painter.actor):
		var actor=painter.actor
		info.painter=_figure(game,actor.character_visual,actor.player.position)
		info.hand=_xy(actor.hand_world())
		info.current_grip=_xy(Vector2(actor.player.position.x,actor.hand_world().y))
		info.grounded=actor.on_ground and not actor.player.support_bodies().is_empty()
		info.reach=preload("res://scripts/companion_pen_reach.gd").PLAN_RADIUS
	return info

static func snapshot(game,project:Dictionary,extra_work_ids:Array=[]) -> Dictionary:
	var scope:Dictionary=project.get("scope",{})
	if game.team_slot.get("team_id","")=="" or game.team_slot.get("world_id","")=="" or (not scope.is_empty() and (scope.get("team_id")!=game.team_slot.get("team_id") or scope.get("world_id")!=game.team_slot.get("world_id"))):
		return {}
	var ids:Dictionary={}
	for id in project.get("work_ids",[])+extra_work_ids:ids[id]=true
	if not str(project.get("subject","")).is_empty():ids[project.subject]=true
	var works:Array=[]
	for obj:Dictionary in game.objects:
		var id:String=obj.get("work_id","")
		if not ids.has(id) or not obj.has("built_plan") or obj.get("hp",1)<=0:continue
		var meta:Dictionary=obj.built_plan
		if not meta.has("layout") or meta.layout.get("layers",[]).size()!=obj.paths.size():continue
		var owner:String=meta.get("owner","")
		var plan_id:=int(meta.get("id",-1))
		var master:=Plans._source(game,owner,plan_id)
		var layers:Array=[]
		var cutters:Array=[]
		var cuts:Array=obj.get("damage_cuts",[])
		for j in cuts.size():cutters.append(PaperObjectDamage._cutter(cuts[j],j))
		for i in obj.paths.size():layers.append(_mark(game,obj,i,master,cutters))
		var fixtures:Array=[]
		for station:Dictionary in meta.layout.get("stations",[]):
			for label in station.get("fixture_layers",[]):
				if not fixtures.has(label):fixtures.append(label)
		var access_clearance:Array=[]
		for access in meta.layout.access:
			var at:Vector2=game.object_point(obj,Plans.point(meta.offset)+Plans.point(access))
			var half:=.73 if Plans.paired_station(meta.layout,access[0]) else .40
			access_clearance.append([at.x-half,at.y+.06,at.x+half,at.y+1.50])
		works.append({"id":id,"name":obj.get("name",""),"plan_id":plan_id,"plan_owner":owner,
			"origin":_xy(game.object_point(obj,Plans.point(meta.offset))),"angle":obj.get("angle",0.0),
			"fixture_layers":fixtures,"layers":layers,"access_clearance":access_clearance})
	if works.is_empty():return {}
	var stations:=Frame._usable_stations(game,ids)
	for work:Dictionary in works:
		work.stands=[]
		for station:Dictionary in stations:
			if station.work_id==work.id:
				var row:={"kind":station.kind,"use":station.use,"feet":_xy(station.at)}
				if not work.stands.has(row):work.stands.append(row)
	var water:Array=[]
	var space=game.medieval_world.paper_space
	for id in ids:
		var entry:Dictionary=space.entries.get(id,{})
		if entry.is_empty() or entry.record.mode!="water" or entry.parts.is_empty():continue
		var rims:Array=[]
		for rim:Rect2 in Frame._visible_rims(entry):rims.append([_xy(rim.position),_xy(rim.end)])
		var fill:Array=[]
		var origin:=Space.origin_for(entry.frame)
		for part:PackedVector2Array in entry.parts:
			var polygon:Array=[]
			for p in part:polygon.append(_xy(origin+p))
			fill.append(polygon)
		water.append({"id":id,"rims":rims,"fill":fill})
	return {"project_id":project.get("project_id",""),"works":works,"water":water,"view":_display_view(game)}
