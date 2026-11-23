extends BaseButton
## Side elevation of this player's world. Coordinates are metres, positive Y up.
const Targets := preload("res://scripts/war_god_senses.gd")
const SOIL := Color("d6c8ab")
const RIM := Color("665c48")
const WATER := Color("99c7cc")
const WATERLINE := Color("497f86")
const PAPER := Color("faf6e9")
const INK := Color("2d403d")
const NAMES := {"player":"我","painter":"阿靛","priest":"牧师","guard":"战神","traveller":"砾舟","danger":"敌"}
const COLORS := {"player":Color("1b514d"),"painter":Color("485f9b"),"priest":Color("865b29"),"guard":Color("61465f"),"traveller":Color("287363"),"danger":Color("b03526")}

var game
var view := Rect2()
var markers := {}
var threats: Array = []
var _plot := Control.new()
var _ink := Node2D.new()
var _world_id := 0
var _slot := ""
var _revision := -1
var _tip := Vector2.INF
var _cached_area := Rect2()
var _terrain := {}
var _refresh_left := 0.0
var _threat_left := 0.0

func _ready() -> void:
	name="NearbyMinimap"
	tooltip_text="附近地形与角色 · 打开地图"
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	focus_mode=Control.FOCUS_ALL
	clip_contents=true
	_plot.name="MapArea"
	_plot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_plot.clip_contents=true
	add_child(_plot)
	_plot.add_child(_ink)
	_ink.draw.connect(_draw_plot)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var tight:=size.x<180 or size.y<100
	_plot.position=Vector2(3,17 if tight else 24)
	_plot.size=Vector2(maxf(1,size.x-6),maxf(1,size.y-_plot.position.y-(17 if tight else 23)))
	_refresh_left=0.0
	queue_redraw()

func _process(delta:float) -> void:
	if not is_visible_in_tree():return
	if not is_instance_valid(game) or not is_instance_valid(game.medieval_world) or not is_instance_valid(game.player):
		if _world_id!=0:_reset()
		return
	var world=game.medieval_world
	if world.paper_space==null:return
	var slot:=str(game.team_slot.get("slot_id",""))
	if world.get_instance_id()!=_world_id or slot!=_slot:
		_reset()
		_world_id=world.get_instance_id()
		_slot=slot
		_refresh_left=0
	_refresh_left-=delta
	_threat_left-=delta
	if _refresh_left>0:return
	_refresh_left=.10
	var center:Vector2=game.player.position-Vector2(0,.29)
	var tight:=size.x<180 or size.y<100
	var span:=Vector2(34,10.8) if tight else Vector2(48,15)
	view=Rect2(center-span*Vector2(.5,.48),span)
	var space=world.paper_space
	var tip:Vector2=world.terrain.profile[-1]
	if _revision!=space.navigation_revision or tip!=_tip or not _cached_area.encloses(view):
		_cached_area=view.grow(5)
		_terrain=_collect(world,_cached_area)
		_revision=space.navigation_revision
		_tip=tip
	_update_markers(world,center)
	if _threat_left<=0:
		_threat_left=.25
		threats=_nearby_threats(world)
	_ink.queue_redraw()
	queue_redraw()

func _reset() -> void:
	_world_id=0
	_slot=""
	_revision=-1
	_tip=Vector2.INF
	_cached_area=Rect2()
	view=Rect2()
	_terrain.clear()
	markers.clear()
	threats.clear()
	_threat_left=0
	_ink.queue_redraw()
	queue_redraw()

func _update_markers(world,center:Vector2) -> void:
	markers={"player":center}
	var painter=world.get_node_or_null("SandboxCompanion")
	if painter!=null:
		var p:Vector2=painter.observation_target()
		if p.is_finite():markers.painter=p-Vector2(0,.29)
	var priest=world.get_node_or_null("SandboxPriest")
	if priest!=null:markers.priest=Vector2(priest.priest_x,priest.priest_y)
	var traveller=world.get_node_or_null("SandboxAdventurer")
	if traveller!=null and is_instance_valid(traveller.actor):markers.traveller=traveller.actor.player.position-Vector2(0,.29)
	var guard=world.get_node_or_null("SandboxWarGod")
	if guard!=null:
		var p:Vector2=guard.foot_position()
		if p.is_finite():markers.guard=p

func _nearby_threats(world) -> Array:
	var result: Array=[]
	var priest=world.get_node_or_null("SandboxPriest")
	if priest!=null:
		for row in priest.combat_targets(view.get_center(),view.size.length()*.5):
			var pos:=Vector2(row.x,row.y)
			if row.hostile and row.health>0 and view.has_point(pos):
				result.append({"id":row.work_id,"at":pos})
	for entity in world.entities:
		if not is_instance_valid(entity) or entity.kind!="dragon" or not view.grow(1).has_point(entity.position):continue
		var row:=Targets.native_target(world,Targets.NATIVE_PREFIX+entity.entity_id)
		if row.is_empty() or row.health<=0:continue
		var pos:=Vector2(row.at[0],row.at[1])
		if view.has_point(pos):result.append({"id":row.id,"at":pos})
	return result

static func _first_segment(profile:PackedVector2Array,x:float) -> int:
	var lo:=0
	var hi:=profile.size()-1
	while lo<hi:
		var mid:=(lo+hi)/2
		if profile[mid].x<x:lo=mid+1
		else:hi=mid
	return maxi(1,lo)

func _collect(world,area:Rect2) -> Dictionary:
	var space=world.paper_space
	var data:={"soil":[],"water":[],"waterline":[],"rim":[],"platform":[]}
	var profile:PackedVector2Array=world.terrain.profile
	for i in range(_first_segment(profile,area.position.x),profile.size()):
		var a:=profile[i-1]
		var b:=profile[i]
		if a.x>area.end.x:break
		if b.x<area.position.x:continue
		var base:=PackedVector2Array([a,b,Vector2(b.x,world.terrain.BOTTOM),Vector2(a.x,world.terrain.BOTTOM)])
		var box:=Rect2(base[0],Vector2.ZERO).expand(base[1]).expand(base[2]).expand(base[3])
		if box.intersects(area,true):
			var parts: Array=[base]
			for entry in space.nearby(box.intersection(area).grow(.01)):
				if entry.record.mode=="carve":parts=space.subtract(parts,space.cutters_in(entry,Vector2i.ZERO))
			data.soil.append_array(parts)
		if Rect2(a,Vector2.ZERO).expand(b).intersects(area,true):data.rim.append_array(space.legacy_line(a,b))
		for zone in world.terrain.WATER_ZONES:
			var l:=maxf(a.x,zone.left)
			var r:=minf(b.x,zone.right)
			if l>=r:continue
			var yl:=lerpf(a.y,b.y,(l-a.x)/(b.x-a.x))
			var yr:=lerpf(a.y,b.y,(r-a.x)/(b.x-a.x))
			var h:float=zone.height
			if minf(yl,yr)>=h:continue
			if yl>h:l=lerpf(l,r,(h-yl)/(yr-yl));yl=h
			elif yr>h:r=lerpf(l,r,(h-yl)/(yr-yl));yr=h
			var wet:=PackedVector2Array([Vector2(l,h),Vector2(r,h)])
			if yr<h:wet.append(Vector2(r,yr))
			if yl<h:wet.append(Vector2(l,yl))
			data.water.append(wet)
			data.waterline.append([Vector2(l,h),Vector2(r,h)])
	for deck in world.terrain.ROAD_DECKS:
		if Rect2(deck[0],Vector2.ZERO).expand(deck[1]).intersects(area,true):data.platform.append(deck)
	for entry in space.nearby(area):
		var origin:Vector2=space.origin_for(entry.frame)
		match entry.record.mode:
			"rock","carve":
				for part in entry.parts:data.soil.append(Transform2D(0,origin)*part)
				for line in entry.lines:data.rim.append([origin+line[0],origin+line[1]])
			"platform":
				for j in range(1,entry.path.size()):data.platform.append([origin+entry.path[j-1],origin+entry.path[j]])
			"water":
				for part in entry.parts:data.water.append(Transform2D(0,origin)*part)
				for line in entry.lines:data.waterline.append([origin+line[0],origin+line[1]])
	return data

func map_point(p:Vector2) -> Vector2:
	var frac:Vector2=(p-view.position)/view.size
	return Vector2(frac.x,1.0-frac.y)*_plot.size

func _fill(paths:Array,color:Color) -> void:
	for path:PackedVector2Array in paths:
		# The cached pieces are convex. A triangle fan also covers narrow cuts.
		var a:=map_point(path[0])
		for i in range(2,path.size()):
			_ink.draw_primitive(PackedVector2Array([a,map_point(path[i-1]),map_point(path[i])]),PackedColorArray([color]),PackedVector2Array())

func _lines(paths:Array,color:Color,width:float) -> void:
	for pair in paths:_ink.draw_line(map_point(pair[0]),map_point(pair[1]),color,width,true)

func _symbol(canvas:CanvasItem,role:String,p:Vector2,r:float) -> void:
	var color:Color=COLORS[role]
	if role=="player":
		canvas.draw_circle(p,r+1,PAPER,true,-1,true)
		canvas.draw_circle(p,r,color,true,-1,true)
		return
	var vertices:=PackedVector2Array()
	match role:
		"painter":vertices=PackedVector2Array([Vector2(0,-1.2),Vector2(1,0),Vector2(0,1.2),Vector2(-1,0)])
		"priest":vertices=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
		"traveller":vertices=PackedVector2Array([Vector2(-1,-.8),Vector2(.45,-.8),Vector2(1.2,0),Vector2(.45,.8),Vector2(-1,.8)])
		"guard":vertices=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(.9,.3),Vector2(0,1.25),Vector2(-.9,.3)])
		"danger":vertices=PackedVector2Array([Vector2(0,-1.3),Vector2(1.25,1),Vector2(-1.25,1)])
	for i in vertices.size():vertices[i]=p+vertices[i]*r
	canvas.draw_colored_polygon(vertices,color)
	vertices.append(vertices[0])
	canvas.draw_polyline(vertices,PAPER,1.15,true)
	if role=="danger":canvas.draw_line(p-Vector2(0,r*.48),p+Vector2(0,r*.28),PAPER,1.05,true)

func _draw_plot() -> void:
	_ink.draw_rect(Rect2(Vector2.ZERO,_plot.size),Color("f5f2e6"))
	if view.size.x<=0 or _terrain.is_empty():return
	_fill(_terrain.water,WATER)
	_lines(_terrain.waterline,WATERLINE,1.45)
	_fill(_terrain.soil,SOIL)
	_lines(_terrain.rim,RIM,1.25)
	_lines(_terrain.platform,INK,1.8)
	var pins:Array=[]
	var radius:=3.2 if size.x<180 or size.y<100 else 4.2
	var occupied:Array[Vector2]=[]
	for role in ["player","danger","painter","priest","guard","traveller"]:
		if role=="danger":
			for sighting in threats:
				if view.has_point(sighting.at):pins.append(_pin(role,sighting.at,radius+1,occupied))
		elif markers.has(role) and view.has_point(markers[role]):
			pins.append(_pin(role,markers[role],radius,occupied))
	for pin in pins:
		_ink.draw_line(pin.foot,pin.tag,COLORS[pin.role],1.1,true)
		_ink.draw_circle(pin.foot,1.35,COLORS[pin.role])
	for pin in pins:_symbol(_ink,pin.role,pin.tag,pin.radius)

func _pin(role:String,world_at:Vector2,radius:float,occupied:Array[Vector2]) -> Dictionary:
	var foot:=map_point(world_at)
	var margin:=Vector2.ONE*(radius+1.5)
	var best:=foot
	var best_clearance:=-1.0
	for offset:Vector2 in [Vector2.UP,Vector2(1.35,-1),Vector2(-1.35,-1),Vector2(1,1),Vector2(-1,1),Vector2.DOWN,Vector2(1.8,0),Vector2(-1.8,0)]:
		var candidate:Vector2=(foot+offset*(radius+3.5)).clamp(margin,_plot.size-margin)
		var clearance:=INF
		for other in occupied:clearance=minf(clearance,other.distance_to(candidate))
		if clearance>best_clearance:
			best_clearance=clearance
			best=candidate
		if clearance>=radius*2.45:break
	occupied.append(best)
	return {"role":role,"foot":foot,"tag":best,"radius":radius}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),PAPER)
	draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),PaperTheme.TEAL if has_focus() or is_hovered() else Color("a8aa94"),false,1.2)
	var font:=get_theme_default_font()
	var tight:=size.x<180 or size.y<100
	var header_y:=13.0 if tight else 17.0
	draw_string(font,Vector2(7,header_y),"附近地图",HORIZONTAL_ALIGNMENT_LEFT,-1,11 if tight else 13,INK)
	if view.size.x>0:
		var bar:=10.0/view.size.x*_plot.size.x
		var right:=size.x-7
		draw_string(font,Vector2(right-bar-28,header_y),"10米",HORIZONTAL_ALIGNMENT_LEFT,-1,10,PaperTheme.MUTED)
		draw_line(Vector2(right-bar,header_y-3),Vector2(right,header_y-3),PaperTheme.MUTED,1)
		for x:float in [right-bar,right]:draw_line(Vector2(x,header_y-6),Vector2(x,header_y-2),PaperTheme.MUTED,1)
	var row:=["player","painter","priest","guard","traveller"]
	if not threats.is_empty():row.append("danger")
	var advance:float=(size.x-8)/row.size()
	var font_size:=9 if tight else 12
	for i in row.size():
		var role:String=row[i]
		var x:float=7+i*advance
		var y:=size.y-(8 if tight else 11)
		_symbol(self,role,Vector2(x+1,y-1),2.7 if tight else 3.4)
		var label:String=NAMES[role]
		if tight and row.size()>5:label={"painter":"画","priest":"牧","guard":"战","traveller":"砾"}.get(role,label)
		draw_string(font,Vector2(x+5,y+font_size*.33),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,INK)
