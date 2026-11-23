extends RefCounted
## Track a continuous walking surface, including ink floors above/below the old road.
const PROP_NAMES:={"crate":"木箱","fence":"围栏","barrel":"木桶","bench":"长凳","haystack":"草垛","cart_goods":"货车","wagon":"马车","wall":"墙体","tower":"塔楼","gate":"城门","house":"房屋","oak":"橡树","pine":"松树","orchard_tree":"果树"}

static func obstacle_name(kind:String) -> String:
	return PROP_NAMES.get(kind,"场景实物")

static func bounds(world) -> Vector2:
	var rect: Rect2 = world.paper_motion_bounds()
	return Vector2(rect.position.x,rect.end.x)

static func nearby(world, x: float, y: float, tolerance: float) -> Dictionary:
	var best := {}
	var distance := INF
	for item in world.paper_surfaces(x,y-tolerance,y+tolerance):
		var gap := absf(float(item.y)-y)
		if item.face=="floor" and gap<distance:
			distance=gap
			best=item
	return best

static func trace(world, start: Vector2, x: float) -> Dictionary:
	var point := start
	var limits := bounds(world)
	if x<limits.x or x>limits.y: return {}
	var steps := maxi(1,ceili(absf(x-start.x)/.32))
	if steps>384: return {}
	var floor_row := {}
	for n in steps:
		var next_x := lerpf(start.x,x,float(n+1)/steps)
		floor_row=nearby(world,next_x,point.y,.07+absf(next_x-point.x)*1.6)
		if floor_row.is_empty(): return {}
		point=Vector2(next_x,floor_row.y)
	return floor_row

static func cell(world, point: Vector2) -> Vector2i:
	return world.paper_cell_at(point)

static func room(priest, x: float, y: float) -> bool:
	return room_problem(priest,x,y).is_empty()

static func room_problem(priest, x:float, y:float) -> String:
	var world=priest.world
	var foot:=Vector2(x,y)
	var left:=trace(world,foot,x-.55)
	var right:=trace(world,foot,x+.55)
	if left.is_empty() or right.is_empty() or absf(left.y-right.y)>1.1: return "两侧脚面不连续或坡差太大"
	var a:=Vector2(x-.55,left.y+.08)
	var b:=Vector2(x+.55,right.y+.08)
	var shape:=PackedVector2Array([a,b,b+Vector2.DOWN*.90,a+Vector2.DOWN*.90])
	for row in world.paper_surfaces(x,y+.05,y+1.0):
		if row.face in ["floor","ceiling"]: return "上方平台或洞顶太低"
	for entity in world.entities:
		if entity.alive and absf(entity.position.y-y)<1.5 and absf(entity.position.x-x)<.8 and entity.kind in ["pine","oak","orchard_tree"]: return "树干占了出生点"
	var body := Rect2(Vector2(x-.55,minf(a.y,b.y)),Vector2(1.1,.9+absf(b.y-a.y)))
	for obj in priest.game.objects:
		if obj.get("pen")=="draw_object" or obj.has("built_plan"):
			if body.intersects(priest.game.object_bounds(obj)): return "与现有建筑或笔画实物重叠"
	var blocker:String=world.spawn_shape_blocker(shape)
	if blocker=="terrain":return "地形凸进了出生空间"
	if blocker!="":return obstacle_name(blocker)+"占了出生空间"
	return ""
