extends RefCounted
## Ground and overhead strokes are sampled in world coordinates. Energy is restored on the ground.
const Obstacles:=preload("res://scripts/priest_obstacles.gd")
const Ground:=preload("res://scripts/priest_ground.gd")
static func floor_below(a,x:float,y:float) -> Dictionary:
	var floor_row:={}
	for r in a.world.paper_surfaces(x,y-12,y+.06):
		if r.face=="floor":floor_row=r
	return floor_row

static func clear(a,x:float,y:float,launch:bool=false) -> bool:
	if not Obstacles.permits(a,Vector2(a.beast_x,a.beast_y),Vector2(x,y),0.0,a.face):return false
	var half:float=clampf(a.form.body_bounds.size.x*.25,.12,.55)
	var h:float=maxf(.2,a.form.body_bounds.size.y)
	for sx in [x-half,x,x+half]:
		for r in a.world.paper_surfaces(sx,y+.1,y+h+.08):
			if r.face not in ["ceiling","floor"]:continue
			if launch and r.face=="floor":
				var slope:=Ground.trace(a.world,Vector2(x,a.perch_y),sx)
				if not slope.is_empty() and absf(float(slope.y)-float(r.y))<.025:continue
			return false
	return true

static func step(a,dt:float) -> bool:
	if not a.has_action("fly") or a.phase=="dead": return false
	var flying:bool=a.phase in ["takeoff","fly","land"]
	if not flying:
		a.flight_energy=minf(1.0,a.flight_energy+dt*.065)
		if a.flight_energy<.99 or a.phase in ["eat","pickup","hunt","flee","chase"]:return false
		var under:=floor_below(a,a.beast_x,a.beast_y)
		if under.is_empty():return false
		a.perch_y=under.y
		if not clear(a,a.beast_x,a.beast_y,true):return false
		a.phase="takeoff"
		a.takeoffs+=1
		a.keeper.record_outcome("起飞",a.design.name,"从实际脚面升空",a.work_id)
	a.stride=fmod(a.stride+dt*9.0,TAU)
	a.flight_energy=maxf(0.0,a.flight_energy-dt*.19)
	var height:float=a.design.get("flight_height",1.7)
	var limits:=Ground.bounds(a.world)
	var under:=floor_below(a,a.beast_x,a.beast_y)
	if a.phase=="takeoff":
		var next_y:=move_toward(float(a.beast_y),a.perch_y+height,dt*1.45)
		if clear(a,a.beast_x,next_y,true):
			a.beast_y=next_y
			if next_y>=a.perch_y+height-.04:a.phase="fly"
		else:a.phase="land"
	elif a.phase=="fly":
		var x:=clampf(a.beast_x+a.face*float(a.design.pace)*dt,limits.x+.65,limits.y-.65)
		var landing:=floor_below(a,x,a.beast_y)
		if landing.is_empty() or not clear(a,x,a.beast_y) or absf(x-a.beast_x)<.0001:a.phase="land"
		else:a.beast_x=x
	if a.flight_energy<=.24:a.phase="land"
	if a.phase=="land":
		if under.is_empty():return true
		a.beast_y=move_toward(float(a.beast_y),float(under.y),dt*1.8)
		if absf(a.beast_y-under.y)<.025:
			a.beast_y=under.y
			a.phase="search"
			a.flight_energy=0
			a.landings+=1
			a.keeper.record_outcome("落地",a.design.name,"重新站稳在 "+str(under.work_id),a.work_id)
	return true
